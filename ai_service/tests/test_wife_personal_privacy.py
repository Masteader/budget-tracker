"""
Who reads a wife's personal purchases (owner decision 2026-11-06), at the API.

Her personal purchases (transactions with ``nafaqah_class`` 'wife_personal') are read only by the
wife herself (her own), her husband (the household's Nafaqah provider while he is a member who is
not a wife) and a household admin who is not a wife: the people who read her allowance. The API
reads transactions with the service role, which bypasses the database's read policy (test 64), so
every answer to a member built from transactions checks the caller itself. A co-wife (even an
admin) and an ordinary member get nothing of those rows and nothing derived from them: no
merchant, item, price or amount in the price history, the shopping basket, the monthly statement,
the recurring bills, the settlements' personal totals or a duplicate warning. Every other
transaction is still in every member's answers.

The matrix: callers (the wife, her husband, a co-wife, an ordinary member, an admin who is not a
wife, a wife who is an admin) x (husband present and an admin, present and not an admin, gone).
The transactions table is strict (only the selected columns come back, as from PostgREST), so an
answer that never read a row's class cannot pass by accident.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from reportlab import rl_config

import chat_parser
from receipt_scanner import decode_zatca_tlv
from dedup_engine import compute_zatca_fingerprint
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixture)
    CHILD,
    COADMIN,
    HH,
    HUSBAND,
    WIFE,
    bearer,
    client,
    family,
)

COWIFE = "b2000000-0000-4000-8000-00000000000e"
WIFE_ADMIN = "b2000000-0000-4000-8000-00000000000f"

CALLERS = {
    "wife": WIFE,
    "husband": HUSBAND,
    "co-wife": COWIFE,
    "member": CHILD,
    "admin": COADMIN,
    "wife-admin": WIFE_ADMIN,
}
WIVES = (WIFE, COWIFE, WIFE_ADMIN)

TX_COLUMNS = {
    "id", "household_id", "user_id", "amount", "currency", "merchant", "category_code", "timestamp", "notes",
    "is_reallocated", "reallocated_from_budget_id", "created_at", "source", "items", "receipt_url",
    "dedup_fingerprint", "spent_by", "sub_category", "cycle_key", "qr_code_raw", "beneficiary_type",
    "beneficiary_id", "is_settlement", "settlement_target_id", "line_items", "account_id", "nafaqah_class",
    "nafaqah_spouse_id",
}

NOW = datetime.now(timezone.utc)
RECENT = (NOW - timedelta(minutes=5)).isoformat()
MONTH_AGO = (NOW - timedelta(days=30)).isoformat()

# Each wife's personal purchases: (id, merchant, amount, item or None, when). Names and amounts
# are distinct, so a leak shows in a response's text.
PERSONAL = {
    WIFE: [("p-w1", "Boutique Wafa", 211.0, "Musk", RECENT),
           ("p-w2", "Gym Wafa", 151.0, None, MONTH_AGO),
           ("p-w3", "Gym Wafa", 151.0, None, RECENT)],
    COWIFE: [("p-c1", "Salon Huda", 313.0, "Henna", RECENT),
             ("p-c2", "Yoga Huda", 127.0, None, MONTH_AGO),
             ("p-c3", "Yoga Huda", 127.0, None, RECENT)],
    WIFE_ADMIN: [("p-a1", "Gold Mona", 419.0, "Oud", RECENT)],
}
# What the cycle (now) holds of each wife's personal purchases.
CYCLE_PERSONAL = {WIFE: 211.0 + 151.0, COWIFE: 313.0 + 127.0, WIFE_ADMIN: 419.0}


def _tx(tx_id, user, merchant, amount, when, *, cls=None, wife=None, item=None, category="OPEX-SHOPPING", **extra):
    row = {c: None for c in TX_COLUMNS}
    row.update({
        "id": tx_id, "household_id": HH, "user_id": user, "amount": amount, "currency": "SAR", "merchant": merchant,
        "category_code": category, "timestamp": when, "created_at": when, "source": "manual", "spent_by": "both",
        "beneficiary_type": "household", "is_settlement": False, "nafaqah_class": cls, "nafaqah_spouse_id": wife,
        "items": [{"name": item, "price": amount, "quantity": 1}] if item else None, "notes": f"note {merchant}",
    })
    row.update(extra)
    return row


@pytest.fixture(params=["present-admin", "present-member", "gone"])
def household(request, family):
    """The family of test_wife_repayment_debit with a co-wife and a wife who is an admin, ordinary
    household expenses, and personal purchases of each wife. 'present-member': the husband is not
    an admin. 'gone': he left the household (his membership ended, which clears the provider)."""
    family.tables["users"].extend([
        {"id": COWIFE, "household_id": HH, "role": "member", "financial_role": "spouse", "display_name": "Huda"},
        {"id": WIFE_ADMIN, "household_id": HH, "role": "admin", "financial_role": "spouse", "display_name": "Mona"},
    ])
    family.tables["household_memberships"].extend([
        {"user_id": COWIFE, "financial_role": "spouse", "household_id": HH, "role": "member",
         "created_at": "2026-01-05T00:00:00+00:00"},
        {"user_id": WIFE_ADMIN, "financial_role": "spouse", "household_id": HH, "role": "admin",
         "created_at": "2026-01-06T00:00:00+00:00"},
    ])
    # Her wife_reimbursable advance of the family fixture (300 at Panda), in this cycle.
    rows = [_tx(r["id"], r["nafaqah_spouse_id"], r["merchant"], r["amount"], RECENT, cls=r["nafaqah_class"],
                wife=r["nafaqah_spouse_id"], category="OPEX-GROCERY")
            for r in family.tables["transactions"]]
    rows += [
        _tx("o-1", HUSBAND, "Danube Market", 103.0, RECENT, item="Rice", category="OPEX-GROCERY"),
        _tx("o-2", CHILD, "STC Bill", 230.0, MONTH_AGO, category="OPEX-UTILITIES"),
        _tx("o-3", CHILD, "STC Bill", 230.0, RECENT, category="OPEX-UTILITIES"),
    ]
    for wife, purchases in PERSONAL.items():
        for tx_id, merchant, amount, item, when in purchases:
            rows.append(_tx(tx_id, wife, merchant, amount, when, cls="wife_personal", wife=wife, item=item,
                            spent_by="me", beneficiary_type="individual", beneficiary_id=wife))
    family.tables["transactions"][:] = rows
    family.schemas["transactions"] = set(TX_COLUMNS)
    if request.param == "present-member":
        for table in (family.tables["household_memberships"], family.tables["users"]):
            for m in table:
                if m.get("user_id", m.get("id")) == HUSBAND:
                    m["role"] = "member"
        for h in family.tables["households"]:
            if h["id"] == HH:
                h["owner_user_id"] = COADMIN
    if request.param == "gone":
        family.tables["household_memberships"][:] = [
            m for m in family.tables["household_memberships"] if m["user_id"] != HUSBAND]
        for h in family.tables["households"]:
            if h["id"] == HH:
                h["nafaqah_provider_user_id"] = None
                h["owner_user_id"] = COADMIN
    family.state = request.param
    return family


def _sees(state, who, wife):
    """Whether ``who`` reads ``wife``'s personal purchases: she herself; the husband while a
    member; an admin who is not a wife."""
    if CALLERS[who] == wife:
        return True
    if who == "husband":
        return state != "gone"
    return who == "admin"


def _seen_wives(state, who):
    return [w for w in WIVES if _sees(state, who, w)]


def _gone_husband(household, who, resp):
    """The husband who left is no longer a member: refused at the door."""
    if who == "husband" and household.state == "gone":
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])
        return True
    assert resp.status_code == 200, (resp.status_code, resp.text[:300])
    return False


def _assert_shows(text, household, who, *, labels):
    """``labels(wife)`` are the strings of her purchases an answer would carry: present exactly when
    the caller reads them. Ordinary expenses are in every member's answers."""
    for wife in WIVES:
        for label in labels(wife):
            if _sees(household.state, who, wife):
                assert label in text, (who, wife, label)
            else:
                assert label not in text, (who, wife, label)


