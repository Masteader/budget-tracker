"""
Who reads the installment plans of a wife's personal purchases, and her transfers, at the API
(owner decision 2026-11-06).

An installment plan linked to a purchase (``original_transaction_id``) is read by whoever reads
that purchase: a plan of her personal purchase (``nafaqah_class`` 'wife_personal') only by the
wife herself, her husband (the Nafaqah provider while he is a member who is not a wife) and a
household admin who is not a wife, as the database's installment_plans policy (test 65) says. Its
shop, amounts, dates, schedule and payments are the plan's own fields. The API reads plans with the
service role, so every answer checks the caller itself: the list, a payment, an edit, and a new plan
linked to a purchase. A caller who does not read a plan gets "not found" and changes nothing.
The plan keeps whose it was (``personal_owner_id``, kept by the database) after her purchase is
deleted, so it stays read by the same people (test 66). Every other plan (unlinked with no owner, of
an ordinary purchase, of her advance, of a woman who is no longer a wife of the household) stays in
every member's answers.

Transfers (account_transfers) are read by the API in one place only: a repayment's own transfer
inside her ledger, which only she and her husband read and which never involves her account. A
guard below keeps it that way.

The matrix: callers (the wife, her husband, a co-wife, an ordinary member, an admin who is not a
wife, a wife who is an admin) x (husband present and an admin, present and not an admin, gone).
"""

from __future__ import annotations

import pathlib
import re

import pytest

from test_wife_personal_privacy import (  # noqa: F401  (pytest fixtures)
    CALLERS,
    COWIFE,
    WIFE_ADMIN,
    _sees,
    household,
)
from test_wife_repayment_debit import (  # noqa: F401  (pytest fixtures)
    HH,
    WIFE,
    bearer,
    client,
    family,
)

PLAN_W = "b6000000-0000-4000-8000-000000000001"
PLAN_C = "b6000000-0000-4000-8000-000000000002"
PLAN_A = "b6000000-0000-4000-8000-000000000003"
PLAN_O = "b6000000-0000-4000-8000-000000000004"
PLAN_U = "b6000000-0000-4000-8000-000000000005"
PLAN_R = "b6000000-0000-4000-8000-000000000006"
PLAN_X = "b6000000-0000-4000-8000-000000000007"
# Plans whose purchase was deleted: no link, the owner the database kept.
PLAN_WD = "b6000000-0000-4000-8000-000000000008"
PLAN_CD = "b6000000-0000-4000-8000-000000000009"
PLAN_AD = "b6000000-0000-4000-8000-00000000000a"
PLAN_LD = "b6000000-0000-4000-8000-00000000000b"
# A woman who was a wife of the household and left it: no longer a wife here, her plans are everyone's.
FORMER = "b2000000-0000-4000-8000-0000000000aa"
# Read by no member: linked to a purchase that is not in the household (as under RLS).
NOBODY = "nobody"

# Each plan: (id, shop, linked purchase, whose personal purchase it is or None, the owner the
# database keeps on it). Names are distinct, so a leak shows in a response's text.
PLANS = [
    (PLAN_W, "Tabby Boutique Wafa", "p-w1", WIFE, WIFE),
    (PLAN_C, "Tamara Salon Huda", "p-c1", COWIFE, COWIFE),
    (PLAN_A, "Tabby Gold Mona", "p-a1", WIFE_ADMIN, WIFE_ADMIN),
    (PLAN_O, "Bank Danube Fridge", "o-1", None, None),
    (PLAN_U, "Other Unlinked Sofa", None, None, None),
    # Her wife_reimbursable advance (the family fixture's t1): an ordinary row for reading.
    (PLAN_R, "Tabby Panda Advance", "t1", None, None),
    (PLAN_X, "Bank Elsewhere Lamp", "tx-of-another-household", NOBODY, None),
    # Her purchase deleted: the plan stays hers.
    (PLAN_WD, "Tabby Perfume Wafa", None, WIFE, WIFE),
    (PLAN_CD, "Tamara Abaya Huda", None, COWIFE, COWIFE),
    (PLAN_AD, "Tabby Ring Mona", None, WIFE_ADMIN, WIFE_ADMIN),
    # She left the household: no longer a wife of it, so her plan is read like other rows.
    (PLAN_LD, "Tabby Scarf Former", None, None, FORMER),
]
OWNER = {pid: wife for pid, _shop, _tx, wife, _kept in PLANS}
SHOP = {pid: shop for pid, shop, _tx, _wife, _kept in PLANS}
PLAN_COLUMNS = {
    "id", "household_id", "merchant", "provider", "total_amount", "installment_count", "monthly_amount",
    "paid_installments", "day_of_month", "start_date", "frequency", "next_due_at", "status", "category_code",
    "original_transaction_id", "notes", "created_at", "personal_owner_id",
}


