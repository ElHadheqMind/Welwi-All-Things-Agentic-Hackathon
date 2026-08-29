"""Calendar tools for the Calendar sub-agent (and the voice companion).

Same propose -> confirm shape as notes_tools: the agent never creates an
event without an explicit confirmation step surfaced in session state for
the client to render as an action card. Storage is Firestore, the same
backing store as notes_tools.py — not the real Google Calendar API.

That's a deliberate correction, not the original design: this used to call
the real Google Calendar API via a user OAuth token (GOOGLE_CALENDAR_TOKEN_PATH).
That token was never actually minted for either deployed service (confirmed
by inspecting both Cloud Run services' env vars directly — the var isn't
set on `welwi-text-agent` or `welwi-voice-agent`), which meant every
`create_calendar_event`/`list_upcoming_events` call was silently returning
a "not connected" error in production the whole time, and the client-side
local-provider mirror (gated on status == "created") never fired either.
Firestore-backed storage, mirroring notes_tools.py's already-proven
pattern, actually works today instead of depending on an OAuth flow no one
has time to wire up before the deadline. The real-Calendar path can come
back later behind the same function signatures if that token ever gets
minted; nothing about the propose/confirm contract needs to change for it.
"""
from datetime import datetime, timezone

from google.adk.tools import ToolContext

from ..firestore_client import get_db

_PENDING_KEY = "pending_event"
_COLLECTION = "events"


def propose_calendar_event(
    title: str,
    start_iso: str,
    end_iso: str,
    tool_context: ToolContext,
    description: str = "",
) -> dict:
    """Draft a calendar event for the user to review before it is created.

    Args:
        title: Event title.
        start_iso: Start time, ISO 8601 with timezone offset (the agent
            must resolve any relative phrase like "tomorrow at 3pm" to an
            absolute timestamp before calling this tool).
        end_iso: End time, ISO 8601 with timezone offset.
        description: Optional event notes.
    """
    proposal = {
        "title": title,
        "start_iso": start_iso,
        "end_iso": end_iso,
        "description": description,
    }
    tool_context.state[_PENDING_KEY] = proposal
    return {"status": "awaiting_confirmation", "action": "create_calendar_event", "event": proposal}


def create_calendar_event(tool_context: ToolContext) -> dict:
    """Create the currently proposed event, after the user has confirmed it."""
    proposal = tool_context.state.get(_PENDING_KEY)
    if not proposal:
        return {"status": "error", "message": "No proposed event to create."}

    user_id = tool_context.state.get("user_id", "anonymous")
    doc = {
        **proposal,
        "user_id": user_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        ref = get_db().collection(_COLLECTION).document()
        ref.set(doc)
    except Exception as e:
        # Deliberately broad, not just FirestoreUnavailable: a single bad
        # query (e.g. a missing Firestore composite index — hit in
        # production and confirmed to kill the entire Live WebSocket
        # session, not just fail this one tool call) must degrade to a
        # normal tool error instead of propagating and taking the whole
        # conversation down with it.
        return {"status": "error", "message": str(e)}
    tool_context.state[_PENDING_KEY] = None
    return {"status": "created", "event_id": ref.id, "event": doc}


def discard_calendar_event(tool_context: ToolContext) -> dict:
    """Drop the currently proposed event because the user rejected it."""
    tool_context.state[_PENDING_KEY] = None
    return {"status": "discarded"}


def list_upcoming_events(tool_context: ToolContext, max_results: int = 10) -> dict:
    """List the user's events, soonest first, starting from the beginning of
    today. Deliberately not "from this exact moment" — someone asking what's
    on their calendar today means the whole day, including things earlier
    today, not just what's still ahead of the current second.
    """
    user_id = tool_context.state.get("user_id", "anonymous")
    start_of_today_iso = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).isoformat()
    try:
        docs = (
            get_db()
            .collection(_COLLECTION)
            .where("user_id", "==", user_id)
            .order_by("start_iso")
            .limit(200)
            .stream()
        )
        events = []
        for doc in docs:
            data = doc.to_dict()
            if data.get("start_iso", "") >= start_of_today_iso:
                events.append({"event_id": doc.id, **data})
            if len(events) >= max_results:
                break
    except Exception as e:
        # Deliberately broad, not just FirestoreUnavailable: a single bad
        # query (e.g. a missing Firestore composite index — hit in
        # production and confirmed to kill the entire Live WebSocket
        # session, not just fail this one tool call) must degrade to a
        # normal tool error instead of propagating and taking the whole
        # conversation down with it.
        return {"status": "error", "message": str(e)}
    return {"status": "ok", "events": events}


def update_calendar_event(
    event_id: str,
    tool_context: ToolContext,
    title: str = "",
    start_iso: str = "",
    end_iso: str = "",
    description: str = "",
) -> dict:
    """Change an already-created event — reschedule it, rename it, etc.

    Call `list_upcoming_events` first to find the right event_id; confirm
    the change with the user in conversation before calling this (there is
    no separate propose/confirm staging step for edits — the confirmation
    is the conversation itself). Only pass the fields that are changing;
    leave the rest as empty strings to keep their current value.

    Args:
        event_id: The event's id, from `list_upcoming_events`.
        title: New title, or empty to leave unchanged.
        start_iso: New start time (ISO 8601 with timezone offset), or empty
            to leave unchanged.
        end_iso: New end time, or empty to leave unchanged.
        description: New description, or empty to leave unchanged.
    """
    updates = {
        k: v
        for k, v in {
            "title": title,
            "start_iso": start_iso,
            "end_iso": end_iso,
            "description": description,
        }.items()
        if v
    }
    if not updates:
        return {"status": "error", "message": "Nothing to update."}
    try:
        ref = get_db().collection(_COLLECTION).document(event_id)
        if not ref.get().exists:
            return {"status": "error", "message": "No such event."}
        ref.update(updates)
    except Exception as e:
        # Deliberately broad, not just FirestoreUnavailable: a single bad
        # query (e.g. a missing Firestore composite index — hit in
        # production and confirmed to kill the entire Live WebSocket
        # session, not just fail this one tool call) must degrade to a
        # normal tool error instead of propagating and taking the whole
        # conversation down with it.
        return {"status": "error", "message": str(e)}
    return {"status": "updated", "event_id": event_id, "updates": updates}


def delete_calendar_event(event_id: str, tool_context: ToolContext) -> dict:
    """Permanently remove an already-created event.

    Call `list_upcoming_events` first to find the right event_id, and
    confirm with the user before calling this — it cannot be undone.
    """
    try:
        ref = get_db().collection(_COLLECTION).document(event_id)
        if not ref.get().exists:
            return {"status": "error", "message": "No such event."}
        ref.delete()
    except Exception as e:
        # Deliberately broad, not just FirestoreUnavailable: a single bad
        # query (e.g. a missing Firestore composite index — hit in
        # production and confirmed to kill the entire Live WebSocket
        # session, not just fail this one tool call) must degrade to a
        # normal tool error instead of propagating and taking the whole
        # conversation down with it.
        return {"status": "error", "message": str(e)}
    return {"status": "deleted", "event_id": event_id}
