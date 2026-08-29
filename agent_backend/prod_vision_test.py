"""Production test: vision pipeline (photo -> proposed event -> confirm ->
real Calendar/Firestore) against the DEPLOYED Agent Engine resource.
"""
import base64
import io
import os

from dotenv import load_dotenv

load_dotenv()

import vertexai
from vertexai import agent_engines

PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
RESOURCE_NAME = "projects/549628512893/locations/us-central1/reasoningEngines/2331955860617560064"


def make_flyer_png(lines):
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


vertexai.init(project=PROJECT, location=LOCATION)
agent_engine = agent_engines.get(RESOURCE_NAME)

session = agent_engine.create_session(user_id="prod_vision_test_user")
print("Session created:", session["id"])


def send(parts_message):
    for event in agent_engine.stream_query(user_id="prod_vision_test_user", session_id=session["id"], message=parts_message):
        content = event.get("content", {})
        for part in content.get("parts", []):
            if "text" in part:
                print(f"    [{event.get('author')}] says: {part['text']}")
            if "function_call" in part:
                fc = part["function_call"]
                print(f"    [{event.get('author')}] calls: {fc.get('name')}({fc.get('args')})")
            if "function_response" in part:
                fr = part["function_response"]
                print(f"    [{event.get('author')}] tool result: {fr.get('response')}")


flyer_bytes = make_flyer_png(["Dentist Appointment", "Tomorrow at 3:00 PM"])
b64 = base64.b64encode(flyer_bytes).decode("utf-8")

print("\n>>> USER: [photo of flyer] What should I do with this?")
send(
    {
        "role": "user",
        "parts": [
            {"inline_data": {"mime_type": "image/png", "data": b64}},
            {"text": "What should I do with this?"},
        ],
    }
)

print("\n>>> USER: yes please")
send("yes please")

print("\nDone.")
