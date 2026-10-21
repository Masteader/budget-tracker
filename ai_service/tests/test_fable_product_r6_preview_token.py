"""
PRODUCT-R6 / R9 (docs/review/audit/product_review.md 2.1, 3.1, "Stop doing"): one LLM call per
expense.

The chat and receipt previews return a server-signed ``preview_token`` (HMAC over the parsed
payload, the user, the household, an expiry and the input digest). A commit that sends it back
inserts from the signed payload without calling the model; the user's edits go through the same
validation as before. Without a token the commit re-parses (installed apps keep working).
A tampered token, or one issued to someone else, is 422 ``{"detail": {"code":
"invalid_preview_token"}}``; an expired one falls back to re-parsing.

Receipts: the OCR runs at temperature 0.1-0.2, and the photo is uploaded to Storage only after
the transaction row exists (never before parsing, never for a refused insert).
"""
from __future__ import annotations

import base64
import io
import json
import types

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import preview_token as pt
from fable_world import World
from main import app


@pytest.fixture()
def api():
    return TestClient(app)


@pytest.fixture(autouse=True)
def _fresh_key(monkeypatch):
    monkeypatch.delenv("PREVIEW_TOKEN_SECRET", raising=False)
    pt.reset_preview_token_key()
    yield
    pt.reset_preview_token_key()


class LLM:
    """Counts model calls; answers with the queued payload."""

    def __init__(self, monkeypatch, payload: dict):
        import litellm

        self.calls = []
        self.payload = payload

        def completion(*_a, **kwargs):
            self.calls.append(kwargs)
            msg = types.SimpleNamespace(content=json.dumps(self.payload))
            return types.SimpleNamespace(choices=[types.SimpleNamespace(message=msg)])

        monkeypatch.setattr(litellm, "completion", completion)


CHAT_PARSE = {
    "is_transaction": True, "merchant": "Albaik", "total_amount": 46.0, "currency": "SAR",
    "category_code": "OPEX-DINING", "sub_category": "restaurants_dinners", "paid_by": "me", "beneficiary": "both",
    "items": [{"name": "Broast", "quantity": 2, "price": 46.0}],
}
RECEIPT_PARSE = {
    "merchant": "Danube", "total_amount": 82.5, "vat_amount": 10.76, "currency": "SAR", "date": None,
    "category_code": "OPEX-GROCERY", "zatca_qr_raw": None, "confidence": "high",
    "items": [{"name": "Milk", "quantity": 2, "price": 12.5}, {"name": "Rice 5kg", "quantity": 1, "price": 70.0}],
}


def _codes(fake):
    fake.seed("cost_control_codes", [
        {"id": c, "code": c, "category": c, "keywords": [], "is_flexible": c == "OPEX-MISC", "household_id": None}
        for c in ("OPEX-DINING", "OPEX-GROCERY", "OPEX-MISC", "OPEX-SHOPPING")
    ])


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


def _tamper(token: str) -> str:
    version, kid, body, sig = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    claims["p"]["total_amount"] = 1.0
    forged = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    return ".".join([version, kid, forged, sig])


# ─── token unit behaviour ──────────────────────────────────────────────────────

def test_token_round_trip_and_binding():
    tok = pt.issue_preview_token("chat", "u1", "h1", {"a": 1}, {"m": "x"})
    res = pt.verify_preview_token(tok, "chat", "u1", "h1")
    assert res.valid and res.payload == {"a": 1} and res.binding == {"m": "x"}


@pytest.mark.parametrize("args", [("receipt", "u1", "h1"), ("chat", "u2", "h1"), ("chat", "u1", "h2")])
def test_token_for_another_kind_user_or_household_is_invalid(args):
    tok = pt.issue_preview_token("chat", "u1", "h1", {"a": 1})
    with pytest.raises(pt.InvalidPreviewToken):
        pt.verify_preview_token(tok, *args)


@pytest.mark.parametrize("bad", ["", "nope", "pt1.a.b", "pt2.a.b.c", None, 42, "pt1." + "x" * (pt.MAX_PREVIEW_TOKEN_LENGTH)])
def test_malformed_tokens_are_invalid(bad):
    with pytest.raises(pt.InvalidPreviewToken):
        pt.verify_preview_token(bad, "chat", "u1", "h1")


def test_tampered_payload_or_signature_is_invalid():
    tok = pt.issue_preview_token("chat", "u1", "h1", {"total_amount": 46.0})
    with pytest.raises(pt.InvalidPreviewToken):
        pt.verify_preview_token(_tamper(tok), "chat", "u1", "h1")
    with pytest.raises(pt.InvalidPreviewToken):
        pt.verify_preview_token(tok[:-2] + ("AA" if not tok.endswith("AA") else "BB"), "chat", "u1", "h1")


