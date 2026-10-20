"""
Supabase database helper functions for the Budget Tracker AI microservice.
All DB operations use the SERVICE ROLE KEY — bypasses RLS intentionally.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import date, datetime, timezone
from typing import Any, Optional

from supabase import create_client, Client

from models import BudgetRow, CostControlCode

from utils import riyadh_today  # noqa: E402  (Asia/Riyadh calendar date)

logger = logging.getLogger(__name__)

# ─── Singleton client ─────────────────────────────────────────────────────────
_client: Optional[Client] = None

_KEY_ENV_VARS = ("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY")
_PRIVILEGED_ROLES = ("secret", "service_role")


def _classify_supabase_key(key: str) -> str:
    """
    Classify a Supabase API key WITHOUT verifying or logging it.

    Returns one of: 'secret' (opaque sb_secret_ key), 'service_role', 'anon',
    'authenticated', 'publishable', 'unknown-jwt', 'unknown'. Only 'secret' and
    'service_role' grant the privileges this server-side service is designed for.
    """
    key = (key or "").strip()
    if key.startswith("sb_secret_") and len(key) > len("sb_secret_"):
        return "secret"
    if key.startswith("sb_publishable_"):
        return "publishable"
    parts = key.split(".")
    if len(parts) == 3 and parts[0].startswith("eyJ"):
        try:
            import base64
            payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(payload_b64.encode("ascii")))
            role = str(payload.get("role") or "")
            return role if role in ("service_role", "anon", "authenticated") else "unknown-jwt"
        except Exception:
            return "unknown-jwt"
    return "unknown"


def describe_supabase_key() -> dict:
    """
    Pick the privileged key to use from SUPABASE_SECRET_KEY and SUPABASE_SERVICE_ROLE_KEY.

    Either variable may hold either kind of privileged key: a new opaque ``sb_secret_…`` key or
    a legacy JWT whose role claim is ``service_role``. Anon / publishable / authenticated /
    unrecognised values are never used (an anon JWT once silently downgraded every query to the
    anon role: RLS denied household checks, the quota RPC was refused, writes fell back to local
    JSON).

    Precedence (both variables are always inspected):
      1. an ``sb_secret_`` key (legacy JWT keys can be disabled in the dashboard once a project
         migrates, so the new key is the one that keeps working), SUPABASE_SECRET_KEY first;
      2. a legacy ``service_role`` JWT, SUPABASE_SECRET_KEY first.
    A non-privileged value next to a privileged one is ignored with a warning, as is a second,
    different privileged key, so a misconfiguration is visible instead of silently skipped.

    Returns {"env_var", "role", "key", "rejected": [(env_var, role)], "warnings": [str]}.
    Never log "key"; "warnings" name variables and roles only.
    """
    candidates = []
    rejected = []
    for env_var in _KEY_ENV_VARS:
        value = (os.environ.get(env_var) or "").strip()
        if not value:
            continue
        role = _classify_supabase_key(value)
        if role in _PRIVILEGED_ROLES:
            candidates.append((env_var, role, value))
        else:
            rejected.append((env_var, role))

    candidates.sort(key=lambda c: _PRIVILEGED_ROLES.index(c[1]))  # stable: keeps variable order
    chosen = candidates[0] if candidates else None
    warnings = []
    if chosen:
        for env_var, role in rejected:
            warnings.append(
                f"{env_var} holds a non-privileged Supabase key (role '{role}') and is ignored; "
                f"using {chosen[0]} ({chosen[1]})."
            )
        for env_var, role, value in candidates[1:]:
            if value != chosen[2]:
                warnings.append(
                    f"{env_var} holds a different privileged key ({role}) and is ignored; "
                    f"using {chosen[0]} ({chosen[1]}). Remove the stale one."
                )
        return {"env_var": chosen[0], "role": chosen[1], "key": chosen[2], "rejected": rejected, "warnings": warnings}
    return {"env_var": None, "role": None, "key": None, "rejected": rejected, "warnings": warnings}


def get_client() -> Client:
    """Return (or lazily create) the Supabase service-role client. Fails closed on a non-privileged key."""
    global _client
    if _client is None:
        url = (os.environ.get("SUPABASE_URL") or "").strip()
        info = describe_supabase_key()
        if not url or not info["key"]:
            rejected = ", ".join(f"{var} has role '{role}'" for var, role in info["rejected"])
            raise RuntimeError(
                "Supabase is not configured with a privileged key. Set SUPABASE_URL and an "
                "sb_secret_... key (or a legacy service_role JWT) in SUPABASE_SECRET_KEY or "
                "SUPABASE_SERVICE_ROLE_KEY. "
                + (f"Rejected: {rejected}." if rejected else "No key found.")
            )
        for warning in info["warnings"]:
            logger.warning(warning)
        _client = create_client(url, info["key"])
        logger.info("Supabase client initialised with %s (%s).", info["env_var"], info["role"])
    return _client




from postgrest_compat import first_row  # noqa: E402,F401  (zero-or-one-row lookups, any postgrest version)


# =============================================================================
# COST CONTROL CODES
# =============================================================================

# ─── Cost Control Codes Cache ───────────────────────────────────────────────
_cached_cost_codes: Optional[list[CostControlCode]] = None
_cached_cost_codes_time: Optional[float] = None
_CACHE_TTL_SECONDS = 300.0  # 5 minutes


def fetch_all_cost_control_codes(force_refresh: bool = False) -> list[CostControlCode]:
    """
    Load the full cost_control_codes table into memory with a 5-minute TTL cache.
    Eliminates repetitive network queries for static categories during chat and receipt parsing.
    """
    global _cached_cost_codes, _cached_cost_codes_time
    import time
    now = time.time()
    if not force_refresh and _cached_cost_codes is not None and _cached_cost_codes_time is not None:
        if now - _cached_cost_codes_time < _CACHE_TTL_SECONDS:
            return _cached_cost_codes

    client = get_client()
    response = client.table("cost_control_codes").select("*").execute()
    rows = response.data or []
    _cached_cost_codes = [CostControlCode(**row) for row in rows]
    _cached_cost_codes_time = now
    logger.debug("Fetched and cached %d cost control codes (TTL %ds).", len(rows), int(_CACHE_TTL_SECONDS))
    return _cached_cost_codes


def match_category(merchant: str, codes: list[CostControlCode]) -> Optional[CostControlCode]:
    """
    Find the best-matching CostControlCode for a merchant name.
    Requires word-boundary matching for short keywords (< 4 chars) to prevent false positives (e.g. 'du' matching 'Dunkin').
    """
    import re
    merchant_lower = merchant.lower().strip()
    
    # Sort codes with longer keywords first for specificity
    for code in codes:
        for kw in sorted(code.keywords, key=len, reverse=True):
            kw_clean = kw.lower().strip()
            if not kw_clean:
                continue
            if len(kw_clean) < 4:
                # Require word boundary
                if re.search(rf"\b{re.escape(kw_clean)}\b", merchant_lower):
                    logger.debug("Merchant '%s' matched short keyword '%s' → %s", merchant, kw, code.code)
                    return code
            else:
                if kw_clean in merchant_lower or merchant_lower in kw_clean:
                    logger.debug("Merchant '%s' matched keyword '%s' → %s", merchant, kw, code.code)
                    return code
    return None


# =============================================================================
# BUDGETS
# =============================================================================

def _cycle_key_for(household_id: str, on_date: date) -> str:
    from salary_cycle import get_cycle_for_date
    return get_cycle_for_date(on_date, payday_day=get_household_payday(household_id))["cycle_key"]


def fetch_budget(
    household_id: str,
    category_code: str,
    month: date,
) -> Optional[BudgetRow]:
    """
    Fetch the budget row for a given household + category + month.
    Returns None if no budget has been allocated yet.
    """
    client = get_client()
    month_str = month.replace(day=1).isoformat()  # always first of month

    # Budgets are keyed by salary cycle: after the 27th the calendar month still matches the
    # *previous* cycle's row, so a month lookup reallocated against the wrong budget.
    cycle_key = _cycle_key_for(household_id, month)
    response = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("category_code", category_code)
        .eq("cycle_key", cycle_key)
        .limit(1)
        .execute()
    )
    data = response.data
    if not data:
        response = (
            client.table("budgets")
            .select("*")
            .eq("household_id", household_id)
            .eq("category_code", category_code)
            .eq("month", month_str)
            .is_("cycle_key", "null")
            .limit(1)
            .execute()
        )
        data = response.data
    if not data:
        logger.warning(
            "No budget found for household=%s category=%s month=%s",
            household_id, category_code, month_str,
        )
        return None
    return BudgetRow(**data[0])


def fetch_flexible_budgets(
    household_id: str,
    month: date,
    exclude_code: str,
) -> list[BudgetRow]:
    """
    Fetch all flexible budgets for the household in the given month,
    sorted by remaining_amount descending (most headroom first).
    Excludes the category that already overflowed.
    """
    client = get_client()
    month_str = month.replace(day=1).isoformat()

    # Get flexible category codes first
    codes_resp = (
        client.table("cost_control_codes")
        .select("code")
        .eq("is_flexible", True)
        .neq("code", exclude_code)
        .execute()
    )
    flexible_codes = [row["code"] for row in (codes_resp.data or [])]
    if not flexible_codes:
        return []

    cycle_key = _cycle_key_for(household_id, month)
    response = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("cycle_key", cycle_key)
        .in_("category_code", flexible_codes)
        .gt("remaining_amount", 0)
        .order("remaining_amount", desc=True)
        .execute()
    )
    rows = response.data or []
    if not rows:
        response = (
            client.table("budgets")
            .select("*")
            .eq("household_id", household_id)
            .eq("month", month_str)
            .is_("cycle_key", "null")
            .in_("category_code", flexible_codes)
            .gt("remaining_amount", 0)
            .order("remaining_amount", desc=True)
            .execute()
        )
        rows = response.data or []
    logger.debug("Found %d flexible budgets available for reallocation.", len(rows))
    return [BudgetRow(**r) for r in rows]


def reallocate_budget(from_budget_id: str, to_budget_id: str, amount: Any) -> bool:
    """
    Move ``amount`` of allocation from a flexible budget to ``to_budget_id`` through the
    ``reallocate_budget`` RPC (20261020030000: row locks, same-household and sufficient-allocation
    checks, positive amount with at most 2 decimals). Returns True when it happened.

    The amount is sent as exact decimal text: a float deficit such as 50.3 - 20.1 =
    30.199999999999996 was refused by the RPC, and the old fallback then rewrote both rows with
    two unlocked, unchecked updates (FR-B-06). A refusal now just means no reallocation.
    """
    from decimal import ROUND_HALF_UP, Decimal

    value = Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if value <= 0:
        return False
    try:
        get_client().rpc("reallocate_budget", {
            "p_from_id": from_budget_id,
            "p_to_id": to_budget_id,
            "p_amount": format(value, "f"),
        }).execute()
    except Exception as exc:
        logger.warning("Budget reallocation %s -> %s of %s refused: %s", from_budget_id, to_budget_id, value, exc)
        return False
    logger.info("Reallocated %s from budget %s to %s.", value, from_budget_id, to_budget_id)
    return True


# =============================================================================
# TRANSACTIONS
# =============================================================================

# Ingestion channels a transaction can come from. Expenses are entered by chat/voice
# ("chat"), receipt photo or ZATCA QR scan ("receipt_scan"), or by hand ("manual").
# There is deliberately no "sms" channel: the app never reads SMS (zero-SMS policy).
TRANSACTION_SOURCES = frozenset({"chat", "receipt_scan", "manual"})


def insert_transaction(
    household_id: str,
    amount: float,
    currency: str,
    merchant: str,
    category_code: str,
    timestamp: str,
    raw_sms: str,
    is_reallocated: bool = False,
    reallocated_from_budget_id: Optional[str] = None,
    source: str = "manual",
    items: Optional[list] = None,
    receipt_url: Optional[str] = None,
    spent_by: Optional[str] = None,
    paid_by: Optional[str] = None,
    beneficiary: Optional[str] = None,
    sub_category: Optional[str] = None,
    cycle_key: Optional[str] = None,
    dedup_fingerprint: Optional[str] = None,
    qr_code_raw: Optional[str] = None,
    nafaqah_class: Optional[str] = None,
    nafaqah_spouse_id: Optional[str] = None,
    user_id: Optional[str] = None,
) -> str:
    """
    Insert a new transaction row and return its UUID.

    ``user_id`` is the creator: the verified JWT subject of the request (DB-18). The service
    role bypasses RLS, so request-driven callers must always pass it; it is never pruned by the
    fallbacks below, and only that user or a household admin may later edit or delete the row.
    The on_transaction_insert trigger automatically updates budgets.spent_amount.

    ``raw_sms`` is the free-text audit note column (chat text, receipt summary, manual
    note); the name is historical — the app never reads SMS. ``source`` must be one of
    ``TRANSACTION_SOURCES``: there is no SMS ingestion channel (zero-SMS policy).
    ``nafaqah_class``/``nafaqah_spouse_id`` (family households) are never pruned by the
    fallbacks below: silently dropping them would erase the wife's reimbursement debt.
    """
    if source not in TRANSACTION_SOURCES:
        raise ValueError(f"Unsupported transaction source: {source!r}")
    client = get_client()

    # Automatically derive cycle_key from timestamp if not supplied
    # Mirrors the DB trigger populate_transaction_cycle_key: Riyadh calendar date of the
    # timestamp and the household's configured payday (was: UTC date and a fixed 27th).
    if not cycle_key:
        from salary_cycle import get_cycle_for_date
        from utils import riyadh_date_for_timestamp
        payday_day = get_household_payday(household_id)
        try:
            tx_date = riyadh_date_for_timestamp(timestamp)
        except (TypeError, ValueError):
            tx_date = riyadh_today()
        cycle_key = get_cycle_for_date(tx_date, payday_day=payday_day)["cycle_key"]

    # Automatically derive sub_category from keywords if not supplied
    if not sub_category and category_code:
        try:
            from salary_cycle import match_sub_category
            sub_category = match_sub_category(category_code, f"{merchant} {raw_sms}", items)
        except Exception:
            pass

    payload = {
        "household_id": household_id,
        "user_id": user_id,
        "amount": amount,
        "currency": currency,
        "merchant": merchant,
        "category_code": category_code,
        "timestamp": timestamp,
        "raw_sms": raw_sms,
        "is_reallocated": is_reallocated,
        "reallocated_from_budget_id": reallocated_from_budget_id,
        "source": source,
    }
    if items:
        payload["items"] = items
    if receipt_url:
        payload["receipt_url"] = receipt_url
    if spent_by:
        payload["spent_by"] = spent_by
    if paid_by:
        payload["paid_by"] = paid_by
    if beneficiary:
        payload["beneficiary"] = beneficiary
    if sub_category:
        payload["sub_category"] = sub_category
    if cycle_key:
        payload["cycle_key"] = cycle_key
    if dedup_fingerprint:
        payload["dedup_fingerprint"] = dedup_fingerprint
    if qr_code_raw:
        payload["qr_code_raw"] = qr_code_raw
    nafaqah_fields = (
        {"nafaqah_class": nafaqah_class, "nafaqah_spouse_id": nafaqah_spouse_id}
        if nafaqah_class and nafaqah_spouse_id
        else {}
    )
    payload.update(nafaqah_fields)


    try:
        response = client.table("transactions").insert(payload).execute()
    except Exception as exc:
        logger.warning("Insert with initial payload failed (%s), retrying without unmigrated attribution columns.", exc)
        # Prune unmigrated columns (paid_by and beneficiary are already recorded in the raw_sms audit note)
        safe_payload = dict(payload)
        safe_payload.pop("paid_by", None)
        safe_payload.pop("beneficiary", None)
        try:
            response = client.table("transactions").insert(safe_payload).execute()
        except Exception as exc2:
            logger.warning("Insert without paid_by/beneficiary failed (%s), pruning advanced optional columns.", exc2)
            safe_payload.pop("qr_code_raw", None)
            safe_payload.pop("dedup_fingerprint", None)
            try:
                response = client.table("transactions").insert(safe_payload).execute()
            except Exception as exc3:
                logger.warning("Falling back to core payload (preserving sub_category): %s", exc3)
                base_payload = {
                    "household_id": household_id,
                    "user_id": user_id,
                    "amount": amount,
                    "currency": currency,
                    "merchant": merchant,
                    "category_code": category_code,
                    "timestamp": timestamp,
                    "raw_sms": raw_sms,
                    "is_reallocated": is_reallocated,
                    "reallocated_from_budget_id": reallocated_from_budget_id,
                    "source": source,
                }
                if sub_category:
                    base_payload["sub_category"] = sub_category
                if cycle_key:
                    base_payload["cycle_key"] = cycle_key
                if spent_by:
                    base_payload["spent_by"] = spent_by
                base_payload.update(nafaqah_fields)
                response = client.table("transactions").insert(base_payload).execute()

    transaction_id = response.data[0]["id"]
    logger.info(
        "Transaction inserted: id=%s amount=%.2f %s merchant=%s category=%s sub_category=%s cycle=%s reallocated=%s source=%s",
        transaction_id, amount, currency, merchant, category_code, sub_category, cycle_key, is_reallocated, source,
    )
    try:
        from installment_service import InstallmentService
        InstallmentService.recalculate_budgets(household_id, cycle_key)
    except Exception as recalc_err:
        logger.debug("Background recalculate_budgets on insert failed: %s", recalc_err)

    return transaction_id


def ensure_household_cycle_budgets(
    household_id: str,
    target_date: Optional[date] = None,
    payday_day: Optional[int] = None,
) -> list[dict]:
    """
    Ensure budget allocation rows exist for the salary cycle corresponding to target_date.
    If rows exist for cycle_key, return them.
    If missing, automatically roll over from the most recent active cycle.
    """
    from salary_cycle import get_cycle_for_date
    if payday_day is None:
        payday_day = get_household_payday(household_id)
    cycle_info = get_cycle_for_date(target_date, payday_day=payday_day)
    cycle_key = cycle_info["cycle_key"]
    client = get_client()

    # 1. Check existing for this cycle
    existing = client.table("budgets").select("*").eq("household_id", household_id).eq("cycle_key", cycle_key).execute().data
    if existing:
        return existing

    # Fallback check by month
    target_d = target_date or riyadh_today()
    month_str = target_d.replace(day=1).isoformat()
    existing_month = client.table("budgets").select("*").eq("household_id", household_id).eq("month", month_str).execute().data
    if existing_month:
        # Backfill cycle_key on them
        client.table("budgets").update({"cycle_key": cycle_key}).eq("household_id", household_id).eq("month", month_str).execute()
        for b in existing_month:
            b["cycle_key"] = cycle_key
        return existing_month

    # 2. Find latest previous cycle to roll over from
    all_prev = client.table("budgets").select("*").eq("household_id", household_id).order("month", desc=True).execute().data
    if not all_prev:
        return []

    # Group by latest month / cycle
    latest_month = all_prev[0]["month"]
    latest_rows = [b for b in all_prev if b["month"] == latest_month and b.get("is_active", True)]

    # 3. Create new cycle rows with rollover rule
    rollover_rule = get_household_rollover_rule(household_id)
    if rollover_rule == "send_to_savings":
        surplus = round(
            sum(
                max(0.0, float(prev.get("allocated_amount") or 0.0) - float(prev.get("spent_amount") or 0.0))
                for prev in latest_rows
            ),
            2,
        )
        if surplus > 0:
            add_household_savings_surplus(household_id, surplus, cycle_key)
            logger.info("Auto-swept cycle surplus of SAR %.2f to savings for household=%s cycle=%s", surplus, household_id, cycle_key)

    new_rows = []
    for prev in latest_rows:
        prev_allocated = float(prev.get("allocated_amount") or 0.0)
        prev_spent = float(prev.get("spent_amount") or 0.0)
        if rollover_rule == "rollover_to_categories":
            delta = round(prev_allocated - prev_spent, 2)
        else:
            delta = 0.0

        new_rows.append({
            "household_id": household_id,
            "month": month_str,
            "cycle_key": cycle_key,
            "category_code": prev["category_code"],
            "allocated_amount": prev_allocated,
            "spent_amount": 0.0,
            "previous_cycle_delta": delta,
            "is_active": True,
        })

    if new_rows:
        inserted = client.table("budgets").insert(new_rows).execute().data
        logger.info("Auto-rolled over %d budgets for household=%s cycle=%s (rule=%s)", len(new_rows), household_id, cycle_key, rollover_rule)
        return inserted

    return []


# =============================================================================
# HOUSEHOLD PAYDAY CONFIGURATION
# =============================================================================

HOUSEHOLD_SETTINGS_FILE = os.path.join(os.path.dirname(__file__), "data", "household_settings.json")


def get_household_payday(household_id: str) -> int:
    """
    Retrieves the payday day (1-31) for a household.
    Checks Supabase households.payday_day, falls back to local JSON cache, defaults to 27.
    """
    if not household_id:
        return 27
    try:
        client = get_client()
        row = first_row(client.table("households").select("payday_day").eq("id", household_id))
        if row and row.get("payday_day") is not None:
            return int(row["payday_day"])
    except Exception:
        pass

    try:
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
                if household_id in settings and "payday_day" in settings[household_id]:
                    return int(settings[household_id]["payday_day"])
    except Exception:
        pass

    return 27


def set_household_payday(household_id: str, payday_day: int) -> int:
    """
    Sets the payday day (1-31) for a household.
    Updates Supabase if column exists, and always caches in household_settings.json.
    """
    if not household_id:
        return 27
    payday_day = max(1, min(31, int(payday_day)))

    # 1. Update local storage
    try:
        os.makedirs(os.path.dirname(HOUSEHOLD_SETTINGS_FILE), exist_ok=True)
        settings = {}
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
        if household_id not in settings:
            settings[household_id] = {}
        settings[household_id]["payday_day"] = payday_day
        with open(HOUSEHOLD_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        logger.warning(f"Failed to persist household_settings.json: {e}")

    # 2. Update Supabase
    try:
        client = get_client()
        client.table("households").update({"payday_day": payday_day}).eq("id", household_id).execute()
    except Exception as e:
        logger.info(f"Supabase households.payday_day column update skipped (pending migration): {e}")

    return payday_day


def get_household_income(household_id: str) -> float:
    """
    Retrieves the monthly income (SAR) for a household.
    Checks Supabase households.monthly_income, falls back to local JSON cache, defaults to 0.0.
    """
    if not household_id:
        return 0.0
    try:
        client = get_client()
        row = first_row(client.table("households").select("monthly_income").eq("id", household_id))
        if row and row.get("monthly_income") is not None:
            return float(row["monthly_income"])
    except Exception:
        pass

    try:
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
                if household_id in settings and "monthly_income" in settings[household_id]:
                    return float(settings[household_id]["monthly_income"])
    except Exception:
        pass

    return 0.0


def set_household_income(household_id: str, monthly_income: float) -> float:
    """
    Sets the monthly income (SAR) for a household.
    Updates Supabase if column exists, and always caches in household_settings.json.
    """
    if not household_id:
        return 0.0
    monthly_income = max(0.0, float(monthly_income))

    # 1. Update local storage
    try:
        os.makedirs(os.path.dirname(HOUSEHOLD_SETTINGS_FILE), exist_ok=True)
        settings = {}
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
        if household_id not in settings:
            settings[household_id] = {}
        settings[household_id]["monthly_income"] = monthly_income
        with open(HOUSEHOLD_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        logger.warning(f"Failed to persist household_settings.json for income: {e}")

    # 2. Update Supabase
    try:
        client = get_client()
        client.table("households").update({"monthly_income": monthly_income}).eq("id", household_id).execute()
    except Exception as e:
        logger.info(f"Supabase households.monthly_income column update skipped: {e}")

    return monthly_income


# =============================================================================
# HOUSEHOLD ROLLOVER RULES & SAVINGS RESERVE
# =============================================================================

VALID_ROLLOVER_RULES = {"send_to_savings", "rollover_to_categories", "fresh_start"}
DEFAULT_ROLLOVER_RULE = "send_to_savings"


def get_household_rollover_rule(household_id: str) -> str:
    """
    Retrieves the rollover rule for a household.
    Options: 'send_to_savings' (default), 'rollover_to_categories', 'fresh_start'.
    """
    if not household_id:
        return DEFAULT_ROLLOVER_RULE
    try:
        client = get_client()
        row = first_row(client.table("households").select("rollover_rule").eq("id", household_id))
        if row and row.get("rollover_rule") in VALID_ROLLOVER_RULES:
            return str(row["rollover_rule"])
    except Exception:
        pass

    try:
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
                if household_id in settings and settings[household_id].get("rollover_rule") in VALID_ROLLOVER_RULES:
                    return str(settings[household_id]["rollover_rule"])
    except Exception:
        pass

    return DEFAULT_ROLLOVER_RULE


def set_household_rollover_rule(household_id: str, rollover_rule: str) -> str:
    """
    Sets the rollover rule for a household.
    Options: 'send_to_savings', 'rollover_to_categories', 'fresh_start'.
    """
    if not household_id:
        return DEFAULT_ROLLOVER_RULE

    rule = rollover_rule if rollover_rule in VALID_ROLLOVER_RULES else DEFAULT_ROLLOVER_RULE

    # 1. Update local storage
    try:
        os.makedirs(os.path.dirname(HOUSEHOLD_SETTINGS_FILE), exist_ok=True)
        settings = {}
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
        if household_id not in settings:
            settings[household_id] = {}
        settings[household_id]["rollover_rule"] = rule
        with open(HOUSEHOLD_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        logger.warning(f"Failed to persist household_settings.json for rollover_rule: {e}")

    # 2. Update Supabase
    try:
        client = get_client()
        client.table("households").update({"rollover_rule": rule}).eq("id", household_id).execute()
    except Exception as e:
        logger.info(f"Supabase households.rollover_rule column update skipped (pending migration): {e}")

    return rule


def add_household_savings_surplus(household_id: str, surplus: float, cycle_key: str) -> float:
    """
    Sweeps unspent positive cycle surplus into the household's accumulated savings pool.
    Updates Supabase households table and syncs local cache.
    """
    if not household_id or surplus <= 0:
        return 0.0

    accumulated: Optional[float] = None
    # 1. Update Supabase — only authoritative when the household row actually exists;
    #    otherwise computing from 0 would overwrite the running total kept in the local cache.
    try:
        client = get_client()
        row = first_row(client.table("households").select("accumulated_savings").eq("id", household_id))
        if row:
            current_savings = float(row.get("accumulated_savings") or 0.0)
            accumulated = round(current_savings + float(surplus), 2)
            client.table("households").update({
                "accumulated_savings": accumulated,
                "last_rollover_surplus": round(float(surplus), 2),
                "last_rollover_cycle": cycle_key,
            }).eq("id", household_id).execute()
    except Exception as e:
        logger.info(f"Supabase update of accumulated_savings skipped: {e}")

    # 2. Update local fallback cache
    try:
        os.makedirs(os.path.dirname(HOUSEHOLD_SETTINGS_FILE), exist_ok=True)
        settings = {}
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
        if household_id not in settings:
            settings[household_id] = {}

        if accumulated is None:
            accumulated = float(settings[household_id].get("accumulated_savings") or 0.0) + round(surplus, 2)
        settings[household_id]["accumulated_savings"] = round(accumulated, 2)
        settings[household_id]["last_rollover_surplus"] = round(surplus, 2)
        settings[household_id]["last_rollover_cycle"] = cycle_key

        with open(HOUSEHOLD_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
    except Exception as e:
        logger.warning(f"Failed to record savings surplus in household_settings.json: {e}")

    return float(accumulated) if accumulated is not None else round(float(surplus), 2)


def get_household_savings_summary(household_id: str) -> dict:
    """
    Returns accumulated savings surplus and configured rollover rule.
    Queries Supabase first, falls back to local cache.
    """
    rule = get_household_rollover_rule(household_id)
    accumulated = 0.0
    last_surplus = 0.0
    last_cycle = None

    try:
        client = get_client()
        row = first_row(
            client.table("households")
            .select("accumulated_savings, last_rollover_surplus, last_rollover_cycle")
            .eq("id", household_id)
        )
        if row:
            if row.get("accumulated_savings") is not None:
                accumulated = float(row["accumulated_savings"])
            if row.get("last_rollover_surplus") is not None:
                last_surplus = float(row["last_rollover_surplus"])
            last_cycle = row.get("last_rollover_cycle")
            return {
                "household_id": household_id,
                "rollover_rule": rule,
                "accumulated_savings": round(accumulated, 2),
                "last_rollover_surplus": round(last_surplus, 2),
                "last_rollover_cycle": last_cycle,
            }
    except Exception:
        pass

    try:
        if os.path.exists(HOUSEHOLD_SETTINGS_FILE):
            with open(HOUSEHOLD_SETTINGS_FILE, "r", encoding="utf-8") as f:
                settings = json.load(f)
                if household_id in settings:
                    accumulated = float(settings[household_id].get("accumulated_savings") or 0.0)
                    last_surplus = float(settings[household_id].get("last_rollover_surplus") or 0.0)
                    last_cycle = settings[household_id].get("last_rollover_cycle")
    except Exception:
        pass

    return {
        "household_id": household_id,
        "rollover_rule": rule,
        "accumulated_savings": round(accumulated, 2),
        "last_rollover_surplus": round(last_surplus, 2),
        "last_rollover_cycle": last_cycle,
    }


# =============================================================================
# ROLE-BASED HOUSEHOLD INVITES & REIMBURSEMENT TRANSACTIONS
# =============================================================================

HOUSEHOLD_INVITES_FILE = os.path.join(os.path.dirname(__file__), "data", "household_invites.json")


def is_supabase_configured() -> bool:
    """Return True if Supabase credentials are configured in environment."""
    url = (os.environ.get("SUPABASE_URL") or "").strip()
    return bool(url and describe_supabase_key()["key"])


def create_household_role_invite(
    household_id: str,
    role: str,
    target_member_id: Optional[str] = None,
) -> dict:
    """
    Creates a 16-character invite code for a specific role ('spouse', 'peer', 'family_member').
    Optionally binds the invite code to a pre-created manual member (target_member_id).
    Persists to Supabase household_invites table when configured, with JSON cache fallback only when offline.
    """
    import secrets
    from datetime import datetime, timezone, timedelta

    code = secrets.token_hex(8).upper()
    expires_at = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()
    norm_role = role if role in ("spouse", "peer", "family_member", "dependent") else "peer"

    invite_data = {
        "household_id": household_id,
        "invite_code": code,
        "role": norm_role,
        "target_member_id": target_member_id,
        "expires_at": expires_at,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    if is_supabase_configured():
        client = get_client()
        client.table("household_invites").insert(invite_data).execute()
        return invite_data

    # Local file fallback ONLY when Supabase is not configured
    try:
        os.makedirs(os.path.dirname(HOUSEHOLD_INVITES_FILE), exist_ok=True)
        invites = {}
        if os.path.exists(HOUSEHOLD_INVITES_FILE):
            with open(HOUSEHOLD_INVITES_FILE, "r", encoding="utf-8") as f:
                invites = json.load(f)
        invites[code] = invite_data
        with open(HOUSEHOLD_INVITES_FILE, "w", encoding="utf-8") as f:
            json.dump(invites, f, indent=2)
    except Exception as e:
        logger.warning(f"Failed to persist household_invites.json: {e}")

    return invite_data


def inspect_household_role_invite(invite_code: str) -> dict:
    """
    Retrieves metadata for an invite code: household_id, assigned role, target_member_id, expiry.
    """
    code = invite_code.strip().upper()
    if is_supabase_configured():
        try:
            client = get_client()
            res = client.table("household_invites").select("*").eq("invite_code", code).maybe_single().execute()
            if res and hasattr(res, "data") and res.data:
                inv = res.data
                is_valid = True
                if inv.get("used_by"):
                    is_valid = False
                if inv.get("expires_at"):
                    try:
                        exp = datetime.fromisoformat(inv["expires_at"].replace("Z", "+00:00"))
                        if exp < datetime.now(timezone.utc):
                            is_valid = False
                    except Exception:
                        pass
                inv["is_valid"] = is_valid
                target_member_id = inv.get("target_member_id")
                if target_member_id:
                    try:
                        dep_res = client.table("household_dependents").select("name").eq("id", target_member_id).maybe_single().execute()
                        if dep_res and hasattr(dep_res, "data") and dep_res.data:
                            inv["target_member_name"] = dep_res.data.get("name")
                    except Exception as dep_exc:
                        logger.warning("Could not resolve target_member_name: %s", dep_exc)
                return inv
        except Exception as exc:
            logger.warning("Supabase inspect invite query failed: %s", exc)
        return {
            "invite_code": code,
            "household_id": None,
            "role": "peer",
            "target_member_id": None,
            "target_member_name": None,
            "is_valid": False,
        }

    # Fallback ONLY when Supabase is not configured
    try:
        if os.path.exists(HOUSEHOLD_INVITES_FILE):
            with open(HOUSEHOLD_INVITES_FILE, "r", encoding="utf-8") as f:
                invites = json.load(f)
                if code in invites:
                    data = dict(invites[code])
                    data["is_valid"] = not bool(data.get("used_by"))
                    return data
    except Exception:
        pass

    return {
        "invite_code": code,
        "household_id": None,
        "role": "peer",
        "target_member_id": None,
        "is_valid": False,
    }


def claim_household_role_invite(invite_code: str, user_id: str) -> dict:
    """
    Claims a household invite for a user atomically:
    1. If Supabase is configured: calls the atomic claim_household_role_invite RPC.
    2. If Supabase is not configured: claims locally via file cache fallback.
    """
    code = invite_code.strip().upper()

    if is_supabase_configured():
        try:
            client = get_client()
            res = client.rpc("claim_household_role_invite", {
                "p_invite_code": code,
                "p_user_id": user_id,
            }).execute()
            if res and hasattr(res, "data") and isinstance(res.data, dict):
                data = res.data
                if not data.get("success"):
                    message = str(data.get("error") or "Invite code is invalid or expired.")
                    if "too many failed join attempts" in message.lower():
                        return {"status": "error", "code": "rate_limited", "error": message}
                    return {"status": "error", "error": message}
                return {
                    "status": "success",
                    "household_id": data.get("household_id"),
                    "user_id": user_id,
                    "linked_member_id": data.get("target_member_id"),
                    "financial_role": data.get("role"),
                }
        except Exception as exc:
            logger.error("Supabase claim_household_role_invite RPC error: %s", exc)
            # Never echo raw database errors to the client. The DB lockout (repeated failed
            # join attempts) is surfaced distinctly so the route can answer 429.
            if "too many failed join attempts" in str(exc).lower():
                return {
                    "status": "error",
                    "code": "rate_limited",
                    "error": "Too many failed join attempts. Please try again later.",
                }
            return {"status": "error", "error": "Invite code is invalid, expired or could not be claimed."}

    # Fallback ONLY when Supabase is not configured
    try:
        inv = inspect_household_role_invite(code)
        if not inv or not inv.get("is_valid", True):
            return {"status": "error", "error": "Invite code is invalid or expired."}
        if inv.get("used_by"):
            return {"status": "error", "error": "Invite code has already been used."}

        hid = inv.get("household_id")
        target_mid = inv.get("target_member_id")
        role = inv.get("role", "peer")

        if os.path.exists(HOUSEHOLD_INVITES_FILE):
            with open(HOUSEHOLD_INVITES_FILE, "r", encoding="utf-8") as f:
                invites = json.load(f)
            if code in invites and not invites[code].get("used_by"):
                invites[code]["used_by"] = user_id
                with open(HOUSEHOLD_INVITES_FILE, "w", encoding="utf-8") as f:
                    json.dump(invites, f, indent=2)
            else:
                return {"status": "error", "error": "Invite code has already been used or expired."}

        return {
            "status": "success",
            "household_id": hid,
            "user_id": user_id,
            "linked_member_id": target_mid,
            "financial_role": role,
        }
    except Exception as e:
        logger.error("Failed to claim household invite (fallback): %s", e)
        return {"status": "error", "error": str(e)}




def record_household_reimbursement(
    household_id: str,
    payer_id: str,
    recipient_id: str,
    amount: Any,
    payment_method: str = "stc_pay",
    notes: Optional[str] = None,
    recorded_by: Optional[str] = None,
) -> dict:
    """
    Records a roommate/partner settlement payment (``payer_id`` paid ``recipient_id``).

    Only columns that exist on ``public.transactions`` are written (FR-B-01: there is no
    ``paid_by`` or ``notes`` column and no ``OPEX-SETTLEMENT`` category, so the previous payload
    was rejected on every call). The payer is kept in the ``PaidBy:`` audit tag of ``raw_sms``
    (the tag chat entries use), the recipient in ``beneficiary_id`` / ``settlement_target_id``,
    and ``category_code`` stays NULL so a settlement is never counted as spending in a budget
    category. ``recorded_by`` (the verified caller) is the transaction's creator (DB-18).
    """
    import uuid
    from decimal import Decimal

    tx_id = str(uuid.uuid4())
    now_iso = datetime.now(timezone.utc).isoformat()
    value = Decimal(str(amount)).quantize(Decimal("0.01"))
    method = (payment_method or "").strip().upper() or "OTHER"
    # One audit part per tag: a "|" inside the note must not create a second PaidBy tag.
    note_text = " ".join((notes or "").replace("|", "/").split())[:500]
    audit = f"Settlement | PaidBy: {payer_id} | Recipient: {recipient_id} | Method: {method}"
    if note_text:
        audit += f" | Note: {note_text}"

    tx_data = {
        "id": tx_id,
        "household_id": household_id,
        "user_id": recorded_by,
        # Exact decimal text: PostgREST casts it to numeric(14,2) without a float round trip.
        "amount": format(value, "f"),
        "currency": "SAR",
        "merchant": f"Settlement Reimbursement ({method})",
        "category_code": None,
        "beneficiary_type": "individual",
        "beneficiary_id": recipient_id,
        "settlement_target_id": recipient_id,
        "is_settlement": True,
        "source": "manual",
        "raw_sms": audit,
        "timestamp": now_iso,
    }

    # Persist. A failed insert must propagate: it used to be swallowed and the endpoint still
    # answered "success", so the client believed a settlement was recorded that never existed.
    client = get_client()
    client.table("transactions").insert(tx_data).execute()

    return {
        "status": "success",
        "transaction_id": tx_id,
        "household_id": household_id,
        "amount": float(value),
        "payer_id": payer_id,
        "recipient_id": recipient_id,
        "is_settlement": True,
        "timestamp": now_iso,
    }



