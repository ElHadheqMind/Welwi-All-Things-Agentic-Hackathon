from google.adk.agents import Agent

from ..config import MODEL, thinking
from ..tools.calendar_tools import (
    create_calendar_event,
    discard_calendar_event,
    list_upcoming_events,
    propose_calendar_event,
)
from ..tools.notes_tools import discard_note, list_notes, propose_note, save_note
from ..tools.feedback_tools import record_action_feedback
from ..callbacks import bound_request_timeout, inject_current_time

# "Iris" — Welwi's vision subsystem: the eyes of the user, the agent that
# turns a photo into an action instead of a caption. It speaks to the user
# as "Welwi" like every other agent (one companion brand, not a second
# character) — Iris is the internal/architectural name for this capability,
# for the diagram and the logs, not something the user hears announced.
#
# Carries the full propose -> confirm toolset itself (like note_agent /
# calendar_agent combined) rather than proposing then transferring back to
# whichever agent should finish the job. A cross-branch transfer from a leaf
# sub-agent back to a sibling isn't something to rely on for a two-turn flow
# (photo now, "yes" a few seconds later) — simpler and more testable to let
# Iris close the loop on what it opened.
#
# It also gets read-only access to note_agent's and calendar_agent's own
# `list_notes`/`list_upcoming_events` tools — genuine coordination with the
# other agents (checking "have I already noted this?" / "is this already on
# the calendar?" before proposing a duplicate), not just shared Firestore
# state underneath.
iris_agent = Agent(
    name="iris_agent",
    model=MODEL,
    description=(
        "Welwi's eyes: reads a photo (flyer, schedule, whiteboard, appointment "
        "card) and turns it directly into a proposed note or calendar event, "
        "cross-checking existing notes/events first so the user never has to "
        "type what they can just point the camera at, and never gets duplicates."
    ),
    generate_content_config=thinking("LOW"),  # image understanding + duplicate-check judgment
    before_agent_callback=inject_current_time,
    before_model_callback=bound_request_timeout,
    instruction="""You are Welwi (same companion as every other agent — you
are the part of Welwi that sees). The user sends you an image plus,
optionally, a short spoken instruction. Read the image and decide what it is:

- If it clearly describes a dated event (appointment card, flyer with a date/time,
  schedule entry), resolve the date/time against the current timestamp, which is
  {current_time} (ISO 8601, UTC). Before proposing, call `list_upcoming_events`
  to check it isn't already on the calendar — if a clear duplicate exists, tell
  the user that instead of proposing a new one. Otherwise call
  `propose_calendar_event` directly — do not just describe the image in prose.
- Otherwise, if it contains information worth remembering (a sign, a label, a
  note on paper), call `list_notes` first to check for an existing near-duplicate,
  then `propose_note` with a concise title and the extracted text.
- If the image is ambiguous, ask ONE short clarifying question instead of
  guessing at a date or committing to the wrong action type.
- Never just describe the image back to the user without proposing an action
  (unless it was a true duplicate) — that is the one failure mode to avoid:
  don't be a captioning tool, be an agent that acts on what it sees.

The user's next message (often without a new image) is their answer to your
proposal:
- On confirmation, call `save_note` or `create_calendar_event` (whichever you
  proposed), then `record_action_feedback` with accepted=True.
- On rejection/cancel, call `discard_note` or `discard_calendar_event`, then
  `record_action_feedback` with accepted=False.
""",
    tools=[
        propose_note,
        save_note,
        discard_note,
        list_notes,
        propose_calendar_event,
        create_calendar_event,
        discard_calendar_event,
        list_upcoming_events,
        record_action_feedback,
    ],
)
