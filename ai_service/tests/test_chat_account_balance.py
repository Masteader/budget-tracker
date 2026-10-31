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



def test_insert_transaction_wife_personal_isolates_account_balance(fake_supabase):
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
        amount=150.00,
        currency="SAR",
        merchant="Sephora",
        category_code="OPEX-PERSONAL",
        timestamp="2026-10-30T00:00:00Z",
        raw_sms="Manual: Sephora",
        account_id=account_id,
        nafaqah_class="wife_personal",
    )

    # 1. Transaction row must NOT link to operating pool account for wife_personal
    tx_row = next(t for t in fake_supabase.tables["transactions"] if t["id"] == tx_id)
    assert tx_row.get("account_id") is None

    # 2. Account balance must remain unchanged: 7076.00
    acc_row = next(a for a in fake_supabase.tables["accounts"] if a["id"] == account_id)
    assert round(float(acc_row["balance"]), 2) == 7076.00


def test_insert_transaction_wife_reimbursable_does_not_deduct_account_balance(fake_supabase):
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
        amount=150.00,
        currency="SAR",
        merchant="Panda Supermarket",
        category_code="OPEX-GROCERY",
        timestamp="2026-10-30T00:00:00Z",
        raw_sms="Manual: Panda Supermarket",
        account_id=account_id,
        nafaqah_class="wife_reimbursable",
        nafaqah_spouse_id="u2222222-3333-4444-5555-666666666666",
    )

    # 1. Transaction row must NOT link to husband's operating pool account for wife_reimbursable
    tx_row = next(t for t in fake_supabase.tables["transactions"] if t["id"] == tx_id)
    assert tx_row.get("account_id") is None

    # 2. Account balance must remain unchanged: 7076.00
    acc_row = next(a for a in fake_supabase.tables["accounts"] if a["id"] == account_id)
    assert round(float(acc_row["balance"]), 2) == 7076.00


def test_resolve_expense_nafaqah_preserves_default_spouse_id_for_husband_me(fake_supabase):
    from nafaqah_service import resolve_expense_nafaqah

    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    husband_id = "u1111111-2222-3333-4444-555555555555"
    wife_id = "u2222222-3333-4444-5555-666666666666"

    fake_supabase.tables["households"] = [{"id": household_id, "household_type": "family", "payday_day": 27, "owner_user_id": husband_id, "nafaqah_provider_user_id": husband_id}]
    fake_supabase.tables["household_memberships"] = [
        {"household_id": household_id, "user_id": husband_id, "role": "admin", "financial_role": "provider"},
        {"household_id": household_id, "user_id": wife_id, "role": "member", "financial_role": "spouse"},
    ]
    fake_supabase.tables["users"] = [
        {"id": husband_id, "email": "husband@example.com", "raw_user_meta_data": {"full_name": "Abu Fahad"}},
        {"id": wife_id, "email": "wife@example.com", "raw_user_meta_data": {"full_name": "Um Fahad"}},
    ]

    res = resolve_expense_nafaqah(household_id, husband_id, "me", "both")
    assert res["household_mode"] == "family_nafaqah"
    assert res["nafaqah_class"] is None
    assert res["default_spouse_id"] == wife_id
    assert len(res["wives"]) == 1
    assert res["wives"][0]["id"] == wife_id


@patch("receipt_scanner.reallocate_budget")
@patch("receipt_scanner.fetch_budget")
@patch("receipt_scanner.parse_receipt_images")
def test_receipt_scanner_wife_personal_skips_budget_reallocation(mock_vision, mock_fetch_budget, mock_reallocate, fake_supabase):
    from receipt_scanner import process_receipt_scan

    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    husband_id = "u1111111-2222-3333-4444-555555555555"
    wife_id = "u2222222-3333-4444-5555-666666666666"

    fake_supabase.tables["households"] = [{"id": household_id, "household_type": "family", "payday_day": 27, "owner_user_id": husband_id, "nafaqah_provider_user_id": husband_id}]
    fake_supabase.tables["household_memberships"] = [
        {"household_id": household_id, "user_id": husband_id, "role": "admin", "financial_role": "provider"},
        {"household_id": household_id, "user_id": wife_id, "role": "member", "financial_role": "spouse"},
    ]
    fake_supabase.tables["users"] = [
        {"id": husband_id, "email": "husband@example.com", "raw_user_meta_data": {"full_name": "Abu Fahad"}},
        {"id": wife_id, "email": "wife@example.com", "raw_user_meta_data": {"full_name": "Um Fahad"}},
    ]

    mock_vision.return_value = {
        "merchant": "Sephora",
        "total_amount": 350.0,
        "vat_amount": 45.65,
        "category_code": "OPEX-PERSONAL",
        "items": [{"name": "Makeup", "quantity": 1.0, "price": 350.0}],
    }

    res = process_receipt_scan(
        household_id=household_id,
        images_base64=["iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="],
        user_id=husband_id,
        paid_by="partner",
        beneficiary="partner",
        override_nafaqah_class="wife_personal",
        override_nafaqah_spouse_id=wife_id,
        preview_only=False,
    )

    assert res["status"] == "success"
    # fetch_budget and reallocate_budget should NOT have been called for wife_personal
    mock_fetch_budget.assert_not_called()
    mock_reallocate.assert_not_called()


@patch("receipt_scanner.parse_receipt_images")
def test_process_receipt_scan_forwards_account_id(mock_vision, fake_supabase):
    from receipt_scanner import process_receipt_scan

    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    account_id = "a1111111-2222-3333-4444-555555555555"
    user_id = "u1111111-2222-3333-4444-555555555555"

    fake_supabase.tables["households"] = [{"id": household_id, "household_type": "family", "payday_day": 27, "owner_user_id": user_id}]
    fake_supabase.tables["household_memberships"] = [{"household_id": household_id, "user_id": user_id, "role": "admin", "financial_role": "provider"}]
    fake_supabase.tables["accounts"] = [
        {
            "id": account_id,
            "household_id": household_id,
            "name": "Rajhi Main account",
            "account_type": "checking",
            "is_shared_pool": True,
            "is_archived": False,
            "balance": 5000.00,
        }
    ]

    mock_vision.return_value = {
        "merchant": "Tamimi Markets",
        "total_amount": 250.0,
        "vat_amount": 32.61,
        "category_code": "OPEX-GROCERY",
        "items": [{"name": "Groceries", "quantity": 1.0, "price": 250.0}],
    }

    res = process_receipt_scan(
        household_id=household_id,
        images_base64=["iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="],
        user_id=user_id,
        preview_only=False,
        account_id=account_id,
    )

    assert res["status"] == "success"
    tx_row = next(t for t in fake_supabase.tables["transactions"] if t["id"] == res["transaction_id"])
    assert tx_row["account_id"] == account_id

    acc_row = next(a for a in fake_supabase.tables["accounts"] if a["id"] == account_id)
    assert round(float(acc_row["balance"]), 2) == 4750.00
