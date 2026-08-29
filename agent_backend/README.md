# Welwi Agent Backend (ADK + Gemini)

Cloud counterpart to the Flutter app: a multi-agent [ADK](https://google.github.io/adk-docs/)
service that acts on the user's notes and real Google Calendar instead of just
talking about them. Built for the *All Things Agentic* hackathon (Collaborative
Partner track): every action is **proposed** by the agent and **confirmed** by
the user before it touches real data — that propose/confirm pair, plus the
feedback log, is the "guided interaction with adaptive feedback" story.

## Architecture

```mermaid
flowchart TB
    subgraph Client["Flutter App"]
        UI[Chat / Action-card UI]
        MIC["Mic + camera\n(voice companion mode)"]
    end

    subgraph GCP["Google Cloud"]
        GW["Cloud Run gateway (FastAPI)\nverifies Firebase Auth ID token\nSSE for text, WebSocket relay for voice"]
        AE["Vertex AI Agent Engine"]
        FS[(Firestore\nnotes / feedback log)]
        CAL[[Google Calendar API]]
        SCHED["Cloud Scheduler / Tasks\n(fires at event start time)"]
        FCM[[Firebase Cloud Messaging]]

        subgraph TextApp["welwi_agent (text, turn-based)"]
            ORCH[Orchestrator]
            NOTE[note_agent]
            CALA[calendar_agent]
            IRIS["iris_agent\n(\"Iris\" - Welwi's eyes)"]
            ORCH --> NOTE
            ORCH --> CALA
            ORCH --> IRIS
        end

        subgraph VoiceApp["welwi_voice_agent (Gemini Live, standing session)"]
            VOICE["welwi_voice_companion\naudio in/out + live video\nsame propose/confirm tools"]
        end

        AE --- TextApp
        AE --- VoiceApp
    end

    UI -- "text / image + Firebase ID token" --> GW
    MIC -- "audio + camera stream" --> GW
    GW -- "query() / bidi stream (service account)" --> AE
    NOTE <--> FS
    CALA <--> FS
    CALA --> CAL
    IRIS -- "check for duplicates" --> NOTE
    IRIS -- "check for duplicates" --> CALA
    IRIS --> FS
    IRIS --> CAL
    VOICE <--> FS
    VOICE --> CAL
    CALA -- "on event created" --> SCHED
    SCHED --> FCM
    FCM -- "wake app, wake_reason=reminder" --> MIC
    AE -- "action cards / speech" --> GW --> UI
```

Two deployable Cloud services satisfy the "at least one Google Cloud
infrastructure service" requirement twice over, and for a real reason, not
padding:

- **Vertex AI Agent Engine** hosts the ADK agent itself — managed autoscaling
  and a built-in `VertexAiSessionService` (multi-turn memory with zero
  hand-rolled session infra).
- **Cloud Run** hosts a thin FastAPI gateway that verifies the mobile client's
  Firebase Auth token and forwards to Agent Engine using a server-side service
  account. The mobile app never holds a GCP credential — that's the security
  point judges are scoring under "Architectural Discipline."
- **Firestore** is the durable store for notes and the accept/reject feedback
  log (Agent Engine's session service handles in-conversation memory, not
  cross-session user data).

### Fast path if you're short on time

Skip the gateway and Agent Engine for the first working demo: run
`adk api_server welwi_agent` locally, or deploy that same FastAPI app straight
to Cloud Run (`gcloud run deploy --source .`). It already speaks REST/SSE, so
Flutter can hit it directly. Upgrade to the Agent Engine + gateway split above
once the core flow (propose -> confirm -> Calendar/Firestore write) works
end-to-end — it's an infra swap, not an agent-code rewrite.

## Agents

Two separate ADK apps, one Firestore/Calendar backing them both:

| App | Agent | Role |
|---|---|---|
| `welwi_agent` (text, turn-based) | `welwi_orchestrator` (root) | Routes each turn to the right sub-agent. No tools of its own. |
| | `note_agent` | `propose_note` -> (user confirms) -> `save_note`; `list_notes` for recall. |
| | `calendar_agent` | Resolves relative dates against the real clock, `propose_calendar_event` -> `create_calendar_event` on the user's real Google Calendar; `list_upcoming_events`. |
| | **`iris_agent`** ("Iris" — Welwi's eyes) | Takes a photo (flyer, appointment card, whiteboard) and calls `propose_note`/`propose_calendar_event` directly — no "let me describe what I see" detour. First calls `list_notes`/`list_upcoming_events` (the same tools `note_agent`/`calendar_agent` own) to check for an existing near-duplicate before proposing — genuine coordination with the other agents, not just shared Firestore underneath. |
| `welwi_voice_agent` (Gemini Live, standing session) | `welwi_voice_companion` | Same propose/confirm/list/feedback tools, held flat on one agent (see the docstring in `welwi_voice_agent/agent.py` for why no sub-agent transfer here — mid-stream model handoffs cost audio continuity). Additionally narrates a live camera feed and cross-references a saved shopping-list note via `get_shopping_list`. Same eyes-of-the-user role as Iris, continuous instead of snapshot — see that file's docstring for the relationship. |

"Iris" is the internal/architectural name for the vision capability — it
appears in the trace logs (`[iris_agent] calls: propose_note(...)`) and this
README, not something the user hears announced. The user only ever hears one
companion, "Welwi," regardless of which underlying agent handled the turn —
splitting that into two spoken personas would fragment the product identity
mid-demo.

Every propose/confirm or propose/discard pair (from either app) calls
`record_action_feedback`, logged to Firestore's `agent_feedback` collection.

### The voice companion — what it's actually for

Not a novelty. It's the answer to "an agent that guides you to action, not a
chatbot" pushed to its natural conclusion:

- **It speaks unprompted.** When a Cloud Scheduler job fires at an event's
  start time, it pushes an FCM notification that wakes the app straight into
  a `welwi_voice_agent` session with `wake_reason="reminder"` — the companion
  opens by saying the user's name and what's happening, not a text banner the
  user has to read and dismiss. (The "call his name until he answers"
  escalation is the notification layer re-firing/raising volume on
  no-response, not agent logic — see TODO.)
- **It sees while it talks.** With the camera on, the same session gets live
  video frames, so "what's on the shelf in front of me" and "do I still need
  eggs" are answered against both what it's looking at and the saved
  `get_shopping_list` note, in one continuous conversation — not a separate
  photo-snap-and-wait step like Iris's (`iris_agent`) flow.
- **Try it today**, no Flutter integration needed yet: `adk web` from
  `agent_backend/`, pick `welwi_voice_agent` from the app dropdown, and use
  its built-in mic/camera toggle. This is genuinely the fastest way to prove
  the Live API story works before wiring the phone app to it.

**Verified with real video frame streaming**, not just construction —
`voice_camera_test.py` drives `run_live()` directly (same mechanism `adk web`'s
browser toggle and a future Flutter client both use), streaming synthetic
camera frames into a real Live session and checking the transcribed spoken
response actually describes them. Confirmed working:
`"I see the word MILK on a plain background."`

**Important finding for the Flutter camera client**: a single still frame is
*not* enough — sending one frame got "I'm not seeing anything, just a black
screen." Only a short burst of continuous frames (tested: 5 frames @ 2fps)
registered as video. Build the camera client as an actual frame-grab loop
(1-2fps is plenty for a companion narrating what it sees), not a
snap-a-photo-and-send call.

### Deploying the voice agent to production — RESOLVED, working on Cloud Run

Both `welwi_agent` and `welwi_voice_agent` are deployed to **Cloud Run**
(`adk deploy cloud_run`), separate services, separate from Agent Engine:

- `welwi-text-agent`: https://welwi-text-agent-549628512893.us-central1.run.app
  — **fully verified working**. Real conversation over its REST API, real
  Gemini 3.6 via Vertex, correct routing across all three sub-agents (verified
  individually: note_agent, calendar_agent, iris_agent), correct
  propose/confirm, real Firestore. ~10-14s/turn, faster and far more
  consistent than local dev's 38-102s range, since Cloud Run's calls to
  Gemini never leave Google's network.
- `welwi-voice-agent`: https://welwi-voice-agent-549628512893.us-central1.run.app
  — **fully verified working**, including real streamed video. A test client
  streamed 10 synthetic camera frames over the real `/run_live` WebSocket;
  the deployed agent replied (transcribed, real spoken response): *"I see
  butter. Are you starting your shopping now? I can pull up your list if
  that's helpful."* — correctly reading the frame content AND proactively
  offering the shopping-companion behavior it was designed for.

**The path here, for anyone touching this again** — this took real
debugging, not luck, and the root cause was subtle enough to be worth
recording precisely:

1. Vertex AI's Live/bidi path rejected the connection ("Publisher model ...
   was not found") under every non-interactive identity tried — Agent
   Engine's EXPERIMENTAL bidi mode, and initially Cloud Run's native
   `/run_live` too — while the identical call succeeded locally under
   interactive user credentials. Ruling this out on two unrelated Google
   Cloud products, with both the preview and GA Live models, looked like a
   Vertex-side gap.
2. It wasn't a Vertex entitlement issue at all. The hackathon's own rules
   allow Gemini access via *either* the Gemini API or Vertex AI — so the fix
   was to run the voice agent over the plain **Gemini Developer API**
   (`GOOGLE_API_KEY`, stored in **Secret Manager**, not a plain env var)
   instead of Vertex, which is what already worked locally.
3. That still failed identically on Cloud Run even with
   `GOOGLE_GENAI_USE_VERTEXAI=FALSE` explicitly set — because `adk deploy
   cloud_run` unconditionally bakes `ENV GOOGLE_GENAI_USE_ENTERPRISE=1` into
   every generated Dockerfile, and google-genai's `Client()` gives
   `ENTERPRISE` priority over `VERTEXAI` when both are present. A bare
   `Client()` call silently ends up in Vertex mode on Cloud Run regardless of
   `GOOGLE_GENAI_USE_VERTEXAI`. Found by adding a diagnostic print inside the
   client-resolution property and reading it back via `gcloud logging read`
   — same technique that cracked the text agent's location bug earlier.
   Fixed for good in `welwi_agent/config.py`: pass `enterprise=False`
   explicitly to `Client(...)` rather than relying on env-var
   auto-detection, since explicit constructor arguments always win over
   env vars in the SDK's own resolution order.
4. Once the connection worked, a single still frame still wasn't enough to
   register as video (same finding as the very first local test) — 10 frames
   over ~10s, not 5 over 2.5s, was what worked reliably on Cloud Run's
   network path specifically.

Two more subtle deploy-mechanics bugs, worth knowing if you touch this
again: `adk deploy cloud_run` copies exactly one folder per deploy (not a
multi-app parent directory like `adk web` accepts locally), and
`requirements.txt` must live inside that exact folder, not a sibling.
`welwi_voice_agent`'s dependency on `welwi_agent`'s tools required vendoring
a copy of `welwi_agent` inside the voice agent's deploy folder with its
imports rewritten to relative (`.welwi_agent.config` instead of
`welwi_agent.config`) — the tracked source in `welwi_voice_agent/agent.py`
is untouched; only the disposable staging copy differs. All of this —
staging, the import rewrite, both `adk deploy cloud_run` calls with the
correct env vars/secrets — is scripted in `deploy_cloud_run.ps1`, so a
redeploy is one command, not a sequence to remember:

```powershell
cd agent_backend
.\deploy_cloud_run.ps1
```

## Local setup

```bash
cd agent_backend
python -m venv .venv && source .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
cp .env.example .env   # fill in your project id, model id, calendar token path
```

**Firestore**: `gcloud firestore databases create --location=$GOOGLE_CLOUD_LOCATION`
(Native mode) in your project if you don't already have one.

**Google Calendar OAuth token** (one-time, local):

```bash
python - <<'PY'
from google_auth_oauthlib.flow import InstalledAppFlow
flow = InstalledAppFlow.from_client_secrets_file(
    "client_secret.json",  # from Google Cloud Console > APIs & Services > Credentials
    ["https://www.googleapis.com/auth/calendar.events"],
)
creds = flow.run_local_server(port=0)
open("secrets/calendar_token.json", "w").write(creds.to_json())
PY
```

**GCP auth for Firestore** (only needed once Firestore tools are exercised;
routing/tool-selection works without it): `gcloud auth application-default
login`, then set `GOOGLE_CLOUD_PROJECT` in `.env` to a project with Firestore
enabled.

**Run it**:

```bash
adk web        # dev UI, app dropdown lets you pick welwi_agent (text) or
                # welwi_voice_agent (mic/camera Live session), great for demoing both
# or, text app only:
adk run welwi_agent
```

**Before every deploy, run the integration check**:

```bash
pip install -r requirements-dev.txt   # adds Pillow, for the vision scenarios
python demo_script.py
```

This runs 6 scenarios against the **real Gemini API** (your `GOOGLE_API_KEY`),
with an in-memory fake standing in for Firestore/Calendar (`testing/fakes.py`)
so it needs zero GCP setup — it verifies agent logic and routing, not cloud
plumbing. Confirmed passing end-to-end on `gemini-3.6-flash`: note
propose/confirm, note propose/reject, calendar propose/confirm/list, calendar
propose/reject, and — the best demo moment — a synthetic photo of a flyer
correctly OCR'd into a proposed calendar event, and a photo of a sticky note
into a proposed note. Each scenario prints a full transcript, useful as a
rehearsal script before recording the demo video.

One thing this exercise surfaced and fixed: Gemini calls had no client-side
timeout, so a single stalled connection could hang a turn (voice or text)
forever. `welwi_agent/callbacks.py`'s `bound_request_timeout` now caps every
call at 60s with bounded retries, wired via `before_model_callback` on all
five agents.

## Performance

Three levers, each verified rather than assumed:

- **Thinking level matched to task complexity** (`welwi_agent/config.py`'s
  `thinking()` helper, Gemini 3.x's `thinking_level`). Found by inspecting a
  trace: the root orchestrator burned ~400 thought tokens to decide "transfer
  to note_agent" — a 3-way label pick against explicit routing rules, not a
  reasoning task. Root + `note_agent` (extract a field, call one tool) run at
  `MINIMAL`; `calendar_agent` (date math) and `iris_agent` (image
  understanding + duplicate-check judgment) run at `LOW`. This cuts token
  usage/cost per call for certain; wall-clock latency in this specific setup
  is dominated by something else (see below), so don't expect a dramatic
  speed difference from this alone.
- **Context caching for local dev** (`welwi_agent/agent.py`'s `app` export,
  `ContextCacheConfig`). Every test run this session printed a warning that
  agent transfers re-send the whole prompt uncached — `adk web`/`adk run`
  check for an `app` variable (not `root_agent`) to enable this, so it's
  wired now. Caching only kicks in from a session's 2nd turn once the
  cacheable prefix clears Gemini 3's 4096-token minimum. **Local/CLI-serving
  only** — the currently installed Agent Engine deploy SDK builds its Runner
  directly from `agent=root_agent`, bypassing this App wrapper, so it doesn't
  yet reach the production deployment.
- **Cold-start elimination for the actual demo** (`deploy_agent_engine.py`'s
  `WELWI_MIN_INSTANCES` env var, default 0). A cold Agent Engine instance
  adds real latency to the first request after idle — bad if a judge's first
  interaction is that request. Left at 0 (autoscale-to-zero) day-to-day since
  `min_instances=1` bills continuously even at zero traffic; set
  `WELWI_MIN_INSTANCES=1` and redeploy shortly before the actual demo/judging
  window, then back to 0 after.

**What actually dominates latency here, measured, not guessed**: ran the
identical 2-turn note scenario three times back-to-back locally —
38s / 60s / 102s. That 2.7x spread has nothing to do with thinking tokens or
caching; it's network variance between this dev sandbox and Vertex.
Production is a different story — Agent Engine's calls to Gemini happen
entirely inside Google's network, never touching this sandbox's connection —
confirmed with a real deployed production timing test: 23s + 48s for the
same 2-turn flow. If you're chasing latency further, profile against the
*deployed* resource (`prod_test.py`, which now prints per-turn timing), not
local runs — local numbers include noise that's structurally absent in
production.

## Deploy

**Live right now**, verified end-to-end in real production (real Gemini 3.6 via
Vertex, real Firestore write, real IAM):

- Project: `welwi-agent-hack` (dedicated — kept separate from any other GCP
  project so hackathon resources/billing don't commingle).
- Resource: `projects/549628512893/locations/us-central1/reasoningEngines/2331955860617560064`
- Verify it yourself: `python prod_test.py` (talks to the deployed resource
  directly, not local — real Gemini + real Firestore).

### One-time project setup (already done for `welwi-agent-hack`, reproduce for your own)

```bash
gcloud projects create YOUR_PROJECT_ID --name="Welwi Agent"
gcloud billing projects link YOUR_PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT
gcloud services enable aiplatform.googleapis.com firestore.googleapis.com \
    run.googleapis.com calendar-json.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com iam.googleapis.com iamcredentials.googleapis.com \
    --project=YOUR_PROJECT_ID
gcloud config set project YOUR_PROJECT_ID

# Firestore (native mode) + the composite index notes_tools.py's queries need
# (where user_id == X, order_by saved_at desc — Firestore 400s without this):
gcloud firestore databases create --location=us-central1
gcloud firestore indexes composite create --collection-group=notes \
    --field-config=field-path=user_id,order=ascending \
    --field-config=field-path=saved_at,order=descending

# Staging bucket for Agent Engine deploys (name must match {project}-agent-staging,
# see deploy_agent_engine.py):
gcloud storage buckets create gs://YOUR_PROJECT_ID-agent-staging --location=us-central1

# ADC — separate from `gcloud auth login`; the Python SDKs need this too:
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

### Deploy the agent

```bash
python deploy_agent_engine.py
```

The *first* deploy in a project auto-creates Agent Engine's own service agent
(`service-{PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com`) — it
doesn't exist beforehand, so granting it Firestore access has to happen
*after*:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:service-PROJECT_NUMBER@gcp-sa-aiplatform-re.iam.gserviceaccount.com" \
    --role="roles/datastore.user" --condition=None
```

### Two real gotchas hit getting this working (both fixed in `welwi_agent/config.py`)

1. **`GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_LOCATION` are reserved** in Agent
   Engine's `env_vars` — passing them 400s the whole deploy. Agent Engine sets
   them itself, pinned to wherever you deployed the resource.
2. **That pinned location broke model calls.** `gemini-3.6-flash` (like many
   new Gemini releases) is only on Vertex AI's `global` endpoint at launch,
   not yet in regional endpoints like `us-central1` — but the reserved
   `GOOGLE_CLOUD_LOCATION` above forces the *agent's* region onto model calls
   too by default, causing a 404. Fixed by giving the model its own client via
   a small `Gemini` subclass (`_EnvAwareGemini`, ADK's own documented pattern
   for this) that pins `location="global"` specifically for the model calls,
   independent of the agent's deploy region. A second layer to this: Agent
   Engine also normalizes `env_vars` values to `"1"`/`"0"`, not the
   `"TRUE"`/`"FALSE"` strings you set — a strict string-equality check on that
   silently fails, so the check is a case-insensitive membership test now.
   Found by adding a diagnostic `print()` inside the client-resolution
   property and reading it back via `gcloud logging read`, since that's the
   only way to see what a deployed agent's process actually observes.

### Gateway (not yet deployed)

- `gcloud run deploy welwi-gateway --source ./gateway --region $GOOGLE_CLOUD_LOCATION`
  (gateway service not scaffolded yet — see TODO below).

## TODO

- [ ] `gateway/` FastAPI service: verify Firebase ID token, call
      `remote_app.stream_query(...)` on the deployed Agent Engine resource for
      `welwi_agent`, and relay the `/run_live` WebSocket for `welwi_voice_agent`
      (Flutter can't hold a GCP service-account credential itself — the
      gateway is what lets a mobile client speak to a Live-API session safely).
- [ ] Flutter, text path: replace the on-device `GemmaInferenceService` call
      sites with a client for the gateway's `/chat` endpoint; render
      `awaiting_confirmation` tool results as action cards with
      Confirm/Edit/Discard buttons instead of plain chat bubbles.
- [ ] Flutter, voice path: mic capture + (optional) camera frame streaming
      into the gateway's WebSocket, playback of returned audio chunks. This
      replaces `audio_record_service.dart`/`speech_service.dart`'s on-device
      STT/TTS with the Live API doing both natively.
- [ ] Reminder pipeline: on `create_calendar_event`, schedule a Cloud
      Scheduler (or Cloud Tasks with an ETA) job for the event's start time
      that sends an FCM data message; app foreground/wake handler opens a
      `welwi_voice_agent` session with `wake_reason="reminder"` +
      `reminder_title` in session state, and re-sends the notification on an
      increasing interval until the user opens it (the "keeps saying your
      name until you answer" behavior) — client-side escalation logic, not
      agent code.
- [ ] Swap `list_notes`' substring search for a Vertex AI Vector Search /
      Firestore vector index if there's time — direct upgrade from the old
      on-device SQLite RAG story, same UX.
