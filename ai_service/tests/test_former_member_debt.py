"""
What the husband still owes a wife who deleted her account (owner decision 2026-11-06).

Migration 20261105001200_account_deletion_former_member_debt.sql keeps one anonymised record per
household. The API shows it in the Nafaqah summary and closes it through two SECURITY DEFINER
RPCs, passing the verified caller: a payment (amount, payment method and the account it leaves, as an ordinary
reimbursement; the API itself touches no table, and paying from an account, which the database
debits, is test_wife_repayment_debit's) or her waiver (إبراء). Before the
deletion the creditor sees an in-app notice; the worker emails it ('creditor_owed').

The database suite (tests 54 and 55) proves the RPCs; here they are stand-ins that record their
parameters, and the HTTP layer runs with real JWTs and membership checks.
"""

from __future__ import annotations

import pathlib
import re
import time
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient
from jose import jwt
from postgrest.exceptions import APIError

import account_deletion_notices as notices
import account_deletion_worker as worker
import mail_service
import nafaqah_service as ns
from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"
MIGRATION = (pathlib.Path(__file__).resolve().parents[2] / "supabase" / "migrations"
             / "20261105001200_account_deletion_former_member_debt.sql")

HH = "a1000000-0000-4000-8000-000000000001"
HH_OTHER = "a1000000-0000-4000-8000-000000000002"
HUSBAND = "a2000000-0000-4000-8000-00000000000a"
WIFE = "a2000000-0000-4000-8000-00000000000b"
CHILD = "a2000000-0000-4000-8000-00000000000c"
COADMIN = "a2000000-0000-4000-8000-00000000000d"
OUTSIDER = "a2000000-0000-4000-8000-00000000000e"
DEBT = "a3000000-0000-4000-8000-000000000001"
DEBT_CLOSED = "a3000000-0000-4000-8000-000000000002"
DEBT_OTHER = "a3000000-0000-4000-8000-000000000003"
KEY = "a4000000-0000-4000-8000-000000000001"
# Since 20261105001300 every payment leaves an account (its debit is test_wife_repayment_debit's).
ACCOUNT = "a5000000-0000-4000-8000-000000000001"

client = TestClient(app)


def bearer(sub: str) -> dict:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "iss": ISSUER, "role": "authenticated", "iat": now, "exp": now + 3600}
    return {"Authorization": f"Bearer {jwt.encode(claims, TEST_SECRET, algorithm='HS256')}"}


def db_error(hint: str, code: str = "22023", message: str = "refused") -> APIError:
    return APIError({"code": code, "hint": hint, "details": None, "message": message})


