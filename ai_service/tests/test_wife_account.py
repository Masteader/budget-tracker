"""
The wife account (owner decisions 2026-11-06, migration 20261105001300 section 12).

  * Her husband (the household's Nafaqah provider while he is a member who is not a wife) creates,
    owns and assigns an account of kind 'wife' to one wife; its owner archives it. Nobody else.
  * Seen by her, its owner and her ledger's managers (her husband; an admin who is not a wife when
    he is gone). A co-wife, a wife-admin, a member and an admin while the husband is there get
    nothing, not even that it exists.
  * Every repayment credits one of hers: the payer names it (direct repayment, approval: another of
    hers), she names it on her request. None: wife_account_required (409). Not hers: 422.
  * Every new refusal of the database is a coded answer the app translates.

The database suite (tests 68 and 69) proves the RPCs; here they are stand-ins that record their
parameters, and the HTTP layer runs with real JWTs and membership checks.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt
from postgrest.exceptions import APIError

import nafaqah_service as ns
from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

HH = "c1000000-0000-4000-8000-000000000001"
HUSBAND = "c2000000-0000-4000-8000-00000000000a"
WIFE = "c2000000-0000-4000-8000-00000000000b"
COWIFE = "c2000000-0000-4000-8000-00000000000c"
MEMBER = "c2000000-0000-4000-8000-00000000000d"
ADMIN = "c2000000-0000-4000-8000-00000000000e"
WIFE_ADMIN = "c2000000-0000-4000-8000-00000000000f"
HIS_BANK = "c5000000-0000-4000-8000-000000000001"
HER_BANK = "c5000000-0000-4000-8000-000000000002"
WA1 = "c5000000-0000-4000-8000-0000000000a1"
WA2 = "c5000000-0000-4000-8000-0000000000a2"
WA_ARCHIVED = "c5000000-0000-4000-8000-0000000000a3"
WC = "c5000000-0000-4000-8000-0000000000c1"
KEY = "c4000000-0000-4000-8000-000000000001"
Q_PENDING = "c7000000-0000-4000-8000-000000000001"
R_PAID = "c9000000-0000-4000-8000-000000000001"
T_PAID = "c6000000-0000-4000-8000-000000000001"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def db_error(hint: str, code: str = "22023", details: str = "") -> APIError:
    return APIError({"code": code, "hint": hint, "details": details, "message": "refused"})


def _account(aid, owner, name, wife=None, archived=False, balance=0.0):
    return {"id": aid, "household_id": HH, "owner_user_id": owner, "name": name, "balance": balance,
            "account_type": "wife" if wife else "bank", "assigned_wife_id": wife, "is_shared_pool": False,
            "is_archived": archived, "currency": "SAR", "created_at": "2026-11-06T10:00:00+00:00"}


@pytest.fixture()
def family(fake_supabase):
    people = [(HUSBAND, "admin", "provider"), (WIFE, "member", "spouse"), (COWIFE, "member", "spouse"),
              (MEMBER, "member", "family_member"), (ADMIN, "admin", "family_member"), (WIFE_ADMIN, "admin", "spouse")]
    fake_supabase.seed("users", [{"id": u, "household_id": HH, "role": r, "financial_role": f, "display_name": u[-2:]}
                                 for u, r, f in people])
    fake_supabase.seed("household_memberships", [
        {"user_id": u, "household_id": HH, "role": r, "financial_role": f, "created_at": f"2026-01-0{i + 1}T00:00:00+00:00"}
        for i, (u, r, f) in enumerate(people)])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND, "household_type": "family"}])
    fake_supabase.seed("accounts", [
        _account(HIS_BANK, HUSBAND, "His bank", balance=3000.0),
        _account(HER_BANK, WIFE, "Her bank", balance=500.0),
        _account(WA1, HUSBAND, "Sara card", wife=WIFE, balance=120.0),
        _account(WA2, HUSBAND, "Sara wallet", wife=WIFE),
        _account(WA_ARCHIVED, HUSBAND, "Old", wife=WIFE, archived=True),
        _account(WC, HUSBAND, "Huda card", wife=COWIFE, balance=40.0),
    ])
    fake_supabase.seed("transactions", [
        {"id": "t1", "household_id": HH, "amount": 300.0, "merchant": "Panda", "timestamp": "2026-11-10T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
    ])
    fake_supabase.seed("spouse_reimbursements", [
        {"id": R_PAID, "household_id": HH, "wife_user_id": WIFE, "paid_by_user_id": HUSBAND, "amount": 25.0,
         "payment_method": "cash", "notes": None, "recorded_by": HUSBAND, "created_at": "2026-11-12T10:00:00+00:00",
         "transfer_id": T_PAID, "request_key": KEY, "kind": "payment", "reverses_id": None,
         "account_id": HIS_BANK, "wife_account_id": WA1},
    ])
    fake_supabase.seed("account_transfers", [
        {"id": T_PAID, "household_id": HH, "from_account_id": HIS_BANK, "to_account_id": WA1, "amount": 25.0},
    ])
    fake_supabase.seed("spouse_reimbursement_requests", [
        {"id": Q_PENDING, "household_id": HH, "wife_user_id": WIFE, "amount": 30.0, "payment_method": "cash",
         "created_at": "2026-11-15T10:00:00+00:00", "wife_account_id": WA2},
    ])
    fake_supabase.seed("spouse_reimbursement_request_outcomes", [])
    fake_supabase.rpc_handlers["create_wife_account"] = lambda p: {
        "id": "c5000000-0000-4000-8000-0000000000ff", "household_id": p["p_household_id"], "owner_user_id": p["p_actor_user_id"],
        "assigned_wife_id": p["p_wife_user_id"], "name": p["p_name"], "account_type": "wife", "currency": "SAR",
        "balance": 0, "is_archived": False}
    fake_supabase.rpc_handlers["assign_wife_account"] = lambda p: {
        "id": p["p_account_id"], "assigned_wife_id": p["p_wife_user_id"], "changed": True}
    fake_supabase.rpc_handlers["archive_wife_account"] = lambda p: {
        "id": p["p_account_id"], "is_archived": True, "changed": True}
    fake_supabase.rpc_handlers["record_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-x", "amount": float(p["p_amount"]),
        "payment_method": p["p_payment_method"], "account_id": p["p_account_id"], "wife_account_id": p["p_wife_account_id"],
        "outstanding_before": 275.0, "outstanding_after": 275.0 - float(p["p_amount"])}
    fake_supabase.rpc_handlers["request_spouse_reimbursement"] = lambda p: {
        "success": True, "replayed": False, "request_id": "q-new", "status": "pending", "amount": float(p["p_amount"]),
        "payment_method": p["p_payment_method"], "wife_account_id": p["p_wife_account_id"], "outstanding": 275.0}
    fake_supabase.rpc_handlers["approve_spouse_reimbursement_request"] = lambda p: {
        "success": True, "replayed": False, "reimbursement_id": "r-appr", "request_id": p["p_request_id"], "amount": 30.0,
        "payment_method": "cash", "account_id": p["p_account_id"], "wife_account_id": p["p_wife_account_id"] or WA2,
        "outstanding_before": 275.0, "outstanding_after": 245.0}
    return fake_supabase


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def _wa(path=""):
    return f"/households/{HH}/nafaqah/wife-accounts{path}"


def _set_provider(fake, provider):
    for h in fake.tables["households"]:
        h["nafaqah_provider_user_id"] = provider


# ─── Creating, assigning, archiving: her husband (its owner) only ──────────────

def test_her_husband_creates_her_wife_account(family):
    resp = client.post(_wa(), headers=bearer(HUSBAND), json={"wife_user_id": WIFE, "name": "  Sara card  "})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "create_wife_account") == [
        {"p_household_id": HH, "p_wife_user_id": WIFE, "p_name": "Sara card", "p_actor_user_id": HUSBAND}]
    body = resp.json()
    assert (body["account_type"], body["owner_user_id"], body["assigned_wife_id"]) == ("wife", HUSBAND, WIFE)


@pytest.mark.parametrize("who", [WIFE, COWIFE, MEMBER, ADMIN, WIFE_ADMIN])
def test_nobody_else_creates_one(family, who):
    resp = client.post(_wa(), headers=bearer(who), json={"wife_user_id": WIFE, "name": "x"})
    assert resp.status_code == 403, resp.text
    assert resp.json()["detail"]["code"] == "wife_account_forbidden"
    assert _calls(family, "create_wife_account") == []


def test_when_he_is_gone_nobody_creates_one(family):
    _set_provider(family, None)
    resp = client.post(_wa(), headers=bearer(ADMIN), json={"wife_user_id": WIFE, "name": "x"})
    assert resp.status_code == 403 and resp.json()["detail"]["code"] == "wife_account_forbidden"


@pytest.mark.parametrize("body,code", [
    ({"wife_user_id": MEMBER, "name": "x"}, "not_a_wife"),
    ({"wife_user_id": WIFE, "name": "   "}, "invalid_name"),
    ({"wife_user_id": WIFE, "name": "x" * 61}, "invalid_name"),
])
def test_creation_input_is_checked(family, body, code):
    resp = client.post(_wa(), headers=bearer(HUSBAND), json=body)
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"]["code"] == code
    assert _calls(family, "create_wife_account") == []


def test_he_reassigns_it(family):
    resp = client.put(_wa(f"/{WA2}/assignment"), headers=bearer(HUSBAND), json={"wife_user_id": COWIFE})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "assign_wife_account") == [
        {"p_household_id": HH, "p_account_id": WA2, "p_wife_user_id": COWIFE, "p_actor_user_id": HUSBAND}]


@pytest.mark.parametrize("who,status,code", [
    (WIFE, 403, "wife_account_forbidden"),      # she sees it, she does not assign it
    (COWIFE, 404, "account_not_found"),         # she does not see it
    (MEMBER, 404, "account_not_found"),
    (ADMIN, 404, "account_not_found"),          # an admin while the husband is there
])
def test_nobody_else_assigns_it(family, who, status, code):
    resp = client.put(_wa(f"/{WA2}/assignment"), headers=bearer(who), json={"wife_user_id": COWIFE})
    assert resp.status_code == status, resp.text
    assert resp.json()["detail"]["code"] == code
    assert _calls(family, "assign_wife_account") == []


def test_reassigning_one_with_history_is_refused(family):
    def refuse(_p):
        raise db_error("wife_account_has_history")
    family.rpc_handlers["assign_wife_account"] = refuse
    resp = client.put(_wa(f"/{WA1}/assignment"), headers=bearer(HUSBAND), json={"wife_user_id": COWIFE})
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "wife_account_has_history"


def test_its_owner_archives_it(family):
    resp = client.post(_wa(f"/{WA1}/archive"), headers=bearer(HUSBAND))
    assert resp.status_code == 200, resp.text
    assert _calls(family, "archive_wife_account") == [{"p_household_id": HH, "p_account_id": WA1, "p_actor_user_id": HUSBAND}]


@pytest.mark.parametrize("who,status,code", [
    (WIFE, 403, "wife_account_forbidden"), (COWIFE, 404, "account_not_found"), (MEMBER, 404, "account_not_found")])
def test_nobody_else_archives_it(family, who, status, code):
    resp = client.post(_wa(f"/{WA1}/archive"), headers=bearer(who))
    assert resp.status_code == status and resp.json()["detail"]["code"] == code
    assert _calls(family, "archive_wife_account") == []


def test_an_account_of_nothing_is_not_found(family):
    resp = client.post(_wa("/c5000000-0000-4000-8000-0000000000ee/archive"), headers=bearer(HUSBAND))
    assert resp.status_code == 404 and resp.json()["detail"]["code"] == "account_not_found"


# ─── Who sees it ─────────────────────────────────────────────────────────────────

def _listed(who, query=""):
    resp = client.get(_wa(query), headers=bearer(who))
    assert resp.status_code == 200, resp.text
    return sorted(a["id"] for a in resp.json()["accounts"])


def test_who_sees_which_wife_accounts_with_the_husband_present(family):
    assert _listed(HUSBAND) == sorted([WA1, WA2, WA_ARCHIVED, WC])
    assert _listed(WIFE) == sorted([WA1, WA2, WA_ARCHIVED])
    assert _listed(COWIFE) == [WC]
    for nobody in (MEMBER, ADMIN, WIFE_ADMIN):
        assert _listed(nobody) == [], nobody


def test_who_sees_them_when_he_is_gone_or_replaced(family):
    _set_provider(family, None)
    assert _listed(ADMIN) == sorted([WA1, WA2, WA_ARCHIVED, WC]), "an admin who is not a wife, once he is gone"
    assert _listed(WIFE_ADMIN) == [] and _listed(MEMBER) == []
    assert _listed(HUSBAND) == sorted([WA1, WA2, WA_ARCHIVED, WC]), "he still owns them"
    _set_provider(family, MEMBER)
    assert _listed(MEMBER) == sorted([WA1, WA2, WA_ARCHIVED, WC]), "her husband now"
    assert _listed(ADMIN) == []


def test_the_list_by_wife_and_only_what_can_be_used(family):
    assert _listed(HUSBAND, f"?wife_user_id={WIFE}&active_only=true") == sorted([WA1, WA2])
    # A wife naming her co-wife learns nothing more.
    assert _listed(WIFE, f"?wife_user_id={COWIFE}") == []
    resp = client.get(_wa(), headers=bearer(WIFE))
    sara = {a["id"]: a for a in resp.json()["accounts"]}[WA1]
    assert (sara["balance"], sara["name"], sara["is_archived"], sara["assigned_wife_id"]) == (120.0, "Sara card", False, WIFE)


# ─── Repayments credit one of hers ───────────────────────────────────────────────

def _repay(user, **body):
    payload = {"amount": 20, "payment_method": "cash", "account_id": HIS_BANK, "request_key": KEY, **body}
    return client.post(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(user), json=payload)


def test_a_repayment_names_the_wife_account_it_credits(family):
    resp = _repay(HUSBAND, wife_user_id=WIFE, wife_account_id=WA1)
    assert resp.status_code == 200, resp.text
    (call,) = _calls(family, "record_spouse_reimbursement")
    assert (call["p_account_id"], call["p_wife_account_id"]) == (HIS_BANK, WA1)
    assert resp.json()["wife_account_id"] == WA1


@pytest.mark.parametrize("wife_account", [WC, HER_BANK, WA_ARCHIVED, "c5000000-0000-4000-8000-0000000000ee", None])
def test_never_an_account_that_is_not_hers(family, wife_account):
    body = {"wife_user_id": WIFE}
    if wife_account:
        body["wife_account_id"] = wife_account
    resp = _repay(HUSBAND, **body)
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"]["code"] == "wife_account_invalid"
    assert _calls(family, "record_spouse_reimbursement") == []


def test_no_wife_account_is_wife_account_required(family):
    family.tables["accounts"][:] = [a for a in family.tables["accounts"] if a.get("assigned_wife_id") != WIFE or a["is_archived"]]
    resp = _repay(HUSBAND, wife_user_id=WIFE)
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"]["code"] == "wife_account_required"
    assert _calls(family, "record_spouse_reimbursement") == []


def test_the_legacy_route_passes_the_wife_account(family):
    resp = client.post(f"/households/{HH}/reimbursements", headers=bearer(HUSBAND), json={
        "household_id": HH, "payer_id": "husband", "recipient_id": WIFE, "amount": 10, "payment_method": "cash",
        "account_id": HIS_BANK, "request_key": KEY, "wife_account_id": WA1})
    assert resp.status_code == 200, resp.text
    assert _calls(family, "record_spouse_reimbursement")[0]["p_wife_account_id"] == WA1


# ─── Her request names one of hers; the approval uses it, or another of hers ─────

def _ask(user, **body):
    return client.post(f"/households/{HH}/nafaqah/reimbursement-requests", headers=bearer(user),
                       json={"amount": 30, "payment_method": "cash", "request_key": KEY, **body})


def test_her_request_names_the_account_it_went_into(family):
    resp = _ask(WIFE, wife_account_id=WA2)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "request_spouse_reimbursement")[0]["p_wife_account_id"] == WA2
    assert resp.json()["wife_account_id"] == WA2


@pytest.mark.parametrize("wife_account", [WC, HER_BANK, WA_ARCHIVED, None])
def test_her_request_into_an_account_not_hers(family, wife_account):
    body = {"wife_account_id": wife_account} if wife_account else {}
    resp = _ask(WIFE, **body)
    assert resp.status_code == 422 and resp.json()["detail"]["code"] == "wife_account_invalid", resp.text
    assert _calls(family, "request_spouse_reimbursement") == []


def test_her_request_with_no_wife_account(family):
    resp = _ask(COWIFE, wife_account_id=WA1)  # the co-wife's only one is WC; none named of hers
    assert resp.status_code == 422
    family.tables["accounts"][:] = [a for a in family.tables["accounts"] if a.get("assigned_wife_id") != COWIFE]
    resp = _ask(COWIFE)
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "wife_account_required"


def _approve(user, **body):
    return client.post(f"/households/{HH}/nafaqah/reimbursement-requests/{Q_PENDING}/approve", headers=bearer(user),
                       json={"account_id": HIS_BANK, "request_key": KEY, **body})


def test_the_approval_uses_her_choice(family):
    resp = _approve(HUSBAND)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "approve_spouse_reimbursement_request")[0]["p_wife_account_id"] is None
    assert resp.json()["wife_account_id"] == WA2


def test_he_switches_to_another_of_hers(family):
    resp = _approve(HUSBAND, wife_account_id=WA1)
    assert resp.status_code == 200, resp.text
    assert _calls(family, "approve_spouse_reimbursement_request")[0]["p_wife_account_id"] == WA1


@pytest.mark.parametrize("wife_account", [WC, HIS_BANK, HER_BANK, WA_ARCHIVED])
def test_he_never_switches_to_an_account_not_hers(family, wife_account):
    resp = _approve(HUSBAND, wife_account_id=wife_account)
    assert resp.status_code == 422 and resp.json()["detail"]["code"] == "wife_account_invalid", resp.text
    assert _calls(family, "approve_spouse_reimbursement_request") == []


# ─── The ledger names the wife account; every new refusal has a code ─────────────

def test_the_ledger_names_the_wife_account(family):
    resp = client.get(f"/households/{HH}/nafaqah/reimbursements", headers=bearer(WIFE))
    assert resp.status_code == 200, resp.text
    paid = [h for h in resp.json()["history"] if h.get("id") == R_PAID][0]
    assert paid["wife_account_id"] == WA1
    assert resp.json()["requests"][0]["wife_account_id"] == WA2


@pytest.mark.parametrize("hint,sqlstate,status,extra", [
    ("wife_account_required", "22023", 409, {}),
    ("wife_account_invalid", "22023", 422, {}),
    ("wife_account_invalid", "P0002", 422, {}),
    ("wife_account_insufficient_funds", "22000", 409, {"available": 12.5}),
    ("wife_account_forbidden", "42501", 403, {}),
    ("wife_account_has_history", "22023", 409, {}),
    ("not_a_wife", "22023", 422, {}),
    ("invalid_name", "22023", 422, {}),
    ("account_not_found", "P0002", 404, {}),
])
def test_every_new_refusal_is_coded(family, hint, sqlstate, status, extra):
    def refuse(_p):
        raise db_error(hint, code=sqlstate, details="12.50")
    family.rpc_handlers["reverse_spouse_reimbursement"] = refuse
    resp = client.post(f"/households/{HH}/nafaqah/reimbursements/{R_PAID}/reversal", headers=bearer(HUSBAND),
                       json={"request_key": KEY})
    assert resp.status_code == status, resp.text
    detail = resp.json()["detail"]
    assert detail["code"] == hint
    for k, v in extra.items():
        assert detail[k] == v


def test_the_service_mirrors_who_sees_a_wife_account(family):
    ctx = ns.load_family_context(HH)
    wa1 = _account(WA1, HUSBAND, "x", wife=WIFE)
    assert [w for w in (HUSBAND, WIFE, COWIFE, MEMBER, ADMIN, WIFE_ADMIN) if ns.can_view_wife_account(ctx, w, wa1)] == [HUSBAND, WIFE]
