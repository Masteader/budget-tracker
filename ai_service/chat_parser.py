"""
Natural language chat transaction parser using Gemini via LiteLLM.
Extracts merchant, total amount, category, and itemized line items.
"""

from __future__ import annotations
import json
import logging
import math
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator

import litellm
from dotenv import load_dotenv

load_dotenv()

from dedup_engine import find_duplicate_candidate, enrich_transaction_items
from nafaqah_service import resolve_expense_nafaqah
from supabase_client import (
    fetch_all_cost_control_codes,
    fetch_household_cost_control_codes,
    match_category,
    insert_transaction,
    fetch_budget,
    fetch_flexible_budgets,
    reallocate_budget,
    category_code_in_taxonomy,
    household_attribution,
    UnknownCategoryError,
)

from preview_token import (  # noqa: E402
    KIND_CHAT,
    InvalidPreviewToken,
    issue_preview_token,
    text_digest,
    verify_preview_token,
)
from utils import (  # noqa: E402
    build_audit_note,
    litellm_model,
    riyadh_today,
    riyadh_date_for_timestamp,
    sanitize_audit_text,
)

MAX_MERCHANT_LENGTH = 120

logger = logging.getLogger(__name__)

class ChatLineItem(BaseModel):
    name: str = Field(..., description="Name of the item purchased")
    quantity: float = Field(1.0, description="Quantity of item")
    price: float = Field(..., description="Total price for this item line in SAR")
    sub_category: Optional[str] = Field(None, description="Sub-category code for this specific item")

    @field_validator("name")
    @classmethod
    def bound_name(cls, v: str) -> str:
        return v[:200] if isinstance(v, str) else v

    @field_validator("price")
    @classmethod
    def validate_price(cls, v: float) -> float:
        if not math.isfinite(v):
            raise ValueError("Item price must be a finite number")
        if v < 0:
            raise ValueError("Item price cannot be negative")
        if v > 10_000_000:
            raise ValueError("Item price exceeds maximum limit")
        return round(float(v), 2)

    @field_validator("quantity")
    @classmethod
    def validate_quantity(cls, v: float) -> float:
        if not math.isfinite(v) or v <= 0:
            return 1.0
        return min(float(v), 10_000.0)

class ParsedChatExpense(BaseModel):
    intent: str = Field("transaction", description="'transaction' | 'simulation' | 'app_guidance' | 'off_topic'")
    is_transaction: bool = Field(True, description="Whether the text represents a financial expense to record")
    is_simulation: bool = Field(False, description="Whether the user is asking an affordability simulation question like 'Can I buy a 1200 SAR iPad?' or 'أقدر اشتري ايباد بـ 1200 ريال؟'")
    simulated_amount: Optional[float] = Field(None, description="Simulated purchase price in SAR")
    simulated_item: Optional[str] = Field(None, description="Simulated item or merchant name")
    merchant: str = Field("Unknown Merchant", description="Store or merchant name")
    total_amount: float = Field(0.0, description="Total amount in SAR")
    currency: str = "SAR"
    category_code: str = Field("OPEX-MISC", description="Category code like OPEX-DINING, OPEX-GROCERY, OPEX-SHOPPING, etc.")
    sub_category: Optional[str] = Field(None, description="Sub-category code like restaurants_dinners, coffee_bakeries, etc.")
    spent_by: str = Field("both", description="Who spent this: 'me', 'partner', or 'both'")
    paid_by: str = Field("me", description="Who paid: 'me' or 'partner'")
    beneficiary: str = Field("both", description="For whom: 'me', 'partner', 'both', or dependent/child name")
    items: List[ChatLineItem] = Field(default_factory=list, description="Itemized breakdown")
    notes: Optional[str] = None
    # Heuristic parser only: it could not tell who paid for what (FABLE-LOGIC-07); the preview
    # asks instead of suggesting a Nafaqah class.
    attribution_needs_confirmation: bool = False

    @field_validator("total_amount")
    @classmethod
    def validate_total_amount(cls, v: float) -> float:
        # NaN compares False against every bound, so it slipped through the range checks below.
        if not math.isfinite(v):
            raise ValueError("Total expense amount must be a finite number")
        if v < 0:
            raise ValueError("Total expense amount cannot be negative")
        if v > 10_000_000:
            raise ValueError("Total expense amount exceeds maximum limit (10,000,000 SAR)")
        return round(float(v), 2)

    @field_validator("beneficiary", "sub_category", "paid_by", "spent_by")
    @classmethod
    def bound_short_text(cls, v: Optional[str]) -> Optional[str]:
        # Model output is not trusted either (FABLE-API-06): short attribution/code fields.
        return v[:60] if isinstance(v, str) else v

    @field_validator("merchant")
    @classmethod
    def sanitize_merchant(cls, v: str) -> str:
        clean = (v or "Unknown Merchant").strip()
        clean = "".join(ch for ch in clean if ch.isprintable() and ch not in "\r\n\t")
        return clean[:120] if clean else "Unknown Merchant"

def normalize_arabic_numbers(text: str) -> str:
    """Converts Eastern Arabic numerals (٠-٩) and Persian numerals to Western digits (0-9)."""
    eastern_to_western = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    return text.translate(eastern_to_western)


