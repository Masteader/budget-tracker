"""
Scenario 9 (owner decisions D1-D3, migration 20261020900000) on the real stack.

- D1: a flat created as 'roommates' and joined by the static code settles as roommates (peers,
  multi_roommate, pairwise debts); the released app's {p_name} call still creates a family; an
  admin switches the type and sets financial roles through the API; mismatched invites are refused.
- D2: an adult son can classify nothing (API 403 with a code; PostgREST insert refused by the
  database), the wife and the provider can.
- D3: when the wife leaves, her ledger in that household is gone and her expenses are ordinary
  (a former wife_personal purchase now counts in the category budget).
"""

from __future__ import annotations


def _static_join(world, db, user, hh):
    code = db.scalar("SELECT invite_code FROM public.households WHERE id = %s", (hh.id,))
    res = user.rpc("join_household_by_code", {"p_invite_code": code})
    assert res.status_code == 200 and "error" not in res.json(), res.text
    hh.members.append(user)


def test_static_code_flat_settles_as_roommates(world, db, llm):
    admin = world.signup("FlatAdminR9a")
    flat = world.create_household(admin, "Flat R9a", household_type="roommates")
    mate1, mate2 = world.signup("Mate1R9a"), world.signup("Mate2R9a")
    _static_join(world, db, mate1, flat)
    _static_join(world, db, mate2, flat)

    members = admin.api.get(f"/households/{flat.id}/members").json()
    assert members["household_type"] == "roommates"
    assert {m["financial_role"] for m in members["members"]} == {"peer"}
    assert members["nafaqah_provider_user_id"] is None

    res = world.chat_commit(admin, flat, llm, merchant="Dinner R9a", amount=300, category_code="OPEX-DINING",
                            paid_by="me", beneficiary="both")
    assert res.status_code == 200, res.text
    assert res.json().get("nafaqah_class") is None
    settlement = admin.api.get(f"/households/{flat.id}/settlement-v2").json()
    assert settlement["mode"] == "multi_roommate", settlement
    owed = {(d["from_id"], d["to_id"]): d["amount"] for d in settlement["simplified_debts"]}
    assert owed == {(mate1.id, admin.id): 100.0, (mate2.id, admin.id): 100.0}, settlement

    # A spouse invite does not fit a flat: refused when created and when claimed.
    refused = admin.api.post(f"/households/{flat.id}/invites", json={"role": "spouse"})
    assert refused.status_code == 409 and refused.json()["detail"]["code"] == "invite_role_mismatch"
    db.query("INSERT INTO public.household_invites (household_id, invite_code, role, created_by, expires_at)"
             " VALUES (%s, 'R9AWIFE1', 'spouse', %s, now() + interval '1 day')", (flat.id, admin.id))
    outsider = world.signup("OutsiderR9a")
    claim = outsider.rpc("claim_household_role_invite", {"p_invite_code": "R9AWIFE1"})
    assert claim.status_code == 200 and claim.json()["code"] == "invite_role_mismatch", claim.text
    # No Nafaqah provider in a flat.
    provider = admin.api.put(f"/households/{flat.id}/nafaqah/provider", json={"user_id": mate1.id})
    assert provider.status_code == 409 and provider.json()["detail"]["code"] == "not_family"


def test_old_app_call_shape_creates_a_family_and_admins_manage_type_and_roles(world, db):
    owner = world.signup("OwnerR9b")
    hh = world.create_household(owner, "Home R9b")  # {p_name} only, like the released app
    assert db.scalar("SELECT household_type FROM public.households WHERE id = %s", (hh.id,)) == "family"
    kid = world.signup("KidR9b")
    _static_join(world, db, kid, hh)
    assert db.scalar("SELECT financial_role FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
                     (hh.id, kid.id)) == "family_member"

    # Members cannot change the type or roles.
    assert kid.api.put(f"/households/{hh.id}/type", json={"household_type": "roommates"}).status_code == 403
    assert kid.api.put(f"/households/{hh.id}/members/{kid.id}/financial-role",
                       json={"financial_role": "dependent"}).status_code == 403

    res = owner.api.put(f"/households/{hh.id}/members/{kid.id}/financial-role", json={"financial_role": "dependent"})
    assert res.status_code == 200, res.text
    assert res.json() == {"status": "success", "household_id": hh.id, "user_id": kid.id, "financial_role": "dependent"}
    bad = owner.api.put(f"/households/{hh.id}/members/{kid.id}/financial-role", json={"financial_role": "peer"})
    assert bad.status_code == 422 and bad.json()["detail"]["code"] == "financial_role_not_allowed"
    spouse_provider = owner.api.put(f"/households/{hh.id}/members/{owner.id}/financial-role",
                                    json={"financial_role": "spouse"})
    assert spouse_provider.status_code == 409 and spouse_provider.json()["detail"]["code"] == "provider_is_spouse"

    # No wife yet: the family can become roommates (everyone a peer) and back.
    res = owner.api.put(f"/households/{hh.id}/type", json={"household_type": "roommates"})
    assert res.status_code == 200 and res.json() == {"status": "success", "household_id": hh.id, "household_type": "roommates"}
    members = owner.api.get(f"/households/{hh.id}/members").json()
    assert members["household_type"] == "roommates" and {m["financial_role"] for m in members["members"]} == {"peer"}
    res = owner.api.put(f"/households/{hh.id}/type", json={"household_type": "family"})
    assert res.status_code == 200, res.text
    members = owner.api.get(f"/households/{hh.id}/members").json()
    assert members["nafaqah_provider_user_id"] == owner.id
    roles = {m["user_id"]: m["financial_role"] for m in members["members"]}
    assert roles == {owner.id: "provider", kid.id: "family_member"}

    # With a wife, family -> roommates is refused.
    wife = world.signup("WifeR9b")
    world.join(wife, hh, world.invite(owner, hh, "spouse"))
    blocked = owner.api.put(f"/households/{hh.id}/type", json={"household_type": "roommates"})
    assert blocked.status_code == 409 and blocked.json()["detail"]["code"] == "type_change_blocked"
    # Clients cannot write the column directly.
    owner.rest.patch(f"/households?id=eq.{hh.id}", json={"household_type": "roommates"})
    assert db.scalar("SELECT household_type FROM public.households WHERE id = %s", (hh.id,)) == "family"


