import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from unittest.mock import MagicMock, patch
from settlement_engine import calculate_partner_settlement

def test_dependent_beneficiary_treated_as_shared_family_expense(monkeypatch):
    mock_client = MagicMock()
    mock_txs = [
        {
            "id": "tx-child-1",
            "amount": 200.0,
            "category_code": "OPEX-SHOPPING",
            "paid_by": "me",
            "beneficiary": "sarah",  # Child expense
            "spent_by": "both",
            "timestamp": "2026-10-10T12:00:00Z",
            "raw_sms": "Clothes for Sarah"
        }
    ]
    mock_client.table.return_value.select.return_value.eq.return_value.gte.return_value.order.return_value.execute.return_value.data = mock_txs
    monkeypatch.setattr("settlement_engine.get_client", lambda: mock_client)

    with patch("settlement_engine.load_family_context") as mock_ctx:
        from nafaqah_service import FamilyContext
        mock_ctx.return_value = FamilyContext(household_id="test-household-001", household_type="roommates")
        res = calculate_partner_settlement("test-household-001", split_ratio=0.50)
    # 200 SAR paid by me for child -> shared expense, partner owes 50% = 100 SAR
    assert res["shared_paid_by_me"] == 200.0
    assert res["net_balance"] == 100.0
    assert "partner owes you" in res["recommendation_en"].lower()
