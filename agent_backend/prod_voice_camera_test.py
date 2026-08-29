"""Proves the DEPLOYED bidi-streaming voice agent (Agent Engine, not local)
actually works with real video-frame streaming — the production equivalent
of voice_camera_test.py. Connects over the live WebSocket API, streams
synthetic camera frames, and checks the transcribed spoken response.

Run: .venv/Scripts/python.exe prod_voice_camera_test.py
"""
import asyncio
import base64
import io
import os

from dotenv import load_dotenv

load_dotenv()

import agentplatform

PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
RESOURCE_NAME = "projects/549628512893/locations/us-central1/reasoningEngines/4772625383675658240"


def make_frame_jpeg(text_on_frame: str) -> bytes:
    from PIL import Image, ImageDraw, ImageFont

    font = None
    for candidate in (r"C:\Windows\Fonts\arial.ttf",):
        try:
            font = ImageFont.truetype(candidate, 60)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
    img = Image.new("RGB", (640, 480), "white")
    draw = ImageDraw.Draw(img)
    draw.text((40, 200), text_on_frame, fill="black", font=font)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


async def main():
    client = agentplatform.Client(project=PROJECT, location=LOCATION)

    frame_b64 = base64.b64encode(make_frame_jpeg("EGGS")).decode("utf-8")

    async with client.aio.live.agent_engines.connect(
        agent_engine=RESOURCE_NAME,
        config={"class_method": "bidi_stream_query"},
    ) as session:
        print(">>> connecting + sending first video frame (simulated camera: 'EGGS')")
        await session.send(
            {
                "user_id": "prod_camera_test_user",
                "run_config": {
                    "response_modalities": ["AUDIO"],
                    "output_audio_transcription": {},
                    "streaming_mode": "bidi",
                },
                "live_request": {"blob": {"mime_type": "image/jpeg", "data": frame_b64}},
            }
        )

        print(">>> streaming 4 more frames (simulated 2fps camera feed)")
        for _ in range(4):
            await asyncio.sleep(0.5)
            await session.send({"blob": {"mime_type": "image/jpeg", "data": frame_b64}})

        print(">>> sending text turn: 'What do you see right now?'")
        await session.send(
            {"content": {"role": "user", "parts": [{"text": "What do you see right now?"}]}}
        )

        transcript_parts = []

        async def collect():
            try:
                while True:
                    response = await asyncio.wait_for(session.receive(), timeout=20)
                    print("RAW:", response)
                    ot = response.get("output_transcription") or response.get("outputTranscription")
                    if ot and ot.get("text"):
                        transcript_parts.append(ot["text"])
            except (asyncio.TimeoutError, Exception) as e:
                print("(stopped receiving:", type(e).__name__, ")")

        await asyncio.wait_for(collect(), timeout=25)

        full = "".join(transcript_parts)
        print(f"\nFull transcript: {full!r}")
        print(f"Response referenced the frame content ('eggs'): {'egg' in full.lower()}")


if __name__ == "__main__":
    asyncio.run(main())
