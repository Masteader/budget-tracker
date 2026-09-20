"""
LangGraph state machine for the Budget Tracker AI microservice.

Flow:
  receive_sms → extract_fields → lookup_category → check_budget
             → [reallocate_if_needed] → write_transaction → END

Every node receives the full AgentState and returns a partial dict
with only the fields it mutates — LangGraph merges the rest automatically.
"""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime, date, timezone
from typing import Any

import litellm
from langgraph.graph import StateGraph, END

import supabase_client as db
from models import AgentState, CostControlCode

logger = logging.getLogger(__name__)

# ─── Module-level cache for cost control codes (loaded once at import time) ───
_cost_codes: list[CostControlCode] = []

ARABIC_TO_ENGLISH_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")


# =============================================================================
# HELPERS
# =============================================================================

def _normalise_arabic(text: str) -> str:
    """Transliterate Arabic-Indic numerals to ASCII digits."""
    return text.translate(ARABIC_TO_ENGLISH_DIGITS)


def _get_cost_codes() -> list[CostControlCode]:
    """Return cached cost control codes, fetching from Supabase on first call."""
    global _cost_codes
    if not _cost_codes:
        _cost_codes = db.fetch_all_cost_control_codes()
    return _cost_codes


def _first_day_of_month(dt: datetime) -> date:
    return dt.date().replace(day=1)


# =============================================================================
# NODE 1 — receive_sms
# Deduplication guard. Returns early if SMS was already processed.
# =============================================================================

def receive_sms(state: AgentState) -> dict[str, Any]:
    logger.info("[receive_sms] sender=%s household=%s", state.sender, state.household_id)

    # Allowed sender whitelist
    allowed = [s.strip().lower() for s in os.environ.get("ALLOWED_SENDERS", "snb,alrajhi").split(",")]
    if state.sender.lower() not in allowed:
        logger.warning("[receive_sms] Rejected: sender '%s' not in whitelist.", state.sender)
        return {"rejection_reason": f"Sender '{state.sender}' is not a whitelisted bank."}

    # Duplicate check
    if db.is_duplicate_sms(state.raw_sms, state.household_id):
        logger.warning("[receive_sms] Duplicate SMS detected — skipping.")
        return {"rejection_reason": "Duplicate SMS received within the deduplication window."}

    return {}   # pass-through


# =============================================================================
# NODE 2 — extract_fields
# Uses LiteLLM to parse amount, currency, merchant, and timestamp from raw SMS.
# =============================================================================

EXTRACTION_SYSTEM_PROMPT = """
You are a financial SMS parser for Saudi banks (SNB and Al Rajhi Bank).

Your job is to extract structured data from a bank SMS notification.
Respond ONLY with a valid JSON object — no markdown, no explanation.

Required fields:
  "amount"    : float  (the transaction amount; convert Arabic numerals if needed)
  "currency"  : string (default "SAR"; use "USD", "EUR" if explicitly stated)
  "merchant"  : string (business or person name; translate to English if Arabic)
  "timestamp" : string (ISO-8601 datetime; use the device received_at if not in SMS)
  "is_transaction": bool (false if this is an OTP, balance inquiry, or marketing SMS)

Rules:
- Arabic-Indic digits (٠-٩) must be converted to standard digits (0-9).
- If the merchant is in Arabic, provide an English transliteration.
- If no timestamp is in the SMS, output the value of received_at provided below.
- NEVER include any text outside the JSON object.
""".strip()


