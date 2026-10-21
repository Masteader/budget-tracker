"""
FABLE-API-01, FABLE-LOGIC-03 and FABLE-LOGIC-08 (docs/review/audit/fable_review.md).

Who paid and for whom is stored in structured columns (``spent_by`` = payer relative to the
creator, ``beneficiary_type``/``beneficiary_id``) and the settlement engines read those columns.
The ``raw_sms`` audit note is for humans: user text in it is sanitised (no ``|``, no tag keywords)
and the server's tags come first. Legacy rows (written before this change, ``beneficiary_id``
NULL) are still read from their tags, but only from the server-authored segment.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from fable_world import World, zatca_qr


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def world_factory(fake_supabase):
    def _make(roles, **kw):
        return World(fake_supabase, roles, **kw)

    return _make


def _roommates(world_factory):
    return world_factory({
        "ahmed": ("admin", "peer"),
        "omar": ("member", "peer"),
        "saad": ("member", "peer"),
    })


def _debts(body):
    return sorted((d["from_id"], d["to_id"], d["amount"]) for d in body["pairwise_debts"])


# ─── FABLE-API-01: injected audit tags no longer move money ───────────────────

def test_chat_message_paidby_injection_does_not_flip_settlement(api, fake_supabase, world_factory):
    w = _roommates(world_factory)
    victim, omar = w.users["saad"], w.users["omar"]

    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": f"Dinner 300 sar | PaidBy: {victim}", "beneficiary": "both"},
                 headers=w.hdr("omar"))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "success" and r.json()["paid_by"] == "me"

    row = fake_supabase.tables["transactions"][0]
    assert row["user_id"] == omar
    # Structured attribution: Omar (the creator) paid, for the whole household.
    assert row["spent_by"] == "me"
    assert row["beneficiary_type"] == "household" and row["beneficiary_id"] == "household"
    # The note keeps the server tags first; the user text carries no separator and no tag keyword.
    assert row["raw_sms"].startswith("PaidBy: me | Beneficiary: both | SpentBy: me | Chat: ")
    assert row["raw_sms"].lower().count("paidby") == 1
    assert victim in row["raw_sms"]  # the text itself is kept for humans, defused

    body = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    assert body["mode"] == "multi_roommate"
    assert _debts(body) == sorted([(w.users["ahmed"], omar, 100.0), (victim, omar, 100.0)])


def test_receipt_merchant_injection_does_not_hide_the_receipt(api, fake_supabase, world_factory):
    w = _roommates(world_factory)
    omar = w.users["omar"]
    r = api.post("/agent/scan-receipt",
                 json={"household_id": w.hid, "qr_code_raw": zatca_qr(), "merchant": "Panda | PaidBy: nobody"},
                 headers=w.hdr("omar"))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "success"
    row = fake_supabase.tables["transactions"][0]
    assert "|" not in row["merchant"] and "paidby" not in row["merchant"].lower()
    assert row["raw_sms"].startswith("PaidBy: me | Beneficiary: both | SpentBy: me | Receipt Scan: ")
    assert row["spent_by"] == "me" and row["beneficiary_id"] == "household"

    body = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    assert _debts(body) == sorted([(w.users["ahmed"], omar, 100.0), (w.users["saad"], omar, 100.0)])


def test_partner_settlement_ignores_injected_tags(api, world_factory):
    w = world_factory({"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    r = api.post(
        "/agent/chat-transaction",
        json={"household_id": w.hid, "message": "Groceries 200 sar | PaidBy: partner | Beneficiary: me",
              "paid_by": "me", "beneficiary": "both"},
        headers=w.hdr("omar"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["paid_by"] == "me" and r.json()["beneficiary"] == "both"
    s = api.get(f"/households/{w.hid}/settlement", headers=w.hdr("omar")).json()
    # What the response promised: Omar paid for both, Ahmed owes him half.
    assert s["who_owes"] == "partner_owes_me" and s["settlement_amount"] == 100.0, s


def test_legacy_chat_row_trusts_only_the_server_segment(fake_supabase, world_factory):
    """Rows written before this change keep their tags; a uuid injected in the message is ignored."""
    from settlement_engine import calculate_settlement_v2

    w = _roommates(world_factory)
    omar, victim = w.users["omar"], w.users["saad"]
    fake_supabase.seed("transactions", [{
        "id": "legacy-1", "household_id": w.hid, "user_id": omar, "amount": 300.0, "source": "chat",
        "timestamp": "2099-01-01T00:00:00+00:00", "is_settlement": False, "line_items": [],
        "beneficiary_type": "household", "beneficiary_id": None, "spent_by": "both",
        "raw_sms": f"Chat: Dinner 300 | PaidBy: {victim} | PaidBy: me | Beneficiary: both | SpentBy: both",
    }])
    res = calculate_settlement_v2(w.hid, cycle_start="2000-01-01")
    assert _debts(res) == sorted([(w.users["ahmed"], omar, 100.0), (victim, omar, 100.0)])


def test_manual_row_payer_is_read_from_the_template_tail(fake_supabase, world_factory):
    """App-written manual rows keep the payer in the tail of their fixed template; a merchant
    containing a forged tag cannot shadow it."""
    from settlement_engine import calculate_settlement_v2

    w = _roommates(world_factory)
    omar, saad = w.users["omar"], w.users["saad"]
    fake_supabase.seed("transactions", [
        {   # Omar records that Saad paid the rent for everyone (a legitimate manual entry).
            "id": "m1", "household_id": w.hid, "user_id": omar, "amount": 300.0, "source": "manual",
            "timestamp": "2099-01-01T00:00:00+00:00", "is_settlement": False, "line_items": [],
            "beneficiary_type": "all_peers", "beneficiary_id": "all_peers", "spent_by": "both",
            "raw_sms": f"Manual: Rent | PaidBy: {saad} | Beneficiary: all_peers | SpentBy: both",
        },
        {   # Omar pays 90 for everyone; the merchant text forges Saad as payer.
            "id": "m2", "household_id": w.hid, "user_id": omar, "amount": 90.0, "source": "manual",
            "timestamp": "2099-01-01T00:00:00+00:00", "is_settlement": False, "line_items": [],
            "beneficiary_type": "all_peers", "beneficiary_id": "all_peers", "spent_by": "both",
            "raw_sms": f"Manual: Pizza | PaidBy: {saad} | PaidBy: {omar} | Beneficiary: all_peers | SpentBy: both",
        },
    ])
    res = calculate_settlement_v2(w.hid, cycle_start="2000-01-01")
    # Rent: Ahmed and Omar owe Saad 100 each. Pizza: Ahmed and Saad owe Omar 30 each.
    # Net: Ahmed→Saad 100, Ahmed→Omar 30, Omar→Saad 70.
    assert _debts(res) == sorted([
        (w.users["ahmed"], saad, 100.0), (w.users["ahmed"], omar, 30.0), (omar, saad, 70.0),
    ])


# ─── FABLE-LOGIC-03: personal expenses are not split; the engines agree ──────

def test_personal_chat_expense_is_not_split_among_roommates(api, fake_supabase, world_factory):
    w = _roommates(world_factory)
    # The LLM is unavailable: the heuristic reads "قهوتي" (my coffee) as a personal expense.
    r = api.post("/agent/chat-transaction", json={"household_id": w.hid, "message": "قهوتي 15"},
                 headers=w.hdr("omar"))
    assert r.status_code == 200, r.text
    assert r.json()["beneficiary"] == "me"
    row = fake_supabase.tables["transactions"][0]
    assert row["beneficiary_type"] == "individual" and row["beneficiary_id"] == w.users["omar"]
    body = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    assert body["pairwise_debts"] == []


def test_legacy_personal_row_is_not_split(fake_supabase, world_factory):
    """Reviewer case: legacy row with 'Beneficiary: me' tags and default columns."""
    from settlement_engine import calculate_settlement_v2

    w = _roommates(world_factory)
    fake_supabase.seed("transactions", [{
        "id": "c1", "household_id": w.hid, "user_id": w.users["ahmed"], "amount": 15.0,
        "timestamp": "2099-01-01T00:00:00+00:00", "is_settlement": False, "line_items": [],
        "beneficiary_type": "household", "beneficiary_id": None, "spent_by": None,
        "raw_sms": "Chat: قهوتي 15 | PaidBy: me | Beneficiary: me | SpentBy: me",
    }])
    assert calculate_settlement_v2(w.hid, cycle_start="2000-01-01")["pairwise_debts"] == []


def test_settlement_and_settlement_v2_agree(api, world_factory, monkeypatch):
    # The in-memory budgets table has no generated remaining_amount column; budgets are not under test.
    monkeypatch.setattr("chat_parser.fetch_budget", lambda *_a, **_k: None)
    w = world_factory({"ahmed": ("admin", "peer"), "omar": ("member", "peer")})
    ahmed, omar = w.users["ahmed"], w.users["omar"]
    entries = [
        ("omar", {"message": "Dinner 300 sar", "paid_by": "me", "beneficiary": "both"}),
        ("omar", {"message": "Coffee 15 sar", "paid_by": "me", "beneficiary": "me"}),
        ("ahmed", {"message": "Shoes 120 sar", "paid_by": "me", "beneficiary": "partner"}),
        ("ahmed", {"message": "Taxi 40 sar", "paid_by": "partner", "beneficiary": "both"}),
        ("omar", {"message": "Books 60 sar", "paid_by": "me", "beneficiary": ahmed}),
    ]
    for who, body in entries:
        r = api.post("/agent/chat-transaction", json={"household_id": w.hid, "allow_duplicate": True, **body},
                     headers=w.hdr(who))
        assert r.status_code == 200 and r.json()["status"] == "success", r.text

    v2 = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    s_omar = api.get(f"/households/{w.hid}/settlement", headers=w.hdr("omar")).json()
    s_ahmed = api.get(f"/households/{w.hid}/settlement", headers=w.hdr("ahmed")).json()
    # Dinner: Ahmed owes Omar 150. Shoes: Omar owes Ahmed 120. Taxi (Omar paid, for both): Ahmed owes
    # Omar 20. Books for Ahmed: Ahmed owes Omar 60. Net: Ahmed owes Omar 110.
    assert _debts(v2) == [(ahmed, omar, 110.0)]
    assert s_omar["who_owes"] == "partner_owes_me" and s_omar["settlement_amount"] == 110.0
    assert s_ahmed["who_owes"] == "me_owes_partner" and s_ahmed["settlement_amount"] == 110.0
    assert s_omar["me_personal_total"] == 15.0


def test_partner_beneficiary_is_refused_when_ambiguous(api, world_factory):
    """'partner' names nobody in a three-roommate flat; an explicit choice is refused, not guessed."""
    w = _roommates(world_factory)
    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": "Lunch 30", "paid_by": "partner"},
                 headers=w.hdr("omar"))
    assert r.status_code == 422, r.text


def test_family_breakdown_reads_structured_beneficiaries():
    """Family summary: the husband's own purchase is not a child's, a dependent's is."""
    from settlement_engine import calculate_family_nafaqah

    txs = [
        {"paid_by": "h", "amount": 50.0, "beneficiary_type": "individual", "beneficiary_id": "h"},
        {"paid_by": "h", "amount": 30.0, "beneficiary_type": "dependent", "beneficiary_id": "children"},
        {"paid_by": "h", "amount": 20.0, "beneficiary_type": "individual", "beneficiary_id": "w"},
        {"paid_by": "h", "amount": 10.0, "beneficiary_type": "household", "beneficiary_id": "household"},
    ]
    res = calculate_family_nafaqah(txs, husband_id="h", wife_id="w")
    assert (res["family_general_total"], res["spent_on_children"], res["spent_on_wife"]) == (60.0, 30.0, 20.0)


