"""
BNPL Installment Service (Tamara, Tabby, Bank 0% Installment Plans)
Manages installment plans, their payment schedules (monthly or every two weeks), and cycle reservations.

Schedule (migration 20261021000000): installment k (0-based) is due on ``start_date`` + k * 14 days
(``biweekly``: Tabby / Tamara "Pay in 4", first payment at purchase) or ``start_date`` + k months
(``monthly``: bank plans, Tamara 3 monthly; end-of-month clamped from the anchor, so 31 Jan ->
28 Feb -> 31 Mar). ``next_due_at`` is the due date of the first unpaid installment while the plan is
ACTIVE, else None. The database derives the same value (trigger trg_installment_plans_schedule) and
pay_installment_plan advances it.
"""

from __future__ import annotations

import calendar
import logging
import re
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_DOWN, ROUND_HALF_UP
from typing import Any, Dict, List, Literal, Optional
from pydantic import BaseModel, Field, field_validator, model_validator

import supabase_client
from postgrest_compat import db_error_fields

logger = logging.getLogger(__name__)

FREQUENCIES = ("monthly", "biweekly")
# Providers whose standard "Pay in 4" plan charges every two weeks, the first payment at purchase.
PAY_IN_4_PROVIDERS = frozenset({"tabby", "tamara"})
_HALALA = Decimal("0.01")


def _sar_half_up(value: Any) -> float:
    """SAR amount rounded half-up to the halala (Python's round() is half-even on floats)."""
    return float(Decimal(str(value)).quantize(_HALALA, rounding=ROUND_HALF_UP))


