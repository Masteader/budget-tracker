"""
Product review R4 (Saudi taxonomy) and R10 (BNPL schedule), migration 20261021000000.

- Installment amounts are exact in halalas (the last installment absorbs the remainder) and due
  every two weeks (Tabby / Tamara "Pay in 4", first payment at purchase) or every month (bank).
- ``frequency`` defaults by provider; the API returns ``frequency`` and ``next_due_at``; a payment
  advances ``next_due_at`` by one interval.
- ``list_plans`` reads installment_plans rows only; legacy "Financed via" notes become rows only
  through the explicit, idempotent backfill.
- The new system sub-categories are trusted for keyword matching and the new categories are
  "available, not budgeted" for existing households.
"""
from __future__ import annotations

import os
import re
from datetime import date
from decimal import Decimal

import pytest
from pydantic import ValidationError
from starlette.testclient import TestClient

from installment_service import (
    InstallmentPlan,
    InstallmentPlanCreate,
    InstallmentService,
    calculate_installment_terms,
    default_frequency_for_provider,
    installment_amounts,
    installment_due_date,
    next_due_date,
)

HID = "f860188e-23b5-4749-b180-868c956151a6"
CALLER = "00000000-0000-0000-0000-000000000001"
HEADERS = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}
MIGRATION = os.path.join(os.path.dirname(__file__), "..", "..", "supabase", "migrations",
                         "20261021000000_saudi_taxonomy_and_bnpl_schedule.sql")


@pytest.fixture
def api(fake_supabase):
    fake_supabase.seed("household_memberships", [{"household_id": HID, "user_id": CALLER, "role": "admin"}])
    from main import app

    return TestClient(app)


# ─── Amounts and dates ────────────────────────────────────────────────────────

@pytest.mark.parametrize("total,count", [
    (100, 3), (0.5, 4), (7408, 4), (999.99, 4), (0.09, 12), (0.01, 60), (1234.56, 7), (10_000_000, 60),
])
def test_installment_amounts_are_exact_halalas(total, count):
    amounts = installment_amounts(total, count)
    assert len(amounts) == count
    assert sum(Decimal(str(a)) for a in amounts) == Decimal(str(total)).quantize(Decimal("0.01"))
    assert all(a >= 0 for a in amounts)
    assert len(set(amounts[:-1])) <= 1  # every installment but the last is the same


def test_last_installment_absorbs_the_remainder():
    assert installment_amounts(100, 3) == [33.33, 33.33, 33.34]
    assert installment_amounts(0.5, 4) == [0.13, 0.13, 0.13, 0.11]
    assert installment_amounts(0.09, 12)[-1] == 0.09  # half-up would make the last one negative