@pytest.fixture()
def household(fake_supabase):
    """A family whose second wife already deleted her account (two records), plus one wife still here."""
    fake_supabase.seed("users", [
        {"id": HUSBAND, "household_id": HH, "role": "admin", "financial_role": "provider", "display_name": "Ahmed"},
        {"id": WIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Sara"},
        {"id": CHILD, "household_id": HH, "role": "member", "financial_role": "family_member", "display_name": "Fahad"},
        {"id": COADMIN, "household_id": HH, "role": "admin", "financial_role": "family_member", "display_name": "Huda"},
        {"id": OUTSIDER, "household_id": HH_OTHER, "role": "admin", "financial_role": "provider", "display_name": "Omar"},
    ])
    fake_supabase.seed("household_memberships", [
        {"user_id": HUSBAND, "financial_role": "provider", "household_id": HH, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
        {"user_id": WIFE, "financial_role": "spouse", "household_id": HH, "role": "member", "created_at": "2026-01-02T00:00:00+00:00"},
        {"user_id": CHILD, "financial_role": "family_member", "household_id": HH, "role": "member", "created_at": "2026-01-03T00:00:00+00:00"},
        {"user_id": COADMIN, "financial_role": "family_member", "household_id": HH, "role": "admin", "created_at": "2026-01-04T00:00:00+00:00"},
        {"user_id": OUTSIDER, "financial_role": "provider", "household_id": HH_OTHER, "role": "admin", "created_at": "2026-01-01T00:00:00+00:00"},
    ])
    fake_supabase.seed("households", [
        {"id": HH, "payday_day": 27, "owner_user_id": HUSBAND, "nafaqah_provider_user_id": HUSBAND, "household_type": "family"},
        {"id": HH_OTHER, "payday_day": 27, "owner_user_id": OUTSIDER, "nafaqah_provider_user_id": OUTSIDER, "household_type": "family"},
    ])
    fake_supabase.seed("transactions", [
        {"id": "t1", "household_id": HH, "amount": 300.0, "merchant": "Panda", "timestamp": "2026-11-10T09:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": WIFE},
    ])
    fake_supabase.seed("former_member_debts", [
        {"id": DEBT, "household_id": HH, "original_amount": 170.0, "paid_amount": 70.0, "status": "open",
         "created_at": "2026-11-05T10:00:00+00:00", "closed_at": None},
        {"id": DEBT_CLOSED, "household_id": HH, "original_amount": 40.0, "paid_amount": 10.0, "status": "waived",
         "created_at": "2026-10-01T10:00:00+00:00", "closed_at": "2026-10-20T10:00:00+00:00"},
        {"id": DEBT_OTHER, "household_id": HH_OTHER, "original_amount": 999.0, "paid_amount": 0.0, "status": "open",
         "created_at": "2026-11-01T10:00:00+00:00", "closed_at": None},
    ])
    fake_supabase.seed("former_member_debt_events", [
        {"id": "e1", "debt_id": DEBT, "kind": "payment", "amount": 70.0, "payment_method": "cash",
         "remaining_after": 100.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-11-06T10:00:00+00:00"},
        {"id": "e2", "debt_id": DEBT_CLOSED, "kind": "payment", "amount": 10.0, "payment_method": "stc_pay",
         "remaining_after": 30.0, "recorded_by": HUSBAND, "request_key": KEY, "created_at": "2026-10-10T10:00:00+00:00"},
        {"id": "e3", "debt_id": DEBT_CLOSED, "kind": "waiver", "amount": 30.0, "payment_method": None,
         "remaining_after": 0.0, "recorded_by": COADMIN, "request_key": KEY, "created_at": "2026-10-20T10:00:00+00:00"},
        {"id": "e4", "debt_id": DEBT_OTHER, "kind": "payment", "amount": 1.0, "payment_method": "cash",
         "remaining_after": 998.0, "recorded_by": OUTSIDER, "request_key": KEY, "created_at": "2026-11-02T10:00:00+00:00"},
    ])

    def notices_for(params):
        # The DB returns rows only for a creditor; the stand-in mirrors that for the husband.
        if params.get("p_household_id") == HH and params.get("p_actor_user_id") == HUSBAND:
            return [{"wife_user_id": WIFE, "scheduled_for": "2026-12-01T22:30:00+00:00", "outstanding": 300.0}]
        return []

    def pay(params):
        return {"success": True, "replayed": False, "event_id": "e-new", "debt_id": params["p_debt_id"],
                "amount": float(params["p_amount"]), "payment_method": params["p_payment_method"],
                "remaining": 100.0 - float(params["p_amount"]), "status": "open"}

    def waive(params):
        return {"success": True, "replayed": False, "event_id": "e-w", "debt_id": params["p_debt_id"],
                "waived_amount": 100.0, "remaining": 0.0, "status": "waived"}

    fake_supabase.rpc_handlers["get_former_member_debt_deletion_notices"] = notices_for
    fake_supabase.rpc_handlers["record_former_member_debt_payment"] = pay
    fake_supabase.rpc_handlers["waive_former_member_debt"] = waive
    return fake_supabase


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def _pay(user, debt=DEBT, **body):
    payload = {"amount": 30, "payment_method": "bank_transfer", "request_key": KEY, "account_id": ACCOUNT, **body}
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{debt}/payments", headers=bearer(user), json=payload)


def _waive(user, debt=DEBT, **body):
    payload = {"request_key": KEY, **body}
    return client.post(f"/households/{HH}/nafaqah/former-member-debts/{debt}/waiver", headers=bearer(user), json=payload)


# ─── The summary ─────────────────────────────────────────────────────────────

@pytest.mark.parametrize("caller", [HUSBAND, WIFE, CHILD, COADMIN])
def test_every_member_sees_the_households_records_with_their_history(household, caller):
    resp = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller))
    assert resp.status_code == 200, resp.text
    debts = resp.json()["former_member_debts"]
    assert [d["id"] for d in debts] == [DEBT, DEBT_CLOSED], "newest first, never another household's"
    first, closed = debts
    assert (first["original_amount"], first["paid_amount"], first["remaining"], first["status"]) == (170.0, 70.0, 100.0, "open")
    assert (closed["remaining"], closed["status"], closed["closed_at"]) == (30.0, "waived", "2026-10-20T10:00:00+00:00")
    assert [(e["kind"], e["amount"], e["payment_method"]) for e in closed["events"]] == [
        ("payment", 10.0, "stc_pay"), ("waiver", 30.0, None)]
    assert all("recorded_by" not in e and "request_key" not in e for d in debts for e in d["events"])


@pytest.mark.parametrize("caller, allowed", [(HUSBAND, True), (COADMIN, True), (CHILD, False), (WIFE, False)])
def test_only_the_husband_or_an_admin_may_close_a_record(household, caller, allowed):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller)).json()
    assert body["can_manage_former_member_debts"] is allowed


