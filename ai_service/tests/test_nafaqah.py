"""
Islamic family Nafaqah rules (owner decision on audit item UI-24).

1. Shared family expenses are the husband's Nafaqah: never split between spouses.
2. Wife pays from her own money for something shared (household / children / dependents)
   -> 'wife_reimbursable' -> the husband owes her; partial or full reimbursements reduce it,
   overpayment is rejected.
3. Personal purchase for the wife -> 'wife_personal' -> charged to her per-cycle allowance;
   overspend shows as negative remaining and is never blocked.
4. Husband-paid shared expenses are ordinary expenses (no class, no debt).
Roommate households and households without a spouse are unaffected.

Requests in this module carry real HS256 JWTs (excluded from the conftest auth mock) and
household membership is resolved from the in-memory FakeSupabaseClient, so IDOR checks are real.
"""

from __future__ import annotations

import time
from decimal import Decimal
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from jose import jwt

import nafaqah_service as ns
from main import app
from settlement_engine import calculate_family_nafaqah, calculate_roommate_pairwise_debts, calculate_settlement_v2

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

HH = "f860188e-23b5-4749-b180-868c956151a6"
HH_OTHER = "bbbbbbbb-0000-4000-8000-000000000002"
HH_ROOM = "cccccccc-0000-4000-8000-000000000003"
HUSBAND = "00000000-0000-4000-8000-00000000000a"
WIFE = "00000000-0000-4000-8000-00000000000b"
CHILD = "00000000-0000-4000-8000-00000000000c"
OUTSIDER = "00000000-0000-4000-8000-00000000000d"
OUTSIDER_WIFE = "00000000-0000-4000-8000-00000000000e"
PEER1 = "00000000-0000-4000-8000-0000000000f1"
PEER2 = "00000000-0000-4000-8000-0000000000f2"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def _install_rpcs(fake):
    """Minimal stand-ins for the SECURITY DEFINER RPCs (the DB suite proves the real ones)."""

    def record(params):
        fake.tables.setdefault("spouse_reimbursements", []).append({
            "id": f"r{len(fake.tables.get('spouse_reimbursements', [])) + 1}",
            "household_id": params["p_household_id"],
            "wife_user_id": params["p_wife_user_id"],
            "paid_by_user_id": HUSBAND,
            "amount": params["p_amount"],
            "payment_method": params["p_payment_method"],
            "notes": params.get("p_notes"),
            "recorded_by": params["p_actor_user_id"],
            "created_at": "2026-11-15T10:00:00+00:00",
        })
        return {"success": True, "reimbursement_id": "r-new"}

    def set_allowance(params):
        rows = fake.tables.setdefault("member_allowances", [])
        key = (params["p_household_id"], params["p_member_user_id"], params["p_cycle_key"])
        for r in rows:
            if (r["household_id"], r["member_user_id"], r["cycle_key"]) == key:
                r["amount"] = params["p_amount"]
                break
        else:
            rows.append({"household_id": key[0], "member_user_id": key[1], "cycle_key": key[2],
                         "amount": params["p_amount"], "set_by": params["p_actor_user_id"]})
        return None  # service re-reads the status itself

    fake.rpc_handlers["record_spouse_reimbursement"] = record
    fake.rpc_handlers["set_member_allowance"] = set_allowance


