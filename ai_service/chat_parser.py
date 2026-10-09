"""
Natural language chat transaction parser using Gemini via LiteLLM.
Extracts merchant, total amount, category, and itemized line items.
"""

from __future__ import annotations
import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field

import litellm
from dotenv import load_dotenv

load_dotenv()

from dedup_engine import find_duplicate_candidate, enrich_transaction_items
from supabase_client import (
    fetch_all_cost_control_codes,
    match_category,
    insert_transaction,
    fetch_budget,
    fetch_flexible_budgets,
    reallocate_budget,
)

logger = logging.getLogger(__name__)

class ChatLineItem(BaseModel):
    name: str = Field(..., description="Name of the item purchased")
    quantity: float = Field(1.0, description="Quantity of item")
    price: float = Field(..., description="Total price for this item line in SAR")

class ParsedChatExpense(BaseModel):
    is_transaction: bool = Field(True, description="Whether the text represents a financial expense to record")
    is_simulation: bool = Field(False, description="Whether the user is asking an affordability simulation question like 'Can I buy a 1200 SAR iPad?' or 'أقدر اشتري ايباد بـ 1200 ريال؟'")
    simulated_amount: Optional[float] = Field(None, description="Simulated purchase price in SAR")
    simulated_item: Optional[str] = Field(None, description="Simulated item or merchant name")
    merchant: str = Field("Unknown Merchant", description="Store or merchant name")
    total_amount: float = Field(0.0, description="Total amount in SAR")
    currency: str = "SAR"
    category_code: str = Field("OPEX-MISC", description="Category code like OPEX-DINING, OPEX-GROCERY, OPEX-SHOPPING, etc.")
    spent_by: str = Field("both", description="Who spent this: 'me', 'partner', or 'both'")
    paid_by: str = Field("me", description="Who paid: 'me' or 'partner'")
    beneficiary: str = Field("both", description="For whom: 'me', 'partner', or 'both'")
    items: List[ChatLineItem] = Field(default_factory=list, description="Itemized breakdown")
    notes: Optional[str] = None

def normalize_arabic_numbers(text: str) -> str:
    """Converts Eastern Arabic numerals (٠-٩) and Persian numerals to Western digits (0-9)."""
    eastern_to_western = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
    return text.translate(eastern_to_western)


