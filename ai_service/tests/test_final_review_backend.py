"""
Final backend review (docs/review/audit/final_review_backend.md), FR-B findings.

The in-memory fake runs with the real ``public.transactions`` column list (live and the local
rebuild agree; see docs/review/audit/live_db_preflight.md, MOB-03: there is no ``paid_by`` /
``beneficiary`` / ``notes`` column), so a query naming a column that does not exist fails here
the way PostgREST fails in production instead of silently succeeding.

Requests carry real HS256 JWTs (this module is excluded from the conftest auth mock), so
membership and admin checks are real.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone
from decimal import Decimal
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from jose import jwt

from fakes import FakeSchemaError
from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

# public.transactions columns on live and in the local rebuild (information_schema order).
TRANSACTION_COLUMNS = {
    "id", "household_id", "user_id", "amount", "currency", "merchant", "category_code", "timestamp",
    "raw_sms", "is_reallocated", "reallocated_from_budget_id", "created_at", "source", "items",
    "receipt_url", "dedup_fingerprint", "spent_by", "sub_category", "cycle_key", "qr_code_raw",
    "beneficiary_type", "beneficiary_id", "is_settlement", "settlement_target_id", "line_items",
    "account_id", "nafaqah_class", "nafaqah_spouse_id",
}

ROOM = "aaaa0000-0000-4000-8000-0000000000f1"
FAMILY = "bbbb0000-0000-4000-8000-0000000000f2"
A = "00000000-0000-4000-8000-0000000000f1"  # roommate admin
B = "00000000-0000-4000-8000-0000000000f2"  # roommate member
C = "00000000-0000-4000-8000-0000000000f3"  # roommate member
OUTSIDER = "00000000-0000-4000-8000-0000000000f9"
HUSBAND = "00000000-0000-4000-8000-0000000000e1"
WIFE = "00000000-0000-4000-8000-0000000000e2"

NOW = datetime.now(timezone.utc).isoformat()

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


@pytest.fixture()
def db(fake_supabase):
    fake_supabase.schemas["transactions"] = set(TRANSACTION_COLUMNS)
    fake_supabase.seed("users", [
        {"id": A, "household_id": ROOM, "role": "admin", "financial_role": "peer", "display_name": "A"},
        {"id": B, "household_id": ROOM, "role": "member", "financial_role": "peer", "display_name": "B"},
        {"id": C, "household_id": ROOM, "role": "member", "financial_role": "peer", "display_name": "C"},
        {"id": HUSBAND, "household_id": FAMILY, "role": "admin", "financial_role": "provider", "display_name": "H"},
        {"id": WIFE, "household_id": FAMILY, "role": "member", "financial_role": "spouse", "display_name": "W"},
    ])
    fake_supabase.seed("household_memberships", [
        {"household_id": ROOM, "user_id": A, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": ROOM, "user_id": B, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"household_id": ROOM, "user_id": C, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": HUSBAND, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"household_id": FAMILY, "user_id": WIFE, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": ROOM, "name": "Room", "payday_day": 27, "owner_user_id": A},
        {"id": FAMILY, "name": "Family", "payday_day": 27, "owner_user_id": HUSBAND},
    ])
    return fake_supabase


def test_strict_fake_rejects_unknown_transaction_columns(db):
    """Guard for the guard: the schema-aware fake really fails on a missing column."""
    with pytest.raises(FakeSchemaError):
        db.table("transactions").select("id, paid_by").execute()
    with pytest.raises(FakeSchemaError):
        db.table("transactions").insert({"household_id": ROOM, "notes": "x"}).execute()


# ─── FR-B-01: roommate settlement recording ───────────────────────────────────

def _settle(payer, recipient, amount=30.0, caller=None):
    return client.post(
        f"/households/{ROOM}/reimbursements",
        headers=bearer(caller or payer),
        json={"household_id": ROOM, "payer_id": payer, "recipient_id": recipient, "amount": amount,
              "payment_method": "stc_pay", "notes": "B paid A"},
    )


def test_roommate_settlement_is_recorded_with_existing_columns(db):
    res = _settle(B, A, 30.0)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "success" and body["is_settlement"] is True
    rows = [t for t in db.tables["transactions"] if t.get("is_settlement")]
    assert len(rows) == 1
    row = rows[0]
    assert set(row) <= TRANSACTION_COLUMNS
    assert row["user_id"] == B  # the verified caller is the creator (DB-18)
    assert row["settlement_target_id"] == A and row["beneficiary_id"] == A
    assert row["category_code"] is None  # a settlement is not spending in any budget category
    assert row["source"] == "manual"
    assert f"PaidBy: {B}" in row["raw_sms"]
    assert Decimal(str(row["amount"])) == Decimal("30.00")


def test_roommate_settlement_parties_must_be_members(db):
    res = _settle(B, OUTSIDER, 10.0)
    assert res.status_code == 400
    assert not db.tables.get("transactions")


def test_roommate_settlement_appears_in_settlement_v2(db):
    # A paid 90 for everyone (chat entry by A); B then pays A back 30.
    db.seed("transactions", [{
        "id": "r1", "household_id": ROOM, "user_id": A, "amount": 90.0, "timestamp": NOW,
        "raw_sms": "Chat: groceries 90 | PaidBy: me | Beneficiary: both | SpentBy: me",
        "beneficiary_type": "household", "is_settlement": False, "line_items": [],
    }])
    before = client.get(f"/households/{ROOM}/settlement-v2", headers=bearer(B), params={"cycle_start": "2000-01-01"})
    assert before.status_code == 200, before.text
    debts = {(d["from_id"], d["to_id"]): d["amount"] for d in before.json()["pairwise_debts"]}
    assert debts == {(B, A): 30.0, (C, A): 30.0}

    assert _settle(B, A, 30.0).status_code == 200
    after = client.get(f"/households/{ROOM}/settlement-v2", headers=bearer(B), params={"cycle_start": "2000-01-01"})
    debts = {(d["from_id"], d["to_id"]): d["amount"] for d in after.json()["pairwise_debts"]}
    assert debts == {(C, A): 30.0}


# ─── FR-B-02: settlement v2 reads only existing columns ───────────────────────

def test_settlement_v2_roommate_debts_use_creator_as_payer(db):
    from settlement_engine import calculate_settlement_v2

    db.seed("transactions", [
        {"id": "r1", "household_id": ROOM, "user_id": B, "amount": 60.0, "timestamp": NOW,
         "raw_sms": "Manual entry", "beneficiary_type": "household", "is_settlement": False},
        {"id": "r2", "household_id": ROOM, "user_id": None, "amount": 99.0, "timestamp": NOW,
         "raw_sms": "legacy row without creator or payer", "beneficiary_type": "household"},
    ])
    res = calculate_settlement_v2(ROOM, cycle_start="2000-01-01")
    assert res["mode"] == "multi_roommate"
    debts = {(d["from_id"], d["to_id"]): d["amount"] for d in res["pairwise_debts"]}
    assert debts == {(A, B): 20.0, (C, B): 20.0}


# ─── FR-B-03: /settlement honours the Nafaqah class on the real schema ───────

def test_partner_settlement_reads_nafaqah_class(db):
    from settlement_engine import calculate_partner_settlement

    db.seed("transactions", [{
        "id": "w1", "household_id": FAMILY, "user_id": WIFE, "amount": 100.0, "timestamp": NOW,
        "category_code": "OPEX-GROCERY", "raw_sms": "Chat: groceries | PaidBy: me | Beneficiary: both",
        "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE,
    }])
    res = calculate_partner_settlement(FAMILY, cycle_start="2000-01-01", caller_user_id=HUSBAND)
    assert res["mode"] == "family_nafaqah"
    # From the husband's point of view his wife paid this shared expense.
    assert res["shared_paid_by_partner"] == 100.0
    assert res["shared_paid_by_me"] == 0.0
    assert res["owed_to_partner"] == 100.0


def test_partner_settlement_counts_recorded_roommate_settlements(db):
    from settlement_engine import calculate_partner_settlement

    db.tables["household_memberships"] = [m for m in db.tables["household_memberships"] if m["user_id"] != C]
    db.seed("transactions", [{
        "id": "g1", "household_id": ROOM, "user_id": A, "amount": 100.0, "timestamp": NOW,
        "category_code": "OPEX-GROCERY", "raw_sms": "Chat: groceries | PaidBy: me | Beneficiary: both",
    }])
    assert _settle(B, A, 50.0).status_code == 200
    res = calculate_partner_settlement(ROOM, cycle_start="2000-01-01", caller_user_id=A)
    assert res["mode"] == "shared_split"
    assert res["total_shared_expenses"] == 100.0  # the settlement is not a shared expense
    assert res["who_owes"] == "settled" and res["net_balance"] == 0.0


def test_recalculate_budgets_ignores_settlements(db):
    from installment_service import InstallmentService
    from salary_cycle import get_cycle_for_date

    key = get_cycle_for_date(payday_day=27)["cycle_key"]
    db.seed("budgets", [{"id": "bm", "household_id": ROOM, "category_code": "OPEX-MISC", "cycle_key": key,
                         "month": f"{key}-01", "allocated_amount": 100.0, "spent_amount": 0.0}])
    assert _settle(B, A, 40.0).status_code == 200
    InstallmentService.recalculate_budgets(ROOM, key)
    assert db.tables["budgets"][0]["spent_amount"] == 0.0


# ─── FR-B-05: budget and category writes are admin-only, as in RLS ──────────

def _budget_writes(household_id):
    return [
        ("post", "/budgets/categories", "add_category_and_budget",
         {"json": {"household_id": household_id, "code": "OPEX-REVIEW", "category": "Review", "allocated_amount": 100}}),
        ("post", "/budgets/sub-allocations", "save_sub_allocations",
         {"json": {"household_id": household_id, "category_code": "OPEX-GROCERY", "sub_allocations": {"sub-veg": 50}}}),
        ("post", "/budgets/sub-categories", "add_sub_category_for_household",
         {"json": {"household_id": household_id, "parent_code": "OPEX-GROCERY", "name_en": "Veg", "allocated_amount": 20}}),
        ("delete", "/budgets/sub-categories", "remove_sub_category_for_household",
         {"params": {"household_id": household_id, "parent_code": "OPEX-GROCERY", "sub_code": "sub-veg"}}),
        ("delete", "/budgets/categories/OPEX-GROCERY", "archive_category_for_household",
         {"params": {"household_id": household_id}}),
    ]


@pytest.mark.parametrize("index", range(5))
def test_members_cannot_write_budgets(db, index):
    method, path, worker, kwargs = _budget_writes(ROOM)[index]
    with patch(f"routes.budgets.{worker}", return_value={"status": "success"}) as work:
        res = getattr(client, method)(path, headers=bearer(B), **kwargs)
    assert res.status_code == 403, res.text
    work.assert_not_called()


@pytest.mark.parametrize("index", range(5))
def test_admins_can_write_budgets(db, index):
    method, path, worker, kwargs = _budget_writes(ROOM)[index]
    with patch(f"routes.budgets.{worker}", return_value={"status": "success"}) as work:
        res = getattr(client, method)(path, headers=bearer(A), **kwargs)
    assert res.status_code == 200, res.text
    work.assert_called_once()


# ─── FR-B-06: budget reallocation goes through the hardened RPC only ─────────

class _DbError(Exception):
    def __init__(self, message, code):
        super().__init__(message)
        self.message, self.code = message, code


def _seed_budgets(fake):
    fake.seed("budgets", [
        {"id": "b-from", "household_id": ROOM, "allocated_amount": 100.0},
        {"id": "b-to", "household_id": ROOM, "allocated_amount": 20.1},
    ])


def test_reallocation_sends_an_exact_two_decimal_amount(db):
    from supabase_client import reallocate_budget

    _seed_budgets(db)

    def rpc(params):  # the 20261020030000 RPC refuses sub-halala amounts with 22023
        if Decimal(str(params["p_amount"])) != Decimal(str(params["p_amount"])).quantize(Decimal("0.01")):
            raise _DbError("Reallocation amount must be positive with at most 2 decimals", "22023")
        return None

    db.rpc_handlers["reallocate_budget"] = rpc
    deficit = 50.3 - 20.1  # 30.199999999999996 in binary floating point
    assert reallocate_budget("b-from", "b-to", deficit) is True
    assert db.rpc_calls[-1] == ("reallocate_budget", {"p_from_id": "b-from", "p_to_id": "b-to", "p_amount": "30.20"})


def test_refused_reallocation_never_falls_back_to_unchecked_updates(db):
    from supabase_client import reallocate_budget

    _seed_budgets(db)

    def rpc(_params):
        raise _DbError("Insufficient allocation: 100.00 available, 500.00 requested", "22000")

    db.rpc_handlers["reallocate_budget"] = rpc
    assert reallocate_budget("b-from", "b-to", 500.0) is False
    assert [b["allocated_amount"] for b in db.tables["budgets"]] == [100.0, 20.1]


def test_chat_marks_reallocation_only_when_it_happened(db):
    from chat_parser import ChatLineItem, ParsedChatExpense, process_chat_transaction
    from models import BudgetRow

    parsed = ParsedChatExpense(merchant="Panda", total_amount=50.0, category_code="OPEX-GROCERY",
                               items=[ChatLineItem(name="milk", price=50.0, quantity=1)], is_transaction=True)
    budget = BudgetRow(id="b-to", household_id=ROOM, month="2026-10-01", category_code="OPEX-GROCERY",
                       allocated_amount=20.0, spent_amount=0.0, remaining_amount=20.0)
    flexible = BudgetRow(id="b-from", household_id=ROOM, month="2026-10-01", category_code="OPEX-DINING",
                         allocated_amount=100.0, spent_amount=0.0, remaining_amount=100.0)
    with patch("chat_parser.parse_chat_expense", return_value=parsed), \
            patch("chat_parser.fetch_budget", return_value=budget), \
            patch("chat_parser.fetch_flexible_budgets", return_value=[flexible]), \
            patch("chat_parser.reallocate_budget", return_value=False), \
            patch("chat_parser.insert_transaction", return_value="tx-1") as insert:
        process_chat_transaction(household_id=ROOM, message="Panda 50", user_id=A, allow_duplicate=True)
    assert insert.call_args.kwargs["is_reallocated"] is False
    assert insert.call_args.kwargs["reallocated_from_budget_id"] is None


# ─── FR-B-07: a commit never drops the Nafaqah class on a lookup failure ─────

def test_commit_fails_instead_of_storing_an_unclassified_family_expense(db):
    import nafaqah_service as ns

    with patch("nafaqah_service.load_family_context", side_effect=RuntimeError("db down")):
        preview = ns.resolve_expense_nafaqah(FAMILY, WIFE, "me", "both", require_spouse=False)
        assert preview["household_mode"] == "not_family"  # a preview may degrade
        with pytest.raises(RuntimeError):
            ns.resolve_expense_nafaqah(FAMILY, WIFE, "me", "both", require_spouse=True)


# ─── FR-B-11: inserts fit the schema; receipts keep who paid ─────────────────

def test_insert_transaction_fits_the_schema_first_time(db, caplog):
    from supabase_client import insert_transaction

    with caplog.at_level("WARNING", logger="supabase_client"):
        tx_id = insert_transaction(
            household_id=ROOM, amount=12.5, currency="SAR", merchant="Cafe", category_code="OPEX-DINING",
            timestamp=NOW, raw_sms="Chat: coffee | PaidBy: me | Beneficiary: both", source="chat",
            paid_by="me", beneficiary="both", user_id=B,
        )
    # No failed first attempt naming the non-existent paid_by / beneficiary columns.
    assert not [r for r in caplog.records if "Insert with initial payload failed" in r.getMessage()]
    row = next(t for t in db.tables["transactions"] if t["id"] == tx_id)
    assert set(row) <= TRANSACTION_COLUMNS and row["user_id"] == B


def test_receipt_commit_records_who_paid_in_the_audit_tags(db, monkeypatch):
    from receipt_scanner import process_receipt_scan

    monkeypatch.setattr("receipt_scanner.parse_receipt_image", lambda *_a, **_k: {
        "merchant": "Panda", "total_amount": 60.0, "items": [{"name": "rice", "quantity": 1, "price": 60.0}],
    })
    monkeypatch.setattr("receipt_scanner.fetch_budget", lambda *_a, **_k: None)
    import base64
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="PNG")
    image = base64.b64encode(buf.getvalue()).decode()
    res = process_receipt_scan(household_id=ROOM, images_base64=[image], user_id=B, allow_duplicate=True,
                               paid_by="partner", beneficiary="both")
    assert res["status"] == "success", res
    row = next(t for t in db.tables["transactions"] if t["id"] == res["transaction_id"])
    assert "PaidBy: partner" in row["raw_sms"] and "Beneficiary: both" in row["raw_sms"]


# ─── FR-B-09: one LiteLLM model default for every module ─────────────────────

def test_every_llm_call_uses_the_same_default_model(monkeypatch):
    import re
    from pathlib import Path

    import utils

    root = Path(__file__).resolve().parent.parent
    env_example = (root / ".env.example").read_text(encoding="utf-8")
    assert f"LITELLM_MODEL={utils.DEFAULT_LITELLM_MODEL}" in env_example
    compose = (root / "docker-compose.yml").read_text(encoding="utf-8")
    assert f"LITELLM_MODEL:-{utils.DEFAULT_LITELLM_MODEL}" in compose
    for name in ("chat_parser.py", "receipt_scanner.py", "support_agent.py"):
        source = (root / name).read_text(encoding="utf-8")
        # No module carries its own fallback model string any more.
        assert not re.search(r"LITELLM_MODEL\"\s*,\s*\"", source), name
        assert "litellm_model()" in source, name

    monkeypatch.delenv("LITELLM_MODEL", raising=False)
    assert utils.litellm_model() == utils.DEFAULT_LITELLM_MODEL
    monkeypatch.setenv("LITELLM_MODEL", "  gemini/override  ")
    assert utils.litellm_model() == "gemini/override"


def test_partner_settlement_tags_are_relative_to_the_creator(db):
    """'PaidBy: me' written by A means A paid: B must see that they owe, not that A owes them."""
    from settlement_engine import calculate_partner_settlement

    db.tables["household_memberships"] = [m for m in db.tables["household_memberships"] if m["user_id"] != C]
    db.seed("transactions", [{
        "id": "g1", "household_id": ROOM, "user_id": A, "amount": 100.0, "timestamp": NOW,
        "category_code": "OPEX-GROCERY", "raw_sms": "Chat: groceries | PaidBy: me | Beneficiary: both",
    }])
    a_view = calculate_partner_settlement(ROOM, cycle_start="2000-01-01", caller_user_id=A)
    b_view = calculate_partner_settlement(ROOM, cycle_start="2000-01-01", caller_user_id=B)
    assert a_view["who_owes"] == "partner_owes_me" and a_view["settlement_amount"] == 50.0
    assert b_view["who_owes"] == "me_owes_partner" and b_view["settlement_amount"] == 50.0
