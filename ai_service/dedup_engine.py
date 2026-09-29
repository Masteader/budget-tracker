"""
Deduplication and cross-channel matching engine.
Prevents double-counting when transactions arrive via SMS, Chat, or Receipt Scans.
Supports auto-enrichment of existing SMS transactions with line items.
"""

from __future__ import annotations
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List
from supabase_client import get_client

logger = logging.getLogger(__name__)

def find_duplicate_candidate(
    household_id: str,
    amount: float,
    merchant: Optional[str] = None,
    window_minutes: int = 1440,
) -> Optional[Dict[str, Any]]:
    """
    Search for a recent transaction for the household with the same amount (±0.05)
    within the last `window_minutes` (default 24 hours).
    If merchant is provided, checks for merchant keyword overlap to avoid false positives.
    """
    client = get_client()
    now = datetime.now(timezone.utc)
    cutoff = (now - timedelta(minutes=window_minutes)).isoformat()

    try:
        # Fetch transactions within time window
        response = (
            client.table("transactions")
            .select("*")
            .eq("household_id", household_id)
            .gte("timestamp", cutoff)
            .order("timestamp", desc=True)
            .limit(50)
            .execute()
        )
        rows = response.data or []
    except Exception as exc:
        logger.error("Failed to query recent transactions for dedup: %s", exc)
        return None

    merchant_clean = (merchant or "").lower().strip()

    for row in rows:
        row_amount = float(row.get("amount", 0.0))
        if abs(row_amount - amount) <= 0.05:
            row_merchant = (row.get("merchant") or "").lower().strip()
            
            # If no merchant specified on either
            if not merchant_clean or not row_merchant:
                logger.info("Found duplicate candidate by amount: tx_id=%s, amount=%.2f", row["id"], row_amount)
                return row
            
            # Check for name overlap
            if merchant_clean in row_merchant or row_merchant in merchant_clean:
                logger.info(
                    "Found duplicate candidate by amount & merchant (%s ~ %s): tx_id=%s",
                    merchant_clean, row_merchant, row["id"],
                )
                return row
                
    return None


def enrich_transaction_items(
    transaction_id: str,
    items: List[Dict[str, Any]],
    receipt_url: Optional[str] = None,
) -> bool:
    """
    Enrich an existing transaction (e.g. from SMS) with itemized breakdown and/or receipt URL.
    Does NOT increment budget spent_amount because the expense was already counted!
    """
    client = get_client()
    update_data: Dict[str, Any] = {}
    
    # Try updating items column
    if items:
        update_data["items"] = items
    if receipt_url:
        update_data["receipt_url"] = receipt_url

    if not update_data:
        return True

    try:
        client.table("transactions").update(update_data).eq("id", transaction_id).execute()
        logger.info("Enriched transaction %s with %d items.", transaction_id, len(items))
        return True
    except Exception as exc:
        # If columns don't exist yet, append items into raw_sms as audit trail
        logger.warning("Failed to update items column directly (%s), trying raw_sms fallback.", exc)
        try:
            current = client.table("transactions").select("raw_sms").eq("id", transaction_id).single().execute()
            existing_sms = (current.data or {}).get("raw_sms") or ""
            items_str = ", ".join(f"{it.get('quantity', 1)}x {it.get('name')} (SAR {it.get('price', 0)})" for it in items)
            enriched_sms = f"{existing_sms} | Items: [{items_str}]"
            client.table("transactions").update({"raw_sms": enriched_sms}).eq("id", transaction_id).execute()
            return True
        except Exception as fallback_exc:
            logger.error("Failed fallback enrichment: %s", fallback_exc)
            return False