SYSTEM_PROMPT = """You are an intelligent financial assistant for a Saudi budget tracker.
Parse natural language expense logs into structured financial transactions with line-item breakdowns, OR detect pre-purchase affordability simulation questions.

Categories and Sub-categories available:
- OPEX-GROCERY: meat, vegetables_fruit, dairy_eggs, snacks_chips, beverages, pantry_staples, cleaning_household (Tamimi, Danube, Panda, Carrefour, Lulu, Othaim, بنده, العثيم, التميمي, مقاضي)
- OPEX-DINING: restaurants_dinners, coffee_bakeries, delivery_apps (Albaik, McDonald's, Beit Al Shawarma, Dunkin, Starbucks, Jahez, Hungerstation, Mrsool, البيك, بيت الشاورما, شاورما, بروستد, جاهز, هنقرستيشن)
- OPEX-FUEL: gas_fuel, car_maintenance (Aramco, Sahel, SASCO, Aldrees, ساسكو, الدريس, بنزين 91, بنزين 95, زيت, صيانة السيارة)
- OPEX-TRANSPORT: car_installment, ride_hailing, public_transport, car_maintenance (Uber, Careem, Bolt, اوبر, كريم, تاكسي, مواصلات, قسط السيارة, ٹیکسی)
- OPEX-UTILITIES: electricity_sec, fiber_internet, mobile_sims, water_municipal (STC, Mobily, Zain, SEC, الكهرباء, المياه)
- OPEX-HOUSING: housing_rent, annual_rent, housing_services (ايجار, إيجار, الإيجار, Ejar, rent, کرایہ)
- OPEX-EDUCATION: tuition_fees, school_transport, school_uniforms, books_supplies (مدرسة, رسوم مدرسية, جامعة, حضانة, school fees, اسکول فیس)
- OPEX-DOMESTIC-HELP: maid_salary, driver_salary, recruitment_visa (خادمة, شغالة, سائق, سواق, عاملة, مساند, maid, driver, ڈرائیور, ماسی)
- OPEX-FAMILY-SUPPORT: parents_support, relatives_support (الوالدين, مساعدة الأهل, لأهلي, parents, والدین)
- OPEX-CHARITY: sadaqah, zakat (صدقة, زكاة, خيرات, تبرع, sadaqah, zakat, صدقہ, زکوٰۃ, خیرات)
- OPEX-INSURANCE: car_insurance, health_insurance, home_insurance (تأمين, Tameeni, تأميني, Tawuniya, Bupa, insurance, انشورنس, بیمہ)
- OPEX-REMITTANCE: family_remittance, transfer_fees (حوالة, تحويل للخارج, Western Union, Enjaz, remittance, ترسیل زر)
- OPEX-SHOPPING: clothing_fashion, electronics_gadgets, home_furniture (Jarir, Extra, Noon, Amazon, Apple, Ikea, جرير, اكسترا, ايكيا)
- OPEX-HEALTH: prescriptions_meds, clinics_dental (Nahdi, Al Dawaa, Habib, النهدي, الدواء, صيدلية, عيادة)
- OPEX-ENTERTAINMENT: Movies, cinemas, streaming, gaming (Muvi, Vox, Netflix, PlayStation, Shahid)
- OPEX-MISC: Anything else that doesn't fit above (house cleaning, maintenance).
Petrol stays OPEX-FUEL (gas_fuel); taxis, Uber/Careem, buses and car installments are OPEX-TRANSPORT.

SAUDI COLLOQUIAL ARABIC & 2D ATTRIBUTION SUPPORT:
- "paid_by" (who actually paid):
  - "دفعتها أنا / دافعه أنا / ع حسابي / حاسبت" -> "me"
  - "دفعتها زوجتي / حاسبها زوجي / جابته المدام" -> "partner"
- "beneficiary" (for whom was this expense):
  - "لي / لي لحالي / لنفسي / اشتريت لنفسي / ع حسابي الشخصي" -> "me"
  - "لزوجتي / للشريك" -> "partner"
  - "مقاضي البيت / لنا اثنيننا / مشترك / للبيت" -> "both"
  - "للعيال / للأولاد / للأطفال / للبنات" -> "children"
  - Mention of a specific child / dependent (e.g. "لسارة", "لفهد", "حليب سارة", "بامبرز") -> child's name (e.g. "Sarah", "Fahad").
- Never split anything between a husband and wife: the app applies the Islamic Nafaqah rules itself from paid_by and beneficiary.

Expense Input examples:
"عبيت بنزين 91 بـ 60 ريال من ساسكو"
-> merchant: "SASCO", total_amount: 60.0, category_code: "OPEX-FUEL", sub_category: "gas_fuel", paid_by: "me", beneficiary: "both", items: [{"name": "بنزين 91", "quantity": 1, "price": 60.0, "sub_category": "gas_fuel"}]

"طلبنا من بيت الشاورما بـ 25 ريال ساندويش شاورما وعصير"
-> merchant: "Beit Al Shawarma", total_amount: 25.0, category_code: "OPEX-DINING", sub_category: "restaurants_dinners", paid_by: "me", beneficiary: "me", items: [{"name": "ساندويش شاورما", "quantity": 1, "price": 15.0, "sub_category": "restaurants_dinners"}, {"name": "عصير", "quantity": 1, "price": 10.0, "sub_category": "restaurants_dinners"}]

"شريت حفاضات لسارة بـ 85 ريال من النهدي"
-> merchant: "Nahdi", total_amount: 85.0, category_code: "OPEX-HEALTH", sub_category: "prescriptions_meds", paid_by: "me", beneficiary: "Sarah", items: [{"name": "حفاضات", "quantity": 1, "price": 85.0, "sub_category": "prescriptions_meds"}]

"دفعت ايجار الشقة 3000 ريال"
-> merchant: "Rent", total_amount: 3000.0, category_code: "OPEX-HOUSING", sub_category: "housing_rent", paid_by: "me", beneficiary: "both", items: [{"name": "ايجار الشقة", "quantity": 1, "price": 3000.0}]

URDU (اردو) inputs are common among residents; parse them the same way ("میں نے دیا / میں نے خریدا" -> paid_by "me", "بیوی نے دیا" -> paid_by "partner", "گھر کے لیے" -> beneficiary "both", "بچوں کے لیے" -> beneficiary "children"):
"پانڈا سے گھر کا سودا 250 ریال میں خریدا"
-> merchant: "Panda", total_amount: 250.0, category_code: "OPEX-GROCERY", sub_category: "pantry_staples", paid_by: "me", beneficiary: "both", items: [{"name": "گھر کا سودا", "quantity": 1, "price": 250.0, "sub_category": "pantry_staples"}]
"مکان کا کرایہ 3000 ریال دیا"
-> merchant: "Rent", total_amount: 3000.0, category_code: "OPEX-HOUSING", sub_category: "housing_rent", paid_by: "me", beneficiary: "both", items: [{"name": "مکان کا کرایہ", "quantity": 1, "price": 3000.0}]
"بچوں کی اسکول فیس 1500 ریال"
-> merchant: "School", total_amount: 1500.0, category_code: "OPEX-EDUCATION", sub_category: "tuition_fees", paid_by: "me", beneficiary: "children", items: [{"name": "اسکول فیس", "quantity": 1, "price": 1500.0}]
"پاکستان گھر والوں کو ترسیل زر 1200 ریال"
-> merchant: "Remittance", total_amount: 1200.0, category_code: "OPEX-REMITTANCE", sub_category: "family_remittance", paid_by: "me", beneficiary: "me", items: [{"name": "ترسیل زر", "quantity": 1, "price": 1200.0}]
"ڈرائیور کی تنخواہ 1800 ریال"
-> merchant: "Driver", total_amount: 1800.0, category_code: "OPEX-DOMESTIC-HELP", sub_category: "driver_salary", paid_by: "me", beneficiary: "both", items: [{"name": "ڈرائیور کی تنخواہ", "quantity": 1, "price": 1800.0}]
"کریم ٹیکسی 35 ریال، بیوی نے دیا"
-> merchant: "Careem", total_amount: 35.0, category_code: "OPEX-TRANSPORT", sub_category: "ride_hailing", paid_by: "partner", beneficiary: "partner", items: [{"name": "ٹیکسی", "quantity": 1, "price": 35.0}]
"مسجد کے لیے صدقہ 100 ریال"
-> merchant: "Sadaqah", total_amount: 100.0, category_code: "OPEX-CHARITY", sub_category: "sadaqah", paid_by: "me", beneficiary: "me", items: [{"name": "صدقہ", "quantity": 1, "price": 100.0}]

Return STRICTLY valid JSON conforming to:
{
  "intent": "transaction" | "simulation" | "app_guidance" | "off_topic",
  "is_transaction": true,
  "is_simulation": false,
  "simulated_amount": null,
  "simulated_item": null,
  "merchant": "...",
  "total_amount": 0.0,
  "currency": "SAR",
  "category_code": "...",
  "sub_category": "...",
  "spent_by": "me" | "partner" | "both",
  "paid_by": "me" | "partner",
  "beneficiary": "me" | "partner" | "both" | "<child_name>",
  "items": [{"name": "...", "quantity": 1, "price": 0.0, "sub_category": "..."}],
  "notes": "..."
}
RULES FOR INTENT:
- 'transaction': financial expense to record (buying items, food, bills, rent, services, etc.)
- 'simulation': asking about affordability/purchasing power ('Can I buy an iPad?', 'أقدر اشتري ايباد؟')
- 'app_guidance': questions about the app, features, setup, payday settings, Nafaqah rules, envelopes ('كيف اضبط الراتب؟', 'what is nafaqah?', 'how to use')
- 'off_topic': casual chit-chat, jokes, bedtime stories, weather, coding, or unrelated non-financial conversation ('tell me a story', 'what is the weather?', 'كيف حالك')
"""

