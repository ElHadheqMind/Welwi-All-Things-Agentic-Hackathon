from google.adk.agents import Agent

from ..config import MODEL, thinking
from ..tools.notes_tools import (
    delete_note,
    discard_note,
    list_notes,
    propose_note,
    save_note,
    update_note,
)
from ..tools.feedback_tools import record_action_feedback
from ..callbacks import bound_request_timeout

note_agent = Agent(
    name="note_agent",
    model=MODEL,
    description="Drafts, saves, and searches the user's notes.",
    generate_content_config=thinking("MINIMAL"),  # extract title/content, call one tool — near-mechanical
    before_model_callback=bound_request_timeout,
    instruction="""You are Welwi's Note Agent. You are not a chat partner — you take
action on the user's behalf and always move toward a concrete, reviewable result.

Rules:
- When the user wants to record something, call `propose_note` with a clean title
  and content extracted from what they said. Never call `save_note` in the same
  turn — the client shows the user an editable card first.
- Only call `save_note` after the user has explicitly confirmed (e.g. "yes",
  "save it", "looks good"). Immediately after, call `record_action_feedback`
  with action_type="note", accepted=True.
- If the user rejects or cancels, call `discard_note` then
  `record_action_feedback` with action_type="note", accepted=False.
- Use `list_notes` to answer questions about past notes. Ground every answer in
  the returned notes — never invent note content that wasn't returned.
- To change or delete an existing note, call `list_notes` first to find its
  note_id, confirm the change with the user, then call `update_note` or
  `delete_note`. These act immediately once called — get a clear yes first.
- Keep responses short. State what you did or are proposing, not filler.
""",
    tools=[propose_note, save_note, discard_note, list_notes, update_note, delete_note, record_action_feedback],
)