def _halalas(value: Any) -> int:
    """A SAR amount as an integer number of halalas, rounded half-up."""
    return int((Decimal(str(value)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def default_frequency_for_provider(provider: Optional[str], installment_count: int = 4) -> str:
    """Tabby / Tamara "Pay in 4" -> biweekly; every other plan (bank, Tamara 3 monthly, ...) -> monthly."""
    if (provider or "").strip().lower() in PAY_IN_4_PROVIDERS and installment_count == 4:
        return "biweekly"
    return "monthly"


def installment_amounts(total_amount: float, installment_count: int) -> List[float]:
    """
    Exact per-installment amounts in halalas: every installment is the total divided by the count,
    rounded half-up to the halala, and the last one absorbs the remainder so the amounts add up to
    the total exactly (100 / 3 -> 33.33, 33.33, 33.34). When half-up rounding would leave the last
    installment negative (tiny totals over many installments), the regular amount is rounded down.
    """
    count = max(1, int(installment_count))
    total = _halalas(total_amount)
    regular = int((Decimal(total) / count).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    if total - regular * (count - 1) < 0:
        regular = int((Decimal(total) / count).quantize(Decimal("1"), rounding=ROUND_DOWN))
    last = total - regular * (count - 1)
    return [regular / 100.0] * (count - 1) + [last / 100.0]


def _add_months(anchor: date, months: int) -> date:
    """``anchor`` + ``months`` calendar months, the day clamped to the month's end (PostgreSQL rule)."""
    month_index = anchor.month - 1 + months
    year, month = anchor.year + month_index // 12, month_index % 12 + 1
    return date(year, month, min(anchor.day, calendar.monthrange(year, month)[1]))


def installment_due_date(start_date: date, frequency: str, index: int) -> date:
    """Due date of installment ``index`` (0-based) of a plan starting on ``start_date``."""
    index = max(0, int(index))
    if frequency == "biweekly":
        return start_date + timedelta(days=14 * index)
    return _add_months(start_date, index)


def _as_date(value: Any) -> Optional[date]:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def next_due_date(
    start_date: Any,
    frequency: str,
    paid_installments: int,
    installment_count: int,
    status: str = "ACTIVE",
) -> Optional[str]:
    """ISO due date of the first unpaid installment of an ACTIVE plan, else None
    (mirror of public.installment_next_due_at)."""
    start = _as_date(start_date)
    if start is None or status != "ACTIVE" or int(paid_installments or 0) >= int(installment_count or 0):
        return None
    return installment_due_date(start, frequency, int(paid_installments or 0)).isoformat()

# Plans live in public.installment_plans only. The former container-local JSON fallback (used when
# the insert failed, e.g. for start_date "not-a-date") reported plans as created that no other
# instance could see and that vanished on redeploy (FABLE-API-09): a failed insert now fails.


def calculate_installment_terms(
    total_amount: float,
    installment_count: int = 4,
    start_date: Optional[date] = None,
    day_of_month: int = 27,
    frequency: str = "monthly",
    paid_installments: int = 1,
) -> Dict[str, Any]:
    """
    Payment schedule of an installment plan: exact halala amounts (the last installment absorbs the
    rounding remainder) and due dates every month or every two weeks from ``start_date``.

    ``monthly_amount`` is the regular installment amount whatever the frequency (the column name
    predates bi-weekly plans).
    """
    if installment_count <= 0:
        installment_count = 1
    if frequency not in FREQUENCIES:
        raise ValueError(f"frequency must be one of {FREQUENCIES}")
    start = start_date or date.today()
    paid = min(max(0, int(paid_installments)), installment_count)

    amounts = installment_amounts(total_amount, installment_count)
    schedule = [
        {
            "number": i + 1,
            "due_date": installment_due_date(start, frequency, i).isoformat(),
            "amount": amounts[i],
            "paid": i < paid,
        }
        for i in range(installment_count)
    ]
    remaining_halalas = sum(_halalas(a) for a in amounts[paid:])

    return {
        "total_amount": _sar_half_up(total_amount),
        "installment_count": installment_count,
        "frequency": frequency,
        "monthly_amount": amounts[0],
        "final_installment_amount": amounts[-1],
        "paid_installments": paid,
        "remaining_installments": installment_count - paid,
        "remaining_amount": remaining_halalas / 100.0,
        "day_of_month": day_of_month,
        "start_date": start.isoformat(),
        "next_due_at": next_due_date(start, frequency, paid, installment_count,
                                     "ACTIVE" if paid < installment_count else "COMPLETED"),
        "schedule": schedule,
    }


class InstallmentPlanCreate(BaseModel):
    household_id: str
    merchant: str = Field(..., min_length=1, max_length=120)
    provider: str = Field("Tamara", max_length=40)  # Tamara, Tabby, Bank, Other
    total_amount: float = Field(..., gt=0, le=10_000_000, allow_inf_nan=False)
    installment_count: int = Field(4, ge=1, le=60)
    monthly_amount: Optional[float] = Field(None, ge=0, le=10_000_000, allow_inf_nan=False)
    paid_installments: int = Field(1, ge=0, le=60)
    day_of_month: int = Field(27, ge=1, le=31)
    start_date: Optional[str] = Field(None, max_length=32)
    # None -> by provider: Tabby / Tamara "Pay in 4" biweekly, everything else monthly.
    frequency: Optional[Literal["monthly", "biweekly"]] = None
    category_code: str = Field("OPEX-SHOPPING", max_length=60)
    original_transaction_id: Optional[str] = Field(None, max_length=64)
    notes: Optional[str] = Field(None, max_length=500)
    adjust_original_transaction: bool = True

    @field_validator("start_date")
    @classmethod
    def validate_start_date(cls, v: Optional[str]) -> Optional[str]:
        """An ISO calendar date (YYYY-MM-DD), the type of installment_plans.start_date."""
        if v is None:
            return v
        try:
            return date.fromisoformat(v.strip()).isoformat()
        except (AttributeError, ValueError):
            raise ValueError("start_date must be an ISO date (YYYY-MM-DD)")

    @field_validator("frequency", mode="before")
    @classmethod
    def normalize_frequency(cls, v: Any) -> Any:
        if isinstance(v, str):
            return v.strip().lower() or None
        return v

    @model_validator(mode="after")
    def default_frequency(self) -> "InstallmentPlanCreate":
        if self.frequency is None:
            self.frequency = default_frequency_for_provider(self.provider, self.installment_count)
        return self


class InstallmentPlanUpdate(BaseModel):
    merchant: Optional[str] = Field(None, min_length=1, max_length=120)
    provider: Optional[str] = Field(None, max_length=40)
    total_amount: Optional[float] = Field(None, gt=0, le=10_000_000, allow_inf_nan=False)
    installment_count: Optional[int] = Field(None, ge=1, le=60)
    monthly_amount: Optional[float] = Field(None, ge=0, le=10_000_000, allow_inf_nan=False)
    paid_installments: Optional[int] = Field(None, ge=0, le=60)
    day_of_month: Optional[int] = Field(None, ge=1, le=31)
    start_date: Optional[str] = Field(None, max_length=32)
    frequency: Optional[Literal["monthly", "biweekly"]] = None
    category_code: Optional[str] = Field(None, max_length=60)
    notes: Optional[str] = Field(None, max_length=500)
    status: Optional[str] = Field(None, max_length=20)

    @field_validator("start_date")
    @classmethod
    def validate_start_date(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        try:
            return date.fromisoformat(v.strip()).isoformat()
        except (AttributeError, ValueError):
            raise ValueError("start_date must be an ISO date (YYYY-MM-DD)")

    @field_validator("frequency", mode="before")
    @classmethod
    def normalize_frequency(cls, v: Any) -> Any:
        if isinstance(v, str):
            return v.strip().lower() or None
        return v


class InstallmentPlan(BaseModel):
    id: str
    household_id: str
    merchant: str
    provider: str = "Tamara"
    total_amount: float
    installment_count: int = 4
    monthly_amount: float
    paid_installments: int = 1
    day_of_month: int = 27
    start_date: str = Field(default_factory=lambda: date.today().isoformat())
    frequency: str = "monthly"  # monthly | biweekly
    next_due_at: Optional[str] = None  # YYYY-MM-DD of the first unpaid installment; None unless ACTIVE
    status: str = "ACTIVE"  # ACTIVE, COMPLETED
    category_code: str = "OPEX-SHOPPING"
    original_transaction_id: Optional[str] = None
    notes: Optional[str] = None
    created_at: Optional[str] = None

    @field_validator("start_date", "next_due_at", mode="before")
    @classmethod
    def iso_date(cls, v: Any) -> Any:
        d = _as_date(v) if v is not None else None
        return d.isoformat() if d is not None else v

    @property
    def remaining_amount(self) -> float:
        """Outstanding SAR, computed in Decimal halalas. The final installment absorbs the
        rounding remainder (100/3 → 33.33, 33.33, 33.34), so a completed plan owes exactly 0
        instead of a residual 0.01 from float math."""
        if self.paid_installments >= self.installment_count:
            return 0.0
        total = Decimal(str(self.total_amount)).quantize(_HALALA, rounding=ROUND_HALF_UP)
        monthly = Decimal(str(self.monthly_amount)).quantize(_HALALA, rounding=ROUND_HALF_UP)
        remaining = total - monthly * self.paid_installments
        return float(max(Decimal("0"), remaining))

    @property
    def remaining_installments(self) -> int:
        return max(0, self.installment_count - self.paid_installments)

    def record_payment(self) -> None:
        if self.paid_installments < self.installment_count:
            self.paid_installments += 1
        if self.paid_installments >= self.installment_count:
            self.status = "COMPLETED"
        self.next_due_at = next_due_date(self.start_date, self.frequency, self.paid_installments,
                                         self.installment_count, self.status)


# Suffix written by InstallmentService._adjust_original_transaction on the financed transaction.
_LEGACY_NOTE = re.compile(
    r"Financed via\s+([^:\]]+):\s*Installment\s*(\d+)\s*of\s*(\d+)\.?\s*(?:Full price:\s*(?:SAR\s*)?([0-9,]+(?:\.[0-9]+)?))?",
    re.IGNORECASE,
)
_LEGACY_PLAN_NAMESPACE = uuid.UUID("6f1c7a52-6a0e-4c43-9a55-0d6b1f3e2b10")


class PlanNotActiveError(Exception):
    """The plan is neither ACTIVE nor COMPLETED (e.g. CANCELLED): it takes no payments."""


class InstallmentService:
    @staticmethod
    def transaction_belongs_to_household(tx_id: str, household_id: str) -> bool:
        """True when transaction ``tx_id`` exists inside ``household_id`` (service role bypasses RLS)."""
        try:
            sb = supabase_client.get_client()
            res = (
                sb.table("transactions")
                .select("id")
                .eq("id", tx_id)
                .eq("household_id", household_id)
                .limit(1)
                .execute()
            )
            return bool(res is not None and res.data)
        except Exception as e:
            logger.warning("Could not verify ownership of transaction %s: %s", tx_id, e)
            return False

    @classmethod
    def get_plan_household_id(cls, plan_id: str) -> Optional[str]:
        """Owning household of an installment plan, None when it does not exist (errors propagate)."""
        sb = supabase_client.get_client()
        res = sb.table("installment_plans").select("household_id").eq("id", plan_id).limit(1).execute()
        if res is not None and res.data:
            return res.data[0].get("household_id")
        return None

    @classmethod
    def create_plan(cls, req: InstallmentPlanCreate) -> InstallmentPlan:
        # The optional original transaction must belong to the plan's household; otherwise any
        # member could rewrite another household's transaction amount through this endpoint.
        if req.original_transaction_id and not cls.transaction_belongs_to_household(
            req.original_transaction_id, req.household_id
        ):
            raise PermissionError("original_transaction_id does not belong to this household")

        # Regular installment amount if not provided: exact halalas, the last installment absorbs
        # the remainder (remaining_amount relies on that).
        monthly = req.monthly_amount
        if not monthly or monthly <= 0:
            monthly = installment_amounts(req.total_amount, req.installment_count)[0]

        frequency = req.frequency or default_frequency_for_provider(req.provider, req.installment_count)
        start_date = req.start_date or date.today().isoformat()
        status = "COMPLETED" if req.paid_installments >= req.installment_count else "ACTIVE"
        plan_id = str(uuid.uuid4())
        plan_dict = {
            "id": plan_id,
            "household_id": req.household_id,
            "merchant": req.merchant,
            "provider": req.provider,
            "total_amount": _sar_half_up(req.total_amount),
            "installment_count": req.installment_count,
            "monthly_amount": monthly,
            "paid_installments": req.paid_installments,
            "day_of_month": req.day_of_month,
            "start_date": start_date,
            "frequency": frequency,
            # Derived; the database trigger recomputes the same value (migration 20261021000000).
            "next_due_at": next_due_date(start_date, frequency, req.paid_installments, req.installment_count, status),
            "status": status,
            "category_code": req.category_code,
            "original_transaction_id": req.original_transaction_id,
            "notes": req.notes,
            "created_at": datetime.now().isoformat(),
        }

        # Persist. A failure propagates (the request fails): there is no local fallback, and the
        # original transaction is only adjusted once the plan is stored (FABLE-API-09).
        sb = supabase_client.get_client()
        sb.table("installment_plans").insert(plan_dict).execute()
        logger.info("Persisted installment plan %s to Supabase", plan_id)

        # Only now: adjust the original transaction down to the monthly amount, if requested. A
        # refused adjustment (e.g. the wife-ledger guard: the advance was already repaid) removes
        # the plan again and fails the request: never a stored plan next to an unchanged
        # transaction reported as success (FABLE2-API-05).
        if req.original_transaction_id and req.adjust_original_transaction:
            try:
                cls._adjust_original_transaction(
                    tx_id=req.original_transaction_id,
                    household_id=req.household_id,
                    monthly_amount=monthly,
                    total_amount=req.total_amount,
                    provider=req.provider,
                    installment_count=req.installment_count,
                )
            except Exception as exc:
                logger.warning("Adjusting transaction %s refused; removing plan %s: %s",
                               req.original_transaction_id, plan_id, exc)
                try:
                    sb.table("installment_plans").delete().eq("id", plan_id).eq(
                        "household_id", req.household_id).execute()
                except Exception as cleanup_exc:  # noqa: BLE001 - the original error is what matters
                    logger.error("Could not remove installment plan %s: %s", plan_id, cleanup_exc)
                final = supabase_client.final_transaction_db_error(exc)
                if final is not None:
                    raise final from exc
                raise

        return InstallmentPlan(**plan_dict)

    @classmethod
    def update_plan(
        cls,
        plan_id: str,
        household_id: str,
        req: "InstallmentPlanUpdate",
        actor_user_id: Optional[str] = None,
    ) -> Optional[InstallmentPlan]:
        sb = supabase_client.get_client()
        res = sb.table("installment_plans").select("*").eq("id", plan_id).eq("household_id", household_id).execute()
        rows = res.data or []
        if not rows:
            return None
        existing = rows[0]

        update_dict: Dict[str, Any] = {}
        if req.merchant is not None:
            update_dict["merchant"] = req.merchant.strip()
        if req.provider is not None:
            update_dict["provider"] = req.provider.strip()
        if req.category_code is not None:
            update_dict["category_code"] = req.category_code.strip()
        if req.notes is not None:
            update_dict["notes"] = req.notes
        if req.day_of_month is not None:
            update_dict["day_of_month"] = req.day_of_month

        total_amount = Decimal(str(req.total_amount if req.total_amount is not None else existing["total_amount"])).quantize(_HALALA, rounding=ROUND_HALF_UP)
        if req.total_amount is not None:
            update_dict["total_amount"] = float(total_amount)

        count = req.installment_count if req.installment_count is not None else existing.get("installment_count", 4)
        if req.installment_count is not None:
            update_dict["installment_count"] = count

        paid = req.paid_installments if req.paid_installments is not None else existing.get("paid_installments", 0)
        if paid > count:
            raise ValueError(f"paid_installments ({paid}) cannot exceed installment_count ({count})")
        if req.paid_installments is not None:
            update_dict["paid_installments"] = paid

        if req.monthly_amount is not None:
            monthly = Decimal(str(req.monthly_amount)).quantize(_HALALA, rounding=ROUND_HALF_UP)
            update_dict["monthly_amount"] = float(monthly)
        elif req.total_amount is not None or req.installment_count is not None:
            amounts = installment_amounts(float(total_amount), count)
            update_dict["monthly_amount"] = amounts[0]

        start_date = req.start_date or existing.get("start_date") or date.today().isoformat()
        if req.start_date is not None:
            update_dict["start_date"] = start_date

        frequency = req.frequency or existing.get("frequency") or "monthly"
        if req.frequency is not None:
            update_dict["frequency"] = frequency

        status = req.status or ("COMPLETED" if paid >= count else "ACTIVE")
        update_dict["status"] = status

        next_due = next_due_date(start_date, frequency, paid, count, status)
        update_dict["next_due_at"] = next_due

        sb.table("installment_plans").update(update_dict).eq("id", plan_id).eq("household_id", household_id).execute()
        cls.recalculate_budgets(household_id)

        updated_res = sb.table("installment_plans").select("*").eq("id", plan_id).eq("household_id", household_id).execute()
        updated_rows = updated_res.data or []
        if not updated_rows:
            return None
        return InstallmentPlan(**updated_rows[0])

    @classmethod
    def _adjust_original_transaction(
        cls,
        tx_id: str,
        household_id: str,
        monthly_amount: float,
        total_amount: float,
        provider: str,
        installment_count: int,
    ) -> None:
        """
        Adjusts the first transaction to reflect the first installment payment rather than the
        entire purchase. Errors propagate (create_plan removes the plan again).
        """
        sb = supabase_client.get_client()
        note_suffix = f" [Financed via {provider}: Installment 1 of {installment_count}. Full price: SAR {total_amount:,.2f}]"

        # Fetch existing transaction
        tx = (
            sb.table("transactions")
            .select("raw_sms, household_id")
            .eq("id", tx_id)
            .eq("household_id", household_id)
            .single()
            .execute()
        )
        raw_sms = (tx.data.get("raw_sms") or "") + note_suffix

        sb.table("transactions").update({
            "amount": monthly_amount,
            "raw_sms": raw_sms,
        }).eq("id", tx_id).eq("household_id", household_id).execute()

        logger.info(
            "Adjusted original transaction %s from %s to monthly installment %s",
            tx_id, total_amount, monthly_amount
        )
        # recalculate_budgets logs and swallows its own errors: the adjustment itself succeeded.
        cls.recalculate_budgets(household_id)

    @classmethod
    def recalculate_budgets(cls, household_id: str, cycle_key: Optional[str] = None) -> None:
        """
        Recompute ``budgets.spent_amount`` of one salary cycle (``cycle_key``, default the current
        one) from its transactions. The transaction triggers keep the column current, so this is
        a repair tool (POST /budgets/recalculate, a payday change), never run per insert.

        It calls the SQL function ``recompute_budget_spent(p_household_id, p_cycle_keys)``
        (migration 20261020800000; SECURITY DEFINER, executable by service_role only), which applies
        the trigger rules in one statement: settlements and ``wife_personal`` rows are not category
        spending. When the function is missing (migration not applied yet) the same computation
        runs here, reading only that cycle's transactions and budget rows. Errors are logged and
        swallowed: callers treat the recalculation as best effort.
        """
        from decimal import Decimal

        try:
            from salary_cycle import get_cycle_for_date
            from supabase_client import get_household_payday

            target_key = cycle_key or get_cycle_for_date(payday_day=get_household_payday(household_id))["cycle_key"]
            sb = supabase_client.get_client()
        except Exception as e:
            logger.warning("Could not recalculate budgets for household %s: %s", household_id, e)
            return

        try:
            sb.rpc("recompute_budget_spent", {"p_household_id": household_id, "p_cycle_keys": [target_key]}).execute()
            logger.info("Recomputed budgets for household %s cycle %s (SQL)", household_id, target_key)
            return
        except Exception as rpc_err:
            logger.info("recompute_budget_spent unavailable (%s); recalculating cycle %s in Python.", rpc_err, target_key)

        try:
            tx_rows = (
                sb.table("transactions")
                .select("category_code, amount, is_settlement, nafaqah_class")
                .eq("household_id", household_id)
                .eq("cycle_key", target_key)
                .execute()
                .data
                or []
            )
            spent_by_cat: Dict[str, Decimal] = {}
            for t in tx_rows:
                if t.get("is_settlement"):
                    continue  # a settlement payment between members is not spending
                if t.get("nafaqah_class") == "wife_personal":
                    continue  # charged to the wife's allowance only (owner decision, FABLE-LOGIC-06)
                cat = t.get("category_code")
                spent_by_cat[cat] = spent_by_cat.get(cat, Decimal("0")) + Decimal(str(t.get("amount") or 0))

            budget_rows = (
                sb.table("budgets")
                .select("id, category_code")
                .eq("household_id", household_id)
                .eq("cycle_key", target_key)
                .execute()
                .data
                or []
            )
            for b in budget_rows:
                spent = max(Decimal("0"), spent_by_cat.get(b.get("category_code"), Decimal("0")))
                sb.table("budgets").update({"spent_amount": float(spent.quantize(Decimal("0.01")))}).eq(
                    "id", b["id"]
                ).execute()
            logger.info("Recalculated budgets for household %s cycle %s (Python)", household_id, target_key)
        except Exception as e:
            logger.warning("Could not recalculate budgets for household %s: %s", household_id, e)

    @classmethod
    def list_plans(cls, household_id: str) -> List[InstallmentPlan]:
        """
        The household's plans, read from public.installment_plans only (the database is the only
        store: a failed query fails the request, FABLE-API-09). ACTIVE plans first, by next due
        date; then the others, newest first.

        Plans are no longer reconstructed by regex from transaction notes on every load (product
        review R10): legacy "Financed via ..." notes without a plan row are turned into rows once,
        by hand, with ``backfill_plans_from_legacy_notes``.
        """
        sb = supabase_client.get_client()
        res = sb.table("installment_plans").select("*").eq("household_id", household_id).execute()
        plans = [InstallmentPlan(**row) for row in (res.data or [])]
        active = sorted((p for p in plans if p.status == "ACTIVE"),
                        key=lambda p: (p.next_due_at or "9999-12-31", p.created_at or ""))
        others = sorted((p for p in plans if p.status != "ACTIVE"),
                        key=lambda p: p.created_at or "", reverse=True)
        return active + others

    @classmethod
    def backfill_plans_from_legacy_notes(
        cls,
        household_id: Optional[str] = None,
        apply: bool = False,
    ) -> Dict[str, Any]:
        """
        One-time, idempotent backfill (NOT run automatically): creates an installment_plans row for
        every transaction whose note carries the suffix written by ``_adjust_original_transaction``
        ("[Financed via <provider>: Installment <n> of <m>. Full price: SAR <total>]") and that no
        plan references yet. Before migration 20261021000000's release, list_plans re-derived such
        plans on every load; now only rows are listed.

        * ``apply=False`` (default) only reports what would be created.
        * Idempotent: a transaction that a plan already references (``original_transaction_id``) is
          skipped, and the plan id is derived from the transaction id (uuid5), so a re-run creates
          nothing and a concurrent run cannot create a duplicate.
        * Only the explicit suffix is parsed (no guessing from a bare "Tabby"/"Tamara" mention); the
          transaction is never changed again; the frequency follows the provider default.

        Run from ``ai_service/`` with the service-role environment of the target database, e.g.
        ``python -m installment_service --backfill-legacy [--household <uuid>] [--apply]``.
        """
        sb = supabase_client.get_client()
        plan_query = sb.table("installment_plans").select("original_transaction_id")
        tx_query = sb.table("transactions").select(
            "id, household_id, merchant, amount, raw_sms, category_code, timestamp")
        if household_id:
            plan_query = plan_query.eq("household_id", household_id)
            tx_query = tx_query.eq("household_id", household_id)
        linked = {r.get("original_transaction_id") for r in (plan_query.execute().data or [])
                  if r.get("original_transaction_id")}

        candidates: List[Dict[str, Any]] = []
        for tx in (tx_query.execute().data or []):
            tx_id = tx.get("id")
            match = _LEGACY_NOTE.search(tx.get("raw_sms") or "")
            if not tx_id or tx_id in linked or not match:
                continue
            provider = match.group(1).strip()[:40] or "Other"
            paid, count = int(match.group(2)), int(match.group(3))
            if count < 1 or count > 60 or paid < 0 or paid > count:
                continue
            amount = _sar_half_up(tx.get("amount") or 0)
            total = _sar_half_up(match.group(4).replace(",", "")) if match.group(4) else _sar_half_up(amount * count)
            if total <= 0:
                continue
            frequency = default_frequency_for_provider(provider, count)
            start = (tx.get("timestamp") or date.today().isoformat())[:10]
            status = "COMPLETED" if paid >= count else "ACTIVE"
            candidates.append({
                "id": str(uuid.uuid5(_LEGACY_PLAN_NAMESPACE, str(tx_id))),
                "household_id": tx.get("household_id"),
                "merchant": (tx.get("merchant") or "Installment Purchase")[:120],
                "provider": provider,
                "total_amount": total,
                "installment_count": count,
                "monthly_amount": amount if amount > 0 else installment_amounts(total, count)[0],
                "paid_installments": paid,
                "start_date": start,
                "frequency": frequency,
                "next_due_at": next_due_date(start, frequency, paid, count, status),
                "status": status,
                "category_code": tx.get("category_code") or "OPEX-SHOPPING",
                "original_transaction_id": tx_id,
                "notes": "Backfilled from a legacy transaction note",
            })

        created = 0
        if apply:
            for row in candidates:
                res = sb.table("installment_plans").upsert(row, on_conflict="id", ignore_duplicates=True).execute()
                created += len((res.data if res is not None else None) or [])
        logger.info("Legacy installment backfill: %d candidate(s), %d written (apply=%s)",
                    len(candidates), created, apply)
        return {"candidates": len(candidates), "created": created, "applied": apply,
                "plans": [{k: r[k] for k in ("id", "household_id", "provider", "installment_count",
                                             "paid_installments", "frequency", "original_transaction_id")}
                          for r in candidates]}

    @classmethod
    def pay_installment(cls, plan_id: str, household_id: str, actor_user_id: str) -> Optional[InstallmentPlan]:
        """
        Record one payment on ``plan_id``, scoped to the caller-verified ``household_id``.

        One atomic conditional increment in the database (RPC pay_installment_plan, migration
        20261020750000): concurrent payments each count exactly once and never beyond
        installment_count (FABLE-API-10; the old read-modify-write lost one of two concurrent
        payments). A paid-up plan is returned unchanged; None when the plan is not in the household.
        """
        sb = supabase_client.get_client()
        try:
            res = sb.rpc("pay_installment_plan", {
                "p_plan_id": plan_id,
                "p_household_id": household_id,
                "p_actor_user_id": actor_user_id,
            }).execute()
        except Exception as exc:
            # Migration 20261020900000 refuses payments on a non-ACTIVE plan (HINT plan_not_active).
            if db_error_fields(exc).get("hint") == "plan_not_active":
                raise PlanNotActiveError(str(plan_id)) from exc
            raise
        rows = res.data if res is not None else None
        if isinstance(rows, dict):
            rows = [rows]
        if not rows:
            return None
        return InstallmentPlan(**rows[0])


def _main(argv: Optional[List[str]] = None) -> int:
    """CLI for the one-time legacy backfill (dry run unless --apply)."""
    import argparse
    import json

    parser = argparse.ArgumentParser(description="Installment plan maintenance (never run automatically).")
    parser.add_argument("--backfill-legacy", action="store_true",
                        help="Create plan rows from legacy 'Financed via' transaction notes.")
    parser.add_argument("--household", default=None, help="Limit to one household id.")
    parser.add_argument("--apply", action="store_true", help="Write the rows (default: dry run).")
    args = parser.parse_args(argv)
    if not args.backfill_legacy:
        parser.print_help()
        return 2
    result = InstallmentService.backfill_plans_from_legacy_notes(household_id=args.household, apply=args.apply)
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