# ─── Heuristic attribution vocabulary (FABLE-LOGIC-07) ─────────────────────────
# Recorder-relative: 'partner' is the other spouse / roommate, 'me' the recorder.
_PARTNER_PAID_CUES = (
    "partner paid", "wife paid", "husband paid", "paid by my wife", "paid by my husband", "paid by wife",
    "paid by husband", "paid by my partner", "paid by partner", "my partner paid",
    "حاسبتها هي", "دفعتها هي", "دفعتها زوجتي", "دفعته زوجتي", "دفعت زوجتي", "زوجتي دفعت", "زوجتي دفعتها",
    "حاسبت زوجتي", "حاسبتها زوجتي", "زوجتي حاسبت", "دفعتها المدام", "دفعت المدام", "المدام دفعت",
    "حاسبت المدام", "المدام حاسبت", "جابته المدام", "جابته زوجتي", "دفعه زوجي", "دفعها زوجي", "دفعته زوجي",
    "دفع زوجي", "زوجي دفع", "حاسب زوجي", "حاسبه زوجي", "حاسبها زوجي", "زوجي حاسب", "جابه زوجي",
    "على حساب زوجي", "ع حساب زوجي", "على حساب زوجتي", "ع حساب زوجتي", "على حساب المدام",
)
_ME_PAID_CUES = (
    "i paid", "i spent", "i bought", "bought", "paid", "spent",
    "دفعتها انا", "دفعتها أنا", "دفعته انا", "دفعته أنا", "ع حسابي", "على حسابي", "حاسبت", "دفعت", "شريت",
    "اشتريت", "عبيت", "طلبت", "تقضيت", "تقضينا", "طلبنا", "جبت",
)
_CHILDREN_CUES = (
    "for the kids", "for my kids", "for the children", "for my children", "kids'", "children's",
    "للعيال", "للأولاد", "للاولاد", "للأطفال", "للاطفال", "للبنات",
)
_PARTNER_BENEFICIARY_CUES = (
    "for my wife", "for my husband", "for partner", "for my partner", "for husband", "for wife", "for her",
    "for him", "لزوجتي", "لزوجي", "للمدام", "للشريك", "فستان زوجتي", "هدية زوجتي", "هدية لزوجتي",
)
_PARTNER_PRONOUN_WORDS = {"لها", "له"}
_ME_BENEFICIARY_CUES = (
    "for me", "for myself", "bought myself", "my own", "لي لحالي", "شريت لنفسي", "لنفسي", "قهوتي", "ملابسي",
    "عطري", "جوالي", "دفعتها انا", "دفعتها أنا", "دفعته انا", "دفعته أنا",
)
_EXTERNAL_BENEFICIARY_CUES = (
    "gift", "present for", "for my mother", "for my mom", "for my father", "for my dad", "for my sister",
    "for my brother", "for my friend", "for my parents",
    "هدية", "هديه", "لأمي", "لامي", "لأبوي", "لابوي", "لأبي", "لابي", "لأختي", "لاختي", "لأخوي", "لاخوي",
    "لأخي", "لاخي", "لخالتي", "لعمتي", "لصديقتي", "لصديقي", "لأهلي", "لاهلي",
)
_SHARED_BENEFICIARY_CUES = (
    "cleaning", "grocery", "groceries", "supermarket", "utilities", "bills", "bill", "both", "we ", "house ",
    "home ", "rent", "electricity", "water bill", "internet", "milk", "bread", "eggs", "rice", "vegetables",
    "مقاضي", "اغراض البيت", "لنا", "اثنيننا", "مشترك", "البيت", "فاتورة", "فاتوره", "الكهرباء", "كهرباء",
    "المياه", "الانترنت", "انترنت", "ايجار", "إيجار", "حليب", "خبز", "بيض", "رز", "خضار", "دجاج",
    "بنده", "عثيم", "تميمي", "دانوب", "لولو", "كارفور", "بقالة", "سوبرماركت",
)
# ─── Household categories added after the product review (PRODUCT-R4) ─────────
# System categories (cost_control_codes.household_id NULL) created by their own migration. Until
# that migration is applied a new code is replaced by its legacy code (the DB trigger
# validate_category_code_exists would refuse the insert otherwise).
OPEX_HOUSING = "OPEX-HOUSING"
OPEX_EDUCATION = "OPEX-EDUCATION"
OPEX_DOMESTIC_HELP = "OPEX-DOMESTIC-HELP"
OPEX_FAMILY_SUPPORT = "OPEX-FAMILY-SUPPORT"
OPEX_CHARITY = "OPEX-CHARITY"
OPEX_TRANSPORT = "OPEX-TRANSPORT"
OPEX_INSURANCE = "OPEX-INSURANCE"
OPEX_REMITTANCE = "OPEX-REMITTANCE"
NEW_SYSTEM_CATEGORY_CODES = (
    OPEX_HOUSING, OPEX_EDUCATION, OPEX_DOMESTIC_HELP, OPEX_FAMILY_SUPPORT,
    OPEX_CHARITY, OPEX_TRANSPORT, OPEX_INSURANCE, OPEX_REMITTANCE,
)
LEGACY_CATEGORY_FALLBACK = {
    OPEX_HOUSING: "OPEX-UTILITIES",  # its housing_rent sub-category
    OPEX_TRANSPORT: "OPEX-FUEL",  # its ride_hailing sub-category
}
DEFAULT_CATEGORY_CODE = "OPEX-MISC"

# Checked in this order (the first match wins); English cues match whole words, single Arabic /
# Urdu words also with a و/ب/ل/ف and ال/لل prefix but never inside another word ("معاملة" is not
# "عاملة"), phrases as written.
_NEW_CATEGORY_CUES = (
    (OPEX_REMITTANCE, (
        "remittance", "western union", "transfer abroad", "money transfer abroad", "sent money home",
        "send money home", "enjaz", "tahweel", "حوالة", "حواله", "حوالات", "تحويل للخارج", "تحويل خارجي",
        "ويسترن يونيون", "انجاز", "إنجاز", "تحويل الراجحي", "ترسیل زر", "ترسیلِ زر", "رقم بھیجی", "پیسے بھیجے",
    )),
    (OPEX_CHARITY, (
        "charity", "donation", "donated", "sadaqah", "sadaqa", "sadaka", "zakat", "zakah",
        "صدقة", "صدقه", "زكاة", "زكاه", "زكاة المال", "خيرات", "تبرع", "تبرعات", "إحسان",
        "صدقہ", "زکوٰۃ", "زکات", "زکوة", "خیرات", "خیرات",
    )),
    (OPEX_DOMESTIC_HELP, (
        "maid", "housemaid", "nanny", "driver", "domestic worker", "domestic help", "musaned",
        "خادمة", "خادمه", "خادمتي", "خادمتنا", "شغالة", "شغاله", "الشغالة", "سائق", "سواق", "سواقنا",
        "عاملة", "عاملة منزلية", "مربية", "مساند", "ڈرائیور", "ماسی", "نوکرانی", "ملازمہ",
    )),
    (OPEX_EDUCATION, (
        "school", "school fees", "tuition", "university", "college", "nursery", "kindergarten",
        "مدرسة", "مدرسه", "مدارس", "رسوم مدرسية", "رسوم المدرسة", "جامعة", "جامعه", "حضانة", "روضة",
        "رسوم دراسية", "اسکول", "اسکول فیس", "سکول", "ٹیوشن", "یونیورسٹی", "فیس",
    )),
    (OPEX_INSURANCE, (
        "insurance", "tameeni", "tawuniya", "bupa", "medgulf",
        "تأمين", "تامين", "التأمين", "تأميني", "تاميني", "التعاونية", "بوبا",
        "انشورنس", "بیمہ",
    )),
    (OPEX_HOUSING, (
        "rent", "landlord", "ejar", "housing",
        "ايجار", "إيجار", "اجار", "أجار", "ايجار الشقة", "إيجار الشقة", "إيجار البيت", "ايجار البيت",
        "منصة إيجار", "کرایہ", "کرایا", "مکان کا کرایہ",
    )),
    (OPEX_FAMILY_SUPPORT, (
        "parents", "my parents", "family support", "for my family back home",
        "الوالدين", "للوالدين", "مساعدة الأهل", "مساعدة الاهل", "لأهلي", "لاهلي", "مصروف الوالدة",
        "مصروف الوالد", "والدین", "گھر والوں", "امی ابو",
    )),
    (OPEX_TRANSPORT, (
        "taxi", "uber", "careem", "bolt", "bus", "metro", "train", "car installment", "car loan",
        "تاكسي", "اوبر", "أوبر", "كريم", "بولت", "مواصلات", "باص", "مترو", "قطار", "قسط السيارة",
        "قسط سيارة", "ٹیکسی", "رکشہ",
    )),
)
_ARABIC_LETTER = "\u0600-\u06FF"

