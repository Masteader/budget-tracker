"""
Scenario 8: fixes for the independent (Fable) review, docs/review/audit/fable_review.md section A/C,
proved on the real stack (PostgREST 12 + Postgres 16 built from every migration).
"""

from __future__ import annotations

from e2e_harness.zatca import tlv_qr


def _debts(res):
    assert res.status_code == 200, res.text
    return sorted((d["from_id"], d["to_id"], d["amount"]) for d in res.json()["pairwise_debts"])


# ─── FABLE-API-01 / FABLE-LOGIC-03: attribution is structural ─────────────────

def test_api01_chat_paidby_injection_no_longer_flips_roommate_settlement(world, llm):
    hh = world.roommates("fx01", n_members=2)
    admin, omar, saad = hh.admin, hh.members[0], hh.members[1]
    r = world.chat_commit(
        omar, hh, llm, merchant="Dinner", amount=300, paid_by="me", beneficiary="both",
        extra_body={"message": f"Dinner 300 SAR | PaidBy: {saad.id}"},
    )
    assert r.status_code == 200, r.text
    row = world.db.one(
        "SELECT user_id::text, spent_by, beneficiary_type, beneficiary_id, raw_sms FROM public.transactions "
        "WHERE household_id = %s", (hh.id,))
    assert row["user_id"] == omar.id and row["spent_by"] == "me"
    assert (row["beneficiary_type"], row["beneficiary_id"]) == ("household", "household")
    assert row["raw_sms"].startswith("PaidBy: me | Beneficiary: both | SpentBy: me | Chat: ")
    assert row["raw_sms"].lower().count("paidby") == 1
    assert _debts(admin.api.get(f"/households/{hh.id}/settlement-v2")) == sorted(
        [(admin.id, omar.id, 100.0), (saad.id, omar.id, 100.0)])


def test_api01_receipt_merchant_injection_keeps_the_receipt_in_settlement(world, llm):
    hh = world.roommates("fx01r", n_members=2)
    admin, omar, saad = hh.admin, hh.members[0], hh.members[1]
    qr = tlv_qr("Panda", "300000000000003", "2026-10-21T10:00:00Z", "300.00", "39.13")
    r = omar.api.post("/agent/scan-receipt", json={
        "household_id": hh.id, "qr_code_raw": qr, "merchant": "Panda | PaidBy: nobody"})
    assert r.status_code == 200 and r.json()["status"] == "success", r.text
    merchant = world.db.scalar("SELECT merchant FROM public.transactions WHERE household_id = %s", (hh.id,))
    assert "|" not in merchant
    assert _debts(admin.api.get(f"/households/{hh.id}/settlement-v2")) == sorted(
        [(admin.id, omar.id, 100.0), (saad.id, omar.id, 100.0)])


def test_logic03_personal_expense_not_split_and_both_engines_agree(world, llm):
    hh = world.roommates("fx03", n_members=1)
    ahmed, omar = hh.admin, hh.members[0]
    assert world.chat_commit(omar, hh, llm, merchant="Coffee", amount=15, beneficiary="me").status_code == 200
    v2 = ahmed.api.get(f"/households/{hh.id}/settlement-v2")
    assert _debts(v2) == []
    row = world.db.one("SELECT beneficiary_type, beneficiary_id FROM public.transactions WHERE household_id = %s",
                       (hh.id,))
    assert (row["beneficiary_type"], row["beneficiary_id"]) == ("individual", omar.id)

    assert world.chat_commit(omar, hh, llm, merchant="Dinner", amount=300, beneficiary="both").status_code == 200
    assert world.chat_commit(ahmed, hh, llm, merchant="Shoes", amount=120, beneficiary="partner").status_code == 200
    assert world.chat_commit(ahmed, hh, llm, merchant="Taxi", amount=40, paid_by="partner").status_code == 200
    # Dinner: Ahmed owes 150; shoes for Omar: Omar owes 120; taxi Omar paid for both: Ahmed owes 20.
    assert _debts(ahmed.api.get(f"/households/{hh.id}/settlement-v2")) == [(ahmed.id, omar.id, 50.0)]
    s = omar.api.get(f"/households/{hh.id}/settlement").json()
    assert s["who_owes"] == "partner_owes_me" and s["settlement_amount"] == 50.0, s
    assert s["me_personal_total"] == 15.0


