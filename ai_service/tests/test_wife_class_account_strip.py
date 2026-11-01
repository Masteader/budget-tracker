"""
Unit & integration tests verifying that wife-class transactions (wife_personal, wife_reimbursable)
always strip account_id to None at the API commit routes (chat & scan-receipt), preventing
any household account debit.
"""
from __future__ import annotations

import base64
import time
from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from jose import jwt

from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

HH = "f860188e-23b5-4749-b180-868c956151a6"
HUSBAND = "00000000-0000-4000-8000-00000000000a"
WIFE = "00000000-0000-4000-8000-00000000000b"
ACC_ID = "a1111111-2222-3333-4444-555555555555"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {
        "sub": sub,
        "aud": "authenticated",
        "iss": ISSUER,
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def _zatca_qr(total="150.00") -> str:
    def tlv(tag: int, val: str) -> bytes:
        b = val.encode("utf-8")
        return bytes([tag, len(b)]) + b

    return base64.b64encode(
        tlv(1, "Panda Supermarket")
        + tlv(2, "300012345600003")
        + tlv(3, "2026-10-04T12:00:00Z")
        + tlv(4, total)
        + tlv(5, "19.57")
    ).decode()


@pytest.fixture()
def family(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
    ])
    fake_supabase.seed("household_memberships", [
        {"user_id": HUSBAND, "financial_role": "provider", "household_id": HH, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": WIFE, "financial_role": "spouse", "household_id": HH, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND, "household_type": "family"},
    ])
    fake_supabase.seed("accounts", [
        {"id": ACC_ID, "household_id": HH, "name": "Rajhi Main", "account_type": "checking", "balance": 5000.0, "currency": "SAR", "is_shared_pool": True, "is_archived": False},
    ])
    return fake_supabase


def _last_tx(fake):
    return fake.tables["transactions"][-1]


def test_chat_transaction_wife_personal_strips_account_id(family):
    body = {
        "household_id": HH,
        "message": "اشتريت فستان بـ 200 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "wife_personal",
        "account_id": ACC_ID,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_personal"
    assert tx.get("account_id") is None


def test_chat_transaction_wife_reimbursable_strips_account_id(family):
    body = {
        "household_id": HH,
        "message": "دفعت مقاضي البيت 350 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "wife_reimbursable",
        "account_id": ACC_ID,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_reimbursable"
    assert tx.get("account_id") is None


def test_scan_receipt_wife_personal_strips_account_id(family):
    body = {
        "household_id": HH,
        "qr_code_raw": _zatca_qr(),
        "allow_duplicate": True,
        "nafaqah_class": "wife_personal",
        "account_id": ACC_ID,
    }
    with patch("receipt_scanner.fetch_budget", return_value=None):
        resp = client.post("/agent/scan-receipt", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_personal"
    assert tx.get("account_id") is None


def test_scan_receipt_wife_reimbursable_strips_account_id(family):
    body = {
        "household_id": HH,
        "qr_code_raw": _zatca_qr(),
        "allow_duplicate": True,
        "nafaqah_class": "wife_reimbursable",
        "account_id": ACC_ID,
    }
    with patch("receipt_scanner.fetch_budget", return_value=None):
        resp = client.post("/agent/scan-receipt", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_reimbursable"
    assert tx.get("account_id") is None


def test_chat_transaction_husband_preserves_account_id(family):
    body = {
        "household_id": HH,
        "message": "بنزين 100 ريال",
        "allow_duplicate": True,
        "account_id": ACC_ID,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx.get("account_id") == ACC_ID


def test_chat_transaction_derived_wife_class_strips_account_id(family):
    body = {
        "household_id": HH,
        "message": "مقاضي البيت 350 ريال",
        "allow_duplicate": True,
        "paid_by": "partner",
        "beneficiary": "both",
        "nafaqah_spouse_id": WIFE,
        "account_id": ACC_ID,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_reimbursable"
    assert tx.get("account_id") is None


def test_scan_receipt_derived_wife_class_strips_account_id(family):
    body = {
        "household_id": HH,
        "qr_code_raw": _zatca_qr(),
        "allow_duplicate": True,
        "paid_by": "partner",
        "beneficiary": "both",
        "nafaqah_spouse_id": WIFE,
        "account_id": ACC_ID,
    }
    with patch("receipt_scanner.fetch_budget", return_value=None):
        resp = client.post("/agent/scan-receipt", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_reimbursable"
    assert tx.get("account_id") is None