# Sub-codes of the new categories (cost_control_sub_categories, migration 20261021000000): the
# first sub-code whose cues match wins, else the category's default (last entry, no cues).
NEW_CATEGORY_SUB_CODES = {
    OPEX_HOUSING: (
        ("annual_rent", ("annual rent", "yearly rent", "سنوي", "السنوي", "سنويا", "سنة كاملة", "سالانہ")),
        ("housing_services", ("maintenance", "service charge", "صيانة", "خدمات", "حارس", "مرافق", "مینٹیننس")),
        ("housing_rent", ()),
    ),
    OPEX_EDUCATION: (
        ("school_transport", ("school bus", "school transport", "باص المدرسة", "باص", "نقل مدرسي", "توصيل المدرسة",
                              "اسکول وین", "وین")),
        ("school_uniforms", ("uniform", "uniforms", "زي مدرسي", "الزي المدرسي", "مريول", "یونیفارم")),
        ("books_supplies", ("books", "stationery", "supplies", "كتب", "قرطاسية", "ادوات مدرسية", "أدوات مدرسية",
                            "کتابیں", "کاپیاں")),
        ("tuition_fees", ()),
    ),
    OPEX_DOMESTIC_HELP: (
        ("recruitment_visa", ("recruitment", "visa", "musaned", "استقدام", "تأشيرة", "تاشيرة", "مساند", "ویزا")),
        ("driver_salary", ("driver", "سائق", "سواق", "سواقنا", "ڈرائیور")),
        ("maid_salary", ()),
    ),
    OPEX_FAMILY_SUPPORT: (
        ("relatives_support", ("relatives", "my brother", "my sister", "اقارب", "أقارب", "أخوي", "اخوي", "أختي",
                               "اختي", "لأخي", "لاخي", "خالتي", "عمتي", "رشتہ دار", "بھائی", "بہن")),
        ("parents_support", ()),
    ),
    OPEX_CHARITY: (
        ("zakat", ("zakat", "zakah", "زكاة", "زكاه", "زكاة المال", "زکوٰۃ", "زکات", "زکوة")),
        ("sadaqah", ()),
    ),
    OPEX_TRANSPORT: (
        ("car_installment", ("car installment", "car loan", "قسط السيارة", "قسط سيارة", "تمويل السيارة",
                             "گاڑی کی قسط")),
        ("public_transport", ("bus", "metro", "train", "باص", "حافلة", "مترو", "قطار", "ٹرین")),
        ("car_maintenance", ("maintenance", "oil change", "tyres", "صيانة", "زيت", "كفرات", "ورشة",
                             "گاڑی کی مرمت")),
        ("ride_hailing", ()),
    ),
    OPEX_INSURANCE: (
        ("health_insurance", ("medical", "health", "bupa", "medgulf", "طبي", "صحي", "بوبا", "میڈیکل", "صحت")),
        ("home_insurance", ("home insurance", "house insurance", "تأمين المنزل", "تأمين البيت", "تامين المنزل",
                            "گھر کی انشورنس")),
        ("car_insurance", ()),
    ),
    OPEX_REMITTANCE: (
        ("transfer_fees", ("transfer fee", "transfer fees", "رسوم التحويل", "رسوم حوالة", "عمولة التحويل",
                           "عمولة", "ٹرانسفر فیس")),
        ("family_remittance", ()),
    ),
}


def _cue_in(text: str, cue: str) -> bool:
    """Whether ``cue`` occurs in ``text`` as a word (see _NEW_CATEGORY_CUES)."""
    import re

    if cue.isascii():
        return re.search(r"\b" + re.escape(cue) + r"\b", text) is not None
    if " " in cue:
        return cue in text
    stem = cue[2:] if cue.startswith("ال") and len(cue) > 4 else cue
    pattern = rf"(?<![{_ARABIC_LETTER}])(?:[وبلف])?(?:ال|لل)?{re.escape(stem)}(?![{_ARABIC_LETTER}])"
    return re.search(pattern, text) is not None


def new_category_sub_code(category_code: str, text: str) -> Optional[str]:
    """The sub-code of a new category for the text (its default when no cue matches)."""
    subs = NEW_CATEGORY_SUB_CODES.get(category_code)
    if not subs:
        return None
    lower = text.lower()
    for sub_code, cues in subs:
        if not cues or any(_cue_in(lower, cue) for cue in cues):
            return sub_code
    return subs[-1][0]


def new_category_for_text(text: str) -> Optional[str]:
    """One of the new household categories when the text names it, else None."""
    lower = text.lower()
    for code, cues in _NEW_CATEGORY_CUES:
        if any(_cue_in(lower, cue) for cue in cues):
            return code
    return None


def resolve_category_in_taxonomy(category_code: Optional[str], codes: list) -> str:
    """
    The code to store for a parsed (not user-chosen) category: itself when the taxonomy has it,
    the legacy code for a new system code whose migration is not applied yet, OPEX-MISC for a code
    the model made up. An empty taxonomy (lookup failed) leaves the decision to the database.
    """
    code = (category_code or DEFAULT_CATEGORY_CODE).strip() or DEFAULT_CATEGORY_CODE
    known = {getattr(c, "code", None) for c in codes or []}
    if not known or code in known:
        return code
    legacy = LEGACY_CATEGORY_FALLBACK.get(code, DEFAULT_CATEGORY_CODE)
    return legacy if legacy in known else DEFAULT_CATEGORY_CODE


# After the "ل" (for) prefix: pronoun suffixes and words that are never a dependent's name.
_NOT_A_NAME_AFTER_LAM = {
    "ي", "ه", "ها", "هم", "هن", "هما", "نا", "ك", "كم", "كن", "كي",
    "حالي", "نفسي", "نفسها", "نفسه", "البيت", "بيت", "لنا", "الزوجة", "المدام", "الزوج", "زوجتي", "زوجي",
    "لشريك", "شريك", "كل", "الكل", "عيال", "لعيال",
}
_WORDS_STARTING_WITH_LAM = {
    "لبن", "لبنة", "لحم", "لحوم", "ليمون", "لوز", "لابتوب", "لولو", "لاب", "لعبة", "لعب", "لوازم", "ليلة",
    "لاتيه", "لفة", "لزقة", "لمبة", "لمبات",
}