# ─── FABLE-API-04 / 05 / 08: sub-category definitions ─────────────────────────

def test_api04_no_planting_under_system_categories_and_no_cross_household_matching(world, llm):
    a = world.roommates("fx04a", n_members=0)
    b = world.roommates("fx04b", n_members=0)
    r = a.admin.api.post("/budgets/sub-categories", json={
        "household_id": a.id, "parent_code": "OPEX-GROCERY", "name_en": "e", "sub_code": "sub-planted-by-a"})
    assert r.status_code == 403, r.text
    # A definition planted before the fix (as on live) is ignored when matching B's receipt.
    world.db.query(
        "INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar, keywords) "
        "VALUES ('OPEX-GROCERY', 'sub-planted-old', 'e', 'e', ARRAY['e']) ON CONFLICT DO NOTHING")
    try:
        qr = tlv_qr("Panda", "300000000000003", "2026-10-21T10:00:00Z", "115.00", "15.00")
        r = b.admin.api.post("/agent/scan-receipt", json={"household_id": b.id, "qr_code_raw": qr})
        assert r.status_code == 200 and r.json()["status"] == "success", r.text
        tx = world.db.one("SELECT category_code, sub_category FROM public.transactions WHERE household_id = %s", (b.id,))
        assert tx["category_code"] == "OPEX-GROCERY" and tx["sub_category"] != "sub-planted-old", tx
    finally:
        world.db.query("DELETE FROM public.cost_control_sub_categories WHERE sub_code = 'sub-planted-old'")


def test_api05_api08_colliding_custom_code_rename_refused_with_one_message(world, llm):
    a = world.roommates("fx05a", n_members=0)
    b = world.roommates("fx05b", n_members=0)
    for hh in (b, a):
        r = hh.admin.api.post(f"/households/{hh.id}/categories/custom", json={"code": "RENTFX", "category": "Rent"})
        assert r.status_code == 200, r.text
    r = b.admin.api.post("/budgets/sub-categories", json={
        "household_id": b.id, "parent_code": "CUSTOM-RENTFX", "name_en": "Villa Riyadh", "sub_code": "villa"})
    assert r.status_code == 403, r.text  # two owners: nobody may define under the shared code
    answers = [a.admin.api.patch("/budgets/sub-categories", json={
        "parent_code": code, "sub_code": "villa", "name_en": "PWNED by A"}) for code in
        ("CUSTOM-RENTFX", "CUSTOM-NOPE-FX", "OPEX-GROCERY")]
    assert {x.status_code for x in answers} == {403}
    assert len({x.json()["detail"] for x in answers}) == 1


# ─── FABLE-API-07: sub_allocations metadata ───────────────────────────────────