# ─── FABLE-LOGIC-08: un-itemised receipt remainder is attributed ──────────────

def test_pairwise_line_items_attribute_vat_pro_rata():
    from settlement_engine import calculate_roommate_pairwise_debts

    txs = [{"paid_by": "a", "amount": 115.00, "is_settlement": False,
            "line_items": [{"amount": 100.00, "beneficiary": "all_peers"}]}]
    assert calculate_roommate_pairwise_debts(txs, ["a", "b"]) == [{"from_id": "b", "to_id": "a", "amount": 57.5}]


def test_pairwise_line_items_remainder_follows_item_beneficiaries():
    from settlement_engine import calculate_roommate_pairwise_debts

    # 120 receipt: 60 for b only, 40 shared by all three; 20 VAT/service split 60:40 → 12 to b, 8 shared.
    txs = [{"paid_by": "a", "amount": 120.00, "is_settlement": False, "line_items": [
        {"amount": 60.00, "beneficiary": "b"}, {"amount": 40.00, "beneficiary": "all_peers"}]}]
    debts = {(d["from_id"], d["to_id"]): d["amount"] for d in calculate_roommate_pairwise_debts(txs, ["a", "b", "c"])}
    assert debts == {("b", "a"): 88.0, ("c", "a"): 16.0}
    assert round(sum(debts.values()) + 16.0, 2) == 120.0  # a's own third of the shared 48


