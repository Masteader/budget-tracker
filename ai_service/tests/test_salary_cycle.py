import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from datetime import date
import pytest
from dotenv import load_dotenv

load_dotenv()
from salary_cycle import get_cycle_for_date, adjust_saudi_payday
from supabase_client import ensure_household_cycle_budgets, get_client


def test_get_cycle_for_date_october_mid():
    info = get_cycle_for_date(date(2026, 10, 2))
    assert info["cycle_key"] == "2026-10"
    assert info["cycle_start"] == "2026-09-27"
    assert info["cycle_end"] == "2026-10-26"
    assert info["month_name"] == "October 2026"
    assert "October 2026" in info["label"]
    assert "Sep 27" in info["label"]
    assert "Oct 26" in info["label"]


def test_get_cycle_for_date_transitions_on_27th():
    # Day 26 is still October cycle
    info_26 = get_cycle_for_date(date(2026, 10, 26))
    assert info_26["cycle_key"] == "2026-10"
    assert info_26["cycle_start"] == "2026-09-27"
    assert info_26["cycle_end"] == "2026-10-26"

    # Day 27 immediately transitions to November cycle
    info_27 = get_cycle_for_date(date(2026, 10, 27))
    assert info_27["cycle_key"] == "2026-11"
    assert info_27["cycle_start"] == "2026-10-27"
    assert info_27["cycle_end"] == "2026-11-26"
    assert "November 2026" in info_27["label"]


def test_get_cycle_for_date_year_boundary():
    # Dec 27 starts January next year
    info_dec27 = get_cycle_for_date(date(2026, 12, 27))
    assert info_dec27["cycle_key"] == "2027-01"
    assert info_dec27["cycle_start"] == "2026-12-27"
    assert info_dec27["cycle_end"] == "2027-01-26"

    # Jan 10 belongs to January cycle
    info_jan10 = get_cycle_for_date(date(2027, 1, 10))
    assert info_jan10["cycle_key"] == "2027-01"
    assert info_jan10["cycle_start"] == "2026-12-27"
    assert info_jan10["cycle_end"] == "2027-01-26"


def test_ensure_household_cycle_budgets_existing():
    client = get_client()
    # Get a real household ID
    h_res = client.table("households").select("id").limit(1).execute()
    assert h_res.data
    hid = h_res.data[0]["id"]

    # When called for current date (Oct 2), October budgets already exist
    budgets = ensure_household_cycle_budgets(hid, date(2026, 10, 2))
    assert len(budgets) >= 1
    assert all(b.get("cycle_key") == "2026-10" for b in budgets)