def test_due_dates_biweekly_and_monthly_from_the_anchor():
    start = date(2026, 1, 31)
    assert [installment_due_date(start, "biweekly", i).isoformat() for i in range(4)] == [
        "2026-01-31", "2026-02-14", "2026-02-28", "2026-03-14"]
    # Month arithmetic from the anchor, like PostgreSQL: no drift after February.
    assert [installment_due_date(start, "monthly", i).isoformat() for i in range(4)] == [
        "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]
    assert installment_due_date(date(2027, 12, 31), "monthly", 2).isoformat() == "2028-02-29"
    assert next_due_date("2026-10-01", "biweekly", 4, 4) is None
    assert next_due_date("2026-10-01", "biweekly", 1, 4, "CANCELLED") is None
    assert next_due_date("2026-10-01", "biweekly", 0, 4) == "2026-10-01"


def test_terms_pay_in_4_every_two_weeks_first_at_purchase():
    terms = calculate_installment_terms(999.99, 4, start_date=date(2026, 10, 1), frequency="biweekly")
    assert terms["frequency"] == "biweekly"
    assert [(s["due_date"], s["amount"], s["paid"]) for s in terms["schedule"]] == [
        ("2026-10-01", 250.0, True), ("2026-10-15", 250.0, False),
        ("2026-10-29", 250.0, False), ("2026-11-12", 249.99, False)]
    assert terms["monthly_amount"] == 250.0 and terms["final_installment_amount"] == 249.99
    assert terms["remaining_amount"] == 749.99 and terms["remaining_installments"] == 3
    assert terms["next_due_at"] == "2026-10-15"
    with pytest.raises(ValueError):
        calculate_installment_terms(100, 4, frequency="weekly")


# ─── Frequency defaults and the API contract ──────────────────────────────────

@pytest.mark.parametrize("provider,count,want", [
    ("Tabby", 4, "biweekly"), ("TAMARA", 4, "biweekly"), (" tamara ", 4, "biweekly"),
    ("Tamara", 3, "monthly"), ("Tabby", 12, "monthly"), ("Bank", 4, "monthly"), ("Other", 4, "monthly"),
])
def test_default_frequency_by_provider(provider, count, want):
    assert default_frequency_for_provider(provider, count) == want
    req = InstallmentPlanCreate(household_id=HID, merchant="m", provider=provider, total_amount=400,
                                installment_count=count)
    assert req.frequency == want


def test_explicit_frequency_wins_and_unknown_is_refused():
    req = InstallmentPlanCreate(household_id=HID, merchant="m", provider="Tabby", total_amount=400,
                                frequency="Monthly")
    assert req.frequency == "monthly"
    with pytest.raises(ValidationError):
        InstallmentPlanCreate(household_id=HID, merchant="m", total_amount=400, frequency="weekly")


def test_api_tabby_plan_is_biweekly_and_payments_advance_next_due(api, fake_supabase):
    r = api.post("/budgets/installments", headers=HEADERS, json={
        "household_id": HID, "merchant": "Noon", "provider": "Tabby", "total_amount": 999.99,
        "start_date": "2026-10-01", "adjust_original_transaction": False})
    assert r.status_code == 200, r.text
    plan = r.json()
    assert plan["frequency"] == "biweekly" and plan["next_due_at"] == "2026-10-15"
    assert plan["installment_count"] == 4 and plan["paid_installments"] == 1 and plan["monthly_amount"] == 250.0
    stored = fake_supabase.tables["installment_plans"][0]
    assert stored["frequency"] == "biweekly" and stored["next_due_at"] == "2026-10-15"

    listed = api.get(f"/budgets/installments?household_id={HID}", headers=HEADERS).json()["plans"]
    assert [(p["frequency"], p["next_due_at"]) for p in listed] == [("biweekly", "2026-10-15")]

    dues = [api.post(f"/budgets/installments/{plan['id']}/pay", headers=HEADERS).json()["next_due_at"]
            for _ in range(3)]
    assert dues == ["2026-10-29", "2026-11-12", None]
    assert fake_supabase.tables["installment_plans"][0]["status"] == "COMPLETED"


def test_api_bank_plan_is_monthly(api):
    r = api.post("/budgets/installments", headers=HEADERS, json={
        "household_id": HID, "merchant": "Jarir", "provider": "Bank", "total_amount": 1000,
        "installment_count": 3, "start_date": "2026-01-31", "adjust_original_transaction": False})
    assert r.status_code == 200, r.text
    assert (r.json()["frequency"], r.json()["next_due_at"], r.json()["monthly_amount"]) == (
        "monthly", "2026-02-28", 333.33)


def test_api_refuses_an_unknown_frequency(api, fake_supabase):
    r = api.post("/budgets/installments", headers=HEADERS, json={
        "household_id": HID, "merchant": "Noon", "total_amount": 100, "frequency": "weekly"})
    assert r.status_code == 422, r.text
    assert not fake_supabase.tables.get("installment_plans")


def test_plan_rows_from_an_older_database_still_load():
    plan = InstallmentPlan(id="p", household_id=HID, merchant="m", total_amount=100, monthly_amount=25,
                           start_date="2026-10-01T00:00:00")
    assert plan.frequency == "monthly" and plan.next_due_at is None and plan.start_date == "2026-10-01"


# ─── No regex reconstruction; explicit legacy backfill ────────────────────────

LEGACY_TX = {
    "id": "aaaaaaaa-0000-4000-8000-0000000000aa", "household_id": HID, "merchant": "eXtra",
    "amount": 300.0, "category_code": "OPEX-SHOPPING", "timestamp": "2026-09-10T12:00:00+03:00",
    "raw_sms": "Chat: eXtra 1200 [Financed via Tamara: Installment 1 of 4. Full price: SAR 1,200.00]",
}


def test_list_plans_reads_rows_only(fake_supabase):
    fake_supabase.seed("transactions", [LEGACY_TX, {
        "id": "bbbbbbbb-0000-4000-8000-0000000000bb", "household_id": HID, "merchant": "Tabby",
        "amount": 50.0, "raw_sms": "Paid Tabby", "category_code": "OPEX-SHOPPING"}])
    assert InstallmentService.list_plans(HID) == []


def test_legacy_backfill_is_explicit_and_idempotent(fake_supabase):
    fake_supabase.seed("transactions", [LEGACY_TX, {
        "id": "bbbbbbbb-0000-4000-8000-0000000000bb", "household_id": HID, "merchant": "Tabby",
        "amount": 50.0, "raw_sms": "Paid Tabby", "category_code": "OPEX-SHOPPING"}])

    dry = InstallmentService.backfill_plans_from_legacy_notes(HID)
    assert dry["candidates"] == 1 and dry["created"] == 0 and not fake_supabase.tables.get("installment_plans")

    done = InstallmentService.backfill_plans_from_legacy_notes(HID, apply=True)
    assert done["created"] == 1
    plans = InstallmentService.list_plans(HID)
    assert len(plans) == 1
    p = plans[0]
    assert (p.provider, p.total_amount, p.installment_count, p.paid_installments, p.monthly_amount) == (
        "Tamara", 1200.0, 4, 1, 300.0)
    assert (p.frequency, p.start_date, p.next_due_at, p.original_transaction_id) == (
        "biweekly", "2026-09-10", "2026-09-24", LEGACY_TX["id"])
    assert fake_supabase.tables["transactions"][0]["amount"] == 300.0  # the transaction is not touched

    again = InstallmentService.backfill_plans_from_legacy_notes(HID, apply=True)
    assert again["candidates"] == 0 and again["created"] == 0
    assert len(fake_supabase.tables["installment_plans"]) == 1


def test_active_plans_are_listed_by_next_due_date(fake_supabase):
    base = {"household_id": HID, "merchant": "m", "total_amount": 400, "installment_count": 4,
            "monthly_amount": 100, "paid_installments": 1}
    fake_supabase.seed("installment_plans", [
        {**base, "id": "p-done", "status": "COMPLETED", "created_at": "2026-10-03"},
        {**base, "id": "p-late", "status": "ACTIVE", "next_due_at": "2026-11-20", "created_at": "2026-10-01"},
        {**base, "id": "p-soon", "status": "ACTIVE", "next_due_at": "2026-10-25", "created_at": "2026-10-02"},
    ])
    assert [p.id for p in InstallmentService.list_plans(HID)] == ["p-soon", "p-late", "p-done"]


# ─── Taxonomy ─────────────────────────────────────────────────────────────────

def _migration_sub_categories():
    sql = open(MIGRATION, encoding="utf-8").read()
    section = sql[sql.index("INSERT INTO public.cost_control_sub_categories"):sql.index("ON CONFLICT (parent_code, sub_code)")]
    return set(re.findall(r"\('(OPEX-[A-Z-]+)', '([a-z_]+)', '", section))


def test_system_sub_categories_match_the_migration():
    from salary_cycle import SAUDI_TAXONOMY_CATEGORIES, SYSTEM_SUB_CATEGORIES

    seeded = _migration_sub_categories()
    assert len(seeded) == 23
    assert {parent for parent, _ in seeded} == set(SAUDI_TAXONOMY_CATEGORIES)
    assert {s for s in SYSTEM_SUB_CATEGORIES if s[0] in SAUDI_TAXONOMY_CATEGORIES} == seeded
    assert ("OPEX-UTILITIES", "housing_rent") in SYSTEM_SUB_CATEGORIES  # the old row stays valid


def test_new_system_sub_category_keywords_match(fake_supabase):
    from salary_cycle import match_sub_category

    fake_supabase.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-HOUSING", "category": "Housing & Rent", "keywords": ["ejar"],
         "is_flexible": False, "is_system": True, "household_id": None}])
    fake_supabase.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-HOUSING", "sub_code": "housing_rent", "name_en": "Housing Rent",
         "name_ar": "إيجار السكن", "keywords": ["rent", "إيجار"]},
        {"parent_code": "OPEX-HOUSING", "sub_code": "annual_rent", "name_en": "Annual Rent",
         "name_ar": "الإيجار السنوي", "keywords": ["annual rent", "عقد إيجار"]}])
    assert match_sub_category("OPEX-HOUSING", "دفعة إيجار شهر اكتوبر") == "housing_rent"


