"""Closes the remaining Cloud Run test gaps: note_agent (never explicitly
exercised there) and iris_agent/vision (never tested there at all — only
locally and on Agent Engine). Same REST API a Flutter client would use.
"""
import base64
import io
import subprocess
import time
import uuid

import requests

BASE_URL = "https://welwi-text-agent-549628512893.us-central1.run.app"
APP_NAME = "welwi_agent"


def get_token():
    return subprocess.check_output(["gcloud", "auth", "print-identity-token"], shell=True, text=True).strip()


def make_flyer_png(lines):
    from PIL import Image, ImageDraw, ImageFont

    font = None
    for candidate in (r"C:\Windows\Fonts\arial.ttf",):
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


def run_scenario(name, user_id, session_id, headers, turns):
    print(f"\n{'='*70}\n{name}\n{'='*70}")
    r = requests.post(
        f"{BASE_URL}/apps/{APP_NAME}/users/{user_id}/sessions/{session_id}",
        headers={**headers, "Content-Type": "application/json"},
        json={},
    )
    assert r.status_code == 200, f"session create failed: {r.status_code} {r.text}"

    results = []
    for label, parts in turns:
        t0 = time.time()
        r = requests.post(
            f"{BASE_URL}/run",
            headers={**headers, "Content-Type": "application/json"},
            json={"app_name": APP_NAME, "user_id": user_id, "session_id": session_id,
                  "new_message": {"role": "user", "parts": parts}},
            timeout=90,
        )
        dt = time.time() - t0
        print(f"\n>>> {label} (HTTP {r.status_code}, {dt:.1f}s)")
        if r.status_code != 200:
            print("    ERROR:", r.text[:500])
            results.append(False)
            continue
        events = r.json()
        calls = []
        for event in events:
            content = event.get("content", {})
            for part in content.get("parts", []):
                if "text" in part:
                    print(f"    [{event.get('author')}] says: {part['text']}")
                if "functionCall" in part:
                    fc = part["functionCall"]
                    calls.append(fc.get("name"))
                    print(f"    [{event.get('author')}] calls: {fc.get('name')}({fc.get('args')})")
                if "functionResponse" in part:
                    fr = part["functionResponse"]
                    print(f"    [{event.get('author')}] tool result: {fr.get('response')}")
        results.append(calls)
    return results


def main():
    token = get_token()
    headers = {"Authorization": f"Bearer {token}"}
    uid = f"full_test_{uuid.uuid4().hex[:6]}"

    all_pass = True

    # --- note_agent, explicitly (a phrase that has never routed anywhere else in prior tests) ---
    calls = run_scenario(
        "TEST 1: note_agent on Cloud Run",
        uid, "s1", headers,
        [
            ("Note that the wifi password is Sunflower42.", [{"text": "Note that the wifi password is Sunflower42."}]),
            ("yes, save it", [{"text": "yes, save it"}]),
        ],
    )
    ok1 = "propose_note" in calls[0] and "save_note" in calls[1]
    print(f"\n[{'PASS' if ok1 else 'FAIL'}] note_agent propose+confirm on Cloud Run")
    all_pass &= ok1

    # --- iris_agent / vision, never tested on Cloud Run at all ---
    flyer = make_flyer_png(["Dentist Appointment", "Tomorrow at 3:00 PM"])
    b64 = base64.b64encode(flyer).decode("utf-8")
    calls = run_scenario(
        "TEST 2: iris_agent (vision) on Cloud Run",
        uid, "s2", headers,
        [
            ("[photo of flyer] What should I do with this?",
             [{"inlineData": {"mimeType": "image/png", "data": b64}}, {"text": "What should I do with this?"}]),
            ("yes please", [{"text": "yes please"}]),
        ],
    )
    ok2 = "propose_calendar_event" in calls[0] and "create_calendar_event" in calls[1]
    print(f"\n[{'PASS' if ok2 else 'FAIL'}] iris_agent (vision) propose+confirm on Cloud Run")
    all_pass &= ok2

    print(f"\n{'='*70}\nOVERALL: {'ALL PASS' if all_pass else 'SOME FAILED'}\n{'='*70}")


if __name__ == "__main__":
    main()
