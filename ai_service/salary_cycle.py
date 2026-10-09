"""
Saudi Salary Cycle (27th of month) forecaster and Pre-Purchase Affordability Simulator.
Calculates days to payday, burn rates, projected run-out dates, and budget health.
"""

from __future__ import annotations
import calendar
import logging
from datetime import date, datetime, timedelta, timezone
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

from supabase_client import get_client, fetch_flexible_budgets

def adjust_saudi_payday(target_date: date) -> date:
    """
    Adjusts the Saudi 27th payday according to Saudi banking conventions:
    - If 27th is Friday (weekday=4), salary is paid on Thursday (26th).
    - If 27th is Saturday (weekday=5), salary is paid on Sunday (28th).
    - Otherwise paid on 27th.
    """
    wd = target_date.weekday()
    if wd == 4:  # Friday
        return target_date - timedelta(days=1)
    elif wd == 5:  # Saturday
        return target_date + timedelta(days=1)
    return target_date


def _clamp_day(year: int, month: int, day: int) -> int:
    max_days = calendar.monthrange(year, month)[1]
    return min(max(1, day), max_days)


def get_cycle_for_date(target_date: Optional[date] = None, payday_day: int = 27) -> Dict[str, Any]:
    """
    Computes salary cycle boundaries for a given payday day (default 27).
    - If payday_day == 1, cycle is the calendar month (1st to last day of month).
    - If payday_day > 1, cycle is from payday_day of previous month to day before payday of this month (or from this month to next month if today >= payday).
    """
    payday_day = max(1, min(31, int(payday_day)))
    today = target_date or datetime.now(timezone.utc).date()

    if payday_day == 1:
        start_date = date(today.year, today.month, 1)
        max_days = calendar.monthrange(today.year, today.month)[1]
        end_date = date(today.year, today.month, max_days)
        cycle_key = f"{today.year:04d}-{today.month:02d}"
        cycle_month_name = date(today.year, today.month, 1).strftime("%B %Y")
    else:
        clamped_today_payday = _clamp_day(today.year, today.month, payday_day)
        if today.day >= clamped_today_payday:
            start_date = date(today.year, today.month, clamped_today_payday)
            next_year = today.year + (1 if today.month == 12 else 0)
            next_month = 1 if today.month == 12 else today.month + 1
            clamped_next_payday = _clamp_day(next_year, next_month, payday_day)
            end_date = date(next_year, next_month, clamped_next_payday) - timedelta(days=1)

            if payday_day <= 15:
                cycle_key = f"{today.year:04d}-{today.month:02d}"
                cycle_month_name = date(today.year, today.month, 1).strftime("%B %Y")
            else:
                cycle_key = f"{next_year:04d}-{next_month:02d}"
                cycle_month_name = date(next_year, next_month, 1).strftime("%B %Y")
        else:
            clamped_next_payday = clamped_today_payday
            end_date = date(today.year, today.month, clamped_next_payday) - timedelta(days=1)
            prev_year = today.year - (1 if today.month == 1 else 0)
            prev_month = 12 if today.month == 1 else today.month - 1
            clamped_prev_payday = _clamp_day(prev_year, prev_month, payday_day)
            start_date = date(prev_year, prev_month, clamped_prev_payday)

            if payday_day <= 15:
                cycle_key = f"{prev_year:04d}-{prev_month:02d}"
                cycle_month_name = date(prev_year, prev_month, 1).strftime("%B %Y")
            else:
                cycle_key = f"{today.year:04d}-{today.month:02d}"
                cycle_month_name = date(today.year, today.month, 1).strftime("%B %Y")

    return {
        "cycle_key": cycle_key,
        "cycle_start": start_date.isoformat(),
        "cycle_end": end_date.isoformat(),
        "label": f"{cycle_month_name} Budget ({start_date.strftime('%b %d')} - {end_date.strftime('%b %d')})",
        "month_name": cycle_month_name,
        "payday_day": payday_day,
    }


