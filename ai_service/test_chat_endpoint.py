import os
import json
import hmac
import hashlib
import urllib.request
from dotenv import load_dotenv

load_dotenv()

SECRET = os.environ.get("WEBHOOK_SECRET", "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400")
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

def test_chat():
    payload = {
        "message": "merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut",
        "household_id": HOUSEHOLD_ID,
        "allow_duplicate": False
    }
    body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sig = hmac.new(SECRET.encode(), body_bytes, hashlib.sha256).hexdigest()

    req = urllib.request.Request(
        "http://127.0.0.1:8000/agent/chat-transaction",
        data=body_bytes,
        headers={
            "Content-Type": "application/json",
            "X-Signature": f"sha256={sig}"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print("HTTP Status:", resp.status)
            print(json.dumps(data, indent=2, ensure_ascii=False))
    except urllib.error.HTTPError as e:
        print("HTTP Error:", e.code, e.read().decode("utf-8"))
    except Exception as e:
        print("Error:", str(e))

if __name__ == "__main__":
    test_chat()
