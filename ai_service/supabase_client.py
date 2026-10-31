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


def fetch_household_cost_control_codes(household_id: str, force_refresh: bool = False) -> list[CostControlCode]:
    """
    Load the cost control codes applicable to this household:
    1. System/global codes + household's custom codes.
    2. Filter out codes that are deactivated in household_category_settings.
    """
    if not household_id:
        return fetch_all_cost_control_codes(force_refresh=force_refresh)

    try:
        from salary_cycle import get_household_categories
        cats = get_household_categories(household_id)
        active_list = cats.get("active", [])
        if active_list:
            res: list[CostControlCode] = []
            for c in active_list:
                res.append(CostControlCode(
                    code=c.get("code") or "",
                    category=c.get("category") or "",
                    is_flexible=bool(c.get("is_flexible", False)),
                    keywords=list(c.get("keywords") or []),
                    is_system=bool(c.get("is_system", False)),
                    household_id=c.get("household_id")
                ))
            return res
    except Exception as exc:
        logger.warning("Could not fetch household-scoped categories for %s: %s", household_id, exc)

    return fetch_all_cost_control_codes(force_refresh=force_refresh)


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


class UnknownCategoryError(ValueError):
    """
    A transaction's category code is in neither the global taxonomy nor the household's own
    categories (E2E-03). The DB trigger validate_category_code_exists refuses it with 23503;
    routes answer 422 with ``PUBLIC_MESSAGE`` and never echo the database text.
    """

    PUBLIC_MESSAGE = "Unknown category_code: choose one of your household's categories."

    def __init__(self, message: str = PUBLIC_MESSAGE):
        super().__init__(message)


class InvalidAttributionError(ValueError):
    """
    ``paid_by`` / ``beneficiary`` of an expense name nobody in the household (e.g. 'partner' in a
    flat of three). Routes answer 422 with the message, which never contains database text.
    """


class TransactionRejectedError(ValueError):
    """
    The database refused a transaction write with a constraint or permission error (FABLE2-API-01).
    Retrying with fewer columns cannot help, so it is raised at once. Routes answer
    ``status_code`` (403 permission, 409 conflict, 422 otherwise) with ``PUBLIC_MESSAGE``: the
    database text is never echoed.
    """

    PUBLIC_MESSAGE = "The database rejected this transaction."
    _STATUS = {"42501": 403, "23505": 409}

    def __init__(self, sqlstate: str):
        super().__init__(self.PUBLIC_MESSAGE)
        self.sqlstate = sqlstate

    @property
    def status_code(self) -> int:
        return self._STATUS.get(self.sqlstate, 422)


# SQLSTATEs of refusals that a pruned payload cannot fix (check/trigger constraint, invalid
# parameter, foreign key, row-level security / forbidden, unique violation).
FINAL_DB_REFUSAL_CODES = frozenset({"23514", "22023", "23503", "42501", "23505"})


def final_transaction_db_error(exc: BaseException) -> Optional[Exception]:
    """
    The error to raise instead of retrying when ``exc`` is a final database refusal of a
    transaction write, else None. The Nafaqah triggers' hints map to the service's errors (routes
    answer 409 ``no_provider`` / ``ledger_would_be_overpaid``); an unknown category code to
    UnknownCategoryError; any other constraint or permission refusal to TransactionRejectedError.
    """
    from nafaqah_service import LedgerWouldBeOverpaid, NoProviderError
    from postgrest_compat import db_error_fields

    fields = db_error_fields(exc)
    code, hint = fields["code"], fields["hint"]
    if hint == "no_nafaqah_provider":
        return NoProviderError("This family has no Nafaqah provider: a household admin must choose one.")
    if hint == "ledger_would_be_overpaid":
        return LedgerWouldBeOverpaid(
            "This change would leave the wife's reimbursement ledger overpaid: the husband already repaid more."
        )
    if is_unknown_category_db_error(exc):
        return UnknownCategoryError()
    if code in FINAL_DB_REFUSAL_CODES:
        return TransactionRejectedError(code)
    return None


def is_unknown_category_db_error(exc: BaseException) -> bool:
    """True for validate_category_code_exists' refusal (SQLSTATE 23503 'Category code ...')."""
    from postgrest_compat import db_error_fields

    fields = db_error_fields(exc)
    return fields["code"] == "23503" and "Category code" in fields["message"]


