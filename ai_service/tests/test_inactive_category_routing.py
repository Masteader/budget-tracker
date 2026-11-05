"""
An expense in a category the household has but keeps inactive is filed under that category, never
a fallback (owner decision 2026-11-05; e2e test_rent_expense_lands_in_the_new_housing_sub_category).
Whether a category exists is decided from the household's whole catalog, active or inactive. The
legacy code stays for a code missing from cost_control_codes altogether, OPEX-MISC for a code
nobody has. Inactive categories count in no budget (migration 20261105001000).
"""

from __future__ import annotations

import base64
import io
import json
import types
from unittest.mock import MagicMock

import pytest

import chat_parser
from chat_parser import ParsedChatExpense, choose_expense_category
from models import CostControlCode

HH = "f860188e-23b5-4749-b180-868c956151a6"
OTHER_HH = "0b2f7c55-1111-4c9e-9d55-2a8f3c0a9e01"


def _code(code, keywords=(), household_id=None):
    return {"id": code, "code": code, "category": code.title(), "keywords": list(keywords), "is_flexible": False,
            "household_id": household_id, "is_system": household_id is None}


CATALOG = [
    _code("OPEX-GROCERY", ["panda"]),
    _code("OPEX-DINING", ["albaik"]),
    _code("OPEX-UTILITIES", ["sec", "stc"]),
    _code("OPEX-HOUSING", ["ejar", "إيجار", "ايجار"]),
    _code("OPEX-CHARITY", ["zakat", "صدقة", "ehsan"]),
    _code("OPEX-MISC"),
    _code("CUSTOM-RENTX", ["rentx"], household_id=OTHER_HH),
]


def _seed(fake, settings=None, codes=CATALOG):
    fake.seed("cost_control_codes", codes)
    fake.seed("households", [{"id": HH, "payday_day": 27}])
    fake.seed("household_category_settings", [
        {"household_id": HH, "category_code": code, "is_active": active} for code, active in (settings or {}).items()
    ])


def _parsed(merchant, amount, code, sub=None):
    return ParsedChatExpense(merchant=merchant, total_amount=amount, currency="SAR", category_code=code,
                             sub_category=sub, paid_by="me", beneficiary="both",
                             items=[{"name": merchant, "price": amount, "quantity": 1}])


def _chat(monkeypatch, parsed, message, preview_only=True):
    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda msg, household_id=None: parsed)
    monkeypatch.setattr("chat_parser.find_duplicate_candidate", lambda *a, **k: None)
    monkeypatch.setattr("chat_parser.fetch_budget", lambda *a, **k: None)
    insert = MagicMock(return_value="tx-1")
    monkeypatch.setattr("chat_parser.insert_transaction", insert)
    monkeypatch.setattr("chat_parser.enrich_transaction_items", lambda *a, **k: True)
    res = chat_parser.process_chat_transaction(HH, message, user_id=None, preview_only=preview_only)
    return res, insert


# ─── chat ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("settings", [{"OPEX-HOUSING": False}, {}], ids=["toggled-off", "never-activated"])
def test_rent_in_inactive_housing_is_filed_as_housing(fake_supabase, monkeypatch, settings):
    _seed(fake_supabase, settings)
    res, _ = _chat(monkeypatch, _parsed("Ejar", 2500, "OPEX-HOUSING", "housing_rent"), "Ejar 2500 SAR")
    assert res["category_code"] == "OPEX-HOUSING"
    assert res["sub_category"] == "housing_rent"
    assert res["is_category_inactive"] is True


def test_rent_commit_stores_housing_never_utilities(fake_supabase, monkeypatch):
    _seed(fake_supabase, {"OPEX-HOUSING": False})
    res, insert = _chat(monkeypatch, _parsed("Ejar", 2500, "OPEX-HOUSING", "housing_rent"), "Ejar 2500 SAR",
                        preview_only=False)
    assert res["status"] == "success", res
    kwargs = insert.call_args.kwargs
    assert (kwargs["category_code"], kwargs["sub_category"]) == ("OPEX-HOUSING", "housing_rent")


def test_rent_heuristic_text_in_inactive_housing(fake_supabase, monkeypatch):
    """No LLM: the heuristic parser names Housing, and the inactive Housing keeps it."""
    _seed(fake_supabase, {"OPEX-HOUSING": False})
    monkeypatch.setattr("chat_parser.find_duplicate_candidate", lambda *a, **k: None)
    res = chat_parser.process_chat_transaction(HH, "دفعت ايجار الشقة 3000 ريال", user_id=None, preview_only=True)
    assert (res["category_code"], res["sub_category"]) == ("OPEX-HOUSING", "housing_rent")


def test_charity_in_inactive_charity_is_not_misc(fake_supabase, monkeypatch):
    _seed(fake_supabase, {"OPEX-CHARITY": False})
    res, _ = _chat(monkeypatch, _parsed("Masjid box", 100, "OPEX-CHARITY", "sadaqah"), "sadaqah 100")
    assert (res["category_code"], res["sub_category"]) == ("OPEX-CHARITY", "sadaqah")


def test_active_housing_unchanged(fake_supabase, monkeypatch):
    _seed(fake_supabase, {"OPEX-HOUSING": True})
    res, _ = _chat(monkeypatch, _parsed("Ejar", 2500, "OPEX-HOUSING", "housing_rent"), "Ejar 2500 SAR")
    assert res["category_code"] == "OPEX-HOUSING"
    assert res["is_category_inactive"] is False


