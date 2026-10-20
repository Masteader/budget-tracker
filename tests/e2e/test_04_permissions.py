"""
Scenario 4: roles and permissions (DB-16 / DB-18) through the API and directly through PostgREST
with the member's own JWT (what the Flutter app does for edits and deletes).
"""

from __future__ import annotations

from typing import Optional


def _commit(world, llm, user, hh, merchant, amount=50.0):
    res = world.chat_commit(user, hh, llm, merchant=merchant, amount=amount, category_code="OPEX-DINING")
    assert res.status_code == 200, res.text
    return res.json()["transaction_id"]


def _patch_tx(user, tx_id, **fields):
    return user.rest.patch(f"/transactions?id=eq.{tx_id}", json=fields, headers={"Prefer": "return=representation"})


def test_transaction_edit_and_delete_permissions(world, db, llm):
    hh = world.roommates("E1", n_members=2)
    admin, alice, bob = hh.admin, hh.members[0], hh.members[1]
    alice_tx = _commit(world, llm, alice, hh, "Kudu Alice")
    bob_tx = _commit(world, llm, bob, hh, "Kudu Bob")

    # Member edits own transaction directly through PostgREST: OK.
    own = _patch_tx(alice, alice_tx, merchant="Kudu Alice (edited)", amount=55)
    assert own.status_code == 200, own.text
    assert own.json()[0]["merchant"] == "Kudu Alice (edited)"

    # Member edits / deletes someone else's: 403 from the database, row untouched.
    other = _patch_tx(alice, bob_tx, amount=1)
    assert other.status_code == 403, other.text
    gone = alice.rest.delete(f"/transactions?id=eq.{bob_tx}")
    assert gone.status_code == 403, gone.text
    assert float(db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (bob_tx,))) == 50.0
    # Re-assigning the creator to dodge the rule is refused too.
    steal = _patch_tx(alice, bob_tx, user_id=alice.id)
    assert steal.status_code == 403

    # Through the API: linking another member's transaction to an installment plan is an edit.
    plan = {"household_id": hh.id, "provider": "tabby", "merchant": "Jarir", "total_amount": 400,
            "installment_count": 4, "original_transaction_id": bob_tx}
    api_other = alice.api.post("/budgets/installments", json=plan)
    assert api_other.status_code == 403, api_other.text
    api_own = alice.api.post("/budgets/installments", json={
        **plan, "original_transaction_id": alice_tx, "adjust_original_transaction": False})
    assert api_own.status_code == 200, api_own.text
    # Enriching another member's transaction by chat is an edit as well.
    world_llm_items = {"is_transaction": True, "merchant": "Kudu Bob", "total_amount": 50, "items": [
        {"name": "Burger", "quantity": 1, "price": 50}]}
    llm.queue_json(world_llm_items)
    enrich = alice.api.post("/agent/chat-transaction", json={
        "household_id": hh.id, "message": "add items", "enrich_tx_id": bob_tx})
    assert enrich.status_code == 403, enrich.text

    # Admin edits and deletes anyone's.
    admin_edit = _patch_tx(admin, bob_tx, merchant="Kudu Bob (admin fix)")
    assert admin_edit.status_code == 200 and admin_edit.json(), admin_edit.text
    admin_del = admin.rest.delete(f"/transactions?id=eq.{alice_tx}", headers={"Prefer": "return=representation"})
    assert admin_del.status_code == 200 and len(admin_del.json()) == 1
    # A member deletes their own.
    own_del = bob.rest.delete(f"/transactions?id=eq.{bob_tx}", headers={"Prefer": "return=representation"})
    assert own_del.status_code == 200 and len(own_del.json()) == 1


def _account(user, hh, name, *, shared: bool) -> str:
    res = user.rest.post("/accounts", json={
        "household_id": hh.id, "owner_user_id": user.id, "name": name,
        "account_type": "shared_pool" if shared else "bank", "is_shared_pool": shared,
    }, headers={"Prefer": "return=representation"})
    assert res.status_code == 201, res.text
    return res.json()[0]["id"]


def _income(user, hh, account_id, amount) -> None:
    res = user.rpc("record_income", {
        "p_household_id": hh.id, "p_account_id": account_id, "p_cycle_key": None, "p_source_type": "salary",
        "p_title": "Salary", "p_base_amount": amount,
    })
    assert res.status_code == 200, res.text


def _transfer(user, hh, src, dst, amount, fee=0) -> "object":
    return user.rpc("transfer_between_accounts", {
        "p_household_id": hh.id, "p_from_account_id": src, "p_to_account_id": dst, "p_amount": amount, "p_fee": fee,
    })


