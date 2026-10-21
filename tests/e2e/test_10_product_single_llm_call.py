"""
Product review (2026-10-21) R6 / R9 / 3.3 on the real stack (PostgREST + local Postgres; only the
LLM and Storage are faked):

* a chat or receipt commit that sends back the preview's ``preview_token`` makes no LLM call;
* a tampered token is 422 ``invalid_preview_token``;
* a receipt photo reaches Storage only after the transaction row exists, and the row links it;
* ``budgets.spent_amount`` follows inserts through the database triggers alone, and
  ``POST /budgets/recalculate`` repairs a cycle through ``recompute_budget_spent`` (service role).
"""

from __future__ import annotations

import base64
import io
import json
import uuid

from PIL import Image

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


def _jpeg() -> str:
    buf = io.BytesIO()
    Image.new("RGB", (40, 60), (250, 250, 250)).save(buf, "JPEG")
    return base64.b64encode(buf.getvalue()).decode()


def _current_cycle(db) -> str:
    return db.scalar("SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 27)")


def test_chat_preview_then_commit_is_one_llm_call_and_triggers_keep_the_budget(world, db, llm):
    flat = world.roommates("P10a", n_members=1)
    user = flat.admin
    key = _current_cycle(db)
    db.query(
        "INSERT INTO public.budgets (household_id, category_code, month, cycle_key, allocated_amount, spent_amount)"
        " VALUES (%s, 'OPEX-DINING', to_date(%s || '-01', 'YYYY-MM-DD'), %s, 500, 0)",
        (flat.id, key, key),
    )
    llm.queue_json(CHAT_PARSE)
    body = {"household_id": flat.id, "message": "Albaik broast 46 riyal", "allow_duplicate": True}
    preview = user.api.post("/agent/chat-transaction", json={**body, "preview_only": True})
    assert preview.status_code == 200, preview.text
    token = preview.json()["preview_token"]
    assert len(llm.calls) == 1

    forged = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(forged[2] + "=" * (-len(forged[2]) % 4)))
    claims["p"]["total_amount"] = 1.0
    forged[2] = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=").decode()
    bad = user.api.post("/agent/chat-transaction", json={**body, "preview_token": ".".join(forged)})
    assert bad.status_code == 422 and bad.json()["detail"] == {"code": "invalid_preview_token"}

    commit = user.api.post(
        "/agent/chat-transaction", json={**body, "preview_token": token},
        headers={"Idempotency-Key": f"p10-{uuid.uuid4().hex}"},
    )
    assert commit.status_code == 200, commit.text
    assert commit.json()["status"] == "success"
    assert len(llm.calls) == 1, "the commit must not call the LLM again"
    row = db.one("SELECT amount, merchant, category_code, user_id::text FROM public.transactions WHERE id = %s",
                 (commit.json()["transaction_id"],))
    assert float(row["amount"]) == 46.0 and row["merchant"] == "Albaik" and row["user_id"] == user.id

    spent = db.scalar("SELECT spent_amount FROM public.budgets WHERE household_id = %s AND cycle_key = %s", (flat.id, key))
    assert float(spent) == 46.0  # trigger only (the API no longer recalculates per insert)

    db.query("UPDATE public.budgets SET spent_amount = 999 WHERE household_id = %s AND cycle_key = %s", (flat.id, key))
    fix = user.api.post(f"/budgets/recalculate?household_id={flat.id}&cycle_key={key}")
    assert fix.status_code == 200, fix.text
    spent = db.scalar("SELECT spent_amount FROM public.budgets WHERE household_id = %s AND cycle_key = %s", (flat.id, key))
    assert float(spent) == 46.0  # recompute_budget_spent through PostgREST as service_role


def test_receipt_preview_then_commit_is_one_vision_call_and_uploads_after_insert(world, db, llm, stack):
    flat = world.roommates("P10b", n_members=1)
    user = flat.admin
    photo = _jpeg()
    llm.queue_json(RECEIPT_PARSE)
    before = set(stack.gateway.storage)
    preview = user.api.post("/agent/scan-receipt", json={
        "household_id": flat.id, "images_base64": [photo], "preview_only": True,
    })
    assert preview.status_code == 200, preview.text
    p = preview.json()
    assert p["status"] == "preview" and p["preview_token"]
    assert set(stack.gateway.storage) == before, "a preview uploads nothing"

    commit = user.api.post("/agent/scan-receipt", json={
        "household_id": flat.id, "images_base64": [photo], "preview_token": p["preview_token"],
        "merchant": "Danube Hittin", "allow_duplicate": True,
    }, headers={"Idempotency-Key": f"p10r-{uuid.uuid4().hex}"})
    assert commit.status_code == 200, commit.text
    c = commit.json()
    assert c["status"] == "success", c
    assert len(llm.calls) == 1, "the commit must not call the vision model again"
    row = db.one("SELECT amount, merchant, receipt_url, items FROM public.transactions WHERE id = %s",
                 (c["transaction_id"],))
    assert float(row["amount"]) == 82.5 and row["merchant"] == "Danube Hittin"
    assert row["receipt_url"] and row["receipt_url"].startswith(f"{flat.id}/")
    assert row["receipt_url"] == c["receipt_url"]
    assert any(k.endswith(row["receipt_url"]) for k in set(stack.gateway.storage) - before)
