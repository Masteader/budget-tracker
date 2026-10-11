import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from unittest.mock import MagicMock
from chat_parser import process_chat_transaction, ParsedChatExpense

def test_shawarma_chat_expense_preview_returns_dining_sub_category(monkeypatch):
    """Verify Beit Al Shawarma generates OPEX-DINING with restaurants_dinners subcategory in preview."""
    from dependents_service import _memory_dependents
    _memory_dependents["test-household-001"] = [
        {"id": "dep-1", "name": "Sarah", "avatar_icon": "child", "household_id": "test-household-001"}
    ]

    mock_parsed = ParsedChatExpense(
        merchant="Beit Al Shawarma",
        total_amount=10.0,
        currency="SAR",
        category_code="OPEX-DINING",
        sub_category="restaurants_dinners",
        paid_by="me",
        beneficiary="me",
        items=[{"name": "سندويش شاورما", "price": 10.0, "quantity": 1, "sub_category": "restaurants_dinners"}],
        notes="Dinner"
    )
    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda msg, household_id=None: mock_parsed)

    msg = "ضيف سندويش شاورما 10 ريال من بيت الشاورما تحت بند المطاعم"
    res = process_chat_transaction(
        household_id="test-household-001",
        message=msg,
        preview_only=True
    )
    assert res["status"] == "pending_confirmation"
    assert res["category_code"] == "OPEX-DINING"
    assert res["sub_category"] == "restaurants_dinners"
    assert "available_sub_categories" in res
    assert res["paid_by"] == "me"
    assert res["beneficiary"] == "me"
    assert "Sarah" in res["dependents"]
    assert len(res["items"]) >= 1
    assert res["items"][0]["sub_category"] == "restaurants_dinners"


def test_child_attribution_in_chat_expense(monkeypatch):
    """Verify mention of child is reflected in beneficiary field."""
    from dependents_service import _memory_dependents
    _memory_dependents["test-household-001"] = [
        {"id": "dep-1", "name": "Sarah", "avatar_icon": "child", "household_id": "test-household-001"}
    ]

    mock_parsed = ParsedChatExpense(
        merchant="Nahdi",
        total_amount=120.0,
        currency="SAR",
        category_code="OPEX-HEALTH",
        sub_category="prescriptions_meds",
        paid_by="me",
        beneficiary="Sarah",
        items=[{"name": "حفاضات وحليب", "price": 120.0, "quantity": 1, "sub_category": "prescriptions_meds"}],
        notes="Kids medicine"
    )
    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda msg, household_id=None: mock_parsed)

    msg = "اشتريت حفاضات وحليب لسارة بـ 120 ريال من النهدي"
    res = process_chat_transaction(
        household_id="test-household-001",
        message=msg,
        preview_only=True
    )
    assert res["status"] == "pending_confirmation"
    assert res["paid_by"] == "me"
    assert res["beneficiary"] == "Sarah"
    assert "Sarah" in res["dependents"]
