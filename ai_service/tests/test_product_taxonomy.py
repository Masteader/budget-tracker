"""
PRODUCT-R4 (docs/review/audit/product_review.md, roadmap item 6): the chat parser knows the Saudi
household categories that were missing (housing, education, domestic help, family support,
charity, transport, insurance, remittance) in its LLM prompt and in the heuristic fallback, in
Arabic, English and Urdu. The codes are system categories (household_id NULL) added by a separate
migration; until it is applied, a new code falls back to the legacy code so no insert is refused.
"""

from __future__ import annotations

import pytest

import chat_parser
from chat_parser import (
    NEW_SYSTEM_CATEGORY_CODES,
    SYSTEM_PROMPT,
    _fallback_heuristic_parse,
    resolve_category_in_taxonomy,
)
from models import CostControlCode

NEW_CODES = {
    "OPEX-HOUSING", "OPEX-EDUCATION", "OPEX-DOMESTIC-HELP", "OPEX-FAMILY-SUPPORT",
    "OPEX-CHARITY", "OPEX-TRANSPORT", "OPEX-INSURANCE", "OPEX-REMITTANCE",
}


def test_new_codes_are_constants_and_in_the_prompt():
    assert set(NEW_SYSTEM_CATEGORY_CODES) == NEW_CODES
    for code in NEW_CODES:
        assert code in SYSTEM_PROMPT, code
    # Existing codes keep working.
    for code in ("OPEX-GROCERY", "OPEX-DINING", "OPEX-FUEL", "OPEX-UTILITIES", "OPEX-SHOPPING",
                 "OPEX-HEALTH", "OPEX-ENTERTAINMENT", "OPEX-MISC"):
        assert code in SYSTEM_PROMPT, code


def test_prompt_has_urdu_examples():
    # Five or more Urdu example inputs (Urdu-only letters: ے ہ ی ک ٹ ڈ).
    examples = [line for line in SYSTEM_PROMPT.splitlines() if line.startswith('"') and any(ch in line for ch in "ےہیکٹڈ")]
    assert len(examples) >= 5, examples


@pytest.mark.parametrize("text, code", [
    # Housing
    ("دفعت ايجار الشقة 3000 ريال", "OPEX-HOUSING"),
    ("إيجار البيت 2500", "OPEX-HOUSING"),
    ("paid rent 3500 sar", "OPEX-HOUSING"),
    ("مکان کا کرایہ 3000 ریال دیا", "OPEX-HOUSING"),
    # Education
    ("رسوم مدرسية للعيال 4000 ريال", "OPEX-EDUCATION"),
    ("school fees 5000 sar", "OPEX-EDUCATION"),
    ("بچوں کی اسکول فیس 1500 ریال", "OPEX-EDUCATION"),
    # Domestic help
    ("راتب الخادمة 1500 ريال", "OPEX-DOMESTIC-HELP"),
    ("سائق 1800 ريال", "OPEX-DOMESTIC-HELP"),
    ("maid salary 1500 sar", "OPEX-DOMESTIC-HELP"),
    ("ڈرائیور کی تنخواہ 1800 ریال", "OPEX-DOMESTIC-HELP"),
    # Family support
    ("مساعدة الأهل 1000 ريال", "OPEX-FAMILY-SUPPORT"),
    ("sent my parents 500 sar", "OPEX-FAMILY-SUPPORT"),
    ("والدین کو 700 ریال", "OPEX-FAMILY-SUPPORT"),
    # Charity
    ("صدقة 100 ريال", "OPEX-CHARITY"),
    ("زكاة المال 2500", "OPEX-CHARITY"),
    ("sadaqah 50 sar", "OPEX-CHARITY"),
    ("خیرات 200 ریال", "OPEX-CHARITY"),
    # Transport
    ("اوبر للدوام 35 ريال", "OPEX-TRANSPORT"),
    ("careem 22 sar", "OPEX-TRANSPORT"),
    ("taxi 40 sar", "OPEX-TRANSPORT"),
    ("قسط السيارة 1900 ريال", "OPEX-TRANSPORT"),
    ("مواصلات 60 ريال", "OPEX-TRANSPORT"),
    # Insurance
    ("تأمين السيارة 1200 ريال", "OPEX-INSURANCE"),
    ("tameeni car insurance 1100 sar", "OPEX-INSURANCE"),
    ("گاڑی کی انشورنس 1000 ریال", "OPEX-INSURANCE"),
    # Remittance
    ("حوالة للهند 2000 ريال", "OPEX-REMITTANCE"),
    ("تحويل للخارج 1500 ريال", "OPEX-REMITTANCE"),
    ("western union 900 sar", "OPEX-REMITTANCE"),
    ("پاکستان ترسیل زر 1200 ریال", "OPEX-REMITTANCE"),
])
def test_heuristic_maps_new_categories(text, code):
    parsed = _fallback_heuristic_parse(text)
    assert parsed.is_transaction
    assert parsed.category_code == code, (text, parsed.category_code)
    assert parsed.total_amount > 0


