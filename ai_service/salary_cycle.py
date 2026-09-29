"""
Saudi Salary Cycle (27th of month) forecaster and Pre-Purchase Affordability Simulator.
Calculates days to payday, burn rates, projected run-out dates, and budget health.
"""

from __future__ import annotations
import calendar
from datetime import date, datetime, timedelta, timezone
from typing import Dict, Any, Optional

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


def get_salary_cycle_dates(current: Optional[date] = None) -> Dict[str, Any]:
    """
    Computes current Saudi salary cycle dates (27th to 26th).
    If current day is >= 27, cycle started on 27th of this month.
    If current day is < 27, cycle started on 27th of previous month.
    """
    today = current or datetime.now(timezone.utc).date()
    
    if today.day >= 27:
        start_date = today.replace(day=27)
        # End date is 26th of next month
        year = today.year + (1 if today.month == 12 else 0)
        month = 1 if today.month == 12 else today.month + 1
        end_date = date(year, month, 26)
        nominal_payday = date(year, month, 27)
    else:
        # Start date was 27th of previous month
        year = today.year - (1 if today.month == 1 else 0)
        month = 12 if today.month == 1 else today.month - 1
        start_date = date(year, month, 27)
        end_date = today.replace(day=26)
        nominal_payday = today.replace(day=27)

    actual_payday = adjust_saudi_payday(nominal_payday)
    days_total = (end_date - start_date).days + 1
    days_elapsed = max(1, (today - start_date).days + 1)
    days_remaining = max(0, (actual_payday - today).days)

    return {
        "today": today.isoformat(),
        "cycle_start": start_date.isoformat(),
        "cycle_end": end_date.isoformat(),
        "nominal_payday": nominal_payday.isoformat(),
        "payday": actual_payday.isoformat(),
        "actual_payday": actual_payday.isoformat(),
        "is_weekend_adjusted": actual_payday != nominal_payday,
        "days_total": days_total,
        "days_elapsed": days_elapsed,
        "days_remaining": days_remaining,
    }


def get_salary_cycle_forecast(household_id: str, current: Optional[date] = None) -> Dict[str, Any]:
    """
    Generates spending velocity, burn rate, and run-out projections for the active salary cycle.
    """
    cycle = get_salary_cycle_dates(current)
    today = current or datetime.now(timezone.utc).date()
    client = get_client()

    # Query budgets for current month
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

    days_total = cycle["days_total"]
    days_elapsed = cycle["days_elapsed"]
    days_remaining = cycle["days_remaining"]

    # Daily burn rates
    daily_budget_target = total_allocated / max(1, days_total)
    actual_burn_rate = total_spent / max(1, days_elapsed)
    daily_remaining_allowance = total_remaining / max(1, days_remaining) if days_remaining > 0 else 0.0

    # Projected spend at current velocity
    projected_spend = actual_burn_rate * days_total
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
