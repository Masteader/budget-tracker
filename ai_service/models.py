"""
Pydantic models for the Budget Tracker AI microservice.
All request/response bodies and internal data structures are defined here.
"""

from __future__ import annotations

from typing import Annotated, List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

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
# SUPABASE ROW MODELS  (used when reading from DB)
# =============================================================================

class CostControlCode(BaseModel):
    id: Optional[str] = None
    code: str
    category: str
    keywords: list[str]
    is_flexible: bool
    is_system: Optional[bool] = None
    household_id: Optional[str] = None


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


class SinkingFundEntry(BaseModel):
    """Accumulate setting of one sub-category (``_parent``: the category itself)."""
    model_config = ConfigDict(extra="forbid")

    accumulate: bool
    base_amount: Money


class SubAllocationsRequest(BaseModel):
    household_id: str
    category_code: Code
    cycle_key: Optional[str] = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")
    sub_allocations: dict[Code, Money] = Field(max_length=200)
    # The parent amount of a category budgeted without sub-category amounts; with them, their
    # sum is the parent amount, so both together are refused.
    allocated_amount: Optional[Money] = None
    # Stored as sub_allocations["_sinking_fund"]; {} clears it, None keeps the stored settings.
    sinking_fund: Optional[dict[Code, SinkingFundEntry]] = Field(default=None, max_length=201)

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)

    @model_validator(mode="after")
    def parent_amount_only_without_sub_amounts(self) -> "SubAllocationsRequest":
        if self.allocated_amount is not None and any(not k.startswith("_") for k in self.sub_allocations):
            raise ValueError("allocated_amount is only for a category without sub-category amounts")
        return self


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
    household_id: Optional[str] = None

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: Optional[str]) -> Optional[str]:
        return _uuid_validator(v) if v else None


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
    # Family households only (migration 20261105001300): the account the repayment is paid from,
    # and the client's idempotency key. Optional here so an old app without them gets HTTP 426
    # (app_update_required) instead of a validation error.
    account_id: Optional[str] = Field(default=None, description="Account the husband pays from (required in a family)")
    request_key: Optional[str] = Field(default=None, description="Client idempotency key (UUID), the same for every retry of one tap")
    wife_account_id: Optional[str] = Field(default=None, description="Her wife account the repayment credits (family)")

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)

    @field_validator("amount")
    @classmethod
    def validate_amount_precision(cls, v: float) -> float:
        # 422 for sub-halala input (FABLE2-API-04), like the Nafaqah repayment route.
        return _two_decimals(v)

    @field_validator("account_id", "request_key", "wife_account_id")
    @classmethod
    def validate_optional_ids(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _required_uuid(v)


def _two_decimals(v: float) -> float:
    """SAR amounts are numeric(14,2): reject sub-halala precision instead of rounding it away."""
    from decimal import Decimal

    if Decimal(str(v)) != Decimal(str(v)).quantize(Decimal("0.01")):
        raise ValueError("Amount must have at most 2 decimal places")
    return v


class NafaqahReimbursementCreateRequest(BaseModel):
    """Husband → wife repayment of her Nafaqah advances (family households only)."""
    amount: PositiveMoney = Field(..., description="Repayment in SAR (partial or full; never above the outstanding balance)")
    payment_method: str = Field(default="cash", pattern=r"^(stc_pay|urpay|bank_transfer|iban|cash|other)$")
    notes: Optional[str] = Field(default=None, max_length=500)
    wife_user_id: Optional[str] = Field(default=None, description="Required only when the household has several wives")
    # Migration 20261105001300: the account he pays from (his own, or a shared pool for an admin)
    # and the idempotency key, both required. Optional here so an old app that sends neither gets
    # HTTP 426 (app_update_required) instead of a validation error.
    account_id: Optional[str] = Field(default=None, description="Account the repayment is paid from (required)")
    request_key: Optional[str] = Field(default=None, description="Client idempotency key (UUID), required")
    # Section 12: her wife account the repayment credits (one of hers, not archived).
    wife_account_id: Optional[str] = Field(default=None, description="Her wife account the repayment credits (required)")

    @field_validator("amount")
    @classmethod
    def validate_amount_precision(cls, v: float) -> float:
        return _two_decimals(v)

    @field_validator("wife_user_id")
    @classmethod
    def validate_wife_uuid(cls, v: Optional[str]) -> Optional[str]:
        return _uuid_validator(v)

    @field_validator("account_id", "request_key", "wife_account_id")
    @classmethod
    def validate_optional_ids(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _required_uuid(v)


def _required_uuid(v: str) -> str:
    """A UUID, normalised to lowercase text (the client's idempotency key)."""
    try:
        return str(UUID(str(v)))
    except (ValueError, AttributeError, TypeError):
        raise ValueError("Invalid UUID")


class NafaqahRepaymentRequestCreate(BaseModel):
    """The wife's "I received X" (migration 20261105001300): a pending request the husband or an
    admin approves or declines. Nothing moves until then."""
    model_config = ConfigDict(extra="forbid")

    amount: PositiveMoney = Field(..., description="What she received, in SAR")
    payment_method: str = Field(default="cash", pattern=r"^(stc_pay|urpay|bank_transfer|iban|cash|other)$")
    request_key: str = Field(..., description="Client idempotency key (UUID), the same for every retry of one tap")
    # Section 12: the wife account she received it into (one of hers).
    wife_account_id: Optional[str] = Field(default=None, description="Her wife account it went into (required)")

    @field_validator("amount")
    @classmethod
    def validate_amount_precision(cls, v: float) -> float:
        return _two_decimals(v)

    @field_validator("request_key")
    @classmethod
    def validate_request_key(cls, v: str) -> str:
        return _required_uuid(v)

    @field_validator("wife_account_id")
    @classmethod
    def validate_wife_account(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _required_uuid(v)


class NafaqahRepaymentRequestApprove(BaseModel):
    """Approving her request: the account the requested amount is paid from, and optionally
    another of her wife accounts than the one she named."""
    model_config = ConfigDict(extra="forbid")

    account_id: str = Field(..., description="Account the husband (or an admin) pays from")
    request_key: str = Field(..., description="Client idempotency key (UUID)")
    wife_account_id: Optional[str] = Field(default=None, description="Another of her wife accounts to credit")

    @field_validator("account_id", "request_key")
    @classmethod
    def validate_ids(cls, v: str) -> str:
        return _required_uuid(v)

    @field_validator("wife_account_id")
    @classmethod
    def validate_wife_account(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _required_uuid(v)


class WifeAccountCreateRequest(BaseModel):
    """Her husband makes her a wife account (section 12 of 20261105001300)."""
    model_config = ConfigDict(extra="forbid")

    wife_user_id: str = Field(..., description="The wife it is assigned to")
    name: str = Field(..., max_length=200, description="Its name, 1 to 60 characters once trimmed")

    @field_validator("wife_user_id")
    @classmethod
    def validate_wife(cls, v: str) -> str:
        return _required_uuid(v)


class WifeAccountAssignRequest(BaseModel):
    """Her husband corrects whom a wife account is assigned to, before it has history."""
    model_config = ConfigDict(extra="forbid")

    wife_user_id: str = Field(..., description="The wife it is assigned to")

    @field_validator("wife_user_id")
    @classmethod
    def validate_wife(cls, v: str) -> str:
        return _required_uuid(v)


class NafaqahRepaymentRequestDecline(BaseModel):
    """Declining her request, with an optional short reason; nothing moves."""
    model_config = ConfigDict(extra="forbid")

    reason: Optional[str] = Field(default=None, max_length=200)


class NafaqahReversalRequest(BaseModel):
    """Reversing a tracked repayment or payment in full (the money goes back, the amount is owed again)."""
    model_config = ConfigDict(extra="forbid")

    request_key: str = Field(..., description="Client idempotency key (UUID)")

    @field_validator("request_key")
    @classmethod
    def validate_request_key(cls, v: str) -> str:
        return _required_uuid(v)


class FormerMemberDebtPaymentRequest(BaseModel):
    """A payment of what was owed to a former member (migration 20261105001200). The same fields
    as an ordinary reimbursement: an amount, a payment method and, since 20261105001300, the account
    it is paid from (required; optional here so an old app gets HTTP 426, app_update_required)."""
    model_config = ConfigDict(extra="forbid")

    amount: PositiveMoney = Field(..., description="Payment in SAR (partial or full; never above what remains)")
    payment_method: str = Field(default="cash", pattern=r"^(stc_pay|urpay|bank_transfer|iban|cash|other)$")
    request_key: str = Field(..., description="Client idempotency key (UUID), the same for every retry of one tap")
    account_id: Optional[str] = Field(default=None, description="Account the payment is paid from (required)")

    @field_validator("account_id")
    @classmethod
    def validate_account_id(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _required_uuid(v)

    @field_validator("amount")
    @classmethod
    def validate_amount_precision(cls, v: float) -> float:
        return _two_decimals(v)

    @field_validator("request_key")
    @classmethod
    def validate_request_key(cls, v: str) -> str:
        return _required_uuid(v)


class FormerMemberDebtWaiverRequest(BaseModel):
    """Her release (إبراء) of what remains of a former member's record."""
    model_config = ConfigDict(extra="forbid")

    request_key: str = Field(..., description="Client idempotency key (UUID)")

    @field_validator("request_key")
    @classmethod
    def validate_request_key(cls, v: str) -> str:
        return _required_uuid(v)


class NafaqahAllowanceSetRequest(BaseModel):
    """Wife personal allowance (مصروفها) for one salary cycle, set by the husband/admin."""
    amount: Money = Field(..., description="Allowance in SAR for the cycle (0 allowed)")
    cycle_key: Optional[str] = Field(default=None, pattern=r"^[0-9]{4}-(0[1-9]|1[0-2])$")
    wife_user_id: Optional[str] = None

    @field_validator("amount")
    @classmethod
    def validate_amount_precision(cls, v: float) -> float:
        return _two_decimals(v)

    @field_validator("wife_user_id")
    @classmethod
    def validate_wife_uuid(cls, v: Optional[str]) -> Optional[str]:
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
    # Bounded like every other code (FABLE2-API-02): a member's key is written into the
    # admin-only budgets row; sub_code must also name an allocation / sub-category (422).
    category_code: Code
    sub_code: Code
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
    support_email: str = "fmscoinfo@fmsco.com.sa"


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


class CategoryReplaceRequest(BaseModel):
    household_id: str
    old_code: Code
    new_name: ShortText
    new_code: Optional[Code] = None
    cycle_key: Optional[str] = None
    update_past_transactions: bool = False

    @field_validator("household_id")
    @classmethod
    def validate_household_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class DependentCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80, description="Member or dependent name")
    avatar_icon: Optional[str] = Field("child", max_length=40, description="Icon representation")
    relationship: Optional[str] = Field("child", max_length=40, description="Role: 'spouse', 'peer', 'child', 'dependent'")
    monthly_allowance: Optional[Money] = Field(0.0, description="Monthly allocated allowance in SAR")


class PrimaryAdminTransferRequest(BaseModel):
    """The primary admin hands primary ownership of the household to another member."""
    new_primary_user_id: str = Field(..., description="User id of the member who becomes the primary admin")

    @field_validator("new_primary_user_id")
    @classmethod
    def validate_new_primary_uuid(cls, v: str) -> str:
        return _uuid_validator(v)


class NafaqahProviderSetRequest(BaseModel):
    """The household's Nafaqah provider (husband): a non-spouse member, chosen by an admin."""
    user_id: str = Field(..., description="Member to name as the Nafaqah provider")

    @field_validator("user_id")
    @classmethod
    def validate_provider_uuid(cls, v: str) -> str:
        return _uuid_validator(v)





class HouseholdTypeUpdateRequest(BaseModel):
    """An admin switches the household type (owner decision D1, migration 20261020900000)."""
    household_type: str = Field(..., pattern="^(family|roommates)$", description="'family' or 'roommates'")


class MemberFinancialRoleUpdateRequest(BaseModel):
    """An admin sets a member's financial role within the household type (FABLE2-DB-07)."""
    financial_role: str = Field(
        ...,
        pattern="^(provider|spouse|peer|family_member|dependent)$",
        description="family: 'spouse' | 'family_member' | 'dependent'; roommates: 'peer'",
    )
