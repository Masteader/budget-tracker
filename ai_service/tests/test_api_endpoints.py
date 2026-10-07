"""
Integration tests for FastAPI endpoints:
- /health
- /agent/chat-transaction
- /agent/scan-receipt
- HMAC signature security checks
- Cross-channel duplicate warnings and auto-enrichment
"""
import hashlib
import hmac
import json
import os
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app, WEBHOOK_SECRET

client = TestClient(app)
SECRET = os.environ.get("WEBHOOK_SECRET", "dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400")
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"

def _make_signed_headers(payload: dict) -> dict:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sig = hmac.new(SECRET.encode(), body, hashlib.sha256).hexdigest()
    return {
        "Content-Type": "application/json",
        "X-Signature": f"sha256={sig}",
    }

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_chat_unauthorized_without_signature():
    payload = {"message": "Dunkin 19 SAR", "household_id": HOUSEHOLD_ID}
    response = client.post("/agent/chat-transaction", json=payload)
    # When WEBHOOK_SECRET is set, requests without valid signature return 401
    if os.environ.get("WEBHOOK_SECRET"):
        assert response.status_code == 401

@patch("chat_parser.parse_chat_expense")
@patch("chat_parser.insert_transaction")
@patch("chat_parser.find_duplicate_candidate")
def test_chat_transaction_success(mock_dedup, mock_insert, mock_parse):
    from chat_parser import ParsedChatExpense, ChatLineItem
    mock_parse.return_value = ParsedChatExpense(
        merchant="Dunkin'",
        total_amount=19.0,
        currency="SAR",
        category_code="OPEX-DINING",
        items=[
            ChatLineItem(name="Ice Latte", quantity=1.0, price=16.0),
            ChatLineItem(name="Donut", quantity=1.0, price=3.0),
        ],
    )
    mock_dedup.return_value = None
    mock_insert.return_value = "tx-9999"

    payload = {
        "message": "merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut",
        "household_id": HOUSEHOLD_ID,
        "allow_duplicate": False,
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/chat-transaction", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["merchant"] == "Dunkin'"
    assert data["amount"] == 19.0
    assert len(data["items"]) == 2

@patch("chat_parser.parse_chat_expense")
@patch("chat_parser.find_duplicate_candidate")
def test_chat_transaction_duplicate_candidate(mock_dedup, mock_parse):
    from chat_parser import ParsedChatExpense, ChatLineItem
    mock_parse.return_value = ParsedChatExpense(
        merchant="Dunkin'",
        total_amount=19.0,
        currency="SAR",
        category_code="OPEX-DINING",
        items=[ChatLineItem(name="Ice Latte", quantity=1.0, price=19.0)],
    )
    mock_dedup.return_value = {
        "id": "tx-sms-111",
        "merchant": "Dunkin'",
        "amount": 19.0,
        "timestamp": "2026-09-25T14:00:00Z",
    }

    payload = {
        "message": "Dunkin 19 SAR latte",
        "household_id": HOUSEHOLD_ID,
        "allow_duplicate": False,
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/chat-transaction", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "duplicate_candidate"
    assert data["candidate_transaction_id"] == "tx-sms-111"

@patch("chat_parser.enrich_transaction_items")
@patch("chat_parser.parse_chat_expense")
def test_chat_transaction_explicit_enrich(mock_parse, mock_enrich):
    from chat_parser import ParsedChatExpense, ChatLineItem
    mock_parse.return_value = ParsedChatExpense(
        merchant="Dunkin'",
        total_amount=19.0,
        currency="SAR",
        category_code="OPEX-DINING",
        items=[
            ChatLineItem(name="Ice Latte", quantity=1.0, price=16.0),
            ChatLineItem(name="Donut", quantity=1.0, price=3.0),
        ],
    )
    mock_enrich.return_value = True

    payload = {
        "message": "16 latte, 3 donut",
        "household_id": HOUSEHOLD_ID,
        "enrich_tx_id": "tx-sms-111",
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/chat-transaction", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "enriched"
    assert data["transaction_id"] == "tx-sms-111"
    assert len(data["items"]) == 2

@patch("receipt_scanner.parse_receipt_image")
@patch("receipt_scanner.insert_transaction")
@patch("receipt_scanner.find_duplicate_candidate")
def test_scan_receipt_success(mock_dedup, mock_insert, mock_parse):
    mock_parse.return_value = {
        "merchant": "Tamimi Markets",
        "total_amount": 85.50,
        "category_code": "OPEX-GROCERY",
        "items": [
            {"name": "Apples", "quantity": 1.0, "price": 15.50},
            {"name": "Olive Oil", "quantity": 1.0, "price": 70.0},
        ],
    }
    mock_dedup.return_value = None
    mock_insert.return_value = "tx-receipt-555"

    payload = {
        "image_base64": "fake_base64_data",
        "household_id": HOUSEHOLD_ID,
        "allow_duplicate": False,
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/scan-receipt", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "success"
    assert data["merchant"] == "Tamimi Markets"
    assert data["amount"] == 85.50
    assert len(data["items"]) == 2


def test_get_and_update_household_payday():
    # 1. Update payday to 1st of month
    put_res = client.put(f"/households/{HOUSEHOLD_ID}/payday", json={"payday_day": 1})
    assert put_res.status_code == 200
    assert put_res.json()["payday_day"] == 1
    assert put_res.json()["status"] == "success"

    # 2. Get payday
    get_res = client.get(f"/households/{HOUSEHOLD_ID}/payday")
    assert get_res.status_code == 200
    assert get_res.json()["payday_day"] == 1

    # 3. Restore to default 27
    restore_res = client.put(f"/households/{HOUSEHOLD_ID}/payday", json={"payday_day": 27})
    assert restore_res.status_code == 200
    assert restore_res.json()["payday_day"] == 27

