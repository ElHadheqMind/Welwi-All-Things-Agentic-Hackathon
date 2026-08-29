"""Pre-deploy rehearsal + integration check for the Welwi agent backend.

Exercises every propose -> confirm pipeline in `welwi_agent` against the
REAL Gemini API (uses your GOOGLE_API_KEY from .env), with an in-memory fake
standing in for Firestore and Google Calendar (see testing/fakes.py) so this
runs with zero GCP project setup. It verifies agent *logic and routing* —
not cloud plumbing, which still needs a real run against your GCP project
before submission (see README.md "Local setup").

Also doubles as a literal demo transcript: every scenario prints exactly
what a live conversation looks like, good to skim before recording the demo
video.

Run:  .venv/Scripts/python.exe demo_script.py
      (needs Pillow for the vision scenario: pip install -r requirements-dev.txt)

Exits non-zero if any scenario fails.
"""
import asyncio
import io
import sys
from unittest import mock

from google.adk.runners import InMemoryRunner
from google.genai import types

from testing.fakes import FakeCalendarService, FakeFirestore
from welwi_agent.agent import root_agent

results = []


def record(name, passed, detail=""):
    results.append((name, passed))
    mark = "PASS" if passed else "FAIL"
    print(f"\n=== [{mark}] {name}")
    if detail:
        print(f"     {detail}")


async def send(runner, session_id, *, text=None, image_bytes=None, label=""):
    parts = []
    if image_bytes:
        parts.append(types.Part.from_bytes(data=image_bytes, mime_type="image/png"))
    if text:
        parts.append(types.Part(text=text))
    message = types.Content(role="user", parts=parts)
    print(f"\n>>> USER {label}: {text or '[image]'}")
    transcript = []
    async for event in runner.run_async(user_id="demo_user", session_id=session_id, new_message=message):
        if event.content and event.content.parts:
            for part in event.content.parts:
                if part.text:
                    print(f"    [{event.author}] says: {part.text}")
                    transcript.append(("text", event.author, part.text))
                if part.function_call:
                    args = dict(part.function_call.args or {})
                    print(f"    [{event.author}] calls: {part.function_call.name}({args})")
                    transcript.append(("call", event.author, part.function_call.name))
                if part.function_response:
                    print(f"    [{event.author}] tool result: {part.function_response.response}")
                    transcript.append(("result", event.author, part.function_response.response))
    return transcript


def calls_named(transcript, name):
    return [t for t in transcript if t[0] == "call" and t[2] == name]


