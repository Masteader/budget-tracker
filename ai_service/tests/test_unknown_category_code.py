"""
E2E-03 (docs/review/audit/e2e_results.md): a commit whose category code is in neither the
global taxonomy nor the household's own categories answered 500. The DB trigger
validate_category_code_exists refuses it with SQLSTATE 23503, and the APIError escaped
insert_transaction's fallback chain unhandled. It is the client's error: 422 with a fixed message.

The fake below mimics that trigger on public.transactions inserts.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

import fakes
from main import app

HH = "aaaa0000-0000-4000-8000-00000000e301"
OTHER_HH = "bbbb0000-0000-4000-8000-00000000e302"

client = TestClient(app)


@pytest.fixture()
def db(fake_supabase, monkeypatch):
    fake_supabase.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-MISC", "category": "Misc", "keywords": [], "is_flexible": True,
         "household_id": None, "is_system": True},
        {"id": "c2", "code": "OPEX-DINING", "category": "Dining", "keywords": ["cafe"], "is_flexible": False,
         "household_id": None, "is_system": True},
        {"id": "c3", "code": "CUSTOM-OURS", "category": "Ours", "keywords": [], "is_flexible": False,
         "household_id": HH, "is_system": False},
        {"id": "c4", "code": "CUSTOM-THEIRS", "category": "Theirs", "keywords": [], "is_flexible": False,
         "household_id": OTHER_HH, "is_system": False},
    ])
    fake_supabase.seed("households", [{"id": HH, "name": "H", "payday_day": 27}])
    attempts = []
    original = fakes.FakeQuery.execute

    def execute(self):
        if self._table == "transactions" and self._op == "insert":
            attempts.append(dict(self._payload))
            code = self._payload.get("category_code")
            ok = any(
                r["code"] == code and r.get("household_id") in (None, self._payload.get("household_id"))
                for r in self._client.tables.get("cost_control_codes", [])
            )
            if code is not None and not ok:
                raise APIError({
                    "code": "23503",
                    "message": f"Category code {code} does not exist in global or household taxonomy",
                    "hint": None, "details": None,
                })
        return original(self)

    monkeypatch.setattr(fakes.FakeQuery, "execute", execute)
    fake_supabase.insert_attempts = attempts
    return fake_supabase


def _insert(code: str):
    from supabase_client import insert_transaction

    return insert_transaction(
        household_id=HH, amount=12.0, currency="SAR", merchant="Mystery", category_code=code,
        timestamp="2026-10-20T10:00:00+00:00", raw_sms="Chat: mystery 12", source="chat",
        user_id="00000000-0000-0000-0000-000000000001",
    )


def test_insert_transaction_raises_unknown_category_without_retrying(db):
    from supabase_client import UnknownCategoryError

    with pytest.raises(UnknownCategoryError):
        _insert("OPEX-NOPE")
    # The refusal is not a schema mismatch: no pruned-payload retries.
    assert len(db.insert_attempts) == 1
    assert db.tables.get("transactions", []) == []


def test_insert_transaction_accepts_global_and_own_codes(db):
    assert _insert("OPEX-DINING")
    assert _insert("CUSTOM-OURS")
    assert len(db.tables["transactions"]) == 2


def test_category_code_in_taxonomy_follows_the_trigger_rule(db):
    from supabase_client import category_code_in_taxonomy

    assert category_code_in_taxonomy(HH, "OPEX-DINING") is True
    assert category_code_in_taxonomy(HH, "CUSTOM-OURS") is True
    assert category_code_in_taxonomy(HH, "CUSTOM-THEIRS") is False  # another household's code
    assert category_code_in_taxonomy(HH, "OPEX-NOPE") is False


def _chat(category_code, **extra):
    return client.post("/agent/chat-transaction", json={
        "household_id": HH, "message": "Mystery 12 SAR", "allow_duplicate": True,
        "category_code": category_code, **extra,
    })


@pytest.mark.parametrize("code", ["OPEX-NOPE", "CUSTOM-THEIRS", "   ", 42])
def test_chat_commit_with_unknown_category_override_is_422(db, code):
    res = _chat(code)
    assert res.status_code == 422, res.text
    detail = res.json()["detail"]
    assert detail == "Unknown category_code: choose one of your household's categories."
    assert "23503" not in res.text and "taxonomy" not in res.text  # no database text
    assert db.tables.get("transactions", []) == []
    assert db.insert_attempts == []  # refused before touching the database


def test_chat_preview_with_unknown_category_override_is_422(db):
    res = _chat("OPEX-NOPE", preview_only=True)
    assert res.status_code == 422, res.text


def test_chat_commit_with_own_custom_category_override_succeeds(db):
    res = _chat("CUSTOM-OURS")
    assert res.status_code == 200, res.text
    assert res.json()["category_code"] == "CUSTOM-OURS"
    assert [t["category_code"] for t in db.tables["transactions"]] == ["CUSTOM-OURS"]


def test_chat_commit_maps_a_late_trigger_refusal_to_422(db, monkeypatch):
    # The pre-check could not run (lookup failure): the DB refusal still becomes a 422.
    monkeypatch.setattr("chat_parser.category_code_in_taxonomy", lambda *_a: None)
    res = _chat("OPEX-NOPE")
    assert res.status_code == 422, res.text
    assert db.tables.get("transactions", []) == []


def test_receipt_commit_with_unknown_category_is_422(db, monkeypatch):
    # The receipt path has no client override; a code the model invents reaches the trigger.
    monkeypatch.setattr("receipt_scanner.parse_receipt_image", lambda *_a, **_k: {
        "merchant": "Zzz Unknown Shop", "total_amount": 30.0, "category_code": "OPEX-INVENTED",
        "items": [{"name": "thing", "quantity": 1, "price": 30.0}],
    })
    import base64
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, format="PNG")
    res = client.post("/agent/scan-receipt", json={
        "household_id": HH, "images_base64": [base64.b64encode(buf.getvalue()).decode()],
        "allow_duplicate": True,
    })
    assert res.status_code == 422, res.text
    assert res.json()["detail"] == "Unknown category_code: choose one of your household's categories."
    assert db.tables.get("transactions", []) == []
