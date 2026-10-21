"""
Scenario 8 (Fable review, migration 20261020800000): household roles and Nafaqah integrity on the
real stack.

- A wife who joins a roommate flat stays the wife of her family; the flat stays roommates.
- An existing member cannot claim the spouse invite meant for someone else.
- The husband is the explicit provider: a son who created the household is the default, an admin
  changes it through PUT /households/{id}/nafaqah/provider.
- Editing/deleting a wife advance after a repayment is refused by the database (PostgREST 22023,
  hint ledger_would_be_overpaid) and the ledger stays exact.
- wife_personal purchases never reach the category budget.
- Changing the payday through the API re-keys the open cycle.
"""

from __future__ import annotations


def _summary(user, hh):
    res = user.api.get(f"/households/{hh.id}/nafaqah")
    assert res.status_code == 200, res.text
    return res.json()


def test_wife_joining_a_flat_keeps_family_and_flat_apart(world, db, llm):
    family = world.family("R8a")
    husband, wife = family.admin, family.members[0]
    flat = world.roommates("R8a", n_members=1)
    world.join(wife, flat, world.invite(flat.admin, flat, "peer"))

    roles = {m["user_id"]: m["financial_role"] for m in flat.admin.api.get(f"/households/{flat.id}/members").json()["members"]}
    assert roles[wife.id] == "peer"
    assert db.scalar("SELECT financial_role FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
                     (family.id, wife.id)) == "spouse"

    summary = _summary(husband, family)
    assert summary["mode"] == "family_nafaqah" and summary["husband"]["id"] == husband.id
    assert [w["id"] for w in summary["wives"]] == [wife.id]
    assert flat.admin.api.get(f"/households/{flat.id}/settlement-v2").json()["mode"] == "multi_roommate"
    assert _summary(flat.admin, flat)["mode"] == "not_family"


def test_member_cannot_claim_the_spouse_invite(world, db):
    family = world.family("R8b")
    husband = family.admin
    son = world.signup("SonR8b")
    world.join(son, family, world.invite(husband, family, "family_member"))
    code = world.invite(husband, family, "spouse")

    # Members cannot even read invite codes through PostgREST.
    assert son.rest.get("/household_invites", params={"select": "invite_code"}).json() == []
    taken = son.api.post(f"/households/invites/{code}/claim")
    assert taken.status_code == 400, taken.text
    assert db.scalar("SELECT used_by FROM public.household_invites WHERE invite_code = %s", (code,)) is None
    assert db.scalar("SELECT financial_role FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
                     (family.id, son.id)) == "family_member"
    # The real invitee still can.
    second = world.signup("SecondWifeR8b")
    world.join(second, family, code)


def test_son_created_household_provider_is_explicit_and_changeable(world, db):
    son = world.signup("SonR8c")
    hh = world.create_household(son, "Son house R8c")
    wife = world.signup("WifeR8c")
    world.join(wife, hh, world.invite(son, hh, "spouse"))
    father = world.signup("FatherR8c")
    code = db.scalar("SELECT invite_code FROM public.households WHERE id = %s", (hh.id,))
    joined = father.rpc("join_household_by_code", {"p_invite_code": code})
    assert joined.status_code == 200 and "error" not in joined.json(), joined.text
    assert db.scalar("SELECT financial_role FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
                     (hh.id, father.id)) == "family_member"

    assert _summary(son, hh)["husband"]["id"] == son.id  # default: the primary admin
    assert father.api.put(f"/households/{hh.id}/nafaqah/provider", json={"user_id": father.id}).status_code == 403
    assert son.api.put(f"/households/{hh.id}/nafaqah/provider", json={"user_id": wife.id}).status_code == 422
    res = son.api.put(f"/households/{hh.id}/nafaqah/provider", json={"user_id": father.id})
    assert res.status_code == 200, res.text
    assert res.json()["summary"]["husband"]["id"] == father.id
    members = son.api.get(f"/households/{hh.id}/members").json()
    assert members["nafaqah_provider_user_id"] == father.id
    # Clients cannot write the column directly.
    son.rest.patch(f"/households?id=eq.{hh.id}", json={"nafaqah_provider_user_id": son.id})
    assert db.scalar("SELECT nafaqah_provider_user_id::text FROM public.households WHERE id = %s", (hh.id,)) == father.id


