import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import patch, MagicMock
from dedup_engine import find_duplicate_candidate, enrich_transaction_items, compute_zatca_fingerprint

def test_compute_zatca_fingerprint():
    fp1 = compute_zatca_fingerprint("300012345600003", "2026-10-04T12:00:00Z", 150.0)
    fp2 = compute_zatca_fingerprint("300012345600003", "2026-10-04T12:00:00Z", 150.00)
    fp_diff = compute_zatca_fingerprint("300012345600003", "2026-10-04T12:00:01Z", 150.0)
    assert fp1 == fp2
    assert fp1 != fp_diff
    assert len(fp1) == 64  # SHA-256 hex string

@patch("dedup_engine.get_client")
def test_find_duplicate_candidate_by_zatca_fingerprint(mock_get_client):
    mock_client = MagicMock()
    mock_select = MagicMock()
    mock_eq_hh = MagicMock()
    mock_eq_fp = MagicMock()
    mock_limit = MagicMock()

    mock_client.table.return_value.select.return_value = mock_select
    mock_select.eq.return_value = mock_eq_hh
    mock_eq_hh.eq.return_value = mock_eq_fp
    mock_eq_fp.limit.return_value = mock_limit
    mock_limit.execute.return_value = MagicMock(data=[
        {
            "id": "tx-zatca-999",
            "household_id": "hh-abc",
            "amount": 7408.0,
            "merchant": "United Electronics Co. eXtra",
            "timestamp": "2026-10-04T22:19:34Z",
            "dedup_fingerprint": "fake-zatca-hash-123",
        }
    ])
    mock_get_client.return_value = mock_client

    candidate = find_duplicate_candidate(
        household_id="hh-abc",
        amount=7408.0,
        merchant="eXtra",
        zatca_fingerprint="fake-zatca-hash-123",
    )
    assert candidate is not None
    assert candidate["id"] == "tx-zatca-999"
    assert candidate["amount"] == 7408.0

@patch("dedup_engine.get_client")
def test_find_duplicate_candidate_found(mock_get_client):
    mock_client = MagicMock()
    mock_select = MagicMock()
    mock_eq = MagicMock()
    mock_order = MagicMock()
    mock_limit = MagicMock()

    mock_client.table.return_value.select.return_value = mock_select
    mock_select.eq.return_value = mock_eq
    mock_eq.order.return_value = mock_order
    mock_order.limit.return_value = mock_limit
    mock_limit.execute.return_value = MagicMock(data=[
        {
            "id": "tx-1234",
            "household_id": "hh-abc",
            "amount": 19.0,
            "merchant": "Dunkin Donuts",
            "timestamp": "2026-10-05T01:00:00Z",
            "created_at": "2026-10-05T01:00:00Z",
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

