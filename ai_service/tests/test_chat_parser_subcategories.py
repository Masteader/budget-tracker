import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from unittest.mock import MagicMock
from chat_parser import process_chat_transaction, ParsedChatExpense

def test_shawarma_chat_expense_preview_returns_dining_sub_category(monkeypatch, fake_supabase):
    """Verify Beit Al Shawarma generates OPEX-DINING with restaurants_dinners subcategory in preview."""
    fake_supabase.seed("household_dependents", [
        {"id": "dep-1", "name": "Sarah", "avatar_icon": "child", "household_id": "test-household-001", "created_at": "2026-10-01T00:00:00+00:00"}
    ])

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


def test_child_attribution_in_chat_expense(monkeypatch, fake_supabase):
    """Verify mention of child is reflected in beneficiary field."""
    fake_supabase.seed("household_dependents", [
        {"id": "dep-1", "name": "Sarah", "avatar_icon": "child", "household_id": "test-household-001", "created_at": "2026-10-01T00:00:00+00:00"}
    ])

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


def test_confirm_chat_transaction_preserves_category_sub_category_and_attribution(monkeypatch):
    """Verify confirming pending expense persists category_code and sub_category rather than falling back to OPEX-MISC."""
    mock_insert = MagicMock(return_value="tx-uuid-1234")
    monkeypatch.setattr("chat_parser.insert_transaction", mock_insert)
    monkeypatch.setattr("chat_parser.enrich_transaction_items", lambda tx_id, items: True)
    monkeypatch.setattr("chat_parser.fetch_budget", lambda *args, **kwargs: None)
    monkeypatch.setattr("chat_parser.find_duplicate_candidate", lambda *args, **kwargs: None)

    mock_parsed = ParsedChatExpense(
        merchant="Albaik",
        total_amount=25.0,
        currency="SAR",
        category_code="OPEX-DINING",
        sub_category="restaurants_dinners",
        paid_by="me",
        beneficiary="me",
        items=[{"name": "big baik sandwich", "price": 25.0, "quantity": 1}],
        notes="Dinner"
    )
    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda msg, household_id=None: mock_parsed)

    res = process_chat_transaction(
        household_id="test-household-001",
        message="big baik sandwich 25 sar",
        preview_only=False,
        allow_duplicate=True,
        override_merchant="Albaik",
        override_category_code="OPEX-DINING",
        override_sub_category="restaurants_dinners",
        override_paid_by="partner",
        override_beneficiary="both",
    )

    assert res["status"] == "success"
    assert res["category_code"] == "OPEX-DINING"
    assert res["sub_category"] == "restaurants_dinners"
    assert res["paid_by"] == "partner"
    assert res["beneficiary"] == "both"

    mock_insert.assert_called_once()
    kwargs = mock_insert.call_args.kwargs
    assert kwargs["category_code"] == "OPEX-DINING"
    assert kwargs["sub_category"] == "restaurants_dinners"
    assert kwargs["paid_by"] == "partner"
    assert kwargs["beneficiary"] == "both"
    assert kwargs["items"][0]["sub_category"] == "restaurants_dinners"


def test_chat_confirmation_overrides_items_stale_sub_category(monkeypatch):
    """Verify that user override_sub_category replaces initial parsed sub_category on line items."""
    mock_insert = MagicMock(return_value="tx-zain-001")
    monkeypatch.setattr("chat_parser.insert_transaction", mock_insert)
    monkeypatch.setattr("chat_parser.fetch_budget", lambda *args, **kwargs: None)

    mock_parsed = ParsedChatExpense(
        merchant="Zain",
        total_amount=287.0,
        currency="SAR",
        category_code="OPEX-UTILITIES",
        sub_category="fiber_internet",
        paid_by="me",
        beneficiary="both",
        items=[{"name": "فاتورة انترنت", "price": 287.0, "quantity": 1, "sub_category": "fiber_internet"}],
        notes="Internet"
    )
    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda msg, household_id=None: mock_parsed)

    res = process_chat_transaction(
        household_id="test-household-001",
        message="zain internet & sim 287 sar",
        preview_only=False,
        allow_duplicate=True,
        override_merchant="Zain",
        override_category_code="OPEX-UTILITIES",
        override_sub_category="sub-zain-internet-sim",
        override_paid_by="me",
        override_beneficiary="both",
    )

    assert res["status"] == "success"
    assert res["sub_category"] == "sub-zain-internet-sim"
    assert res["items"][0]["sub_category"] == "sub-zain-internet-sim"

    kwargs = mock_insert.call_args.kwargs
    assert kwargs["sub_category"] == "sub-zain-internet-sim"
    assert kwargs["items"][0]["sub_category"] == "sub-zain-internet-sim"


