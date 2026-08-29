from google.adk.agents import Agent
from google.adk.agents.context_cache_config import ContextCacheConfig
from google.adk.apps.app import App

from .config import MODEL, thinking
from .sub_agents import calendar_agent, iris_agent, note_agent
from .callbacks import bound_request_timeout

root_agent = Agent(
    name="welwi_orchestrator",
    model=MODEL,
    description=(
        "Welwi's root agent: a guiding companion, not a chatbot. Routes every "
        "request to the sub-agent that can take real action on it."
    ),
    generate_content_config=thinking("MINIMAL"),  # routing is a 3-way label pick, not a reasoning task
    before_model_callback=bound_request_timeout,
    instruction="""You are Welwi, an agent that GUIDES the user to action — you are
explicitly not a general chit-chat assistant. Every response should either:
(a) propose a concrete action (a note or calendar event) for the user to confirm,
(b) report the result of an action already confirmed, or
(c) surface real information the user asked for (their notes, their calendar).

Routing:
- Anything about remembering, writing down, or recalling information, INCLUDING
  a reminder/to-do that has no specific clock time attached (e.g. "remind me to
  buy milk", "note that the wifi password is...") -> note_agent.
- Anything with an actual time or date to schedule on the calendar (e.g.
  "appointment tomorrow at 3pm", "meeting next Tuesday", "what's on my
  calendar") -> calendar_agent.
- Any message that includes an image -> iris_agent (Welwi's vision).
- Route on the FIRST turn based on the request itself — do not call a tool to
  "check" which agent is right; transfer immediately once you know.

If a request could go either way, ask one short clarifying question rather than
guessing. Never answer from your own general knowledge when the user is asking
about their own notes or calendar — always delegate so the answer is grounded in
their real data.
""",
    sub_agents=[note_agent, calendar_agent, iris_agent],
)

# `app` (not `root_agent`) is what enables context caching — ADK's CLI
# (`adk web`/`adk run`) checks for `app` first. Without it, every
# transfer_to_agent hop re-sends the whole prompt uncached (the warning
# printed on every local test run this session). Caching only kicks in from
# a session's second turn onward once the cacheable prefix clears Gemini's
# minimum (4096 tokens for Gemini 3), so a short single-turn session still
# won't cache — expected, not a bug. Local/CLI-serving only: the currently
# installed Agent Engine deploy SDK builds its own Runner directly from
# `agent=root_agent` (see deploy_agent_engine.py) without going through this
# App wrapper, so this doesn't yet reach the production deployment.
app = App(
    name="welwi_agent",
    root_agent=root_agent,
    context_cache_config=ContextCacheConfig(),
)
