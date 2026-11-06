"""
Account deletion, the whole flow on the real stack: request_account_deletion and friends through
PostgREST with a real auth.sessions row, the real worker entry point against real PostgREST, and
fakes only for Auth Admin and Storage (both in the gateway). Nothing here reaches a hosted service.

The date cannot be moved by waiting 30 days, so "time passing" means moving the request's dates
back as the superuser. Everything else goes through the surfaces the app, the web page and the
Railway Cron service use.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest

from e2e_harness.tokens import anon_key


# ── Helpers ──────────────────────────────────────────────────────────────────


def _account(user, hh, name, *, shared=False):
    res = user.rest.post("/accounts", json={
        "household_id": hh.id, "owner_user_id": user.id, "name": name,
        "account_type": "shared_pool" if shared else "bank", "is_shared_pool": shared,
    }, headers={"Prefer": "return=representation"})
    assert res.status_code == 201, res.text
    return res.json()[0]["id"]


def _income(user, hh, account_id, amount):
    res = user.rpc("record_income", {
        "p_household_id": hh.id, "p_account_id": account_id, "p_cycle_key": None, "p_source_type": "salary",
        "p_title": f"Salary of {user.display_name}", "p_base_amount": amount,
    })
    assert res.status_code == 200, res.text


def _transfer(user, hh, src, dst, amount):
    res = user.rpc("transfer_between_accounts", {
        "p_household_id": hh.id, "p_from_account_id": src, "p_to_account_id": dst, "p_amount": amount, "p_fee": 0,
    })
    assert res.status_code == 200, res.text


def _expense(user, hh, amount, *, notes=None, receipt_url=None, beneficiary_id=None, account_id=None,
             merchant="Shared groceries", category="OPEX-GROCERY"):
    body = {
        "household_id": hh.id, "user_id": user.id, "amount": amount, "merchant": merchant, "category_code": category,
        "timestamp": datetime.now(timezone.utc).isoformat(), "source": "manual", "notes": notes,
        "receipt_url": receipt_url, "beneficiary_id": beneficiary_id, "account_id": account_id,
    }
    res = user.rest.post("/transactions", json=body, headers={"Prefer": "return=representation"})
    assert res.status_code == 201, res.text
    return res.json()[0]["id"]


def _budget(admin, hh, code="OPEX-GROCERY", amount=5000):
    res = admin.api.post("/budgets/categories", json={"household_id": hh.id, "code": code, "category": code,
                                                      "allocated_amount": amount})
    assert res.status_code == 200, res.text


def _session_client(world, db, user, *, age_minutes=0, owner=None):
    """A client whose JWT names a real auth.sessions row, as a fresh sign-in produces."""
    session_id = str(uuid.uuid4())
    db.query(
        "INSERT INTO auth.sessions (id, user_id, created_at) VALUES (%s, %s, now() - make_interval(mins => %s))",
        (session_id, (owner or user).id, age_minutes),
    )
    token = world.token_for(user, session_id=session_id)
    return world._client(
        f"{world.gateway_url}/rest/v1",
        {"Authorization": f"Bearer {token}", "apikey": anon_key(), "Content-Type": "application/json"},
    )


def _request(client, word="DELETE", *, choices=None, locale="en", reason=None):
    body = {"p_confirmation": word, "p_household_choices": choices or [], "p_locale": locale}
    if reason:
        body["p_reason"] = reason
    return client.post("/rpc/request_account_deletion", json=body)


def _hint(res):
    return res.json().get("hint")


def _pass_the_date(db, user):
    """The grace period is over: move the open request, and the marks it made, into the past."""
    db.query(
        """UPDATE public.account_deletion_requests
           SET scheduled_for = now() - interval '1 minute', requested_at = requested_at - interval '30 days'
           WHERE user_id = %s AND status = 'scheduled'""",
        (user.id,),
    )
    db.query(
        """UPDATE public.households
           SET deletion_scheduled_for = now() - interval '1 minute', deletion_requested_at = deletion_requested_at - interval '30 days'
           WHERE deletion_requested_by = %s""",
        (user.id,),
    )


@pytest.fixture()
def run_worker(stack, monkeypatch):
    """The Railway Cron entry point, in this process so the network guard stays on."""
    import account_deletion_worker

    def run(enabled=True, emails=None):
        if enabled:
            monkeypatch.setenv("ACCOUNT_DELETION_PURGE_ENABLED", "1")
        else:
            monkeypatch.delenv("ACCOUNT_DELETION_PURGE_ENABLED", raising=False)
        if emails is True:
            monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")
        elif emails is False:
            monkeypatch.delenv("ACCOUNT_DELETION_EMAILS_ENABLED", raising=False)
        return account_deletion_worker.main()

    return run


@pytest.fixture()
def gateway(stack):
    stack.gateway.auth_calls.clear()
    stack.gateway.auth_delete_failures = 0
    stack.gateway.emails.clear()
    yield stack.gateway
    stack.gateway.auth_delete_failures = 0
    stack.gateway.emails.clear()  # test_06 asserts an empty mailbox without a provider


@pytest.fixture()
def resend(gateway, monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_e2e_fake_key")
    monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")
    gateway.resend_status = 200
    yield gateway


def _pool_balances(db, *households):
    rows = db.query(
        "SELECT id::text, balance FROM public.accounts WHERE is_shared_pool AND household_id = ANY(%s::uuid[])",
        ([hh.id for hh in households],),
    )
    return {r["id"]: Decimal(r["balance"]) for r in rows}


def _budgets_spent(db, *households):
    rows = db.query(
        "SELECT id::text, spent_amount FROM public.budgets WHERE household_id = ANY(%s::uuid[])",
        ([hh.id for hh in households],),
    )
    return {r["id"]: Decimal(r["spent_amount"]) for r in rows}


def _public_rows_naming(db, needle):
    """Every row of every public table whose text contains needle, as {table: count}."""
    found = {}
    tables = db.query(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
    )
    for row in tables:
        name = row["table_name"]
        count = db.scalar(f'SELECT count(*) FROM public."{name}" x WHERE x::text ILIKE %s', (f"%{needle}%",))
        if count:
            found[name] = count
    return found


def _assert_user_erased(db, user):
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = %s", (user.id,)) == 0
    assert db.scalar("SELECT count(*) FROM public.users WHERE id = %s", (user.id,)) == 0
    assert db.scalar("SELECT count(*) FROM auth.sessions WHERE user_id = %s", (user.id,)) == 0
    for needle in (user.id, user.email, user.display_name):
        assert _public_rows_naming(db, needle) == {}, needle


def _completed_tombstones(db):
    return db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE status = 'completed'")


# ── The member's path ────────────────────────────────────────────────────────


def test_member_request_cancel_rerequest_and_purge_keep_the_ledgers(world, db, gateway, run_worker):
    flat = world.roommates("DELA", n_members=2)
    admin, bob, carol = flat.admin, flat.members[0], flat.members[1]
    outsider = world.signup("OutsiderDELA")

    _budget(admin, flat)
    pool = _account(admin, flat, "House pool", shared=True)
    bob_wallet = _account(bob, flat, "Bob wallet")
    _income(admin, flat, pool, 2000)
    _income(bob, flat, pool, 1000)                 # his income into the pool stays
    _income(bob, flat, bob_wallet, 700)            # his income into his own account goes
    _transfer(bob, flat, bob_wallet, pool, 150)    # personal to pool: the pool keeps it

    receipt_path = f"{flat.id}/bob-receipt.jpg"
    carol_receipt_path = f"{flat.id}/carol-receipt.jpg"
    gateway.storage[f"receipts/{receipt_path}"] = b"bob"
    gateway.storage[f"receipts/{carol_receipt_path}"] = b"carol"

    bob_tx = _expense(
        bob, flat, 80,
        notes=f"Ask {bob.display_name} on 0500000000 | PaidBy: me | Beneficiary: both | SpentBy: me",
        receipt_url=f"{world.gateway_url}/storage/v1/object/receipts/{receipt_path}",
    )
    carol_tx = _expense(
        carol, flat, 45, beneficiary_id=bob.id,
        notes=f"For the flat | PaidBy: me | Beneficiary: {bob.id} | SpentBy: me",
        receipt_url=f"{world.gateway_url}/storage/v1/object/receipts/{carol_receipt_path}",
    )

    pools_before = _pool_balances(db, flat)
    budgets_before = _budgets_spent(db, flat)
    assert pools_before[pool] == Decimal("3150.00")
    assert budgets_before and sum(budgets_before.values()) == Decimal("125.00")
    tombstones_before = _completed_tombstones(db)

    # Nothing pending yet.
    assert bob.rpc("get_account_deletion_status").json()["status"] == "none"

    # Re-auth is enforced by the server: no session row, an old one, someone else's.
    assert _hint(_request(bob.rest)) == "reauthentication_required"
    stale = _session_client(world, db, bob, age_minutes=16)
    assert _hint(_request(stale)) == "reauthentication_required"
    foreign = _session_client(world, db, bob, owner=carol)
    assert _hint(_request(foreign)) == "reauthentication_required"

    fresh = _session_client(world, db, bob)
    wrong = _request(fresh, "please delete")
    assert wrong.status_code == 400 and _hint(wrong) == "confirmation_mismatch", wrong.text
    assert bob.rpc("get_account_deletion_status").json()["status"] == "none"

    # The Urdu word, spelled as the app and the web page show it.
    first = _request(fresh, "حذف کریں", locale="ur", reason="moving away")
    assert first.status_code == 200, first.text
    body = first.json()
    assert body["success"] is True and body["already_requested"] is False
    assert body["status"] == "scheduled" and body["can_cancel"] is True and body["locale"] == "ur"
    assert "reason" not in body
    when = datetime.fromisoformat(body["scheduled_for"])
    assert timedelta(days=29, hours=23) < when - datetime.now(timezone.utc) <= timedelta(days=30)

    # A double request keeps the first date.
    again = _request(fresh, "حذف کریں", locale="ur")
    assert again.json()["already_requested"] is True and again.json()["scheduled_for"] == body["scheduled_for"]

    # While pending: usable, but no joining or creating. The API answers 409 with the hint's message.
    assert bob.api.get(f"/households/{flat.id}/settlement-v2").status_code == 200
    other = world.create_household(outsider, "Other flat DELA", household_type="roommates")
    joined = bob.api.post(f"/households/invites/{world.invite(outsider, other)}/claim")
    assert joined.status_code == 409, joined.text
    created = bob.rpc("create_household_and_claim", {"p_name": "Escape"})
    assert _hint(created) == "account_pending_deletion", created.text

    # Cancel needs no re-auth, and a cancelled request is never purged even with its date passed.
    cancelled = bob.rpc("cancel_account_deletion")
    assert cancelled.status_code == 200 and cancelled.json()["cancelled"] is True, cancelled.text
    assert bob.rpc("get_account_deletion_status").json()["status"] == "none"
    db.query("UPDATE public.account_deletion_requests SET scheduled_for = now() - interval '1 day' WHERE user_id = %s",
             (bob.id,))
    assert run_worker() == 0
    assert gateway.auth_calls == []
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = %s", (bob.id,)) == 1

    # Re-request: a new request with a new date. Not due yet, so the worker leaves it alone.
    second = _request(fresh, "delete", locale="en")
    assert second.status_code == 200 and second.json()["already_requested"] is False, second.text
    assert second.json()["request_id"] != body["request_id"]
    assert run_worker() == 0
    assert gateway.auth_calls == []
    assert bob.rpc("get_account_deletion_status").json()["status"] == "scheduled"

    # The date passes. With the safety switch off the worker changes nothing.
    _pass_the_date(db, bob)
    assert run_worker(enabled=False) == 0
    assert gateway.auth_calls == []
    assert bob.rpc("get_account_deletion_status").json()["status"] == "scheduled"
    assert f"receipts/{receipt_path}" in gateway.storage

    runs_before = db.scalar("SELECT count(*) FROM public.account_deletion_worker_runs")

    # The switch on: the purge runs.
    assert run_worker() == 0

    assert ("DELETE", bob.id) in gateway.auth_calls
    assert db.scalar("SELECT count(*) FROM public.account_deletion_worker_runs") == runs_before + 1
    last_run = db.one("SELECT claimed, completed, failed FROM public.account_deletion_worker_runs ORDER BY started_at DESC LIMIT 1")
    assert (last_run["claimed"], last_run["completed"], last_run["failed"]) == (1, 1, 0)

    # An identifier-free tombstone, and the older cancelled request is gone.
    assert _completed_tombstones(db) == tombstones_before + 1
    tombstone = db.one("SELECT user_id, reason FROM public.account_deletion_requests WHERE id = %s",
                       (second.json()["request_id"],))
    assert tombstone == {"user_id": None, "reason": None}
    assert db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE id = %s", (body["request_id"],)) == 0

    # The ledgers did not move.
    assert _pool_balances(db, flat) == pools_before
    assert _budgets_spent(db, flat) == budgets_before

    # His rows stay, without him.
    tx = db.one("SELECT user_id, notes, receipt_url, amount FROM public.transactions WHERE id = %s", (bob_tx,))
    assert tx["user_id"] is None and tx["receipt_url"] is None and Decimal(tx["amount"]) == Decimal("80.00")
    assert tx["notes"] == "| PaidBy: me | Beneficiary: both | SpentBy: me"
    income = db.query("SELECT user_id, notes, title, net_amount FROM public.income_records WHERE account_id = %s",
                      (pool,))
    assert sorted(Decimal(r["net_amount"]) for r in income) == [Decimal("1000.00"), Decimal("2000.00")]
    his = next(r for r in income if Decimal(r["net_amount"]) == Decimal("1000.00"))
    assert his["user_id"] is None and his["notes"] is None and bob.display_name not in (his["title"] or "")
    assert db.scalar("SELECT count(*) FROM public.accounts WHERE id = %s", (bob_wallet,)) == 0
    transfer = db.one("SELECT user_id, from_account_id::text AS src, to_account_id::text AS dst, amount "
                      "FROM public.account_transfers WHERE household_id = %s", (flat.id,))
    assert transfer["user_id"] is None and transfer["src"] is None and transfer["dst"] == pool
    assert Decimal(transfer["amount"]) == Decimal("150.00")

    # Someone else's row names him no more, and keeps its own words and receipt.
    theirs = db.one("SELECT user_id::text AS user_id, notes, beneficiary_id, receipt_url FROM public.transactions "
                    "WHERE id = %s", (carol_tx,))
    assert theirs["user_id"] == carol.id and theirs["beneficiary_id"] == "deleted_member"
    assert theirs["notes"] == "For the flat | PaidBy: me | Beneficiary: deleted_member | SpentBy: me"
    assert theirs["receipt_url"]

    # Only his image went.
    assert f"receipts/{receipt_path}" not in gateway.storage
    assert f"receipts/{carol_receipt_path}" in gateway.storage

    _assert_user_erased(db, bob)

    # The household carries on and its screens still load with a creator-less row in them.
    assert db.scalar("SELECT count(*) FROM public.household_memberships WHERE household_id = %s", (flat.id,)) == 2
    for user in (admin, carol):
        assert user.api.get(f"/households/{flat.id}/settlement-v2").status_code == 200
        assert user.api.get(f"/households/{flat.id}/settlement").status_code == 200

    # His JWT lives until exp, and reaches nothing: the row is gone.
    assert bob.api.get(f"/households/{flat.id}/settlement-v2").status_code in (401, 403, 404)
    assert bob.rest.get(f"/transactions?household_id=eq.{flat.id}").json() == []
    assert bob.rpc("get_account_deletion_status").json()["status"] == "none"

    # A later run has nothing left to do.
    gateway.auth_calls.clear()
    assert run_worker() == 0
    assert gateway.auth_calls == []


# ── The admin's two choices ──────────────────────────────────────────────────


def test_admin_deletes_household_and_former_members_are_repointed(world, db, resend, run_worker):
    doomed = world.roommates("DELB", n_members=0)
    ann = doomed.admin
    mo = world.signup("MoDELB")      # co-admin here, plain member of a second household
    lia = world.signup("LiaDELB")    # only here
    world.join(mo, doomed, world.invite(ann, doomed))
    world.join(lia, doomed, world.invite(ann, doomed))
    promoted = ann.api.post(f"/households/{doomed.id}/members/{mo.id}/admin")
    assert promoted.status_code == 200, promoted.text

    other = world.roommates("DELC", n_members=0)
    world.join(mo, other, world.invite(other.admin, other))
    _budget(other.admin, other)
    other_pool = _account(other.admin, other, "Other pool", shared=True)
    _income(other.admin, other, other_pool, 900)
    _expense(mo, other, 33)

    # Mo looks at the doomed household when it goes.
    switched = mo.rpc("switch_active_household", {"p_household_id": doomed.id})
    assert switched.status_code in (200, 204), switched.text
    active = db.one("SELECT household_id::text AS h, role FROM public.users WHERE id = %s", (mo.id,))
    assert active == {"h": doomed.id, "role": "admin"}

    doomed_pool = _account(ann, doomed, "Doomed pool", shared=True)
    _income(lia, doomed, doomed_pool, 500)
    lia_wallet = _account(lia, doomed, "Lia wallet")
    _income(lia, doomed, lia_wallet, 200)
    _transfer(lia, doomed, lia_wallet, doomed_pool, 50)
    _expense(lia, doomed, 12)

    gateway = resend
    gateway.storage[f"receipts/{doomed.id}/a.jpg"] = b"a"
    gateway.storage[f"receipts/{doomed.id}/2026/b.jpg"] = b"b"
    gateway.storage[f"receipts/{other.id}/keep.jpg"] = b"keep"

    other_pools = _pool_balances(db, other)
    other_budgets = _budgets_spent(db, other)
    assert other_budgets

    client = _session_client(world, db, ann)

    # The preflight says what the flow must ask.
    preflight = client.post("/rpc/get_account_deletion_preflight", json={}).json()
    entry = next(h for h in preflight["households"] if h["household_id"] == doomed.id)
    assert entry["position"] == "primary_admin" and entry["needs_choice"] is True
    assert {c["user_id"] for c in entry["candidates"]} == {mo.id, lia.id}

    # A required choice, and the successor is checked.
    assert _hint(_request(client)) == "household_choice_missing"
    bad = _request(client, choices=[{"household_id": doomed.id, "action": "transfer", "successor_user_id": other.admin.id}])
    assert _hint(bad) == "successor_invalid", bad.text
    foreign = _request(client, choices=[{"household_id": other.id, "action": "delete"}])
    assert _hint(foreign) == "household_choice_invalid", foreign.text

    choice = [{"household_id": doomed.id, "action": "delete"}]
    first = _request(client, choices=choice)
    assert first.status_code == 200, first.text
    assert [m["household_id"] for m in first.json()["marked_households"]] == [doomed.id]

    # Members see the mark (the banner reads this), and the household takes nobody new.
    seen = lia.rest.get(f"/households?id=eq.{doomed.id}&select=deletion_scheduled_for").json()
    assert seen[0]["deletion_scheduled_for"]
    invite = ann.api.post(f"/households/{doomed.id}/invites", json={"role": "peer"})
    assert invite.status_code == 409, invite.text

    # Cancel lifts the mark and the banner with it; choosing again marks it again.
    assert ann.rpc("cancel_account_deletion").json()["cancelled"] is True
    seen = lia.rest.get(f"/households?id=eq.{doomed.id}&select=deletion_scheduled_for").json()
    assert seen[0]["deletion_scheduled_for"] is None
    assert _request(client, choices=choice).status_code == 200

    # The next run tells the members, before the date, in the request's language.
    gateway.emails.clear()
    assert run_worker() == 0
    assert sorted(addr for mail in gateway.emails for addr in mail["to"]) == sorted([mo.email, lia.email])
    assert db.scalar("SELECT 'member_marked' = ANY(notices_sent) FROM public.account_deletion_requests "
                     "WHERE user_id = %s AND status = 'scheduled'", (ann.id,)) is True
    assert db.scalar("SELECT count(*) FROM public.households WHERE id = %s", (doomed.id,)) == 1

    _pass_the_date(db, ann)
    gateway.emails.clear()
    assert run_worker() == 0

    # The household and everything in it is gone, including other members' entries.
    assert db.scalar("SELECT count(*) FROM public.households WHERE id = %s", (doomed.id,)) == 0
    for table in ("transactions", "accounts", "income_records", "account_transfers", "household_memberships", "budgets"):
        assert db.scalar(f"SELECT count(*) FROM public.{table} WHERE household_id = %s", (doomed.id,)) == 0, table
    assert [k for k in gateway.storage if k.startswith(f"receipts/{doomed.id}/")] == []
    assert f"receipts/{other.id}/keep.jpg" in gateway.storage

    # The other household did not notice.
    assert _pool_balances(db, other) == other_pools
    assert _budgets_spent(db, other) == other_budgets

    # Repointed, with the role of the household they landed in.
    moved = db.one("SELECT household_id::text AS h, role, financial_role FROM public.users WHERE id = %s", (mo.id,))
    membership = db.one("SELECT role, financial_role, is_default FROM public.household_memberships "
                        "WHERE user_id = %s AND household_id = %s", (mo.id, other.id))
    assert moved == {"h": other.id, "role": "member", "financial_role": membership["financial_role"]}
    assert membership["role"] == "member" and membership["is_default"] is True
    alone = db.one("SELECT household_id, role FROM public.users WHERE id = %s", (lia.id,))
    assert alone == {"household_id": None, "role": "member"}

    # Both keep their logins, and Mo's app works against the new household.
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = ANY(%s::uuid[])", ([mo.id, lia.id],)) == 2
    assert mo.api.get(f"/households/{other.id}/settlement-v2").status_code == 200

    # The account holder heard it was done, after the delete and in their language.
    assert [mail["to"] for mail in gateway.emails] == [[ann.email]]
    _assert_user_erased(db, ann)


def test_admin_transfers_and_household_survives_with_its_pool(world, db, gateway, run_worker):
    flat = world.roommates("DELD", n_members=2)
    admin, heir, mate = flat.admin, flat.members[0], flat.members[1]
    _budget(admin, flat)
    pool = _account(admin, flat, "Pool", shared=True)
    _income(admin, flat, pool, 1200)
    _income(mate, flat, pool, 300)
    _expense(admin, flat, 60, account_id=pool)
    pools_before = _pool_balances(db, flat)
    budgets_before = _budgets_spent(db, flat)

    client = _session_client(world, db, admin)
    choice = [{"household_id": flat.id, "action": "transfer", "successor_user_id": heir.id}]
    res = _request(client, "حذف", choices=choice, locale="ar")
    assert res.status_code == 200, res.text
    assert res.json()["marked_households"] == []

    # The handover runs at once; the caller stays a co-admin until the end.
    assert db.scalar("SELECT owner_user_id::text FROM public.households WHERE id = %s", (flat.id,)) == heir.id
    assert db.scalar("SELECT role FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
                     (flat.id, admin.id)) == "admin"

    # Cancelling keeps the handover: only the primary title was lost.
    assert admin.rpc("cancel_account_deletion").json()["cancelled"] is True
    assert db.scalar("SELECT owner_user_id::text FROM public.households WHERE id = %s", (flat.id,)) == heir.id

    # Now only a co-admin, so no choice on the way back in.
    assert _request(client, "حذف", locale="ar").status_code == 200

    _pass_the_date(db, admin)
    assert run_worker() == 0

    assert db.scalar("SELECT count(*) FROM public.households WHERE id = %s", (flat.id,)) == 1
    assert _pool_balances(db, flat) == pools_before
    assert _budgets_spent(db, flat) == budgets_before
    assert db.scalar("SELECT owner_user_id::text FROM public.accounts WHERE id = %s", (pool,)) == heir.id
    assert heir.api.get(f"/households/{flat.id}/settlement-v2").status_code == 200
    _assert_user_erased(db, admin)


# ── Wife, in a family household ──────────────────────────────────────────────


def test_wife_purge_moves_no_budget(world, db, llm, gateway, run_worker):
    hh = world.family("DELE")
    husband, wife = hh.admin, hh.members[0]
    assert husband.api.put(f"/households/{hh.id}/nafaqah/allowance", json={"amount": 500}).status_code == 200
    _budget(husband, hh, "OPEX-SHOPPING")
    _budget(husband, hh, "OPEX-GROCERY")
    personal = world.chat_commit(wife, hh, llm, merchant="Zara", amount=120, category_code="OPEX-SHOPPING",
                                 paid_by="me", beneficiary="me")
    assert personal.status_code == 200 and personal.json()["nafaqah_class"] == "wife_personal", personal.text
    advance = world.chat_commit(wife, hh, llm, merchant="Lulu", amount=60, category_code="OPEX-GROCERY")
    assert advance.status_code == 200, advance.text
    budgets_before = _budgets_spent(db, hh)
    assert budgets_before

    client = _session_client(world, db, wife)
    assert _request(client, "delete").status_code == 200
    _pass_the_date(db, wife)
    assert run_worker() == 0

    assert _budgets_spent(db, hh) == budgets_before
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE id = %s", (personal.json()["transaction_id"],)) == 0
    kept = db.one("SELECT user_id, nafaqah_class FROM public.transactions WHERE id = %s",
                  (advance.json()["transaction_id"],))
    assert kept is not None and kept["user_id"] is None
    assert kept["nafaqah_class"] != "wife_personal"
    assert husband.api.get(f"/households/{hh.id}/settlement").status_code == 200
    _assert_user_erased(db, wife)


def test_what_a_leaving_wife_is_owed_reaches_her_husband_and_stays_as_one_anonymised_record(
        world, db, llm, resend, run_worker):
    """Migration 20261105001200: told before, kept after, closed by payment or waiver, no money moved."""
    gateway = resend
    hh = world.family("DELO")
    husband, wife = hh.admin, hh.members[0]
    _budget(husband, hh, "OPEX-GROCERY")
    advance = world.chat_commit(wife, hh, llm, merchant="Lulu", amount=90, category_code="OPEX-GROCERY")
    assert advance.status_code == 200 and advance.json()["nafaqah_class"] == "wife_reimbursable", advance.text
    paid = husband.api.post(f"/households/{hh.id}/nafaqah/reimbursements", json={"amount": 20, "payment_method": "cash"})
    assert paid.status_code == 200, paid.text

    assert _request(_session_client(world, db, wife), "delete").status_code == 200
    # Before: the husband sees it in the app, the wife does not see a creditor notice.
    pending = husband.api.get(f"/households/{hh.id}/nafaqah").json()["wives"][0]["pending_deletion"]
    assert pending["outstanding"] == 70.0 and pending["scheduled_for"]
    assert wife.api.get(f"/households/{hh.id}/nafaqah").json()["wives"][0]["pending_deletion"] is None
    gateway.emails.clear()
    assert run_worker(emails=True) == 0
    to_husband = [m for m in gateway.emails if husband.email in m["to"]]
    assert len(to_husband) == 1 and "70.00" in to_husband[0]["text"]
    assert wife.display_name not in to_husband[0]["text"] + to_husband[0]["subject"]
    gateway.emails.clear()
    assert run_worker(emails=True) == 0
    assert [m for m in gateway.emails if husband.email in m["to"]] == [], "once"

    pools, budgets = _pool_balances(db, hh), _budgets_spent(db, hh)
    _pass_the_date(db, wife)
    assert run_worker(emails=False) == 0
    _assert_user_erased(db, wife)

    debts = husband.api.get(f"/households/{hh.id}/nafaqah").json()["former_member_debts"]
    assert [(d["original_amount"], d["remaining"], d["status"]) for d in debts] == [(70.0, 70.0, "open")]
    debt = debts[0]["id"]
    base = f"/households/{hh.id}/nafaqah/former-member-debts/{debt}"
    key = str(uuid.uuid4())
    first = husband.api.post(f"{base}/payments", json={"amount": 30.5, "payment_method": "bank_transfer", "request_key": key})
    assert first.status_code == 200, first.text
    assert (first.json()["remaining"], first.json()["replayed"]) == (39.5, False)
    again = husband.api.post(f"{base}/payments", json={"amount": 30.5, "payment_method": "bank_transfer", "request_key": key})
    assert again.status_code == 200 and again.json()["replayed"] is True
    over = husband.api.post(f"{base}/payments", json={"amount": 39.51, "payment_method": "cash", "request_key": str(uuid.uuid4())})
    assert over.status_code == 409 and over.json()["detail"]["code"] == "overpayment"
    # Straight to the database function, as the app's JWT: the same refusal.
    direct = husband.rpc("record_former_member_debt_payment", {
        "p_household_id": hh.id, "p_debt_id": debt, "p_amount": 39.51, "p_payment_method": "cash",
        "p_request_key": str(uuid.uuid4())})
    assert direct.status_code >= 400 and _hint(direct) == "overpayment"
    waived = husband.api.post(f"{base}/waiver", json={"request_key": str(uuid.uuid4())})
    assert waived.status_code == 200 and waived.json()["status"] == "waived", waived.text

    after = husband.api.get(f"/households/{hh.id}/nafaqah").json()["former_member_debts"][0]
    assert (after["status"], after["paid_amount"]) == ("waived", 30.5)
    assert [(e["kind"], e["amount"]) for e in after["events"]] == [("payment", 30.5), ("waiver", 39.5)]
    assert _pool_balances(db, hh) == pools and _budgets_spent(db, hh) == budgets
    _assert_user_erased(db, wife)


# ── Failure and retry ────────────────────────────────────────────────────────


def test_auth_failure_is_recorded_and_the_retry_finishes_the_job(world, db, gateway, run_worker, caplog):
    caplog.set_level("INFO")
    flat = world.roommates("DELF", n_members=1)
    admin, mate = flat.admin, flat.members[0]
    pool = _account(admin, flat, "Pool", shared=True)
    _income(mate, flat, pool, 400)
    before = _pool_balances(db, flat)
    client = _session_client(world, db, mate)
    request_id = _request(client, "delete").json()["request_id"]
    _pass_the_date(db, mate)

    gateway.auth_delete_failures = 1
    assert run_worker() == 1  # Railway shows the run as failed

    row = db.one("SELECT status, stage, attempts, last_error_code, lease_expires_at > now() AS backing_off "
                 "FROM public.account_deletion_requests WHERE id = %s", (request_id,))
    assert row == {"status": "processing", "stage": "storage_done", "attempts": 1, "last_error_code": "auth_failed",
                   "backing_off": True}
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = %s", (mate.id,)) == 1

    # Too late to cancel: the data is already gone.
    refused = mate.rpc("cancel_account_deletion")
    assert _hint(refused) == "deletion_in_progress", refused.text

    # Backing off, so the next run skips it.
    gateway.auth_calls.clear()
    assert run_worker() == 0
    assert gateway.auth_calls == []

    db.query("UPDATE public.account_deletion_requests SET lease_expires_at = now() - interval '1 minute' WHERE id = %s",
             (request_id,))
    assert run_worker() == 0
    assert db.scalar("SELECT status FROM public.account_deletion_requests WHERE id = %s", (request_id,)) == "completed"
    assert _pool_balances(db, flat) == before
    _assert_user_erased(db, mate)

    # The run logged the job and its error code, and nothing that identifies the person.
    assert "auth_failed" in caplog.text
    assert mate.id not in caplog.text and mate.email not in caplog.text


def test_user_already_gone_from_auth_counts_as_done(world, db, gateway, run_worker):
    """A dashboard delete during grace: the fake answers 404 as GoTrue does, and the job still closes."""
    flat = world.roommates("DELG", n_members=1)
    mate = flat.members[0]
    client = _session_client(world, db, mate)
    request_id = _request(client, "delete").json()["request_id"]
    db.query("DELETE FROM auth.users WHERE id = %s", (mate.id,))
    _pass_the_date(db, mate)

    assert run_worker() == 0
    assert ("DELETE", mate.id) in gateway.auth_calls
    tombstone = db.one("SELECT status, user_id FROM public.account_deletion_requests WHERE id = %s", (request_id,))
    assert tombstone == {"status": "completed", "user_id": None}


def test_a_cancel_between_claim_and_prepare_is_not_a_failed_run(world, db, gateway, run_worker, monkeypatch, caplog):
    """The user cancels after the worker claimed the job and before prepare: the real
    prepare_account_purge refuses (purge_not_allowed), the real record_account_purge_failure answers
    'cancelled', and the run is a success with nothing purged."""
    import account_deletion_worker

    caplog.set_level("INFO")
    flat = world.roommates("DELH", n_members=1)
    mate = flat.members[0]
    request_id = _request(_session_client(world, db, mate), "delete").json()["request_id"]
    _pass_the_date(db, mate)

    real_rpc = account_deletion_worker._rpc
    cancels = []

    def rpc(client, name, params=None):
        data = real_rpc(client, name, params)
        if name == "claim_due_account_deletions" and any(j["request_id"] == request_id for j in data or []):
            assert db.scalar("SELECT status FROM public.account_deletion_requests WHERE id = %s", (request_id,)) == "processing"
            cancels.append(mate.rpc("cancel_account_deletion").json())
        return data

    monkeypatch.setattr(account_deletion_worker, "_rpc", rpc)
    runs_before = db.scalar("SELECT count(*) FROM public.account_deletion_worker_runs")

    assert run_worker() == 0

    assert [c.get("cancelled") for c in cancels] == [True]
    row = db.one("SELECT status, stage, user_id::text AS user_id FROM public.account_deletion_requests WHERE id = %s",
                 (request_id,))
    assert row == {"status": "cancelled", "stage": "none", "user_id": mate.id}
    assert gateway.auth_calls == []
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = %s", (mate.id,)) == 1
    assert db.scalar("SELECT count(*) FROM public.account_deletion_worker_runs") == runs_before + 1
    last_run = db.one("SELECT failed FROM public.account_deletion_worker_runs ORDER BY started_at DESC LIMIT 1")
    assert last_run == {"failed": 0}
    worker_errors = [r for r in caplog.records if r.name == "account_deletion_worker" and r.levelname == "ERROR"]
    assert worker_errors == []
    assert f"Account deletion job {request_id} was cancelled" in caplog.text


# ── The operator path, for someone who cannot sign in ────────────────────────


def _operator_cli():
    """ai_service/scripts/account_deletion_operator.py, against the real PostgREST."""
    import importlib.util
    from pathlib import Path

    from e2e_harness import config

    path = Path(config.AI_SERVICE_DIR) / "scripts" / "account_deletion_operator.py"
    spec = importlib.util.spec_from_file_location("account_deletion_operator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _form_request(world, email):
    res = world.anonymous_api().post("/public/inquiries", json={
        "type": "account_deletion", "email": email, "message": "I cannot sign in", "locale": "en", "source": "web",
    })
    assert res.status_code == 200, res.text
    return res


def test_operator_path_from_form_to_purge(world, db, resend, run_worker, capsys):
    from supabase_client import get_client

    gateway = resend
    flat = world.roommates("DELO", n_members=1)
    admin, mate = flat.admin, flat.members[0]
    pool = _account(admin, flat, "Pool", shared=True)
    _income(mate, flat, pool, 800)
    pools_before = _pool_balances(db, flat)

    # The form stored a row. It looked up nothing and scheduled nothing.
    _form_request(world, mate.email)
    assert db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE user_id = %s", (mate.id,)) == 0
    reference = db.scalar("SELECT reference FROM public.inquiries WHERE email = %s AND type = 'account_deletion'",
                          (mate.email,))

    operator = _operator_cli()
    client = get_client()
    base = ["--email", mate.email, "--inquiry-id", reference, "--verified-by", "dev_one"]

    # Dry run: says what would happen, changes nothing.
    assert operator.main(base, client=client) == 0
    out = capsys.readouterr().out
    assert "DRY RUN" in out and mate.email not in out and mate.id not in out
    assert db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE user_id = %s", (mate.id,)) == 0

    # An admin with other members is refused until someone says what happens to the household.
    admin_base = ["--email", admin.email, "--inquiry-id", reference, "--verified-by", "dev_one"]
    assert operator.main([*admin_base, "--execute"], client=client) == 2
    out = capsys.readouterr().out
    assert flat.id in out and "--choice" in out and mate.id not in out and mate.email not in out
    assert db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE user_id = %s", (admin.id,)) == 0

    # Nobody with that address: said plainly, with nothing else.
    assert operator.main(["--email", "nobody@e2e.test", "--inquiry-id", reference, "--verified-by", "dev_one"],
                         client=client) == 2

    # Scheduled, and the ordinary status and cancel see it.
    assert operator.main([*base, "--execute"], client=client) == 0
    assert mate.rpc("get_account_deletion_status").json()["status"] == "scheduled"
    assert mate.rpc("cancel_account_deletion").json()["cancelled"] is True

    # Scheduled again, then cancelled by the operator, then scheduled for good.
    assert operator.main([*base, "--execute"], client=client) == 0
    assert operator.main([*base, "--execute"], client=client) == 0  # idempotent
    assert db.scalar("SELECT count(*) FROM public.account_deletion_requests WHERE user_id = %s AND status = 'scheduled'",
                     (mate.id,)) == 1
    assert operator.main([*base, "--cancel", "--execute"], client=client) == 0
    assert mate.rpc("get_account_deletion_status").json()["status"] == "none"
    assert operator.main([*base, "--execute"], client=client) == 0
    capsys.readouterr()

    row = db.one("SELECT id::text, initiated_by, operator_inquiry_reference, operator_verified_by, reason "
                 "FROM public.account_deletion_requests WHERE user_id = %s AND status = 'scheduled'", (mate.id,))
    assert (row["initiated_by"], row["operator_inquiry_reference"], row["operator_verified_by"], row["reason"]) == (
        "operator", reference, "dev_one", None)

    # The 90-day removal takes the row, as the page says, and the job does not care.
    db.query("UPDATE public.inquiries SET created_at = now() - interval '91 days' WHERE reference = %s", (reference,))
    db.query("UPDATE public.account_deletion_requests SET notices_sent = '{}' WHERE id = %s", (row["id"],))
    assert run_worker() == 0
    assert db.scalar("SELECT count(*) FROM public.inquiries WHERE reference = %s", (reference,)) == 0
    assert db.scalar("SELECT operator_inquiry_reference FROM public.account_deletion_requests WHERE id = %s",
                     (row["id"],)) == reference

    _pass_the_date(db, mate)
    assert run_worker() == 0
    tombstone = db.one("SELECT status, user_id, initiated_by, operator_inquiry_reference "
                       "FROM public.account_deletion_requests WHERE id = %s", (row["id"],))
    assert tombstone == {"status": "completed", "user_id": None, "initiated_by": "operator",
                         "operator_inquiry_reference": None}
    assert _pool_balances(db, flat) == pools_before
    _assert_user_erased(db, mate)


# ── The email switch, real worker against real SQL ───────────────────────────


def _date_in(db, user, away):
    """How far away the date is now, for the request and the households it marked."""
    db.query("UPDATE public.account_deletion_requests SET scheduled_for = now() + %s::interval "
             "WHERE user_id = %s AND status = 'scheduled'", (away, user.id))
    db.query("UPDATE public.households SET deletion_scheduled_for = now() + %s::interval "
             "WHERE deletion_requested_by = %s", (away, user.id))


def _notices_sent(db, request_id):
    return db.scalar("SELECT notices_sent FROM public.account_deletion_requests WHERE id = %s", (request_id,))


def _mail_to(gateway):
    return sorted(addr for mail in gateway.emails for addr in mail["to"])


def _household_being_deleted(world, db, tag):
    flat = world.roommates(tag, n_members=1)
    client = _session_client(world, db, flat.admin)
    res = _request(client, choices=[{"household_id": flat.id, "action": "delete"}])
    assert res.status_code == 200, res.text
    return flat, flat.admin, flat.members[0], res.json()["request_id"]


def test_emails_off_for_weeks_then_on_sends_only_what_still_helps(world, db, resend, run_worker):
    gateway = resend
    flat, holder, member, request_id = _household_being_deleted(world, db, "DELM")

    # Off, with a provider ready: nobody hears anything and nothing counts as sent.
    assert run_worker(emails=False) == 0
    _date_in(db, holder, "5 days")
    assert run_worker(emails=False) == 0
    _date_in(db, holder, "12 hours")
    assert run_worker(emails=False) == 0
    assert gateway.emails == []
    assert _notices_sent(db, request_id) == []

    # On, 12 hours out: T-1 for the holder and the first notice for the member. The T-7 that
    # passed unsent stays unsent, so no one gets a stale reminder or two at once.
    assert run_worker(emails=True) == 0
    assert _mail_to(gateway) == sorted([holder.email, member.email])
    subjects = {mail["to"][0]: mail["subject"] for mail in gateway.emails}
    assert "last reminder" in subjects[holder.email]
    assert "a household you belong to" in subjects[member.email]
    assert set(_notices_sent(db, request_id)) >= {"holder_t1", "member_marked"}
    assert "holder_t7" not in _notices_sent(db, request_id)

    # Once each.
    gateway.emails.clear()
    assert run_worker(emails=True) == 0
    assert gateway.emails == []

    # Off again when the date passes: the completion email is skipped, and the job completes.
    gateway.auth_calls.clear()
    _pass_the_date(db, holder)
    assert run_worker(emails=False) == 0
    assert gateway.emails == []
    assert db.scalar("SELECT status FROM public.account_deletion_requests WHERE id = %s", (request_id,)) == "completed"
    assert not {"GET"} & {method for method, _ in gateway.auth_calls}, "no address is read when nothing will be sent"
    assert db.scalar("SELECT count(*) FROM public.households WHERE id = %s", (flat.id,)) == 0
    _assert_user_erased(db, holder)


@pytest.mark.parametrize("away, holder_gets", [
    ("36 hours", False),      # T-7 is stale and T-1 is coming
    ("30 minutes", False),    # the purge is next
    ("3 days", True),         # T-7 was missed, and still helps
])
def test_turning_emails_on_near_the_date(world, db, resend, run_worker, away, holder_gets):
    gateway = resend
    mate_flat = world.roommates("DELN", n_members=1)
    mate = mate_flat.members[0]
    client = _session_client(world, db, mate)
    request_id = _request(client).json()["request_id"]
    _date_in(db, mate, away)

    assert run_worker(emails=True) == 0
    assert _mail_to(gateway) == ([mate.email] if holder_gets else [])
    assert ("holder_t7" in _notices_sent(db, request_id)) is holder_gets

    assert mate.rpc("cancel_account_deletion").json()["cancelled"] is True


def test_completion_email_goes_when_emails_are_on(world, db, resend, run_worker):
    gateway = resend
    flat = world.roommates("DELP", n_members=1)
    mate = flat.members[0]
    client = _session_client(world, db, mate)
    _request(client, locale="ur")
    _pass_the_date(db, mate)
    assert run_worker(emails=True) == 0
    assert _mail_to(gateway) == [mate.email]
    assert "حذف ہو گیا ہے" in gateway.emails[0]["subject"]
    _assert_user_erased(db, mate)


def test_developer_alert_goes_out_with_emails_off(world, db, resend, run_worker):
    gateway = resend
    flat = world.roommates("DELQ", n_members=1)
    mate = flat.members[0]
    client = _session_client(world, db, mate)
    request_id = _request(client).json()["request_id"]
    _pass_the_date(db, mate)
    db.query("UPDATE public.account_deletion_requests SET attempts = 4 WHERE id = %s", (request_id,))
    gateway.auth_delete_failures = 1

    assert run_worker(emails=False) == 1
    assert db.scalar("SELECT status FROM public.account_deletion_requests WHERE id = %s", (request_id,)) == "failed"
    assert _mail_to(gateway) == ["inbox@e2e.test"]
    body = gateway.emails[0]["text"]
    assert request_id in body and mate.email not in body and mate.id not in body
    assert _notices_sent(db, request_id) == ["ops_failed"]

    # Once.
    gateway.emails.clear()
    assert run_worker(emails=False) == 0
    assert gateway.emails == []


def test_purge_off_sends_no_reminder_and_touches_no_job(world, db, resend, run_worker):
    """A reminder would name a date the purge would not meet, so it needs both switches."""
    gateway = resend
    flat = world.roommates("DELR", n_members=1)
    mate = flat.members[0]
    client = _session_client(world, db, mate)
    request_id = _request(client).json()["request_id"]
    _date_in(db, mate, "12 hours")

    assert run_worker(enabled=False, emails=True) == 0
    assert gateway.emails == []
    assert _notices_sent(db, request_id) == []

    # The date passes with the purge still off: no job claimed.
    _pass_the_date(db, mate)
    assert run_worker(enabled=False, emails=True) == 0
    assert gateway.emails == []
    assert gateway.auth_calls == []
    assert db.scalar("SELECT status FROM public.account_deletion_requests WHERE id = %s", (request_id,)) == "scheduled"

    # Both on, with the date a day out: the reminder that was held back goes.
    _date_in(db, mate, "12 hours")
    assert run_worker(enabled=True, emails=True) == 0
    assert _mail_to(gateway) == [mate.email]
    assert "holder_t1" in _notices_sent(db, request_id)

    assert mate.rpc("cancel_account_deletion").json()["cancelled"] is True


# ── What clients cannot do ───────────────────────────────────────────────────


SERVICE_ONLY = {
    "claim_due_account_deletions": {"p_limit": 1, "p_lease_minutes": 30},
    "prepare_account_purge": {"p_request_id": "00000000-0000-0000-0000-000000000000"},
    "list_account_purge_storage": {"p_request_id": "00000000-0000-0000-0000-000000000000"},
    "mark_account_purge_storage_done": {"p_request_id": "00000000-0000-0000-0000-000000000000"},
    "complete_account_purge": {"p_request_id": "00000000-0000-0000-0000-000000000000"},
    "record_account_purge_failure": {"p_request_id": "00000000-0000-0000-0000-000000000000", "p_error_code": "x"},
    "list_account_deletion_notices_due": {},
    "mark_account_deletion_notice_sent": {"p_request_id": "00000000-0000-0000-0000-000000000000", "p_notice": "holder_t7"},
    "record_account_deletion_worker_run": {"p_started_at": "2026-11-05T00:00:00Z", "p_claimed": 0, "p_completed": 0, "p_failed": 0},
    "get_account_deletion_queue_summary": {},
    "get_account_deletion_operator_preview": {"p_email": "someone@example.com", "p_inquiry_reference": "x"},
    "schedule_account_deletion_by_operator": {"p_user_id": "00000000-0000-0000-0000-000000000000",
                                              "p_inquiry_reference": "x", "p_verified_by": "x"},
    "cancel_account_deletion_by_operator": {"p_user_id": "00000000-0000-0000-0000-000000000000",
                                            "p_inquiry_reference": "x", "p_verified_by": "x"},
    "list_account_deletion_alerts_due": {},
    "purge_expired_account_deletion_inquiries": {"p_days": 90},
}

CLIENT_RPCS = {
    "get_account_deletion_status": {},
    "get_account_deletion_preflight": {},
    "cancel_account_deletion": {},
    "request_account_deletion": {"p_confirmation": "delete"},
}

CLOSED_TABLES = ("account_deletion_requests", "account_deletion_storage_queue", "account_deletion_worker_runs")


def test_clients_cannot_reach_the_purge(world, db, gateway):
    user = world.signup("ClientDELH")
    anon = world._client(f"{world.gateway_url}/rest/v1", {"apikey": anon_key(), "Content-Type": "application/json"})

    for name, params in SERVICE_ONLY.items():
        for client in (user.rest, anon):
            res = client.post(f"/rpc/{name}", json=params)
            assert res.status_code in (401, 403, 404), f"{name}: {res.status_code} {res.text}"
    for name, params in CLIENT_RPCS.items():
        res = anon.post(f"/rpc/{name}", json=params)
        assert res.status_code in (401, 403, 404), f"{name}: {res.status_code} {res.text}"
    for table in CLOSED_TABLES:
        for client in (user.rest, anon):
            assert client.get(f"/{table}").status_code in (401, 403, 404), table
            assert client.post(f"/{table}", json={}).status_code in (401, 403, 404), table

    # A client cannot mark a household or clear a mark by writing the columns itself.
    hh = world.create_household(user, "Mine DELH", household_type="roommates")
    write = user.rest.patch(f"/households?id=eq.{hh.id}", json={"deletion_scheduled_for": None})
    assert write.status_code in (401, 403), write.text

    # The fake Auth Admin refuses anything but the service role, like the real one.
    client = world._client(world.gateway_url, {"Authorization": f"Bearer {user.token}"})
    assert client.delete(f"/auth/v1/admin/users/{user.id}").status_code == 403
    assert gateway.auth_calls == []
    assert db.scalar("SELECT count(*) FROM auth.users WHERE id = %s", (user.id,)) == 1


# ── The public page and form, served by the rebuilt bundle ───────────────────


def test_public_page_and_links_resolve(world):
    # Behind the proxy, the way the Play Store listing and the app reach it.
    visitor = world.anonymous_api(**{"X-Forwarded-For": "203.0.113.90"})
    root = visitor.get("/")
    assert root.status_code == 200 and "text/html" in root.headers["content-type"]
    for lang in ("ar", "en", "ur"):
        page = visitor.get("/delete-account", params={"lang": lang})
        assert page.status_code == 200, page.text
        assert page.text == root.text
    assert visitor.get("/delete-account-not-a-page").status_code in (401, 404)
    assert visitor.get("/delete-account/").status_code in (200, 307, 401, 404)


def test_public_form_only_stores_a_row(world, db, resend):
    resend.emails.clear()
    email = f"leaver.{uuid.uuid4().hex[:6]}@example.com"
    res = world.anonymous_api().post("/public/inquiries", json={
        "type": "account_deletion", "email": email, "name": "Leaver", "message": "Please delete me",
        "locale": "ur", "source": "web",
    })
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "sent"
    assert db.scalar("SELECT count(*) FROM public.inquiries WHERE type = 'account_deletion' AND lower(email) = %s",
                     (email,)) == 1
    # It goes to the developer, never to the address typed into the form, and touches no account.
    assert resend.emails and all(mail["to"] == ["inbox@e2e.test"] for mail in resend.emails)
    assert resend.auth_calls == []
