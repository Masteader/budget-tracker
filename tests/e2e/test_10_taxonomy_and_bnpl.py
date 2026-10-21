"""
Scenario 10: Saudi taxonomy (product review R4) and the BNPL payment schedule (R10), migration
20261021000000, proved on the real stack (PostgREST 12 + Postgres 16 built from every migration).
"""

from __future__ import annotations

NEW_CODES = {"OPEX-HOUSING", "OPEX-EDUCATION", "OPEX-DOMESTIC-HELP", "OPEX-FAMILY-SUPPORT",
             "OPEX-CHARITY", "OPEX-TRANSPORT", "OPEX-INSURANCE", "OPEX-REMITTANCE"}


# ─── R10: frequency + next_due_at ─────────────────────────────────────────────

def test_tabby_pay_in_4_is_biweekly_and_payments_advance_next_due(world, db):
    hh = world.roommates("bn1", n_members=1)
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Noon", "provider": "Tabby", "total_amount": 999.99,
        "start_date": "2026-10-01"})
    assert r.status_code == 200, r.text
    plan = r.json()
    assert (plan["frequency"], plan["next_due_at"], plan["monthly_amount"]) == ("biweekly", "2026-10-15", 250.0)
    row = db.one("SELECT frequency, next_due_at::text AS due, installment_count FROM public.installment_plans "
                 "WHERE id = %s", (plan["id"],))
    assert row == {"frequency": "biweekly", "due": "2026-10-15", "installment_count": 4}

    listed = hh.members[0].api.get("/budgets/installments", params={"household_id": hh.id}).json()["plans"]
    assert [(p["id"], p["frequency"], p["next_due_at"]) for p in listed] == [(plan["id"], "biweekly", "2026-10-15")]

    dues = []
    for payer in (hh.admin, hh.members[0], hh.admin):
        res = payer.api.post(f"/budgets/installments/{plan['id']}/pay")
        assert res.status_code == 200, res.text
        dues.append(res.json()["next_due_at"])
    assert dues == ["2026-10-29", "2026-11-12", None]
    assert db.scalar("SELECT status FROM public.installment_plans WHERE id = %s", (plan["id"],)) == "COMPLETED"


def test_bank_plan_is_monthly_from_the_anchor(world, db):
    hh = world.roommates("bn2", n_members=0)
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Jarir", "provider": "Bank", "total_amount": 1000,
        "installment_count": 3, "start_date": "2026-01-31"})
    assert r.status_code == 200, r.text
    assert (r.json()["frequency"], r.json()["next_due_at"]) == ("monthly", "2026-02-28")
    res = hh.admin.api.post(f"/budgets/installments/{r.json()['id']}/pay")
    assert res.status_code == 200 and res.json()["next_due_at"] == "2026-03-31", res.text
    # Explicit frequency wins over the provider default; unknown values are refused.
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Shein", "provider": "Tamara", "total_amount": 300,
        "installment_count": 3, "frequency": "monthly", "start_date": "2026-10-05"})
    assert r.status_code == 200 and r.json()["next_due_at"] == "2026-11-05", r.text
    r = hh.admin.api.post("/budgets/installments", json={
        "household_id": hh.id, "merchant": "Shein", "total_amount": 300, "frequency": "weekly"})
    assert r.status_code == 422, r.text


def test_clients_cannot_forge_the_schedule(world, db):
    hh = world.roommates("bn3", n_members=0)
    res = hh.admin.rest.post("/installment_plans", headers={"Prefer": "return=representation"}, json={
        "household_id": hh.id, "merchant": "Direct", "provider": "Tabby", "total_amount": 400,
        "installment_count": 4, "monthly_amount": 100, "paid_installments": 1, "start_date": "2026-10-01",
        "frequency": "biweekly", "next_due_at": "2030-01-01"})
    assert res.status_code == 201, res.text
    plan = res.json()[0]
    assert plan["next_due_at"] == "2026-10-15"  # derived by the trigger, not taken from the client
    for patch in ({"next_due_at": "2030-01-01"}, {"frequency": "monthly"}, {"paid_installments": 4}):
        res = hh.admin.rest.patch(f"/installment_plans?id=eq.{plan['id']}", json=patch)
        assert res.status_code in (401, 403), (patch, res.status_code, res.text)
    assert db.scalar("SELECT next_due_at::text FROM public.installment_plans WHERE id = %s", (plan["id"],)) == "2026-10-15"


def test_legacy_notes_are_not_reconstructed_into_plans(world, db, llm):
    hh = world.roommates("bn4", n_members=0)
    r = world.chat_commit(hh.admin, hh, llm, merchant="eXtra", amount=300)
    assert r.status_code == 200, r.text
    db.query("UPDATE public.transactions SET raw_sms = raw_sms || %s WHERE id = %s",
             (" [Financed via Tamara: Installment 1 of 4. Full price: SAR 1,200.00]", r.json()["transaction_id"]))
    assert hh.admin.api.get("/budgets/installments", params={"household_id": hh.id}).json()["plans"] == []


# ─── R4: taxonomy ─────────────────────────────────────────────────────────────

def test_new_categories_are_available_not_budgeted_until_added(world, db):
    hh = world.roommates("tx1", n_members=1)
    cats = hh.members[0].api.get(f"/households/{hh.id}/categories")
    assert cats.status_code == 200, cats.text
    inactive = {c["code"]: c["category"] for c in cats.json()["inactive"]}
    assert NEW_CODES <= set(inactive), inactive
    assert inactive["OPEX-HOUSING"] == "Housing & Rent" and inactive["OPEX-CHARITY"] == "Charity & Zakat"
    assert not NEW_CODES & {c["code"] for c in cats.json()["active"]}

    subs = hh.members[0].api.get("/budgets/sub-categories", params={"parent_code": "OPEX-HOUSING",
                                                                     "household_id": hh.id})
    assert subs.status_code == 200, subs.text
    names = {s["sub_code"]: (s["name_en"], s["name_ar"]) for s in subs.json()["sub_categories"]}
    assert names == {"housing_rent": ("Housing Rent", "إيجار السكن"),
                     "annual_rent": ("Annual / Semi-annual Rent", "الإيجار السنوي ونصف السنوي"),
                     "housing_services": ("Building Services & Home Repairs", "خدمات السكن والصيانة")}

    # The admin adds a budget: the category becomes active, the system definition is untouched.
    res = hh.admin.api.post("/budgets/categories", json={
        "household_id": hh.id, "code": "OPEX-HOUSING", "category": "My rent", "allocated_amount": 3000})
    assert res.status_code == 200, res.text
    active = {c["code"] for c in hh.admin.api.get(f"/households/{hh.id}/categories").json()["active"]}
    assert "OPEX-HOUSING" in active
    assert db.scalar("SELECT category FROM public.cost_control_codes WHERE code = 'OPEX-HOUSING' "
                     "AND household_id IS NULL") == "Housing & Rent"
    assert db.scalar("SELECT count(*) FROM public.cost_control_codes WHERE code = 'OPEX-HOUSING'") == 1


def test_rent_expense_lands_in_the_new_housing_sub_category(world, db, llm):
    hh = world.roommates("tx2", n_members=0)
    res = world.chat_commit(hh.admin, hh, llm, merchant="Ejar", amount=2500, category_code="OPEX-HOUSING")
    assert res.status_code == 200, res.text
    row = db.one("SELECT category_code, sub_category FROM public.transactions WHERE id = %s",
                 (res.json()["transaction_id"],))
    assert row["category_code"] == "OPEX-HOUSING"
    assert row["sub_category"] == "housing_rent", row
