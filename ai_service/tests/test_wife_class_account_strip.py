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
        {"id": "b2222222-2222-3333-4444-555555555555", "household_id": "99999999-9999-4999-8999-999999999999", "name": "Foreign Account", "account_type": "checking", "balance": 1000.0, "currency": "SAR", "is_shared_pool": False, "is_archived": False},
        {"id": "c3333333-2222-3333-4444-555555555555", "household_id": HH, "name": "Wife Personal", "account_type": "checking", "balance": 1500.0, "currency": "SAR", "owner_user_id": WIFE, "is_shared_pool": False, "is_archived": False},
        {"id": "d4444444-2222-3333-4444-555555555555", "household_id": HH, "name": "Husband Personal", "account_type": "checking", "balance": 3000.0, "currency": "SAR", "owner_user_id": HUSBAND, "is_shared_pool": False, "is_archived": False},
        {"id": "e5555555-2222-3333-4444-555555555555", "household_id": HH, "name": "Archived Account", "account_type": "checking", "balance": 1000.0, "currency": "SAR", "owner_user_id": HUSBAND, "is_shared_pool": False, "is_archived": True},
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


FOREIGN_ACC = "b2222222-2222-3333-4444-555555555555"
WIFE_PERSONAL_ACC = "c3333333-2222-3333-4444-555555555555"
HUSBAND_PERSONAL_ACC = "d4444444-2222-3333-4444-555555555555"
ARCHIVED_ACC = "e5555555-2222-3333-4444-555555555555"


def test_chat_rejects_foreign_household_account(family):
    body = {
        "household_id": HH,
        "message": "بنزين 50 ريال",
        "allow_duplicate": True,
        "account_id": FOREIGN_ACC,
    }
    tx_count_before = len(family.tables.get("transactions", []))
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 403, resp.text
    assert len(family.tables.get("transactions", [])) == tx_count_before


def test_scan_rejects_other_members_personal_account(family):
    body = {
        "household_id": HH,
        "qr_code_raw": _zatca_qr(),
        "allow_duplicate": True,
        "account_id": WIFE_PERSONAL_ACC,
    }
    with patch("receipt_scanner.fetch_budget", return_value=None):
        resp = client.post("/agent/scan-receipt", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 403, resp.text


def test_scan_rejects_non_uuid_account_id(family):
    body = {
        "household_id": HH,
        "qr_code_raw": _zatca_qr(),
        "allow_duplicate": True,
        "account_id": "not-a-uuid",
    }
    with patch("receipt_scanner.fetch_budget", return_value=None):
        resp = client.post("/agent/scan-receipt", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 422, resp.text


def test_chat_allows_own_personal_account(family):
    body = {
        "household_id": HH,
        "message": "بنزين 50 ريال",
        "allow_duplicate": True,
        "account_id": HUSBAND_PERSONAL_ACC,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx.get("account_id") == HUSBAND_PERSONAL_ACC



def test_chat_transaction_wife_personal_with_wife_personal_account_kept(family):
    body = {
        "household_id": HH,
        "message": "اشتريت فستان بـ 200 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "wife_personal",
        "account_id": WIFE_PERSONAL_ACC,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    assert resp.json()["account_id"] == WIFE_PERSONAL_ACC
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == "wife_personal"
    assert tx.get("account_id") == WIFE_PERSONAL_ACC


def test_member_cannot_debit_shared_pool(family):
    body = {
        "household_id": HH,
        "message": "غداء 100 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "none",
        "account_id": ACC_ID,
    }
    tx_count_before = len(family.tables.get("transactions", []))
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 403, resp.text
    assert len(family.tables.get("transactions", [])) == tx_count_before


def test_archived_account_rejected(family):
    body = {
        "household_id": HH,
        "message": "بنزين 50 ريال",
        "allow_duplicate": True,
        "account_id": ARCHIVED_ACC,
    }
    tx_count_before = len(family.tables.get("transactions", []))
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 403, resp.text
    assert len(family.tables.get("transactions", [])) == tx_count_before


def test_chat_success_returns_stored_account_id_none_for_household_account_wife_class(family):
    body = {
        "household_id": HH,
        "message": "فستان 200 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "wife_personal",
        "account_id": ACC_ID,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    assert resp.json()["account_id"] is None


def test_scan_receipt_success_returns_stored_account_id_none_for_household_account_wife_class(family):
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
    assert resp.json()["account_id"] is None


def test_insert_never_updates_account_balance_directly(family):
    from supabase_client import insert_transaction
    bal_before = [a["balance"] for a in family.tables["accounts"] if a["id"] == ACC_ID][0]
    tx_id = insert_transaction(
        household_id=HH,
        amount=100.0,
        currency="SAR",
        merchant="Gas",
        category_code="OPEX-FUEL",
        timestamp="2026-10-01T12:00:00Z",
        notes="Fuel",
        account_id=ACC_ID,
        user_id=HUSBAND,
    )
    assert tx_id is not None
    acc_after = [a["balance"] for a in family.tables["accounts"] if a["id"] == ACC_ID][0]
    assert acc_after == bal_before


def test_member_expense_without_account_id_is_not_linked_to_shared_pool(family):
    shared_bal_before = [a["balance"] for a in family.tables["accounts"] if a["id"] == ACC_ID][0]
    body = {
        "household_id": HH,
        "message": "غداء 80 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "none",
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(WIFE), json=body)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx.get("account_id") != ACC_ID
    assert tx.get("account_id") == "c3333333-2222-3333-4444-555555555555"
    shared_bal_after = [a["balance"] for a in family.tables["accounts"] if a["id"] == ACC_ID][0]
    assert shared_bal_after == shared_bal_before


def test_husband_cannot_debit_wife_personal_account_without_spouse_id(family):
    wife_acc = "c3333333-2222-3333-4444-555555555555"
    tx_count_before = len(family.tables.get("transactions", []))
    body = {
        "household_id": HH,
        "message": "عطر 300 ريال",
        "allow_duplicate": True,
        "nafaqah_class": "wife_personal",
        "account_id": wife_acc,
    }
    with patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline")), patch("chat_parser.fetch_budget", return_value=None):
        resp = client.post("/agent/chat-transaction", headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 403, resp.text
    assert len(family.tables.get("transactions", [])) == tx_count_before
