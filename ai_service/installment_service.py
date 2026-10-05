"""
BNPL Installment Service (Tamara, Tabby, Bank 0% Installment Plans)
Manages installment plans, monthly payment schedules, and cycle reservations.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import date, datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

import supabase_client

logger = logging.getLogger(__name__)

# Fallback persistence file if DB table migration has not been applied yet
FALLBACK_FILE = Path(__file__).parent / "data" / "installment_plans.json"


def calculate_installment_terms(
    total_amount: float,
    installment_count: int = 4,
    start_date: Optional[date] = None,
    day_of_month: int = 27,
) -> Dict[str, Any]:
    """Calculates monthly payment and remaining balance for an installment plan."""
    if installment_count <= 0:
        installment_count = 1

    monthly_amount = round(total_amount / installment_count, 2)
    # Handle rounding cents on last payment
    paid_installments = 1
    remaining_installments = max(0, installment_count - paid_installments)
    remaining_amount = round(total_amount - (monthly_amount * paid_installments), 2)

    return {
        "total_amount": round(total_amount, 2),
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
    merchant: str
    provider: str = "Tamara"  # Tamara, Tabby, Bank, Other
    total_amount: float
    installment_count: int = 4
    monthly_amount: Optional[float] = None
    paid_installments: int = 1
    day_of_month: int = 27
    start_date: Optional[str] = None
    category_code: str = "OPEX-SHOPPING"
    original_transaction_id: Optional[str] = None
    notes: Optional[str] = None
    adjust_original_transaction: bool = True


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
        paid = self.monthly_amount * self.paid_installments
        return max(0.0, round(self.total_amount - paid, 2))

    @property
    def remaining_installments(self) -> int:
        return max(0, self.installment_count - self.paid_installments)

    def record_payment(self) -> None:
        if self.paid_installments < self.installment_count:
            self.paid_installments += 1
        if self.paid_installments >= self.installment_count:
            self.status = "COMPLETED"


class InstallmentService:
    @staticmethod
    def _read_fallback_plans() -> List[Dict[str, Any]]:
        if not FALLBACK_FILE.exists():
            return []
        try:
            with open(FALLBACK_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

    @staticmethod
    def _write_fallback_plans(plans: List[Dict[str, Any]]) -> None:
        FALLBACK_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(FALLBACK_FILE, "w", encoding="utf-8") as f:
            json.dump(plans, f, indent=2, ensure_ascii=False)

    @classmethod
    def create_plan(cls, req: InstallmentPlanCreate) -> InstallmentPlan:
        # Calculate monthly amount if not provided
        monthly = req.monthly_amount
        if not monthly or monthly <= 0:
            monthly = round(req.total_amount / max(1, req.installment_count), 2)

        plan_id = str(uuid.uuid4())
        plan_dict = {
            "id": plan_id,
            "household_id": req.household_id,
            "merchant": req.merchant,
            "provider": req.provider,
            "total_amount": round(req.total_amount, 2),
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

        # Try to persist to Supabase
        persisted = False
        try:
            sb = supabase_client.get_client()
            sb.table("installment_plans").insert(plan_dict).execute()
            persisted = True
            logger.info("Persisted installment plan %s to Supabase", plan_id)
        except Exception as e:
            logger.warning("Could not persist to Supabase installment_plans (%s), using local fallback", e)
            plans = cls._read_fallback_plans()
            plans.append(plan_dict)
            cls._write_fallback_plans(plans)

        # If original transaction is supplied and adjust is requested, adjust transaction down to monthly amount
        if req.original_transaction_id and req.adjust_original_transaction:
            cls._adjust_original_transaction(
                tx_id=req.original_transaction_id,
                monthly_amount=monthly,
                total_amount=req.total_amount,
                provider=req.provider,
                installment_count=req.installment_count,
            )

        return InstallmentPlan(**plan_dict)

    @staticmethod
    def _adjust_original_transaction(
        tx_id: str,
        monthly_amount: float,
        total_amount: float,
        provider: str,
        installment_count: int,
    ) -> None:
        """Adjusts the first transaction to reflect the first installment payment rather than entire purchase."""
        try:
            sb = supabase_client.get_client()
            note_suffix = f" [Financed via {provider}: Installment 1 of {installment_count}. Full price: SAR {total_amount:,.2f}]"
            
            # Fetch existing transaction
            tx = sb.table("transactions").select("raw_sms").eq("id", tx_id).single().execute()
            raw_sms = (tx.data.get("raw_sms") or "") + note_suffix

            sb.table("transactions").update({
                "amount": monthly_amount,
                "raw_sms": raw_sms,
            }).eq("id", tx_id).execute()

            logger.info(
                "Adjusted original transaction %s from %s to monthly installment %s",
                tx_id, total_amount, monthly_amount
            )
        except Exception as e:
            logger.warning("Failed to adjust original transaction %s: %s", tx_id, e)

    @classmethod
    def list_plans(cls, household_id: str) -> List[InstallmentPlan]:
        try:
            sb = supabase_client.get_client()
            res = sb.table("installment_plans").select("*").eq("household_id", household_id).execute()
            if res.data:
                return [InstallmentPlan(**row) for row in res.data]
        except Exception:
            pass

        # Fallback to local
        plans = cls._read_fallback_plans()
        return [
            InstallmentPlan(**p) for p in plans
            if p.get("household_id") == household_id
        ]

    @classmethod
    def pay_installment(cls, plan_id: str) -> Optional[InstallmentPlan]:
        # Try Supabase first
        try:
            sb = supabase_client.get_client()
            res = sb.table("installment_plans").select("*").eq("id", plan_id).single().execute()
            if res.data:
                plan = InstallmentPlan(**res.data)
                plan.record_payment()
                sb.table("installment_plans").update({
                    "paid_installments": plan.paid_installments,
                    "status": plan.status,
                }).eq("id", plan_id).execute()
                return plan
        except Exception:
            pass

        # Fallback
        plans = cls._read_fallback_plans()
        for p in plans:
            if p.get("id") == plan_id:
                plan = InstallmentPlan(**p)
                plan.record_payment()
                p["paid_installments"] = plan.paid_installments
                p["status"] = plan.status
                cls._write_fallback_plans(plans)
                return plan
        return None