def _merchants(wife):
    return sorted({p[1] for p in PERSONAL[wife]})


def _items(wife):
    return [p[3] for p in PERSONAL[wife] if p[3]] + [p[1] for p in PERSONAL[wife] if p[3]]


# ─── Price history and the shopping basket ────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_price_history_shows_her_items_only_to_who_reads_them(household, who):
    resp = client.get("/analytics/price-history", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    _assert_shows(resp.text, household, who, labels=_items)
    assert "Rice" in resp.text and "Danube Market" in resp.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_shopping_basket_prices_her_stores_only_for_who_reads_them(household, who):
    resp = client.post("/analytics/shopping-basket-optimize", headers=bearer(CALLERS[who]),
                       json={"household_id": HH, "items": ["Musk", "Henna", "Oud", "Rice"]})
    if _gone_husband(household, who, resp):
        return
    _assert_shows(resp.text, household, who, labels=lambda w: [p[1] for p in PERSONAL[w] if p[3]])
    assert "Danube Market" in resp.text


# ─── The monthly statement ────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_statement_lists_and_sums_her_purchases_only_for_who_reads_them(household, who, monkeypatch):
    monkeypatch.setattr(rl_config, "pageCompression", 0)
    resp = client.get("/reports/statement-pdf", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    text = resp.content.decode("latin-1")
    _assert_shows(text, household, who, labels=_merchants)
    assert "Danube Market" in text and "STC Bill" in text and "Panda" in text
    # The total spent: every row of the cycle the caller reads, and no other.
    total = 103.0 + 230.0 + 300.0 + sum(CYCLE_PERSONAL[w] for w in _seen_wives(household.state, who))
    assert f"{total:,.2f}" in text, (who, total)


# ─── Recurring bills ──────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_recurring_bills_carry_her_subscriptions_only_for_who_reads_them(household, who):
    resp = client.get("/budgets/recurring-bills", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    recurring = {WIFE: ["Gym Wafa"], COWIFE: ["Yoga Huda"], WIFE_ADMIN: []}
    _assert_shows(resp.text, household, who, labels=lambda w: recurring[w])
    assert "STC Bill" in resp.text


# ─── Salary cycles ────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_a_cycle_holding_only_her_purchase_is_listed_only_for_who_reads_it(household, who):
    household.tables["transactions"].append(
        _tx("p-c-old", COWIFE, "Old Salon Huda", 99.0, "2025-01-10T10:00:00+00:00", cls="wife_personal", wife=COWIFE,
            cycle_key="2025-01"))
    household.tables["transactions"].append(
        _tx("o-old", CHILD, "Old Bakery", 9.0, "2025-03-10T10:00:00+00:00", cycle_key="2025-03"))
    resp = client.get("/budgets/cycles", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    assert ("2025-01" in resp.text) is _sees(household.state, who, COWIFE), resp.text[:300]
    assert "2025-03" in resp.text


# ─── Settlements ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_settlement_personal_totals_hold_only_what_the_caller_reads(household, who):
    resp = client.get(f"/households/{HH}/settlement", headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    body = resp.json()
    expected = round(sum(CYCLE_PERSONAL[w] for w in _seen_wives(household.state, who)), 2)
    assert round(body["me_personal_total"] + body["partner_personal_total"], 2) == expected, body


@pytest.mark.parametrize("who", list(CALLERS))
def test_settlement_v2_spent_on_wife_holds_only_what_the_caller_reads(household, who):
    resp = client.get(f"/households/{HH}/settlement-v2", headers=bearer(CALLERS[who]))
    if _gone_husband(household, who, resp):
        return
    summary = resp.json()["family_summary"]
    expected = round(sum(CYCLE_PERSONAL[w] for w in _seen_wives(household.state, who)), 2)
    assert summary["spent_on_wife"] == expected, summary


# ─── Duplicate warnings ───────────────────────────────────────────────────────

QR = ("ARxVbml0ZWQgRWxlY3Ryb25pY3MgQ28uIGVYdHJhAg8zMDA0Njg3ODE5MTAwMDMDFDIwMjYtMTAtMDRUMjI6MTk6MzRaBAc3NDA4"
      "LjAwBQY5NjYuMjY=")


@pytest.mark.parametrize("who", list(CALLERS))
def test_a_receipt_scan_warns_of_her_purchase_only_to_who_reads_it(household, who):
    """The co-wife's personal purchase of the same receipt (its ZATCA fingerprint): a duplicate
    warning names its merchant, amount and id, so only who reads it gets one."""
    zatca = decode_zatca_tlv(QR)
    fp = compute_zatca_fingerprint(vat_number=zatca["vat_number"], invoice_timestamp=zatca["timestamp"],
                                   total_amount=7408.0)
    household.tables["transactions"].append(
        _tx("p-c-extra", COWIFE, "United Electronics Co. eXtra", 7408.0, MONTH_AGO, cls="wife_personal", wife=COWIFE,
            dedup_fingerprint=fp))
    resp = client.post("/agent/scan-receipt", headers=bearer(CALLERS[who]),
                       json={"household_id": HH, "qr_code_raw": QR, "preview_only": True})
    if _gone_husband(household, who, resp):
        return
    body = resp.json()
    if _sees(household.state, who, COWIFE):
        assert body["status"] == "duplicate_candidate", body
        assert body["candidate_transaction_id"] == "p-c-extra"
    else:
        assert body["status"] != "duplicate_candidate", body
        assert "p-c-extra" not in resp.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_a_chat_entry_warns_of_her_purchase_only_to_who_reads_it(household, who, monkeypatch):
    """A chat entry of the co-wife's purchase (same amount and merchant, today): only who reads it
    is told it was already recorded; anyone else records it as a new expense."""
    monkeypatch.setattr(chat_parser, "parse_chat_expense", lambda _m: chat_parser.ParsedChatExpense(
        merchant="Salon Huda", total_amount=313.0, currency="SAR", category_code="OPEX-SHOPPING", items=[]))
    monkeypatch.setattr(chat_parser, "insert_transaction", lambda *a, **k: "tx-new")
    resp = client.post("/agent/chat-transaction", headers=bearer(CALLERS[who]),
                       json={"household_id": HH, "message": "Salon Huda 313", "allow_duplicate": False})
    if who == "husband" and household.state == "gone":
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])
        return
    if _sees(household.state, who, COWIFE):
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "duplicate_candidate", resp.text
        assert resp.json()["candidate_transaction_id"] == "p-c1"
    else:
        # Recorded as new, or refused for its own reason (a family without a provider): never
        # told of hers.
        assert resp.status_code in (200, 409), resp.text
        assert "duplicate_candidate" not in resp.text and "p-c1" not in resp.text, resp.text


# ─── The rule itself, for every row ───────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_every_member_still_reads_every_other_transaction(household, who):
    """Regression: an ordinary household expense and her wife_reimbursable advance are in every
    member's price history, statement and recurring bills, as before."""
    if who == "husband" and household.state == "gone":
        return
    monkey_text = client.get("/reports/statement-pdf", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    assert monkey_text.status_code == 200
    bills = client.get("/budgets/recurring-bills", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    assert "STC Bill" in bills.text
    history = client.get("/analytics/price-history", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    assert "Rice" in history.text
