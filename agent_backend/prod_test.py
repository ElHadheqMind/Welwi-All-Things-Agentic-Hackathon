"""Real production smoke test: talks to the DEPLOYED Vertex AI Agent Engine
resource (not local, not fakes) — real Gemini via Vertex, real Firestore.
Run: .venv/Scripts/python.exe prod_test.py
"""
import os
import time

from dotenv import load_dotenv

load_dotenv()

import vertexai
from vertexai import agent_engines

PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
RESOURCE_NAME = "projects/549628512893/locations/us-central1/reasoningEngines/8214219923916849152"

vertexai.init(project=PROJECT, location=LOCATION)

agent_engine = agent_engines.get(RESOURCE_NAME)

session = agent_engine.create_session(user_id="prod_test_user")
print("Session created:", session["id"])


def send(text):
    print(f"\n>>> USER: {text}")
    t0 = time.time()
    for event in agent_engine.stream_query(user_id="prod_test_user", session_id=session["id"], message=text):
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
    print(f"    (turn took {time.time() - t0:.1f}s)")


send("Remind myself to buy milk and eggs tomorrow.")
send("yes, save it")

print("\nDone.")