def get_salary_cycle_dates(current: Optional[date] = None, payday_day: int = 27) -> Dict[str, Any]:
    """
    Computes active salary cycle dates, days remaining to payday, and elapsed days.
    """
    payday_day = max(1, min(31, int(payday_day)))
    today = current or datetime.now(timezone.utc).date()
    cycle_info = get_cycle_for_date(today, payday_day=payday_day)
    start_date = date.fromisoformat(cycle_info["cycle_start"])
    end_date = date.fromisoformat(cycle_info["cycle_end"])

    if payday_day == 1:
        next_year = today.year + (1 if today.month == 12 else 0)
        next_month = 1 if today.month == 12 else today.month + 1
        nominal_payday = date(next_year, next_month, 1)
    else:
        clamped_today_payday = _clamp_day(today.year, today.month, payday_day)
        if today.day >= clamped_today_payday:
            next_year = today.year + (1 if today.month == 12 else 0)
            next_month = 1 if today.month == 12 else today.month + 1
            nominal_payday = date(next_year, next_month, _clamp_day(next_year, next_month, payday_day))
        else:
            nominal_payday = date(today.year, today.month, clamped_today_payday)

    actual_payday = adjust_saudi_payday(nominal_payday)
    days_total = (end_date - start_date).days + 1
    days_elapsed = max(1, (today - start_date).days + 1)
    days_remaining = max(0, (actual_payday - today).days)

    return {
        "today": today.isoformat(),
        "cycle_start": start_date.isoformat(),
        "cycle_end": end_date.isoformat(),
        "cycle_key": cycle_info["cycle_key"],
        "cycle_label": cycle_info["label"],
        "payday_day": payday_day,
        "nominal_payday": nominal_payday.isoformat(),
        "payday": actual_payday.isoformat(),
        "actual_payday": actual_payday.isoformat(),
        "is_weekend_adjusted": actual_payday != nominal_payday,
        "days_total": days_total,
        "days_elapsed": days_elapsed,
        "days_remaining": days_remaining,
    }