def category_code_in_taxonomy(household_id: str, category_code: str) -> Optional[bool]:
    """
    Whether ``category_code`` is a global code or one of ``household_id``'s own codes, the same
    rule as the DB trigger validate_category_code_exists. Queried live (not the 5-minute code
    cache) so a category created a moment ago is accepted. None when the lookup itself fails:
    the caller then lets the database decide.
    """
    try:
        rows = (
            get_client()
            .table("cost_control_codes")
            .select("household_id")
            .eq("code", category_code)
            .execute()
            .data
            or []
        )
    except Exception as exc:
        logger.warning("Category code lookup failed: %s", exc)
        return None
    return any(r.get("household_id") in (None, household_id) for r in rows)


def household_attribution(
    household_id: str,
    user_id: Optional[str],
    paid_by: Optional[str],
    beneficiary: Optional[str],
    spouse_id: Optional[str] = None,
    nafaqah_class: Optional[str] = None,
) -> dict:
    """
    ``{spent_by, beneficiary_type, beneficiary_id}`` for an expense ``user_id`` records in
    ``household_id`` (settlement_engine.structured_attribution against the household roster).
    Raises InvalidAttributionError when 'partner' names nobody. If the roster cannot be read the
    relative token is stored and resolved by the settlement engines when they read the row.

    With a ``nafaqah_class`` to store, a family without a provider is refused here with
    NoProviderError (HTTP 409 ``no_provider``), before any budget is reallocated: the database
    trigger would refuse the insert anyway (FABLE2-API-01).
    """
    from nafaqah_service import NoProviderError, load_family_context
    from settlement_engine import structured_attribution

    try:
        ctx = load_family_context(household_id)
    except Exception as exc:
        logger.warning("Household roster unavailable for attribution (%s); storing relative tokens.", exc)
        ctx = None
    if nafaqah_class and ctx is not None and getattr(ctx, "needs_provider", False):
        raise NoProviderError("This family has no Nafaqah provider: a household admin must choose one.")
    return structured_attribution(ctx, user_id, paid_by, beneficiary, spouse_id=spouse_id)


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
    beneficiary_type: Optional[str] = None,
    beneficiary_id: Optional[str] = None,
    account_id: Optional[str] = None,
) -> str:
    """
    Insert a new transaction row and return its UUID.

    Who paid and for whom are stored in columns (FABLE-API-01 / FABLE-LOGIC-03): ``spent_by`` is
    the payer relative to the creator ('me' | 'partner') and ``beneficiary_type`` /
    ``beneficiary_id`` the beneficiary (settlement_engine.structured_attribution). Callers pass
    the three columns, or ``paid_by`` / ``beneficiary`` and they are derived here (raising
    InvalidAttributionError when 'partner' names nobody). The settlement engines read these
    columns, never the free text of ``raw_sms``.

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
    if beneficiary_id is None and (paid_by is not None or beneficiary is not None):
        attribution = household_attribution(household_id, user_id, paid_by, beneficiary, nafaqah_spouse_id)
        spent_by = attribution["spent_by"]
        beneficiary_type, beneficiary_id = attribution["beneficiary_type"], attribution["beneficiary_id"]
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
            sub_category = match_sub_category(category_code, f"{merchant} {raw_sms}", items, household_id=household_id)
        except Exception:
            pass

    # Rule 02.3: Wife personal allowance is isolated from husband's / operating pool accounts
    if nafaqah_class == "wife_personal":
        account_id = None

    # Automatically resolve account_id if not supplied
    if not account_id and nafaqah_class != "wife_personal":
        try:
            b_res = (
                client.table("budgets")
                .select("account_id")
                .eq("household_id", household_id)
                .eq("category_code", category_code)
                .eq("is_active", True)
                .execute()
            )
            if b_res.data:
                for b_row in b_res.data:
                    if b_row.get("account_id"):
                        account_id = b_row["account_id"]
                        break
        except Exception as e:
            logger.debug("Failed checking budget account: %s", e)

        if not account_id:
            try:
                accs_res = (
                    client.table("accounts")
                    .select("id, account_type, is_shared_pool, balance")
                    .eq("household_id", household_id)
                    .eq("is_archived", False)
                    .execute()
                )
                if accs_res.data:
                    pool_acc = next(
                        (a for a in accs_res.data if a.get("is_shared_pool") or a.get("account_type") in ("checking", "primary_operating")),
                        accs_res.data[0]
                    )
                    account_id = pool_acc.get("id")
            except Exception as e:
                logger.debug("Failed finding default operating account: %s", e)

    bal_before = None
    if account_id:
        try:
            cur_acc = client.table("accounts").select("balance").eq("id", account_id).execute()
            if cur_acc.data:
                bal_before = float(cur_acc.data[0].get("balance") or 0.0)
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
    if account_id:
        payload["account_id"] = account_id
    if items:
        payload["items"] = items
    if receipt_url:
        payload["receipt_url"] = receipt_url
    if spent_by:
        payload["spent_by"] = spent_by
    # paid_by / beneficiary are not columns of public.transactions (live and the repo schema
    # agree; sending them made every first insert attempt fail, FR-B-11): they are stored as
    # spent_by + beneficiary_type/beneficiary_id, which the settlement engines read.
    attribution_fields = (
        {"beneficiary_type": beneficiary_type or "household", "beneficiary_id": beneficiary_id}
        if beneficiary_id
        else {}
    )
    payload.update(attribution_fields)
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


    # A constraint or permission refusal (an unknown category code, E2E-03; a family without a
    # provider; RLS) is final, never a schema mismatch: retrying with a pruned payload cannot help,
    # sent the same refused row three times and surfaced as a 500 (FABLE2-API-01).
    try:
        response = client.table("transactions").insert(payload).execute()
    except Exception as exc:
        final = final_transaction_db_error(exc)
        if final is not None:
            raise final from exc
        logger.warning("Insert with initial payload failed (%s), pruning advanced optional columns.", exc)
        safe_payload = dict(payload)
        safe_payload.pop("qr_code_raw", None)
        safe_payload.pop("dedup_fingerprint", None)
        try:
            response = client.table("transactions").insert(safe_payload).execute()
        except Exception as exc3:
            final = final_transaction_db_error(exc3)
            if final is not None:
                raise final from exc3
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
            if account_id:
                base_payload["account_id"] = account_id
            # Never pruned: without them the expense would be split among every member.
            base_payload.update(attribution_fields)
            base_payload.update(nafaqah_fields)
            try:
                response = client.table("transactions").insert(base_payload).execute()
            except Exception as exc4:
                final = final_transaction_db_error(exc4)
                if final is not None:
                    raise final from exc4
                raise

    transaction_id = response.data[0]["id"]

    # Synchronize account balance if the database trigger did not decrement it
    if account_id and bal_before is not None and nafaqah_class != "wife_personal":
        try:
            cur_acc_after = client.table("accounts").select("balance").eq("id", account_id).execute()
            if cur_acc_after.data:
                bal_after = float(cur_acc_after.data[0].get("balance") or 0.0)
                if abs(bal_after - bal_before) < 0.001:
                    new_bal = max(0.0, round(bal_before - float(amount), 2))
                    from utils import utc_now
                    client.table("accounts").update({
                        "balance": new_bal,
                        "updated_at": utc_now().isoformat()
                    }).eq("id", account_id).execute()
                    logger.info("Synchronized account %s balance from %.2f to %.2f", account_id, bal_before, new_bal)
        except Exception as e:
            logger.warning("Failed balance synchronization for account %s: %s", account_id, e)

    logger.info(
        "Transaction inserted: id=%s amount=%.2f %s merchant=%s category=%s sub_category=%s cycle=%s reallocated=%s source=%s",
        transaction_id, amount, currency, merchant, category_code, sub_category, cycle_key, is_reallocated, source,
    )
    # budgets.spent_amount is maintained by the transaction triggers (BUG-02, 20261020800000 /
    # 20261020900000): no recalculation here. It used to read every transaction of the household
    # on each insert (product review 3.3); POST /budgets/recalculate repairs a cycle on demand.
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
    cycle_month_str = f"{cycle_key}-01"

    # 1. Fetch existing budgets for this target cycle
    existing_resp = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .eq("cycle_key", cycle_key)
        .execute()
    )
    existing = existing_resp.data if isinstance(getattr(existing_resp, "data", None), list) else []

    # 2. Fetch all budget rows to find prior cycle envelopes
    all_prev_resp = (
        client.table("budgets")
        .select("*")
        .eq("household_id", household_id)
        .order("month", desc=True)
        .execute()
    )
    all_prev = all_prev_resp.data if isinstance(getattr(all_prev_resp, "data", None), list) else []

    # If all_prev includes rows for cycle_key, merge them into existing
    existing_from_all = [
        b for b in all_prev
        if b.get("cycle_key") == cycle_key or (not b.get("cycle_key") and (b.get("month") or "")[:7] == cycle_key)
    ]
    if existing_from_all and not existing:
        existing = existing_from_all

    # Fallback: only backfill legacy rows that truly belong to this cycle where cycle_key is null.
    try:
        legacy_to_update = [b for b in existing if not b.get("cycle_key") and (b.get("month") or "") == cycle_month_str]
        if legacy_to_update:
            client.table("budgets").update({"cycle_key": cycle_key}).eq("household_id", household_id).eq("month", cycle_month_str).is_("cycle_key", "null").execute()
            for b in legacy_to_update:
                b["cycle_key"] = cycle_key
    except Exception as exc:
        logger.warning("Could not check legacy budget rows for household=%s cycle=%s: %s", household_id, cycle_key, exc)

    # 2. Find latest previous cycle that has active budgets (strictly earlier than cycle_key)
    prior_budgets = [
        b for b in all_prev
        if (b.get("cycle_key") or (b.get("month") or "")[:7]) < cycle_key
        and b.get("is_active", True) is not False
    ]
    if not prior_budgets:
        return existing

    # Find the maximum previous cycle key
    prior_cycle_keys = sorted(
        {b.get("cycle_key") or (b.get("month") or "")[:7] for b in prior_budgets},
        reverse=True,
    )
    latest_prev_key = prior_cycle_keys[0] if prior_cycle_keys else None
    if not latest_prev_key:
        return existing

    latest_rows = [
        b for b in prior_budgets
        if (b.get("cycle_key") == latest_prev_key or (not b.get("cycle_key") and (b.get("month") or "")[:7] == latest_prev_key))
        and b.get("is_active", True) is not False
    ]
    if not latest_rows:
        return existing

    # 3. Determine which categories are missing from target cycle
    existing_codes = {b.get("category_code") for b in existing}
    missing_prev_rows = [b for b in latest_rows if b.get("category_code") not in existing_codes]

    if not missing_prev_rows:
        return existing

    # 4. Create new cycle rows with rollover rule and sinking funds
    rollover_rule = get_household_rollover_rule(household_id)

    total_surplus = 0.0
    new_rows = []

    for prev in missing_prev_rows:
        prev_allocated = float(prev.get("allocated_amount") or 0.0)
        prev_spent = float(prev.get("spent_amount") or 0.0)
        sub_allocs = prev.get("sub_allocations") or {}
        sinking_cfg = sub_allocs.get("_sinking_fund") if isinstance(sub_allocs, dict) else {}
        if not isinstance(sinking_cfg, dict):
            sinking_cfg = {}

        numeric_subs = {
            k: float(v) for k, v in sub_allocs.items()
            if not k.startswith("_") and isinstance(v, (int, float))
        }

        delta = 0.0
        if sinking_cfg:
            if numeric_subs:
                new_sub_numeric = {}
                for sc, prev_sub_alloc in numeric_subs.items():
                    sc_cfg = sinking_cfg.get(sc) if isinstance(sinking_cfg, dict) else None
                    accumulate = bool(sc_cfg.get("accumulate")) if isinstance(sc_cfg, dict) else False
                    base_amt = float(sc_cfg.get("base_amount", prev_sub_alloc)) if isinstance(sc_cfg, dict) else prev_sub_alloc

                    ratio = (prev_sub_alloc / prev_allocated) if prev_allocated > 0 else 0.0
                    sub_spent = round(prev_spent * ratio, 2)
                    unspent = max(0.0, prev_sub_alloc - sub_spent)

                    if accumulate:
                        new_sub_alloc = round(base_amt + unspent, 2)
                    else:
                        new_sub_alloc = round(base_amt, 2)
                        total_surplus += unspent

                    new_sub_numeric[sc] = new_sub_alloc

                new_allocated = round(sum(new_sub_numeric.values()), 2)
                new_sub_allocations = {**sub_allocs, **new_sub_numeric}
                delta = round(max(0.0, new_allocated - sum(
                    float(sinking_cfg.get(sc, {}).get("base_amount", numeric_subs[sc])) if isinstance(sinking_cfg.get(sc), dict) else numeric_subs[sc]
                    for sc in numeric_subs
                )), 2)
            else:
                parent_cfg = sinking_cfg.get("_parent") or sinking_cfg.get("_self") if isinstance(sinking_cfg, dict) else None
                accumulate = bool(parent_cfg.get("accumulate")) if isinstance(parent_cfg, dict) else (rollover_rule == "rollover_to_categories")
                base_amt = float(parent_cfg.get("base_amount", prev_allocated)) if isinstance(parent_cfg, dict) else prev_allocated

                unspent = max(0.0, prev_allocated - prev_spent)
                if accumulate:
                    new_allocated = round(base_amt + unspent, 2)
                    delta = round(unspent, 2)
                else:
                    new_allocated = round(base_amt, 2)
                    delta = 0.0
                    total_surplus += unspent

                new_sub_allocations = sub_allocs
        else:
            # Standard rollover without sinking fund
            new_allocated = prev_allocated
            new_sub_allocations = sub_allocs
            if rollover_rule == "rollover_to_categories":
                delta = round(prev_allocated - prev_spent, 2)
            else:
                delta = 0.0
                total_surplus += max(0.0, prev_allocated - prev_spent)

        new_rows.append({
            "household_id": household_id,
            "month": cycle_month_str,
            "cycle_key": cycle_key,
            "category_code": prev["category_code"],
            "allocated_amount": new_allocated,
            "sub_allocations": new_sub_allocations,
            "account_id": prev.get("account_id"),
            "spent_amount": 0.0,
            "previous_cycle_delta": delta,
            "is_active": True,
        })

    if not existing and rollover_rule == "send_to_savings" and total_surplus > 0:
        total_surplus = round(total_surplus, 2)
        add_household_savings_surplus(household_id, total_surplus, cycle_key)
        logger.info("Auto-swept cycle surplus of SAR %.2f to savings for household=%s cycle=%s", total_surplus, household_id, cycle_key)

    if new_rows:
        inserted = client.table("budgets").insert(new_rows).execute().data or []
        logger.info("Auto-rolled over %d missing budgets for household=%s cycle=%s (rule=%s)", len(new_rows), household_id, cycle_key, rollover_rule)
        return list(existing) + list(inserted)

    return existing


# =============================================================================
# HOUSEHOLD SETTINGS (payday, income, rollover rule, savings reserve)
# =============================================================================
# The database is the only store (product review 4.1, API-33): the container-local JSON files
# (household_settings.json / household_invites.json) were ephemeral on Railway and diverged
# between instances. A failed read or write raises HouseholdSettingsUnavailable; the routes answer
# with an error instead of serving or "saving" a value no other instance can see.

DEFAULT_PAYDAY_DAY = 27


class HouseholdSettingsUnavailable(RuntimeError):
    """The households row could not be read or written (database unreachable or refused)."""

    PUBLIC_MESSAGE = "Household settings are temporarily unavailable. Please try again."

    def __init__(self, operation: str):
        super().__init__(f"{self.PUBLIC_MESSAGE} ({operation})")
        self.operation = operation


def _household_row(household_id: str, columns: str, operation: str) -> Optional[dict]:
    try:
        return first_row(get_client().table("households").select(columns).eq("id", household_id))
    except Exception as exc:
        logger.error("Could not read households.%s for %s: %s", columns, household_id, exc)
        raise HouseholdSettingsUnavailable(operation) from exc


def _update_household(household_id: str, values: dict, operation: str) -> None:
    try:
        get_client().table("households").update(values).eq("id", household_id).execute()
    except Exception as exc:
        logger.error("Could not update households (%s) for %s: %s", ", ".join(values), household_id, exc)
        raise HouseholdSettingsUnavailable(operation) from exc


def get_household_payday(household_id: str) -> int:
    """households.payday_day (1-31); 27 when the household has none (or no id is given)."""
    if not household_id:
        return DEFAULT_PAYDAY_DAY
    row = _household_row(household_id, "payday_day", "read payday")
    if row and row.get("payday_day") is not None:
        return int(row["payday_day"])
    return DEFAULT_PAYDAY_DAY


def set_household_payday(household_id: str, payday_day: int) -> int:
    """Store households.payday_day (clamped to 1-31); the DB trigger re-keys the open cycle."""
    if not household_id:
        return DEFAULT_PAYDAY_DAY
    payday_day = max(1, min(31, int(payday_day)))
    _update_household(household_id, {"payday_day": payday_day}, "update payday")
    return payday_day


def get_household_income(household_id: str) -> float:
    """households.monthly_income (SAR); 0.0 when unset."""
    if not household_id:
        return 0.0
    row = _household_row(household_id, "monthly_income", "read income")
    if row and row.get("monthly_income") is not None:
        return float(row["monthly_income"])
    return 0.0


def set_household_income(household_id: str, monthly_income: float) -> float:
    """Store households.monthly_income (SAR, never negative)."""
    if not household_id:
        return 0.0
    monthly_income = max(0.0, float(monthly_income))
    _update_household(household_id, {"monthly_income": monthly_income}, "update income")
    return monthly_income


# =============================================================================
# HOUSEHOLD ROLLOVER RULES & SAVINGS RESERVE
# =============================================================================

VALID_ROLLOVER_RULES = {"send_to_savings", "rollover_to_categories", "fresh_start"}
DEFAULT_ROLLOVER_RULE = "send_to_savings"


def get_household_rollover_rule(household_id: str) -> str:
    """
    households.rollover_rule: 'send_to_savings' (default), 'rollover_to_categories' or
    'fresh_start'.
    """
    if not household_id:
        return DEFAULT_ROLLOVER_RULE
    row = _household_row(household_id, "rollover_rule", "read rollover rule")
    if row and row.get("rollover_rule") in VALID_ROLLOVER_RULES:
        return str(row["rollover_rule"])
    return DEFAULT_ROLLOVER_RULE


def set_household_rollover_rule(household_id: str, rollover_rule: str) -> str:
    """Store households.rollover_rule (an unknown value stores the default)."""
    if not household_id:
        return DEFAULT_ROLLOVER_RULE
    rule = rollover_rule if rollover_rule in VALID_ROLLOVER_RULES else DEFAULT_ROLLOVER_RULE
    _update_household(household_id, {"rollover_rule": rule}, "update rollover rule")
    return rule


def add_household_savings_surplus(household_id: str, surplus: float, cycle_key: str) -> float:
    """
    Sweep a positive cycle surplus into households.accumulated_savings and return the new total.
    Raises HouseholdSettingsUnavailable when the household row cannot be read or written.
    """
    if not household_id or surplus <= 0:
        return 0.0
    row = _household_row(household_id, "accumulated_savings", "read savings")
    if not row:
        raise HouseholdSettingsUnavailable("household not found")
    accumulated = round(float(row.get("accumulated_savings") or 0.0) + float(surplus), 2)
    _update_household(household_id, {
        "accumulated_savings": accumulated,
        "last_rollover_surplus": round(float(surplus), 2),
        "last_rollover_cycle": cycle_key,
    }, "update savings")
    return accumulated


def get_household_savings_summary(household_id: str) -> dict:
    """Accumulated savings, the last swept surplus and the rollover rule of a household."""
    rule = get_household_rollover_rule(household_id)
    row = _household_row(
        household_id, "accumulated_savings, last_rollover_surplus, last_rollover_cycle", "read savings",
    ) or {}
    return {
        "household_id": household_id,
        "rollover_rule": rule,
        "accumulated_savings": round(float(row.get("accumulated_savings") or 0.0), 2),
        "last_rollover_surplus": round(float(row.get("last_rollover_surplus") or 0.0), 2),
        "last_rollover_cycle": row.get("last_rollover_cycle"),
    }


# =============================================================================
# ROLE-BASED HOUSEHOLD INVITES & REIMBURSEMENT TRANSACTIONS
# =============================================================================


def is_supabase_configured() -> bool:
    """Return True if Supabase credentials are configured in environment."""
    url = (os.environ.get("SUPABASE_URL") or "").strip()
    return bool(url and describe_supabase_key()["key"])


class InviteTargetNotFound(LookupError):
    """``target_member_id`` is not a dependent of the inviting household (HTTP 404)."""

    PUBLIC_MESSAGE = "target_member_id is not a member profile of this household."

    def __init__(self, message: str = PUBLIC_MESSAGE):
        super().__init__(message)


class InviteRejectedError(TransactionRejectedError):
    """The database refused the invite insert (403 / 409 / 422, never the database text)."""

    PUBLIC_MESSAGE = "The database rejected this invite."


def create_household_role_invite(
    household_id: str,
    role: str,
    target_member_id: Optional[str] = None,
) -> dict:
    """
    Creates a 16-character invite code for a specific role ('spouse', 'peer', 'family_member').
    Optionally binds the invite code to a pre-created manual member (target_member_id).
    Stored in household_invites only (no local file fallback): a failed insert raises.
    """
    import secrets
    from datetime import datetime, timezone, timedelta

    if target_member_id is not None:
        # FABLE2-API-06: the target must be a dependent (manual member) of this household; the
        # route checked it is a UUID (400). The DB trigger validate_invite_target_member enforces
        # the same rule; checking first answers 404 instead of a refused insert.
        res = (
            get_client()
            .table("household_dependents")
            .select("id, household_id")
            .eq("id", target_member_id)
            .eq("household_id", household_id)
            .execute()
        )
        data = getattr(res, "data", None)
        rows = data if isinstance(data, list) else ([data] if data else [])
        if not any(str(r.get("household_id")) == str(household_id) for r in rows if isinstance(r, dict)):
            raise InviteTargetNotFound()

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

    client = get_client()
    try:
        client.table("household_invites").insert(invite_data).execute()
    except Exception as exc:
        # A database refusal is the request's fault (4xx), never a 500 (FABLE2-API-06).
        from postgrest_compat import db_error_fields

        sqlstate = db_error_fields(exc)["code"]
        if sqlstate == "23503":
            raise InviteTargetNotFound() from exc
        if sqlstate in FINAL_DB_REFUSAL_CODES or sqlstate == "22P02":
            raise InviteRejectedError(sqlstate) from exc
        raise
    return invite_data


def inspect_household_role_invite(invite_code: str) -> dict:
    """
    Retrieves metadata for an invite code: household_id, assigned role, target_member_id, expiry.
    """
    code = invite_code.strip().upper()
    # A failed lookup raises (the route answers an error); it is never reported as an invalid code.
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
                # Only a dependent of the invite's own household is named (FABLE2-API-06).
                dep_res = (
                    client.table("household_dependents").select("name").eq("id", target_member_id)
                    .eq("household_id", inv.get("household_id")).maybe_single().execute()
                )
                if dep_res and hasattr(dep_res, "data") and dep_res.data:
                    inv["target_member_name"] = dep_res.data.get("name")
            except Exception as dep_exc:
                logger.warning("Could not resolve target_member_name: %s", dep_exc)
        return inv
    return {
        "invite_code": code,
        "household_id": None,
        "role": "peer",
        "target_member_id": None,
        "target_member_name": None,
        "is_valid": False,
    }


def claim_household_role_invite(invite_code: str, user_id: str) -> dict:
    """
    Claims a household invite for a user atomically through the claim_household_role_invite RPC
    (no local file fallback).
    """
    code = invite_code.strip().upper()

    try:
        client = get_client()
        res = client.rpc("claim_household_role_invite", {
            "p_invite_code": code,
            "p_user_id": user_id,
        }).execute()
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

    data = res.data if res is not None and isinstance(getattr(res, "data", None), dict) else None
    if data is None:
        return {"status": "error", "error": "Invite code is invalid, expired or could not be claimed."}
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
    from decimal import ROUND_HALF_UP, Decimal

    tx_id = str(uuid.uuid4())
    now_iso = datetime.now(timezone.utc).isoformat()
    # The route refuses sub-halala input (422); any other caller rounds half-up like the app.
    value = Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
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