def _plan_row(pid, shop, tx, kept):
    return {
        "id": pid, "household_id": HH, "merchant": shop, "provider": "Tabby", "total_amount": 800.0,
        "installment_count": 4, "monthly_amount": 200.0, "paid_installments": 1, "day_of_month": 27,
        "start_date": "2026-11-01", "frequency": "monthly", "next_due_at": "2026-12-01", "status": "ACTIVE",
        "category_code": "OPEX-SHOPPING", "original_transaction_id": tx, "notes": f"note {shop}",
        "created_at": "2026-11-01T10:00:00+00:00", "personal_owner_id": kept,
    }


@pytest.fixture()
def plans(household):
    household.tables["installment_plans"] = [_plan_row(pid, shop, tx, kept) for pid, shop, tx, _w, kept in PLANS]
    # Strict, as PostgREST: only the selected columns come back, so a read that never selected the
    # owner cannot pass by accident.
    household.schemas["installment_plans"] = set(PLAN_COLUMNS)
    return household


def _reads(state, who, pid):
    wife = OWNER[pid]
    return wife is None or (wife != NOBODY and _sees(state, who, wife))


def _gone_husband(plans, who, resp):
    """The husband who left is no longer a member: refused at the door."""
    if who == "husband" and plans.state == "gone":
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])
        return True
    return False


def _plan(plans, pid):
    return next(p for p in plans.tables["installment_plans"] if p["id"] == pid)


# ─── The list ─────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_the_plan_list_holds_her_plans_only_for_who_reads_her_purchases(plans, who):
    resp = client.get("/budgets/installments", params={"household_id": HH}, headers=bearer(CALLERS[who]))
    if _gone_husband(plans, who, resp):
        return
    assert resp.status_code == 200, resp.text
    listed = {p["id"] for p in resp.json()["plans"]}
    expected = {pid for pid, *_ in PLANS if _reads(plans.state, who, pid)}
    assert listed == expected, (who, plans.state)
    assert resp.json()["count"] == len(expected)
    # Nothing of a plan the caller does not read: its shop, note or linked purchase.
    for pid, shop, tx, _wife, _kept in PLANS:
        if pid not in expected:
            assert shop not in resp.text and f"note {shop}" not in resp.text and f'"{tx}"' not in resp.text, (who, pid)
    # The owner the database keeps is not part of the answer.
    assert "personal_owner_id" not in resp.text


# ─── A payment, an edit ───────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("pid", [PLAN_W, PLAN_C, PLAN_A, PLAN_O, PLAN_U, PLAN_X, PLAN_WD, PLAN_CD, PLAN_AD, PLAN_LD])
def test_a_payment_on_her_plan_is_not_found_for_who_does_not_read_it(plans, who, pid):
    resp = client.post(f"/budgets/installments/{pid}/pay", headers=bearer(CALLERS[who]))
    if _gone_husband(plans, who, resp):
        assert _plan(plans, pid)["paid_installments"] == 1
        return
    if _reads(plans.state, who, pid):
        assert resp.status_code == 200, resp.text
        assert _plan(plans, pid)["paid_installments"] == 2
    else:
        assert resp.status_code == 404, resp.text
        assert SHOP[pid] not in resp.text
        assert _plan(plans, pid)["paid_installments"] == 1


