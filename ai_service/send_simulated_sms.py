import os
import sys
import json
import time
import hmac
import hashlib
import urllib.request
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

SECRET = os.environ.get("WEBHOOK_SECRET", "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400")
HOUSEHOLD_ID = os.environ.get("TEST_HOUSEHOLD_ID", "f860188e-23b5-4749-b180-868c956151a6")

def send_sms(raw_text: str, sender: str = "AlRajhi"):
    payload = {
        "raw_sms": raw_text,
        "sender": sender,
        "received_at": datetime.now().isoformat(),
        "household_id": HOUSEHOLD_ID,
        "device_id": "RFGYC0B58DH"
    }
    body_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    signature = hmac.new(SECRET.encode(), body_bytes, hashlib.sha256).hexdigest()

    req = urllib.request.Request(
        "http://127.0.0.1:8000/webhook/sms",
        data=body_bytes,
        headers={
            "Content-Type": "application/json",
            "X-Signature": f"sha256={signature}"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print("HTTP Response:", resp.status)
            print(json.dumps(data, indent=2, ensure_ascii=False))
            return data
    except urllib.error.HTTPError as e:
        print("HTTP Error:", e.code, e.read().decode("utf-8"))
    except Exception as e:
        print("Error:", str(e))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        text = sys.argv[1]
    else:
        text = "شراء عبر نقاط البيع\nبطاقة مدى: **8821\nمبلغ: 85.50 رس\nلدى: صيدلية النهدي NAHDI\nفي: 2026-09-25 19:20\nالرصيد: 3,364.50 رس"
    send_sms(text)
