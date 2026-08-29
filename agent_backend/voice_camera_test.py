"""Proves real-time VIDEO FRAME streaming into a live Gemini session actually
works end-to-end — not just that the agent object constructs. Drives ADK's
`run_live()` directly with a `LiveRequestQueue`, feeding it a synthetic
"camera frame" (a JPEG generated locally, standing in for a real phone
camera frame — the wire format is identical either way: raw image bytes in
a `types.Blob`), and checks the model's spoken/text response actually
describes what's in that frame.

This is the same underlying mechanism `adk web`'s browser mic/camera toggle
uses, and the same one a real Flutter camera client would use — just driven
by a script instead of a browser, so it can run headless and be verified.

Run: .venv/Scripts/python.exe voice_camera_test.py
"""
import asyncio
import io

from google.adk.agents.live_request_queue import LiveRequestQueue
from google.adk.agents.run_config import RunConfig, StreamingMode
from google.adk.runners import InMemoryRunner
from google.genai import types

from welwi_voice_agent.agent import root_agent


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
    runner = InMemoryRunner(agent=root_agent, app_name="voice_camera_test")
    session = await runner.session_service.create_session(
        app_name="voice_camera_test", user_id="camera_test_user"
    )

    queue = LiveRequestQueue()
    run_config = RunConfig(
        # Native-audio Live models are speech-to-speech only — TEXT-only
        # response_modalities isn't supported (confirmed by testing: the
        # session rejects the connection outright). Request AUDIO, but turn
        # on the transcription side-channel so the spoken response is also
        # checkable as text without needing to decode/play actual audio.
        response_modalities=["AUDIO"],
        output_audio_transcription=types.AudioTranscriptionConfig(),
        streaming_mode=StreamingMode.BIDI,
    )

    events = []

    async def consume():
        async for event in runner.run_live(
            user_id="camera_test_user",
            session_id=session.id,
            live_request_queue=queue,
            run_config=run_config,
        ):
            events.append(event)
            if event.output_transcription and event.output_transcription.text:
                print(f"[{event.author}] (spoken, transcribed): {event.output_transcription.text}")
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if part.text:
                        print(f"[{event.author}] says: {part.text}")

    consumer_task = asyncio.create_task(consume())

    # Simulate a phone camera pointing at a shelf with a milk carton label —
    # a real camera streams continuous frames, not one still shot, so send
    # several over ~2s the way a real client's frame-grab loop would.
    frame_bytes = make_frame_jpeg("MILK")
    print(">>> streaming video frames (simulated camera feed, 2fps): a frame showing the word 'MILK'")
    for _ in range(5):
        queue.send_realtime(types.Blob(mime_type="image/jpeg", data=frame_bytes))
        await asyncio.sleep(0.5)

    print(">>> sending text turn: 'What do you see right now?'")
    queue.send_content(types.Content(role="user", parts=[types.Part(text="What do you see right now?")]))

    # Give the model time to respond, then close the stream.
    await asyncio.sleep(15)
    queue.close()

    try:
        await asyncio.wait_for(consumer_task, timeout=10)
    except asyncio.TimeoutError:
        consumer_task.cancel()

    print(f"\nTotal events received: {len(events)}")
    transcripts = [e.output_transcription.text for e in events if e.output_transcription and e.output_transcription.text]
    full_transcript = "".join(transcripts)
    print(f"Full spoken response (transcribed): {full_transcript!r}")
    print(f"Model's response referenced the frame content ('milk'): {'milk' in full_transcript.lower()}")


if __name__ == "__main__":
    asyncio.run(main())
