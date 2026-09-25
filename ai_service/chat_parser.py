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
    is_transaction: bool = Field(True, description="Whether the text represents a financial expense")
    merchant: str = Field("Unknown Merchant", description="Store or merchant name")
    total_amount: float = Field(..., description="Total amount in SAR")
    currency: str = "SAR"
    category_code: str = Field("OPEX-MISC", description="Category code like OPEX-DINING, OPEX-GROCERY, etc.")
    items: List[ChatLineItem] = Field(default_factory=list, description="Itemized breakdown")
    notes: Optional[str] = None

SYSTEM_PROMPT = """You are an intelligent financial assistant for a Saudi budget tracker.
Parse natural language expense logs into structured financial transactions with line-item breakdowns.

Categories available:
- OPEX-GROCERY: Supermarkets, groceries, food stores (Tamimi, Danube, Panda, Carrefour, Lulu, Othaim)
- OPEX-DINING: Restaurants, cafes, fast food, coffee shops, bakeries, delivery (Dunkin, Starbucks, Albaik, McDonald's, Jahez, Hungerstation)
- OPEX-FUEL: Fuel stations, gas, transport, taxi, Uber, Careem, trains (Aramco, Sahel, Uber, Careem)
- OPEX-UTILITIES: Electricity, water, internet, mobile bills (STC, Mobily, Zain, SEC)
- OPEX-SHOPPING: Retail, clothing, electronics, books (Jarir, Extra, Noon, Amazon)
- OPEX-ENTERTAINMENT: Movies, cinemas, streaming, gaming, concerts (Muvi, Vox, Netflix, PlayStation, Shahid)
- OPEX-HEALTH: Pharmacies, clinics, doctors, hospitals, medicine (Nahdi, Al Dawaa, Habib)
- OPEX-MISC: Anything else that doesn't fit above.

Input examples:
"merchant dunkin and i spent 19 sar total, 16 ice latte and 3 donut"
-> merchant: "Dunkin'", total_amount: 19.0, category_code: "OPEX-DINING", items: [{"name": "Ice Latte", "quantity": 1, "price": 16.0}, {"name": "Donut", "quantity": 1, "price": 3.0}]

"Bought groceries from Danube for 145 SAR: 2 milk 20 sar, bread 5 sar, chicken 120 sar"
-> merchant: "Danube", total_amount: 145.0, category_code: "OPEX-GROCERY", items: [{"name": "Milk", "quantity": 2, "price": 20.0}, {"name": "Bread", "quantity": 1, "price": 5.0}, {"name": "Chicken", "quantity": 1, "price": 120.0}]

Return STRICTLY valid JSON conforming to:
{
  "is_transaction": true,
  "merchant": "...",
  "total_amount": 0.0,
  "currency": "SAR",
  "category_code": "...",
  "items": [{"name": "...", "quantity": 1, "price": 0.0}],
  "notes": "..."
}
"""

def parse_chat_expense(text: str) -> ParsedChatExpense:
    """Call Gemini to extract structured expense information from user chat text."""
    model = os.environ.get("LITELLM_MODEL", "gemini/gemini-3.5-flash-lite")
    
    response = litellm.completion(
        model=model,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        response_format={"type": "json_object"},
        temperature=1.0,
    )
    
    content = response.choices[0].message.content
    data = json.loads(content)
    return ParsedChatExpense(**data)


def process_chat_transaction(
    household_id: str,
    message: str,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Parse a chat message, perform duplicate checks/enrichment, update budget, and insert transaction.
    """
    parsed = parse_chat_expense(message)
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

    # Match or fallback category
    codes = fetch_all_cost_control_codes()
    matched = match_category(parsed.merchant, codes)
    category_code = matched.code if matched else parsed.category_code

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
    audit_text = f"Chat: {message} | Items: [{items_summary}]" if items_summary else f"Chat: {message}"

    # Insert transaction
    tx_id = insert_transaction(
        household_id=household_id,
        amount=parsed.total_amount,
        currency="SAR",
        merchant=parsed.merchant,
        category_code=category_code,
        timestamp=now_iso,
        raw_sms=audit_text,
        is_reallocated=is_reallocated,
        reallocated_from_budget_id=reallocated_from_id,
        source="chat",
        items=items_dicts,
    )

    # Attach items fallback if needed
    if items_dicts:
        enrich_transaction_items(tx_id, items_dicts)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": parsed.merchant,
        "amount": parsed.total_amount,
        "category_code": category_code,
        "items": items_dicts,
        "is_reallocated": is_reallocated,
        "message": f"Recorded SAR {parsed.total_amount:.2f} at {parsed.merchant} under {category_code}.",
    }
