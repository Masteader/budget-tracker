"""
FABLE2-LOGIC-01 (backend tolerance): rows edited by old app builds.

Before the edit sheet wrote structured columns, its fallback write (flutter_app/lib/screens/home/
edit_transaction_sheet.dart at 84e264f, ``_saveChanges``) stored ``spent_by = derivedSpentBy``
('both' whenever the beneficiary was 'both') and appended
``" | PaidBy: <p> | Beneficiary: <b> | SubCategory: <s> | SpentBy: <derived>"`` to ``raw_sms``,
leaving ``beneficiary_type`` / ``beneficiary_id`` as they were. The settlement engines must not
read ``spent_by = 'both'`` as "the creator paid": the payer comes from the note's tags then. The
trust model is unchanged otherwise (manual rows take the payer from their tail, API rows only
accept 'me' / 'partner').
"""
from __future__ import annotations

import re

import pytest

from settlement_engine import transaction_attribution


def old_edit_sheet_note(raw: str, paid_by: str, beneficiary: str, sub_category: str | None) -> tuple[str, str]:
    """(raw_sms, spent_by) exactly as the old edit sheet's fallback wrote them."""
    if beneficiary == "both":
        derived = "both"
    elif paid_by == "partner" and beneficiary == "partner":
        derived = "partner"
    elif paid_by == "me" and beneficiary == "me":
        derived = "me"
    else:
        derived = beneficiary
    clean = re.sub(r"\|\s*SpentBy:\s*(me|partner|both)", "", raw, flags=re.I)
    clean = re.sub(r"\|\s*PaidBy:\s*(me|partner)", "", clean, flags=re.I)
    clean = re.sub(r"\|\s*Beneficiary:\s*([^\s\|]+)", "", clean, flags=re.I)
    clean = re.sub(r"\|\s*SubCategory:\s*([^\s\|]+)", "", clean, flags=re.I).strip()
    note = f"{clean} | PaidBy: {paid_by} | Beneficiary: {beneficiary} | SubCategory: {sub_category or ''} | SpentBy: {derived}"
    return note, derived


CHAT_RAW = "PaidBy: partner | Beneficiary: both | SpentBy: partner | Chat: Groceries 200 | Items: [1x Groceries (200 SAR)]"


def test_helper_reproduces_the_exact_old_sheet_strings():
    note, spent_by = old_edit_sheet_note(CHAT_RAW, "partner", "both", None)
    assert spent_by == "both"
    assert note == (
        "PaidBy: partner   | Chat: Groceries 200 | Items: [1x Groceries (200 SAR)]"
        " | PaidBy: partner | Beneficiary: both | SubCategory:  | SpentBy: both"
    )


@pytest.mark.parametrize("raw_sms, expected_payer", [
    # Chat row re-saved unchanged by the old sheet (the merchant was edited): the partner paid.
    ("PaidBy: partner  | Chat: Groceries 200 | Items: [1x Groceries (200 SAR)]"
     " | PaidBy: partner | Beneficiary: both | SubCategory:  | SpentBy: both", "partner"),
    # With a sub-category chosen in the sheet.
    ("PaidBy: me  | Chat: SEC bill | PaidBy: partner | Beneficiary: both | SubCategory: electricity_sec"
     " | SpentBy: both", "partner"),
    # An old row whose sheet tail says the creator paid.
    ("PaidBy: partner | Chat: x | PaidBy: me | Beneficiary: both | SubCategory:  | SpentBy: both", "me"),
])
def test_api_row_with_spent_by_both_reads_the_payer_from_the_tags(raw_sms, expected_payer):
    tx = {"source": "chat", "spent_by": "both", "raw_sms": raw_sms,
          "beneficiary_type": "household", "beneficiary_id": "household"}
    assert transaction_attribution(tx) == (expected_payer, "shared")


def test_api_row_with_spent_by_both_and_no_tail_uses_the_server_head_tag():
    tx = {"source": "receipt_scan", "spent_by": "both", "beneficiary_type": "household", "beneficiary_id": "household",
          "raw_sms": "PaidBy: partner | Beneficiary: both | SpentBy: partner | Receipt Scan: Panda"}
    assert transaction_attribution(tx) == ("partner", "shared")


