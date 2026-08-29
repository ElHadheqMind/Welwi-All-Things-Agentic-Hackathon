"""Proves the DEPLOYED Cloud Run voice agent handles real streamed video
frames over its native /run_live WebSocket — the thing that failed on
Agent Engine's EXPERIMENTAL bidi mode. Uses gcloud identity token auth.
"""
import asyncio
import base64
import io
import json
import subprocess

import requests
import websockets

BASE_URL = "https://welwi-voice-agent-549628512893.us-central1.run.app"
WS_URL = "wss://welwi-voice-agent-549628512893.us-central1.run.app"
APP_NAME = "welwi_voice_agent"
USER_ID = "cloud_run_camera_test_user"
SESSION_ID = "camera-test-session-7"


def get_token():
    return subprocess.check_output(["gcloud", "auth", "print-identity-token"], shell=True, text=True).strip()


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
    token = get_token()
    headers = {"Authorization": f"Bearer {token}"}

    # Create session over plain HTTPS first (websocket handler requires it to already exist)
    r = requests.post(
        f"{BASE_URL}/apps/{APP_NAME}/users/{USER_ID}/sessions/{SESSION_ID}",
        headers={**headers, "Content-Type": "application/json"},
        json={},
    )
    print("Create session:", r.status_code, r.text[:200])

    ws_uri = f"{WS_URL}/run_live?user_id={USER_ID}&session_id={SESSION_ID}&app_name={APP_NAME}&modalities=AUDIO"

    async with websockets.connect(ws_uri, additional_headers=headers) as ws:
        print(">>> connected, streaming video frames (simulated camera, ~1fps, 10 frames): word 'BUTTER'")
        frame_b64 = base64.b64encode(make_frame_jpeg("BUTTER")).decode("utf-8")
        for _ in range(10):
            await ws.send(json.dumps({"blob": {"mime_type": "image/jpeg", "data": frame_b64}}))
            await asyncio.sleep(1.0)
        await asyncio.sleep(1.0)

        print(">>> sending text turn: 'What do you see right now?'")
        await ws.send(
            json.dumps({"content": {"role": "user", "parts": [{"text": "What do you see right now?"}]}})
        )

        transcript_parts = []
        try:
            for _ in range(40):
                raw = await asyncio.wait_for(ws.recv(), timeout=15)
                event = json.loads(raw)
                ot = event.get("outputTranscription") or event.get("output_transcription")
                if ot and ot.get("text"):
                    transcript_parts.append(ot["text"])
                    print("TRANSCRIPT PIECE:", ot["text"])
        except asyncio.TimeoutError:
            print("(no more events, timed out waiting)")

        full = "".join(transcript_parts)
        print(f"\nFull transcript: {full!r}")
        print(f"Response referenced the frame content ('butter'): {'butter' in full.lower()}")


if __name__ == "__main__":
    asyncio.run(main())
