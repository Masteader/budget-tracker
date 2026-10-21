"""
FABLE-LOGIC-07 (docs/review/audit/fable_review.md): the heuristic chat parser (used when the LLM is
unavailable) misread common Saudi phrasing; 7 of the reviewer's 15 phrases got the wrong Nafaqah
class. The table below is the reviewer's, verbatim: (recorder role, text, expected class).

Expected None means no automatic class: the husband paid, or (a gift for someone outside the
household) the parser cannot tell and the preview asks the user (``paid_by`` 'unknown',
``attribution_needs_confirmation``). Pronoun suffixes (لها، له، لي...) are never child names.
"""
from __future__ import annotations

import pytest

from chat_parser import _fallback_heuristic_parse
from nafaqah_service import classify_nafaqah

PHRASES = [
    ("wife", "دفعت مقاضي البيت من بنده بـ 300 ريال", "wife_reimbursable"),
    ("wife", "شريت عباية لنفسي بـ 400 من نون", "wife_personal"),
    ("wife", "حاسب زوجي العشاء في البيك بـ 90", None),
    ("wife", "paid by my husband 200 for groceries", None),
    ("wife", "my husband paid 200 for groceries", None),
    ("wife", "شريت هدية لأمي بـ 150", None),
    ("wife", "دفعت فاتورة الكهرباء 450 ريال", "wife_reimbursable"),
    ("wife", "I paid 120 for the kids' school books", "wife_reimbursable"),
    ("wife", "bought milk and bread 35 SAR", "wife_reimbursable"),
    ("husband", "شريت فستان زوجتي بـ 300 ريال", None),
    ("husband", "زوجتي دفعت المقاضي 250 ريال", "wife_reimbursable"),
    ("husband", "my wife paid 250 for groceries", "wife_reimbursable"),
    ("husband", "wife paid 80 for her perfume", "wife_personal"),
    ("husband", "دفعتها زوجتي عطر لها بـ 80", "wife_personal"),
    ("husband", "دفعت 60 بنزين", None),
]


@pytest.mark.parametrize("role,text,expected", PHRASES)
def test_reviewer_phrase_table(role, text, expected):
    parsed = _fallback_heuristic_parse(text)
    assert classify_nafaqah(role, parsed.paid_by, parsed.beneficiary) == expected, (
        parsed.paid_by, parsed.beneficiary)
    assert parsed.total_amount > 0


@pytest.mark.parametrize("text", ["دفعتها زوجتي عطر لها بـ 80", "شريت له ساعة بـ 500", "اشتريت لي قهوة 15"])
def test_pronoun_suffixes_are_not_child_names(text):
    parsed = _fallback_heuristic_parse(text)
    assert parsed.beneficiary not in ("ها", "ه", "ي", "هم", "نا", "ك")


def test_named_child_is_still_detected():
    assert _fallback_heuristic_parse("شريت حليب لسارة بـ 20").beneficiary == "سارة"


@pytest.mark.parametrize("text,ask", [
    ("شريت هدية لأمي بـ 150", True),       # gift outside the household: undetermined
    ("عشاء 90", True),                      # no cue about payer or beneficiary
    ("دفعت مقاضي البيت 300", False),        # explicit payer and beneficiary
    ("my wife paid 250 for groceries", False),
])
def test_undetermined_attribution_asks(text, ask):
    assert _fallback_heuristic_parse(text).attribution_needs_confirmation is ask


def test_preview_asks_and_suggests_no_class_for_an_undetermined_family_expense(fake_supabase):
    """The chat preview returns the flag and no Nafaqah suggestion when the parser cannot tell."""
    from fable_world import World
    from chat_parser import process_chat_transaction

    w = World(fake_supabase, {"husband": ("admin", "provider"), "wife": ("member", "spouse")})
    res = process_chat_transaction(household_id=w.hid, message="شريت هدية لأمي بـ 150",
                                   user_id=w.users["wife"], preview_only=True)
    assert res["status"] == "pending_confirmation"
    assert res["attribution_needs_confirmation"] is True
    assert res["nafaqah_class"] is None