def _fallback_heuristic_parse(text: str) -> ParsedChatExpense:
    """Robust heuristic fallback parser for natural language expense logs and simulation queries."""
    import re
    raw = normalize_arabic_numbers(text.strip())
    lower = raw.lower()

    # Affordability simulation check (e.g. "Can I buy a 1200 SAR iPad?", "أقدر اشتري ايباد بـ 1200 ريال؟")
    sim_keywords = [
        "can i afford", "can i buy", "could i buy", "should i buy", "can we afford",
        "أقدر اشتري", "اقدر اشتري", "هل اقدر", "هل أقدر", "يمديني اشتري",
        "ينفع اشتري", "ميزانية ل", "ميزانيه ل", "هل في ميزانية", "هل تكفي الميزانية",
        "أشتري ولا", "اشتري ولا", "اقدر اجيب", "أقدر أجيب", "يمديني اطلب", "يمديني اجيب"
    ]
    if any(k in lower for k in sim_keywords):
        num_matches = re.findall(r'([0-9]+(?:\.[0-9]+)?)', raw)
        sim_amt = float(num_matches[0]) if num_matches else 0.0

        cleaned_item = raw
        for k in sim_keywords + ["sar", "riyal", "ريال", "رس", "?", "؟", "بـ", "ب", "for", "price"]:
            cleaned_item = re.sub(re.escape(k), "", cleaned_item, flags=re.IGNORECASE)
        cleaned_item = re.sub(r'[0-9]+(?:\.[0-9]+)?', '', cleaned_item).strip()
        if not cleaned_item or len(cleaned_item) < 2:
            cleaned_item = "Simulated Item"

        cat_code = "OPEX-SHOPPING"
        if any(w in cleaned_item.lower() for w in ("dinner", "lunch", "coffee", "restaurant", "مطعم", "عشاء", "عشا", "غداء", "غدا", "قهوة", "food")):
            cat_code = "OPEX-DINING"
        elif any(w in cleaned_item.lower() for w in ("flight", "travel", "hotel", "سفر", "طيران", "فندق")):
            cat_code = "OPEX-MISC"
        elif any(w in cleaned_item.lower() for w in ("grocer", "supermarket", "بنده", "تميمي", "مقاضي", "danube")):
            cat_code = "OPEX-GROCERY"

        return ParsedChatExpense(
            intent="simulation",
            is_transaction=False,
            is_simulation=True,
            simulated_amount=sim_amt,
            simulated_item=cleaned_item.title() if cleaned_item else "Item",
            merchant=cleaned_item.title() if cleaned_item else "Item",
            total_amount=sim_amt,
            currency="SAR",
            category_code=cat_code,
            spent_by="me",
            items=[],
            notes="Heuristic simulation detection",
        )

    has_expense_cues = bool(re.search(r'\d+', raw) and any(k in lower for k in ("بـ", "ريال", "sar", "دفعت", "شريت", "اشتريت", "spent", "paid")))

    # Off-topic banter check (checked first to catch weather, stories, jokes, chit-chat)
    offtopic_cues = [
        "story", "joke", "weather", "dragon", "poem", "python", "javascript", "code", "quicksort",
        "who are you", "what are you", "how are you", "hello", "hi", "hey", "tell me",
        "قصة", "حكاية", "نكتة", "الطقس", "جو اليوم", "برمج", "كود", "من انت", "مين انت", "كيف حالك",
        "اخبارك", "شخبارك", "صباح الخير", "مساء الخير", "سوالف", "سالفة", "دردش", "سولف"
    ]
    if any(k in lower for k in offtopic_cues) and not has_expense_cues:
        return ParsedChatExpense(
            intent="off_topic",
            is_transaction=False,
            is_simulation=False,
            notes="Heuristic off-topic detection",
        )

    # App guidance check
    guidance_cues = [
        "كيف اضبط", "كيف اغير", "كيف اسوي", "كيف اسجل", "كيف اضيف", "كيف اشغل", "طريقة", "شرح التطبيق",
        "وش هي النفقة", "ما هي النفقة", "ماهي النفقة", "وش هو التطبيق", "ما هو التطبيق", "ماهو التطبيق",
        "النفقة", "الرواتب", "دورة الراتب", "الحسابات", "محفظة", "توفير",
        "كيف استخدم", "how to use", "how do i", "explain nafaqah", "explain envelopes", "explain payday",
        "what is nafaqah", "what is payday", "what is an envelope", "tutorial", "payday", "nafaqah",
        "مساعدة في التطبيق", "ابغى اعرف عن التطبيق", "علمني عن التطبيق", "الميزانية كيف", "envelope",
        "كيف اقسم", "شرح", "تعليمات"
    ]
    if any(k in lower for k in guidance_cues) and not has_expense_cues:
        return ParsedChatExpense(
            intent="app_guidance",
            is_transaction=False,
            is_simulation=False,
            notes="Heuristic app guidance detection",
        )



    # Attribution 2D: paid_by and beneficiary (FABLE-LOGIC-07). The other spouse paying is checked
    # first ("دفعت زوجتي" also contains "دفعت", "paid by my husband" also contains "paid").
    words = re.findall(r"[\w']+", lower)
    paid_by = "me"
    payer_cue = True
    if any(k in lower for k in _PARTNER_PAID_CUES):
        paid_by = "partner"
    elif not any(k in lower for k in _ME_PAID_CUES):
        payer_cue = False  # nobody said who paid: the recorder, but the preview asks

    beneficiary_cue = True
    external = False
    if any(k in lower for k in _CHILDREN_CUES):
        beneficiary = "children"
    elif any(k in lower for k in _PARTNER_BENEFICIARY_CUES) or any(w in _PARTNER_PRONOUN_WORDS for w in words):
        beneficiary = "partner"
    elif any(k in lower for k in _ME_BENEFICIARY_CUES) or "لي" in words:
        beneficiary = "me"
    elif any(k in lower for k in _EXTERNAL_BENEFICIARY_CUES):
        # A gift / someone outside the household: neither shared nor obviously the recorder's own
        # allowance. Undetermined: no automatic Nafaqah class, the preview asks.
        beneficiary = "me"
        external = True
    elif any(k in lower for k in _SHARED_BENEFICIARY_CUES):
        beneficiary = "both"
    else:
        beneficiary = "me"
        beneficiary_cue = False
    if external:
        paid_by = "unknown"
    needs_confirmation = external or not (payer_cue or beneficiary_cue)

    # Backward-compatible spent_by
    if beneficiary == "both":
        spent_by = "both"
    elif paid_by == "partner" and beneficiary == "partner":
        spent_by = "partner"
    elif paid_by == "me" and beneficiary == "partner":
        spent_by = "partner"
    else:
        spent_by = "me"

    # Merchant extraction
    merchant = "Unknown Merchant"
    known_merchants_map = {
        "بنده": "Panda", "panda": "Panda",
        "العثيم": "Othaim", "عثيم": "Othaim", "othaim": "Othaim",
        "التميمي": "Tamimi", "تميمي": "Tamimi", "tamimi": "Tamimi",
        "الدانوب": "Danube", "دانوب": "Danube", "danube": "Danube",
        "كارفور": "Carrefour", "carrefour": "Carrefour",
        "لولو": "Lulu", "lulu": "Lulu",
        "البيك": "Albaik", "بيك": "Albaik", "albaik": "Albaik",
        "ماك": "McDonald's", "ماكدونالدز": "McDonald's", "mcdonald": "McDonald's",
        "ستاربكس": "Starbucks", "starbucks": "Starbucks",
        "دانكن": "Dunkin'", "dunkin": "Dunkin'",
        "جاهز": "Jahez", "jahez": "Jahez",
        "هنقرستيشن": "HungerStation", "هنقر": "HungerStation", "hungerstation": "HungerStation",
        "مرسول": "Mrsool", "mrsool": "Mrsool",
        "شاورمر": "Shawermer",
        "بارنز": "Barn's",
        "النهدي": "Nahdi", "نهدي": "Nahdi", "nahdi": "Nahdi",
        "الدواء": "Al Dawaa", "al dawaa": "Al Dawaa",
        "جرير": "Jarir", "jarir": "Jarir",
        "اكسترا": "Extra", "extra": "Extra",
        "نون": "Noon", "noon": "Noon",
        "امازون": "Amazon", "amazon": "Amazon",
        "ساسكو": "SASCO", "sasco": "SASCO",
        "الدريس": "Aldrees", "دريس": "Aldrees", "aldrees": "Aldrees",
        "نفط": "Naft",
        "سهل": "Sahel", "sahel": "Sahel",
        "ارامكو": "Aramco", "أرامكو": "Aramco", "aramco": "Aramco",
        "اوبر": "Uber", "أوبر": "Uber", "uber": "Uber",
        "كريم": "Careem", "careem": "Careem",
        "اس تي سي": "STC", "stc": "STC",
        "موبايلي": "Mobily", "mobily": "Mobily",
        "زين": "Zain", "zain": "Zain",
        "الكهرباء": "Electricity Bill", "الكهرب": "Electricity Bill",
        "western union": "Western Union", "ويسترن يونيون": "Western Union",
        "tameeni": "Tameeni", "تأميني": "Tameeni", "تاميني": "Tameeni",
        "tawuniya": "Tawuniya", "التعاونية": "Tawuniya",
        "bupa": "Bupa", "بوبا": "Bupa",
        "musaned": "Musaned", "مساند": "Musaned",
    }
    for km, canonical in known_merchants_map.items():
        if km in lower or km in raw:
            merchant = canonical
            break

    if merchant == "Unknown Merchant":
        m_match = re.search(r'(?:merchant|at|from|من|في)\s+([A-Za-z0-9\'\u0600-\u06FF&]+)', raw, re.IGNORECASE)
        if m_match:
            merchant = m_match.group(1).capitalize()
        else:
            words = raw.split()
            if words:
                merchant = words[0].capitalize()

    # Total amount extraction
    total_amount = 0.0
    amt_text = re.sub(r'بنزين\s*(?:91|95)', 'بنزين', raw)

    tot_match = re.search(r'(?:spent|total|for|بـ|ب|قيمة|مبلغ)\s*([0-9]+(?:\.[0-9]+)?)\s*(?:sar|riyal|ريال|رس)?', amt_text, re.IGNORECASE)
    if not tot_match:
        tot_match = re.search(r'([0-9]+(?:\.[0-9]+)?)\s*(?:sar|riyal|ريال|رس)', amt_text, re.IGNORECASE)
    if not tot_match:
        tot_match = re.search(r'([0-9]+(?:\.[0-9]+)?)', amt_text)

    if tot_match:
        try:
            total_amount = float(tot_match.group(1))
        except ValueError:
            total_amount = 0.0

    # Line items breakdown
    items: List[ChatLineItem] = []
    # Pattern: <price> <name> (e.g. "16 ice latte and 3 donut")
    item_matches = list(re.finditer(r'(\d+(?:\.\d+)?)\s*(?:sar|ريال)?\s+([a-zA-Z\u0600-\u06FF\s]+?)(?:and|و|,|$)', raw, re.IGNORECASE))
    for m in item_matches:
        try:
            val = float(m.group(1))
            name = m.group(2).strip()
            if name.lower() in (merchant.lower(), "total", "sar", "spent", "ريال", "ب") or "total" in name.lower():
                continue
            if val > 0 and len(name) > 1:
                items.append(ChatLineItem(name=name.title(), quantity=1.0, price=val))
        except ValueError:
            pass

    if not items:
        # Fallback Pattern: <name> <price> (e.g. "ice latte 16 sar, donut 3")
        item_matches_b = list(re.finditer(r'([a-zA-Z\u0600-\u06FF\s]+?)\s+(?:بـ|ب)?\s*(\d+(?:\.\d+)?)\s*(?:sar|riyal|ريال)?(?:and|و|,|$)', raw, re.IGNORECASE))
        for m in item_matches_b:
            try:
                name = m.group(1).strip()
                val = float(m.group(2))
                if name.lower() in ("spent", "total", "merchant", "at", "for", "شريت", "دفعت", "من"):
                    continue
                if val > 0 and len(name) > 1:
                    items.append(ChatLineItem(name=name.title(), quantity=1.0, price=val))
            except ValueError:
                pass

    if items:
        items_sum = sum(it.price for it in items)
        if total_amount == 0.0 or total_amount < items_sum:
            total_amount = items_sum
    elif total_amount > 0:
        items.append(ChatLineItem(name=merchant, quantity=1.0, price=total_amount))

    # Category code
    merchant_category_map = {
        "Albaik": "OPEX-DINING", "McDonald's": "OPEX-DINING", "Starbucks": "OPEX-DINING", "Dunkin'": "OPEX-DINING",
        "Jahez": "OPEX-DINING", "HungerStation": "OPEX-DINING", "Mrsool": "OPEX-DINING", "Shawermer": "OPEX-DINING", "Barn's": "OPEX-DINING",
        "Panda": "OPEX-GROCERY", "Othaim": "OPEX-GROCERY", "Tamimi": "OPEX-GROCERY", "Danube": "OPEX-GROCERY", "Lulu": "OPEX-GROCERY", "Carrefour": "OPEX-GROCERY",
        "SASCO": "OPEX-FUEL", "Aldrees": "OPEX-FUEL", "Naft": "OPEX-FUEL", "Sahel": "OPEX-FUEL", "Aramco": "OPEX-FUEL",
        "Uber": OPEX_TRANSPORT, "Careem": OPEX_TRANSPORT,
        "Western Union": OPEX_REMITTANCE, "Tameeni": OPEX_INSURANCE, "Tawuniya": OPEX_INSURANCE, "Bupa": OPEX_INSURANCE,
        "Musaned": OPEX_DOMESTIC_HELP,
        "STC": "OPEX-UTILITIES", "Mobily": "OPEX-UTILITIES", "Zain": "OPEX-UTILITIES", "Electricity Bill": "OPEX-UTILITIES",
        "Nahdi": "OPEX-HEALTH", "Al Dawaa": "OPEX-HEALTH",
        "Jarir": "OPEX-SHOPPING", "Extra": "OPEX-SHOPPING", "Noon": "OPEX-SHOPPING", "Amazon": "OPEX-SHOPPING",
    }
    cat_code = merchant_category_map.get(merchant) or new_category_for_text(raw)
    if not cat_code:
        words_list = lower.split()
        if any(k in lower for k in ("بنزين", "وقود", "محطة", "سولار", "ديزل", "fuel", "gas", "petrol")):
            cat_code = "OPEX-FUEL"
        elif any(k in lower for k in ("كهرب", "فاتورة كهرب", "مياه", "انترنت", "نت", "utilities", "bill")):
            cat_code = "OPEX-UTILITIES"
        elif any(k in lower for k in ("بقالة", "سوبرماركت", "مقاضي", "حليب", "دجاج", "خبز", "بيض", "grocery", "groceries", "supermarket", "milk", "bread", "chicken")) or "لبن" in words_list or "رز" in words_list:
            cat_code = "OPEX-GROCERY"
        elif any(k in lower for k in ("مطعم", "عشاء", "عشا", "غداء", "غدا", "فطور", "كافيه", "قهوة", "شاي", "كوفي", "ايس لاتيه", "حلا", "برجر", "شاورما", "dining", "restaurant", "burger", "cafe")):
            cat_code = "OPEX-DINING"
        elif any(k in lower for k in ("صيدلية", "دواء", "علاج", "بندول", "فيتامين", "pharmacy", "medicine", "doctor", "clinic", "hospital")):
            cat_code = "OPEX-HEALTH"
        elif any(k in lower for k in ("سوق", "ملابس", "عطر", "شاحن", "جوال", "لابتوب", "ايباد", "shopping", "clothes", "perfume", "electronics")):
            cat_code = "OPEX-SHOPPING"
        else:
            cat_code = "OPEX-MISC"

    # Derive sub-category
    sub_cat = new_category_sub_code(cat_code, raw)
    if sub_cat:
        pass
    elif cat_code == "OPEX-DINING":
        if any(w in lower for w in ("كافيه", "قهوة", "شاي", "كوفي", "ايس لاتيه", "حلا", "كيك", "دونات", "كرواسون", "مخبز", "coffee", "cafe", "starbucks", "dunkin")):
            sub_cat = "coffee_bakeries"
        elif any(w in lower for w in ("جاهز", "هنقرستيشن", "مرسول", "تويو", "jahez", "hungerstation", "mrsool", "toyou")):
            sub_cat = "delivery_apps"
        else:
            sub_cat = "restaurants_dinners"
    elif cat_code == "OPEX-GROCERY":
        if any(w in lower for w in ("لحم", "دجاج", "سمك", "meat", "chicken", "beef")):
            sub_cat = "meat"
        elif any(w in lower for w in ("خضار", "فواكه", "produce", "fruit", "vegetable")):
            sub_cat = "vegetables_fruit"
        elif any(w in lower for w in ("حليب", "جبن", "بيض", "لبن", "زبادي", "milk", "cheese", "egg", "dairy")):
            sub_cat = "dairy_eggs"
        elif any(w in lower for w in ("شيبس", "بسكويت", "شوكولاته", "سناك", "chips", "snack", "chocolate")):
            sub_cat = "snacks_chips"
        elif any(w in lower for w in ("ماء", "موية", "عصير", "ببسي", "مشروب", "water", "juice", "beverage")):
            sub_cat = "beverages"
        elif any(w in lower for w in ("صابون", "تايد", "شامبو", "كلوركس", "مناديل", "cleaning", "detergent")):
            sub_cat = "cleaning_household"
        else:
            sub_cat = "pantry_staples"
    elif cat_code == "OPEX-FUEL":
        if any(w in lower for w in ("اوبر", "كريم", "بوليت", "تاكسي", "مشوار", "uber", "careem", "bolt", "ride")):
            sub_cat = "ride_hailing"
        elif any(w in lower for w in ("زيت", "كفرات", "صيانة", "ورشة", "mechanic", "maintenance")):
            sub_cat = "car_maintenance"
        else:
            sub_cat = "gas_fuel"
    elif cat_code == "OPEX-HEALTH":
        if any(w in lower for w in ("عيادة", "اسنان", "طبيب", "دكتور", "clinic", "dental", "doctor")):
            sub_cat = "clinics_dental"
        else:
            sub_cat = "prescriptions_meds"
    elif cat_code == "OPEX-SHOPPING":
        if any(w in lower for w in ("ملابس", "ثوب", "فستان", "حذاء", "شوز", "clothes", "fashion", "zara")):
            sub_cat = "clothing_fashion"
        elif any(w in lower for w in ("جوال", "لابتوب", "ايباد", "سماعة", "شاحن", "كمبيوتر", "electronics", "gadget")):
            sub_cat = "electronics_gadgets"
        else:
            sub_cat = "home_furniture"

    for it in items:
        if not getattr(it, "sub_category", None):
            it.sub_category = sub_cat

    # Detect a child / dependent named after the "ل" (for) prefix ("حليب لسارة"), unless an
    # explicit cue already decided the beneficiary. Pronoun suffixes (لها، له، لي، لنا ...) and
    # ordinary words starting with ل (لبن، لحم ...) are never names (FABLE-LOGIC-07).
    if beneficiary == "both" or not beneficiary_cue:
        for child_match in re.finditer(r'(?:^|\s)ل(?:ـ)?([^\s\d.,!?]+)', raw):
            cand = child_match.group(1).strip()
            if cand in _NOT_A_NAME_AFTER_LAM or ("ل" + cand) in _WORDS_STARTING_WITH_LAM or len(cand) < 2:
                continue
            beneficiary = cand
            beneficiary_cue = True
            needs_confirmation = external or not (payer_cue or beneficiary_cue)
            break

    if total_amount == 0.0 and (merchant == "Unknown Merchant" or not items):
        return ParsedChatExpense(
            intent="off_topic",
            is_transaction=False,
            is_simulation=False,
            notes="No financial transaction detected in text",
        )

    return ParsedChatExpense(
        intent="transaction",
        is_transaction=True,
        merchant=merchant,
        total_amount=total_amount,
        currency="SAR",
        category_code=cat_code,
        sub_category=sub_cat,
        spent_by=spent_by,
        paid_by=paid_by,
        beneficiary=beneficiary,
        items=items,
        notes="Parsed via robust heuristic fallback",
        attribution_needs_confirmation=needs_confirmation,
    )