def test_the_husband_manages_the_record_even_when_he_is_not_an_admin(household):
    """The provider is chosen by an admin and need not be one (set_nafaqah_provider)."""
    for m in household.tables["household_memberships"]:
        if m["user_id"] == HUSBAND:
            m["role"] = "member"
    household.tables["households"][0]["owner_user_id"] = COADMIN
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND)).json()
    assert body["can_manage_former_member_debts"] is True
    assert _pay(HUSBAND).status_code == 200
    assert [p["p_actor_user_id"] for p in _calls(household, "record_former_member_debt_payment")] == [HUSBAND]
    assert _waive(HUSBAND).status_code == 200


def test_a_family_with_no_wife_left_still_shows_its_records(household):
    household.tables["household_memberships"] = [m for m in household.tables["household_memberships"] if m["user_id"] != WIFE]
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(CHILD)).json()
    assert body["mode"] == "family_nafaqah" and body["wives"] == []
    assert [d["id"] for d in body["former_member_debts"]] == [DEBT, DEBT_CLOSED]


def test_the_husband_sees_her_pending_deletion_with_what_he_owes(household):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND)).json()
    assert body["wives"][0]["pending_deletion"] == {"scheduled_for": "2026-12-01T22:30:00+00:00", "outstanding": 300.0}
    assert _calls(household, "get_former_member_debt_deletion_notices") == [
        {"p_household_id": HH, "p_actor_user_id": HUSBAND}]


@pytest.mark.parametrize("caller", [CHILD, COADMIN, WIFE])
def test_nobody_else_sees_the_pending_deletion(household, caller):
    body = client.get(f"/households/{HH}/nafaqah", headers=bearer(caller)).json()
    assert body["wives"][0]["pending_deletion"] is None


def test_a_failed_notice_lookup_is_an_error_never_no_notice(household):
    def boom(_params):
        raise db_error("", code="XX000", message="down")

    household.rpc_handlers["get_former_member_debt_deletion_notices"] = boom
    assert client.get(f"/households/{HH}/nafaqah", headers=bearer(HUSBAND)).status_code == 500


# ─── Recording a payment ─────────────────────────────────────────────────────