def get_salary_cycle_forecast(
    household_id: str,
    current: Optional[date] = None,
    payday_day: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Generates spending velocity, burn rate, and run-out projections for the active salary cycle.
    """
    from supabase_client import get_household_payday
    if payday_day is None:
        payday_day = get_household_payday(household_id)
    cycle = get_salary_cycle_dates(current, payday_day=payday_day)
    today = current or datetime.now(timezone.utc).date()
    client = get_client()

    # Query budgets for current cycle
    budgets_resp = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("cycle_key", cycle["cycle_key"])
        .execute()
    )

    if not budgets_resp.data:
        # Fallback query by month
        month_start = today.replace(day=1).isoformat()
        budgets_resp = (
            client.table("budgets")
            .select("*")
            .eq("household_id", household_id)
            .eq("month", month_start)
            .execute()
        )
    budgets = budgets_resp.data or []

    total_allocated = sum(float(b.get("allocated_amount", 0.0)) for b in budgets)
    total_spent = sum(float(b.get("spent_amount", 0.0)) for b in budgets)
    total_remaining = max(0.0, total_allocated - total_spent)

    FIXED_CODES = {"HOUSING-RENT", "HOUSING", "UTILITIES-BILLS", "UTILITIES"}
    fixed_spent = sum(float(b.get("spent_amount", 0.0)) for b in budgets if b.get("category_code") in FIXED_CODES)
    variable_spent = sum(float(b.get("spent_amount", 0.0)) for b in budgets if b.get("category_code") not in FIXED_CODES)
    
    fixed_allocated = sum(float(b.get("allocated_amount", 0.0)) for b in budgets if b.get("category_code") in FIXED_CODES)
    variable_allocated = sum(float(b.get("allocated_amount", 0.0)) for b in budgets if b.get("category_code") not in FIXED_CODES)
    
    target_allocated = variable_allocated if variable_allocated > 0 else total_allocated
    target_spent = variable_spent if variable_allocated > 0 else total_spent

    days_total = cycle["days_total"]
    days_elapsed = cycle["days_elapsed"]
    days_remaining = cycle["days_remaining"]

    # Daily burn rates based on recurring variable living expenses
    daily_budget_target = target_allocated / max(1, days_total)
    actual_burn_rate = target_spent / max(1, days_elapsed)
    daily_remaining_allowance = total_remaining / max(1, days_remaining) if days_remaining > 0 else 0.0

    # Projected spend: Fixed actual (committed) + projected variable spend over cycle
    projected_spend = fixed_spent + (actual_burn_rate * days_total) if variable_allocated > 0 else actual_burn_rate * days_total
    projected_savings = total_allocated - projected_spend

    # Run-out date forecast
    run_out_date_str = None
    if actual_burn_rate > 0:
        days_until_empty = int(total_remaining / actual_burn_rate)
        forecast_empty_date = today + timedelta(days=days_until_empty)
        run_out_date_str = forecast_empty_date.isoformat()
    else:
        forecast_empty_date = date.fromisoformat(cycle["payday"])
        run_out_date_str = cycle["payday"]

    # Pace status
    if total_spent > total_allocated:
        pace_status = "exhausted"
        pace_label_en = "Budget Exceeded"
        pace_label_ar = "تجاوزت الميزانية"
    elif actual_burn_rate > daily_budget_target * 1.25:
        pace_status = "critical"
        pace_label_en = "Burning Fast"
        pace_label_ar = "استهلاك سريع جداً"
    elif actual_burn_rate > daily_budget_target * 1.05:
        pace_status = "caution"
        pace_label_en = "Slightly Ahead of Pace"
        pace_label_ar = "استهلاك مرتفع نسبياً"
    else:
        pace_status = "on_track"
        pace_label_en = "On Track"
        pace_label_ar = "استهلاك ممتاز ومنتظم"

    return {
        "cycle": cycle,
        "total_allocated": round(total_allocated, 2),
        "total_spent": round(total_spent, 2),
        "total_remaining": round(total_remaining, 2),
        "daily_budget_target": round(daily_budget_target, 2),
        "actual_burn_rate": round(actual_burn_rate, 2),
        "daily_remaining_allowance": round(daily_remaining_allowance, 2),
        "projected_spend": round(projected_spend, 2),
        "projected_savings": round(projected_savings, 2),
        "forecast_run_out_date": run_out_date_str,
        "pace_status": pace_status,
        "pace_label_en": pace_label_en,
        "pace_label_ar": pace_label_ar,
    }


def simulate_affordability(
    household_id: str,
    target_amount: float,
    item_name: str = "item",
    category_code: Optional[str] = None,
) -> Dict[str, Any]:
    """
    'Can I Afford This?' Pre-Purchase simulator.
    Evaluates purchase against current salary cycle headroom, flexible budget pools, and days to 27th.
    """
    forecast = get_salary_cycle_forecast(household_id)
    total_remaining = forecast["total_remaining"]
    days_remaining = forecast["cycle"]["days_remaining"]
    daily_remaining = forecast["daily_remaining_allowance"]

    client = get_client()
    today = datetime.now(timezone.utc).date()
    month_start = today.replace(day=1).isoformat()

    # Category budget details
    cat_budget = None
    if category_code:
        resp = (
            client.table("budgets")
            .select("*")
            .eq("household_id", household_id)
            .eq("category_code", category_code)
            .eq("month", month_start)
            .maybe_single()
            .execute()
        )
        cat_budget = resp.data

    cat_remaining = float(cat_budget.get("remaining_amount", 0.0)) if cat_budget else 0.0

    # Flexible pools available for reallocation
    flexible = fetch_flexible_budgets(household_id, today, exclude_code=category_code or "")
    flexible_headroom = sum(f.remaining_amount for f in flexible)

    new_remaining = total_remaining - target_amount
    new_daily_allowance = max(0.0, new_remaining / max(1, days_remaining)) if days_remaining > 0 else 0.0

    if target_amount <= 0:
        verdict = "invalid"
        advice_en = "Please specify a positive price for the item."
        advice_ar = "يرجى تحديد سعر صالح للمنتج."
    elif target_amount <= cat_remaining:
        verdict = "comfortable"
        advice_en = (
            f"✅ Yes! You have SAR {cat_remaining:.1f} remaining in {category_code or 'this category'}. "
            f"You will still have SAR {new_remaining:.1f} total cushion until payday ({days_remaining} days away)."
        )
        advice_ar = (
            f"✅ نعم، بكل أريحية! متبقي لديك {cat_remaining:.1f} ريال في هذا البند. "
            f"وسيبقى لديك {new_remaining:.1f} ريال كمتبقي عام حتى يوم الراتب (بعد {days_remaining} يوم)."
        )
    elif target_amount <= (cat_remaining + flexible_headroom):
        verdict = "caution"
        deficit = target_amount - cat_remaining
        top_flex = flexible[0].category_code if flexible else "other flexible categories"
        advice_en = (
            f"⚠️ You can afford it, but it requires reallocating SAR {deficit:.1f} from {top_flex}. "
            f"Your daily spending cushion until payday drops from SAR {daily_remaining:.1f} to SAR {new_daily_allowance:.1f}/day."
        )
        advice_ar = (
            f"⚠️ نعم يمكنك شراؤها، ولكنها ستتطلب مناقلة {deficit:.1f} ريال من ميزانية {top_flex}. "
            f"وسينخفض معدل مصروفك اليومي المتاح حتى الراتب من {daily_remaining:.1f} ريال إلى {new_daily_allowance:.1f} ريال/يوم."
        )
    else:
        verdict = "unaffordable"
        shortage = target_amount - (cat_remaining + flexible_headroom)
        advice_en = (
            f"❌ Unaffordable right now. This purchase exceeds your total flexible budget by SAR {shortage:.1f}. "
            f"Consider waiting {days_remaining} days until salary day (27th) or setting up a dedicated savings bucket."
        )
        advice_ar = (
            f"❌ لا يمكن تحمل تكلفتها حالياً. تتجاوز الميزانية المتاحة بفارق {shortage:.1f} ريال. "
            f"يُفضل تأجيلها لمدة {days_remaining} يوم حتى موعد نزول الراتب (27 الشهر)."
        )

    return {
        "verdict": verdict,
        "is_affordable": verdict in ("comfortable", "caution"),
        "item_name": item_name,
        "target_amount": round(target_amount, 2),
        "current_total_remaining": round(total_remaining, 2),
        "post_purchase_remaining": round(new_remaining, 2),
        "current_daily_allowance": round(daily_remaining, 2),
        "post_purchase_daily_allowance": round(new_daily_allowance, 2),
        "days_to_payday": days_remaining,
        "advice_en": advice_en,
        "advice_ar": advice_ar,
    }


def get_cycle_info_for_key(cycle_key: str, payday_day: int = 27) -> Dict[str, Any]:
    """
    Given a cycle_key like '2026-10', compute cycle dates and labels.
    """
    payday_day = max(1, min(31, int(payday_day)))
    parts = cycle_key.split("-")
    year = int(parts[0])
    month = int(parts[1])
    cycle_month_name = date(year, month, 1).strftime("%B %Y")

    if payday_day == 1:
        start_date = date(year, month, 1)
        end_date = date(year, month, calendar.monthrange(year, month)[1])
    elif payday_day <= 15:
        start_date = date(year, month, _clamp_day(year, month, payday_day))
        next_year = year + (1 if month == 12 else 0)
        next_month = 1 if month == 12 else month + 1
        end_date = date(next_year, next_month, _clamp_day(next_year, next_month, payday_day)) - timedelta(days=1)
    else:
        prev_year = year - (1 if month == 1 else 0)
        prev_month = 12 if month == 1 else month - 1
        start_date = date(prev_year, prev_month, _clamp_day(prev_year, prev_month, payday_day))
        end_date = date(year, month, _clamp_day(year, month, payday_day)) - timedelta(days=1)

    return {
        "cycle_key": cycle_key,
        "cycle_start": start_date.isoformat(),
        "cycle_end": end_date.isoformat(),
        "label": f"{cycle_month_name} Budget ({start_date.strftime('%b %d')} - {end_date.strftime('%b %d')})",
        "month_name": cycle_month_name,
        "payday_day": payday_day,
    }


def get_available_cycles_for_household(household_id: str, payday_day: Optional[int] = None) -> Dict[str, Any]:
    """
    Returns the active salary cycle and all historical available cycles for a household.
    """
    from supabase_client import get_client, ensure_household_cycle_budgets, get_household_payday

    if payday_day is None:
        payday_day = get_household_payday(household_id)

    ensure_household_cycle_budgets(household_id, payday_day=payday_day)
    current_cycle = get_cycle_for_date(payday_day=payday_day)

    client = get_client()
    res = client.table("budgets").select("cycle_key, month").eq("household_id", household_id).execute()
    keys = set()
    for row in res.data or []:
        ck = row.get("cycle_key")
        if ck and len(ck) == 7:
            keys.add(ck)
        elif row.get("month"):
            keys.add(row["month"][:7])

    keys.add(current_cycle["cycle_key"])

    sorted_keys = sorted(list(keys), reverse=True)
    cycles = []
    for k in sorted_keys:
        info = get_cycle_info_for_key(k, payday_day=payday_day)
        info["is_current"] = (k == current_cycle["cycle_key"])
        cycles.append(info)

    return {
        "current_cycle": current_cycle,
        "cycles": cycles,
        "payday_day": payday_day,
    }


def match_sub_category(category_code: str, text: str, items: Optional[list] = None) -> Optional[str]:
    """
    Matches merchant, SMS text, or item descriptions against seeded sub-category keywords.
    """
    from supabase_client import get_client
    client = get_client()
    try:
        subs = client.table("cost_control_sub_categories").select("*").eq("parent_code", category_code).execute().data or []
    except Exception:
        return None
        
    search_corpus = (text or "").lower()
    if items:
        for it in items:
            search_corpus += " " + str(it.get("name", "")).lower()
            
    for sub in subs:
        keywords = sub.get("keywords") or []
        for kw in keywords:
            if kw.lower() in search_corpus:
                return sub["sub_code"]
    return None


def get_cycle_breakdown(household_id: str, cycle_key: Optional[str] = None) -> Dict[str, Any]:
    """
    Fetches categories and aggregates sub-budget spending for the given salary cycle.
    """
    from supabase_client import get_client, ensure_household_cycle_budgets
    
    current_cycle = get_cycle_for_date()
    target_key = cycle_key or current_cycle["cycle_key"]
    cycle_info = get_cycle_info_for_key(target_key)
    
    if target_key == current_cycle["cycle_key"]:
        ensure_household_cycle_budgets(household_id)
        
    client = get_client()
    
    # 1. Fetch budgets for this cycle
    budgets_resp = client.table("budgets").select("*").eq("household_id", household_id).execute()
    all_budgets = budgets_resp.data or []
    
    cycle_budgets = [
        b for b in all_budgets 
        if (b.get("cycle_key") == target_key or (not b.get("cycle_key") and b.get("month", "")[:7] == target_key))
        and b.get("is_active", True) is not False
    ]
    
    if not cycle_budgets and target_key == current_cycle["cycle_key"]:
        cycle_budgets = ensure_household_cycle_budgets(household_id)
        
    # 2. Category names lookup
    codes_resp = client.table("cost_control_codes").select("code, category").execute()
    cat_names = {c["code"]: c["category"] for c in (codes_resp.data or [])}
    
    # 3. Sub-categories definitions
    sub_resp = client.table("cost_control_sub_categories").select("*").execute()
    sub_defs_by_parent = {}
    for s in (sub_resp.data or []):
        p = s["parent_code"]
        if p not in sub_defs_by_parent:
            sub_defs_by_parent[p] = []
        sub_defs_by_parent[p].append(s)
        
    # 4. Fetch transactions in this cycle date range
    start_ts = f"{cycle_info['cycle_start']}T00:00:00"
    end_ts = f"{cycle_info['cycle_end']}T23:59:59"
    txs_resp = client.table("transactions").select("*").eq("household_id", household_id).gte("timestamp", start_ts).lte("timestamp", end_ts).execute()
    txs = txs_resp.data or []
    
    txs_cycle_resp = client.table("transactions").select("*").eq("household_id", household_id).eq("cycle_key", target_key).execute()
    existing_ids = {t["id"] for t in txs}
    for t in (txs_cycle_resp.data or []):
        if t["id"] not in existing_ids:
            txs.append(t)
            
    cat_sub_spending = {}
    for tx in txs:
        c_code = tx.get("category_code") or "OPEX-MISC"
        s_code = tx.get("sub_category")
        amt = float(tx.get("amount") or 0.0)
        
        key = (c_code, s_code or "other")
        if key not in cat_sub_spending:
            cat_sub_spending[key] = {"spent": 0.0, "count": 0}
        cat_sub_spending[key]["spent"] += amt
        cat_sub_spending[key]["count"] += 1

    # 5. Build category breakdown items
    categories = []
    for b in cycle_budgets:
        c_code = b["category_code"]
        c_name = cat_names.get(c_code, c_code)
        allocated = float(b.get("allocated_amount") or 0.0)
        prev_delta = float(b.get("previous_cycle_delta") or 0.0)
        
        sub_items = []
        predefined = sub_defs_by_parent.get(c_code, [])
        used_sub_codes = set()
        sub_allocs = b.get("sub_allocations") or {}
        if not isinstance(sub_allocs, dict):
            sub_allocs = {}
        
        for pre in predefined:
            sc_code = pre["sub_code"]
            used_sub_codes.add(sc_code)
            sp_data = cat_sub_spending.get((c_code, sc_code), {"spent": 0.0, "count": 0})
            sub_items.append({
                "sub_code": sc_code,
                "name": pre["name_en"],
                "allocated_amount": float(sub_allocs.get(sc_code, 0.0)),
                "spent_amount": round(sp_data["spent"], 2),
                "transaction_count": sp_data["count"],
            })
            
        other_sp = cat_sub_spending.get((c_code, "other"), {"spent": 0.0, "count": 0})
        for (c, sc), data in cat_sub_spending.items():
            if c == c_code and sc != "other" and sc not in used_sub_codes:
                sub_items.append({
                    "sub_code": sc,
                    "name": sc.replace("_", " ").title(),
                    "allocated_amount": float(sub_allocs.get(sc, 0.0)),
                    "spent_amount": round(data["spent"], 2),
                    "transaction_count": data["count"],
                })
                
        if other_sp["spent"] > 0 or other_sp["count"] > 0 or not sub_items:
            sub_items.append({
                "sub_code": "other",
                "name": "General / Other",
                "allocated_amount": float(sub_allocs.get("other", 0.0)),
                "spent_amount": round(other_sp["spent"], 2),
                "transaction_count": other_sp["count"],
            })
            
        total_sub_spent = sum(item["spent_amount"] for item in sub_items)
        actual_spent = max(total_sub_spent, float(b.get("spent_amount") or 0.0))
        remaining = allocated - actual_spent
        
        categories.append({
            "category_code": c_code,
            "category_name": c_name,
            "allocated_amount": allocated,
            "spent_amount": round(actual_spent, 2),
            "remaining_amount": round(remaining, 2),
            "previous_cycle_delta": prev_delta,
            "sub_categories": sub_items,
        })
        
    return {
        "cycle_key": target_key,
        "cycle_info": cycle_info,
        "categories": categories,
    }


def add_category_and_budget(req: Any) -> Dict[str, Any]:
    from supabase_client import get_client
    client = get_client()
    
    keywords = req.keywords or [req.category.lower()]
    existing_code = client.table("cost_control_codes").select("id").eq("code", req.code).execute().data
    if existing_code:
        client.table("cost_control_codes").update({
            "category": req.category,
            "keywords": keywords,
            "is_flexible": req.is_flexible,
        }).eq("code", req.code).execute()
    else:
        client.table("cost_control_codes").insert({
            "code": req.code,
            "category": req.category,
            "keywords": keywords,
            "is_flexible": req.is_flexible,
        }).execute()
    
    current_cycle = get_cycle_for_date()
    today = datetime.now(timezone.utc).date()
    month_str = today.replace(day=1).isoformat()
    
    existing_b = (
        client.table("budgets")
        .select("id")
        .eq("household_id", req.household_id)
        .eq("category_code", req.code)
        .eq("cycle_key", current_cycle["cycle_key"])
        .execute()
        .data
    )
    if existing_b:
        client.table("budgets").update({
            "allocated_amount": req.allocated_amount,
            "is_active": True,
        }).eq("id", existing_b[0]["id"]).execute()
    else:
        budget_payload = {
            "household_id": req.household_id,
            "month": month_str,
            "cycle_key": current_cycle["cycle_key"],
            "category_code": req.code,
            "allocated_amount": req.allocated_amount,
            "spent_amount": 0.0,
            "previous_cycle_delta": 0.0,
            "is_active": True,
        }
        client.table("budgets").insert(budget_payload).execute()
    
    return {
        "status": "success",
        "category_code": req.code,
        "category": req.category,
        "allocated_amount": req.allocated_amount,
    }



def get_sub_categories_for_parent(parent_code: str) -> List[Dict[str, Any]]:
    """
    Fetches all sub-category definitions for a parent category code.
    """
    from supabase_client import get_client
    client = get_client()
    try:
        resp = (
            client.table("cost_control_sub_categories")
            .select("sub_code, name_en, name_ar")
            .eq("parent_code", parent_code)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.warning(f"Error fetching sub-categories for {parent_code}: {e}")
        return []


def archive_category_for_household(household_id: str, category_code: str) -> Dict[str, Any]:
    from supabase_client import get_client
    client = get_client()

    current_cycle = get_cycle_for_date()
    target_key = current_cycle["cycle_key"]
    month_start = f"{target_key}-01"

    # 1. Update or create an inactive record in budgets so the UI reliably knows it is inactive
    existing_budgets = (
        client.table("budgets")
        .select("id")
        .eq("household_id", household_id)
        .eq("category_code", category_code)
        .execute()
    )

    if existing_budgets.data:
        client.table("budgets").update({
            "is_active": False,
            "allocated_amount": 0.0,
            "sub_allocations": {},
        }).eq("household_id", household_id).eq("category_code", category_code).execute()
    else:
        insert_data = {
            "household_id": household_id,
            "category_code": category_code,
            "allocated_amount": 0.0,
            "spent_amount": 0.0,
            "month": month_start,
            "cycle_key": target_key,
            "is_active": False,
            "sub_allocations": {},
        }
        client.table("budgets").insert(insert_data).execute()

    # 2. If it is a non-standard custom category and has zero transactions anywhere, clean up custom definition
    standard_codes = {
        "OPEX-GROCERY", "OPEX-DINING", "OPEX-FUEL", "OPEX-UTILITIES",
        "OPEX-SHOPPING", "OPEX-ENTERTAINMENT", "OPEX-HEALTH", "CAPEX-EDUCATION",
        "OPEX-GOV", "OPEX-MISC"
    }
    if category_code not in standard_codes:
        tx_check = (
            client.table("transactions")
            .select("id")
            .eq("category_code", category_code)
            .limit(1)
            .execute()
        )
        if not (tx_check.data or []):
            try:
                client.table("cost_control_sub_categories").delete().eq("parent_code", category_code).execute()
                client.table("budgets").delete().eq("category_code", category_code).execute()
                client.table("cost_control_codes").delete().eq("code", category_code).execute()
            except Exception as e:
                logger.warning(f"Could not purge custom category {category_code}: {e}")

    return {
        "status": "success",
        "message": f"Category {category_code} archived successfully.",
        "category_code": category_code,
    }


def add_sub_category_for_household(
    household_id: str,
    parent_code: str,
    name_en: str,
    allocated_amount: float = 0.0,
    sub_code: Optional[str] = None,
    cycle_key: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Creates a new sub-category definition under a parent category and assigns an initial allocation.
    """
    from supabase_client import get_client
    import re
    client = get_client()

    if not sub_code:
        slug = re.sub(r"[^a-zA-Z0-9]+", "-", name_en.strip().lower()).strip("-")
        sub_code = f"sub-{slug}"

    # Upsert into cost_control_sub_categories
    existing_sub = client.table("cost_control_sub_categories").select("id").eq("parent_code", parent_code).eq("sub_code", sub_code).execute().data
    if not existing_sub:
        client.table("cost_control_sub_categories").insert({
            "parent_code": parent_code,
            "sub_code": sub_code,
            "name_en": name_en,
            "name_ar": name_en,
            "keywords": [name_en.lower()],
        }).execute()


    current_cycle = get_cycle_for_date()
    target_key = cycle_key or current_cycle["cycle_key"]

    res = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("category_code", parent_code)
        .execute()
    )
    matching = [
        row for row in (res.data or [])
        if row.get("cycle_key") == target_key or (not row.get("cycle_key") and row.get("month", "")[:7] == target_key)
    ]

    sub_allocs = {}
    if matching:
        sub_allocs = matching[0].get("sub_allocations") or {}
        if not isinstance(sub_allocs, dict):
            sub_allocs = {}

    sub_allocs[sub_code] = round(float(allocated_amount), 2)
    return save_sub_allocations(household_id, parent_code, sub_allocs, target_key)


