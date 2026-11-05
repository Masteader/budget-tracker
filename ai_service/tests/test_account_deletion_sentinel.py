"""A purge writes the sentinel ``deleted_member`` where a departed member was named.

The settlement engine must treat it exactly like the id of someone no longer in the household, so
no household's result depends on which of the two is stored. Rows are in the shape
prepare_account_purge leaves them (supabase/tests/39_account_deletion_purge.sql).
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

import settlement_engine as se
from settlement_engine import calculate_partner_settlement, calculate_settlement_v2

SENTINEL = "deleted_member"
UNKNOWN = "ffffffff-0000-4000-8000-00000000dead"

HH = "e5000000-0000-4000-8000-000000000001"
ALI = "e5000000-0000-4000-8000-0000000000a1"
OMAR = "e5000000-0000-4000-8000-0000000000a2"
TARIQ = "e5000000-0000-4000-8000-0000000000a3"
NOW = datetime.now(timezone.utc).isoformat()


def _rows(ref: str) -> list:
    """What a household holds after a member left, with ``ref`` naming that member."""
    return [
        # The departed member's expense: creator NULL, note scrubbed to the tail.
        {"id": "t1", "household_id": HH, "user_id": None, "amount": 90.0, "category_code": "OPEX-GROCERY",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "household",
         "beneficiary_id": "household", "is_settlement": False,
         "notes": f"| PaidBy: {ref} | Beneficiary: both | SpentBy: me", "line_items": []},
        # Their expense with no structured beneficiary: read from the note's tags.
        {"id": "t2", "household_id": HH, "user_id": None, "amount": 40.0, "category_code": "OPEX-DINING",
         "timestamp": NOW, "source": "chat", "spent_by": "partner", "beneficiary_type": None,
         "beneficiary_id": None, "is_settlement": False,
         "notes": f"PaidBy: {ref} | Beneficiary: {ref} | SpentBy: partner", "line_items": []},
        # Ali's expense for the departed member.
        {"id": "t3", "household_id": HH, "user_id": ALI, "amount": 60.0, "category_code": "OPEX-DINING",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "member",
         "beneficiary_id": ref, "is_settlement": False,
         "notes": f"A note by Ali | PaidBy: me | Beneficiary: {ref} | SpentBy: me", "line_items": []},
        # Ali's expense with one line item for the departed member.
        {"id": "t4", "household_id": HH, "user_id": ALI, "amount": 30.0, "category_code": "OPEX-GROCERY",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "household",
         "beneficiary_id": "household", "is_settlement": False, "notes": None,
         "line_items": [{"name": "bread", "amount": 10.0, "beneficiary": ref},
                        {"name": "milk", "amount": 20.0, "beneficiary": OMAR}]},
        # A settlement the departed member paid to Ali.
        {"id": "t5", "household_id": HH, "user_id": None, "amount": 25.0, "category_code": "OPEX-MISC",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "member",
         "beneficiary_id": ALI, "is_settlement": True, "settlement_target_id": ALI,
         "notes": f"Settlement | PaidBy: {ref} | Recipient: {ALI} | Method: cash", "line_items": []},
        # A settlement Omar paid to the departed member.
        {"id": "t6", "household_id": HH, "user_id": OMAR, "amount": 15.0, "category_code": "OPEX-MISC",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "member",
         "beneficiary_id": ref, "is_settlement": True, "settlement_target_id": ref,
         "notes": f"Settlement | PaidBy: {OMAR} | Recipient: {ref} | Method: bank", "line_items": []},
    ]


def _seed(fake, members, household_type, ref, provider=None):
    fake.seed("households", [{"id": HH, "payday_day": 27, "owner_user_id": members[0][0],
                              "household_type": household_type, "nafaqah_provider_user_id": provider}])
    fake.seed("users", [{"id": uid, "household_id": HH, "role": "member", "financial_role": role, "display_name": uid[-2:]}
                        for uid, role in members])
    fake.seed("household_memberships", [
        {"user_id": uid, "household_id": HH, "financial_role": role, "role": "admin" if i == 0 else "member",
         "created_at": f"2026-01-0{i + 1}T00:00:00+00:00"}
        for i, (uid, role) in enumerate(members)])
    fake.seed("transactions", _rows(ref))


ROOMMATES_3 = [(ALI, "peer"), (OMAR, "peer"), (TARIQ, "peer")]
ROOMMATES_2 = [(ALI, "peer"), (OMAR, "peer")]
FAMILY = [(ALI, "provider"), (OMAR, "spouse"), (TARIQ, "family_member")]


def _both(fake_supabase, compute, members, household_type, provider=None) -> tuple:
    _seed(fake_supabase, members, household_type, SENTINEL, provider)
    with_sentinel = compute()
    fake_supabase.tables["transactions"] = []
    fake_supabase.seed("transactions", _rows(UNKNOWN))
    with_unknown = compute()
    return with_sentinel, with_unknown


@pytest.mark.parametrize(
    "members, household_type, provider",
    [(ROOMMATES_3, "roommates", None), (ROOMMATES_2, "roommates", None), (FAMILY, "family", ALI)],
)
def test_settlement_v2_is_the_same_as_for_an_unknown_uuid(fake_supabase, members, household_type, provider):
    a, b = _both(fake_supabase, lambda: calculate_settlement_v2(HH), members, household_type, provider)
    assert a == b


@pytest.mark.parametrize(
    "members, household_type, provider, caller",
    [
        (ROOMMATES_3, "roommates", None, ALI),
        (ROOMMATES_3, "roommates", None, OMAR),
        (ROOMMATES_2, "roommates", None, ALI),
        (ROOMMATES_2, "roommates", None, OMAR),
        (FAMILY, "family", ALI, ALI),
        (FAMILY, "family", ALI, OMAR),
    ],
)
def test_partner_settlement_is_the_same_as_for_an_unknown_uuid(fake_supabase, members, household_type, provider, caller):
    a, b = _both(
        fake_supabase,
        lambda: calculate_partner_settlement(HH, caller_user_id=caller),
        members, household_type, provider,
    )
    assert a == b


class _Ctx:
    members = [ALI, OMAR]
    is_family = False
    husband_id = None
    wives: list = []


@pytest.mark.parametrize(
    "resolve",
    [
        lambda r: se.resolve_member_ref(r, ALI, _Ctx),
        lambda r: se._caller_relative(r, ALI, ALI, _Ctx),
        lambda r: se._item_beneficiary({"beneficiary": r}, ALI, _Ctx),
        lambda r: se._item_beneficiary({"beneficiary_id": r}, ALI, _Ctx),
        lambda r: se._beneficiary_ref("member", r) == r,
        lambda r: se.resolve_member_ref(se.settlement_payer_ref({"notes": f"Settlement | PaidBy: {r} | Recipient: x |"}), ALI, _Ctx),
        lambda r: se.resolve_member_ref(
            se.transaction_attribution({"source": "manual", "beneficiary_id": "household",
                                        "notes": f"| PaidBy: {r} | Beneficiary: both | SpentBy: me"})[0], ALI, _Ctx),
    ],
)
def test_each_resolver_treats_them_alike(resolve):
    assert resolve(SENTINEL) == resolve(UNKNOWN)


def test_the_sentinel_never_names_a_member():
    assert se.resolve_member_ref(SENTINEL, ALI, _Ctx) is None
    assert se._caller_relative(SENTINEL, ALI, ALI, _Ctx) is None


def test_a_row_with_no_creator_is_never_credited_to_the_caller(fake_supabase):
    """A NULL creator with a creator-relative 'me' stays unattributed, whoever asks (plan 4.3)."""
    _seed(fake_supabase, ROOMMATES_2, "roommates", SENTINEL)
    fake_supabase.tables["transactions"] = []
    fake_supabase.seed("transactions", [
        {"id": "t9", "household_id": HH, "user_id": None, "amount": 500.0, "category_code": "OPEX-GROCERY",
         "timestamp": NOW, "source": "manual", "spent_by": "me", "beneficiary_type": "household",
         "beneficiary_id": "household", "is_settlement": False,
         "notes": "| PaidBy: me | Beneficiary: both | SpentBy: me", "line_items": []},
    ])
    for caller in (ALI, OMAR):
        res = calculate_partner_settlement(HH, caller_user_id=caller)
        assert res["owed_to_me"] == 0.0, res
        assert res["net_balance"] == 0.0, res
