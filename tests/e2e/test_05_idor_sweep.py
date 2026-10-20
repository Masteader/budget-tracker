"""
Scenario 5: IDOR sweep. Every household-scoped API route is called by members (admin and plain
member) of household A with household B's id (or a B-owned object id): the answer must be 403/404
and must never carry B's data. The same is checked for the PostgREST surface (tables + RPCs).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Callable, List

import pytest

from e2e_harness.zatca import tlv_qr

SECRET = "SECRETB"


@dataclass
class Victim:
    hh: object
    husband: object
    wife: object
    tx_id: str
    dep_id: str
    plan_id: str
    custom_code: str
    secrets: List[str]


@pytest.fixture()
def victim(world, db, llm) -> Victim:
    hh = world.family("V")
    husband, wife = hh.admin, hh.members[0]
    res = world.chat_commit(wife, hh, llm, merchant=f"{SECRET} Boutique", amount=777.77, category_code="OPEX-SHOPPING")
    assert res.status_code == 200, res.text
    tx_id = res.json()["transaction_id"]
    dep = husband.api.post(f"/households/{hh.id}/dependents", json={"name": f"{SECRET}Kid", "monthly_allowance": 50})
    assert dep.status_code == 200, dep.text
    dep_id = dep.json()["dependent"]["id"]
    plan = husband.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": f"{SECRET} Jarir", "provider": "Tamara", "total_amount": 1200,
        "installment_count": 4})
    assert plan.status_code == 200, plan.text
    custom_code = f"CUSTOM-B{uuid.uuid4().hex[:6].upper()}"
    cat = husband.api.post(f"/households/{hh.id}/categories/custom", json={
        "code": custom_code, "category": f"{SECRET} Category", "allocated_amount": 100})
    assert cat.status_code == 200, cat.text
    sub = husband.api.post("/budgets/sub-categories", json={
        "household_id": hh.id, "parent_code": custom_code, "name_en": f"{SECRET} Sub", "allocated_amount": 10})
    assert sub.status_code == 200, sub.text
    assert husband.api.put(f"/households/{hh.id}/nafaqah/allowance", json={"amount": 321}).status_code == 200
    return Victim(hh=hh, husband=husband, wife=wife, tx_id=tx_id, dep_id=dep_id, plan_id=plan.json()["id"],
                  custom_code=custom_code, secrets=[SECRET, husband.id, wife.id, hh.name, "777.77"])


def _routes(v: Victim, own_hh_id: str) -> List[tuple]:
    B = v.hh.id
    qr = tlv_qr("Panda", "300000000000003", "2026-10-19T10:00:00Z", "11.50", "1.50")
    return [
        # analytics
        ("GET", "/analytics/price-history", {"params": {"household_id": B}}),
        ("POST", "/analytics/shopping-basket-optimize", {"json": {"household_id": B, "items": ["milk"]}}),
        # budgets
        ("GET", "/budgets/salary-cycle-forecast", {"params": {"household_id": B}}),
        ("GET", "/budgets/cycles", {"params": {"household_id": B}}),
        ("GET", "/budgets/recurring-bills", {"params": {"household_id": B}}),
        ("POST", "/budgets/recurring-bills/toggle", {"json": {"household_id": B, "category_code": "OPEX-UTILITIES",
                                                               "sub_code": "electricity", "is_recurring": True}}),
        ("GET", "/budgets/recurring-bills/candidates", {"params": {"household_id": B}}),
        ("GET", "/budgets/installments", {"params": {"household_id": B}}),
        ("POST", "/budgets/installments", {"json": {"household_id": B, "merchant": "x", "total_amount": 10}}),
        ("POST", f"/budgets/installments/{v.plan_id}/pay", {}),
        ("POST", "/budgets/recalculate", {"params": {"household_id": B}}),
        ("GET", "/budgets/breakdown", {"params": {"household_id": B}}),
        ("POST", "/budgets/categories", {"json": {"household_id": B, "code": "OPEX-DINING", "category": "Dining",
                                                  "allocated_amount": 1}}),
        ("POST", "/budgets/sub-allocations", {"json": {"household_id": B, "category_code": v.custom_code,
                                                       "sub_allocations": {"x": 1}}}),
        ("POST", "/budgets/sub-categories", {"json": {"household_id": B, "parent_code": v.custom_code,
                                                      "name_en": "Injected"}}),
        ("PATCH", "/budgets/sub-categories", {"json": {"parent_code": v.custom_code, "sub_code": f"sub-{SECRET.lower()}-sub",
                                                       "name_en": "Renamed by A"}}),
        ("DELETE", "/budgets/sub-categories", {"params": {"household_id": B, "parent_code": v.custom_code,
                                                          "sub_code": f"sub-{SECRET.lower()}-sub"}}),
        ("DELETE", f"/budgets/categories/{v.custom_code}", {"params": {"household_id": B}}),
        ("POST", "/budgets/simulate-affordability", {"json": {"household_id": B, "target_amount": 10}}),
        # chat / receipts
        ("POST", "/agent/chat-transaction", {"json": {"household_id": B, "message": "coffee 5 SAR"}}),
        ("POST", "/agent/chat-transaction", {"json": {"household_id": B, "message": "coffee 5 SAR", "preview_only": True}}),
        ("POST", "/agent/scan-receipt", {"json": {"household_id": B, "qr_code_raw": qr}}),
        ("POST", "/agent/scan-receipt", {"json": {"household_id": B, "qr_code_raw": qr, "preview_only": True}}),
        # households
        ("GET", f"/households/{B}/payday", {}),
        ("PUT", f"/households/{B}/payday", {"json": {"payday_day": 1}}),
        ("GET", f"/households/{B}/income", {}),
        ("PUT", f"/households/{B}/income", {"json": {"monthly_income": 1}}),
        ("GET", f"/households/{B}/rollover-rule", {}),
        ("PUT", f"/households/{B}/rollover-rule", {"json": {"rollover_rule": "fresh_start"}}),
        ("GET", f"/households/{B}/savings-summary", {}),
        ("POST", f"/households/{B}/invites", {"json": {"role": "spouse"}}),
        ("POST", f"/households/{B}/reimbursements", {"json": {"household_id": B, "payer_id": v.husband.id,
                                                              "recipient_id": v.wife.id, "amount": 1}}),
        ("GET", f"/households/{B}/dependents", {}),
        ("POST", f"/households/{B}/dependents", {"json": {"name": "Injected"}}),
        ("DELETE", f"/households/{B}/dependents/{v.dep_id}", {}),
        ("GET", f"/households/{B}/settlement", {}),
        ("GET", f"/households/{B}/settlement-v2", {}),
        ("GET", f"/households/{B}/categories", {}),
        ("POST", f"/households/{B}/categories/toggle", {"json": {"category_code": "OPEX-DINING", "is_active": False}}),
        ("POST", f"/households/{B}/categories/custom", {"json": {"code": "INJ-1", "category": "Injected"}}),
        ("GET", f"/households/{B}/members", {}),
        ("POST", f"/households/{B}/members/{v.wife.id}/admin", {}),
        ("DELETE", f"/households/{B}/members/{v.husband.id}/admin", {}),
        ("POST", f"/households/{B}/primary-admin", {"json": {"new_primary_user_id": v.wife.id}}),
        # nafaqah
        ("GET", f"/households/{B}/nafaqah", {}),
        ("GET", f"/households/{B}/nafaqah/reimbursements", {}),
        ("POST", f"/households/{B}/nafaqah/reimbursements", {"json": {"amount": 1}}),
        ("GET", f"/households/{B}/nafaqah/allowance", {}),
        ("PUT", f"/households/{B}/nafaqah/allowance", {"json": {"amount": 1}}),
        # reports / support
        ("GET", "/reports/statement-pdf", {"params": {"household_id": B}}),
        ("POST", "/agent/support-chat", {"json": {"message": "hi", "household_id": B}}),
        ("POST", "/support/chat", {"json": {"message": "hi", "household_id": B}}),
        # A's own household id, B's object ids
        ("POST", f"/households/{own_hh_id}/members/{v.wife.id}/admin", {}),
        ("POST", f"/households/{own_hh_id}/primary-admin", {"json": {"new_primary_user_id": v.wife.id}}),
        ("POST", "/budgets/installments", {"json": {"household_id": own_hh_id, "merchant": "x", "total_amount": 10,
                                                    "original_transaction_id": v.tx_id}}),
    ]


def _snapshot(db, v: Victim) -> dict:
    return {
        "tx": db.one("SELECT amount, merchant, items::text, category_code FROM public.transactions WHERE id = %s", (v.tx_id,)),
        "deps": db.scalar("SELECT count(*) FROM public.household_dependents WHERE household_id = %s", (v.hh.id,)),
        "plan": db.one("SELECT paid_installments FROM public.installment_plans WHERE id = %s", (v.plan_id,)),
        "hh": db.one("SELECT payday_day, monthly_income, rollover_rule, owner_user_id FROM public.households WHERE id = %s",
                     (v.hh.id,)),
        "members": db.query("SELECT user_id::text, role FROM public.household_memberships WHERE household_id = %s ORDER BY 1",
                            (v.hh.id,)),
        "invites": db.scalar("SELECT count(*) FROM public.household_invites WHERE household_id = %s", (v.hh.id,)),
        "subs": db.query("SELECT sub_code, name_en FROM public.cost_control_sub_categories WHERE parent_code = %s ORDER BY 1",
                         (v.custom_code,)),
        "budgets": db.query("SELECT category_code, allocated_amount, is_active, sub_allocations::text FROM public.budgets"
                            " WHERE household_id = %s ORDER BY 1", (v.hh.id,)),
        "settings": db.query("SELECT * FROM public.household_category_settings WHERE household_id = %s", (v.hh.id,)),
        "txs": db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s", (v.hh.id,)),
        "allow": db.query("SELECT amount FROM public.member_allowances WHERE household_id = %s", (v.hh.id,)),
        "reimb": db.scalar("SELECT count(*) FROM public.spouse_reimbursements WHERE household_id = %s", (v.hh.id,)),
        "codes": db.scalar("SELECT count(*) FROM public.cost_control_codes WHERE household_id = %s", (v.hh.id,)),
    }


@pytest.mark.parametrize("attacker_kind", ["admin", "member"])
def test_api_idor_sweep(world, db, llm, victim, attacker_kind):
    a_hh = world.roommates(f"A{attacker_kind}", n_members=1)
    attacker = a_hh.admin if attacker_kind == "admin" else a_hh.members[0]
    before = _snapshot(db, victim)
    failures = []
    for method, path, kwargs in _routes(victim, a_hh.id):
        llm.queue_json({"is_transaction": True, "merchant": "coffee", "total_amount": 5, "items": []})
        res = attacker.api.request(method, path, **kwargs)
        llm.clear()
        leaked = [s for s in victim.secrets if s in res.text]
        if res.status_code not in (403, 404) or leaked:
            failures.append(f"{method} {path} -> {res.status_code} leaked={leaked} body={res.text[:160]}")
    assert not failures, "\n".join(failures)
    assert _snapshot(db, victim) == before, "household B was modified by household A"


def test_api_cross_household_object_refs_do_not_touch_b(world, db, llm, victim):
    a_hh = world.roommates("AX", n_members=0)
    attacker = a_hh.admin
    before = _snapshot(db, victim)
    # Own household id in the path, B's dependent id: B's dependent survives.
    attacker.api.delete(f"/households/{a_hh.id}/dependents/{victim.dep_id}")
    # Enrich B's transaction while claiming A's household: refused / not found, B untouched.
    llm.queue_json({"is_transaction": True, "merchant": "x", "total_amount": 1, "items": [
        {"name": "INJECTED", "quantity": 1, "price": 1}]})
    chat = attacker.api.post("/agent/chat-transaction", json={
        "household_id": a_hh.id, "message": "x 1 SAR", "enrich_tx_id": victim.tx_id})
    assert chat.status_code in (200, 403, 404) and chat.json().get("status") != "enriched", chat.text
    scan = attacker.api.post("/agent/scan-receipt", json={
        "household_id": a_hh.id, "enrich_tx_id": victim.tx_id,
        "qr_code_raw": tlv_qr("INJECTED", "300000000000003", "2026-10-19T10:00:00Z", "9.00", "1.17")})
    assert scan.status_code in (200, 403, 404) and scan.json().get("status") != "enriched", scan.text
    # A receipt path in B's storage folder is rejected.
    bad_path = attacker.api.post("/agent/scan-receipt", json={
        "household_id": a_hh.id, "receipt_url": f"{victim.hh.id}/stolen.jpg", "preview_only": True,
        "qr_code_raw": tlv_qr("Panda", "300000000000003", "2026-10-19T10:00:00Z", "9.00", "1.17")})
    assert bad_path.status_code in (200, 400, 403) and bad_path.json().get("status") in (None, "error"), bad_path.text
    assert _snapshot(db, victim) == before


def test_postgrest_idor_sweep(world, db, llm, victim):
    a_hh = world.roommates("AP", n_members=1)
    B = victim.hh.id
    for attacker in a_hh.everyone:
        # Tables: RLS hides B's rows entirely.
        for table in ("transactions", "households", "household_memberships", "budgets", "household_dependents",
                      "household_invites", "member_allowances", "spouse_reimbursements", "installment_plans",
                      "accounts", "income_records", "account_transfers", "household_category_settings"):
            res = attacker.rest.get(f"/{table}", params={"household_id": f"eq.{B}"} if table != "households"
                                    else {"id": f"eq.{B}"})
            assert res.status_code in (200, 401, 403, 404), (table, res.status_code, res.text)
            if res.status_code == 200:
                assert res.json() == [], (table, res.text)
        users = attacker.rest.get("/users", params={"id": f"in.({victim.husband.id},{victim.wife.id})"})
        assert users.status_code in (200, 403) and (users.status_code == 403 or users.json() == []), users.text
        # Writes into B are refused.
        ins = attacker.rest.post("/transactions", json={
            "household_id": B, "user_id": attacker.id, "amount": 1, "timestamp": "2026-10-19T10:00:00Z",
            "merchant": "INJECTED", "category_code": "OPEX-DINING"})
        assert ins.status_code in (401, 403), ins.text
        upd = attacker.rest.patch(f"/transactions?id=eq.{victim.tx_id}", json={"amount": 1},
                                  headers={"Prefer": "return=representation"})
        assert upd.status_code in (401, 403) or upd.json() == [], upd.text
        dele = attacker.rest.delete(f"/transactions?id=eq.{victim.tx_id}", headers={"Prefer": "return=representation"})
        assert dele.status_code in (401, 403) or dele.json() == [], dele.text
        # Household-scoped RPCs with B's id (and spoofed actor ids) are refused.
        for name, params in (
            ("get_household_members", {"p_household_id": B, "p_actor_user_id": None}),
            ("get_household_members", {"p_household_id": B, "p_actor_user_id": victim.husband.id}),
            ("get_spouse_reimbursement_balance", {"p_household_id": B, "p_wife_user_id": victim.wife.id,
                                                  "p_actor_user_id": victim.husband.id}),
            ("get_member_allowance_status", {"p_household_id": B, "p_member_user_id": victim.wife.id,
                                             "p_cycle_key": None, "p_actor_user_id": victim.husband.id}),
            ("set_member_allowance", {"p_household_id": B, "p_member_user_id": victim.wife.id, "p_amount": "1",
                                      "p_cycle_key": None, "p_actor_user_id": victim.husband.id}),
            ("record_spouse_reimbursement", {"p_household_id": B, "p_wife_user_id": victim.wife.id, "p_amount": "1",
                                             "p_payment_method": "cash", "p_notes": None,
                                             "p_actor_user_id": victim.husband.id}),
            ("promote_member_to_admin", {"p_household_id": B, "p_user_id": victim.wife.id,
                                         "p_actor_user_id": victim.husband.id}),
            ("revoke_admin", {"p_household_id": B, "p_user_id": victim.husband.id, "p_actor_user_id": None}),
            ("transfer_primary_admin", {"p_household_id": B, "p_new_primary_user_id": attacker.id,
                                        "p_actor_user_id": victim.husband.id}),
            ("switch_active_household", {"p_household_id": B}),
            ("transfer_between_accounts", {"p_household_id": B, "p_from_account_id": str(uuid.uuid4()),
                                           "p_to_account_id": str(uuid.uuid4()), "p_amount": 1, "p_fee": 0}),
            ("reallocate_budget", {"p_from_id": str(uuid.uuid4()), "p_to_id": str(uuid.uuid4()), "p_amount": 1}),
        ):
            res = attacker.rpc(name, params)
            leaked = [s for s in victim.secrets if s in res.text]
            assert res.status_code >= 400 and not leaked, (name, res.status_code, res.text)
    assert db.scalar("SELECT count(*) FROM public.spouse_reimbursements WHERE household_id = %s", (B,)) == 0
    assert db.scalar("SELECT owner_user_id::text FROM public.households WHERE id = %s", (B,)) == victim.husband.id


@pytest.mark.xfail(strict=True, reason=(
    "BUG E2E-04 (low): SECURITY DEFINER helpers household_primary_admin_id(uuid) and "
    "nafaqah_husband_id(uuid) are EXECUTE-able by every authenticated user and return another "
    "household's primary-admin / husband user id for any household id (no membership check); "
    "nafaqah_is_spouse_member(uuid, uuid) is a membership oracle for any household."
))
def test_postgrest_helper_rpcs_do_not_leak_other_household_members(world, victim):
    outsider = world.signup("Outsider")
    for name, params in (
        ("household_primary_admin_id", {"p_household_id": victim.hh.id}),
        ("nafaqah_husband_id", {"p_household_id": victim.hh.id}),
    ):
        res = outsider.rpc(name, params)
        assert res.status_code >= 400 or victim.husband.id not in res.text, (name, res.text)
    oracle = outsider.rpc("nafaqah_is_spouse_member", {"p_household_id": victim.hh.id, "p_user_id": victim.wife.id})
    assert oracle.status_code >= 400 or oracle.json() is not True, oracle.text


_E2E05 = (
    "BUG E2E-05: sub-category definitions are global (cost_control_sub_categories has no household_id). "
    "GET /budgets/sub-categories lists another household's custom sub-categories for any guessed "
    "parent_code, and POST /budgets/sub-categories (any member; only membership of the body's "
    "household is checked) inserts a definition under ANY parent_code -- a system category or another "
    "household's custom category -- that every household then sees (GET /budgets/sub-categories, chat "
    "preview 'available_sub_categories')."
)


@pytest.mark.xfail(strict=True, reason=_E2E05)
def test_sub_categories_of_other_household_are_not_listed(world, victim):
    a_hh = world.roommates("AS", n_members=1)
    attacker = a_hh.members[0]  # a plain member, not even an admin
    peek = attacker.api.get("/budgets/sub-categories", params={"parent_code": victim.custom_code})
    assert peek.status_code in (403, 404) or SECRET not in peek.text, peek.text


@pytest.mark.xfail(strict=True, reason=_E2E05)
def test_sub_category_cannot_be_planted_into_other_households(world, victim):
    a_hh = world.roommates("AT", n_members=1)
    attacker = a_hh.members[0]
    marker = f"Planted by A {uuid.uuid4().hex[:6]}"
    for parent in ("OPEX-DINING", victim.custom_code):
        attacker.api.post("/budgets/sub-categories", json={
            "household_id": a_hh.id, "parent_code": parent, "name_en": marker})
        b_view = victim.husband.api.get("/budgets/sub-categories", params={"parent_code": parent})
        assert marker not in b_view.text, (parent, b_view.text)
