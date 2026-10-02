"""
Pydantic models for the Budget Tracker AI microservice.
All request/response bodies and internal data structures are defined here.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


# =============================================================================
# INBOUND — Flutter → FastAPI
# =============================================================================

class SMSWebhookRequest(BaseModel):
    """Payload sent by the Android Flutter app when an SMS is intercepted."""

    raw_sms: str = Field(..., description="Raw SMS body text (Arabic or English).")
    sender: str = Field(..., description="SMS sender ID, e.g. 'SNB' or 'AlRajhi'.")
    received_at: str = Field(..., description="ISO-8601 timestamp of when the SMS arrived on the device.")
    household_id: str = Field(..., description="UUID of the household to log the transaction against.")
    device_id: Optional[str] = Field(None, description="Optional device identifier for audit.")

    @field_validator("raw_sms")
    @classmethod
    def sms_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("raw_sms must not be empty.")
        return v.strip()


# =============================================================================
# OUTBOUND — FastAPI → Flutter
# =============================================================================

class SMSWebhookResponse(BaseModel):
    """Response returned after the LangGraph agent finishes processing."""

    status: str = Field(..., description="'success' | 'rejected' | 'error'")
    transaction_id: Optional[str] = Field(None, description="UUID of the created transaction row.")
    category_code: Optional[str] = Field(None, description="Assigned cost control code, e.g. 'OPEX-GROCERY'.")
    amount: Optional[float] = Field(None)
    merchant: Optional[str] = Field(None)
    is_reallocated: bool = Field(False)
    reallocated_from_category: Optional[str] = Field(None)
    source: str = Field("sms", description="'sms' | 'chat' | 'receipt_scan' | 'manual'")
    items: list[dict] = Field(default_factory=list, description="Itemized breakdown")
    receipt_url: Optional[str] = None
    message: Optional[str] = Field(None, description="Human-readable status detail.")


# =============================================================================
# INTERNAL — LangGraph AgentState
# =============================================================================

class AgentState(BaseModel):
    """
    The complete mutable state passed between every LangGraph node.
    All fields start as None and are populated progressively through the graph.
    """

    # ── Input ──────────────────────────────────────────────────────────────
    raw_sms: str
    sender: str
    received_at: str
    household_id: str
    device_id: Optional[str] = None
    source: str = "sms"
    items: list[dict] = Field(default_factory=list)
    receipt_url: Optional[str] = None

    # ── Extracted by LiteLLM ───────────────────────────────────────────────
    amount: Optional[float] = None
    currency: str = "SAR"
    merchant: Optional[str] = None
    timestamp: Optional[datetime] = None
    extraction_raw: Optional[str] = None  # raw JSON string from LLM (for debug)

    # ── Categorization ──────────────────────────────────────────────────────
    category_code: Optional[str] = None
    category_name: Optional[str] = None

    # ── Budget check ────────────────────────────────────────────────────────
    budget_id: Optional[str] = None
    allocated_amount: Optional[float] = None
    spent_amount: Optional[float] = None
    remaining_balance: Optional[float] = None

    # ── Reallocation ────────────────────────────────────────────────────────
    is_reallocated: bool = False
    reallocated_from_budget_id: Optional[str] = None
    reallocated_from_category: Optional[str] = None

    # ── Output ──────────────────────────────────────────────────────────────
    transaction_id: Optional[str] = None

    # ── Control flow ────────────────────────────────────────────────────────
    error: Optional[str] = None          # Non-empty → graph routes to END early
    rejection_reason: Optional[str] = None  # Non-transactional SMS

    model_config = ConfigDict(arbitrary_types_allowed=True)


# =============================================================================
# SUPABASE ROW MODELS  (used when reading from DB)
# =============================================================================

class CostControlCode(BaseModel):
    id: str
    code: str
    category: str
    keywords: list[str]
    is_flexible: bool


class BudgetRow(BaseModel):
    id: str
    household_id: str
    month: str            # '2026-09-01'
    category_code: str
    allocated_amount: float
    spent_amount: float
    remaining_amount: float
    cycle_key: Optional[str] = None
    previous_cycle_delta: float = 0.0
    is_active: bool = True


# =============================================================================
# SALARY CYCLE & SUB-BUDGET BREAKDOWN MODELS
# =============================================================================

class SalaryCycleInfo(BaseModel):
    cycle_key: str
    cycle_start: str
    cycle_end: str
    label: str
    month_name: str
    is_current: Optional[bool] = None


class SubCategoryBreakdownItem(BaseModel):
    sub_code: Optional[str] = None
    name: str
    allocated_amount: float = 0.0
    spent_amount: float
    transaction_count: int


class CategoryBreakdownItem(BaseModel):
    category_code: str
    category_name: str
    allocated_amount: float
    spent_amount: float
    remaining_amount: float
    previous_cycle_delta: float = 0.0
    sub_categories: list[SubCategoryBreakdownItem] = Field(default_factory=list)


class BudgetBreakdownResponse(BaseModel):
    cycle_key: str
    cycle_info: SalaryCycleInfo
    categories: list[CategoryBreakdownItem]


class CategoryCreateRequest(BaseModel):
    household_id: str
    code: str
    category: str
    allocated_amount: float = 0.0
    is_flexible: bool = True
    keywords: list[str] = Field(default_factory=list)


class SubAllocationsRequest(BaseModel):
    household_id: str
    category_code: str
    cycle_key: Optional[str] = None
    sub_allocations: dict[str, float]