def rename_sub_category(
    parent_code: str,
    sub_code: str,
    name_en: str,
    name_ar: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Renames an existing sub-category in cost_control_sub_categories.
    """
    from supabase_client import get_client
    client = get_client()

    update_data: Dict[str, Any] = {"name_en": name_en.strip()}
    if name_ar is not None:
        update_data["name_ar"] = name_ar.strip()
    else:
        update_data["name_ar"] = name_en.strip()

    client.table("cost_control_sub_categories").update(update_data).eq("parent_code", parent_code).eq("sub_code", sub_code).execute()

    return {
        "status": "success",
        "parent_code": parent_code,
        "sub_code": sub_code,
        "name_en": name_en.strip(),
    }


def remove_sub_category_for_household(
    household_id: str,
    parent_code: str,
    sub_code: str,
    cycle_key: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Removes a sub-category from a household's cycle budget and purges its definition if unused.
    """
    from supabase_client import get_client
    client = get_client()

    current_cycle = get_cycle_for_date()
    target_key = cycle_key or current_cycle["cycle_key"]

    # 1. Remove from budgets.sub_allocations and recalculate parent allocated_amount
    res = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("category_code", parent_code)
        .execute()
    )
    matching = [
        row for row in (res.data or [])
        if row.get("cycle_key") == target_key or (not row.get("cycle_key") and row.get("month", "")[:7] == target_key)
    ]

    if matching:
        budget_row = matching[0]
        sub_allocs = budget_row.get("sub_allocations") or {}
        if isinstance(sub_allocs, dict) and sub_code in sub_allocs:
            del sub_allocs[sub_code]
            new_total = round(sum(float(v) for v in sub_allocs.values()), 2)
            client.table("budgets").update({
                "sub_allocations": sub_allocs,
                "allocated_amount": new_total,
            }).eq("id", budget_row["id"]).execute()

    # 2. Check if transactions reference this sub_category
    tx_check = (
        client.table("transactions")
        .select("id")
        .eq("household_id", household_id)
        .eq("category_code", parent_code)
        .eq("sub_category", sub_code)
        .limit(1)
        .execute()
    )
    if not (tx_check.data or []):
        try:
            client.table("cost_control_sub_categories").delete().eq("parent_code", parent_code).eq("sub_code", sub_code).execute()
        except Exception as e:
            logger.warning(f"Could not delete sub-category {sub_code}: {e}")

    return {
        "status": "success",
        "parent_code": parent_code,
        "sub_code": sub_code,
    }


