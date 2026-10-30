"""
Tests verifying that chat transactions properly resolve account_id and deduct accounts.balance.
"""
from unittest.mock import patch, MagicMock
from fakes import FakeSupabaseClient
from chat_parser import process_chat_transaction
from supabase_client import insert_transaction


def test_insert_transaction_with_account_id_updates_balance(fake_supabase):
    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    account_id = "a1111111-2222-3333-4444-555555555555"

    fake_supabase.tables["accounts"] = [
        {
            "id": account_id,
            "household_id": household_id,
            "name": "Rajhi Main account",
            "account_type": "checking",
            "is_shared_pool": True,
            "is_archived": False,
            "balance": 7076.00,
        }
    ]

    tx_id = insert_transaction(
        household_id=household_id,
        amount=34.40,
        currency="SAR",
        merchant="Hunger Station AL-Baik Restaurant",
        category_code="OPEX-DINING",
        timestamp="2026-10-30T00:00:00Z",
        raw_sms="Manual: Hunger Station AL-Baik Restaurant",
        account_id=account_id,
    )

    # 1. Transaction row must contain account_id
    tx_row = next(t for t in fake_supabase.tables["transactions"] if t["id"] == tx_id)
    assert tx_row["account_id"] == account_id

    # 2. Account balance must be decremented: 7076.00 - 34.40 = 7041.60
    acc_row = next(a for a in fake_supabase.tables["accounts"] if a["id"] == account_id)
    assert round(float(acc_row["balance"]), 2) == 7041.60


def test_insert_transaction_resolves_default_operating_account_if_none_passed(fake_supabase):
    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    account_id = "a1111111-2222-3333-4444-555555555555"

    fake_supabase.tables["accounts"] = [
        {
            "id": account_id,
            "household_id": household_id,
            "name": "Rajhi Main account",
            "account_type": "checking",
            "is_shared_pool": True,
            "is_archived": False,
            "balance": 7076.00,
        }
    ]

    # No account_id passed
    tx_id = insert_transaction(
        household_id=household_id,
        amount=34.40,
        currency="SAR",
        merchant="Hunger Station AL-Baik Restaurant",
        category_code="OPEX-DINING",
        timestamp="2026-10-30T00:00:00Z",
        raw_sms="Manual: Hunger Station AL-Baik Restaurant",
    )

    # Transaction must have resolved to the operating pool account
    tx_row = next(t for t in fake_supabase.tables["transactions"] if t["id"] == tx_id)
    assert tx_row["account_id"] == account_id

    # Account balance must be deducted
    acc_row = next(a for a in fake_supabase.tables["accounts"] if a["id"] == account_id)
    assert round(float(acc_row["balance"]), 2) == 7041.60


@patch("chat_parser.litellm.completion")
def test_process_chat_transaction_deducts_account_balance(mock_completion, fake_supabase):
    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    account_id = "a1111111-2222-3333-4444-555555555555"

    fake_supabase.tables["accounts"] = [
        {
            "id": account_id,
            "household_id": household_id,
            "name": "Rajhi Main account",
            "account_type": "checking",
            "is_shared_pool": True,
            "is_archived": False,
            "balance": 7076.00,
        }
    ]

    mock_resp = MagicMock()
    mock_resp.choices = [
        MagicMock(
            message=MagicMock(
                content='''{
                    "is_transaction": true,
                    "merchant": "Hunger Station AL-Baik Restaurant",
                    "total_amount": 34.40,
                    "currency": "SAR",
                    "category_code": "OPEX-DINING",
                    "items": []
                }'''
            )
        )
    ]
    mock_completion.return_value = mock_resp

    res = process_chat_transaction(
        household_id=household_id,
        message="Hunger Station AL-Baik Restaurant 34.4 SAR",
        user_id="u1111111-2222-3333-4444-555555555555",
        preview_only=False,
    )

    assert res["status"] == "success"
    assert res["amount"] == 34.40
    assert len(fake_supabase.tables["transactions"]) == 1
    tx = fake_supabase.tables["transactions"][0]
    assert tx["account_id"] == account_id

    acc = fake_supabase.tables["accounts"][0]
    assert round(float(acc["balance"]), 2) == 7041.60