@pytest.mark.parametrize("caller", [HUSBAND, COADMIN])
def test_a_payment_goes_to_the_rpc_with_the_verified_caller_and_exact_amount(household, caller):
    resp = _pay(caller, amount=30.4)
    assert resp.status_code == 200, resp.text
    assert _calls(household, "record_former_member_debt_payment") == [{
        "p_household_id": HH, "p_debt_id": DEBT, "p_amount": "30.40", "p_payment_method": "bank_transfer",
        "p_request_key": KEY, "p_actor_user_id": caller, "p_account_id": ACCOUNT}]
    body = resp.json()
    assert (body["status"], body["remaining"], body["replayed"]) == ("open", 69.6, False)


def test_a_payment_touches_no_table_directly(household):
    before = {name: [dict(r) for r in rows] for name, rows in household.tables.items()}
    assert _pay(HUSBAND).status_code == 200
    assert household.tables == before, "only the RPC writes, and it touches no account, budget or transaction"
    assert [n for n, _ in household.rpc_calls if n not in ("get_former_member_debt_deletion_notices",)] == [
        "record_former_member_debt_payment"]


@pytest.mark.parametrize("caller", [CHILD, WIFE])
def test_a_member_may_not_pay(household, caller):
    resp = _pay(caller)
    assert resp.status_code == 403
    assert _calls(household, "record_former_member_debt_payment") == []


def test_another_household_is_refused_before_anything(household):
    assert _pay(OUTSIDER).status_code == 403
    assert _calls(household, "record_former_member_debt_payment") == []


# Review R1-02: the API does not judge the record before the database. A retry of a payment that
# went through finds it settled or with less remaining, and the database answers it as the first
# time; only the database, after its replay lookup, refuses an unknown, closed or overpaid record.

def _refuse_payment(household, hint, code="22023", details=None):
    def refuse(_params):
        raise APIError({"code": code, "hint": hint, "details": details, "message": "refused"})

    household.rpc_handlers["record_former_member_debt_payment"] = refuse


def test_a_record_of_another_household_is_the_databases_not_found(household):
    _refuse_payment(household, "debt_not_found", code="P0002")
    resp = _pay(HUSBAND, debt=DEBT_OTHER)
    assert resp.status_code == 404
    assert resp.json()["detail"]["code"] == "debt_not_found"
    assert [p["p_debt_id"] for p in _calls(household, "record_former_member_debt_payment")] == [DEBT_OTHER]


def test_more_than_remains_is_the_databases_to_refuse(household):
    _refuse_payment(household, "overpayment", details="100.00")
    resp = _pay(HUSBAND, amount=100.01)
    assert resp.status_code == 409
    assert resp.json()["detail"]["code"] == "overpayment" and resp.json()["detail"]["outstanding"] == 100.0
    assert len(_calls(household, "record_former_member_debt_payment")) == 1


def test_a_closed_record_is_the_databases_to_refuse(household):
    _refuse_payment(household, "debt_closed")
    resp = _pay(HUSBAND, debt=DEBT_CLOSED, amount=1)
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "debt_closed"
    assert len(_calls(household, "record_former_member_debt_payment")) == 1


@pytest.mark.parametrize("hint, code, status_code, detail_code", [
    ("overpayment", "22023", 409, "overpayment"),
    ("debt_closed", "22023", 409, "debt_closed"),
    ("debt_not_found", "P0002", 404, "debt_not_found"),
    ("request_key_reused", "22023", 409, "request_key_reused"),
    ("forbidden", "42501", 403, None),
    ("invalid_amount", "22023", 422, None),
    ("invalid_payment_method", "22023", 422, None),
])
def test_database_refusals_map_to_codes_the_app_knows(household, hint, code, status_code, detail_code):
    def refuse(_params):
        raise db_error(hint, code=code)

    household.rpc_handlers["record_former_member_debt_payment"] = refuse
    resp = _pay(HUSBAND)
    assert resp.status_code == status_code, resp.text
    if detail_code:
        assert resp.json()["detail"]["code"] == detail_code
    assert "refused" not in resp.text, "the raw database text never reaches the client"


