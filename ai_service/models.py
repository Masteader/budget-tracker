"""
Pydantic models for the Budget Tracker AI microservice.
All request/response bodies and internal data structures are defined here.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

# Monetary inputs: finite, non-negative, bounded. Pydantic floats accept NaN/Infinity by default
# (and Starlette's JSON parser accepts the NaN/Infinity literals), which Postgres numeric stores,
# corrupting budget totals.
MAX_SAR_AMOUNT = 10_000_000
Money = Annotated[float, Field(ge=0, le=MAX_SAR_AMOUNT, allow_inf_nan=False)]
PositiveMoney = Annotated[float, Field(gt=0, le=MAX_SAR_AMOUNT, allow_inf_nan=False)]
Code = Annotated[str, Field(min_length=1, max_length=60)]
ShortText = Annotated[str, Field(min_length=1, max_length=120)]
Keyword = Annotated[str, Field(max_length=60)]


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


def _uuid_validator(v: Optional[str]) -> Optional[str]:
    """Validate household_id is a proper UUID string."""
    if v is None:
        return v
    try:
        UUID(str(v))
    except (ValueError, AttributeError):
        raise ValueError(f"Invalid UUID: {v}")
    return str(v)


class CategoryCreateRequest(BaseModel):
    household_id: str
    code: Code
    category: ShortText
    allocated_amount: Money = 0.0
    is_flexible: bool = True
    keywords: list[Keyword] = Field(default_factory=list, max_length=50)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class SubAllocationsRequest(BaseModel):
    household_id: str
    category_code: Code
    cycle_key: Optional[str] = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")
    sub_allocations: dict[Code, Money] = Field(max_length=200)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class SubCategoryCreateRequest(BaseModel):
    household_id: str
    parent_code: Code
    name_en: ShortText
    allocated_amount: Money = 0.0
    sub_code: Optional[Code] = None
    cycle_key: Optional[str] = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class SubCategoryRenameRequest(BaseModel):
    parent_code: Code
    sub_code: Code
    name_en: ShortText
    name_ar: Optional[ShortText] = None


class PaydayUpdateRequest(BaseModel):
    payday_day: int = Field(..., ge=1, le=31, description="Configured monthly payday day (1-31)")


class RolloverRuleUpdateRequest(BaseModel):
    rollover_rule: str = Field(
        ...,
        pattern="^(send_to_savings|rollover_to_categories|fresh_start)$",
        description="Budget rollover rule for end of salary cycle: 'send_to_savings', 'rollover_to_categories', or 'fresh_start'",
    )


class HouseholdInviteCreateRequest(BaseModel):
    role: str = Field(
        default="peer",
        pattern="^(spouse|peer|family_member|dependent)$",
        description="Assigned role for invited member: 'spouse', 'peer', or 'family_member'",
    )
    target_member_id: Optional[str] = Field(
        default=None,
        description="Optional pre-created manual member ID to bind this invite to",
    )


class HouseholdProfileClaimRequest(BaseModel):
    user_id: str = Field(..., description="ID of the live user claiming the pre-created profile")


class HouseholdReimbursementRequest(BaseModel):
    household_id: str
    payer_id: ShortText
    recipient_id: ShortText
    amount: PositiveMoney = Field(..., description="Settlement reimbursement amount in SAR")
    payment_method: str = Field(default="stc_pay", max_length=20, description="Payment method: 'stc_pay', 'urpay', 'iban', 'cash'")
    notes: Optional[str] = Field(default=None, max_length=500)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class ShoppingBasketOptimizeRequest(BaseModel):
    household_id: str
    items: List[ShortText] = Field(default_factory=list, max_length=200, description="List of grocery item names to price and optimize")

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class RecurringBillToggleRequest(BaseModel):
    household_id: str
    category_code: str
    sub_code: str
    is_recurring: bool = True
    due_day: Optional[int] = Field(default=None, ge=1, le=31)
    custom_name: Optional[str] = Field(default=None, max_length=120)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class SupportChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    household_id: Optional[str] = None
    user_id: Optional[str] = None  # ignored: the caller is identified by the JWT
    history: Optional[List[dict]] = Field(default=None, max_length=50)
    language: Optional[str] = Field(default="ar", max_length=8)


class SupportChatResponse(BaseModel):
    reply: str
    escalate_to_developer: bool = False
    summary: Optional[str] = None
    support_email: str = "abedmowafaq@gmail.com"


class HouseholdIncomeRequest(BaseModel):
    monthly_income: Money = Field(..., description="Monthly household salary/income in SAR")


class HouseholdIncomeResponse(BaseModel):
    household_id: str
    monthly_income: float
    status: str = "success"


class CategoryToggleRequest(BaseModel):
    category_code: Code
    is_active: bool


class CustomCategoryCreateRequest(BaseModel):
    code: Code
    category: ShortText
    keywords: List[Keyword] = Field(default_factory=list, max_length=50)
    is_flexible: bool = False
    allocated_amount: Money = 0.0


class DependentCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80, description="Member or dependent name")
    avatar_icon: Optional[str] = Field("child", max_length=40, description="Icon representation")
    relationship: Optional[str] = Field("child", max_length=40, description="Role: 'spouse', 'peer', 'child', 'dependent'")
    monthly_allowance: Optional[Money] = Field(0.0, description="Monthly allocated allowance in SAR")