SYSTEM_PROMPT = """You are an intelligent financial assistant for a Saudi budget tracker.
Parse natural language expense logs into structured financial transactions with line-item breakdowns, OR detect pre-purchase affordability simulation questions.

Categories available:
- OPEX-GROCERY: Supermarkets, groceries, food stores (Tamimi, Danube, Panda, Carrefour, Lulu, Othaim, بنده, العثيم, التميمي, مقاضي)
- OPEX-DINING: Restaurants, cafes, fast food, coffee shops, bakeries, delivery (Dunkin, Starbucks, Albaik, McDonald's, Jahez, Hungerstation, Mrsool, البيك, جاهز, هنقرستيشن)
- OPEX-FUEL: Fuel stations, gas, transport, taxi, Uber, Careem, trains (Aramco, Sahel, SASCO, Aldrees, ساسكو, الدريس, بنزين 91, بنزين 95)
- OPEX-UTILITIES: Electricity, water, internet, mobile bills (STC, Mobily, Zain, SEC, الكهرباء, المياه)
- OPEX-SHOPPING: Retail, clothing, electronics, books, iPad, gadgets (Jarir, Extra, Noon, Amazon, Apple, جرير, اكسترا)
- OPEX-ENTERTAINMENT: Movies, cinemas, streaming, gaming, concerts (Muvi, Vox, Netflix, PlayStation, Shahid)
- OPEX-HEALTH: Pharmacies, clinics, doctors, hospitals, medicine (Nahdi, Al Dawaa, Habib, النهدي, الدواء, صيدلية)
- OPEX-MISC: Anything else that doesn't fit above (house cleaning, maintenance, home services).

SAUDI COLLOQUIAL ARABIC & VOICE ENTRY SUPPORT:
Users frequently log transactions in Saudi dialect (اللهجة السعودية الدارجة). Interpret colloquial Saudi verbs and expressions accurately:
- Verbs: "عبيت" (filled/fueled), "تقضيت" (bought groceries), "حاسبت" (paid), "دفعت" (paid), "سددت" (settled bill), "شريت" (bought), "جبت" (got), "طلبت" (ordered delivery).
- Slang items: "بنزين 91 / 95" -> OPEX-FUEL, "مقاضي البيت" -> OPEX-GROCERY, "عشاء / غداء / قهوة / شاهي / حلا" -> OPEX-DINING, "بندول" -> OPEX-HEALTH, "فاتورة الكهرب / النت" -> OPEX-UTILITIES.
- Attribution ("spent_by"):
  - "دفعتها أنا / دافعه أنا / ع حسابي / لي لحالي" -> "me"
  - "دفعتها زوجتي / حاسبها زوجي / جابته المدام" -> "partner"
  - "مقاضي البيت / لنا اثنيننا / مشترك / للبيت" -> "both" (default for grocery/house bills)
- Local Saudi Merchants:
  - Groceries: بنده (Panda), العثيم (Othaim), التميمي (Tamimi), الدانوب (Danube), لولو (Lulu), كارفور (Carrefour)
  - Dining & Delivery: البيك (Albaik), ماك (McDonald's), جاهز (Jahez), هنقرستيشن (HungerStation), مرسول (Mrsool), بارنز (Barn's), دانكن (Dunkin')
  - Fuel: ساسكو (SASCO), الدريس (Aldrees), نفط (Naft), أرامكو (Aramco), سهل (Sahel)
  - Health: النهدي (Nahdi), الدواء (Al Dawaa), الحبيب (Al Habib)
  - Shopping: جرير (Jarir), اكسترا (Extra), نون (Noon)
  - Utilities: الكهرباء (SEC / Electricity), اس تي سي (STC), موبايلي (Mobily), زين (Zain)
- Numerical support: Handles both Western digits (123) and Eastern Arabic numerals (١٢٣).

PRE-PURCHASE AFFORDABILITY SIMULATION:
If the user asks whether they can afford or buy an item, or asking if their budget permits a potential purchase:
Examples:
- "Can I buy a 1200 SAR iPad?" -> is_transaction: false, is_simulation: true, simulated_amount: 1200.0, simulated_item: "iPad", total_amount: 1200.0, category_code: "OPEX-SHOPPING"
- "أقدر اشتري ايباد بـ 1200 ريال؟" -> is_transaction: false, is_simulation: true, simulated_amount: 1200.0, simulated_item: "iPad", total_amount: 1200.0, category_code: "OPEX-SHOPPING"
- "يمديني اطلب عشا بـ 80 ريال؟" -> is_transaction: false, is_simulation: true, simulated_amount: 80.0, simulated_item: "عشا", total_amount: 80.0, category_code: "OPEX-DINING"

Expense Input examples:
"عبيت بنزين 91 بـ 60 ريال من ساسكو"
-> merchant: "SASCO", total_amount: 60.0, category_code: "OPEX-FUEL", spent_by: "me", items: [{"name": "بنزين 91", "quantity": 1, "price": 60.0}]

"تقضينا من بنده مقاضي البيت بـ 85 ريال حليب 15 وجبن 25 ودجاج 45"
-> merchant: "Panda", total_amount: 85.0, category_code: "OPEX-GROCERY", spent_by: "both", items: [{"name": "حليب", "quantity": 1, "price": 15.0}, {"name": "جبن", "quantity": 1, "price": 25.0}, {"name": "دجاج", "quantity": 1, "price": 45.0}]

"طلبنا من البيك بـ 54 ريال مسحب وبيبس دفعتها أنا"
-> merchant: "Albaik", total_amount: 54.0, category_code: "OPEX-DINING", spent_by: "me", items: [{"name": "مسحب وبيبس", "quantity": 1, "price": 54.0}]

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
  "spent_by": "me" | "partner" | "both",
  "items": [{"name": "...", "quantity": 1, "price": 0.0}],
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

    beneficiary = "me"
    if any(k in lower for k in ("for my wife", "for partner", "for husband", "for her", "for him", "لزوجتي", "لزوجي", "للشريك", "فستان زوجتي", "هدية")):
        beneficiary = "partner"
    elif any(k in lower for k in ("for me", "for myself", "bought myself", "لي لحالي", "شريت لنفسي", "قهوتي", "ملابسي", "دفعتها انا", "دفعتها أنا", "دفعته انا", "دفعته أنا")):
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

    return ParsedChatExpense(
        is_transaction=True,
        merchant=merchant,
        total_amount=total_amount,
        currency="SAR",
        category_code=cat_code,
        spent_by=spent_by,
        paid_by=paid_by,
        beneficiary=beneficiary,
        items=items,
        notes="Parsed via robust heuristic fallback",
    )


def parse_chat_expense(text: str) -> ParsedChatExpense:
    """Call Gemini to extract structured expense information from user chat text, with graceful fallback."""
    text = normalize_arabic_numbers(text)
    model = os.environ.get("LITELLM_MODEL", "gemini/gemini-2.0-flash")
    
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


def process_chat_transaction(
    household_id: str,
    message: str,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
    preview_only: bool = False,
    override_merchant: Optional[str] = None,
    override_spent_by: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Parse a chat message, perform duplicate checks/enrichment, update budget, and insert transaction.
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
        success = enrich_transaction_items(enrich_tx_id, items_dicts)
        return {
            "status": "enriched",
            "transaction_id": enrich_tx_id,
            "merchant": parsed.merchant,
            "amount": parsed.total_amount,
            "category_code": parsed.category_code,
            "items": items_dicts,
            "message": f"Successfully enriched existing transaction with {len(items_dicts)} items.",
        }

    merchant = (override_merchant or parsed.merchant).strip()
    spent_by = (override_spent_by or parsed.spent_by).lower()
    if spent_by not in ("me", "partner", "both"):
        spent_by = "both"

    # Match or fallback category
    codes = fetch_all_cost_control_codes()
    matched = match_category(merchant, codes)
    category_code = matched.code if matched else parsed.category_code

    # If preview only, return structured data asking user for confirmation
    if preview_only:
        return {
            "status": "pending_confirmation",
            "merchant": merchant,
            "amount": parsed.total_amount,
            "category_code": category_code,
            "spent_by": spent_by,
            "items": items_dicts,
            "original_message": message,
            "message": f"Found expense of SAR {parsed.total_amount:.2f} ({len(items_dicts)} items). Please confirm store name and who spent it:",
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

    now_iso = datetime.now(timezone.utc).isoformat()
    now_date = datetime.now(timezone.utc).date()

    # Check budget and reallocate if necessary
    budget = fetch_budget(household_id, category_code, now_date)
    is_reallocated = False
    reallocated_from_id = None

    if budget and budget.remaining_amount < parsed.total_amount:
        # Need reallocation
        deficit = parsed.total_amount - budget.remaining_amount
        flexible = fetch_flexible_budgets(household_id, now_date, exclude_code=category_code)
        if flexible and flexible[0].remaining_amount >= deficit:
            reallocate_budget(flexible[0].id, budget.id, deficit)
            is_reallocated = True
            reallocated_from_id = flexible[0].id

    # Format raw text for audit trail
    paid_by = getattr(parsed, "paid_by", "me")
    beneficiary = getattr(parsed, "beneficiary", "both")
    items_summary = ", ".join(f"{it.get('quantity', 1)}x {it.get('name')} ({it.get('price')} SAR)" for it in items_dicts)
    audit_text = (
        f"Chat: {message} | PaidBy: {paid_by} | Beneficiary: {beneficiary} | SpentBy: {spent_by} | Items: [{items_summary}]"
        if items_summary
        else f"Chat: {message} | PaidBy: {paid_by} | Beneficiary: {beneficiary} | SpentBy: {spent_by}"
    )

    # Insert transaction
    tx_id = insert_transaction(
        household_id=household_id,
        amount=parsed.total_amount,
        currency="SAR",
        merchant=merchant,
        category_code=category_code,
        timestamp=now_iso,
        raw_sms=audit_text,
        is_reallocated=is_reallocated,
        reallocated_from_budget_id=reallocated_from_id,
        source="chat",
        items=items_dicts,
        spent_by=spent_by,
        paid_by=paid_by,
        beneficiary=beneficiary,
    )

    # Attach items fallback if needed
    if items_dicts:
        enrich_transaction_items(tx_id, items_dicts)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": merchant,
        "amount": parsed.total_amount,
        "category_code": category_code,
        "spent_by": spent_by,
        "items": items_dicts,
        "is_reallocated": is_reallocated,
        "message": f"Recorded SAR {parsed.total_amount:.2f} at {merchant} under {category_code} ({spent_by.capitalize()}).",
    }
