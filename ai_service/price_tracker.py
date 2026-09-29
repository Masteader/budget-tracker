"""
Grocery Price History & Inflation Tracker.
Aggregates line items across receipts, voice entries, and chat to track price trends, store comparisons, and inflation rates.
"""

from __future__ import annotations
import logging
import re
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
from collections import defaultdict

from supabase_client import get_client

logger = logging.getLogger(__name__)

def _normalize_item_name(raw_name: str) -> str:
    """Normalize item name for aggregation across languages and stores."""
    cleaned = raw_name.lower().strip()
    mapping = {
        "milk": ["حليب", "لبن", "almarai milk", "alsafi milk", "fresh milk"],
        "chicken": ["دجاج", "صدور دجاج", "sadia chicken", "alyoum chicken", "chicken breast"],
        "bread": ["خبز", "صامولي", "toast", "pita", "lusine bread"],
        "eggs": ["بيض", "طبق بيض", "fresh eggs"],
        "cheese": ["جبنة", "جبن", "cheddar", "mozzarella", "cream cheese", "kiri"],
        "rice": ["رز", "ارز", "basmati rice", "alwalimah"],
        "oil": ["زيت", "زيت نباتي", "cooking oil", "sunflower oil", "olive oil"],
        "water": ["مياه", "ماء", "bottled water", "berain", "nova"],
        "coffee": ["قهوة", "لاتيه", "بن", "latte", "ice latte", "cappuccino", "espresso"],
        "donut": ["دونات", "donuts"],
        "tea": ["شاي", "lipton", "tea bag"],
    }
    for standard, synonyms in mapping.items():
        if standard in cleaned or any(syn in cleaned for syn in synonyms):
            return standard.capitalize()
    
    return re.sub(r'[^a-zA-Z0-9\u0600-\u06FF\s]', '', raw_name).strip().capitalize()


def get_grocery_price_history(household_id: str, item_filter: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Returns historical price entries for items purchased by the household,
    including store prices and inflation percentages.
    """
    client = get_client()

    try:
        response = (
            client.table("transactions")
            .select("id, merchant, category_code, timestamp, items")
            .eq("household_id", household_id)
            .not_.is_("items", "null")
            .order("timestamp", desc=False)
            .execute()
        )
        txs = response.data or []
    except Exception as exc:
        logger.error("Failed to query transactions for price history: %s", exc)
        txs = []

    history_by_item: Dict[str, List[Dict[str, Any]]] = defaultdict(list)

    for tx in txs:
        merchant = tx.get("merchant") or "Store"
        ts = tx.get("timestamp") or datetime.now(timezone.utc).isoformat()
        items = tx.get("items") or []
        if isinstance(items, list):
            for it in items:
                if not isinstance(it, dict):
                    continue
                name = it.get("name")
                price = it.get("price")
                qty = it.get("quantity", 1.0)
                if not name or price is None:
                    continue
                try:
                    price_val = float(price)
                    qty_val = float(qty) if qty else 1.0
                    unit_price = round(price_val / max(1.0, qty_val), 2)
                    norm_name = _normalize_item_name(str(name))

                    if item_filter and item_filter.lower() not in norm_name.lower():
                        continue

                    history_by_item[norm_name].append({
                        "merchant": merchant,
                        "unit_price": unit_price,
                        "total_price": price_val,
                        "quantity": qty_val,
                        "timestamp": ts,
                        "date": ts[:10],
                    })
                except (ValueError, TypeError):
                    continue

    summary: List[Dict[str, Any]] = []

    for item_name, records in history_by_item.items():
        if not records:
            continue
        records.sort(key=lambda r: r["timestamp"])
        prices = [r["unit_price"] for r in records]
        first_price = prices[0]
        latest_price = prices[-1]
        min_price = min(prices)
        max_price = max(prices)
        avg_price = round(sum(prices) / len(prices), 2)

        inflation_pct = round(((latest_price - first_price) / first_price) * 100.0, 1) if first_price > 0 else 0.0

        stores_latest: Dict[str, float] = {}
        for r in records:
            stores_latest[r["merchant"]] = r["unit_price"]

        cheapest_store = min(stores_latest, key=stores_latest.get) if stores_latest else None

        summary.append({
            "item_name": item_name,
            "purchase_count": len(records),
            "latest_price": latest_price,
            "earliest_price": first_price,
            "min_price": min_price,
            "max_price": max_price,
            "average_price": avg_price,
            "inflation_pct": inflation_pct,
            "cheapest_store": cheapest_store,
            "cheapest_store_price": stores_latest.get(cheapest_store) if cheapest_store else None,
            "store_comparison": stores_latest,
            "history": records[-10:],
        })

    summary.sort(key=lambda s: s["purchase_count"], reverse=True)
    return summary
