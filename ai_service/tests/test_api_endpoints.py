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
from jose import jwt
from main import app, WEBHOOK_SECRET

client = TestClient(app)
SECRET = os.environ.get("WEBHOOK_SECRET", "test_secret_for_ci_only_do_not_use_in_prod")
HOUSEHOLD_ID = "f860188e-23b5-4749-b180-868c956151a6"
# Valid 1x1 PNG: uploads must now be real JPEG/PNG/WebP payloads (API-23).
TINY_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

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

def test_chat_accepts_unsigned_request_from_authenticated_user():
    """The per-user JWT is the credential; X-Signature is no longer required (client contract).
    Missing/invalid JWT → 401 is covered with real verification in test_api_audit.py."""
    payload = {"message": "Dunkin 19 SAR", "household_id": HOUSEHOLD_ID, "preview_only": True}
    response = client.post("/agent/chat-transaction", json=payload)
    assert response.status_code == 200

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
        "id": "tx-receipt-111",
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
    assert data["candidate_transaction_id"] == "tx-receipt-111"

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
        "enrich_tx_id": "tx-receipt-111",
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/chat-transaction", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "enriched"
    assert data["transaction_id"] == "tx-receipt-111"
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
        "image_base64": TINY_PNG_B64,
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
    token = jwt.encode(
        {
            "sub": "00000000-0000-0000-0000-000000000001",
            "aud": "authenticated",
            "iss": f"{os.environ.get('SUPABASE_URL', 'https://mockproject.supabase.co')}/auth/v1",
            "role": "authenticated",
        },
        os.environ.get("SUPABASE_JWT_SECRET", "super-secret-test-jwt-key-32bytes-long!"),
        algorithm="HS256",
    )
    admin_headers = {"Authorization": f"Bearer {token}"}

    with patch("auth._get_user_membership") as mock_mem, \
         patch("routes.households.set_household_payday") as mock_set_payday, \
         patch("routes.households.get_household_payday") as mock_get_payday:
        mock_mem.return_value = {"role": "admin", "household_id": HOUSEHOLD_ID}
        mock_set_payday.side_effect = lambda hh, day: day
        mock_get_payday.return_value = 1

        # 1. Update payday to 1st of month
        put_res = client.put(f"/households/{HOUSEHOLD_ID}/payday", json={"payday_day": 1}, headers=admin_headers)
        assert put_res.status_code == 200
        assert put_res.json()["payday_day"] == 1
        assert put_res.json()["status"] == "success"

        # 2. Get payday
        get_res = client.get(f"/households/{HOUSEHOLD_ID}/payday", headers=admin_headers)
        assert get_res.status_code == 200
        assert get_res.json()["payday_day"] == 1

        # 3. Restore to default 27
        restore_res = client.put(f"/households/{HOUSEHOLD_ID}/payday", json={"payday_day": 27}, headers=admin_headers)
        assert restore_res.status_code == 200
        assert restore_res.json()["payday_day"] == 27


def test_scan_receipt_with_receipt_url():
    """Verify /agent/scan-receipt accepts receipt_url and normalizes it to relative storage path."""
    payload = {
        "household_id": HOUSEHOLD_ID,
        "qr_code_raw": "ARxVbml0ZWQgRWxlY3Ryb25pY3MgQ28uIGVYdHJhAg8zMDA0Njg3ODE5MTAwMDMDFDIwMjYtMTAtMDRUMjI6MTk6MzRaBAc3NDA4LjAwBQY5NjYuMjY=",
        "receipt_url": f"https://example.supabase.co/storage/v1/object/public/receipts/{HOUSEHOLD_ID}/test.jpg",
        "preview_only": True,
    }
    headers = _make_signed_headers(payload)
    response = client.post("/agent/scan-receipt", content=json.dumps(payload), headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("preview", "success")
    assert data.get("receipt_url") == f"{HOUSEHOLD_ID}/test.jpg"
    assert data["merchant"] == "United Electronics Co. eXtra"


@patch("main.generate_monthly_pdf_statement", create=True)
def test_export_statement_pdf(mock_gen):
    with patch("pdf_statement_generator.generate_monthly_pdf_statement", return_value=b"%PDF-1.4 test"):
        res = client.get(f"/reports/statement-pdf?household_id={HOUSEHOLD_ID}")
        assert res.status_code == 200
        assert res.headers["content-type"] == "application/pdf"
        assert res.content.startswith(b"%PDF")


def test_grocery_price_history_endpoint():
    res = client.get(f"/analytics/price-history?household_id={HOUSEHOLD_ID}")
    assert res.status_code == 200
    data = res.json()
    assert "items" in data
    assert isinstance(data["items"], list)
    assert "count" in data


def test_shopping_basket_optimize_endpoint():
    payload = {
        "household_id": HOUSEHOLD_ID,
        "items": ["Milk", "Bread", "Chicken", "Eggs"],
    }
    res = client.post("/analytics/shopping-basket-optimize", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["items_count"] == 4
    assert data["cheapest_store"] in ["Panda", "Danube", "Tamimi", "Othaim", "Lulu"]
    assert data["cheapest_store_total"] > 0
    assert "store_totals" in data
    assert "split_optimization" in data

@patch("routes.receipts.process_receipt_scan")
def test_scan_receipt_rate_limiting_strict(mock_process):
    from main import _reset_receipt_scan_rate_limits
    _reset_receipt_scan_rate_limits()

    mock_process.return_value = {
        "status": "success",
        "merchant": "Al Meera",
        "amount": 50.0,
        "category_code": "OPEX-GROCERY",
    }

    target_hh = "a0000000-0000-0000-0000-000000000001"
    payload = {
        "image_base64": TINY_PNG_B64,
        "household_id": target_hh,
        "allow_duplicate": True,
    }
    headers = _make_signed_headers(payload)

    # First 10 requests should succeed (200 OK)
    for i in range(10):
        resp = client.post("/agent/scan-receipt", content=json.dumps(payload), headers=headers)
        assert resp.status_code == 200, f"Request {i+1} failed with status {resp.status_code}: {resp.text}"

    # 11th request must fail with 429 Too Many Requests
    blocked_resp = client.post("/agent/scan-receipt", content=json.dumps(payload), headers=headers)
    assert blocked_resp.status_code == 429, f"Expected 429 but got {blocked_resp.status_code}"
    assert "Rate limit exceeded" in blocked_resp.json()["detail"]
    assert "Retry-After" in blocked_resp.headers

    # The window is keyed by the verified user (API-08): the same user cannot reset it by
    # switching household_id, while a different user is not affected.
    other_payload = {
        "image_base64": TINY_PNG_B64,
        "household_id": "b0000000-0000-0000-0000-000000000002",
        "allow_duplicate": True,
    }
    other_headers = _make_signed_headers(other_payload)
    same_user_resp = client.post("/agent/scan-receipt", content=json.dumps(other_payload), headers=other_headers)
    assert same_user_resp.status_code == 429

    import routes.receipts as receipts_routes
    original_user = receipts_routes.get_current_user_id
    receipts_routes.get_current_user_id = lambda request: "00000000-0000-0000-0000-000000000002"
    try:
        other_resp = client.post("/agent/scan-receipt", content=json.dumps(other_payload), headers=other_headers)
    finally:
        receipts_routes.get_current_user_id = original_user
    assert other_resp.status_code == 200

    _reset_receipt_scan_rate_limits()
