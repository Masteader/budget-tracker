"""
Multimodal receipt and invoice scanner using Gemini 3.5 Flash Vision.
Parses camera receipts (paper, thermal, ZATCA tax invoices) into line-item transactions.
"""

from __future__ import annotations
import base64
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

RECEIPT_PROMPT = """You are an expert financial receipt & invoice analyzer for Saudi Arabia.
Inspect the attached receipt/invoice image carefully (it may be in Arabic, English, or bilingual).
Extract all financial transaction details with complete itemized breakdown.

Categories available:
- OPEX-GROCERY: Supermarkets, groceries (Tamimi, Danube, Panda, Carrefour, Lulu, Othaim)
- OPEX-DINING: Restaurants, cafes, coffee shops, bakeries (Dunkin, Starbucks, Albaik, McDonald's)
- OPEX-FUEL: Gas stations, petrol, transport, car wash (Aramco, Sahel, Petromin)
- OPEX-UTILITIES: Electricity, water, telecoms, bills
- OPEX-SHOPPING: Retail, clothing, electronics, books (Jarir, Extra, Noon)
- OPEX-ENTERTAINMENT: Movies, cinemas, recreation
- OPEX-HEALTH: Pharmacies, hospitals, clinics, medicine (Nahdi, Al Dawaa)
- OPEX-MISC: Anything else

Return STRICTLY a JSON object conforming to:
{
  "merchant": "Store Name",
  "total_amount": 0.0,
  "vat_amount": 0.0,
  "currency": "SAR",
  "date": "YYYY-MM-DD HH:MM:SS or null",
  "category_code": "OPEX-...",
  "items": [
    {
      "name": "Item Description",
      "quantity": 1.0,
      "price": 0.0
    }
  ],
  "confidence": "high | medium | low"
}
"""

def parse_receipt_image(image_base64: str) -> Dict[str, Any]:
    """Call Gemini multimodal vision API with the base64 receipt image."""
    model = os.environ.get("LITELLM_MODEL", "gemini/gemini-3.8-flash")
    
    # Clean base64 if it has prefix
    if "," in image_base64:
        image_base64 = image_base64.split(",", 1)[1]

    data_url = f"data:image/jpeg;base64,{image_base64}"

    response = litellm.completion(
        model=model,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": RECEIPT_PROMPT},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
        response_format={"type": "json_object"},
        temperature=1.0,
    )

    content = response.choices[0].message.content
    return json.loads(content)


def process_receipt_scan(
    household_id: str,
    image_base64: str,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Process scanned receipt image:
    1. Parse via Gemini Vision
    2. Check for duplicate against recent SMS/Chat entries
    3. Auto-enrich or insert transaction
    """
    try:
        parsed = parse_receipt_image(image_base64)
    except Exception as exc:
        logger.error("Failed to parse receipt image: %s", exc)
        return {
            "status": "error",
            "message": f"Failed to analyze receipt image: {str(exc)}",
        }

    merchant = parsed.get("merchant") or "Scanned Merchant"
    total_amount = float(parsed.get("total_amount") or 0.0)
    category_code = parsed.get("category_code") or "OPEX-MISC"
    items = parsed.get("items") or []

    if total_amount <= 0:
        return {
            "status": "error",
            "message": "Could not detect a valid total amount on the scanned receipt.",
            "parsed_data": parsed,
        }

    # Explicit enrichment
    if enrich_tx_id:
        success = enrich_transaction_items(enrich_tx_id, items)
        return {
            "status": "enriched",
            "transaction_id": enrich_tx_id,
            "merchant": merchant,
            "amount": total_amount,
            "category_code": category_code,
            "items": items,
            "message": f"Successfully attached {len(items)} scanned receipt items to existing transaction.",
        }

    # Deduplication check against recent SMS transactions
    if not allow_duplicate:
        candidate = find_duplicate_candidate(household_id, total_amount, merchant)
        if candidate:
            logger.info("Duplicate candidate found for scanned receipt: %s", candidate["id"])
            return {
                "status": "duplicate_candidate",
                "candidate_transaction_id": candidate["id"],
                "candidate_merchant": candidate.get("merchant"),
                "candidate_amount": candidate.get("amount"),
                "candidate_timestamp": candidate.get("timestamp"),
                "parsed_data": {
                    "merchant": merchant,
                    "amount": total_amount,
                    "category_code": category_code,
                    "items": items,
                },
                "message": (
                    f"A transaction of SAR {candidate.get('amount')} at '{candidate.get('merchant')}' "
                    f"was already recorded. Would you like to attach these receipt items or log as separate expense?"
                ),
            }

    # Match category with keyword taxonomy
    codes = fetch_all_cost_control_codes()
    matched = match_category(merchant, codes)
    if matched:
        category_code = matched.code

    now_iso = datetime.now(timezone.utc).isoformat()
    now_date = datetime.now(timezone.utc).date()

    # Check budget
    budget = fetch_budget(household_id, category_code, now_date)
    is_reallocated = False
    reallocated_from_id = None

    if budget and budget.remaining_amount < total_amount:
        deficit = total_amount - budget.remaining_amount
        flexible = fetch_flexible_budgets(household_id, now_date, exclude_code=category_code)
        if flexible and flexible[0].remaining_amount >= deficit:
            reallocate_budget(flexible[0].id, budget.id, deficit)
            is_reallocated = True
            reallocated_from_id = flexible[0].id

    spent_by = "both" if any(k in category_code for k in ("GROCERY", "UTILITIES", "MISC")) else "me"
    items_summary = ", ".join(f"{it.get('quantity', 1)}x {it.get('name')} ({it.get('price')} SAR)" for it in items)
    audit_text = f"Receipt Scan: {merchant} | SpentBy: {spent_by} | Items: [{items_summary}]" if items_summary else f"Receipt Scan: {merchant} | SpentBy: {spent_by}"

    tx_id = insert_transaction(
        household_id=household_id,
        amount=total_amount,
        currency="SAR",
        merchant=merchant,
        category_code=category_code,
        timestamp=now_iso,
        raw_sms=audit_text,
        is_reallocated=is_reallocated,
        reallocated_from_budget_id=reallocated_from_id,
        source="receipt_scan",
        items=items,
        spent_by=spent_by,
    )

    if items:
        enrich_transaction_items(tx_id, items)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": merchant,
        "amount": total_amount,
        "category_code": category_code,
        "spent_by": spent_by,
        "items": items,
        "is_reallocated": is_reallocated,
        "message": f"Recorded SAR {total_amount:.2f} from scanned receipt ({merchant}).",
    }
