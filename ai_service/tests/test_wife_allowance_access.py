"""
Who sees and who sets a wife's personal allowance (owner decision 2026-11-06), at the API.

Her allowance (allocated, spent, remaining for a salary cycle) is read by the wife herself (her own
only), her husband (the household's Nafaqah provider while he is a member who is not a wife) and a
household admin who is not a wife. A co-wife (even an admin) and an ordinary member read nothing
of it: no figure from GET .../allowance and no entry in the summary. It is set by whoever set it
before (the husband, an admin or not, and the household's admins), but never by a wife: a wife who
is an admin no longer sets a co-wife's.

The matrix: callers (the wife, her husband, a co-wife, an ordinary member, an admin who is not a
wife, a wife who is an admin) x (husband present and an admin, present and not an admin, gone).
The database (test 63) enforces the same; here its RPC is a stand-in and the API's own gate is
what is tested.
"""

from __future__ import annotations

from decimal import Decimal

import pytest

import nafaqah_service as ns
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
# Each wife's allocated figure for 2026-11; distinct, so a leak shows in a response's text.
ALLOCATED = {WIFE: 1111.11, COWIFE: 2222.22, WIFE_ADMIN: 3333.33}
WIVES = (WIFE, COWIFE, WIFE_ADMIN)


@pytest.fixture(params=["present-admin", "present-member", "gone"])
def household(request, family):
    """The family of test_wife_repayment_debit with a co-wife, a wife who is an admin and an
    allowance for each wife. 'present-member': the husband is not an admin. 'gone': he left the
    household (his membership ended, which clears the provider)."""
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
    family.tables.setdefault("member_allowances", []).extend([
        {"household_id": HH, "member_user_id": wife, "cycle_key": "2026-11", "amount": amount}
        for wife, amount in ALLOCATED.items()
    ])
    family.tables["transactions"].append(
        {"id": "t-personal", "household_id": HH, "amount": 44.0, "merchant": "Nahdi", "timestamp": "2026-11-10T10:00:00+00:00",
         "cycle_key": "2026-11", "nafaqah_class": "wife_personal", "nafaqah_spouse_id": WIFE})

    def set_allowance(params):
        return {"cycle_key": params["p_cycle_key"], "is_set": True, "allocated": params["p_amount"], "spent": 0,
                "transaction_count": 0}

    family.rpc_handlers["set_member_allowance"] = set_allowance
    if request.param == "present-member":
        for rows in (family.tables["household_memberships"], family.tables["users"]):
            for m in rows:
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
    """Whether ``who`` reads ``wife``'s allowance: she herself; the husband while a member; an
    admin who is not a wife."""
    if CALLERS[who] == wife:
        return True
    if who == "husband":
        return state != "gone"
    return who == "admin"


def _sets(state, who):
    """Who sets another wife's allowance: the husband (an admin or not) while a member, an admin
    who is not a wife. Never a wife, never an ordinary member."""
    if who == "husband":
        return state != "gone"
    return who == "admin"


def _calls(fake, name):
    return [p for n, p in fake.rpc_calls if n == name]


def _figure(wife):
    return f"{ALLOCATED[wife]:.2f}"


# ─── Reads ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("wife", WIVES)
def test_get_allowance_naming_her_is_answered_only_to_who_sees_it(household, who, wife):
    resp = client.get(f"/households/{HH}/nafaqah/allowance", params={"wife_user_id": wife, "cycle_key": "2026-11"},
                      headers=bearer(CALLERS[who]))
    if _sees(household.state, who, wife):
        assert resp.status_code == 200, resp.text
        assert resp.json()["allocated"] == ALLOCATED[wife]
        assert resp.json()["member_user_id"] == wife
    else:
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])
        assert _figure(wife) not in resp.text


@pytest.mark.parametrize("who", list(CALLERS))
def test_get_allowance_without_naming_her(household, who):
    """A wife gets her own; who sees every wife's must name one (several wives); anyone else is
    refused before any wife is named or looked up."""
    resp = client.get(f"/households/{HH}/nafaqah/allowance", params={"cycle_key": "2026-11"}, headers=bearer(CALLERS[who]))
    if who in ("wife", "co-wife", "wife-admin"):
        assert resp.status_code == 200, resp.text
        assert resp.json()["member_user_id"] == CALLERS[who]
    elif _sets(household.state, who):
        assert resp.status_code == 422, resp.text
    else:
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])