def extract_fields(state: AgentState) -> dict[str, Any]:
    logger.info("[extract_fields] Extracting from SMS (len=%d).", len(state.raw_sms))

    normalised_sms = _normalise_arabic(state.raw_sms)
    model = os.environ.get("LITELLM_MODEL", "gemini/gemini-2.0-flash-lite")

    user_content = (
        f"SMS text:\n{normalised_sms}\n\n"
        f"received_at: {state.received_at}\n"
        f"sender: {state.sender}"
    )

    try:
        response = litellm.completion(
            model=model,
            messages=[
                {"role": "system", "content": EXTRACTION_SYSTEM_PROMPT},
                {"role": "user", "content": user_content},
            ],
            temperature=0,
            max_tokens=300,
        )
        raw_json = response.choices[0].message.content.strip()

        # Strip markdown fences if model disobeys the system prompt
        raw_json = re.sub(r"^```(?:json)?\n?", "", raw_json)
        raw_json = re.sub(r"\n?```$", "", raw_json)

        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        logger.error("[extract_fields] JSON parse error: %s | raw=%s", exc, raw_json)
        return {"error": f"LLM returned non-JSON response: {exc}"}
    except Exception as exc:
        logger.error("[extract_fields] LiteLLM call failed: %s", exc)
        return {"error": f"LiteLLM error: {exc}"}

    if not parsed.get("is_transaction", True):
        return {"rejection_reason": "SMS is not a financial transaction (OTP/marketing)."}

    # Parse timestamp
    try:
        ts = datetime.fromisoformat(parsed["timestamp"].replace("Z", "+00:00"))
    except Exception:
        ts = datetime.now(timezone.utc)

    logger.info(
        "[extract_fields] amount=%.2f currency=%s merchant=%s timestamp=%s",
        parsed.get("amount", 0), parsed.get("currency", "SAR"),
        parsed.get("merchant", "?"), ts.isoformat(),
    )

    return {
        "amount": float(parsed.get("amount", 0)),
        "currency": parsed.get("currency", "SAR"),
        "merchant": parsed.get("merchant", "Unknown"),
        "timestamp": ts,
        "extraction_raw": raw_json,
    }


# =============================================================================
# NODE 3 — lookup_category
# Keyword-matches the merchant against cost_control_codes.
# Falls back to OPEX-MISC.
# =============================================================================

def lookup_category(state: AgentState) -> dict[str, Any]:
    if state.error or state.rejection_reason:
        return {}

    logger.info("[lookup_category] merchant='%s'", state.merchant)
    codes = _get_cost_codes()
    match = db.match_category(state.merchant or "", codes)

    if match:
        logger.info("[lookup_category] Matched: %s (%s)", match.code, match.category)
        return {"category_code": match.code, "category_name": match.category}
    else:
        # Fallback to OPEX-MISC
        misc = next((c for c in codes if c.code == "OPEX-MISC"), None)
        code = misc.code if misc else "OPEX-MISC"
        name = misc.category if misc else "Miscellaneous"
        logger.warning("[lookup_category] No keyword match — falling back to %s.", code)
        return {"category_code": code, "category_name": name}


# =============================================================================
# NODE 4 — check_budget
# Fetches the current month's budget for this category.
# =============================================================================

def check_budget(state: AgentState) -> dict[str, Any]:
    if state.error or state.rejection_reason:
        return {}

    month = _first_day_of_month(state.timestamp or datetime.now(timezone.utc))
    logger.info(
        "[check_budget] household=%s category=%s month=%s amount=%.2f",
        state.household_id, state.category_code, month, state.amount,
    )

    budget = db.fetch_budget(state.household_id, state.category_code, month)
    if not budget:
        # No budget set — log transaction without budget enforcement
        logger.warning("[check_budget] No budget row found; proceeding without enforcement.")
        return {
            "budget_id": None,
            "allocated_amount": None,
            "spent_amount": None,
            "remaining_balance": None,
        }

    return {
        "budget_id": budget.id,
        "allocated_amount": budget.allocated_amount,
        "spent_amount": budget.spent_amount,
        "remaining_balance": budget.remaining_amount,
    }


# =============================================================================
# NODE 5 — reallocate_if_needed
# If amount > remaining_balance, pull the deficit from flexible budgets.
# =============================================================================