@pytest.fixture()
def family(fake_supabase):
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": CHILD, "household_id": HH, "role": "member", "financial_role": "family_member", "display_name": "Fahad"},
        {"id": OUTSIDER, "household_id": HH_OTHER, "role": "admin", "financial_role": "provider", "display_name": "Omar"},
        {"id": OUTSIDER_WIFE, "household_id": HH_OTHER, "role": "member", "financial_role": "spouse", "display_name": "Huda"},
        {"id": PEER1, "household_id": HH_ROOM, "role": "admin", "financial_role": "peer", "display_name": "Ali"},
        {"id": PEER2, "household_id": HH_ROOM, "role": "member", "financial_role": "peer", "display_name": "Saad"},
    ])
    fake_supabase.seed("household_memberships", [
        {"user_id": HUSBAND, "household_id": HH, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": WIFE, "household_id": HH, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"user_id": CHILD, "household_id": HH, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        {"user_id": OUTSIDER, "household_id": HH_OTHER, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": OUTSIDER_WIFE, "household_id": HH_OTHER, "role": "member", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": PEER1, "household_id": HH_ROOM, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": PEER2, "household_id": HH_ROOM, "role": "member", "created_at": "2026-01-01T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27}, {"id": HH_OTHER, "payday_day": 27}, {"id": HH_ROOM, "payday_day": 27},
    ])
    fake_supabase.seed("transactions", [
        # wife-paid shared (rule 2)
        {"id": "t1", "household_id": HH, "amount": 300.0, "merchant": "Panda", "timestamp": "2026-11-10T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
        {"id": "t2", "household_id": HH, "amount": 200.5, "merchant": "Nahdi (kids)", "timestamp": "2026-11-12T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
        # personal purchases (rule 3)
        {"id": "t3", "household_id": HH, "amount": 400.0, "merchant": "Abaya", "timestamp": "2026-11-05T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE},
        {"id": "t4", "household_id": HH, "amount": 1300.0, "merchant": "Perfume", "timestamp": "2026-11-20T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE},
        {"id": "t5", "household_id": HH, "amount": 99.0, "merchant": "Salon", "timestamp": "2026-12-01T09:00:00+00:00",
         "cycle_key": "2026-12", "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE},
        # husband-paid shared (rule 4): no class
        {"id": "t6", "household_id": HH, "amount": 950.0, "merchant": "Rent", "timestamp": "2026-11-03T09:00:00+00:00",
         "cycle_key": "2026-11"},
        # another household's wife advance must never leak in
        {"id": "t7", "household_id": HH_OTHER, "amount": 777.0, "merchant": "Other", "timestamp": "2026-11-03T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": OUTSIDER_WIFE},
    ])
    _install_rpcs(fake_supabase)
    return fake_supabase


# ─── Pure rules ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("role,paid_by,beneficiary,expected", [
    # recorded by the wife
    ("wife", "me", "me", ns.WIFE_PERSONAL),
    ("wife", "me", "both", ns.WIFE_REIMBURSABLE),
    ("wife", "me", "household", ns.WIFE_REIMBURSABLE),
    ("wife", "me", "children", ns.WIFE_REIMBURSABLE),
    ("wife", "me", "Sarah", ns.WIFE_REIMBURSABLE),        # a child / dependent by name
    ("wife", "me", "partner", ns.WIFE_REIMBURSABLE),      # bought for the husband
    ("wife", "partner", "both", None),                    # husband paid shared: rule 4
    ("wife", "partner", "me", None),                      # husband bought for her: his Nafaqah, not her allowance
    # recorded by the husband
    ("husband", "me", "both", None),
    ("husband", "me", "me", None),
    ("husband", "me", "partner", None),                   # husband bought for his wife: his Nafaqah
    ("husband", "partner", "both", ns.WIFE_REIMBURSABLE),
    ("husband", "partner", "children", ns.WIFE_REIMBURSABLE),
    ("husband", "partner", "partner", ns.WIFE_PERSONAL),
    # anyone else, or not a family household
    ("member", "me", "both", None),
    (None, "me", "me", None),
])
def test_classify_nafaqah(role, paid_by, beneficiary, expected):
    assert ns.classify_nafaqah(role, paid_by, beneficiary) == expected


def test_tabarru_is_opt_in_only():
    assert ns.classify_nafaqah("wife", "me", "both", is_tabarru=True) is None
    assert ns.classify_nafaqah("wife", "me", "both") == ns.WIFE_REIMBURSABLE


def test_balance_uses_exact_halala_arithmetic():
    bal = ns.compute_reimbursement_balance([0.1, 0.2], [0.3])
    assert bal["gross_advanced"] == 0.3 and bal["reimbursed"] == 0.3
    assert bal["outstanding"] == 0.0 and bal["overpaid"] == 0.0
    bal = ns.compute_reimbursement_balance([100, "0.01"], [])
    assert bal["outstanding"] == 100.01


def test_allowance_overspend_is_negative_not_blocked():
    st = ns.compute_allowance_status(Decimal("1500"), [400, 1300])
    assert st == {"is_set": True, "allocated": 1500.0, "spent": 1700.0, "remaining": -200.0, "transaction_count": 2}
    assert ns.compute_allowance_status(None, [99])["remaining"] == -99.0


# ─── Family context ───────────────────────────────────────────────────────────

def test_family_context_roles(family):
    ctx = ns.load_family_context(HH)
    assert ctx.is_family and ctx.husband_id == HUSBAND
    assert [w["id"] for w in ctx.wives] == [WIFE]
    assert ctx.role_of(WIFE) == "wife" and ctx.role_of(HUSBAND) == "husband" and ctx.role_of(CHILD) == "member"
    assert ctx.role_of(OUTSIDER) is None


def test_admin_wife_is_not_taken_for_husband(family):
    for m in family.tables["household_memberships"]:
        if m["household_id"] == HH:
            m["role"] = "admin" if m["user_id"] == WIFE else "member"
    assert ns.load_family_context(HH).husband_id == HUSBAND


def test_roommate_household_is_not_family(family):
    ctx = ns.load_family_context(HH_ROOM)
    assert not ctx.is_family and ctx.husband_id is None and ctx.wives == []


# ─── Reimbursement ledger ─────────────────────────────────────────────────────

def test_ledger_counts_only_this_wifes_shared_advances(family):
    ledger = ns.get_reimbursement_ledger(ns.load_family_context(HH), WIFE)
    assert ledger["balance"]["gross_advanced"] == 500.5
    assert ledger["balance"]["outstanding"] == 500.5
    assert {h["id"] for h in ledger["history"]} == {"t1", "t2"}
    assert all(h["type"] == "advance" for h in ledger["history"])


def test_partial_then_full_reimbursement(family):
    ctx = ns.load_family_context(HH)
    res = ns.record_reimbursement(ctx, HUSBAND, WIFE, Decimal("200"), "stc_pay", "partial")
    assert res["outstanding_after"] == 300.5
    name, params = family.rpc_calls[-1]
    assert name == "record_spouse_reimbursement"
    assert params["p_actor_user_id"] == HUSBAND and params["p_amount"] == 200.0

    # the wife confirms the rest
    res = ns.record_reimbursement(ctx, WIFE, WIFE, Decimal("300.50"), "cash", None)
    assert res["outstanding_after"] == 0.0
    ledger = ns.get_reimbursement_ledger(ctx, WIFE)
    assert ledger["balance"]["reimbursed"] == 500.5 and ledger["balance"]["outstanding"] == 0.0
    assert [h["type"] for h in ledger["history"]].count("reimbursement") == 2

    with pytest.raises(ns.OverpaymentError):
        ns.record_reimbursement(ctx, HUSBAND, WIFE, Decimal("0.01"), "cash", None)


def test_overpayment_is_rejected_before_the_database(family):
    calls = len(family.rpc_calls)
    with pytest.raises(ns.OverpaymentError):
        ns.record_reimbursement(ns.load_family_context(HH), HUSBAND, WIFE, Decimal("500.51"), "cash", None)
    assert len(family.rpc_calls) == calls


def test_database_overpayment_error_is_mapped(family):
    class FakeApiError(Exception):
        code = "22023"

    def racing(_params):
        raise FakeApiError("Reimbursement of 100 exceeds the outstanding balance of 50")

    family.rpc_handlers["record_spouse_reimbursement"] = racing
    with pytest.raises(ns.OverpaymentError):
        ns.record_reimbursement(ns.load_family_context(HH), HUSBAND, WIFE, Decimal("100"), "cash", None)


def test_only_husband_wife_or_admin_record_reimbursements(family):
    with pytest.raises(ns.NafaqahForbidden):
        ns.record_reimbursement(ns.load_family_context(HH), CHILD, WIFE, Decimal("10"), "cash", None)


def test_reimbursement_requires_family_household(family):
    with pytest.raises(ns.NotFamilyHousehold):
        ns.record_reimbursement(ns.load_family_context(HH_ROOM), PEER1, PEER2, Decimal("10"), "cash", None)


def test_wife_of_another_household_is_rejected(family):
    with pytest.raises(ns.InvalidNafaqahRequest):
        ns.get_reimbursement_ledger(ns.load_family_context(HH), OUTSIDER_WIFE)


# ─── Allowance ────────────────────────────────────────────────────────────────

def test_allowance_set_by_husband_and_overspend_shown(family):
    ctx = ns.load_family_context(HH)
    st = ns.set_allowance(ctx, HUSBAND, WIFE, Decimal("1500"), "2026-11")
    assert st == {"household_id": HH, "member_user_id": WIFE, "cycle_key": "2026-11", "is_set": True,
                  "allocated": 1500.0, "spent": 1700.0, "remaining": -200.0, "transaction_count": 2}
    name, params = family.rpc_calls[-1]
    assert name == "set_member_allowance" and params["p_actor_user_id"] == HUSBAND
    # next cycle: not set yet, the 99 SAR purchase already counts
    st = ns.get_allowance(ctx, WIFE, "2026-12")
    assert st["is_set"] is False and st["spent"] == 99.0 and st["remaining"] == -99.0


def test_wife_and_ordinary_members_cannot_set_allowance(family):
    ctx = ns.load_family_context(HH)
    for actor in (WIFE, CHILD):
        with pytest.raises(ns.NafaqahForbidden):
            ns.set_allowance(ctx, actor, WIFE, Decimal("100"), "2026-11")


def test_allowance_defaults_to_current_cycle(family):
    with patch("nafaqah_service.current_cycle_key", return_value="2026-11"):
        st = ns.get_allowance(ns.load_family_context(HH), WIFE, None)
    assert st["cycle_key"] == "2026-11" and st["spent"] == 1700.0


def test_invalid_cycle_key_rejected(family):
    with pytest.raises(ns.InvalidNafaqahRequest):
        ns.get_allowance(ns.load_family_context(HH), WIFE, "2026-13")


# ─── HTTP API (real JWT + membership) ────────────────────────────────────────

def test_summary_for_wife(family):
    with patch("nafaqah_service.current_cycle_key", return_value="2026-11"):
        resp = client.get(f"/households/{HH}/nafaqah", headers=bearer(WIFE))
    assert resp.status_code == 200
    body = resp.json()
    assert body["mode"] == "family_nafaqah" and body["caller_role"] == "wife"
    assert body["husband"]["id"] == HUSBAND
    wife = body["wives"][0]
    assert wife["id"] == WIFE and wife["reimbursement"]["outstanding"] == 500.5
    assert wife["allowance"]["spent"] == 1700.0 and wife["allowance"]["cycle_key"] == "2026-11"
    assert body["can_set_allowance"] is False and body["can_record_reimbursement"] is True


def test_summary_for_husband_can_set_allowance(family):
    resp = client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND))
    assert resp.status_code == 200
    assert resp.json()["caller_role"] == "husband" and resp.json()["can_set_allowance"] is True


def test_summary_requires_membership(family):
    assert client.get(f"/households/{HH}/nafaqah", headers=bearer(OUTSIDER)).status_code == 403
    assert client.get(f"/households/{HH}/nafaqah").status_code == 401


def test_summary_for_roommates_is_not_family(family):
    resp = client.get(f"/households/{HH_ROOM}/nafaqah", headers=bearer(PEER1))
    assert resp.status_code == 200
    assert resp.json()["mode"] == "not_family" and resp.json()["wives"] == []


def test_record_reimbursement_endpoint(family):
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                       json={"amount": 200, "payment_method": "stc_pay"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["outstanding_after"] == 300.5
    # overpayment
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                       json={"amount": 300.51, "payment_method": "cash"})
    assert resp.status_code == 409
    # sub-halala, zero and negative amounts
    for bad in (10.005, 0, -5):
        resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                           json={"amount": bad, "payment_method": "cash"})
        assert resp.status_code == 422
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                       json={"amount": 1, "payment_method": "bitcoin"})
    assert resp.status_code == 422