def test_expired_token_reports_expired():
    tok = pt.issue_preview_token("chat", "u1", "h1", {"a": 1}, now=1_000)
    assert pt.verify_preview_token(tok, "chat", "u1", "h1", now=1_000 + pt.PREVIEW_TOKEN_TTL_SECONDS - 1).valid
    assert pt.verify_preview_token(tok, "chat", "u1", "h1", now=1_000 + pt.PREVIEW_TOKEN_TTL_SECONDS + 1).status == "expired"
    assert pt.PREVIEW_TOKEN_TTL_SECONDS == 15 * 60


def test_shared_secret_verifies_across_processes_random_key_does_not(monkeypatch):
    tok = pt.issue_preview_token("chat", "u1", "h1", {"a": 1})
    pt.reset_preview_token_key()  # another process without PREVIEW_TOKEN_SECRET
    assert pt.verify_preview_token(tok, "chat", "u1", "h1").status == "unverifiable"

    monkeypatch.setenv("PREVIEW_TOKEN_SECRET", "s" * 40)
    pt.reset_preview_token_key()
    tok = pt.issue_preview_token("chat", "u1", "h1", {"a": 1})
    pt.reset_preview_token_key()
    assert pt.verify_preview_token(tok, "chat", "u1", "h1").valid


def test_short_or_missing_secret_warns(monkeypatch, caplog):
    monkeypatch.setenv("PREVIEW_TOKEN_SECRET", "tiny-value")
    pt.reset_preview_token_key()
    with caplog.at_level("WARNING"):
        pt.issue_preview_token("chat", "u1", "h1", {})
    assert "PREVIEW_TOKEN_SECRET" in caplog.text and "tiny-value" not in caplog.text
    monkeypatch.delenv("PREVIEW_TOKEN_SECRET")
    pt.reset_preview_token_key()
    caplog.clear()
    with caplog.at_level("WARNING"):
        pt.issue_preview_token("chat", "u1", "h1", {})
    assert "PREVIEW_TOKEN_SECRET is not set" in caplog.text


def test_oversized_payload_gets_no_token():
    assert pt.issue_preview_token("receipt", "u1", "h1", {"x": "y" * pt.MAX_PREVIEW_TOKEN_LENGTH}) is None


# ─── chat ──────────────────────────────────────────────────────────────────────

