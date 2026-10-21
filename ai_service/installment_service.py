"""
BNPL Installment Service (Tamara, Tabby, Bank 0% Installment Plans)
Manages installment plans, monthly payment schedules, and cycle reservations.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, field_validator

import supabase_client
from postgrest_compat import db_error_fields

logger = logging.getLogger(__name__)


def _sar_half_up(value: Any) -> float:
    """SAR amount rounded half-up to the halala (Python's round() is half-even on floats)."""
    from decimal import Decimal, ROUND_HALF_UP

    return float(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))

# Plans live in public.installment_plans only. The former container-local JSON fallback (used when
# the insert failed, e.g. for start_date "not-a-date") reported plans as created that no other
# instance could see and that vanished on redeploy (FABLE-API-09): a failed insert now fails.


def calculate_installment_terms(
    total_amount: float,
    installment_count: int = 4,
    start_date: Optional[date] = None,
    day_of_month: int = 27,
) -> Dict[str, Any]:
    """Calculates monthly payment and remaining balance for an installment plan."""
    if installment_count <= 0:
        installment_count = 1

    monthly_amount = _sar_half_up(total_amount / installment_count)
    # Handle rounding cents on last payment
    paid_installments = 1
    remaining_installments = max(0, installment_count - paid_installments)
    remaining_amount = _sar_half_up(total_amount - (monthly_amount * paid_installments))

    return {
        "total_amount": _sar_half_up(total_amount),
        "installment_count": installment_count,
        "monthly_amount": monthly_amount,
        "paid_installments": paid_installments,
        "remaining_installments": remaining_installments,
        "remaining_amount": max(0.0, remaining_amount),
        "day_of_month": day_of_month,
        "start_date": (start_date or date.today()).isoformat(),
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
    status: str = "ACTIVE"  # ACTIVE, COMPLETED
    category_code: str = "OPEX-SHOPPING"
    original_transaction_id: Optional[str] = None
    notes: Optional[str] = None
    created_at: Optional[str] = None

    @property
    def remaining_amount(self) -> float:
        """Outstanding SAR, computed in Decimal halalas. The final installment absorbs the
        rounding remainder (100/3 → 33.33, 33.33, 33.34), so a completed plan owes exactly 0
        instead of a residual 0.01 from float math."""
        from decimal import Decimal, ROUND_HALF_UP

        if self.paid_installments >= self.installment_count:
            return 0.0
        total = Decimal(str(self.total_amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        monthly = Decimal(str(self.monthly_amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
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

        # Calculate monthly amount if not provided
        monthly = req.monthly_amount
        if not monthly or monthly <= 0:
            monthly = _sar_half_up(req.total_amount / max(1, req.installment_count))

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
            "start_date": req.start_date or date.today().isoformat(),
            "status": "COMPLETED" if req.paid_installments >= req.installment_count else "ACTIVE",
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
        Recalculates spent_amount for all categories in a household from transactions,
        scoped to the specified cycle (or current cycle if None).
        Also ensures budget rows exist for any category that has active transactions.
        """
        try:
            sb = supabase_client.get_client()
            from salary_cycle import get_cycle_for_date, get_cycle_info_for_key
            from supabase_client import get_household_payday

            payday_day = get_household_payday(household_id)
            current_cycle = get_cycle_for_date(payday_day=payday_day)
            target_key = cycle_key or current_cycle["cycle_key"]
            cycle_info = get_cycle_info_for_key(target_key, payday_day=payday_day)

            # Query transactions in this cycle
            start_ts = f"{cycle_info['cycle_start']}T00:00:00"
            end_ts = f"{cycle_info['cycle_end']}T23:59:59"
            tx_res = (
                sb.table("transactions")
                .select("id, category_code, amount, cycle_key, timestamp, is_settlement, nafaqah_class")
                .eq("household_id", household_id)
                .execute()
            )

            # Filter by cycle_key or date range
            spent_by_cat: Dict[str, float] = {}
            for t in (tx_res.data or []):
                if t.get("is_settlement"):
                    continue  # a settlement payment between members is not spending
                if t.get("nafaqah_class") == "wife_personal":
                    continue  # charged to the wife's allowance only (owner decision, FABLE-LOGIC-06)
                t_cycle = t.get("cycle_key")
                t_ts = t.get("timestamp") or ""
                in_cycle = (t_cycle == target_key) or (not t_cycle and start_ts <= t_ts <= end_ts)
                if in_cycle:
                    cat = t.get("category_code") or "OPEX-MISC"
                    spent_by_cat[cat] = spent_by_cat.get(cat, 0.0) + float(t.get("amount") or 0.0)

            # Fetch existing budgets for this cycle
            budgets_res = (
                sb.table("budgets")
                .select("*")
                .eq("household_id", household_id)
                .execute()
            )
            all_budgets = budgets_res.data or []
            cycle_budgets = {
                b["category_code"]: b for b in all_budgets
                if (b.get("cycle_key") == target_key or (not b.get("cycle_key") and b.get("month", "")[:7] == target_key))
            }

            # Update existing budget rows
            for cat, b in cycle_budgets.items():
                actual_spent = round(spent_by_cat.get(cat, 0.0), 2)
                sb.table("budgets").update({
                    "spent_amount": actual_spent,
                    "cycle_key": target_key,
                }).eq("id", b["id"]).execute()

            # For any category with spending that doesn't have a budget row yet, create one!
            month_str = f"{target_key}-01"
            for cat, spent in spent_by_cat.items():
                if cat not in cycle_budgets:
                    new_budget = {
                        "household_id": household_id,
                        "category_code": cat,
                        "cycle_key": target_key,
                        "month": month_str,
                        "allocated_amount": 0.0,
                        "spent_amount": round(spent, 2),
                        "is_active": True,
                        "previous_cycle_delta": 0.0,
                    }
                    try:
                        sb.table("budgets").insert(new_budget).execute()
                        logger.info("Auto-created budget row for cat=%s cycle=%s spent=%.2f", cat, target_key, spent)
                    except Exception as ins_err:
                        logger.warning("Could not auto-insert budget row for cat=%s: %s", cat, ins_err)

            logger.info("Recalculated budgets for household %s cycle %s", household_id, target_key)
        except Exception as e:
            logger.warning("Could not recalculate budgets for household %s: %s", household_id, e)

    @classmethod
    def list_plans(cls, household_id: str) -> List[InstallmentPlan]:
        found_plans: List[InstallmentPlan] = []
        seen_tx_ids = set()

        # The database is the only store: a failed query fails the request (FABLE-API-09).
        sb = supabase_client.get_client()
        res = sb.table("installment_plans").select("*").eq("household_id", household_id).execute()
        for row in (res.data or []):
            plan = InstallmentPlan(**row)
            found_plans.append(plan)
            if plan.original_transaction_id:
                seen_tx_ids.add(plan.original_transaction_id)

        # Also reconcile directly from transactions table in Supabase
        try:
            sb = supabase_client.get_client()
            tx_res = sb.table("transactions").select("*").eq("household_id", household_id).execute()
            import re
            for tx in (tx_res.data or []):
                raw = tx.get("raw_sms") or ""
                tx_id = tx.get("id")
                if not tx_id or tx_id in seen_tx_ids:
                    continue

                if "Financed via" in raw or "Tamara" in raw or "Tabby" in raw:
                    match = re.search(r"Financed via\s+([^:]+):\s*Installment\s*(\d+)\s*of\s*(\d+)\.?\s*(?:Full price:\s*(?:SAR\s*)?([0-9,.]+))?", raw, re.IGNORECASE)
                    provider = "Tamara" if "tamara" in raw.lower() else ("Tabby" if "tabby" in raw.lower() else "Bank")
                    count = 4
                    paid = 1
                    monthly = float(tx.get("amount") or 0.0)
                    total = monthly * count

                    if match:
                        provider = match.group(1).strip()
                        paid = int(match.group(2))
                        count = int(match.group(3))
                        if match.group(4):
                            try:
                                total = float(match.group(4).replace(",", ""))
                            except Exception:
                                total = monthly * count

                    plan_obj = InstallmentPlan(
                        id=f"plan-{tx_id[:8]}",
                        household_id=household_id,
                        merchant=tx.get("merchant") or "Installment Purchase",
                        provider=provider,
                        total_amount=round(total, 2),
                        installment_count=count,
                        monthly_amount=round(monthly, 2) if monthly > 0 else round(total / count, 2),
                        paid_installments=paid,
                        day_of_month=27,
                        start_date=(tx.get("timestamp") or date.today().isoformat())[:10],
                        status="COMPLETED" if paid >= count else "ACTIVE",
                        category_code=tx.get("category_code") or "OPEX-SHOPPING",
                        original_transaction_id=tx_id,
                        notes=raw,
                    )
                    found_plans.append(plan_obj)
                    seen_tx_ids.add(tx_id)
        except Exception as e:
            logger.debug("Could not reconcile installment plans from transactions: %s", e)

        return found_plans

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