def test_record_reimbursement_idor(family):
    # an outsider cannot touch this household
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(OUTSIDER),
                       json={"amount": 10, "payment_method": "cash", "wife_user_id": WIFE})
    assert resp.status_code == 403
    # a member cannot target another household's wife through their own household
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                       json={"amount": 10, "payment_method": "cash", "wife_user_id": OUTSIDER_WIFE})
    assert resp.status_code == 422
    # an ordinary member cannot record
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(CHILD),
                       json={"amount": 10, "payment_method": "cash"})
    assert resp.status_code == 403
    assert "spouse_reimbursements" not in family.tables


def test_reimbursement_in_roommate_household_is_conflict(family):
    resp = client.post(f"/households/{HH_ROOM}/nafaqah/reimbursements", headers=bearer(PEER1),
                       json={"amount": 10, "payment_method": "cash", "wife_user_id": PEER2})
    assert resp.status_code == 409


def test_reimbursement_history_endpoint(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert resp.status_code == 200
    assert resp.json()["balance"]["outstanding"] == 500.5
    assert len(resp.json()["history"]) == 2


def test_allowance_endpoints(family):
    resp = client.put(f"/households/{HH}/nafaqah/allowance", headers=bearer(HUSBAND),
                      json={"amount": 1500, "cycle_key": "2026-11"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["remaining"] == -200.0
    resp = client.put(f"/households/{HH}/nafaqah/allowance", headers=bearer(WIFE),
                      json={"amount": 5000, "cycle_key": "2026-11"})
    assert resp.status_code == 403
    resp = client.put(f"/households/{HH}/nafaqah/allowance", headers=bearer(HUSBAND),
                      json={"amount": -1, "cycle_key": "2026-11"})
    assert resp.status_code == 422
    resp = client.get(f"/households/{HH}/nafaqah/allowance", headers=bearer(WIFE), params={"cycle_key": "2026-11"})
    assert resp.status_code == 200 and resp.json()["allocated"] == 1500.0
    resp = client.get(f"/households/{HH}/nafaqah/allowance", headers=bearer(OUTSIDER), params={"cycle_key": "2026-11"})
    assert resp.status_code == 403


def test_legacy_reimbursement_route_uses_nafaqah_ledger_in_family_mode(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": "wife", "amount": 100, "payment_method": "cash",
    })
    assert resp.status_code == 200, resp.text
    assert family.tables["spouse_reimbursements"][0]["amount"] == 100.0
    assert not any(t.get("is_settlement") for t in family.tables["transactions"])


# ─── Settlement engines: rule 1 and roommates unchanged ─────────────────────

def test_family_engine_honours_nafaqah_class():
    txs = [
        {"amount": 300.0, "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
        {"amount": 120.0, "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE},
        {"amount": 950.0, "paid_by": HUSBAND, "beneficiary_type": "household"},
    ]
    res = calculate_family_nafaqah(txs, husband_id=HUSBAND, wife_id=WIFE)
    assert res["wife_reimbursement_owed"] == 300.0
    assert res["spent_on_wife"] == 120.0
    assert res["family_general_total"] == 1250.0


def test_roommate_split_unchanged_by_nafaqah_columns():
    txs = [{"amount": 90.0, "paid_by": "a", "beneficiary_type": "all_peers", "nafaqah_class": None}]
    assert calculate_roommate_pairwise_debts(txs, ["a", "b", "c"]) == [
        {"from_id": "b", "to_id": "a", "amount": 30.0},
        {"from_id": "c", "to_id": "a", "amount": 30.0},
    ]


def test_settlement_v2_roommates_still_multi_roommate(family):
    res = calculate_settlement_v2(HH_ROOM, cycle_start="2000-01-01")
    assert res["mode"] == "multi_roommate" and res["family_summary"] is None


# ─── Chat ingestion classification ───────────────────────────────────────────

def _llm_down():
    return patch("chat_parser.litellm.completion", side_effect=RuntimeError("offline"))


def _chat(user, message, household=HH, **extra):
    body = {"household_id": household, "message": message, "allow_duplicate": True}
    body.update(extra)
    with _llm_down(), patch("chat_parser.fetch_budget", return_value=None):
        return client.post("/agent/chat-transaction", headers=bearer(user), json=body)


def _last_tx(fake):
    return fake.tables["transactions"][-1]


def test_chat_wife_personal_purchase_goes_to_allowance(family):
    resp = _chat(WIFE, "اشتريت لنفسي عطر بـ 250 ريال")
    assert resp.status_code == 200, resp.text
    assert resp.json()["nafaqah_class"] == ns.WIFE_PERSONAL
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == ns.WIFE_PERSONAL and tx["nafaqah_spouse_id"] == WIFE


@pytest.mark.parametrize("message", [
    "دفعت فاتورة البيت 300 ريال",
    "اشتريت أغراض البيت من بنده بـ 180 ريال",
    "اشتريت ملابس للعيال بـ 220 ريال",
])
def test_chat_wife_shared_payment_is_husband_debt(family, message):
    resp = _chat(WIFE, message)
    assert resp.status_code == 200, resp.text
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == ns.WIFE_REIMBURSABLE and tx["nafaqah_spouse_id"] == WIFE


def test_chat_husband_paying_household_is_plain_expense(family):
    resp = _chat(HUSBAND, "دفعت فاتورة البيت 300 ريال")
    assert resp.status_code == 200
    tx = _last_tx(family)
    assert tx.get("nafaqah_class") is None and tx.get("nafaqah_spouse_id") is None


def test_chat_husband_records_wife_paid_shared(family):
    resp = _chat(HUSBAND, "دفعت زوجتي مقاضي البيت 150 ريال")
    assert resp.status_code == 200
    tx = _last_tx(family)
    assert tx["nafaqah_class"] == ns.WIFE_REIMBURSABLE and tx["nafaqah_spouse_id"] == WIFE


def test_chat_roommates_never_classified(family):
    resp = _chat(PEER1, "اشتريت لنفسي عطر بـ 250 ريال", household=HH_ROOM)
    assert resp.status_code == 200
    tx = _last_tx(family)
    assert tx.get("nafaqah_class") is None


def test_chat_preview_suggests_and_override_wins(family):
    resp = _chat(WIFE, "دفعت فاتورة البيت 300 ريال", preview_only=True)
    assert resp.status_code == 200
    body = resp.json()
    assert body["nafaqah_class"] == ns.WIFE_REIMBURSABLE
    assert body["household_mode"] == "family_nafaqah" and body["recorder_role"] == "wife"

    resp = _chat(WIFE, "دفعت فاتورة البيت 300 ريال", nafaqah_class="wife_personal")
    assert _last_tx(family)["nafaqah_class"] == ns.WIFE_PERSONAL
    resp = _chat(WIFE, "دفعت فاتورة البيت 300 ريال", nafaqah_class="none")
    assert _last_tx(family).get("nafaqah_class") is None
    resp = _chat(WIFE, "دفعت فاتورة البيت 300 ريال", nafaqah_class="split_50_50")
    assert resp.status_code == 422


# ─── Further edge cases ───────────────────────────────────────────────────────

@pytest.mark.parametrize("bad", ["10.005", "-1", "NaN", "abc", "1000000000000"])
def test_parse_sar_amount_rejects_bad_input(bad):
    with pytest.raises(ns.InvalidNafaqahRequest):
        ns.parse_sar_amount(bad, allow_zero=False)


def test_parse_sar_amount_zero_only_where_allowed():
    assert ns.parse_sar_amount("0", allow_zero=True) == Decimal("0.00")
    with pytest.raises(ns.InvalidNafaqahRequest):
        ns.parse_sar_amount("0", allow_zero=False)


def test_zero_allowance_makes_every_personal_purchase_overspend(family):
    st = ns.set_allowance(ns.load_family_context(HH), HUSBAND, WIFE, Decimal("0"), "2026-11")
    assert st["is_set"] is True and st["allocated"] == 0.0 and st["remaining"] == -1700.0


def test_admin_who_is_not_the_husband_can_set_allowance(family):
    for m in family.tables["household_memberships"]:
        if m["user_id"] == CHILD:
            m["role"] = "admin"
    st = ns.set_allowance(ns.load_family_context(HH), CHILD, WIFE, Decimal("800"), "2026-11")
    assert st["allocated"] == 800.0


def test_several_wives_require_an_explicit_wife(family):
    second = "00000000-0000-4000-8000-0000000000aa"
    family.seed("users", [{"id": second, "household_id": HH, "role": "member", "financial_role": "spouse",
                           "display_name": "Mona"}])
    family.seed("household_memberships", [{"user_id": second, "household_id": HH, "role": "member",
                                           "created_at": "2026-02-01T00:00:00+00:00"}])
    ctx = ns.load_family_context(HH)
    with pytest.raises(ns.InvalidNafaqahRequest):
        ns.resolve_wife_id(ctx, None)
    assert ns.resolve_wife_id(ctx, second) == second
    # a wife may confirm only her own repayments
    with pytest.raises(ns.NafaqahForbidden):
        ns.record_reimbursement(ctx, second, WIFE, Decimal("10"), "cash", None)
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(HUSBAND),
                       json={"amount": 10, "payment_method": "cash"})
    assert resp.status_code == 422


def test_legacy_route_refuses_wife_to_husband_settlement_in_family_mode(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(WIFE), json={
        "household_id": HH, "payer_id": WIFE, "recipient_id": HUSBAND, "amount": 50, "payment_method": "cash",
    })
    assert resp.status_code == 409
    assert "spouse_reimbursements" not in family.tables


def test_legacy_route_overpayment_in_family_mode(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": "wife", "amount": 600, "payment_method": "cash",
    })
    assert resp.status_code == 409


def test_legacy_route_unchanged_for_roommates(family):
    resp = client.post(f"/households/{HH_ROOM}/reimbursements", headers=bearer(PEER1), json={
        "household_id": HH_ROOM, "payer_id": PEER2, "recipient_id": PEER1, "amount": 75, "payment_method": "stc_pay",
    })
    assert resp.status_code == 200, resp.text
    assert resp.json()["is_settlement"] is True
    settlement = [t for t in family.tables["transactions"] if t.get("is_settlement")]
    assert len(settlement) == 1 and settlement[0]["amount"] == 75.0
    assert "spouse_reimbursements" not in family.tables


def test_chat_override_is_ignored_outside_family(family):
    resp = _chat(PEER1, "دفعت فاتورة البيت 300 ريال", household=HH_ROOM, nafaqah_class="wife_reimbursable")
    assert resp.status_code == 200
    assert _last_tx(family).get("nafaqah_class") is None
    assert resp.json()["nafaqah_class"] is None


def test_chat_roommate_preview_is_not_family(family):
    resp = _chat(PEER1, "دفعت فاتورة البيت 300 ريال", household=HH_ROOM, preview_only=True)
    assert resp.status_code == 200
    assert resp.json()["household_mode"] == "not_family" and resp.json()["nafaqah_class"] is None


def test_family_partner_settlement_has_no_spousal_split(family):
    from settlement_engine import calculate_partner_settlement

    res = calculate_partner_settlement(HH, cycle_start="2000-01-01", caller_user_id=HUSBAND)
    assert res["mode"] == "family_nafaqah"
    # husband view: the wife's shared advances (500.50) are owed to her; her personal buys are not
    assert res["owed_to_partner"] == 500.5 and res["owed_to_me"] == 0.0
    assert res["fair_share_partner"] == 0.0