@pytest.mark.parametrize("text, code", [
    ("بنزين 91 بـ 60 ريال من ساسكو", "OPEX-FUEL"),
    ("مقاضي البيت من بنده 250 ريال", "OPEX-GROCERY"),
    ("قهوة من ستاربكس 22 ريال", "OPEX-DINING"),
    ("فاتورة الكهرباء 300 ريال", "OPEX-UTILITIES"),
    ("صيدلية النهدي 45 ريال", "OPEX-HEALTH"),
    # Words that merely contain a cue are not that category.
    ("رسوم معاملة 50 ريال", "OPEX-MISC"),
    ("current account fee 10 sar", "OPEX-MISC"),
])
def test_heuristic_existing_categories_unchanged(text, code):
    assert _fallback_heuristic_parse(text).category_code == code, text


def _codes(*names):
    return [CostControlCode(id=n, code=n, category=n, keywords=[], is_flexible=True) for n in names]


def test_new_code_kept_when_in_taxonomy():
    codes = _codes("OPEX-MISC", "OPEX-HOUSING")
    assert resolve_category_in_taxonomy("OPEX-HOUSING", codes) == "OPEX-HOUSING"


@pytest.mark.parametrize("new, legacy", [
    ("OPEX-HOUSING", "OPEX-UTILITIES"),
    ("OPEX-TRANSPORT", "OPEX-FUEL"),
    ("OPEX-CHARITY", "OPEX-MISC"),
    ("OPEX-REMITTANCE", "OPEX-MISC"),
])
def test_new_code_falls_back_before_the_migration(new, legacy):
    codes = _codes("OPEX-MISC", "OPEX-UTILITIES", "OPEX-FUEL")
    assert resolve_category_in_taxonomy(new, codes) == legacy


def test_unknown_model_code_falls_back_to_misc_and_empty_taxonomy_is_left_to_the_db():
    assert resolve_category_in_taxonomy("OPEX-HALLUCINATED", _codes("OPEX-MISC")) == "OPEX-MISC"
    assert resolve_category_in_taxonomy("OPEX-HOUSING", []) == "OPEX-HOUSING"


def test_chat_commit_uses_legacy_code_when_new_code_is_missing(fake_supabase):
    hh = "f860188e-23b5-4749-b180-868c956151a6"
    fake_supabase.seed("cost_control_codes", [
        {"id": "u", "code": "OPEX-UTILITIES", "category": "Utilities", "keywords": [], "is_flexible": False,
         "household_id": None},
        {"id": "m", "code": "OPEX-MISC", "category": "Misc", "keywords": [], "is_flexible": True, "household_id": None},
    ])
    fake_supabase.seed("households", [{"id": hh, "payday_day": 27}])
    res = chat_parser.process_chat_transaction(hh, "دفعت ايجار الشقة 3000 ريال", user_id=None, preview_only=True)
    assert res["category_code"] == "OPEX-UTILITIES"
    assert res["sub_category"] != "annual_rent"  # the new code's sub-code is not kept on the legacy code


# Sub-codes of migration 20261021000000 (cost_control_sub_categories).
SUB_CODES = {
    "OPEX-HOUSING": {"housing_rent", "annual_rent", "housing_services"},
    "OPEX-EDUCATION": {"tuition_fees", "school_transport", "school_uniforms", "books_supplies"},
    "OPEX-DOMESTIC-HELP": {"maid_salary", "driver_salary", "recruitment_visa"},
    "OPEX-FAMILY-SUPPORT": {"parents_support", "relatives_support"},
    "OPEX-CHARITY": {"sadaqah", "zakat"},
    "OPEX-TRANSPORT": {"car_installment", "ride_hailing", "public_transport", "car_maintenance"},
    "OPEX-INSURANCE": {"car_insurance", "health_insurance", "home_insurance"},
    "OPEX-REMITTANCE": {"family_remittance", "transfer_fees"},
}