def test_chat_commit_with_token_makes_no_llm_call(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    preview = _chat(api, flat, "ahmed", preview_only=True)
    assert preview.status_code == 200, preview.text
    p = preview.json()
    assert p["status"] == "pending_confirmation" and isinstance(p["preview_token"], str)
    assert len(llm.calls) == 1

    commit = _chat(api, flat, "ahmed", preview_token=p["preview_token"])
    assert commit.status_code == 200, commit.text
    c = commit.json()
    assert c["status"] == "success", c
    assert len(llm.calls) == 1, "the commit must not call the LLM again"
    (row,) = _txs(fake_supabase)
    assert row["amount"] == 46.0 and row["merchant"] == "Albaik" and row["category_code"] == "OPEX-DINING"
    assert row["user_id"] == flat.users["ahmed"]


def test_chat_commit_applies_user_edits_through_the_same_validation(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]

    unknown = _chat(api, flat, "ahmed", preview_token=token, category_code="OPEX-NOPE")
    assert unknown.status_code == 422  # category scoping, as without a token
    too_long = _chat(api, flat, "ahmed", preview_token=token, merchant="m" * 121)
    assert too_long.status_code == 422  # length limits, as without a token
    ok = _chat(api, flat, "ahmed", preview_token=token, merchant="Al Baik Olaya", category_code="OPEX-SHOPPING",
               paid_by="me", beneficiary="me")
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "success"
    row = _txs(fake_supabase)[-1]
    assert row["merchant"] == "Al Baik Olaya" and row["category_code"] == "OPEX-SHOPPING" and row["amount"] == 46.0
    assert len(llm.calls) == 1


def test_chat_family_rules_still_apply_with_a_token(api, family, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, family, "wife", preview_only=True).json()["preview_token"]
    # Contradiction: the wife says she paid for the household but files it as her allowance.
    bad = _chat(api, family, "wife", preview_token=token, paid_by="me", beneficiary="both",
                nafaqah_class="wife_personal")
    assert bad.status_code == 422, bad.text
    good = _chat(api, family, "wife", preview_token=token, nafaqah_class="wife_reimbursable")
    assert good.status_code == 200 and good.json()["status"] == "success", good.text
    row = _txs(fake_supabase)[-1]
    assert row["nafaqah_class"] == "wife_reimbursable" and row["nafaqah_spouse_id"] == family.users["wife"]
    assert len(llm.calls) == 1


def test_chat_tampered_token_is_422(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    for bad in (_tamper(token), "pt1.garbage", 12345):
        res = _chat(api, flat, "ahmed", preview_token=bad)
        assert res.status_code == 422, res.text
        assert res.json()["detail"] == {"code": "invalid_preview_token"}
    assert _txs(fake_supabase) == [] and len(llm.calls) == 1


def test_chat_token_of_another_member_is_422(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    res = _chat(api, flat, "omar", preview_token=token)
    assert res.status_code == 422 and res.json()["detail"] == {"code": "invalid_preview_token"}
    assert _txs(fake_supabase) == []


def test_chat_expired_token_re_parses(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    monkeypatch.setattr(pt, "PREVIEW_TOKEN_TTL_SECONDS", -1)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    res = _chat(api, flat, "ahmed", preview_token=token)
    assert res.status_code == 200 and res.json()["status"] == "success", res.text
    assert len(llm.calls) == 2


def test_chat_token_for_another_message_re_parses(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    llm.payload = dict(CHAT_PARSE, merchant="Kudu", total_amount=30.0, items=[])
    res = _chat(api, flat, "ahmed", message="Kudu 30 riyal", preview_token=token)
    assert res.status_code == 200 and res.json()["merchant"] == "Kudu"
    assert len(llm.calls) == 2


def test_chat_commit_without_token_still_parses(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    res = _chat(api, flat, "ahmed")
    assert res.status_code == 200 and res.json()["status"] == "success"
    assert len(llm.calls) == 1


def test_chat_duplicate_candidate_carries_a_token(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, CHAT_PARSE)
    assert _chat(api, flat, "ahmed").json()["status"] == "success"
    dup = _chat(api, flat, "ahmed", allow_duplicate=False)
    assert dup.json()["status"] == "duplicate_candidate"
    token = dup.json()["preview_token"]
    again = _chat(api, flat, "ahmed", preview_token=token, allow_duplicate=True)
    assert again.json()["status"] == "success"
    assert len(llm.calls) == 2  # the first commit and the duplicate check; not the third request


# ─── receipts ──────────────────────────────────────────────────────────────────

def test_ocr_temperature_is_low(monkeypatch):
    import receipt_scanner

    llm = LLM(monkeypatch, RECEIPT_PARSE)
    receipt_scanner.parse_receipt_images([_jpeg()])
    assert 0.1 <= llm.calls[0]["temperature"] <= 0.2


def test_receipt_commit_with_token_and_no_photo_makes_no_llm_call(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    preview = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True)
    assert preview.status_code == 200, preview.text
    p = preview.json()
    assert p["status"] == "preview" and isinstance(p["preview_token"], str)
    assert fake_supabase.storage_objects == {}, "nothing is uploaded for a preview"

    commit = _receipt(api, flat, "ahmed", preview_token=p["preview_token"], merchant="Danube Hittin")
    assert commit.status_code == 200, commit.text
    c = commit.json()
    assert c["status"] == "success", c
    assert len(llm.calls) == 1
    (row,) = _txs(fake_supabase)
    assert row["amount"] == 82.5 and row["merchant"] == "Danube Hittin"
    assert [i["name"] for i in row["items"]] == ["Milk", "Rice 5kg"]
    assert fake_supabase.storage_objects == {} and not row.get("receipt_url")


def test_receipt_commit_with_token_and_photo_uploads_after_insert(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    photo = _jpeg()
    token = _receipt(api, flat, "ahmed", images_base64=[photo], preview_only=True).json()["preview_token"]
    commit = _receipt(api, flat, "ahmed", images_base64=[photo], preview_token=token)
    assert commit.status_code == 200 and commit.json()["status"] == "success", commit.text
    assert len(llm.calls) == 1
    (row,) = _txs(fake_supabase)
    (bucket, path), = fake_supabase.storage_objects.keys()
    assert bucket == "receipts" and path.startswith(f"{flat.hid}/")
    assert row["receipt_url"] == path and commit.json()["receipt_url"] == path


def test_receipt_token_with_other_photos_re_parses(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    buf = io.BytesIO()
    Image.new("RGB", (50, 80), (10, 10, 10)).save(buf, "JPEG")
    other = base64.b64encode(buf.getvalue()).decode()
    res = _receipt(api, flat, "ahmed", images_base64=[other], preview_token=token)
    assert res.status_code == 200 and res.json()["status"] == "success"
    assert len(llm.calls) == 2


def test_receipt_tampered_token_is_422(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, flat, "ahmed", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    res = _receipt(api, flat, "ahmed", preview_token=_tamper_receipt(token))
    assert res.status_code == 422 and res.json()["detail"] == {"code": "invalid_preview_token"}
    chat_llm = LLM(monkeypatch, CHAT_PARSE)
    chat_token = _chat(api, flat, "ahmed", preview_only=True).json()["preview_token"]
    res = _receipt(api, flat, "ahmed", preview_token=chat_token)
    assert res.status_code == 422 and res.json()["detail"] == {"code": "invalid_preview_token"}
    assert _txs(fake_supabase) == [] and len(llm.calls) == 1 and len(chat_llm.calls) == 1


def _tamper_receipt(token: str) -> str:
    version, kid, body, sig = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    claims["p"]["parsed"]["total_amount"] = 1.0
    forged = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    return ".".join([version, kid, forged, sig])


def test_receipt_expired_token_without_photo_is_422_with_photo_re_parses(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    monkeypatch.setattr(pt, "PREVIEW_TOKEN_TTL_SECONDS", -1)
    photo = _jpeg()
    token = _receipt(api, flat, "ahmed", images_base64=[photo], preview_only=True).json()["preview_token"]
    res = _receipt(api, flat, "ahmed", preview_token=token)
    assert res.status_code == 422 and res.json()["detail"] == {"code": "preview_token_expired"}
    res = _receipt(api, flat, "ahmed", images_base64=[photo], preview_token=token)
    assert res.status_code == 200 and res.json()["status"] == "success"
    assert len(llm.calls) == 2


def test_receipt_family_rules_still_apply_with_a_token(api, family, fake_supabase, monkeypatch):
    LLM(monkeypatch, RECEIPT_PARSE)
    token = _receipt(api, family, "wife", images_base64=[_jpeg()], preview_only=True).json()["preview_token"]
    bad = _receipt(api, family, "wife", preview_token=token, paid_by="me", beneficiary="both",
                   nafaqah_class="wife_personal")
    assert bad.status_code == 422
    ok = _receipt(api, family, "wife", preview_token=token, nafaqah_class="wife_personal")
    assert ok.status_code == 200 and ok.json()["nafaqah_class"] == "wife_personal", ok.text


def test_receipt_without_photo_or_qr_or_token_is_still_400(api, flat):
    assert _receipt(api, flat, "ahmed").status_code == 400


# ─── R9: parse first, upload after insert ──────────────────────────────────────

def test_receipt_photo_is_not_uploaded_when_parsing_fails(api, flat, fake_supabase, monkeypatch):
    import litellm

    def broken(*_a, **_k):
        raise RuntimeError("model down")

    monkeypatch.setattr(litellm, "completion", broken)
    res = _receipt(api, flat, "ahmed", images_base64=[_jpeg()])
    assert res.json()["status"] == "error"
    assert fake_supabase.storage_objects == {}


def test_receipt_photo_is_not_uploaded_when_the_insert_is_refused(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, RECEIPT_PARSE)
    import receipt_scanner
    from supabase_client import TransactionRejectedError

    def refused(**_kw):
        raise TransactionRejectedError("23514")

    monkeypatch.setattr(receipt_scanner, "insert_transaction", refused)
    res = _receipt(api, flat, "ahmed", images_base64=[_jpeg()])
    assert res.status_code in (409, 422), res.text
    assert fake_supabase.storage_objects == {} and _txs(fake_supabase) == []


def test_receipt_commit_without_token_uploads_after_insert(api, flat, fake_supabase, monkeypatch):
    llm = LLM(monkeypatch, RECEIPT_PARSE)
    order = []
    import receipt_scanner

    real_insert = receipt_scanner.insert_transaction

    def insert(**kw):
        order.append("insert")
        assert fake_supabase.storage_objects == {}, "uploaded before the insert"
        return real_insert(**kw)

    monkeypatch.setattr(receipt_scanner, "insert_transaction", insert)
    res = _receipt(api, flat, "ahmed", images_base64=[_jpeg()])
    assert res.status_code == 200 and res.json()["status"] == "success", res.text
    assert order == ["insert"] and len(fake_supabase.storage_objects) == 1
    assert _txs(fake_supabase)[0]["receipt_url"] == res.json()["receipt_url"]
    assert len(llm.calls) == 1


def test_failed_upload_keeps_the_transaction(api, flat, fake_supabase, monkeypatch):
    LLM(monkeypatch, RECEIPT_PARSE)
    import fakes

    def boom(self, *a, **k):
        raise RuntimeError("storage down")

    monkeypatch.setattr(fakes.FakeBucket, "upload", boom)
    res = _receipt(api, flat, "ahmed", images_base64=[_jpeg()])
    assert res.status_code == 200 and res.json()["status"] == "success"
    assert res.json()["receipt_url"] is None and len(_txs(fake_supabase)) == 1
