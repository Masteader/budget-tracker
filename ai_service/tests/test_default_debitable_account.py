"""
Tests for resolve_default_debitable_account (CRITICAL-04).
"""
import pytest
from supabase_client import resolve_default_debitable_account

HH = "f860188e-23b5-4749-b180-868c956151a6"
HUSBAND = "00000000-0000-4000-8000-00000000000a"
WIFE = "00000000-0000-4000-8000-00000000000b"
MEMBER = "00000000-0000-4000-8000-00000000000c"
ACC_SHARED = "a1111111-2222-3333-4444-555555555555"
ACC_WIFE = "a2222222-2222-3333-4444-555555555555"
ACC_OTHER = "a3333333-2222-3333-4444-555555555555"


def setup_base_tables(fake_supabase):
    fake_supabase.tables["households"] = [
        {"id": HH, "name": "Family HH", "payday_day": 27, "household_type": "family", "owner_user_id": HUSBAND}
    ]
    fake_supabase.tables["household_memberships"] = [
        {"household_id": HH, "user_id": HUSBAND, "role": "admin", "financial_role": "provider"},
        {"household_id": HH, "user_id": WIFE, "role": "member", "financial_role": "spouse"},
        {"household_id": HH, "user_id": MEMBER, "role": "member", "financial_role": "member"},
    ]


def test_wife_personal_returns_none(fake_supabase):
    setup_base_tables(fake_supabase)
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-SHOPPING", "wife_personal")
    assert res is None


def test_wife_reimbursable_returns_none(fake_supabase):
    setup_base_tables(fake_supabase)
    res = resolve_default_debitable_account(HH, WIFE, "OPEX-GROCERY", "wife_reimbursable")
    assert res is None


def test_missing_user_or_household_returns_none(fake_supabase):
    setup_base_tables(fake_supabase)
    assert resolve_default_debitable_account(HH, None, "OPEX-GROCERY", None) is None
    assert resolve_default_debitable_account(HH, "", "OPEX-GROCERY", None) is None
    assert resolve_default_debitable_account("", HUSBAND, "OPEX-GROCERY", None) is None


def test_spouse_actor_with_shared_or_husband_account_returns_none(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"}
    ]
    # WIFE (financial_role == 'spouse') cannot debit shared pool or husband's account
    res = resolve_default_debitable_account(HH, WIFE, "OPEX-GROCERY", None)
    assert res is None


def test_spouse_actor_with_own_account_resolves_own_account(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"},
        {"id": ACC_WIFE, "household_id": HH, "owner_user_id": WIFE, "is_shared_pool": False, "is_archived": False, "account_type": "checking"},
    ]
    res = resolve_default_debitable_account(HH, WIFE, "OPEX-GROCERY", None)
    assert res == ACC_WIFE


def test_budget_candidate_resolves_when_actor_authorized(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"}
    ]
    fake_supabase.tables["budgets"] = [
        {"household_id": HH, "category_code": "OPEX-GROCERY", "account_id": ACC_SHARED, "is_active": True}
    ]
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-GROCERY", None)
    assert res == ACC_SHARED


def test_budget_candidate_returns_none_if_forbidden_without_fallback(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"}
    ]
    fake_supabase.tables["budgets"] = [
        {"household_id": HH, "category_code": "OPEX-GROCERY", "account_id": ACC_SHARED, "is_active": True}
    ]
    # MEMBER is non-admin, so cannot debit ACC_SHARED. Must return None and NOT fall through!
    res = resolve_default_debitable_account(HH, MEMBER, "OPEX-GROCERY", None)
    assert res is None


def test_no_budget_link_single_eligible_account_resolves(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"}
    ]
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-DINING", None)
    assert res == ACC_SHARED


def test_no_budget_link_multiple_eligible_accounts_returns_none(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"},
        {"id": ACC_OTHER, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": False, "is_archived": False, "account_type": "checking"},
    ]
    # Multiple candidate accounts for HUSBAND: never guess, return None!
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-DINING", None)
    assert res is None


def test_archived_accounts_never_candidates(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_SHARED, "household_id": HH, "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": True, "account_type": "checking"}
    ]
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-DINING", None)
    assert res is None


def test_different_household_account_never_candidate(fake_supabase):
    setup_base_tables(fake_supabase)
    fake_supabase.tables["accounts"] = [
        {"id": ACC_OTHER, "household_id": "other-hh-uuid", "owner_user_id": HUSBAND, "is_shared_pool": True, "is_archived": False, "account_type": "checking"}
    ]
    res = resolve_default_debitable_account(HH, HUSBAND, "OPEX-DINING", None)
    assert res is None
