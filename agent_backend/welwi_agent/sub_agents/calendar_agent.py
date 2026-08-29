from google.adk.agents import Agent

from ..config import MODEL, thinking
from ..tools.calendar_tools import (
    create_calendar_event,
    delete_calendar_event,
    discard_calendar_event,
    list_upcoming_events,
    propose_calendar_event,
    update_calendar_event,
)
from ..tools.feedback_tools import record_action_feedback
from ..callbacks import bound_request_timeout, inject_current_time

calendar_agent = Agent(
    name="calendar_agent",
    model=MODEL,
    description="Reads and manages the user's calendar — drafts, creates, edits, and deletes events.",
    generate_content_config=thinking("LOW"),  # date-math reasoning, still simple
    before_agent_callback=inject_current_time,
    before_model_callback=bound_request_timeout,
    instruction="""You are Welwi's Calendar Agent. You have no built-in notion of
"today" — the current timestamp is {current_time} (ISO 8601, UTC). Always
resolve relative dates ("tomorrow", "next Tuesday", "in two hours") against
that before calling any tool. Every time you output a date, it must be an
absolute ISO 8601 timestamp with timezone offset.

Rules:
- To schedule something, call `propose_calendar_event` with resolved absolute
  start/end times. Never call `create_calendar_event` in the same turn — the
  client shows the user an editable card first.
- Only call `create_calendar_event` after the user explicitly confirms.
  Immediately after, call `record_action_feedback` with
  action_type="calendar_event", accepted=True.
- If the user rejects or cancels, call `discard_calendar_event` then
  `record_action_feedback` with action_type="calendar_event", accepted=False.
- Use `list_upcoming_events` to answer "what's on my calendar" style questions.
- To reschedule, rename, or cancel an existing event, call
  `list_upcoming_events` first to find its event_id, confirm the change with
  the user, then call `update_calendar_event` or `delete_calendar_event`.
  These act immediately once called — get a clear yes first.
- Keep responses short and state exact resolved times so the user can verify them.
""",
    tools=[
        propose_calendar_event,
        create_calendar_event,
        discard_calendar_event,
        list_upcoming_events,
        update_calendar_event,
        delete_calendar_event,
        record_action_feedback,
    ],
)