def test_api_row_tags_never_name_an_arbitrary_member():
    member = "11111111-1111-4111-8111-111111111111"
    tx = {"source": "chat", "spent_by": "both", "beneficiary_type": "household", "beneficiary_id": "household",
          "raw_sms": f"PaidBy: me | Chat: x | PaidBy: {member} | Beneficiary: both | SubCategory:  | SpentBy: both"}
    assert transaction_attribution(tx)[0] == "me"


def test_structured_spent_by_still_wins_for_api_rows():
    # A row written by the API (or the fixed sheet) keeps its column: a stale tail is not read.
    tx = {"source": "chat", "spent_by": "me", "beneficiary_type": "household", "beneficiary_id": "household",
          "raw_sms": "PaidBy: me | Chat: x | PaidBy: partner | Beneficiary: both | SubCategory:  | SpentBy: both"}
    assert transaction_attribution(tx) == ("me", "shared")


def test_manual_row_edited_by_the_old_sheet_keeps_the_tail_payer():
    ahmed = "aaaaaaaa-0000-4000-8000-000000000001"
    raw = f"Manual: Groceries | PaidBy: {ahmed} | Beneficiary: all_peers | SpentBy: both"
    note, spent_by = old_edit_sheet_note(raw, "partner", "me", None)
    # The UUID PaidBy is not matched by the sheet's (me|partner) regex: it stays in the text.
    assert note == (f"Manual: Groceries | PaidBy: {ahmed} | PaidBy: partner | Beneficiary: me | SubCategory:  "
                    f"| SpentBy: me")
    assert spent_by == "me"
    tx = {"source": "manual", "spent_by": spent_by, "raw_sms": note,
          "beneficiary_type": "all_peers", "beneficiary_id": "all_peers"}
    assert transaction_attribution(tx)[0] == "partner"


def test_manual_tail_with_a_sub_category_value():
    tx = {"source": "manual", "spent_by": "both", "beneficiary_type": "household", "beneficiary_id": "household",
          "raw_sms": "Manual: SEC | PaidBy: partner | Beneficiary: both | SubCategory: electricity_sec | SpentBy: both"}
    assert transaction_attribution(tx) == ("partner", "shared")


def test_legacy_row_without_columns_reads_the_sheet_tail_after_the_items():
    # No beneficiary columns (pre-structured row) and the tail sits after " | Items: [...]".
    tx = {"source": "chat", "spent_by": "both", "beneficiary_id": None, "category_code": "OPEX-DINING",
          "raw_sms": "PaidBy: me | Chat: dinner | Items: [1x Dinner (90 SAR)]"
                     " | PaidBy: partner | Beneficiary: me | SubCategory:  | SpentBy: me"}
    assert transaction_attribution(tx) == ("partner", "me")


def test_settlement_v2_follows_the_old_sheet_edit(fake_supabase):
    """End to end through calculate_settlement_v2 with the fake: Omar's chat row says Ahmed paid."""
    import uuid

    from fable_world import World
    from settlement_engine import calculate_settlement_v2

    w = World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    raw = "PaidBy: partner | Beneficiary: both | SpentBy: partner | Chat: Groceries 200"
    note, spent_by = old_edit_sheet_note(raw, "partner", "both", None)
    from utils import riyadh_today
    fake_supabase.seed("transactions", [{
        "id": str(uuid.uuid4()), "household_id": w.hid, "user_id": w.users["omar"], "amount": 200.0,
        "merchant": "Groceries", "category_code": "OPEX-GROCERY", "spent_by": spent_by,
        "timestamp": f"{riyadh_today().isoformat()}T09:00:00+00:00", "raw_sms": note, "source": "chat",
        "beneficiary_type": "household", "beneficiary_id": "household", "is_settlement": False,
        "settlement_target_id": None, "nafaqah_class": None, "nafaqah_spouse_id": None, "line_items": [],
    }])
    result = calculate_settlement_v2(w.hid)
    debts = [(d["from_id"], d["to_id"], d["amount"]) for d in result["pairwise_debts"]]
    assert debts == [(w.users["omar"], w.users["ahmed"], 100.0)]