def test_sub_code_table_matches_the_migration():
    assert {code: {s for s, _ in subs} for code, subs in chat_parser.NEW_CATEGORY_SUB_CODES.items()} == SUB_CODES
    for code, subs in SUB_CODES.items():
        line = next(l for l in SYSTEM_PROMPT.splitlines() if l.startswith(f"- {code}:"))
        for sub in subs:
            assert sub in line, (code, sub)


def test_receipt_prompt_lists_the_new_codes():
    import receipt_scanner

    for code in NEW_CODES:
        assert f"- {code} (" in receipt_scanner.RECEIPT_PROMPT, code


@pytest.mark.parametrize("text, code, sub", [
    ("دفعت ايجار الشقة 3000 ريال", "OPEX-HOUSING", "housing_rent"),
    ("الإيجار السنوي 36000 ريال", "OPEX-HOUSING", "annual_rent"),
    ("رسوم مدرسية للعيال 4000 ريال", "OPEX-EDUCATION", "tuition_fees"),
    ("باص المدرسة 300 ريال", "OPEX-EDUCATION", "school_transport"),
    ("school uniforms 250 sar", "OPEX-EDUCATION", "school_uniforms"),
    ("كتب وقرطاسية المدرسة 180 ريال", "OPEX-EDUCATION", "books_supplies"),
    ("راتب الخادمة 1500 ريال", "OPEX-DOMESTIC-HELP", "maid_salary"),
    ("سائق 1800 ريال", "OPEX-DOMESTIC-HELP", "driver_salary"),
    ("رسوم استقدام عاملة عبر مساند 9000 ريال", "OPEX-DOMESTIC-HELP", "recruitment_visa"),
    ("مساعدة الأهل 1000 ريال", "OPEX-FAMILY-SUPPORT", "parents_support"),
    ("مساعدة الاهل أخوي 500 ريال", "OPEX-FAMILY-SUPPORT", "relatives_support"),
    ("صدقة 100 ريال", "OPEX-CHARITY", "sadaqah"),
    ("زكاة المال 2500", "OPEX-CHARITY", "zakat"),
    ("اوبر للدوام 35 ريال", "OPEX-TRANSPORT", "ride_hailing"),
    ("قسط السيارة 1900 ريال", "OPEX-TRANSPORT", "car_installment"),
    ("مترو الرياض مواصلات 20 ريال", "OPEX-TRANSPORT", "public_transport"),
    ("تأمين السيارة 1200 ريال", "OPEX-INSURANCE", "car_insurance"),
    ("تأمين طبي بوبا 3000 ريال", "OPEX-INSURANCE", "health_insurance"),
    ("حوالة للهند 2000 ريال", "OPEX-REMITTANCE", "family_remittance"),
    ("رسوم التحويل حوالة 25 ريال", "OPEX-REMITTANCE", "transfer_fees"),
])
def test_heuristic_sub_codes(text, code, sub):
    parsed = _fallback_heuristic_parse(text)
    assert (parsed.category_code, parsed.sub_category) == (code, sub), text
    assert all(it.sub_category == sub for it in parsed.items)


def test_receipt_unknown_model_code_falls_back(fake_supabase, monkeypatch):
    import json
    import types

    import litellm
    import receipt_scanner

    hh = "f860188e-23b5-4749-b180-868c956151a6"
    fake_supabase.seed("cost_control_codes", [
        {"id": "f", "code": "OPEX-FUEL", "category": "Fuel", "keywords": [], "is_flexible": False, "household_id": None},
        {"id": "m", "code": "OPEX-MISC", "category": "Misc", "keywords": [], "is_flexible": True, "household_id": None},
    ])
    fake_supabase.seed("households", [{"id": hh, "payday_day": 27}])
    payload = {"merchant": "Careem", "total_amount": 30.0, "category_code": "OPEX-TRANSPORT",
               "items": [{"name": "Ride", "quantity": 1, "price": 30.0}]}
    msg = types.SimpleNamespace(content=json.dumps(payload))
    monkeypatch.setattr(litellm, "completion",
                        lambda *a, **k: types.SimpleNamespace(choices=[types.SimpleNamespace(message=msg)]))
    import base64
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (20, 20)).save(buf, "JPEG")
    res = receipt_scanner.process_receipt_scan(hh, [base64.b64encode(buf.getvalue()).decode()], preview_only=True)
    assert res["status"] == "preview" and res["category_code"] == "OPEX-FUEL"