@pytest.mark.parametrize("who", list(CALLERS))
def test_the_summary_carries_an_allowance_only_for_who_sees_it(household, who):
    """wives[].allowance and allowance_wives[]: her own for a wife; every wife's for the husband and
    an admin who is not a wife; none for anyone else, not even a figure in the text."""
    resp = client.get(f"/households/{HH}/nafaqah", headers=bearer(CALLERS[who]))
    if who == "husband" and household.state == "gone":
        assert resp.status_code == 403, "he is no longer a member"
        return
    body = resp.json()
    shown = {w["id"] for w in body["wives"] if "allowance" in w} | {w["id"] for w in body["allowance_wives"]}
    expected = {w for w in WIVES if _sees(household.state, who, w)}
    assert shown == expected
    for wife in WIVES:
        if wife not in expected:
            assert _figure(wife) not in str(body), wife
    assert body["can_set_allowance"] is _sets(household.state, who)


# ─── Sets ─────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("wife", WIVES)
def test_put_allowance_only_by_who_sets_it_and_never_a_wife(household, who, wife):
    resp = client.put(f"/households/{HH}/nafaqah/allowance", headers=bearer(CALLERS[who]),
                      json={"wife_user_id": wife, "amount": 900, "cycle_key": "2026-11"})
    calls = _calls(household, "set_member_allowance")
    if _sets(household.state, who) and CALLERS[who] != wife:
        assert resp.status_code == 200, resp.text
        assert [c["p_member_user_id"] for c in calls] == [wife]
        assert calls[0]["p_actor_user_id"] == CALLERS[who]
    else:
        assert resp.status_code == 403, (resp.status_code, resp.text[:200])
        assert calls == []


@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("wife", WIVES)
def test_the_service_sets_only_for_who_sets_it(household, who, wife):
    """set_allowance refuses on its own, whoever calls it (not only the route, whose wife lookup
    already keeps a wife to herself): a wife who is an admin never sets a co-wife's."""
    ctx = ns.load_family_context(HH)
    caller = CALLERS[who]
    sets = _sets(household.state, who) and caller != wife
    assert ns.can_set_allowance(ctx, caller, wife) is sets
    if sets:
        assert ns.set_allowance(ctx, caller, wife, Decimal("900"), "2026-11")["allocated"] == 900.0
    else:
        with pytest.raises(ns.NafaqahForbidden):
            ns.set_allowance(ctx, caller, wife, Decimal("900"), "2026-11")
        assert _calls(household, "set_member_allowance") == []


@pytest.mark.parametrize("who", list(CALLERS))
@pytest.mark.parametrize("wife", WIVES)
def test_the_service_reads_only_for_who_sees_it(household, who, wife):
    """get_allowance with a caller refuses on its own, as the route's gate does."""
    ctx = ns.load_family_context(HH)
    caller = CALLERS[who]
    sees = _sees(household.state, who, wife) and ctx.is_member(caller)
    assert ns.can_view_allowance(ctx, caller, wife) is sees
    if sees:
        assert ns.get_allowance(ctx, wife, "2026-11", caller)["allocated"] == ALLOCATED[wife]
    else:
        with pytest.raises(ns.NafaqahForbidden):
            ns.get_allowance(ctx, wife, "2026-11", caller)


def test_a_wife_admin_is_never_one_who_sees_or_sets_allowances(household):
    ctx = ns.load_family_context(HH)
    assert not ns.can_see_allowances(ctx, WIFE_ADMIN)
    assert not ns.can_set_allowance(ctx, WIFE_ADMIN)
    assert not ns.can_see_allowances(ctx, CHILD)
    assert ns.can_see_allowances(ctx, COADMIN)
    assert ns.can_see_allowances(ctx, HUSBAND) is (household.state != "gone")


def test_a_provider_who_is_a_wife_is_never_her_husband(household):
    """A provider who is a spouse member (a broken row) is not the husband: no reads of others."""
    for h in household.tables["households"]:
        if h["id"] == HH:
            h["nafaqah_provider_user_id"] = COWIFE
    ctx = ns.load_family_context(HH)
    assert not ns.can_view_allowance(ctx, COWIFE, WIFE)
    assert not ns.can_set_allowance(ctx, COWIFE, WIFE)
