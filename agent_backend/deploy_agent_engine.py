"""One-off script: deploy the Welwi ADK agent to Vertex AI Agent Engine.

Agent Engine gives us, for free, exactly what the judging criteria reward:
managed autoscaling, a persistent VertexAiSessionService (multi-turn memory
without hand-rolled infra), and a first-party "Google Cloud infrastructure"
story. Run once per deploy:

    python deploy_agent_engine.py

Requires: `gcloud auth application-default login`, and GOOGLE_CLOUD_PROJECT /
GOOGLE_CLOUD_LOCATION set (see .env.example). You also need a GCS staging
bucket — create one if you don't have it:

    gsutil mb -l $GOOGLE_CLOUD_LOCATION gs://$GOOGLE_CLOUD_PROJECT-agent-staging

The exact Agent Engine SDK surface moves fast; if `vertexai.agent_engines`
has been renamed/relocated by the time you run this, check
https://docs.cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/quickstart-adk
and adjust the two calls below accordingly — the ADK agent code itself
(welwi_agent/) does not change.
"""
import os

from dotenv import load_dotenv

load_dotenv()

import vertexai
from vertexai import agent_engines
from vertexai.preview import reasoning_engines

from welwi_agent.agent import root_agent

PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
STAGING_BUCKET = f"gs://{PROJECT}-agent-staging"

vertexai.init(project=PROJECT, location=LOCATION, staging_bucket=STAGING_BUCKET)

app = reasoning_engines.AdkApp(agent=root_agent, enable_tracing=True)

# min_instances keeps that many container instances warm at all times —
# eliminates cold-start latency (real, can add several seconds to the FIRST
# request after idle) at the cost of continuous billing for the warm
# instance(s), even with zero traffic. Left at 0 (autoscale-to-zero, Agent
# Engine's default) day-to-day; set WELWI_MIN_INSTANCES=1 and redeploy right
# before the actual demo/judging window, then back to 0 after.
MIN_INSTANCES = int(os.environ.get("WELWI_MIN_INSTANCES", "0"))

remote_app = agent_engines.create(
    app,
    requirements="requirements.txt",
    extra_packages=["./welwi_agent"],
    display_name="welwi-orchestrator",
    min_instances=MIN_INSTANCES,
    # The deployed runtime uses Vertex-hosted Gemini under Agent Engine's own
    # service account — no API key baked into the cloud environment, unlike
    # local dev (which uses GOOGLE_API_KEY for a fast feedback loop).
    # GOOGLE_CLOUD_PROJECT / GOOGLE_CLOUD_LOCATION are reserved names Agent
    # Engine sets itself — don't pass them here (it 400s if you do).
    env_vars={
        "GOOGLE_GENAI_USE_VERTEXAI": "TRUE",
        "WELWI_MODEL": os.environ.get("WELWI_MODEL", "gemini-3.6-flash"),
        "FIRESTORE_DATABASE": os.environ.get("FIRESTORE_DATABASE", "(default)"),
    },
)

print("Deployed. Resource name (put this in the Flutter/gateway config):")
print(remote_app.resource_name)
