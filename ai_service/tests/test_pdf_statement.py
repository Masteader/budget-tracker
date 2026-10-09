"""
Unit tests for Monthly PDF Financial Statement generator.
"""
from unittest.mock import patch, MagicMock
from pdf_statement_generator import generate_monthly_pdf_statement


@patch("pdf_statement_generator.get_client")
@patch("pdf_statement_generator.get_salary_cycle_dates")
def test_generate_monthly_pdf_statement_success(mock_cycle, mock_supabase):
    mock_cycle.return_value = {
        "cycle_key": "2026-09",
        "cycle_label": "September 2026",
        "cycle_start": "2026-08-27",
        "cycle_end": "2026-09-26",
    }

    mock_client = MagicMock()
    # Mock budgets response
    mock_b_resp = MagicMock()
    mock_b_resp.data = [
        {"category_code": "OPEX-GROCERY", "allocated_amount": 2500.0, "spent_amount": 1200.0, "cycle_key": "2026-09"},
        {"category_code": "OPEX-DINING", "allocated_amount": 1000.0, "spent_amount": 400.0, "cycle_key": "2026-09"},
        {"category_code": "OPEX-FUEL", "allocated_amount": 500.0, "spent_amount": 200.0, "cycle_key": "2026-09"},
    ]
    # Mock transactions response
    mock_t_resp = MagicMock()
    mock_t_resp.data = [
        {"id": "t1", "amount": 120.0, "merchant": "Panda", "category_code": "OPEX-GROCERY", "timestamp": "2026-09-01T12:00:00Z", "spent_by": "both"},
        {"id": "t2", "amount": 65.0, "merchant": "Albaik", "category_code": "OPEX-DINING", "timestamp": "2026-09-02T14:30:00Z", "spent_by": "me"},
        {"id": "t3", "amount": 50.0, "merchant": "SASCO", "category_code": "OPEX-FUEL", "timestamp": "2026-09-03T09:15:00Z", "spent_by": "partner"},
    ]

    def mock_table(table_name):
        chain = MagicMock()
        chain.select.return_value = chain
        chain.eq.return_value = chain
        chain.gte.return_value = chain
        chain.lte.return_value = chain
        chain.order.return_value = chain
        if table_name == "budgets":
            chain.execute.return_value = mock_b_resp
        else:
            chain.execute.return_value = mock_t_resp
        return chain

    mock_client.table.side_effect = mock_table
    mock_supabase.return_value = mock_client

    pdf_bytes = generate_monthly_pdf_statement("test-household-123", cycle_key="2026-09")
    assert isinstance(pdf_bytes, bytes)
    assert len(pdf_bytes) > 500
    assert pdf_bytes.startswith(b"%PDF")
