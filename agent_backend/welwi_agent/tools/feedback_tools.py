"""Records whether the user accepted or rejected a proposed action.

This is the adaptive-feedback loop: every propose/confirm or
propose/discard pair is logged so future sessions can bias the agent's
instructions (or, later, a fine-tuned ranking) toward the kinds of
proposals a given user actually accepts.
"""
from datetime import datetime, timezone

from google.adk.tools import ToolContext

from ..firestore_client import FirestoreUnavailable, get_db


def record_action_feedback(action_type: str, accepted: bool, tool_context: ToolContext) -> dict:
    """Log whether the user accepted or rejected a proposed action.

    Args:
        action_type: One of "note" or "calendar_event".
        accepted: True if the user confirmed the action, False if they
            rejected/edited it away.
    """
    user_id = tool_context.state.get("user_id", "anonymous")
    try:
        get_db().collection("agent_feedback").add(
            {
                "user_id": user_id,
                "action_type": action_type,
                "accepted": accepted,
                "at": datetime.now(timezone.utc).isoformat(),
            }
        )
    except FirestoreUnavailable as e:
        return {"status": "error", "message": str(e)}
    return {"status": "logged"}
