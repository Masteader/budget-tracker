"""
Multimodal receipt and invoice scanner using Gemini 3.5/3.8 Flash Vision.
Supports:
1. Multi-photo capture for long receipts (60+ items across multiple shots)
2. Saudi ZATCA e-invoicing Base64 TLV QR code decoding
3. Item-by-item extraction without truncation
"""

from __future__ import annotations
import base64
import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any

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


def decode_zatca_tlv(b64_str: str) -> Optional[Dict[str, Any]]:
    """
    Decodes Saudi ZATCA e-invoicing Phase 1 & 2 Base64 TLV QR code.
    Tag 1: Seller Name
    Tag 2: VAT Registration Number (15 digits)
    Tag 3: Invoice Timestamp (ISO)
    Tag 4: Total Amount (with VAT)
    Tag 5: VAT Amount
    """
    if not b64_str or len(b64_str) < 10:
        return None
    try:
        raw = base64.b64decode(b64_str.strip())
        tags: Dict[int, str] = {}
        idx = 0
        while idx < len(raw):
            tag = raw[idx]
            if idx + 1 >= len(raw):
                break
            length = raw[idx + 1]
            val = raw[idx + 2 : idx + 2 + length].decode("utf-8", errors="replace")
            tags[tag] = val
            idx += 2 + length

        seller = tags.get(1)
        vat_no = tags.get(2)
        ts = tags.get(3)
        total = float(tags.get(4, 0)) if tags.get(4) else None
        vat_amt = float(tags.get(5, 0)) if tags.get(5) else None

        if seller and total:
            return {
                "seller_name": seller,
                "vat_number": vat_no,
                "timestamp": ts,
                "total_amount": total,
                "vat_amount": vat_amt,
            }
    except Exception as e:
        logger.debug("ZATCA TLV decode failed: %s", e)
    return None