def parse_chat_expense(text: str) -> ParsedChatExpense:
    """Call Gemini to extract structured expense information from user chat text, with graceful fallback."""
    text = normalize_arabic_numbers(text)
    model = litellm_model()
    
    try:
        response = litellm.completion(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
        )
        content = response.choices[0].message.content
        data = json.loads(content)
        parsed = ParsedChatExpense(**data)
        if parsed.intent == "off_topic":
            parsed.is_transaction = False
            parsed.is_simulation = False
        elif parsed.intent == "simulation":
            parsed.is_simulation = True
            parsed.is_transaction = False
        elif parsed.intent == "app_guidance":
            parsed.is_transaction = False
            parsed.is_simulation = False
        return parsed
    except Exception as exc:
        logger.warning("LiteLLM completion failed (%s). Using fallback heuristic parser.", exc)
        return _fallback_heuristic_parse(text)


def _parsed_from_preview_token(
    token: Optional[str], household_id: str, user_id: Optional[str], message_digest: str,
) -> Optional[ParsedChatExpense]:
    """The signed parse of this message, or None when the caller must run the parser."""
    if token is None:
        return None
    check = verify_preview_token(token, KIND_CHAT, user_id, household_id)  # InvalidPreviewToken
    if not check.valid:
        logger.info("Chat preview token %s: re-parsing.", check.status)
        return None
    if check.binding.get("m") != message_digest:
        logger.info("Chat preview token was issued for another message: re-parsing.")
        return None
    try:
        return ParsedChatExpense(**check.payload)
    except Exception as exc:  # signed by us, so only a format change between releases
        raise InvalidPreviewToken("payload no longer valid") from exc


