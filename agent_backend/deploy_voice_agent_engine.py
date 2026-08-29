"""Deploy welwi_voice_agent (the Gemini Live companion) to Vertex AI Agent
Engine with bidirectional streaming enabled.

Correction to earlier assumption: the older `vertexai.agent_engines.create()`
path (used for the text agent, deploy_agent_engine.py) does NOT support bidi
streaming in this SDK version — confirmed directly ("Bidi stream API mode is
not supported yet in Vertex SDK" at deploy time). But there IS a working path
in the SAME installed SDK: `agentplatform.Client(...).agent_engines.create()`
with `config.agent_server_mode = AgentServerMode.EXPERIMENTAL`. Found by
inspecting `agentplatform._genai.types.common.AgentEngineConfig` directly,
not by guessing from docs — `vertexai.Client` also exposes this but is
deprecated in favor of `agentplatform.Client` (same rebrand as everything
else this project has hit: Vertex AI -> Gemini Enterprise Agent Platform).

Run: .venv/Scripts/python.exe deploy_voice_agent_engine.py

STATUS as of 2026-08-27: deploys successfully, but the actual Live model
connection consistently fails with "Publisher model ... was not found" —
tried and ruled out, one redeploy each: wrong wrapper (fixed — must be
AdkApp, not a bare Agent), wrong `streaming_mode` casing in the client
request (fixed — 'bidi' not 'BIDI'), the specific model (both
gemini-3.1-flash-live-preview and the GA gemini-live-2.5-flash fail
identically), and ambient location resolution (explicitly pinning
project+location in welwi_agent/config.py's `_EnvAwareGeminiLive` made no
difference). The agent itself DOES start (its before_agent_callback fires,
confirmed in the raw event stream) — only the model's own `.connect()` call
fails, every time, regardless of what's changed on our end. That rules out a
client-side bug in this codebase. This matches an unresolved production
report on Google's own ADK forum (Nov 2025) about the same feature. Treat
`agent_server_mode=EXPERIMENTAL` as not currently reliable enough to depend
on for a deadline — see agent_backend/README.md for the recommended
alternative (Cloud Run via `adk deploy cloud_run`, ADK's stable path for
serving a live-streaming agent). Kept in the repo as tested, working
DEPLOYMENT code (the failure is in Google's platform, not this script) in
case Google fixes the underlying issue before you need it.
"""
import os

from dotenv import load_dotenv

load_dotenv()

import agentplatform
from agentplatform._genai.types.common import AgentEngineConfig, AgentServerMode
from vertexai.preview import reasoning_engines

from welwi_voice_agent.agent import root_agent

PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
STAGING_BUCKET = f"gs://{PROJECT}-agent-staging"

client = agentplatform.Client(project=PROJECT, location=LOCATION)

# Must be the AdkApp-wrapped agent, not the raw Agent — confirmed by testing:
# passing agent=root_agent directly deployed "successfully" but the server
# registered zero class methods ("bidi_stream_query not found. Available
# methods are: []"), because class-method autogeneration inspects the
# wrapper's exposed methods (stream_query, bidi_stream_query, etc.), not a
# bare Agent, which has none of those.
adk_app = reasoning_engines.AdkApp(agent=root_agent, enable_tracing=True)

remote_app = client.agent_engines.create(
    agent=adk_app,
    config=AgentEngineConfig(
        staging_bucket=STAGING_BUCKET,
        requirements="requirements.txt",
        extra_packages=["./welwi_agent", "./welwi_voice_agent"],
        display_name="welwi-voice-companion",
        agent_server_mode=AgentServerMode.EXPERIMENTAL,
        env_vars={
            "GOOGLE_GENAI_USE_VERTEXAI": "TRUE",
            "WELWI_LIVE_MODEL": os.environ.get("WELWI_LIVE_MODEL", "gemini-3.1-flash-live-preview"),
            "FIRESTORE_DATABASE": os.environ.get("FIRESTORE_DATABASE", "(default)"),
        },
    ),
)

print("Deployed. Resource name:")
print(remote_app.api_resource.name)