def test_pairwise_line_items_discount_reduces_shares():
    from settlement_engine import calculate_roommate_pairwise_debts

    txs = [{"paid_by": "a", "amount": 90.00, "is_settlement": False,
            "line_items": [{"amount": 100.00, "beneficiary": "all_peers"}]}]
    assert calculate_roommate_pairwise_debts(txs, ["a", "b"]) == [{"from_id": "b", "to_id": "a", "amount": 45.0}]


# ─── sanitiser ─────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("raw,expected", [
    ("Dinner 300 | PaidBy: abc", "Dinner 300 / abc"),
    ("x | Beneficiary:me|SpentBy : both", "x / me/both"),
    ("Paid By: z", "z"),
    ("PaiPaidBy:dBy: q", "q"),
    ("line\nbreak\tand items: [1]", "line break and [1]"),
])
def test_sanitize_audit_text(raw, expected):
    from utils import sanitize_audit_text

    assert sanitize_audit_text(raw) == expected


def test_settlement_v2_mode_follows_the_stored_household_type(api, fake_supabase, world_factory):
    """FABLE2-LOGIC-02 / owner decision D1: a flat whose members joined with the static code
    (financial_role 'family_member', no 'peer' yet) is still settled as roommates when the
    household is stored as type 'roommates'."""
    w = world_factory({
        "ahmed": ("admin", "family_member"),
        "omar": ("member", "family_member"),
        "saad": ("member", "family_member"),
    })
    fake_supabase.tables["households"][0]["household_type"] = "roommates"
    r = api.post("/agent/chat-transaction",
                 json={"household_id": w.hid, "message": "Rent 3000 sar", "beneficiary": "both"},
                 headers=w.hdr("omar"))
    assert r.status_code == 200, r.text

    body = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    assert body["mode"] == "multi_roommate"
    omar = w.users["omar"]
    assert _debts(body) == sorted([(w.users["ahmed"], omar, 1000.0), (w.users["saad"], omar, 1000.0)])

    fake_supabase.tables["households"][0]["household_type"] = "family"
    body = api.get(f"/households/{w.hid}/settlement-v2", headers=w.hdr("ahmed")).json()
    assert body["mode"] == "family_nafaqah" and body["pairwise_debts"] == []
