"""
Deduplication and cross-channel matching engine.
Prevents double-counting when transactions arrive via SMS, Chat, or Receipt Scans.
Supports auto-enrichment of existing SMS transactions with line items.
"""

import hashlib
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List
from supabase_client import get_client

logger = logging.getLogger(__name__)

def compute_zatca_fingerprint(
    vat_number: Optional[str],
    invoice_timestamp: Optional[str],
    total_amount: float,
) -> str:
    """
    Deterministic SHA-256 fingerprint for a Saudi ZATCA e-invoicing Phase 1/2 QR code.
    Combines 15-digit VAT number, invoice timestamp, and total amount.
    """
    clean_vat = (vat_number or "").strip()
    clean_ts = (invoice_timestamp or "").strip()
    clean_total = f"{float(total_amount):.2f}"
    raw = f"zatca:{clean_vat}:{clean_ts}:{clean_total}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()

def find_duplicate_candidate(
    household_id: str,
    amount: float,
    merchant: Optional[str] = None,
    window_minutes: int = 1440,
    zatca_fingerprint: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    """
    Search for an existing duplicate transaction:
    1. If zatca_fingerprint is provided: exact match on dedup_fingerprint across all time.
    2. Fuzzy match: Search recent transactions for the household with the same amount (±0.05)
       within the last `window_minutes` (default 24 hours), matching merchant keyword overlap.
    """
    client = get_client()

    # Priority 1: Exact ZATCA fingerprint match
    if zatca_fingerprint:
        try:
            response = (
                client.table("transactions")
                .select("*")
                .eq("household_id", household_id)
                .eq("dedup_fingerprint", zatca_fingerprint)
                .limit(1)
                .execute()
            )
            if response.data:
                candidate = response.data[0]
                logger.info("Found exact ZATCA duplicate candidate: tx_id=%s", candidate["id"])
                return candidate
        except Exception as exc:
            logger.warning("Failed querying dedup_fingerprint: %s", exc)

    # Priority 2: Recent transactions by amount & merchant
    try:
        response = (
            client.table("transactions")
            .select("*")
            .eq("household_id", household_id)
            .order("created_at", desc=True)
            .limit(50)
            .execute()
        )
        rows = response.data or []
    except Exception as exc:
        logger.error("Failed to query recent transactions for dedup: %s", exc)
        return None

    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(minutes=window_minutes) if window_minutes else None
    merchant_clean = (merchant or "").lower().strip()

    for row in rows:
        # Check time window if cutoff is specified
        if cutoff:
            row_dt = None
            for dt_field in ("timestamp", "created_at"):
                raw_val = row.get(dt_field)
                if raw_val:
                    try:
                        row_dt = datetime.fromisoformat(str(raw_val).replace("Z", "+00:00"))
                        break
                    except Exception:
                        pass

            if row_dt and row_dt < cutoff:
                continue

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