def test_editing_a_repaid_advance_is_refused(world, db, llm):
    family = world.family("R8d")
    husband, wife = family.admin, family.members[0]
    res = world.chat_commit(wife, family, llm, merchant="Panda R8d", amount=300, category_code="OPEX-GROCERY",
                            paid_by="me", beneficiary="both")
    assert res.status_code == 200 and res.json()["nafaqah_class"] == "wife_reimbursable", res.text
    tx_id = res.json()["transaction_id"]
    paid = husband.api.post(f"/households/{family.id}/nafaqah/reimbursements", json={"amount": 200})
    assert paid.status_code == 200, paid.text

    for user, call in (
        (wife, lambda u: u.rest.patch(f"/transactions?id=eq.{tx_id}", json={"amount": 100})),
        (husband, lambda u: u.rest.patch(f"/transactions?id=eq.{tx_id}",
                                         json={"nafaqah_class": None, "nafaqah_spouse_id": None})),
        (husband, lambda u: u.rest.delete(f"/transactions?id=eq.{tx_id}")),
    ):
        refused = call(user)
        assert refused.status_code == 400, refused.text
        assert refused.json()["code"] == "22023" and refused.json()["hint"] == "ledger_would_be_overpaid"
    assert float(db.scalar("SELECT amount FROM public.transactions WHERE id = %s", (tx_id,))) == 300.0
    balance = _summary(wife, family)["wives"][0]["reimbursement"]
    assert balance == {"gross_advanced": 300.0, "reimbursed": 200.0, "outstanding": 100.0, "overpaid": 0.0}

    ok = wife.rest.patch(f"/transactions?id=eq.{tx_id}", json={"amount": 200})
    assert ok.status_code in (200, 204), ok.text


def test_wife_personal_is_not_in_the_category_budget(world, db, llm):
    family = world.family("R8e")
    wife = family.members[0]
    cycle = db.scalar("SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 27)")
    db.query("INSERT INTO public.budgets (household_id, month, category_code, allocated_amount, cycle_key)"
             " VALUES (%s, (%s || '-01')::date, 'OPEX-SHOPPING', 1000, %s)", (family.id, cycle, cycle))
    res = world.chat_commit(wife, family, llm, merchant="Abaya R8e", amount=400, category_code="OPEX-SHOPPING",
                            paid_by="me", beneficiary="me")
    assert res.json()["nafaqah_class"] == "wife_personal", res.text
    world.chat_commit(family.admin, family, llm, merchant="Towels R8e", amount=100, category_code="OPEX-SHOPPING")
    spent = db.scalar("SELECT spent_amount FROM public.budgets WHERE household_id = %s AND category_code = 'OPEX-SHOPPING'",
                      (family.id,))
    assert float(spent) == 100.0
    assert _summary(wife, family)["wives"][0]["allowance"]["spent"] == 400.0


def test_payday_change_rekeys_the_open_cycle(world, db, llm):
    flat = world.roommates("R8f", n_members=1)
    admin = flat.admin
    for i in range(3):
        world.chat_commit(admin, flat, llm, merchant=f"Cafe R8f {i}", amount=10, category_code="OPEX-DINING")
    db.query("UPDATE public.transactions SET timestamp = now() + make_interval(days => (12 * n.i)::int)"
             " FROM (SELECT id, row_number() OVER (ORDER BY id) AS i FROM public.transactions WHERE household_id = %s) n"
             " WHERE public.transactions.id = n.id", (flat.id,))
    # Under payday 10 at least one of these dates (0, 12, 24 days ahead) belongs to another key.
    changing = db.scalar(
        "SELECT count(*) FROM public.transactions t WHERE t.household_id = %s AND t.cycle_key IS DISTINCT FROM"
        " (SELECT c.cycle_key FROM public.get_saudi_cycle_for_timestamp(t.timestamp, 10) c)", (flat.id,))
    assert changing > 0
    assert admin.api.put(f"/households/{flat.id}/payday", json={"payday_day": 10}).status_code == 200
    stale = db.scalar(
        "SELECT count(*) FROM public.transactions t WHERE t.household_id = %s AND t.cycle_key IS DISTINCT FROM"
        " (SELECT c.cycle_key FROM public.get_saudi_cycle_for_timestamp(t.timestamp, 10) c)", (flat.id,))
    assert stale == 0
