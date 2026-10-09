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


BENCHMARK_STORE_PRICES: Dict[str, Dict[str, float]] = {
    "Milk": {"Panda": 14.50, "Danube": 16.00, "Tamimi": 15.50, "Othaim": 14.00, "Lulu": 14.25},
    "Chicken": {"Panda": 38.00, "Danube": 44.50, "Tamimi": 42.00, "Othaim": 36.50, "Lulu": 37.00},
    "Bread": {"Panda": 4.50, "Danube": 5.00, "Tamimi": 5.00, "Othaim": 4.00, "Lulu": 4.25},
    "Eggs": {"Panda": 21.00, "Danube": 24.50, "Tamimi": 23.00, "Othaim": 19.50, "Lulu": 20.00},
    "Cheese": {"Panda": 26.00, "Danube": 29.50, "Tamimi": 28.00, "Othaim": 25.00, "Lulu": 25.50},
    "Rice": {"Panda": 68.00, "Danube": 76.00, "Tamimi": 74.00, "Othaim": 65.00, "Lulu": 67.00},
    "Oil": {"Panda": 32.00, "Danube": 36.50, "Tamimi": 35.00, "Othaim": 30.50, "Lulu": 31.00},
    "Coffee": {"Panda": 42.00, "Danube": 48.00, "Tamimi": 46.50, "Othaim": 39.50, "Lulu": 41.00},
    "Tea": {"Panda": 18.00, "Danube": 21.00, "Tamimi": 20.00, "Othaim": 17.50, "Lulu": 18.00},
}


def optimize_shopping_basket(household_id: str, items: List[str]) -> Dict[str, Any]:
    """
    Given a list of grocery items for a shopping trip, calculates:
    1. Total basket price at each store (Panda, Danube, Tamimi, Othaim, Lulu).
    2. Cheapest single store to do the full grocery run.
    3. Multi-store split trip optimization showing maximum possible savings.
    """
    if not items:
        return {
            "status": "empty",
            "items_count": 0,
            "cheapest_store": None,
            "cheapest_store_total": 0.0,
            "store_totals": {},
            "single_store_savings": 0.0,
            "split_optimization": {"split_total": 0.0, "extra_savings_vs_single_store": 0.0, "items": []},
        }

    # Fetch recorded household grocery prices to override benchmark
    history = get_grocery_price_history(household_id)
    recorded_item_stores: Dict[str, Dict[str, float]] = {}
    for h in history:
        norm_name = h.get("item_name", "").capitalize()
        comparison = h.get("store_comparison", {})
        if comparison:
            recorded_item_stores[norm_name] = {k: float(v) for k, v in comparison.items()}

    all_stores = ["Panda", "Danube", "Tamimi", "Othaim", "Lulu"]
    store_totals: Dict[str, float] = {s: 0.0 for s in all_stores}
    item_breakdown: List[Dict[str, Any]] = []

    for raw_item in items:
        norm = _normalize_item_name(raw_item)
        store_prices = recorded_item_stores.get(norm) or BENCHMARK_STORE_PRICES.get(norm)
        if not store_prices:
            default_est = 20.0
            store_prices = {
                "Panda": default_est,
                "Danube": round(default_est * 1.15, 2),
                "Tamimi": round(default_est * 1.12, 2),
                "Othaim": round(default_est * 0.95, 2),
                "Lulu": default_est,
            }

        cheapest_store_for_item = min(store_prices, key=store_prices.get)
        cheapest_price_for_item = store_prices[cheapest_store_for_item]

        for s in all_stores:
            price = store_prices.get(s, cheapest_price_for_item)
            store_totals[s] = round(store_totals[s] + price, 2)

        item_breakdown.append({
            "item_name": norm,
            "cheapest_store": cheapest_store_for_item,
            "cheapest_price": cheapest_price_for_item,
            "store_prices": {s: store_prices.get(s, cheapest_price_for_item) for s in all_stores},
        })

    cheapest_single_store = min(store_totals, key=store_totals.get)
    cheapest_single_total = store_totals[cheapest_single_store]
    highest_single_total = max(store_totals.values())
    single_store_savings = round(highest_single_total - cheapest_single_total, 2)

    split_total = round(sum(it["cheapest_price"] for it in item_breakdown), 2)
    split_savings = round(cheapest_single_total - split_total, 2)

    return {
        "status": "success",
        "items_count": len(items),
        "cheapest_store": cheapest_single_store,
        "cheapest_store_total": cheapest_single_total,
        "store_totals": store_totals,
        "single_store_savings": single_store_savings,
        "split_optimization": {
            "split_total": split_total,
            "extra_savings_vs_single_store": split_savings,
            "items": item_breakdown,
        },
    }
