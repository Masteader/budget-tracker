"""
FABLE-API-06 (docs/review/audit/fable_review.md): free-text overrides were stored verbatim with no
length limit (up to ~24 MiB per row). Now merchant <= 120, sub_category / beneficiary / paid_by
<= 60 characters (422 otherwise), and qr_code_raw (<= 4096) is persisted only when it decodes as a
ZATCA TLV code.
"""
from __future__ import annotations

import base64

import pytest
from fastapi.testclient import TestClient

from fable_world import PNG_1x1, World, fake_llm, zatca_qr


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase):
    return World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})


@pytest.mark.parametrize("field,size", [("merchant", 121), ("beneficiary", 61), ("sub_category", 61),
                                        ("merchant", 400_000), ("paid_by", 61), ("category_code", 101)])
def test_chat_overrides_are_bounded(api, fake_supabase, w, field, size):
    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": "Coffee 16 sar", field: "M" * size}, headers=w.hdr("omar"))
    assert r.status_code == 422, r.text[:300]
    assert not fake_supabase.tables.get("transactions")


def test_chat_overrides_must_be_text(api, w):
    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": "Coffee 16 sar", "merchant": {"a": 1}}, headers=w.hdr("omar"))
    assert r.status_code == 422


def test_chat_overrides_at_the_limit_are_stored(api, fake_supabase, w):
    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": "Coffee 16 sar", "merchant": "M" * 120,
                       "beneficiary": "B" * 60}, headers=w.hdr("omar"))
    assert r.status_code == 200, r.text
    row = fake_supabase.tables["transactions"][0]
    assert len(row["merchant"]) == 120 and len(row["beneficiary_id"]) == 60


@pytest.mark.parametrize("body", [{"merchant": "X" * 121}, {"qr_code_raw": "Q" * 4097}, {"beneficiary": "B" * 61},
                                  {"paid_by": "P" * 61}])
def test_receipt_overrides_are_bounded(api, fake_supabase, w, monkeypatch, body):
    fake_llm(monkeypatch, {"merchant": "Tamimi", "total_amount": 55.5, "category_code": "OPEX-GROCERY",
                           "items": [{"name": "milk", "quantity": 1, "price": 55.5}]})
    r = api.post("/agent/scan-receipt",
                 json={"household_id": w.hid, "images_base64": [base64.b64encode(PNG_1x1).decode()], **body},
                 headers=w.hdr("omar"))
    assert r.status_code == 422, r.text[:300]
    assert not fake_supabase.tables.get("transactions")


def test_receipt_qr_code_raw_is_kept_only_when_it_decodes(api, fake_supabase, w, monkeypatch):
    # The in-memory budgets table has no generated remaining_amount column; budgets are not under test.
    monkeypatch.setattr("receipt_scanner.fetch_budget", lambda *_a, **_k: None)
    fake_llm(monkeypatch, {"merchant": "Tamimi", "total_amount": 55.5, "category_code": "OPEX-GROCERY",
                           "items": [{"name": "milk", "quantity": 1, "price": 55.5}]})
    image = base64.b64encode(PNG_1x1).decode()
    r = api.post("/agent/scan-receipt",
                 json={"household_id": w.hid, "images_base64": [image], "qr_code_raw": "Q" * 4000},
                 headers=w.hdr("omar"))
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    assert r.json()["qr_code_raw"] is None
    assert fake_supabase.tables["transactions"][0].get("qr_code_raw") is None

    good = zatca_qr("55.50", seller="Tamimi", vat="7.24")
    r = api.post("/agent/scan-receipt",
                 json={"household_id": w.hid, "images_base64": [image], "qr_code_raw": good, "allow_duplicate": True},
                 headers=w.hdr("omar"))
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    assert fake_supabase.tables["transactions"][-1]["qr_code_raw"] == good


def test_model_text_is_bounded_too(monkeypatch):
    """LLM output is not trusted either: the parsed beneficiary/sub-category are cut to 60."""
    from chat_parser import ParsedChatExpense

    parsed = ParsedChatExpense(merchant="x", total_amount=1, beneficiary="B" * 500, sub_category="S" * 500)
    assert len(parsed.beneficiary) == 60 and len(parsed.sub_category) == 60