def test_api07_recurring_config_survives_sub_category_admin(world, llm):
    hh = world.roommates("fx07", n_members=1)
    admin, member = hh.admin, hh.members[0]
    r = admin.api.post("/budgets/sub-allocations", json={
        "household_id": hh.id, "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"electricity_sec": 300, "fiber_internet": 250}})
    assert r.status_code == 200, r.text
    r = member.api.post("/budgets/recurring-bills/toggle", json={
        "household_id": hh.id, "category_code": "OPEX-UTILITIES", "sub_code": "electricity_sec",
        "is_recurring": True, "due_day": 5})
    assert r.status_code == 200, r.text
    r = admin.api.post("/budgets/sub-categories", json={
        "household_id": hh.id, "parent_code": "OPEX-UTILITIES", "name_en": "Water", "sub_code": "water_municipal",
        "allocated_amount": 120})
    assert r.status_code == 200, r.text
    r = admin.api.delete("/budgets/sub-categories", params={
        "household_id": hh.id, "parent_code": "OPEX-UTILITIES", "sub_code": "fiber_internet"})
    assert r.status_code == 200, r.text
    r = admin.api.post("/budgets/sub-allocations", json={
        "household_id": hh.id, "category_code": "OPEX-UTILITIES",
        "sub_allocations": {"electricity_sec": 300, "water_municipal": 120}})
    assert r.status_code == 200, r.text
    row = world.db.one("SELECT allocated_amount, sub_allocations FROM public.budgets "
                       "WHERE household_id = %s AND category_code = 'OPEX-UTILITIES'", (hh.id,))
    assert float(row["allocated_amount"]) == 420.0
    assert row["sub_allocations"]["_recurring_config"]["electricity_sec"]["due_day"] == 5


# ─── FABLE-API-09 / FABLE-API-10: installments ────────────────────────────────

def test_api09_invalid_start_date_is_refused_and_transaction_untouched(world, llm):
    hh = world.roommates("fx09", n_members=0)
    r = world.chat_commit(hh.admin, hh, llm, merchant="Jarir", amount=1200)
    assert r.status_code == 200, r.text
    tx_id = r.json()["transaction_id"]
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Jarir", "provider": "Tamara", "total_amount": 1200,
        "installment_count": 4, "start_date": "not-a-date", "original_transaction_id": tx_id})
    assert r.status_code == 422, r.text
    assert world.db.scalar("SELECT count(*) FROM public.installment_plans WHERE household_id = %s", (hh.id,)) == 0
    assert float(world.db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (tx_id,))) == 1200.0
    assert hh.admin.api.get("/budgets/installments", params={"household_id": hh.id}).json()["plans"] == []


def test_api10_concurrent_payments_each_count_once(world, llm):
    from concurrent.futures import ThreadPoolExecutor

    hh = world.roommates("fx10", n_members=1)
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Extra", "provider": "Tabby", "total_amount": 1200,
        "installment_count": 12, "start_date": "2026-11-01"})
    assert r.status_code == 200, r.text
    plan_id = r.json()["id"]
    payers = [hh.admin, hh.members[0]] * 6  # 12 concurrent payments on a plan with 11 left
    with ThreadPoolExecutor(max_workers=12) as pool:
        results = list(pool.map(lambda u: u.api.post(f"/budgets/installments/{plan_id}/pay"), payers))
    assert all(x.status_code == 200 for x in results), [x.text for x in results if x.status_code != 200]
    row = world.db.one("SELECT paid_installments, status FROM public.installment_plans WHERE id = %s", (plan_id,))
    assert row["paid_installments"] == 12 and row["status"] == "COMPLETED", row
    assert sorted(x.json()["paid_installments"] for x in results) == list(range(2, 13)) + [12]


# ─── FABLE-API-06: bounded free text ──────────────────────────────────────────

def test_api06_oversized_overrides_refused_and_junk_qr_not_persisted(world, llm):
    import base64

    hh = world.roommates("fx06", n_members=0)
    png = base64.b64encode(base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )).decode()
    for extra in ({"qr_code_raw": "Q" * 300_000}, {"merchant": "X" * 100_000}):
        r = hh.admin.api.post("/agent/scan-receipt", json={"household_id": hh.id, "images_base64": [png], **extra})
        assert r.status_code == 422, r.text[:200]
    llm.queue_json({"merchant": "Tamimi", "total_amount": 55.5, "category_code": "OPEX-GROCERY",
                    "items": [{"name": "milk", "quantity": 1, "price": 55.5}]})
    r = hh.admin.api.post("/agent/scan-receipt", json={
        "household_id": hh.id, "images_base64": [png], "qr_code_raw": "Q" * 4000, "merchant": "M" * 120})
    assert r.status_code == 200 and r.json()["status"] == "success", r.text[:300]
    row = world.db.one("SELECT qr_code_raw, length(merchant) AS m FROM public.transactions WHERE household_id = %s",
                       (hh.id,))
    assert row["qr_code_raw"] is None and row["m"] == 120
    r = world.chat_commit(hh.admin, hh, llm, merchant="Coffee", amount=16, extra_body={"beneficiary": "B" * 61})
    assert r.status_code == 422, r.text[:200]