def _issue_chat_token(
    parsed: ParsedChatExpense, household_id: str, user_id: Optional[str], message_digest: str,
) -> Optional[str]:
    return issue_preview_token(
        KIND_CHAT, user_id, household_id, parsed.model_dump(mode="json"), {"m": message_digest},
    )


def check_category_active_status(category_code: str, categories_state: dict) -> bool:
    """
    Returns True if category_code is active for the household,
    False if it is explicitly listed in categories_state['inactive'].
    """
    inactive_codes = {c["code"] for c in categories_state.get("inactive", [])}
    return category_code not in inactive_codes


def process_chat_transaction(
    household_id: str,
    message: str,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
    preview_only: bool = False,
    override_merchant: Optional[str] = None,
    override_spent_by: Optional[str] = None,
    override_category_code: Optional[str] = None,
    override_sub_category: Optional[str] = None,
    override_paid_by: Optional[str] = None,
    override_beneficiary: Optional[str] = None,
    occurred_at: Optional[datetime] = None,
    override_nafaqah_class: Optional[str] = None,
    override_nafaqah_spouse_id: Optional[str] = None,
    preview_token: Optional[str] = None,
    override_amount: Optional[float] = None,
    override_account_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Parse a chat message, perform duplicate checks/enrichment, update budget, and insert transaction.

    One LLM call per expense (PRODUCT-R6): the preview (and a duplicate prompt) returns a signed
    ``preview_token`` of the parsed message. A request that sends it back for the same message is
    served from the signed payload without calling the model; every override below is applied and
    validated exactly as without a token. An expired or unverifiable token, or one for another
    message, re-parses; a tampered one raises InvalidPreviewToken (HTTP 422).

    Family households (Islamic Nafaqah): an expense the wife paid is classified as
    ``wife_reimbursable`` (shared → the husband owes her) or ``wife_personal`` (charged to her
    allowance). The preview returns the suggestion (and the wives, for a household with several);
    ``override_nafaqah_class`` is the user's confirmed choice ('wife_reimbursable' |
    'wife_personal' | 'none') and must agree with an explicit paid_by/beneficiary;
    ``override_nafaqah_spouse_id`` names the wife when there are several
    (nafaqah_service.resolve_expense_nafaqah raises InvalidNafaqahRequest otherwise). Nothing is
    ever split between the spouses, and roommate households are never classified.
    """
    message_digest = text_digest(message)
    parsed = _parsed_from_preview_token(preview_token, household_id, user_id, message_digest)
    if parsed is None:
        parsed = parse_chat_expense(message)
    if parsed.is_simulation:
        from salary_cycle import simulate_affordability
        sim_amt = parsed.simulated_amount or parsed.total_amount
        sim_item = parsed.simulated_item or parsed.merchant or "Item"
        sim_res = simulate_affordability(
            household_id=household_id,
            target_amount=sim_amt,
            item_name=sim_item,
            category_code=parsed.category_code,
        )
        is_arabic = any(ord(c) > 127 for c in message)
        advice = sim_res["advice_ar"] if is_arabic else sim_res["advice_en"]
        return {
            "status": "simulation",
            "is_simulation": True,
            "simulation": sim_res,
            "merchant": sim_item,
            "amount": sim_amt,
            "category_code": parsed.category_code,
            "verdict": sim_res["verdict"],
            "message": advice,
            "advice_en": sim_res["advice_en"],
            "advice_ar": sim_res["advice_ar"],
            "days_to_payday": sim_res["days_to_payday"],
            "current_total_remaining": sim_res["current_total_remaining"],
            "post_purchase_remaining": sim_res["post_purchase_remaining"],
            "current_daily_allowance": sim_res["current_daily_allowance"],
            "post_purchase_daily_allowance": sim_res["post_purchase_daily_allowance"],
        }

    if parsed.intent == "off_topic":
        return {
            "status": "off_topic",
            "intent": "off_topic",
            "message": "Off-topic chit-chat detected.",
        }

    if parsed.intent == "app_guidance":
        return {
            "status": "app_guidance",
            "intent": "app_guidance",
            "message": "App guidance requested.",
        }

    if not parsed.is_transaction:
        return {
            "status": "non_transactional",
            "message": "The message does not appear to contain a transaction expense.",
        }

    if override_amount is not None:
        # The user corrected the amount in the confirmation card (UX-12; validated by the route).
        # A single line that was the whole amount follows it; an itemised list stays as parsed.
        if len(parsed.items) == 1 and abs(parsed.items[0].price * (parsed.items[0].quantity or 1) - parsed.total_amount) < 0.005:
            parsed.items[0].price = override_amount
            parsed.items[0].quantity = 1.0
        parsed.total_amount = override_amount

    items_dicts = [item.model_dump() for item in parsed.items]

    # Explicit enrichment request
    if enrich_tx_id:
        success = enrich_transaction_items(enrich_tx_id, items_dicts, household_id=household_id, actor_user_id=user_id)
        if not success:
            return {
                "status": "error",
                "transaction_id": enrich_tx_id,
                "message": "Transaction to enrich was not found in this household.",
            }
        return {
            "status": "enriched",
            "transaction_id": enrich_tx_id,
            "merchant": parsed.merchant,
            "amount": parsed.total_amount,
            "category_code": parsed.category_code,
            "items": items_dicts,
            "message": f"Successfully enriched existing transaction with {len(items_dicts)} items.",
        }

    # The merchant is shown and stored as text: no audit separator or tag keyword (FABLE-API-01).
    merchant = sanitize_audit_text(override_merchant or parsed.merchant, MAX_MERCHANT_LENGTH) or "Unknown Merchant"

    # Match or fallback category
    codes = fetch_household_cost_control_codes(household_id) if household_id else fetch_all_cost_control_codes()
    matched = match_category(merchant, codes)
    if override_category_code is not None and override_category_code != "":
        # A client-chosen category must exist for this household (global or its own custom
        # code); otherwise the DB trigger refuses the insert. Answer 422, not 500 (E2E-03).
        if (
            not isinstance(override_category_code, str)
            or not override_category_code.strip()
            or len(override_category_code) > 100
            or category_code_in_taxonomy(household_id, override_category_code.strip()) is False
        ):
            raise UnknownCategoryError()
        override_category_code = override_category_code.strip()
    parsed_category = resolve_category_in_taxonomy(parsed.category_code, codes)
    category_code = override_category_code or (matched.code if matched else parsed_category)

    # The parsed sub-category belongs to the parsed code only (not to a legacy fallback).
    parsed_sub = getattr(parsed, "sub_category", None) if parsed_category == parsed.category_code else None
    sub_category = override_sub_category or parsed_sub
    if not sub_category and category_code:
        try:
            from salary_cycle import match_sub_category
            sub_category = match_sub_category(category_code, f"{merchant} {message}", items_dicts, household_id=household_id)
        except Exception:
            pass

    parsed_paid_by = str(getattr(parsed, "paid_by", "me") or "me").lower()
    # The heuristic parser could not tell who paid for what (FABLE-LOGIC-07): the preview asks
    # (attribution_needs_confirmation) and, for 'unknown' (e.g. a gift outside the household),
    # suggests no Nafaqah class. A commit without an explicit choice records the recorder paying.
    attribution_explicit = override_paid_by is not None or override_beneficiary is not None
    needs_confirmation = not attribution_explicit and (
        parsed_paid_by == "unknown" or bool(getattr(parsed, "attribution_needs_confirmation", False))
    )
    paid_by = (override_paid_by or parsed_paid_by).lower()
    classify_as = "unknown" if (preview_only and paid_by == "unknown" and not attribution_explicit) else None
    if paid_by not in ("me", "partner"):
        paid_by = "me"

    beneficiary = override_beneficiary or getattr(parsed, "beneficiary", "both")

    # Ensure items have sub_category (respect explicit user override)
    for it in items_dicts:
        if override_sub_category or not it.get("sub_category"):
            it["sub_category"] = sub_category

    nafaqah = resolve_expense_nafaqah(
        household_id,
        user_id,
        classify_as or paid_by,
        beneficiary,
        override_class=override_nafaqah_class,
        override_spouse_id=override_nafaqah_spouse_id,
        attribution_explicit=attribution_explicit,
        require_spouse=not preview_only,
    )
    paid_by, beneficiary = nafaqah["paid_by"], nafaqah["beneficiary"]
    if paid_by not in ("me", "partner"):
        paid_by = "me"
    # spent_by is the payer relative to the recorder ('me' | 'partner'); the client's legacy
    # spent_by is ignored so the stored columns never contradict paid_by (FABLE-LOGIC-03).
    spent_by = paid_by

    # Check if category is inactive for this household
    is_inactive = False
    try:
        from salary_cycle import get_household_categories
        hh_cats = get_household_categories(household_id)
        is_inactive = not check_category_active_status(category_code, hh_cats)
    except Exception as exc:
        logger.warning(f"Could not check category active status: {exc}")

    # If preview only, return structured data asking user for confirmation
    if preview_only:
        dependents = []
        try:
            from dependents_service import get_household_dependents
            dependents = get_household_dependents(household_id)
        except Exception as exc:
            logger.debug("Could not fetch dependents: %s", exc)

        available_subs = []
        try:
            from salary_cycle import get_sub_categories_for_parent
            available_subs = get_sub_categories_for_parent(category_code, [household_id])
        except Exception as exc:
            logger.debug("Could not fetch sub categories: %s", exc)

        return {
            "status": "pending_confirmation",
            "preview_token": _issue_chat_token(parsed, household_id, user_id, message_digest),
            "merchant": merchant,
            "amount": parsed.total_amount,
            "category_code": category_code,
            "sub_category": sub_category,
            "available_sub_categories": available_subs,
            "is_category_inactive": is_inactive,
            "suggested_alternative": "OPEX-MISC" if is_inactive else None,
            "spent_by": spent_by,
            "paid_by": paid_by,
            "beneficiary": beneficiary,
            "attribution_needs_confirmation": needs_confirmation,
            "dependents": [d.get("name") for d in dependents if d.get("name")],
            "household_mode": nafaqah["household_mode"],
            "recorder_role": nafaqah["recorder_role"],
            "nafaqah_class": nafaqah["nafaqah_class"],
            "nafaqah_spouse_id": nafaqah["nafaqah_spouse_id"],
            "nafaqah_spouse_required": nafaqah["nafaqah_spouse_required"],
            "wives": nafaqah["wives"],
            "items": items_dicts,
            "account_id": override_account_id,
            "original_message": message,
            "message": f"Found expense of SAR {parsed.total_amount:.2f} ({len(items_dicts)} items). Please confirm details:",
        }

    # Duplicate check
    if not allow_duplicate:
        candidate = find_duplicate_candidate(household_id, parsed.total_amount, parsed.merchant)
        if candidate:
            logger.info("Duplicate candidate found for chat transaction: %s", candidate["id"])
            return {
                "status": "duplicate_candidate",
                "preview_token": _issue_chat_token(parsed, household_id, user_id, message_digest),
                "candidate_transaction_id": candidate["id"],
                "candidate_merchant": candidate.get("merchant"),
                "candidate_amount": candidate.get("amount"),
                "candidate_timestamp": candidate.get("timestamp"),
                "parsed_data": {
                    "merchant": parsed.merchant,
                    "amount": parsed.total_amount,
                    "category_code": parsed.category_code,
                    "items": items_dicts,
                },
                "message": (
                    f"A transaction of SAR {candidate.get('amount')} at '{candidate.get('merchant')}' "
                    f"was already recorded recently. Would you like to enrich it or log a separate expense?"
                ),
            }

    # Who paid and for whom, as columns; refused (422) before any budget is touched when
    # 'partner' names nobody in this household.
    # A classified expense in a family without a provider is refused here (409 no_provider).
    attribution = household_attribution(
        household_id, user_id, paid_by, beneficiary, nafaqah["nafaqah_spouse_id"],
        nafaqah_class=nafaqah["nafaqah_class"],
    )

    # A replayed offline commit carries the client-side event time (validated by the route).
    event_time = occurred_at or datetime.now(timezone.utc)
    now_iso = event_time.isoformat()
    now_date = riyadh_date_for_timestamp(event_time)

    # Check budget and reallocate if necessary
    budget = fetch_budget(household_id, category_code, now_date)
    is_reallocated = False
    reallocated_from_id = None

    if budget and budget.remaining_amount < parsed.total_amount:
        # Need reallocation
        deficit = parsed.total_amount - budget.remaining_amount
        flexible = fetch_flexible_budgets(household_id, now_date, exclude_code=category_code)
        if flexible and flexible[0].remaining_amount >= deficit:
            if reallocate_budget(flexible[0].id, budget.id, deficit):
                is_reallocated = True
                reallocated_from_id = flexible[0].id

    # Audit note for humans: the server's tags first, the user's text defused (FABLE-API-01).
    items_summary = ", ".join(
        f"{it.get('quantity', 1)}x {sanitize_audit_text(it.get('name'), 80)} ({it.get('price')} SAR)"
        for it in items_dicts
    )
    audit_text = build_audit_note(
        paid_by, beneficiary, spent_by,
        f"Chat: {sanitize_audit_text(message, 1000)}",
        f"Items: [{items_summary}]" if items_summary else "",
    )

    # Insert transaction
    tx_id = insert_transaction(
        household_id=household_id,
        amount=parsed.total_amount,
        currency="SAR",
        merchant=merchant,
        category_code=category_code,
        sub_category=sub_category,
        timestamp=now_iso,
        raw_sms=audit_text,
        is_reallocated=is_reallocated,
        reallocated_from_budget_id=reallocated_from_id,
        source="chat",
        items=items_dicts,
        spent_by=attribution["spent_by"],
        beneficiary_type=attribution["beneficiary_type"],
        beneficiary_id=attribution["beneficiary_id"],
        nafaqah_class=nafaqah["nafaqah_class"],
        nafaqah_spouse_id=nafaqah["nafaqah_spouse_id"],
        user_id=user_id,
        account_id=override_account_id,
    )

    # Attach items fallback if needed
    if items_dicts:
        enrich_transaction_items(tx_id, items_dicts, household_id=household_id)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": merchant,
        "amount": parsed.total_amount,
        "category_code": category_code,
        "sub_category": sub_category,
        "spent_by": spent_by,
        "paid_by": paid_by,
        "beneficiary": beneficiary,
        "nafaqah_class": nafaqah["nafaqah_class"],
        "nafaqah_spouse_id": nafaqah["nafaqah_spouse_id"],
        "account_id": override_account_id,
        "is_reallocated": is_reallocated,
        "items": items_dicts,
        "message": f"Recorded SAR {parsed.total_amount:.2f} at {merchant} under {category_code} ({spent_by}).",
    }
