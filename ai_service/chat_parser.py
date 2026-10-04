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
    items: List[ChatLineItem] = Field(default_factory=list, description="Itemized breakdown")
    notes: Optional[str] = None

SYSTEM_PROMPT = """You are an intelligent financial assistant for a Saudi budget tracker.
Parse natural language expense logs into structured financial transactions with line-item breakdowns, OR detect pre-purchase affordability simulation questions.

Categories available:
- OPEX-GROCERY: Supermarkets, groceries, food stores (Tamimi, Danube, Panda, Carrefour, Lulu, Othaim)
- OPEX-DINING: Restaurants, cafes, fast food, coffee shops, bakeries, delivery (Dunkin, Starbucks, Albaik, McDonald's, Jahez, Hungerstation)
- OPEX-FUEL: Fuel stations, gas, transport, taxi, Uber, Careem, trains (Aramco, Sahel, Uber, Careem)
- OPEX-UTILITIES: Electricity, water, internet, mobile bills (STC, Mobily, Zain, SEC)
- OPEX-SHOPPING: Retail, clothing, electronics, books, iPad, gadgets (Jarir, Extra, Noon, Amazon, Apple)
- OPEX-ENTERTAINMENT: Movies, cinemas, streaming, gaming, concerts (Muvi, Vox, Netflix, PlayStation, Shahid)
- OPEX-HEALTH: Pharmacies, clinics, doctors, hospitals, medicine (Nahdi, Al Dawaa, Habib)
- OPEX-MISC: Anything else that doesn't fit above (house cleaning, maintenance, home services).

Attribution ("spent_by"):
- "me": Personal expenses or when the user says "I spent", "my coffee", personal items.
- "partner": When the user mentions their partner/wife/husband bought or spent it (e.g., "my partner bought", "wife spent", "partner got").
- "both": Shared household expenses (e.g., groceries, supermarket, house cleaning, maid, utilities, home maintenance, or when user mentions "we spent", "for both of us", "shared", "house"). If it's a household category like groceries or house cleaning and unspecified, default to "both".

PRE-PURCHASE AFFORDABILITY SIMULATION:
If the user asks whether they can afford or buy an item, or asking if their budget permits a potential purchase:
Examples:
- "Can I buy a 1200 SAR iPad?" -> is_transaction: false, is_simulation: true, simulated_amount: 1200.0, simulated_item: "iPad", total_amount: 1200.0, category_code: "OPEX-SHOPPING"
- "أقدر اشتري ايباد بـ 1200 ريال؟" -> is_transaction: false, is_simulation: true, simulated_amount: 1200.0, simulated_item: "iPad", total_amount: 1200.0, category_code: "OPEX-SHOPPING"
- "Can I afford dinner for 350 SAR?" -> is_transaction: false, is_simulation: true, simulated_amount: 350.0, simulated_item: "Dinner", total_amount: 350.0, category_code: "OPEX-DINING"
- "هل ميزانيتي تسمح اشتري لابتوب بـ 4500 ريال؟" -> is_transaction: false, is_simulation: true, simulated_amount: 4500.0, simulated_item: "Laptop", total_amount: 4500.0, category_code: "OPEX-SHOPPING"

Expense Input examples:
"merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut"
-> merchant: "Dunkin'", total_amount: 19.0, category_code: "OPEX-DINING", spent_by: "me", items: [{"name": "Ice Latte", "quantity": 1, "price": 16.0}, {"name": "Donut", "quantity": 1, "price": 3.0}]

"شريت من دانكن 19 ريال ايس لاتيه 16 ودونات 3"
-> merchant: "Dunkin'", total_amount: 19.0, category_code: "OPEX-DINING", spent_by: "me", items: [{"name": "Ice Latte", "quantity": 1, "price": 16.0}, {"name": "Donut", "quantity": 1, "price": 3.0}]

"فاتورة بنده 85 ريال: حليب بـ 15 وجبنة بـ 25 ودجاج بـ 45"
-> merchant: "Panda", total_amount: 85.0, category_code: "OPEX-GROCERY", spent_by: "both", items: [{"name": "Milk", "quantity": 1, "price": 15.0}, {"name": "Cheese", "quantity": 1, "price": 25.0}, {"name": "Chicken", "quantity": 1, "price": 45.0}]

"house cleaning 150 sar"
-> merchant: "House Cleaning", total_amount: 150.0, category_code: "OPEX-MISC", spent_by: "both", items: [{"name": "House Cleaning", "quantity": 1, "price": 150.0}]

"partner bought perfume 250 sar"
-> merchant: "Perfume Shop", total_amount: 250.0, category_code: "OPEX-SHOPPING", spent_by: "partner", items: [{"name": "Perfume", "quantity": 1, "price": 250.0}]

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
    raw = text.strip()
    lower = raw.lower()

    # Affordability simulation check (e.g. "Can I buy a 1200 SAR iPad?", "أقدر اشتري ايباد بـ 1200 ريال؟")
    sim_keywords = [
        "can i afford", "can i buy", "could i buy", "should i buy", "can we afford",
        "أقدر اشتري", "اقدر اشتري", "هل اقدر", "هل أقدر", "يمديني اشتري",
        "ينفع اشتري", "ميزانية ل", "ميزانيه ل", "هل في ميزانية", "هل تكفي الميزانية",
        "أشتري ولا", "اشتري ولا", "اقدر اجيب", "أقدر أجيب"
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
        if any(w in cleaned_item.lower() for w in ("dinner", "lunch", "coffee", "restaurant", "مطعم", "عشاء", "غداء", "قهوة", "food")):
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

    # Attribution: me, partner, or both
    spent_by = "both"
    if any(k in lower for k in ("partner", "wife", "husband", "spouse")):
        spent_by = "partner"
    elif any(k in lower for k in ("cleaning", "grocery", "groceries", "supermarket", "utilities", "bills", "both", "we ", "house ", "home ")):
        spent_by = "both"
    elif any(k in lower for k in ("i spent", "me", "my ", "bought myself")):
        spent_by = "me"
    else:
        spent_by = "me"

    # Merchant extraction
    merchant = "Unknown Merchant"
    known_merchants = [
        "Dunkin", "Starbucks", "Albaik", "McDonald's", "Danube", "Tamimi", "Panda", "Carrefour",
        "Nahdi", "Al Dawaa", "Jarir", "Extra", "Noon", "Amazon", "Aramco", "Sahel", "Uber",
        "Careem", "STC", "Mobily", "Zain", "House Cleaning",
    ]
    for km in known_merchants:
        if km.lower() in lower:
            merchant = km
            break
    if merchant == "Unknown Merchant":
        m_match = re.search(r'(?:merchant|at|from)\s+([A-Za-z0-9\'&]+)', raw, re.IGNORECASE)
        if m_match:
            merchant = m_match.group(1).capitalize()
        else:
            words = raw.split()
            if words:
                merchant = words[0].capitalize()

    # Total amount extraction
    total_amount = 0.0
    tot_match = re.search(r'(?:spent|total|for)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:sar|riyal|rs)?\s*(?:total)?', raw, re.IGNORECASE)
    if tot_match:
        try:
            total_amount = float(tot_match.group(1))
        except ValueError:
            total_amount = 0.0

    # Line items breakdown
    items: List[ChatLineItem] = []
    # Pattern: <price> <name> (e.g. "16 ice latte and 3 donut")
    item_matches = list(re.finditer(r'(\d+(?:\.\d+)?)\s*(?:sar)?\s+([a-zA-Z\s]+?)(?:and|,|$)', raw, re.IGNORECASE))
    for m in item_matches:
        try:
            val = float(m.group(1))
            name = m.group(2).strip()
            if name.lower() in (merchant.lower(), "total", "sar", "spent") or "total" in name.lower():
                continue
            if val > 0 and len(name) > 1:
                items.append(ChatLineItem(name=name.title(), quantity=1.0, price=val))
        except ValueError:
            pass

    if not items:
        # Fallback Pattern: <name> <price> (e.g. "ice latte 16 sar, donut 3")
        item_matches_b = list(re.finditer(r'([a-zA-Z\s]+?)\s+(\d+(?:\.\d+)?)\s*(?:sar|riyal)?(?:and|,|$)', raw, re.IGNORECASE))
        for m in item_matches_b:
            try:
                name = m.group(1).strip()
                val = float(m.group(2))
                if name.lower() in ("spent", "total", "merchant", "at", "for"):
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
    cat_code = "OPEX-MISC"
    if any(k in lower or k in merchant.lower() for k in ("dunkin", "coffee", "latte", "starbucks", "cafe", "dining", "restaurant", "burger", "albaik", "mcdonald")):
        cat_code = "OPEX-DINING"
    elif any(k in lower or k in merchant.lower() for k in ("danube", "tamimi", "panda", "carrefour", "grocery", "groceries", "supermarket", "milk", "bread", "chicken")):
        cat_code = "OPEX-GROCERY"
    elif any(k in lower or k in merchant.lower() for k in ("fuel", "gas", "petrol", "aramco", "sahel", "uber", "careem", "taxi")):
        cat_code = "OPEX-FUEL"
    elif any(k in lower or k in merchant.lower() for k in ("stc", "mobily", "zain", "electric", "water", "bill", "utilities")):
        cat_code = "OPEX-UTILITIES"
    elif any(k in lower or k in merchant.lower() for k in ("jarir", "extra", "amazon", "noon", "shopping", "clothes", "perfume")):
        cat_code = "OPEX-SHOPPING"
    elif any(k in lower or k in merchant.lower() for k in ("nahdi", "pharmacy", "medicine", "doctor", "clinic", "hospital")):
        cat_code = "OPEX-HEALTH"

    return ParsedChatExpense(
        is_transaction=True,
        merchant=merchant,
        total_amount=total_amount,
        currency="SAR",
        category_code=cat_code,
        spent_by=spent_by,
        items=items,
        notes="Parsed via robust heuristic fallback",
    )


def parse_chat_expense(text: str) -> ParsedChatExpense:
    """Call Gemini to extract structured expense information from user chat text, with graceful fallback."""
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
    items_summary = ", ".join(f"{it.get('quantity', 1)}x {it.get('name')} ({it.get('price')} SAR)" for it in items_dicts)
    audit_text = f"Chat: {message} | SpentBy: {spent_by} | Items: [{items_summary}]" if items_summary else f"Chat: {message} | SpentBy: {spent_by}"

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
