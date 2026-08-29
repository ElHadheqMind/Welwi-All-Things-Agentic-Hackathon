import os
from functools import cached_property
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

from google.adk.models import Gemini
from google.genai import Client, types

_MODEL_NAME = os.environ.get("WELWI_MODEL", "gemini-3.6-flash")


def _wants_vertex() -> bool:
    return os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "").strip().lower() in ("1", "true", "yes")


class _EnvAwareGemini(Gemini):
    """Resolves its API client lazily, from whatever process actually runs
    the model call — not from whatever env the deploying machine had.

    `agent_engines.create()` pickles the constructed Agent graph and ships it
    to Agent Engine's runtime, which has its OWN environment (Vertex,
    reserved GOOGLE_CLOUD_LOCATION pinned to the deploy region). If this
    class's client were built eagerly at construction time, it would bake in
    whatever env var state the local deploy script happened to have (e.g.
    local dev's GOOGLE_GENAI_USE_VERTEXAI=FALSE for a fast API-key feedback
    loop) instead of the deployed runtime's. `cached_property` defers that
    decision to first actual use, in whichever process that turns out to be.

    Newer Gemini releases also often land on Vertex AI's "global" endpoint
    only, before regional availability (confirmed by probing: gemini-3.6-flash
    404s in us-central1, works in global) — so when running on Vertex, this
    pins the model client to "global" regardless of the agent's own deploy
    region.
    """

    @cached_property
    def api_client(self) -> Client:
        if _wants_vertex():
            return Client(enterprise=True, location="global")
        # Explicit enterprise=False, not a bare Client(): `adk deploy cloud_run`
        # bakes `ENV GOOGLE_GENAI_USE_ENTERPRISE=1` into every generated
        # Dockerfile unconditionally, and google-genai's Client() gives
        # ENTERPRISE priority over VERTEXAI when both env vars are present —
        # so a bare Client() silently ends up in Vertex mode on Cloud Run even
        # with GOOGLE_GENAI_USE_VERTEXAI=FALSE explicitly set. Passing
        # enterprise=False here as a real constructor argument short-circuits
        # that env-var lookup entirely (see google/genai/client.py: explicit
        # args are only replaced by env vars when both are None). Found by
        # bisecting a live model that only failed on Cloud Run/Agent Engine,
        # never locally, down to this exact Dockerfile line.
        return Client(enterprise=False)


MODEL = _EnvAwareGemini(model=_MODEL_NAME)


def thinking(level: str) -> types.GenerateContentConfig:
    """Caps reasoning depth per agent based on actual task complexity.

    Found by testing: a plain routing decision ("transfer to note_agent")
    burned ~400 thought tokens by default — pure latency for a task that's
    really just picking one of three labels off explicit instructions. Gemini
    3.x's thinking_level lets each agent spend only as much reasoning as its
    job actually needs:
      - MINIMAL: root orchestrator (routing) and note_agent (extract a
        title/content and call one tool) — near-mechanical tasks.
      - LOW: calendar_agent (date math) and iris_agent (image understanding +
        duplicate-check judgment) — still simple, but not zero-reasoning.
    """
    return types.GenerateContentConfig(thinking_config=types.ThinkingConfig(thinking_level=level))


# Native-audio Live API model for the voice companion — bidirectional
# audio/video streaming, distinct from the plain text-generation model above.
#
# Runs over the plain Gemini Developer API (GOOGLE_API_KEY), not Vertex AI —
# deliberately. Vertex's Live/bidi path (both Agent Engine's EXPERIMENTAL
# bidi mode and Cloud Run's native /run_live) consistently rejected the
# connection ("Publisher model ... was not found") under EVERY identity
# tried — Agent Engine's service account, Cloud Run's default compute
# service account (with the broad Editor role already granted) — while an
# identical call succeeded locally under interactive user credentials. That
# pointed at a Vertex-side gap, not a bug here. The hackathon's own rules
# explicitly allow either access path ("Gemini 3.5+ via Gemini API or Vertex
# AI"), so this switches the voice agent to the Gemini API specifically —
# confirmed working end-to-end in production (Cloud Run, real streamed
# video frames, real transcribed response) once GOOGLE_GENAI_USE_ENTERPRISE
# was also explicitly overridden (see _EnvAwareGemini above for why bare
# Client() isn't safe on `adk deploy cloud_run`).
_LIVE_MODEL_NAME = os.environ.get("WELWI_LIVE_MODEL", "gemini-3.1-flash-live-preview")


class _EnvAwareGeminiLive(Gemini):
    """Same lazy-resolution + explicit enterprise=False reasoning as
    _EnvAwareGemini above, but overrides `_live_api_client` (what ADK's
    bidi/Live connect() path actually reads), not `api_client`.
    """

    @cached_property
    def _live_api_client(self) -> Client:
        if _wants_vertex():
            project = os.environ.get("GOOGLE_CLOUD_PROJECT")
            location = os.environ.get("WELWI_LIVE_LOCATION", "us-central1")
            return Client(enterprise=True, project=project, location=location)
        return Client(enterprise=False)


MODEL_LIVE = _EnvAwareGeminiLive(model=_LIVE_MODEL_NAME)
