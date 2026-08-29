# Welwi — a voice agent that acts, not just describes

Millions of visually impaired people already have AI that lets them *see* —
tools that describe a room or read a sign. Welwi is built for what comes
after that: a **multi-agent companion** that manages your day *because of*
what it sees and hears, not just narrates it. Open the app and it's already
listening — no login, no menu, nothing to tap. You talk, it takes real
action: notes saved, calendar events created and rescheduled, a flyer on a
wall turned into a real calendar entry, and — unprompted — a spoken reminder
when something's about to start.

Built for the **All Things Agentic** hackathon on **Gemini 3.5+** (live and
text), orchestrated with **Google's Agent Development Kit (ADK)**, deployed
on **Cloud Run**, backed by **Firestore**.

## What it actually does (all live, all verified against production)

- **Zero-tap voice companion** — the Flutter app opens straight into a live
  Gemini session (`gemini-3.1-flash-live-preview`); no button ever required
  to start talking.
- **Notes** — propose → confirm → save, list, edit, delete. Every write is
  proposed and confirmed out loud before it happens.
- **Calendar** — same propose/confirm pattern for creating, rescheduling, and
  deleting events; "what's on my calendar today" reads back the whole day.
- **Vision, on demand** — the camera is off by default; the agent turns it on
  itself only when asked to look at something, and off again once it's done.
  Point it at an event poster and ask it to add the event — it reads the
  flyer and proposes the calendar entry directly.
- **Proactive reminders** — when a scheduled event's time arrives, the agent
  speaks up on its own, in its own real synthesized voice, without being
  asked — not a push notification.
- **A real conversation, not a script** — natural interruption handling
  (barge in and it actually stops and listens), a warm/funny persona, and
  automatic reconnection if the underlying Live session ends mid-conversation.

## Architecture

```
Flutter app (Android)
  └─ gemini-3.1-flash-live-preview, streamed over WebSocket
        │
        ▼
Cloud Run: welwi-voice-agent  (ADK, single flat agent, full toolbelt)
Cloud Run: welwi-text-agent   (ADK, orchestrator + note/calendar/vision sub-agents)
        │
        ▼
Firestore (notes, events, feedback log)
```

Both services are deployed with `adk deploy cloud_run` and made publicly
invokable — a deliberate, documented demo-scope decision (see
`agent_backend/README.md` for the tradeoff) since a mobile client can't carry
a `gcloud`-style IAM identity token. No GCP credentials ever live in the app;
the service account stays server-side.

Full backend architecture, the multi-agent breakdown, and the debugging
history behind the non-obvious fixes live in
[`agent_backend/README.md`](agent_backend/README.md).

## Reproducible Testing

Two independent ways to verify this actually works — you don't need both.

### Option A — run the real app

```bash
flutter pub get
flutter devices        # confirm your target device/emulator shows up
flutter run            # builds, installs, and launches
```

The app opens directly into the live companion — no login, no setup screen.
Try, in order:

1. Say **"what's on my calendar today?"** — it reads back today's schedule.
2. Say **"note down that my wifi password is Sunflower42"**, then confirm
   with **"yes"** — the agent proposes it back to you before saving.
3. Ask **"what's on my grocery list?"**, then say **"add apples to it"** —
   the note updates in the same conversation.
5. Hold the phone up to any printed text with a date on it (a flyer, an
   appointment card) and say **"add this to my calendar"** — the camera
   turns on by itself, reads it, and proposes the event.
6. Tap five times anywhere on the screen to open the plain data view
   (Notes/Calendar lists) and confirm the note/event from steps 2–5 actually
   landed there.

### Option B — hit the deployed backend directly, no app required

```bash
cd agent_backend
python -m venv .venv && .venv\Scripts\activate   # or source .venv/bin/activate
pip install -r requirements.txt
python cloud_run_full_test.py          # text agent: note + vision scenarios
python cloud_run_voice_camera_test.py  # voice agent: live video streaming
```

These scripts talk to the actual deployed Cloud Run services
(`welwi-text-agent`, `welwi-voice-agent`) — not local mocks — and print the
full event trace, including tool calls and the agent's real spoken/written
responses. See `agent_backend/README.md`'s **Local setup** section for the
fully-offline variant (`demo_script.py`, real Gemini API + in-memory fakes,
zero GCP setup required) if you'd rather not touch live cloud data.

## Known, documented limitations

- The Cloud Run services are public for this demo (see above) — a real
  deployment would sit them behind Firebase Auth or a gateway.
- Calendar is Firestore-backed, not the real Google Calendar API — that
  integration exists in code (`calendar_tools.py`'s docstring explains why)
  but the OAuth token was never minted in time; switching back is a config
  change, not a rewrite.

## Repo layout

- `lib/` — the Flutter app. Entry point: `lib/screens/welwi/cloud_voice_screen.dart`.
- `agent_backend/` — the ADK multi-agent backend, deployment scripts, and
  test suite. See its own README for the full architecture, agent roster,
  and deployment debugging history.