@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("pid", [PLAN_W, PLAN_C, PLAN_A, PLAN_O, PLAN_U, PLAN_X, PLAN_WD, PLAN_CD, PLAN_AD, PLAN_LD])
def test_an_edit_of_her_plan_is_not_found_for_who_does_not_read_it(plans, who, pid):
    resp = client.put(f"/budgets/installments/{pid}", headers=bearer(CALLERS[who]), json={"notes": "edited"})
    if _gone_husband(plans, who, resp):
        assert _plan(plans, pid)["notes"] == f"note {SHOP[pid]}"
        return
    if _reads(plans.state, who, pid):
        assert resp.status_code == 200, resp.text
        assert _plan(plans, pid)["notes"] == "edited"
    else:
        assert resp.status_code == 404, resp.text
        assert SHOP[pid] not in resp.text
        assert _plan(plans, pid)["notes"] == f"note {SHOP[pid]}"


# ─── A new plan linked to her purchase ─────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
def test_a_new_plan_on_her_purchase_is_refused_as_not_found_for_who_does_not_read_it(plans, who):
    """The co-wife's personal purchase p-c1: who does not read it cannot link a plan to it (nor
    learn it exists); who reads it is checked as before (its maker or an admin edits it)."""
    before = len(plans.tables["installment_plans"])
    resp = client.post("/budgets/installments", headers=bearer(CALLERS[who]), json={
        "household_id": HH, "merchant": "Linked", "total_amount": 313.0, "installment_count": 4,
        "original_transaction_id": "p-c1", "adjust_original_transaction": False})
    if _gone_husband(plans, who, resp):
        assert len(plans.tables["installment_plans"]) == before
        return
    if not _sees(plans.state, who, COWIFE):
        assert resp.status_code == 404, resp.text
        assert len(plans.tables["installment_plans"]) == before
    elif who in ("co-wife", "admin") or (who == "husband" and plans.state == "present-admin"):
        assert resp.status_code == 200, resp.text
        assert len(plans.tables["installment_plans"]) == before + 1
    else:
        # The husband who is not an admin reads it but did not make it: the edit rule refuses him.
        assert resp.status_code == 403, resp.text
        assert len(plans.tables["installment_plans"]) == before


@pytest.mark.parametrize("who", list(CALLERS))
def test_a_new_plan_on_an_ordinary_purchase_is_still_checked_as_before(plans, who):
    """Regression: an ordinary expense (o-1, made by the husband) is linked by its maker or an admin."""
    resp = client.post("/budgets/installments", headers=bearer(CALLERS[who]), json={
        "household_id": HH, "merchant": "Linked", "total_amount": 103.0, "installment_count": 4,
        "original_transaction_id": "o-1", "adjust_original_transaction": False})
    if _gone_husband(plans, who, resp):
        return
    admin = who in ("admin", "wife-admin") or (who == "husband" and plans.state == "present-admin")
    maker = who == "husband"
    assert resp.status_code == (200 if admin or maker else 403), (who, resp.text)


# ─── Transfers ────────────────────────────────────────────────────────────────

def test_the_api_reads_transfers_only_for_a_repayment_inside_her_ledger():
    """account_transfers is read with the service role in one place: nafaqah_service._transfers,
    the transfers of the ledger's own repayments (his account or a pool to no account, and their
    reversals), inside answers only she and her husband get. Any new read must filter by the
    caller as the database's transfers read policy does (test 65)."""
    root = pathlib.Path(__file__).resolve().parents[1]
    reads = []
    for path in sorted(root.rglob("*.py")):
        rel = path.relative_to(root).as_posix()
        if rel.startswith(("tests/", ".venv/", "venv/")):
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"""["']account_transfers["']""", line):
                reads.append((rel, line.strip()))
    assert reads == [("nafaqah_service.py",
                      'rows = rows_in(client, "account_transfers", "id, from_account_id, to_account_id", "id", transfer_ids)')], reads
