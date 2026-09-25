"""
Unit tests for deduplication & cross-channel matching engine.
"""
from unittest.mock import patch, MagicMock
from dedup_engine import find_duplicate_candidate, enrich_transaction_items

@patch("dedup_engine.get_client")
def test_find_duplicate_candidate_found(mock_get_client):
    mock_client = MagicMock()
    mock_select = MagicMock()
    mock_eq = MagicMock()
    mock_gte = MagicMock()
    mock_order = MagicMock()
    mock_limit = MagicMock()
    mock_exec = MagicMock()

    mock_client.table.return_value.select.return_value = mock_select
    mock_select.eq.return_value = mock_eq
    mock_eq.gte.return_value = mock_gte
    mock_gte.order.return_value = mock_order
    mock_order.limit.return_value = mock_limit
    mock_limit.execute.return_value = MagicMock(data=[
        {
            "id": "tx-1234",
            "household_id": "hh-abc",
            "amount": 19.0,
            "merchant": "Dunkin Donuts",
            "timestamp": "2026-09-25T14:00:00Z",
        }
    ])
    mock_get_client.return_value = mock_client

    candidate = find_duplicate_candidate("hh-abc", 19.0, "Dunkin")
    assert candidate is not None
    assert candidate["id"] == "tx-1234"
    assert candidate["amount"] == 19.0

@patch("dedup_engine.get_client")
def test_enrich_transaction_items(mock_get_client):
    mock_client = MagicMock()
    mock_client.table.return_value.update.return_value.eq.return_value.execute.return_value = MagicMock()
    mock_get_client.return_value = mock_client

    items = [{"name": "Latte", "quantity": 1, "price": 16.0}]
    success = enrich_transaction_items("tx-1234", items)
    assert success is True
    mock_client.table.assert_called_with("transactions")