def test_son_cannot_classify_but_wife_and_provider_can(world, db, llm):
    family = world.family("R9c")
    husband, wife = family.admin, family.members[0]
    son = world.signup("SonR9c")
    _static_join(world, db, son, family)

    refused = world.chat_commit(son, family, llm, merchant="Bakery R9c", amount=40, category_code="OPEX-GROCERY",
                                extra_body={"nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": wife.id})
    assert refused.status_code == 403, refused.text
    assert refused.json()["detail"]["code"] == "nafaqah_classification_forbidden"

    # The app's direct write is refused by the database (D2).
    direct = son.rest.post("/transactions", json={
        "household_id": family.id, "user_id": son.id, "amount": 40, "merchant": "Direct R9c",
        "category_code": "OPEX-GROCERY", "timestamp": "2026-10-20T10:00:00+03:00",
        "nafaqah_class": "wife_reimbursable", "nafaqah_spouse_id": wife.id,
    })
    assert direct.status_code == 403 and direct.json()["hint"] == "nafaqah_class_not_allowed", direct.text

    ok = world.chat_commit(son, family, llm, merchant="Bakery plain R9c", amount=40, category_code="OPEX-GROCERY")
    assert ok.status_code == 200 and ok.json().get("nafaqah_class") is None, ok.text
    by_wife = world.chat_commit(wife, family, llm, merchant="Panda R9c", amount=120, category_code="OPEX-GROCERY",
                                paid_by="me", beneficiary="both")
    assert by_wife.json()["nafaqah_class"] == "wife_reimbursable", by_wife.text
    by_husband = world.chat_commit(husband, family, llm, merchant="Gift R9c", amount=80, category_code="OPEX-SHOPPING",
                                   paid_by="partner", beneficiary="partner")
    assert by_husband.json()["nafaqah_class"] == "wife_personal", by_husband.text


def test_wife_leaves_and_her_ledger_goes_with_her(world, db, llm):
    family = world.family("R9d")
    husband, wife = family.admin, family.members[0]
    cycle = db.scalar("SELECT cycle_key FROM public.get_saudi_cycle_for_timestamp(now(), 27)")
    db.query("INSERT INTO public.budgets (household_id, month, category_code, allocated_amount, cycle_key)"
             " VALUES (%s, (%s || '-01')::date, 'OPEX-SHOPPING', 1000, %s)", (family.id, cycle, cycle))

    adv = world.chat_commit(wife, family, llm, merchant="Panda R9d", amount=300, category_code="OPEX-GROCERY",
                            paid_by="me", beneficiary="both")
    assert adv.json()["nafaqah_class"] == "wife_reimbursable", adv.text
    personal = world.chat_commit(wife, family, llm, merchant="Abaya R9d", amount=250, category_code="OPEX-SHOPPING",
                                 paid_by="me", beneficiary="me")
    assert personal.json()["nafaqah_class"] == "wife_personal", personal.text
    assert husband.api.post(f"/households/{family.id}/nafaqah/reimbursements", json={"amount": 100}).status_code == 200
    assert husband.api.put(f"/households/{family.id}/nafaqah/allowance",
                           json={"amount": 500}).status_code == 200
    spent = db.scalar("SELECT spent_amount FROM public.budgets WHERE household_id = %s AND category_code = 'OPEX-SHOPPING'",
                      (family.id,))
    assert float(spent) == 0.0

    left = wife.rpc("leave_household")
    assert left.status_code == 200 and left.json()["success"] is True, left.text

    ids = (adv.json()["transaction_id"], personal.json()["transaction_id"])
    rows = db.query("SELECT nafaqah_class, nafaqah_spouse_id FROM public.transactions WHERE id = ANY(%s::uuid[])", (list(ids),))
    assert len(rows) == 2 and all(r["nafaqah_class"] is None and r["nafaqah_spouse_id"] is None for r in rows)
    assert db.scalar("SELECT count(*) FROM public.spouse_reimbursements WHERE household_id = %s", (family.id,)) == 0
    assert db.scalar("SELECT count(*) FROM public.member_allowances WHERE household_id = %s", (family.id,)) == 0
    spent = db.scalar("SELECT spent_amount FROM public.budgets WHERE household_id = %s AND category_code = 'OPEX-SHOPPING'",
                      (family.id,))
    assert float(spent) == 250.0  # the former personal purchase is an ordinary expense now
    summary = husband.api.get(f"/households/{family.id}/nafaqah").json()
    assert summary["mode"] == "not_family" and summary["wives"] == []