@pytest.mark.parametrize("body", [
    {"amount": 0}, {"amount": -5}, {"amount": 10.001}, {"payment_method": "gold"}, {"request_key": "not-a-uuid"},
    {"request_key": None}, {"account_id": "not-a-uuid"}, {"account": "a5000000-0000-4000-8000-000000000001"},
])
def test_malformed_requests_are_refused(household, body):
    payload = {"amount": 30, "payment_method": "cash", "request_key": KEY, **body}
    resp = client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/payments", headers=bearer(HUSBAND), json=payload)
    assert resp.status_code == 422, (body, resp.text)
    assert _calls(household, "record_former_member_debt_payment") == []


def test_a_replay_is_answered_as_success(household):
    household.rpc_handlers["record_former_member_debt_payment"] = lambda p: {
        "success": True, "replayed": True, "event_id": "e1", "debt_id": DEBT, "amount": 70.0,
        "payment_method": "cash", "remaining": 100.0, "status": "open"}
    resp = _pay(HUSBAND, amount=70)
    assert resp.status_code == 200 and resp.json()["replayed"] is True and resp.json()["amount"] == 70.0


# ─── The waiver ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("caller", [HUSBAND, COADMIN])
def test_a_waiver_goes_to_the_rpc_with_the_verified_caller(household, caller):
    resp = _waive(caller)
    assert resp.status_code == 200, resp.text
    assert _calls(household, "waive_former_member_debt") == [
        {"p_household_id": HH, "p_debt_id": DEBT, "p_request_key": KEY, "p_actor_user_id": caller}]
    assert (resp.json()["status"], resp.json()["waived_amount"]) == ("waived", 100.0)


@pytest.mark.parametrize("caller", [CHILD, WIFE, OUTSIDER])
def test_nobody_else_may_waive(household, caller):
    assert _waive(caller).status_code == 403
    assert _calls(household, "waive_former_member_debt") == []


def test_a_closed_record_cannot_be_waived(household):
    def refuse(_params):
        raise db_error("debt_closed")

    household.rpc_handlers["waive_former_member_debt"] = refuse
    resp = _waive(HUSBAND, debt=DEBT_CLOSED)
    assert resp.status_code == 409 and resp.json()["detail"]["code"] == "debt_closed"
    assert len(_calls(household, "waive_former_member_debt")) == 1, "the database decides, after its replay lookup"


def test_a_waiver_needs_a_request_key(household):
    resp = client.post(f"/households/{HH}/nafaqah/former-member-debts/{DEBT}/waiver", headers=bearer(HUSBAND), json={})
    assert resp.status_code == 422


def test_routes_call_the_functions_the_migration_defines():
    text = MIGRATION.read_text(encoding="utf-8")
    for name, params in (
        ("record_former_member_debt_payment",
         {"p_household_id", "p_debt_id", "p_amount", "p_payment_method", "p_request_key", "p_actor_user_id"}),
        ("waive_former_member_debt", {"p_household_id", "p_debt_id", "p_request_key", "p_actor_user_id"}),
        ("get_former_member_debt_deletion_notices", {"p_household_id", "p_actor_user_id"}),
    ):
        match = re.search(rf"CREATE OR REPLACE FUNCTION public\.{name}\((.*?)\)\s*RETURNS", text, re.S)
        assert match, name
        assert set(re.findall(r"\b(p_\w+)\b", match.group(1))) == params


def test_payment_methods_match_todays_reimbursement():
    assert ns.PAYMENT_METHODS == ("stc_pay", "urpay", "bank_transfer", "iban", "cash", "other")
    assert "'stc_pay', 'urpay', 'bank_transfer', 'iban', 'cash', 'other'" in MIGRATION.read_text(encoding="utf-8")


# ─── The email before the deletion ───────────────────────────────────────────

_SCHEDULED = "2026-12-01T22:30:00+00:00"  # 2 December in Riyadh


