"""
Scenario 7: money integrity. Sub-halala transfers/income are rejected (DB-06) and never mint money;
after a long mixed sequence of API and PostgREST operations, budgets.spent_amount equals the sum of
the household's transactions per (category, cycle) and every account balance equals its ledger
(income - debits - transfers out - fees + transfers in).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal

from e2e_harness.zatca import tlv_qr


def _account(user, hh, name, *, shared=False):
    res = user.rest.post("/accounts", json={
        "household_id": hh.id, "owner_user_id": user.id, "name": name,
        "account_type": "shared_pool" if shared else "bank", "is_shared_pool": shared,
    }, headers={"Prefer": "return=representation"})
    assert res.status_code == 201, res.text
    return res.json()[0]["id"]


def _income(user, hh, account_id, amount, **extra):
    return user.rpc("record_income", {
        "p_household_id": hh.id, "p_account_id": account_id, "p_cycle_key": None, "p_source_type": "salary",
        "p_title": "Salary", "p_base_amount": amount, **extra,
    })


def _transfer(user, hh, src, dst, amount, fee=0):
    return user.rpc("transfer_between_accounts", {
        "p_household_id": hh.id, "p_from_account_id": src, "p_to_account_id": dst, "p_amount": amount, "p_fee": fee,
    })


def _balances(db, hh):
    return {r["id"]: Decimal(r["balance"]) for r in db.query(
        "SELECT id::text, balance FROM public.accounts WHERE household_id = %s", (hh.id,))}


def _ledger_mismatches(db, hh):
    rows = db.query(
        """
        SELECT a.id::text, a.name, a.balance,
               COALESCE((SELECT sum(net_amount) FROM public.income_records i WHERE i.account_id = a.id), 0)
             - COALESCE((SELECT sum(amount) FROM public.transactions t WHERE t.account_id = a.id), 0)
             - COALESCE((SELECT sum(amount + fee) FROM public.account_transfers f WHERE f.from_account_id = a.id), 0)
             + COALESCE((SELECT sum(amount) FROM public.account_transfers f WHERE f.to_account_id = a.id), 0)
               AS ledger
        FROM public.accounts a WHERE a.household_id = %s
        """,
        (hh.id,),
    )
    return [(r["name"], r["balance"], r["ledger"]) for r in rows if r["balance"] != r["ledger"]]


def _budget_mismatches(db, hh):
    rows = db.query(
        """
        SELECT b.category_code, b.cycle_key, b.spent_amount,
               COALESCE((SELECT sum(t.amount) FROM public.transactions t
                         WHERE t.household_id = b.household_id AND t.category_code = b.category_code
                           AND t.cycle_key = b.cycle_key), 0) AS tx_sum
        FROM public.budgets b WHERE b.household_id = %s AND b.cycle_key IS NOT NULL
        """,
        (hh.id,),
    )
    return [(r["category_code"], r["cycle_key"], r["spent_amount"], r["tx_sum"]) for r in rows
            if r["spent_amount"] != r["tx_sum"]]


def test_sub_halala_transfers_and_income_are_rejected(world, db):
    hh = world.roommates("M1", n_members=0)
    admin = hh.admin
    a1 = _account(admin, hh, "Al Rajhi")
    a2 = _account(admin, hh, "STC Pay")
    assert _income(admin, hh, a1, 100).status_code == 200

    for amount, fee in ((1.005, 0), ("1.005", 0), (1, 0.001), (0.001, 0)):
        res = _transfer(admin, hh, a1, a2, amount, fee)
        assert res.status_code == 400, (amount, fee, res.text)
        assert "2 decimal" in res.text
    assert _income(admin, hh, a1, 1.005).status_code == 400
    assert _income(admin, hh, a1, 10, p_deductions=-5).status_code == 400
    assert _balances(db, hh) == {a1: Decimal("100.00"), a2: Decimal("0.00")}
    assert db.scalar("SELECT count(*) FROM public.account_transfers WHERE household_id = %s", (hh.id,)) == 0

    ok = _transfer(admin, hh, a1, a2, 1.01, 0.25)
    assert ok.status_code == 200, ok.text
    assert _balances(db, hh) == {a1: Decimal("98.74"), a2: Decimal("1.01")}
    # Money is conserved except for the recorded fee.
    assert sum(_balances(db, hh).values()) + Decimal("0.25") == Decimal("100.00")
    # Overdraft is refused.
    assert _transfer(admin, hh, a2, a1, 5).status_code >= 400

    # API side: a 3-decimal Nafaqah repayment / allowance is a validation error, not silently rounded.
    fam = world.family("M1")
    res = fam.admin.api.put(f"/households/{fam.id}/nafaqah/allowance", json={"amount": 10.005})
    assert res.status_code == 422, res.text


def test_chat_amount_precision_is_consistent(world, db, llm):
    hh = world.roommates("M2", n_members=0)
    res = world.chat_commit(hh.admin, hh, llm, merchant="Herfy", amount=10.005)
    assert res.status_code == 200, res.text
    stored = db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (res.json()["transaction_id"],))
    assert stored == Decimal(str(res.json()["amount"])), "API response and stored amount disagree"
    assert stored == stored.quantize(Decimal("0.01"))


def test_totals_consistent_after_operation_sequence(world, db, llm):
    hh = world.roommates("M3", n_members=2)
    admin, alice, bob = hh.admin, hh.members[0], hh.members[1]

    # Budgets for the current cycle (admin, through the API).
    for code, amount in (("OPEX-DINING", 800), ("OPEX-GROCERY", 1500), ("OPEX-MISC", 300)):
        r = admin.api.post("/budgets/categories", json={"household_id": hh.id, "code": code, "category": code,
                                                         "allocated_amount": amount})
        assert r.status_code == 200, r.text

    # Accounts and income.
    pool = _account(admin, hh, "House pool", shared=True)
    admin_bank = _account(admin, hh, "Admin bank")
    alice_wallet = _account(alice, hh, "Alice STC Pay")
    bob_wallet = _account(bob, hh, "Bob Urpay")
    assert _income(admin, hh, admin_bank, 9000).status_code == 200
    assert _income(alice, hh, alice_wallet, 4000.50).status_code == 200
    assert _income(bob, hh, bob_wallet, 3500).status_code == 200
    assert _income(alice, hh, pool, 1200).status_code == 200
    assert _income(bob, hh, pool, 1200).status_code == 200
    assert _transfer(admin, hh, admin_bank, pool, 1200, 1.15).status_code == 200

    checks = []

    def check(label):
        checks.append((label, _budget_mismatches(db, hh), _ledger_mismatches(db, hh)))

    # 1. Chat commits by everyone (no account) and a ZATCA receipt.
    for user, merchant, amount, cat in ((alice, "Albaik", 31.5, "OPEX-DINING"), (bob, "Panda", 212.35, "OPEX-GROCERY"),
                                        (admin, "Kudu", 44, "OPEX-DINING")):
        assert world.chat_commit(user, hh, llm, merchant=merchant, amount=amount, category_code=cat).status_code == 200
    qr = tlv_qr("Othaim Markets", "310000000000003", "2026-10-19T12:00:00Z", "57.50", "7.50")
    scan = bob.api.post("/agent/scan-receipt", json={"household_id": hh.id, "qr_code_raw": qr})
    assert scan.status_code == 200 and scan.json()["status"] == "success", scan.text
    check("after chat + receipt")

    # 2. Direct PostgREST inserts debiting accounts (what the app does for manual entries).
    now = datetime.now(timezone.utc)

    def manual(user, account, amount, cat, when=None, merchant="Manual"):
        r = user.rest.post("/transactions", json={
            "household_id": hh.id, "user_id": user.id, "amount": amount, "merchant": merchant,
            "category_code": cat, "timestamp": (when or now).isoformat(), "source": "manual", "account_id": account,
        }, headers={"Prefer": "return=representation"})
        assert r.status_code == 201, r.text
        return r.json()[0]["id"]

    t_pool = manual(alice, pool, 400, "OPEX-GROCERY", merchant="Pool groceries")
    t_alice = manual(alice, alice_wallet, 99.99, "OPEX-DINING")
    t_bob = manual(bob, bob_wallet, 15.25, "OPEX-MISC")
    t_admin = manual(admin, admin_bank, 250, "OPEX-GROCERY")
    check("after manual inserts")

    # 3. Edits: amount, category, account, and a timestamp that moves the row to the previous cycle.
    def patch(user, tx, **fields):
        r = user.rest.patch(f"/transactions?id=eq.{tx}", json=fields, headers={"Prefer": "return=representation"})
        assert r.status_code == 200 and r.json(), r.text

    patch(alice, t_alice, amount=120.10)
    patch(alice, t_alice, category_code="OPEX-MISC")
    patch(bob, t_bob, account_id=None)
    patch(bob, t_bob, account_id=bob_wallet, amount=16)
    patch(admin, t_pool, amount=380.40)  # admin edits a member's pool expense
    prev_cycle_day = now - timedelta(days=35)
    patch(admin, t_admin, timestamp=prev_cycle_day.isoformat())
    check("after edits")

    # 4. Deletes and transfers.
    r = admin.rest.delete(f"/transactions?id=eq.{t_bob}", headers={"Prefer": "return=representation"})
    assert r.status_code == 200 and r.json(), r.text
    assert _transfer(alice, hh, alice_wallet, bob_wallet, 250.75, 0.5).status_code == 200
    assert _transfer(admin, hh, pool, admin_bank, 100).status_code == 200
    check("after delete + transfers")

    # 5. API recalculation must agree with the triggers (no drift either way).
    assert admin.api.post("/budgets/recalculate", params={"household_id": hh.id}).status_code == 200
    check("after /budgets/recalculate")

    failures = [(label, b, l) for label, b, l in checks if b or l]
    assert not failures, "\n".join(f"{label}: budgets={b} ledger={l}" for label, b, l in failures)

    # Spot-check the absolute numbers of the current cycle.
    cycle = db.scalar("SELECT cycle_key FROM public.transactions WHERE id = %s", (t_pool,))
    spent = {r["category_code"]: r["spent_amount"] for r in db.query(
        "SELECT category_code, spent_amount FROM public.budgets WHERE household_id = %s AND cycle_key = %s",
        (hh.id, cycle))}
    assert spent["OPEX-DINING"] == Decimal("75.50")
    assert spent["OPEX-GROCERY"] == Decimal("212.35") + Decimal("57.50") + Decimal("380.40")
    assert spent["OPEX-MISC"] == Decimal("120.10")
