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
    match_category,
    insert_transaction,
    fetch_budget,
    fetch_flexible_budgets,
    reallocate_budget,
    category_code_in_taxonomy,
    household_attribution,
    UnknownCategoryError,
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
- OPEX-FUEL: gas_fuel, car_maintenance, ride_hailing (Aramco, Sahel, SASCO, Aldrees, Uber, Careem, ساسكو, الدريس, بنزين 91, بنزين 95, اوبر)
- OPEX-UTILITIES: electricity_sec, fiber_internet, mobile_sims, water_municipal, housing_rent (STC, Mobily, Zain, SEC, الكهرباء, المياه, ايجار)
- OPEX-SHOPPING: clothing_fashion, electronics_gadgets, home_furniture (Jarir, Extra, Noon, Amazon, Apple, Ikea, جرير, اكسترا, ايكيا)
- OPEX-HEALTH: prescriptions_meds, clinics_dental (Nahdi, Al Dawaa, Habib, النهدي, الدواء, صيدلية, عيادة)
- OPEX-ENTERTAINMENT: Movies, cinemas, streaming, gaming (Muvi, Vox, Netflix, PlayStation, Shahid)
- OPEX-MISC: Anything else that doesn't fit above (house cleaning, maintenance).

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

Return STRICTLY valid JSON conforming to:
{
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
"""

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

    # Attribution 2D: paid_by and beneficiary
    paid_by = "me"
    if any(k in lower for k in ("partner paid", "wife paid", "husband paid", "حاسبتها هي", "دفعتها زوجتي", "دفعه زوجي", "حاسبت زوجتي", "دفعت زوجتي")):
        paid_by = "partner"
    elif any(k in lower for k in ("i paid", "i spent", "دفعتها انا", "دفعتها أنا", "دفعته انا", "دفعته أنا", "ع حسابي", "على حسابي", "حاسبت انا")):
        paid_by = "me"

    children_keywords = (
        "for the kids", "for my kids", "for the children", "for my children",
        "للعيال", "للأولاد", "للاولاد", "للأطفال", "للاطفال", "للبنات",
    )
    beneficiary = "me"
    if any(k in lower for k in children_keywords):
        beneficiary = "children"
    elif any(k in lower for k in ("for my wife", "for partner", "for husband", "for her", "for him", "لزوجتي", "لزوجي", "للشريك", "فستان زوجتي", "هدية")):
        beneficiary = "partner"
    elif any(k in lower for k in ("for me", "for myself", "bought myself", "لي لحالي", "شريت لنفسي", "لنفسي", "قهوتي", "ملابسي", "دفعتها انا", "دفعتها أنا", "دفعته انا", "دفعته أنا")):
        beneficiary = "me"
    elif any(k in lower for k in ("cleaning", "grocery", "groceries", "supermarket", "utilities", "bills", "both", "we ", "house ", "home ", "مقاضي", "اغراض البيت", "لنا", "اثنيننا", "مشترك", "البيت")):
        beneficiary = "both"
    elif any(k in lower for k in ("بنده", "عثيم", "تميمي", "دانوب", "لولو", "كارفور", "بقالة", "سوبرماركت")):
        beneficiary = "both"
    else:
        beneficiary = "me"

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
        "SASCO": "OPEX-FUEL", "Aldrees": "OPEX-FUEL", "Naft": "OPEX-FUEL", "Sahel": "OPEX-FUEL", "Aramco": "OPEX-FUEL", "Uber": "OPEX-FUEL", "Careem": "OPEX-FUEL",
        "STC": "OPEX-UTILITIES", "Mobily": "OPEX-UTILITIES", "Zain": "OPEX-UTILITIES", "Electricity Bill": "OPEX-UTILITIES",
        "Nahdi": "OPEX-HEALTH", "Al Dawaa": "OPEX-HEALTH",
        "Jarir": "OPEX-SHOPPING", "Extra": "OPEX-SHOPPING", "Noon": "OPEX-SHOPPING", "Amazon": "OPEX-SHOPPING",
    }
    cat_code = merchant_category_map.get(merchant)
    if not cat_code:
        words_list = lower.split()
        if any(k in lower for k in ("بنزين", "وقود", "محطة", "سولار", "ديزل", "fuel", "gas", "petrol", "taxi")):
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
    sub_cat = None
    if cat_code == "OPEX-DINING":
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

    # Detect child / dependent name in beneficiary
    child_match = re.search(r'(?:^|\s)ل(?:ـ)?([^\s\d.,!?]+)', raw)
    if child_match and beneficiary != "children":
        cand = child_match.group(1).strip()
        if cand not in ("ي", "حالي", "نفسي", "البيت", "لنا", "الزوجة", "المدام", "الزوج", "زوجتي", "زوجي", "لشريك"):
            beneficiary = cand

    return ParsedChatExpense(
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
        return ParsedChatExpense(**data)
    except Exception as exc:
        logger.warning("LiteLLM completion failed (%s). Using fallback heuristic parser.", exc)
        return _fallback_heuristic_parse(text)


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
) -> Dict[str, Any]:
    """
    Parse a chat message, perform duplicate checks/enrichment, update budget, and insert transaction.

    Family households (Islamic Nafaqah): an expense the wife paid is classified as
    ``wife_reimbursable`` (shared → the husband owes her) or ``wife_personal`` (charged to her
    allowance). The preview returns the suggestion (and the wives, for a household with several);
    ``override_nafaqah_class`` is the user's confirmed choice ('wife_reimbursable' |
    'wife_personal' | 'none') and must agree with an explicit paid_by/beneficiary;
    ``override_nafaqah_spouse_id`` names the wife when there are several
    (nafaqah_service.resolve_expense_nafaqah raises InvalidNafaqahRequest otherwise). Nothing is
    ever split between the spouses, and roommate households are never classified.
    """
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

    if not parsed.is_transaction:
        return {
            "status": "non_transactional",
            "message": "The message does not appear to contain a transaction expense.",
        }

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
    codes = fetch_all_cost_control_codes()
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
    category_code = override_category_code or (matched.code if matched else parsed.category_code)

    sub_category = override_sub_category or getattr(parsed, "sub_category", None)
    if not sub_category and category_code:
        try:
            from salary_cycle import match_sub_category
            sub_category = match_sub_category(category_code, f"{merchant} {message}", items_dicts, household_id=household_id)
        except Exception:
            pass

    paid_by = (override_paid_by or getattr(parsed, "paid_by", "me")).lower()
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
        paid_by,
        beneficiary,
        override_class=override_nafaqah_class,
        override_spouse_id=override_nafaqah_spouse_id,
        attribution_explicit=override_paid_by is not None or override_beneficiary is not None,
        require_spouse=not preview_only,
    )
    paid_by, beneficiary = nafaqah["paid_by"], nafaqah["beneficiary"]
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
            "dependents": [d.get("name") for d in dependents if d.get("name")],
            "household_mode": nafaqah["household_mode"],
            "recorder_role": nafaqah["recorder_role"],
            "nafaqah_class": nafaqah["nafaqah_class"],
            "nafaqah_spouse_id": nafaqah["nafaqah_spouse_id"],
            "nafaqah_spouse_required": nafaqah["nafaqah_spouse_required"],
            "wives": nafaqah["wives"],
            "items": items_dicts,
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
    attribution = household_attribution(household_id, user_id, paid_by, beneficiary, nafaqah["nafaqah_spouse_id"])

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
        "is_reallocated": is_reallocated,
        "items": items_dicts,
        "message": f"Recorded SAR {parsed.total_amount:.2f} at {merchant} under {category_code} ({spent_by}).",
    }