RECEIPT_PROMPT = """You are an expert financial receipt & invoice analyzer for Saudi Arabia.
Inspect the attached receipt/invoice photo(s) carefully.
NOTE: If there are multiple photos, they represent sequential parts of a single LONG receipt (e.g. top, middle, bottom of a 60+ item grocery receipt).
When multiple photos are provided, sequential photos may have overlapping items where the shots meet.
You MUST stitch the receipt segments seamlessly and DEDUPLICATE overlapping items so that each physical item appears exactly once.
Cross-check that the sum of item prices matches the printed invoice total.

Analyze ALL photos together and extract:
1. Merchant name (store, supermarket, restaurant, or company name)
2. Total amount (including VAT)
3. VAT amount (15% Saudi VAT if displayed)
4. Invoice date and time
5. Complete itemized breakdown:
   - Extract EVERY SINGLE item item-by-item from start to finish.
   - Do NOT abbreviate or truncate the list. If there are 60 items, list all 60 items.
   - For each item, provide name, quantity, and total item price in SAR.
6. Category code (choose best match):
   - OPEX-GROCERY (supermarket, food, grocery)
   - OPEX-DINING (restaurant, cafe, bakery)
   - OPEX-FUEL (petrol, transport)
   - OPEX-UTILITIES (bills, telecom)
   - OPEX-SHOPPING (retail, electronics, clothes)
   - OPEX-ENTERTAINMENT (movies, games)
   - OPEX-HEALTH (pharmacy, hospital)
   - OPEX-MISC (other)
7. If a ZATCA QR code is visible on any photo, read its encoded text or base64 if possible.

Return STRICTLY a JSON object conforming to:
{
  "merchant": "Store Name",
  "total_amount": 0.0,
  "vat_amount": 0.0,
  "currency": "SAR",
  "date": "YYYY-MM-DD HH:MM:SS or null",
  "category_code": "OPEX-...",
  "zatca_qr_raw": "base64 string if found or null",
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

def parse_receipt_images(
    images_base64: List[str],
    qr_code_raw: Optional[str] = None,
) -> Dict[str, Any]:
    """Call Gemini multimodal vision API with 1 or more receipt images."""
    model = os.environ.get("LITELLM_MODEL", "gemini/gemini-3.5-flash-lite")
    
    content: List[Dict[str, Any]] = [
        {"type": "text", "text": RECEIPT_PROMPT}
    ]

    for img in images_base64:
        clean_img = img.split(",", 1)[1] if "," in img else img
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{clean_img}"}
        })

    response = litellm.completion(
        model=model,
        messages=[{"role": "user", "content": content}],
        response_format={"type": "json_object"},
        temperature=1.0,
    )

    result_json = response.choices[0].message.content
    parsed: Dict[str, Any] = json.loads(result_json)

    # Check for ZATCA QR passed from client or extracted by Gemini
    qr_to_check = qr_code_raw or parsed.get("zatca_qr_raw")
    if qr_to_check:
        zatca = decode_zatca_tlv(qr_to_check)
        if zatca:
            logger.info("ZATCA QR decoded successfully: %s", zatca)
            parsed["zatca_verified"] = zatca
            if zatca.get("seller_name"):
                parsed["merchant"] = zatca["seller_name"]
            if zatca.get("total_amount"):
                parsed["total_amount"] = zatca["total_amount"]
            if zatca.get("vat_amount"):
                parsed["vat_amount"] = zatca["vat_amount"]
            if zatca.get("timestamp"):
                parsed["date"] = zatca["timestamp"]

    return parsed


def parse_receipt_image(
    image_base64: str,
    qr_code_raw: Optional[str] = None,
) -> Dict[str, Any]:
    """Single image wrapper for backwards compatibility."""
    return parse_receipt_images([image_base64], qr_code_raw=qr_code_raw)


def process_receipt_scan(
    household_id: str,
    images_base64: Optional[List[str]] = None,
    qr_code_raw: Optional[str] = None,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Process scanned receipt image(s) or ZATCA QR code:
    1. Parse via Gemini Vision across multiple images if photos provided
    2. Decode ZATCA QR code if provided (or if photos omitted)
    3. Check for duplicate against recent SMS/Chat entries
    4. Auto-enrich or insert transaction
    """
    images_base64 = images_base64 or []

    if images_base64:
        try:
            if len(images_base64) == 1:
                parsed = parse_receipt_image(images_base64[0], qr_code_raw=qr_code_raw)
            else:
                parsed = parse_receipt_images(images_base64, qr_code_raw=qr_code_raw)
        except Exception as exc:
            logger.error("Failed to parse receipt image(s): %s", exc)
            return {
                "status": "error",
                "message": f"Failed to analyze receipt: {str(exc)}",
            }
    elif qr_code_raw:
        zatca = decode_zatca_tlv(qr_code_raw)
        if not zatca:
            return {
                "status": "error",
                "message": "Could not decode ZATCA QR code. Please ensure it is a valid Base64 TLV code.",
            }
        seller = zatca.get("seller_name") or "VAT Tax Invoice"
        total_val = float(zatca.get("total_amount") or 0.0)
        vat_val = float(zatca.get("vat_amount") or 0.0)
        if vat_val == 0.0 and total_val > 0:
            vat_val = round(total_val * 0.15 / 1.15, 2)

        parsed = {
            "merchant": seller,
            "total_amount": total_val,
            "vat_amount": vat_val,
            "category_code": "OPEX-GROCERY",
            "items": [
                {
                    "name": f"Tax Invoice Total (15% VAT {vat_val:.2f} SAR)",
                    "quantity": 1.0,
                    "price": total_val,
                }
            ],
            "zatca_verified": zatca,
            "date": zatca.get("timestamp"),
        }
    else:
        return {
            "status": "error",
            "message": "Please provide receipt image(s) or a ZATCA QR code.",
        }

    merchant = parsed.get("merchant") or "Scanned Merchant"
    total_amount = float(parsed.get("total_amount") or 0.0)
    category_code = parsed.get("category_code") or "OPEX-MISC"
    raw_items = parsed.get("items") or []

    # Clean items formatting
    raw_formatted: List[Dict[str, Any]] = []
    for it in raw_items:
        if isinstance(it, dict):
            raw_formatted.append({
                "name": str(it.get("name", "Item")),
                "quantity": float(it.get("quantity", 1.0)),
                "price": float(it.get("price", 0.0)),
            })

    # Stitch & deduplicate overlapping items from multi-page shots
    items: List[Dict[str, Any]] = []
    seen_item_keys = set()
    for it in raw_formatted:
        clean_name = it["name"].strip().lower()
        key = (clean_name, round(it["price"], 2), round(it["quantity"], 2))
        if key in seen_item_keys:
            continue
        seen_item_keys.add(key)
        items.append(it)

    items_sum = sum(it["price"] for it in items)
    if total_amount <= 0 and items:
        # Sum items if total wasn't explicitly detected
        total_amount = round(items_sum, 2)
    elif total_amount > 0 and items:
        # Subtotal cross-check
        if abs(items_sum - total_amount) > 1.0:
            logger.info("Subtotal cross-check note: item sum is %.2f vs total %.2f", items_sum, total_amount)

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
            "zatca_verified": parsed.get("zatca_verified"),
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
                    "zatca_verified": parsed.get("zatca_verified"),
                },
                "items": items,
                "merchant": merchant,
                "amount": total_amount,
                "category_code": category_code,
                "message": (
                    f"A transaction of SAR {candidate.get('amount')} at '{candidate.get('merchant')}' "
                    f"was already recorded. Would you like to attach these {len(items)} items or log as separate expense?"
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

    items_summary = ", ".join(f"{it['quantity']}x {it['name']} ({it['price']} SAR)" for it in items[:10])
    if len(items) > 10:
        items_summary += f" ...and {len(items) - 10} more items"
    audit_text = f"Receipt Scan: {merchant} ({len(items)} items) | Items: [{items_summary}]"

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
    )


    if items:
        enrich_transaction_items(tx_id, items)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": merchant,
        "amount": total_amount,
        "category_code": category_code,
        "items": items,
        "zatca_verified": parsed.get("zatca_verified"),
        "is_reallocated": is_reallocated,
        "message": f"Recorded SAR {total_amount:.2f} ({len(items)} items) from scanned receipt ({merchant}).",
    }
