"""Tests the DEPLOYED Cloud Run service (welwi-text-agent) via its plain
REST API — the same endpoints a Flutter client would call. Uses gcloud
identity token auth since the service requires authentication.
"""
import json
import subprocess
import time

import requests

BASE_URL = "https://welwi-text-agent-549628512893.us-central1.run.app"
APP_NAME = "welwi_agent"
USER_ID = "cloud_run_test_user"
SESSION_ID = "test-session-1"


def get_token():
    return subprocess.check_output(
        ["gcloud", "auth", "print-identity-token"], shell=True, text=True
    ).strip()


def main():
    token = get_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    # Create session
    r = requests.post(
        f"{BASE_URL}/apps/{APP_NAME}/users/{USER_ID}/sessions/{SESSION_ID}",
        headers=headers,
        json={},
    )
    print("Create session:", r.status_code, r.text[:200])

    def send(text):
        print(f"\n>>> USER: {text}")
        t0 = time.time()
        r = requests.post(
            f"{BASE_URL}/run",
            headers=headers,
            json={
                "app_name": APP_NAME,
                "user_id": USER_ID,
                "session_id": SESSION_ID,
                "new_message": {"role": "user", "parts": [{"text": text}]},
            },
            timeout=90,
        )
        print(f"    HTTP {r.status_code} in {time.time()-t0:.1f}s")
        if r.status_code != 200:
            print("    ERROR BODY:", r.text[:1000])
            return
        events = r.json()
        for event in events:
            content = event.get("content", {})
            for part in content.get("parts", []):
                if "text" in part:
                    print(f"    [{event.get('author')}] says: {part['text']}")
                if "functionCall" in part:
                    fc = part["functionCall"]
                    print(f"    [{event.get('author')}] calls: {fc.get('name')}({fc.get('args')})")
                if "functionResponse" in part:
                    fr = part["functionResponse"]
                    print(f"    [{event.get('author')}] tool result: {fr.get('response')}")

    send("Remind myself to buy milk and eggs tomorrow.")
    send("yes, save it")

    print("\nDone.")


if __name__ == "__main__":
    main()
