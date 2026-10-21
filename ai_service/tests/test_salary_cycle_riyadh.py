"""API-14: salary cycle parity with the DB (Asia/Riyadh dates, household payday)."""

from datetime import date, datetime, timezone

import pytest

import utils
from salary_cycle import get_cycle_for_date, get_cycle_info_for_key, get_salary_cycle_dates
from utils import riyadh_date_for_timestamp


def freeze_utc(monkeypatch, iso: str):
    instant = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    monkeypatch.setattr(utils, "utc_now", lambda: instant)


def test_default_cycle_uses_riyadh_date_after_midnight_on_payday(monkeypatch):
    # 2026-10-26 22:30 UTC == 2026-10-27 01:30 Riyadh → payday has arrived in Riyadh.
    freeze_utc(monkeypatch, "2026-10-26T22:30:00Z")
    assert get_cycle_for_date()["cycle_key"] == "2026-11"
    assert get_salary_cycle_dates()["cycle_key"] == "2026-11"


def test_default_cycle_before_riyadh_midnight_stays_in_previous_cycle(monkeypatch):
    freeze_utc(monkeypatch, "2026-10-26T20:59:59Z")  # 23:59:59 Riyadh on the 26th
    assert get_cycle_for_date()["cycle_key"] == "2026-10"


@pytest.mark.parametrize("ts,expected", [
    ("2026-10-26T21:00:00Z", date(2026, 10, 27)),
    ("2026-10-26T20:59:59+00:00", date(2026, 10, 26)),
    ("2026-10-27T01:00:00+03:00", date(2026, 10, 27)),
    ("2026-10-26T22:00:00", date(2026, 10, 27)),  # naive → UTC
])
def test_riyadh_date_for_timestamp(ts, expected):
    assert riyadh_date_for_timestamp(ts) == expected


@pytest.mark.parametrize("d,payday,key,start,end", [
    (date(2026, 10, 28), 27, "2026-11", "2026-10-27", "2026-11-26"),
    (date(2026, 12, 27), 27, "2027-01", "2026-12-27", "2027-01-26"),
    (date(2026, 12, 26), 27, "2026-12", "2026-11-27", "2026-12-26"),
    (date(2027, 2, 28), 31, "2027-03", "2027-02-28", "2027-03-30"),
    (date(2027, 2, 27), 31, "2027-02", "2027-01-31", "2027-02-27"),
    (date(2028, 2, 29), 30, "2028-03", "2028-02-29", "2028-03-29"),
    (date(2028, 2, 28), 30, "2028-02", "2028-01-30", "2028-02-28"),
])
def test_cycle_boundaries_match_db_function(d, payday, key, start, end):
    info = get_cycle_for_date(d, payday_day=payday)
    assert (info["cycle_key"], info["cycle_start"], info["cycle_end"]) == (key, start, end)
    by_key = get_cycle_info_for_key(key, payday_day=payday)
    assert (by_key["cycle_start"], by_key["cycle_end"]) == (start, end)


def test_insert_transaction_derives_cycle_from_riyadh_date_and_household_payday(fake_supabase, monkeypatch):
    from supabase_client import insert_transaction

    hid = "aaaaaaaa-0000-4000-8000-000000000001"
    fake_supabase.seed("households", [{"id": hid, "payday_day": 25}])
    monkeypatch.setattr("installment_service.InstallmentService.recalculate_budgets", lambda *a, **k: None)
    insert_transaction(
        household_id=hid, amount=10.0, currency="SAR", merchant="Panda", category_code="OPEX-GROCERY",
        timestamp="2026-10-24T21:30:00Z", raw_sms="chat",  # 00:30 on the 25th in Riyadh
    )
    assert fake_supabase.tables["transactions"][0]["cycle_key"] == "2026-11"


def test_category_activation_creates_budget_in_salary_cycle_not_calendar_month(fake_supabase, monkeypatch):
    from salary_cycle import toggle_category_status

    freeze_utc(monkeypatch, "2026-10-28T09:00:00Z")
    hid = "aaaaaaaa-0000-4000-8000-000000000001"
    toggle_category_status(hid, "OPEX-FUEL", is_active=True)
    budget = fake_supabase.tables["budgets"][0]
    assert budget["cycle_key"] == "2026-11"
