"""Shared agent callbacks."""
from datetime import datetime, timezone

from google.adk.agents.callback_context import CallbackContext
from google.adk.models import LlmRequest
from google.genai import types


def inject_current_time(callback_context: CallbackContext) -> None:
    """Refreshes `current_time` in session state before every agent turn.

    Edge LLMs (and cloud ones) have no innate sense of "now" — a session can
    sit open for hours, so this can't just be set once at session creation.
    Agents that resolve relative dates reference `{current_time}` directly in
    their instruction string via ADK's state-templating.
    """
    callback_context.state["current_time"] = datetime.now(timezone.utc).isoformat()


def bound_request_timeout(callback_context: CallbackContext, llm_request: LlmRequest) -> None:
    """Caps every Gemini call at 60s with bounded retries.

    Found by testing: a plain-text turn once hung with zero CPU movement for
    7+ minutes — a stalled connection with no client-side timeout, not a
    logic bug (identical calls elsewhere completed in seconds). Without this,
    a single dropped connection leaves a live user's turn (voice or text)
    hanging forever instead of failing fast and retrying.
    """
    if llm_request.config.http_options is None:
        llm_request.config.http_options = types.HttpOptions()
    llm_request.config.http_options.timeout = 60_000
    llm_request.config.http_options.retry_options = types.HttpRetryOptions(
        attempts=3, initial_delay=1.0, max_delay=10.0
    )
