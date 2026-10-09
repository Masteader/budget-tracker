import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from datetime import date
import pytest
from recurring_detector import (
    normalize_bill_merchant,
    detect_recurring_bills,
    RecurringBill,
)


def test_normalize_bill_merchant():
    assert normalize_bill_merchant("STC Postpaid Mobile") == "STC"
    assert normalize_bill_merchant("Saudi Electricity Company Bill") == "Saudi Electricity"
    assert normalize_bill_merchant("SEC Riyadh Power") == "Saudi Electricity"
    assert normalize_bill_merchant("Netflix.com BV") == "Netflix"
    assert normalize_bill_merchant("Spotify AB Monthly") == "Spotify"
    assert normalize_bill_merchant("Mobily Prepaid / Postpaid") == "Mobily"
    assert normalize_bill_merchant("Random Tamimi Market") == "Random Tamimi Market"


def test_detect_recurring_bills_empty():
    res = detect_recurring_bills([], as_of_date=date(2026, 10, 5))
    assert res["bills"] == []
    assert res["reserved_amount"] == 0.0
    assert res["total_recurring_monthly"] == 0.0


def test_detect_recurring_bills_known_and_cadence():
    # Transactions over the past 3 months
    txs = [
        # STC (paid on 28th)
        {"merchant": "STC Postpaid", "amount": 400.0, "category_code": "OPEX-UTILITIES", "timestamp": "2026-07-28T10:00:00Z"},
        {"merchant": "STC Postpaid", "amount": 400.0, "category_code": "OPEX-UTILITIES", "timestamp": "2026-08-28T10:00:00Z"},
        {"merchant": "STC Postpaid", "amount": 400.0, "category_code": "OPEX-UTILITIES", "timestamp": "2026-09-28T10:00:00Z"},

        # Netflix (paid on 15th - upcoming relative to Oct 5)
        {"merchant": "Netflix", "amount": 65.0, "category_code": "OPEX-ENTERTAINMENT", "timestamp": "2026-08-15T12:00:00Z"},
        {"merchant": "Netflix", "amount": 65.0, "category_code": "OPEX-ENTERTAINMENT", "timestamp": "2026-09-15T12:00:00Z"},

        # Irregular grocery (should not be considered recurring bill)
        {"merchant": "Lulu Hypermarket", "amount": 120.0, "category_code": "OPEX-FOOD-GROCERIES", "timestamp": "2026-09-02T10:00:00Z"},
        {"merchant": "Lulu Hypermarket", "amount": 340.0, "category_code": "OPEX-FOOD-GROCERIES", "timestamp": "2026-09-18T10:00:00Z"},
    ]

    # As of Oct 5, 2026:
    # Active cycle: Sep 27 - Oct 26 (2026-10)
    # STC was paid on Sep 28 -> PAID_THIS_CYCLE
    # Netflix expected on Oct 15 -> UPCOMING, reserved = 65.0
    res = detect_recurring_bills(txs, as_of_date=date(2026, 10, 5))

    bills = res["bills"]
    assert len(bills) == 2

    stc_bill = next((b for b in bills if b["normalized_merchant"] == "STC"), None)
    assert stc_bill is not None
    assert stc_bill["status"] == "PAID_THIS_CYCLE"
    assert stc_bill["average_amount"] == 400.0

    netflix_bill = next((b for b in bills if b["normalized_merchant"] == "Netflix"), None)
    assert netflix_bill is not None
    assert netflix_bill["status"] == "UPCOMING"
    assert netflix_bill["average_amount"] == 65.0

    assert res["total_recurring_monthly"] == 465.0
    assert res["paid_this_cycle"] == 400.0
    assert res["reserved_amount"] == 65.0


def test_detect_recurring_bills_with_budgets_and_iqama():
    budgets = [
        {
            "category_code": "OPEX-UTILITIES",
            "cycle_key": "2026-10",
            "is_active": True,
            "sub_allocations": {
                "housing_rent": 3000.0,
                "electricity_sec": 350.0,
                "fiber_internet": 250.0,
            },
        },
        {
            "category_code": "OPEX-GOV",
            "cycle_key": "2026-10",
            "is_active": True,
            "sub_allocations": {
                "sub-iqama-fees": 400.0,
            },
        },
    ]

    # Only 1 transaction: Housing Rent paid
    txs = [
        {
            "id": "tx-1",
            "merchant": "Housing Rent",
            "amount": 3000.0,
            "category_code": "OPEX-UTILITIES",
            "sub_category": "housing_rent",
            "timestamp": "2026-09-29T10:00:00Z",
        }
    ]

    res = detect_recurring_bills(txs, as_of_date=date(2026, 10, 5), budgets=budgets)
    bills = res["bills"]
    assert len(bills) == 4

    # Housing Rent should be PAID
    rent = next(b for b in bills if "Rent" in b["merchant"])
    assert rent["status"] == "PAID_THIS_CYCLE"
    assert rent["paid_amount"] == 3000.0

    # Electricity and Fiber should be UPCOMING / OVERDUE
    sec = next(b for b in bills if "Electricity" in b["merchant"])
    assert sec["status"] in ("UPCOMING", "OVERDUE")
    assert sec["average_amount"] == 350.0

    # Iqama fees should be included from OPEX-GOV
    iqama = next(b for b in bills if "iqama" in b["merchant"].lower())
    assert iqama["category_code"] == "OPEX-GOV"
    assert iqama["average_amount"] == 400.0
    assert iqama["status"] == "UPCOMING"

    assert res["total_recurring_monthly"] == 4000.0
    assert res["paid_this_cycle"] == 3000.0
    assert res["reserved_amount"] == 1000.0

