"""
FABLE2-API-01: a database refusal of a transaction insert is final.

insert_transaction used to retry every failed insert twice with a pruned payload. A constraint or
permission refusal (SQLSTATE 23514, 22023, 23503, 42501, 23505) cannot be fixed by dropping
optional columns: it was sent three times and then surfaced as a 500. Now it is raised at once:
the Nafaqah triggers' hints map to NoProviderError / LedgerWouldBeOverpaid (HTTP 409
``{"detail": {"code": "no_provider" | "ledger_would_be_overpaid", "message": ...}}``), anything
else to TransactionRejectedError (403 / 409 / 422, never database text). A family without a
provider is refused before any budget is touched when the expense would be classified.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

import fakes
import supabase_client
from fable_world import World, zatca_qr
from nafaqah_service import LedgerWouldBeOverpaid, NoProviderError


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def refuse(fake_supabase, monkeypatch):
    """Make public.transactions inserts fail with the given database error; records attempts."""
    state = {"error": None, "attempts": []}
    original = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "insert":
            state["attempts"].append(dict(self._payload))
            if state["error"] is not None:
                raise state["error"]
        return original(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    return state


def _insert(hid="aaaa0000-0000-4000-8000-0000000000a1"):
    return supabase_client.insert_transaction(
        household_id=hid, amount=10.0, currency="SAR", merchant="Panda", category_code="OPEX-GROCERY",
        timestamp="2026-10-21T10:00:00+00:00", raw_sms="Chat: x", source="chat", cycle_key="2026-10",
        dedup_fingerprint="fp", qr_code_raw="qr", sub_category="groceries",
    )


@pytest.mark.parametrize("code, hint, message, expected", [
    ("23514", "no_nafaqah_provider", "Household x has no Nafaqah provider", NoProviderError),
    ("22023", "ledger_would_be_overpaid", "This change would leave ...", LedgerWouldBeOverpaid),
    ("23514", None, "new row violates check constraint", supabase_client.TransactionRejectedError),
    ("22023", None, "invalid parameter", supabase_client.TransactionRejectedError),
    ("23503", None, "nafaqah_spouse_id x is not a spouse member", supabase_client.TransactionRejectedError),
    ("42501", None, "new row violates row-level security policy", supabase_client.TransactionRejectedError),
    ("23505", None, "duplicate key value violates unique constraint", supabase_client.TransactionRejectedError),
])
def test_constraint_and_permission_refusals_are_not_retried(refuse, code, hint, message, expected):
    refuse["error"] = APIError({"code": code, "message": message, "hint": hint, "details": None})
    with pytest.raises(expected) as info:
        _insert()
    assert len(refuse["attempts"]) == 1
    assert message not in str(info.value)  # never the database text
    if expected is supabase_client.TransactionRejectedError:
        assert info.value.sqlstate == code
        assert info.value.status_code == {"42501": 403, "23505": 409}.get(code, 422)


def test_schema_mismatch_still_falls_back(refuse, fake_supabase, monkeypatch):
    """A PostgREST schema error (unknown column) keeps the pruning fallback."""
    calls = {"n": 0}
    original = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "insert" and "qr_code_raw" in self._payload:
            calls["n"] += 1
            raise APIError({"code": "PGRST204", "message": "Could not find the 'qr_code_raw' column",
                            "hint": None, "details": None})
        return original(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    tx_id = _insert()
    assert calls["n"] == 1 and tx_id
    stored = fake_supabase.tables["transactions"][-1]
    assert "qr_code_raw" not in stored and stored["sub_category"] == "groceries"


# ─── Routes ────────────────────────────────────────────────────────────────────

def _family(fake, provider=True, son=False):
    roles = {"husband": ("admin", "provider"), "wife": ("member", "spouse")}
    if son:
        roles["son"] = ("member", "family_member")
    w = World(fake, roles)
    fake.tables["households"][0]["nafaqah_provider_user_id"] = w.users["husband"] if provider else None
    fake.seed("cost_control_codes", [{"id": "c-groc", "code": "OPEX-GROCERY", "category": "Groceries",
                                      "keywords": ["panda", "groceries"], "is_flexible": False,
                                      "household_id": None, "is_system": True}])
    return w


def _chat(api, w, who="wife", **extra):
    body = {"household_id": w.hid, "message": "Groceries 300 sar", "category_code": "OPEX-GROCERY",
            "paid_by": "me", "beneficiary": "both", **extra}
    return api.post("/agent/chat-transaction", json=body, headers=w.hdr(who))


def test_chat_commit_without_provider_is_409_before_any_write(api, fake_supabase, refuse):
    w = _family(fake_supabase, provider=False)
    r = _chat(api, w)
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "no_provider"
    assert r.json()["detail"]["message"]
    assert refuse["attempts"] == []


def test_receipt_commit_without_provider_is_409_before_any_write(api, fake_supabase, refuse):
    w = _family(fake_supabase, provider=False)
    r = api.post("/agent/scan-receipt", json={"household_id": w.hid, "qr_code_raw": zatca_qr(),
                                              "paid_by": "me", "beneficiary": "both"}, headers=w.hdr("wife"))
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "no_provider"
    assert refuse["attempts"] == []


def test_unclassified_expense_in_a_family_without_provider_is_still_recorded(api, fake_supabase, refuse):
    """Only a class needs the provider: a son's expense (no class) is stored."""
    w = _family(fake_supabase, provider=False, son=True)
    r = _chat(api, w, who="son")
    assert r.status_code == 200, r.text
    assert r.json()["nafaqah_class"] is None and len(refuse["attempts"]) == 1


def test_database_no_provider_refusal_maps_to_409(api, fake_supabase, refuse):
    """The provider left between the check and the insert: the trigger's hint is mapped once."""
    w = _family(fake_supabase)
    refuse["error"] = APIError({"code": "23514", "message": "Household has no Nafaqah provider",
                                "hint": "no_nafaqah_provider", "details": None})
    r = _chat(api, w)
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "no_provider"
    assert len(refuse["attempts"]) == 1


@pytest.mark.parametrize("code, status", [("42501", 403), ("23505", 409), ("23514", 422)])
def test_other_database_refusals_are_4xx_without_database_text(api, fake_supabase, refuse, code, status):
    w = _family(fake_supabase)
    refuse["error"] = APIError({"code": code, "message": "secret internal detail", "hint": None, "details": None})
    r = _chat(api, w)
    assert r.status_code == status, r.text
    assert "secret internal detail" not in r.text
    assert len(refuse["attempts"]) == 1
    r = api.post("/agent/scan-receipt", json={"household_id": w.hid, "qr_code_raw": zatca_qr()},
                 headers=w.hdr("husband"))
    assert r.status_code == status, r.text
    assert "secret internal detail" not in r.text