def reallocate_if_needed(state: AgentState) -> dict[str, Any]:
    if state.error or state.rejection_reason:
        return {}

    # No enforcement needed if no budget was found or there's sufficient balance
    if state.remaining_balance is None or state.amount <= state.remaining_balance:
        return {}

    deficit = state.amount - state.remaining_balance
    logger.warning(
        "[reallocate] Budget insufficient! amount=%.2f remaining=%.2f deficit=%.2f",
        state.amount, state.remaining_balance, deficit,
    )

    month = _first_day_of_month(state.timestamp or datetime.now(timezone.utc))
    flexible = db.fetch_flexible_budgets(state.household_id, month, exclude_code=state.category_code)

    if not flexible:
        logger.warning("[reallocate] No flexible budgets available — proceeding anyway.")
        return {}

    # Cascade deductions across flexible budgets if needed
    remaining_deficit = deficit
    source_budget = None

    for flex_budget in flexible:
        if remaining_deficit <= 0:
            break
        deduction = min(remaining_deficit, flex_budget.remaining_amount)
        db.deduct_from_budget(flex_budget.id, deduction)
        remaining_deficit -= deduction
        if source_budget is None:
            source_budget = flex_budget  # track primary source for tagging
        logger.info(
            "[reallocate] Deducted %.2f from '%s' (id=%s).",
            deduction, flex_budget.category_code, flex_budget.id,
        )

    return {
        "is_reallocated": True,
        "reallocated_from_budget_id": source_budget.id if source_budget else None,
        "reallocated_from_category": source_budget.category_code if source_budget else None,
    }


# =============================================================================
# NODE 6 — write_transaction
# Inserts the final transaction record into Supabase.
# The DB trigger handles updating budgets.spent_amount automatically.
# =============================================================================

def write_transaction(state: AgentState) -> dict[str, Any]:
    if state.error or state.rejection_reason:
        return {}

    logger.info("[write_transaction] Inserting transaction for household=%s.", state.household_id)

    transaction_id = db.insert_transaction(
        household_id=state.household_id,
        amount=state.amount,
        currency=state.currency,
        merchant=state.merchant or "Unknown",
        category_code=state.category_code or "OPEX-MISC",
        timestamp=state.timestamp.isoformat() if state.timestamp else datetime.now(timezone.utc).isoformat(),
        raw_sms=state.raw_sms,
        is_reallocated=state.is_reallocated,
        reallocated_from_budget_id=state.reallocated_from_budget_id,
    )

    logger.info("[write_transaction] Done. transaction_id=%s", transaction_id)
    return {"transaction_id": transaction_id}


# =============================================================================
# ROUTING — conditional edges
# =============================================================================

def route_after_receive(state: AgentState) -> str:
    """If rejected at receive stage, skip to END."""
    if state.rejection_reason:
        return "end"
    return "extract_fields"


def route_after_extract(state: AgentState) -> str:
    """If extraction failed or SMS is non-transactional, skip to END."""
    if state.error or state.rejection_reason:
        return "end"
    return "lookup_category"


def route_after_check_budget(state: AgentState) -> str:
    """Decide whether reallocation is needed."""
    if state.error or state.rejection_reason:
        return "end"
    if (
        state.remaining_balance is not None
        and state.amount is not None
        and state.amount > state.remaining_balance
    ):
        return "reallocate_if_needed"
    return "write_transaction"


# =============================================================================
# GRAPH ASSEMBLY
# =============================================================================

def build_graph() -> Any:
    """Compile and return the LangGraph StateGraph."""
    builder = StateGraph(AgentState)

    # Add nodes
    builder.add_node("receive_sms", receive_sms)
    builder.add_node("extract_fields", extract_fields)
    builder.add_node("lookup_category", lookup_category)
    builder.add_node("check_budget", check_budget)
    builder.add_node("reallocate_if_needed", reallocate_if_needed)
    builder.add_node("write_transaction", write_transaction)

    # Entry point
    builder.set_entry_point("receive_sms")

    # Edges
    builder.add_conditional_edges(
        "receive_sms",
        route_after_receive,
        {"end": END, "extract_fields": "extract_fields"},
    )
    builder.add_conditional_edges(
        "extract_fields",
        route_after_extract,
        {"end": END, "lookup_category": "lookup_category"},
    )
    builder.add_edge("lookup_category", "check_budget")
    builder.add_conditional_edges(
        "check_budget",
        route_after_check_budget,
        {
            "end": END,
            "reallocate_if_needed": "reallocate_if_needed",
            "write_transaction": "write_transaction",
        },
    )
    builder.add_edge("reallocate_if_needed", "write_transaction")
    builder.add_edge("write_transaction", END)

    return builder.compile()


# Module-level compiled graph (imported by main.py)
sms_graph = build_graph()