def make_flyer_png(lines: list[str]) -> bytes:
    from PIL import Image, ImageDraw, ImageFont

    font = None
    for candidate in (r"C:\Windows\Fonts\arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            font = ImageFont.truetype(candidate, 42)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    img = Image.new("RGB", (900, 90 * len(lines) + 60), "white")
    draw = ImageDraw.Draw(img)
    y = 30
    for line in lines:
        draw.text((30, y), line, fill="black", font=font)
        y += 90
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


async def scenario_note_confirm():
    fake_db = FakeFirestore()
    with mock.patch("welwi_agent.tools.notes_tools.get_db", return_value=fake_db), mock.patch(
        "welwi_agent.tools.feedback_tools.get_db", return_value=fake_db
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_note_confirm")
        session = await runner.session_service.create_session(
            app_name="demo_note_confirm", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, text="Remind myself to buy milk and eggs tomorrow.", label="(1/2)")
        t2 = await send(runner, session.id, text="yes, save it", label="(2/2)")

    notes = fake_db.dump().get("notes", {})
    feedback = list(fake_db.dump().get("agent_feedback", {}).values())
    ok = (
        len(calls_named(t1, "propose_note")) == 1
        and len(calls_named(t2, "save_note")) == 1
        and len(notes) == 1
        and any(f["accepted"] is True and f["action_type"] == "note" for f in feedback)
    )
    record(
        "Note pipeline: propose -> confirm -> Firestore write + feedback logged",
        ok,
        f"notes saved={len(notes)}, feedback entries={len(feedback)}",
    )


async def scenario_note_reject():
    fake_db = FakeFirestore()
    with mock.patch("welwi_agent.tools.notes_tools.get_db", return_value=fake_db), mock.patch(
        "welwi_agent.tools.feedback_tools.get_db", return_value=fake_db
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_note_reject")
        session = await runner.session_service.create_session(
            app_name="demo_note_reject", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, text="Note that the wifi password is Sunflower42.", label="(1/2)")
        t2 = await send(runner, session.id, text="no, don't save that", label="(2/2)")

    notes = fake_db.dump().get("notes", {})
    feedback = list(fake_db.dump().get("agent_feedback", {}).values())
    ok = (
        len(calls_named(t1, "propose_note")) == 1
        and len(calls_named(t2, "discard_note")) == 1
        and len(notes) == 0
        and any(f["accepted"] is False and f["action_type"] == "note" for f in feedback)
    )
    record(
        "Note pipeline: propose -> reject -> nothing written + feedback logged False",
        ok,
        f"notes saved={len(notes)}, feedback entries={len(feedback)}",
    )


async def scenario_calendar_confirm_and_list():
    fake_db = FakeFirestore()
    fake_cal = FakeCalendarService()
    with mock.patch("welwi_agent.tools.feedback_tools.get_db", return_value=fake_db), mock.patch(
        "welwi_agent.tools.calendar_tools._calendar_service", return_value=fake_cal
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_cal_confirm")
        session = await runner.session_service.create_session(
            app_name="demo_cal_confirm", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, text="Book a dentist appointment tomorrow at 3pm.", label="(1/3)")
        t2 = await send(runner, session.id, text="yes, that's right", label="(2/3)")
        t3 = await send(runner, session.id, text="What's on my calendar?", label="(3/3)")

    events = fake_cal._store.get("primary", {})
    ok = (
        len(calls_named(t1, "propose_calendar_event")) == 1
        and len(calls_named(t2, "create_calendar_event")) == 1
        and len(events) == 1
        and len(calls_named(t3, "list_upcoming_events")) == 1
    )
    record(
        "Calendar pipeline: propose -> confirm -> real Calendar API write -> list reflects it",
        ok,
        f"events created={len(events)}: {list(events.values())}",
    )


async def scenario_calendar_reject():
    fake_cal = FakeCalendarService()
    with mock.patch("welwi_agent.tools.feedback_tools.get_db", return_value=FakeFirestore()), mock.patch(
        "welwi_agent.tools.calendar_tools._calendar_service", return_value=fake_cal
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_cal_reject")
        session = await runner.session_service.create_session(
            app_name="demo_cal_reject", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, text="Schedule a meeting next Tuesday at 10am.", label="(1/2)")
        t2 = await send(runner, session.id, text="actually cancel that", label="(2/2)")

    events = fake_cal._store.get("primary", {})
    ok = len(calls_named(t1, "propose_calendar_event")) == 1 and len(calls_named(t2, "discard_calendar_event")) == 1 and len(events) == 0
    record("Calendar pipeline: propose -> reject -> nothing created on real Calendar", ok, f"events created={len(events)}")


async def scenario_vision_flyer_to_event():
    flyer = make_flyer_png(["Dentist Appointment", "Tomorrow at 3:00 PM"])
    fake_db = FakeFirestore()
    fake_cal = FakeCalendarService()
    with mock.patch("welwi_agent.tools.feedback_tools.get_db", return_value=fake_db), mock.patch(
        "welwi_agent.tools.calendar_tools._calendar_service", return_value=fake_cal
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_vision_event")
        session = await runner.session_service.create_session(
            app_name="demo_vision_event", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, image_bytes=flyer, text="What should I do with this?", label="(1/2, photo)")
        t2 = await send(runner, session.id, text="yes please", label="(2/2)")

    events = fake_cal._store.get("primary", {})
    ok = len(calls_named(t1, "propose_calendar_event")) == 1 and len(calls_named(t2, "create_calendar_event")) == 1 and len(events) == 1
    record(
        "Vision pipeline: photo of flyer -> proposed event -> confirm -> real Calendar write",
        ok,
        f"events created={len(events)}: {list(events.values())}",
    )


async def scenario_vision_note_to_note():
    sticky = make_flyer_png(["WiFi Password:", "Sunflower42"])
    fake_db = FakeFirestore()
    with mock.patch("welwi_agent.tools.notes_tools.get_db", return_value=fake_db), mock.patch(
        "welwi_agent.tools.feedback_tools.get_db", return_value=fake_db
    ):
        runner = InMemoryRunner(agent=root_agent, app_name="demo_vision_note")
        session = await runner.session_service.create_session(
            app_name="demo_vision_note", user_id="demo_user", state={"user_id": "demo_user"}
        )
        t1 = await send(runner, session.id, image_bytes=sticky, label="(1/2, photo)")
        t2 = await send(runner, session.id, text="yep, save it", label="(2/2)")

    notes = fake_db.dump().get("notes", {})
    ok = len(calls_named(t1, "propose_note")) == 1 and len(calls_named(t2, "save_note")) == 1 and len(notes) == 1
    record("Vision pipeline: photo of a note -> proposed note -> confirm -> Firestore write", ok, f"notes saved={len(notes)}")


async def main():
    print("Welwi agent backend — pre-deploy demo & integration check")
    print("=" * 70)
    await scenario_note_confirm()
    await scenario_note_reject()
    await scenario_calendar_confirm_and_list()
    await scenario_calendar_reject()
    await scenario_vision_flyer_to_event()
    await scenario_vision_note_to_note()

    print("\n" + "=" * 70)
    passed = sum(1 for _, ok in results if ok)
    for name, ok in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    print(f"\n{passed}/{len(results)} scenarios passed.")
    if passed != len(results):
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