def test_shared_pool_withdrawal_admin_only(world, db):
    hh = world.roommates("E2", n_members=1)
    admin, member = hh.admin, hh.members[0]
    # Only an admin can create the shared pool.
    denied_pool = member.rest.post("/accounts", json={
        "household_id": hh.id, "owner_user_id": member.id, "name": "Pool?", "account_type": "shared_pool",
        "is_shared_pool": True})
    assert denied_pool.status_code in (401, 403), denied_pool.text
    pool = _account(admin, hh, "House pool", shared=True)
    member_wallet = _account(member, hh, "Member STC Pay", shared=False)
    admin_wallet = _account(admin, hh, "Admin bank", shared=False)
    _income(member, hh, pool, 1000)  # anyone may pay INTO the pool

    withdraw = _transfer(member, hh, pool, member_wallet, 100)
    assert withdraw.status_code == 403, withdraw.text
    assert "shared pool" in withdraw.text
    assert float(db.scalar("SELECT balance FROM public.accounts WHERE id = %s", (pool,))) == 1000.0

    ok = _transfer(admin, hh, pool, admin_wallet, 100, fee=1.5)
    assert ok.status_code == 200, ok.text
    balances = {r["id"]: float(r["balance"]) for r in db.query(
        "SELECT id::text, balance FROM public.accounts WHERE household_id = %s", (hh.id,))}
    assert balances == {pool: 898.5, admin_wallet: 100.0, member_wallet: 0.0}

    # Nobody moves money out of another member's personal account.
    _income(member, hh, member_wallet, 50)
    assert _transfer(admin, hh, member_wallet, admin_wallet, 10).status_code == 403


def _members(user, hh):
    res = user.api.get(f"/households/{hh.id}/members")
    assert res.status_code == 200, res.text
    return res.json()


def _role(user, hh, target_id) -> Optional[str]:
    return {m["user_id"]: m["role"] for m in _members(user, hh)["members"]}.get(target_id)


def test_co_admin_promotion_protection_and_primary_transfer(world, db, llm):
    hh = world.roommates("E3", n_members=2)
    primary, co, plain = hh.admin, hh.members[0], hh.members[1]

    # A member cannot promote anyone.
    assert plain.api.post(f"/households/{hh.id}/members/{plain.id}/admin").status_code == 403

    promoted = primary.api.post(f"/households/{hh.id}/members/{co.id}/admin")
    assert promoted.status_code == 200, promoted.text
    assert _role(primary, hh, co.id) == "admin"
    assert db.scalar("SELECT role FROM public.users WHERE id = %s", (co.id,)) == "admin"

    # The co-admin now has admin rights in the database too (edits another member's tx via PostgREST).
    plain_tx = _commit(world, llm, plain, hh, "Shawarmer")
    assert _patch_tx(co, plain_tx, merchant="Shawarmer (co-admin)").status_code == 200

    # A co-admin cannot demote the primary admin: API, RPC and raw table write all refuse.
    demote = co.api.delete(f"/households/{hh.id}/members/{primary.id}/admin")
    assert demote.status_code == 403, demote.text
    rpc = co.rpc("revoke_admin", {"p_household_id": hh.id, "p_user_id": primary.id, "p_actor_user_id": co.id})
    assert rpc.status_code >= 400, rpc.text
    raw = co.rest.patch(f"/household_memberships?household_id=eq.{hh.id}&user_id=eq.{primary.id}",
                        json={"role": "member"}, headers={"Prefer": "return=representation"})
    assert raw.status_code in (401, 403) or raw.json() == [], raw.text
    assert _role(primary, hh, primary.id) == "admin"
    # ...nor transfer primary ownership.
    steal = co.api.post(f"/households/{hh.id}/primary-admin", json={"new_primary_user_id": co.id})
    assert steal.status_code == 403
    # A co-admin may promote others (any admin can).
    assert co.api.post(f"/households/{hh.id}/members/{plain.id}/admin").status_code == 200
    assert co.api.delete(f"/households/{hh.id}/members/{plain.id}/admin").status_code == 200
    assert _role(primary, hh, plain.id) == "member"

    # Primary transfers ownership to the co-admin.
    transfer = primary.api.post(f"/households/{hh.id}/primary-admin", json={"new_primary_user_id": co.id})
    assert transfer.status_code == 200, transfer.text
    view = _members(co, hh)
    assert view["primary_admin_user_id"] == co.id and view["caller_is_primary"] is True
    assert db.scalar("SELECT owner_user_id::text FROM public.households WHERE id = %s", (hh.id,)) == co.id
    # The former primary is now an ordinary co-admin: the new primary can demote them...
    assert co.api.delete(f"/households/{hh.id}/members/{primary.id}/admin").status_code == 200
    assert _role(co, hh, primary.id) == "member"
    # ...and the sole remaining admin cannot be demoted.
    last = co.api.delete(f"/households/{hh.id}/members/{co.id}/admin")
    assert last.status_code in (403, 409), last.text
    assert _role(co, hh, co.id) == "admin"
