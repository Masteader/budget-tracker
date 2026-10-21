"""
UX-12 (docs/review/audit/ux_review.md): the user corrects the amount (and, for a receipt, the
category) in the review card before saving. The correction travels with the preview_token
commit as optional ``amount`` / ``category_code`` fields, validated like every other edit; the
signed preview is not re-parsed and the model is not called again. Requests without them keep
the parsed values (installed apps are unaffected).
"""
from __future__ import annotations

import base64
import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import preview_token as pt
from fable_world import World
from main import app
from test_fable_product_r6_preview_token import CHAT_PARSE, LLM, RECEIPT_PARSE, _codes


@pytest.fixture()
def api():
    return TestClient(app)


@pytest.fixture(autouse=True)
def _fresh_key(monkeypatch):
    monkeypatch.delenv("PREVIEW_TOKEN_SECRET", raising=False)
    pt.reset_preview_token_key()
    yield
    pt.reset_preview_token_key()


@pytest.fixture()
def flat(fake_supabase):
    _codes(fake_supabase)
    return World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})


@pytest.fixture()
def family(fake_supabase):
    _codes(fake_supabase)
    w = World(fake_supabase, {"husband": ("admin", "provider"), "wife": ("member", "spouse")})
    fake_supabase.tables["households"][0]["nafaqah_provider_user_id"] = w.users["husband"]
    return w


def _jpeg() -> str:
    buf = io.BytesIO()
    Image.new("RGB", (40, 60), (250, 250, 250)).save(buf, "JPEG")
    return base64.b64encode(buf.getvalue()).decode()


def _txs(fake):
    return fake.tables.get("transactions", [])


def _chat(api, w, who, **body):
    payload = {"household_id": w.hid, "message": "Albaik broast 46 riyal", "allow_duplicate": True}
    payload.update(body)
    return api.post("/agent/chat-transaction", json=payload, headers=w.hdr(who))


def _receipt(api, w, who, **body):
    payload = {"household_id": w.hid, "allow_duplicate": True}
    payload.update(body)
    return api.post("/agent/scan-receipt", json=payload, headers=w.hdr(who))


def test_chat_commit_stores_the_corrected_amount_without_a_second_llm_call(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, dict(CHAT_PARSE, total_amount=816.0, items=[{"name": "Broast", "quantity": 1, "price": 816.0}]))
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    res = _chat(api, flat, "ahmed", preview_token=token, amount=186)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "success" and body["amount"] == 186.0
    (row,) = _txs(fake_supabase)
    assert row["amount"] == 186.0
    # A single line item that was the whole amount follows the correction.
    assert [i["price"] for i in row["items"]] == [186.0]
    assert len(llm.calls) == 1


def test_chat_amount_is_rounded_to_halalas(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    res = _chat(api, flat, "ahmed", preview_token=token, amount=12.345)
    assert res.status_code == 200, res.text
    assert _txs(fake_supabase)[-1]["amount"] == 12.35


@pytest.mark.parametrize("bad", [0, -5, "abc", True, 10_000_001, float("inf")])
def test_chat_invalid_amount_is_422_and_nothing_is_stored(api, flat, fake_supabase, monkeypatch, bad):
    LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    if bad == float("inf"):
        import json as _json

        res = api.post(
            "/agent/chat-transaction",
            content=_json.dumps({"household_id": flat.hid, "message": "Albaik broast 46 riyal", "allow_duplicate": True,
                                 "preview_token": token, "amount": 1e400}),
            headers={**flat.hdr("ahmed"), "Content-Type": "application/json"},
        )
    else:
        res = _chat(api, flat, "ahmed", preview_token=token, amount=bad)
    assert res.status_code == 422, res.text
    assert _txs(fake_supabase) == []


def test_chat_without_amount_keeps_the_parsed_amount(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    assert _chat(api, flat, "ahmed", preview_token=token).status_code == 200
    assert _txs(fake_supabase)[-1]["amount"] == 46.0


def test_chat_corrected_amount_keeps_the_family_rules(api, family, fake_supabase, monkeypatch):
    LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, family, "wife", preview_only=True).json()["preview_token"]
    res = _chat(api, family, "wife", preview_token=token, amount=60, nafaqah_class="wife_reimbursable")
    assert res.status_code == 200, res.text
    row = _txs(fake_supabase)[-1]
    assert row["amount"] == 60.0 and row["nafaqah_class"] == "wife_reimbursable"


def test_receipt_commit_stores_the_corrected_amount_and_category(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    res = _receipt(api, flat, "ahmed", preview_token=token, amount=85.25, category_code="OPEX-SHOPPING")
    assert res.status_code == 200, res.text
    assert res.json()["amount"] == 85.25
    (row,) = _txs(fake_supabase)
    assert row["amount"] == 85.25 and row["category_code"] == "OPEX-SHOPPING"
    # Several scanned lines stay as scanned.
    assert [i["name"] for i in row["items"]] == ["Milk", "Rice 5kg"]
    assert len(llm.calls) == 1


def test_receipt_unknown_category_or_bad_amount_is_422(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    assert _receipt(api, flat, "ahmed", preview_token=token, category_code="OPEX-NOPE").status_code == 422
    assert _receipt(api, flat, "ahmed", preview_token=token, amount=-1).status_code == 422
    assert _txs(fake_supabase) == []


def test_receipt_without_edits_keeps_the_scanned_values(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    assert _receipt(api, flat, "ahmed", preview_token=token).status_code == 200
    row = _txs(fake_supabase)[-1]
    assert row["amount"] == 82.5 and row["category_code"] == "OPEX-GROCERY"