def test_unknown_code_goes_to_misc(fake_supabase, monkeypatch):
    _seed(fake_supabase, {"OPEX-HOUSING": False})
    res, _ = _chat(monkeypatch, _parsed("Some shop", 40, "OPEX-HALLUCINATED"), "Some shop 40")
    assert res["category_code"] == "OPEX-MISC"


def test_another_households_custom_code_is_unknown_here(fake_supabase, monkeypatch):
    _seed(fake_supabase)
    res, _ = _chat(monkeypatch, _parsed("Shop", 40, "CUSTOM-RENTX"), "Shop 40")
    assert res["category_code"] == "OPEX-MISC"


def test_code_missing_from_the_table_keeps_its_legacy_fallback(fake_supabase, monkeypatch):
    codes = [c for c in CATALOG if c["code"] != "OPEX-HOUSING"]
    _seed(fake_supabase, codes=codes)
    res, _ = _chat(monkeypatch, _parsed("Landlord", 2500, "OPEX-HOUSING", "annual_rent"), "rent 2500")
    assert res["category_code"] == "OPEX-UTILITIES"
    assert res["sub_category"] != "annual_rent"  # the new code's sub-code is not kept on the legacy code


# ─── the choice itself ─────────────────────────────────────────────────────────

def _codes(*specs):
    return [CostControlCode(code=c, category=c, keywords=list(k), is_flexible=False) for c, k in specs]


ACTIVE = _codes(("OPEX-DINING", ["albaik"]), ("OPEX-UTILITIES", ["stc"]), ("OPEX-MISC", []))
INACTIVE = _codes(("OPEX-HOUSING", ["ejar"]), ("OPEX-CHARITY", ["ehsan"]))


@pytest.mark.parametrize("merchant, parsed, want", [
    ("Ejar", "OPEX-HOUSING", "OPEX-HOUSING"),        # inactive, parsed and keyword
    ("Landlord", "OPEX-HOUSING", "OPEX-HOUSING"),    # inactive, parsed only
    ("Ejar", "OPEX-HALLUCINATED", "OPEX-HOUSING"),   # unknown parsed code, inactive keyword
    ("Ehsan", None, "OPEX-CHARITY"),                 # no parsed code, inactive keyword
    ("Ejar", "OPEX-DINING", "OPEX-DINING"),          # an active parsed category is kept, as before
    ("Albaik", "OPEX-HOUSING", "OPEX-DINING"),       # an active keyword wins, as before
    ("Shop", "OPEX-HALLUCINATED", "OPEX-MISC"),      # genuinely unknown
    ("Shop", "OPEX-UTILITIES", "OPEX-UTILITIES"),    # active, as before
])
def test_choose_expense_category(merchant, parsed, want):
    assert choose_expense_category(merchant, parsed, ACTIVE, INACTIVE) == want


def test_legacy_fallback_only_when_missing_from_the_whole_catalog():
    assert choose_expense_category("Landlord", "OPEX-HOUSING", ACTIVE, []) == "OPEX-UTILITIES"
    assert choose_expense_category("Landlord", "OPEX-HOUSING", ACTIVE, INACTIVE) == "OPEX-HOUSING"


def test_catalog_is_the_households_codes_split_by_status(fake_supabase):
    import supabase_client

    _seed(fake_supabase, {"OPEX-HOUSING": False, "OPEX-CHARITY": False})
    active, inactive = supabase_client.fetch_household_category_catalog(HH)
    assert {"OPEX-GROCERY", "OPEX-DINING", "OPEX-UTILITIES", "OPEX-MISC"} <= {c.code for c in active}
    assert {c.code for c in inactive} == {"OPEX-HOUSING", "OPEX-CHARITY"}
    assert "CUSTOM-RENTX" not in {c.code for c in active + inactive}
    # The active-only view is unchanged.
    assert {c.code for c in supabase_client.fetch_household_cost_control_codes(HH)} == {c.code for c in active}


# ─── receipts ──────────────────────────────────────────────────────────────────

def _receipt(monkeypatch, merchant, code):
    import litellm
    import receipt_scanner
    from PIL import Image

    payload = {"merchant": merchant, "total_amount": 2500.0, "category_code": code,
               "items": [{"name": merchant, "quantity": 1, "price": 2500.0}]}
    msg = types.SimpleNamespace(content=json.dumps(payload))
    monkeypatch.setattr(litellm, "completion",
                        lambda *a, **k: types.SimpleNamespace(choices=[types.SimpleNamespace(message=msg)]))
    buf = io.BytesIO()
    Image.new("RGB", (20, 20)).save(buf, "JPEG")
    return receipt_scanner.process_receipt_scan(HH, [base64.b64encode(buf.getvalue()).decode()], preview_only=True)


@pytest.mark.parametrize("merchant, code", [
    ("Ejar", "OPEX-HOUSING"),
    ("Landlord office", "OPEX-HOUSING"),
    ("Jood Eskan", "OPEX-CHARITY"),
])
def test_receipt_in_an_inactive_category_keeps_it(fake_supabase, monkeypatch, merchant, code):
    _seed(fake_supabase, {"OPEX-HOUSING": False, "OPEX-CHARITY": False})
    res = _receipt(monkeypatch, merchant, code)
    assert res["status"] == "preview" and res["category_code"] == code, res
    assert res["is_category_inactive"] is True


def test_receipt_unknown_code_is_misc(fake_supabase, monkeypatch):
    _seed(fake_supabase, {"OPEX-HOUSING": False})
    res = _receipt(monkeypatch, "Some shop", "OPEX-HALLUCINATED")
    assert res["category_code"] == "OPEX-MISC"
