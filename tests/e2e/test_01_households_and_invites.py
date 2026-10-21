"""Scenario 1: households are created, joined by invite code, and invite brute force is locked out."""

from __future__ import annotations


def test_stack_smoke(stack, world):
    # PostgREST is real: the service role reads the seeded system categories through it.
    assert world.anonymous_api().get("/health").status_code == 200
    user = world.signup("Smoke")
    res = user.rest.get("/users", params={"select": "id,display_name"})
    assert res.status_code == 200
    assert res.json() == [{"id": user.id, "display_name": "Smoke"}]  # RLS: own row only


def test_family_household_join_via_spouse_invite(world, db):
    hh = world.family("F1")
    husband, wife = hh.admin, hh.members[0]

    members = husband.api.get(f"/households/{hh.id}/members")
    assert members.status_code == 200, members.text
    body = members.json()
    assert body["primary_admin_user_id"] == husband.id
    roles = {m["user_id"]: (m["role"], m["financial_role"]) for m in body["members"]}
    assert roles == {husband.id: ("admin", "provider"), wife.id: ("member", "spouse")}

    # The wife sees the same household; her active household switched to it.
    assert db.scalar("SELECT household_id::text FROM public.users WHERE id = %s", (wife.id,)) == hh.id
    wife_view = wife.api.get(f"/households/{hh.id}/members")
    assert wife_view.status_code == 200
    assert wife_view.json()["caller_role"] == "member"

    # The family is recognised as a Nafaqah household.
    summary = wife.api.get(f"/households/{hh.id}/nafaqah")
    assert summary.status_code == 200, summary.text


def test_roommate_household_join_and_invite_single_use(world, db):
    hh = world.roommates("R1", n_members=2)
    admin = hh.admin
    body = admin.api.get(f"/households/{hh.id}/members").json()
    assert {m["user_id"] for m in body["members"]} == {u.id for u in hh.everyone}
    assert sorted(m["role"] for m in body["members"]) == ["admin", "member", "member"]
    assert {m["financial_role"] for m in body["members"] if m["role"] == "member"} == {"peer"}

    # Invite metadata is public but minimal; a used code is invalid and cannot be re-claimed.
    code = world.invite(admin, hh, "peer")
    info = world.anonymous_api().get(f"/households/invites/{code}")
    assert info.status_code == 200
    assert info.json()["is_valid"] is True and "household_id" not in info.json()
    joiner = world.signup("LateMate")
    world.join(joiner, hh, code)
    assert world.anonymous_api().get(f"/households/invites/{code}").json()["is_valid"] is False
    other = world.signup("Squatter")
    again = other.api.post(f"/households/invites/{code}/claim")
    assert again.status_code == 400

    # Only an admin may mint invites.
    member = hh.members[0]
    assert member.api.post(f"/households/{hh.id}/invites", json={"role": "peer"}).status_code == 403


def test_invite_brute_force_lockout_returns_429(world, db):
    hh = world.roommates("R2", n_members=0)
    attacker = world.signup("Guesser")
    statuses = [attacker.api.post(f"/households/invites/WRONG{i:011d}/claim").status_code for i in range(5)]
    assert statuses == [400] * 5
    locked = attacker.api.post(f"/households/invites/WRONG99999999999/claim")
    assert locked.status_code == 429, locked.text
    assert locked.headers.get("Retry-After") == "900"

    # Even the correct code is refused while locked out.
    good = world.invite(hh.admin, hh, "peer")
    assert attacker.api.post(f"/households/invites/{good}/claim").status_code == 429
    assert db.scalar(
        "SELECT count(*) FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
        (hh.id, attacker.id),
    ) == 0

    # The same lockout guards the direct PostgREST join RPC used by the app.
    direct = attacker.rpc("join_household_by_code", {"p_invite_code": good})
    assert direct.status_code >= 400
    assert db.scalar(
        "SELECT count(*) FROM public.household_memberships WHERE household_id = %s AND user_id = %s",
        (hh.id, attacker.id),
    ) == 0


def test_forged_expired_and_wrong_role_tokens_are_rejected(world, stack):
    import httpx
    from jose import jwt as jose_jwt

    from e2e_harness.tokens import service_role_key, user_token

    hh = world.roommates("T1", n_members=0)
    user = hh.admin
    forged = jose_jwt.encode(jose_jwt.get_unverified_claims(user.token), "not-the-secret", algorithm="HS256")
    expired = user_token(stack.gateway.url, user.id, user.email, ttl=-3600)
    wrong_iss = user_token("https://evil.example", user.id, user.email)
    for token in (forged, expired, wrong_iss, service_role_key()):
        api = world.anonymous_api(Authorization=f"Bearer {token}")
        assert api.get(f"/households/{hh.id}/members").status_code == 401
    # PostgREST verifies the same secret: a forged token never reaches the database as the user.
    res = httpx.get(f"{stack.gateway.url}/rest/v1/households", headers={"Authorization": f"Bearer {forged}"},
                    trust_env=False)
    assert res.status_code == 401
