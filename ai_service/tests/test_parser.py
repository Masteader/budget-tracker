"""
pytest test suite for the Budget Tracker LangGraph AI microservice.

Tests cover:
  1. Arabic debit SMS (Tamimi / Al Rajhi)
  2. English debit SMS (Jarir / Al Rajhi)
  3. English debit SMS (Starbucks / SNB)
  4. Duplicate SMS deduplication
  5. Non-transactional SMS (OTP) rejection

Run with:
  cd ai_service
  pytest tests/test_parser.py -v
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

# ── Import the FastAPI app (loads graph, models, etc.) ────────────────────────
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from main import app
from models import AgentState

# =============================================================================
# FIXTURES
# =============================================================================

HOUSEHOLD_ID = "11111111-1111-1111-1111-111111111111"
BUDGET_ID    = "22222222-2222-2222-2222-222222222222"


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def mock_supabase(monkeypatch):
    """
    Patches all supabase_client functions used by the LangGraph nodes
    so tests don't require a live Supabase project.
    """
    from models import CostControlCode, BudgetRow

    monkeypatch.setattr("main._verify_signature", lambda body, sig: True)

    grocery_code = CostControlCode(
        id="ccc-1", code="OPEX-GROCERY", category="Grocery",
        keywords=["tamimi", "تميمي", "danube", "carrefour"],
        is_flexible=False,
    )
    books_code = CostControlCode(
        id="ccc-2", code="CAPEX-EDUCATION", category="Education",
        keywords=["jarir", "مكتبة جرير"],
        is_flexible=False,
    )
    dining_code = CostControlCode(
        id="ccc-3", code="OPEX-DINING", category="Dining",
        keywords=["starbucks", "ستاربكس", "mcdonald"],
        is_flexible=True,
    )
    misc_code = CostControlCode(
        id="ccc-4", code="OPEX-MISC", category="Miscellaneous",
        keywords=["misc", "payment"],
        is_flexible=True,
    )

    mock_budget = BudgetRow(
        id=BUDGET_ID,
        household_id=HOUSEHOLD_ID,
        month="2026-09-01",
        category_code="OPEX-GROCERY",
        allocated_amount=1000.0,
        spent_amount=400.0,
        remaining_amount=600.0,
    )

    import supabase_client as db

    monkeypatch.setattr(db, "fetch_all_cost_control_codes",
                        lambda: [grocery_code, books_code, dining_code, misc_code])
    monkeypatch.setattr(db, "fetch_budget",
                        lambda hid, code, month: mock_budget)
    monkeypatch.setattr(db, "fetch_flexible_budgets",
                        lambda hid, month, exclude_code: [])
    monkeypatch.setattr(db, "insert_transaction",
                        lambda **kwargs: "tx-test-uuid-0001")
    monkeypatch.setattr(db, "is_duplicate_sms",
                        lambda raw, hid: False)
    monkeypatch.setattr(db, "deduct_from_budget",
                        lambda bid, amount: None)
    monkeypatch.setattr(db, "reallocate_budget",
                        lambda from_id, to_id, amount: None)

    return {
        "grocery_code": grocery_code,
        "books_code": books_code,
        "dining_code": dining_code,
        "mock_budget": mock_budget,
    }


def _make_payload(raw_sms: str, sender: str = "SNB") -> dict:
    return {
        "raw_sms": raw_sms,
        "sender": sender,
        "received_at": datetime.now(timezone.utc).isoformat(),
        "household_id": HOUSEHOLD_ID,
    }


# =============================================================================
# HELPER — mock LiteLLM response
# =============================================================================

def _mock_llm_response(amount: float, currency: str, merchant: str,
                        is_transaction: bool = True):
    """Build a fake litellm.completion return value."""
    content = json.dumps({
        "amount": amount,
        "currency": currency,
        "merchant": merchant,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "is_transaction": is_transaction,
    })
    mock_msg = MagicMock()
    mock_msg.content = content
    mock_choice = MagicMock()
    mock_choice.message = mock_msg
    mock_resp = MagicMock()
    mock_resp.choices = [mock_choice]
    return mock_resp


# =============================================================================
# TEST 1 — Arabic debit SMS (Al Rajhi / Tamimi)
# =============================================================================

@pytest.mark.asyncio
async def test_arabic_grocery_sms(mock_supabase):
    """
    Arabic SMS from Al Rajhi debiting SAR 450 at Tamimi supermarket.
    Expected: amount=450, category=OPEX-GROCERY, merchant contains 'Tamimi'.
    """
    raw_sms = "تم خصم ٤٥٠٫٠٠ ريال من حسابك لدى تميمي للأسواق رقم العملية 123456"

    with patch("litellm.completion",
               return_value=_mock_llm_response(450.0, "SAR", "Tamimi")):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="ALRAJHI"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["amount"] == 450.0
    assert body["category_code"] == "OPEX-GROCERY"
    assert "Tamimi" in (body["merchant"] or "")
    assert body["is_reallocated"] is False


# =============================================================================
# TEST 2 — English debit SMS (Al Rajhi / Jarir)
# =============================================================================

@pytest.mark.asyncio
async def test_english_education_sms(mock_supabase):
    """
    English SMS from Al Rajhi debiting SAR 1,250.75 at Jarir Bookstore.
    Expected: amount=1250.75, category=CAPEX-EDUCATION.
    """
    raw_sms = "Al Rajhi Bank: SAR 1,250.75 was debited from your account for purchase at JARIR BOOKSTORE. Ref: 789012"

    with patch("litellm.completion",
               return_value=_mock_llm_response(1250.75, "SAR", "Jarir Bookstore")):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="ALRAJHI"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["amount"] == 1250.75
    assert body["category_code"] == "CAPEX-EDUCATION"


# =============================================================================
# TEST 3 — English debit SMS (SNB / Starbucks)
# =============================================================================

@pytest.mark.asyncio
async def test_english_dining_sms(mock_supabase):
    """
    English SMS from SNB debiting SAR 89 at Starbucks.
    Expected: amount=89, category=OPEX-DINING.
    """
    raw_sms = "SNB: Purchase of SAR 89.00 at STARBUCKS COFFEE approved. Available balance: SAR 5,421.00"

    with patch("litellm.completion",
               return_value=_mock_llm_response(89.0, "SAR", "Starbucks")):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="SNB"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["amount"] == 89.0
    assert body["category_code"] == "OPEX-DINING"


# =============================================================================
# TEST 4 — Duplicate SMS deduplication
# =============================================================================

@pytest.mark.asyncio
async def test_duplicate_sms_rejected(mock_supabase, monkeypatch):
    """
    Same SMS submitted twice within the deduplication window.
    Second request must be rejected with status='rejected'.
    """
    import supabase_client as db
    monkeypatch.setattr(db, "is_duplicate_sms", lambda raw, hid: True)

    raw_sms = "تم خصم ٤٥٠٫٠٠ ريال من حسابك لدى تميمي للأسواق"

    with patch("litellm.completion",
               return_value=_mock_llm_response(450.0, "SAR", "Tamimi")):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="ALRAJHI"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "rejected"
    assert "Duplicate" in (body.get("message") or "")


# =============================================================================
# TEST 5 — OTP / non-transactional SMS rejection
# =============================================================================

@pytest.mark.asyncio
async def test_otp_sms_rejected(mock_supabase):
    """
    An OTP SMS must be gracefully rejected, not logged as a transaction.
    Expected: status='rejected', no transaction_id.
    """
    raw_sms = "SNB: Your One-Time Password is 483920. Do not share this code with anyone."

    with patch("litellm.completion",
               return_value=_mock_llm_response(
                   0, "SAR", "OTP", is_transaction=False)):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="SNB"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "rejected"
    assert body.get("transaction_id") is None


# =============================================================================
# TEST 6 — Budget reallocation on deficit
# =============================================================================

@pytest.mark.asyncio
async def test_budget_reallocation_triggers(mock_supabase, monkeypatch):
    """
    When transaction amount exceeds remaining budget, reallocation pulls funds
    from flexible budgets.
    """
    from models import BudgetRow
    import supabase_client as db

    # Low balance budget for Grocery
    tight_budget = BudgetRow(
        id=BUDGET_ID,
        household_id=HOUSEHOLD_ID,
        month="2026-09-01",
        category_code="OPEX-GROCERY",
        allocated_amount=500.0,
        spent_amount=480.0,
        remaining_amount=20.0,
    )
    # Flexible budget with headroom
    flex_budget = BudgetRow(
        id="flex-budget-1234",
        household_id=HOUSEHOLD_ID,
        month="2026-09-01",
        category_code="OPEX-DINING",
        allocated_amount=400.0,
        spent_amount=100.0,
        remaining_amount=300.0,
    )

    reallocated_calls = []
    monkeypatch.setattr(db, "fetch_budget", lambda hid, code, month: tight_budget)
    monkeypatch.setattr(db, "fetch_flexible_budgets", lambda hid, month, exclude_code=None: [flex_budget])
    monkeypatch.setattr(
        db, "reallocate_budget",
        lambda from_id, to_id, amount: reallocated_calls.append((from_id, to_id, amount))
    )

    # 100 SAR purchase on a 20 SAR remaining budget -> deficit is 80 SAR
    raw_sms = "SNB: Purchase of SAR 100.00 at Tamimi Markets approved."

    with patch("litellm.completion",
               return_value=_mock_llm_response(100.0, "SAR", "Tamimi")):
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/webhook/sms",
                json=_make_payload(raw_sms, sender="SNB"),
            )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["is_reallocated"] is True
    assert len(reallocated_calls) == 1
    # Check that 80 SAR was transferred from flex_budget to tight_budget
    from_id, to_id, amt = reallocated_calls[0]
    assert from_id == flex_budget.id
    assert to_id == tight_budget.id
    assert amt == 80.0