def test_new_categories_are_available_but_not_budgeted(fake_supabase):
    from salary_cycle import get_household_categories

    fake_supabase.seed("cost_control_codes", [
        {"id": "c0", "code": "OPEX-GROCERY", "category": "Grocery", "keywords": ["tamimi"],
         "is_flexible": False, "is_system": True, "household_id": None},
        {"id": "c1", "code": "OPEX-HOUSING", "category": "Housing & Rent", "keywords": ["ejar"],
         "is_flexible": False, "is_system": True, "household_id": None},
        {"id": "c2", "code": "OPEX-CHARITY", "category": "Charity & Zakat", "keywords": ["zakat"],
         "is_flexible": False, "is_system": True, "household_id": None}])
    cats = get_household_categories(HID)
    assert {c["code"] for c in cats["active"]} == {"OPEX-GROCERY"}
    assert {c["code"] for c in cats["inactive"]} == {"OPEX-HOUSING", "OPEX-CHARITY"}

    # Once the household adds a budget for it, the category is active.
    fake_supabase.seed("budgets", [{"household_id": HID, "category_code": "OPEX-HOUSING", "is_active": True}])
    cats = get_household_categories(HID)
    assert {c["code"] for c in cats["active"]} == {"OPEX-GROCERY", "OPEX-HOUSING"}