def test_the_creditor_email_states_date_and_amount_in_three_languages_arabic_first():
    message = notices.compose("creditor_owed", "en", _SCHEDULED, amount=1234.5)
    body = message.body
    assert body.count("2026-12-02") == 3
    assert body.count("1,234.50") >= 3
    ar, en, ur = body.index("قوام المال"), body.index("Qawam Money"), body.index("نفقہ")
    assert ar < en < ur
    assert "قوام المال" in message.subject and "Qawam Money" in message.subject and "\n" not in message.subject
    assert message == notices.compose("creditor_owed", "ar", _SCHEDULED, amount=1234.5), "no stored language"
    assert "{" not in body and "50/50" not in body


def test_the_creditor_email_never_goes_without_its_amount():
    with pytest.raises(ValueError):
        notices.compose("creditor_owed", "en", _SCHEDULED)


class _Client:
    """Just enough of the worker's client: two notice lists, address lookup, the mark."""

    def __init__(self, rows, fail_list=False):
        self.rows, self.fail_list, self.calls = rows, fail_list, []
        self.auth = type("A", (), {"admin": type("B", (), {"get_user_by_id": self._get})()})()

    def _get(self, uid):
        self.calls.append(("auth.get", uid))
        return type("U", (), {"user": type("E", (), {"email": f"{uid[:8]}@example.com"})()})()

    def rpc(self, name, params=None):
        def execute():
            self.calls.append(("rpc", name, params or {}))
            if name == "list_former_member_debt_notices_due":
                if self.fail_list:
                    raise APIError({"code": "XX000", "message": "boom", "hint": None, "details": None})
                return type("R", (), {"data": self.rows})()
            if name == "list_account_deletion_notices_due":
                return type("R", (), {"data": []})()
            return type("R", (), {"data": None})()
        return type("Q", (), {"execute": staticmethod(execute)})()


def _creditor_row(amount=170.0):
    return {"request_id": "r1", "user_id": HUSBAND, "notice": "creditor_owed", "locale": None,
            "scheduled_for": _SCHEDULED, "amount": amount}


@pytest.fixture()
def mailer(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.delenv("SMTP_HOST", raising=False)
    send = AsyncMock(return_value="resend")
    monkeypatch.setattr(mail_service, "send_email", send)
    return send


def test_the_worker_emails_the_creditor_with_the_amount_and_marks_it(monkeypatch, mailer):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    monkeypatch.setenv(worker.EMAILS_ENV, "1")
    fake = _Client([_creditor_row()])
    worker._send_notices(fake)
    assert [c.kwargs.get("to_override") for c in mailer.await_args_list] == [f"{HUSBAND[:8]}@example.com"]
    assert "170.00" in mailer.await_args.args[0].body
    assert ("rpc", "mark_account_deletion_notice_sent", {"p_request_id": "r1", "p_notice": "creditor_owed"}) in fake.calls


def test_the_email_switch_off_sends_and_marks_nothing(monkeypatch, mailer):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    monkeypatch.delenv(worker.EMAILS_ENV, raising=False)
    fake = _Client([_creditor_row()])
    worker._send_notices(fake)
    mailer.assert_not_awaited()
    assert not [c for c in fake.calls if c[0] == "auth.get" or c[1] == "mark_account_deletion_notice_sent"]


def test_the_purge_switch_off_never_lists_the_creditor_notice(monkeypatch, mailer):
    monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    monkeypatch.setenv(worker.EMAILS_ENV, "1")
    fake = _Client([_creditor_row()])
    worker.run_once(fake)
    mailer.assert_not_awaited()
    assert "list_former_member_debt_notices_due" not in [c[1] for c in fake.calls if c[0] == "rpc"]


def test_a_failing_creditor_list_does_not_stop_the_other_notices(monkeypatch, mailer, caplog):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    monkeypatch.setenv(worker.EMAILS_ENV, "1")
    fake = _Client([], fail_list=True)
    with caplog.at_level("DEBUG"):
        worker._send_notices(fake)
    assert "boom" not in caplog.text
    assert [c[1] for c in fake.calls if c[0] == "rpc"][:2] == [
        "list_account_deletion_notices_due", "list_former_member_debt_notices_due"]