def save_sub_allocations(
    household_id: str,
    category_code: str,
    sub_allocations: Dict[str, float],
    cycle_key: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Saves sub-category allocations for a category in the specified cycle.
    Automatically sets the parent budget's allocated_amount to the sum of sub-allocations.
    """
    from supabase_client import get_client
    
    current_cycle = get_cycle_for_date()
    target_key = cycle_key or current_cycle["cycle_key"]
    
    clean_sub_allocations = {k: round(float(v), 2) for k, v in sub_allocations.items()}
    total_allocated = round(sum(clean_sub_allocations.values()), 2)
    
    client = get_client()
    
    res = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("category_code", category_code)
        .execute()
    )
    matching = [
        row for row in (res.data or [])
        if row.get("cycle_key") == target_key or (not row.get("cycle_key") and row.get("month", "")[:7] == target_key)
    ]
    
    month_start = f"{target_key}-01"
    
    if matching:
        budget_id = matching[0]["id"]
        # Update allocated_amount and sub_allocations (note: remaining_amount is GENERATED ALWAYS)
        update_data = {
            "allocated_amount": total_allocated,
            "sub_allocations": clean_sub_allocations,
            "cycle_key": target_key,
            "is_active": True,
        }
        client.table("budgets").update(update_data).eq("id", budget_id).execute()
    else:
        insert_data = {
            "household_id": household_id,
            "category_code": category_code,
            "allocated_amount": total_allocated,
            "sub_allocations": clean_sub_allocations,
            "spent_amount": 0.0,
            "month": month_start,
            "cycle_key": target_key,
            "is_active": True,
        }
        client.table("budgets").insert(insert_data).execute()
        
    return {
        "status": "success",
        "category_code": category_code,
        "cycle_key": target_key,
        "allocated_amount": total_allocated,
        "sub_allocations": clean_sub_allocations,
    }


