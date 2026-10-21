"""
Household roles and permissions (owner decision on audit items DB-16 and DB-18).

Applies to family and roommate households alike:

1. A member creates transactions and edits or deletes only their own. Only a household admin
   edits or deletes another member's transaction. The creator (``transactions.user_id``) is the
   verified JWT subject at insert and never changes.
2. Only a household admin moves money out of a shared pool (enforced by
   ``transfer_between_accounts`` in the database; the app hides the option for members).
3. An admin promotes members to admin ("co-admins") and revokes that. The primary admin
   (``households.owner_user_id``) cannot be demoted or removed by a co-admin, and only the
   primary admin transfers primary ownership. The last admin of a household is never demoted.

The service role bypasses RLS, so every check here is explicit and uses the verified JWT user.
Role changes then go through the SECURITY DEFINER RPCs of migration
``20261020400000_admin_permissions_and_co_admins.sql`` with that user as ``p_actor_user_id``, so
the database re-checks every rule.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import supabase_client
from postgrest_compat import db_error_fields, first_row

logger = logging.getLogger(__name__)

ADMIN = "admin"
MEMBER = "member"


class HouseholdPermissionError(Exception):
    """Base class for role and permission rule violations."""


class PermissionDeniedError(HouseholdPermissionError):
    """The caller may not perform this action in this household (HTTP 403)."""


class MemberNotFoundError(HouseholdPermissionError):
    """The target user is not a member of this household (HTTP 404)."""


class TransactionNotFoundError(HouseholdPermissionError):
    """No such transaction in this household (HTTP 404)."""


class InvalidRoleChangeError(HouseholdPermissionError):
    """The change would break an invariant, e.g. demote the last admin (HTTP 409)."""


TRANSACTION_FORBIDDEN = "Only household admins can edit or delete another member's transactions."
PRIMARY_PROTECTED = "The primary admin cannot be demoted; the primary admin must transfer primary admin first."
PRIMARY_ONLY_TRANSFER = "Only the primary admin can transfer primary admin."


# ─── Pure rules ───────────────────────────────────────────────────────────────

def can_modify_transaction(actor_id: Optional[str], actor_role: Optional[str], creator_id: Optional[str]) -> bool:
    """A member edits/deletes their own transactions; an admin any transaction of the household."""
    if not actor_id or actor_role not in (ADMIN, MEMBER):
        return False
    if actor_role == ADMIN:
        return True
    return creator_id is not None and str(creator_id) == str(actor_id)


def can_record_settlement(
    actor_id: Optional[str], actor_role: Optional[str], payer_id: Optional[str], recipient_id: Optional[str]
) -> bool:
    """A settlement names who paid whom: either party records it, or an admin for anyone."""
    if not actor_id or actor_role not in (ADMIN, MEMBER):
        return False
    return actor_role == ADMIN or str(actor_id) in (str(payer_id), str(recipient_id))


# ─── Roster ───────────────────────────────────────────────────────────────────

@dataclass
class HouseholdRoster:
    household_id: str
    primary_admin_id: Optional[str] = None
    members: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    nafaqah_provider_id: Optional[str] = None

    def role_of(self, user_id: Optional[str]) -> Optional[str]:
        member = self.members.get(str(user_id or ""))
        return member["role"] if member else None

    def is_member(self, user_id: Optional[str]) -> bool:
        return str(user_id or "") in self.members

    def is_admin(self, user_id: Optional[str]) -> bool:
        return self.role_of(user_id) == ADMIN

    def is_primary(self, user_id: Optional[str]) -> bool:
        return bool(user_id) and self.primary_admin_id == str(user_id)

    def admin_ids(self) -> List[str]:
        return [uid for uid, m in self.members.items() if m["role"] == ADMIN]


def household_owner_id(client, household_id: str) -> Optional[str]:
    """households.owner_user_id (the primary admin), or None when unset or not migrated yet."""
    try:
        row = first_row(client.table("households").select("owner_user_id").eq("id", household_id))
    except Exception as exc:  # column not migrated yet: derive it like the migration backfill
        logger.warning("Could not read households.owner_user_id: %s", exc)
        return None
    owner = row.get("owner_user_id") if row else None
    return str(owner) if owner else None


def household_nafaqah_provider_id(client, household_id: str) -> Optional[str]:
    """
    households.nafaqah_provider_user_id (the explicit Nafaqah provider), or None when unset. Only
    the members list (display) uses this helper; Nafaqah rules read it in load_family_context,
    where a failure propagates.
    """
    try:
        row = first_row(client.table("households").select("nafaqah_provider_user_id").eq("id", household_id))
    except Exception as exc:
        logger.warning("Could not read households.nafaqah_provider_user_id: %s", exc)
        return None
    provider = row.get("nafaqah_provider_user_id") if row else None
    return str(provider) if provider else None


def load_roster(household_id: str) -> HouseholdRoster:
    """Members (household_memberships is authoritative), their roles and the primary admin."""
    client = supabase_client.get_client()
    memberships = (
        client.table("household_memberships")
        .select("user_id, role, created_at, financial_role")
        .eq("household_id", household_id)
        .execute()
    ).data or []
    user_ids = [str(m["user_id"]) for m in memberships if m.get("user_id")]
    users: Dict[str, Dict[str, Any]] = {}
    if user_ids:
        rows = (
            client.table("users")
            .select("id, display_name")
            .in_("id", user_ids)
            .execute()
        ).data or []
        users = {str(u["id"]): u for u in rows if u.get("id")}

    roster = HouseholdRoster(household_id=household_id)
    for m in memberships:
        uid = str(m.get("user_id") or "")
        if not uid:
            continue
        user = users.get(uid, {})
        roster.members[uid] = {
            "user_id": uid,
            "role": ADMIN if m.get("role") == ADMIN else MEMBER,
            "joined_at": str(m.get("created_at") or ""),
            "display_name": user.get("display_name"),
            # The role in THIS household (FABLE-LOGIC-01), not the per-user cache.
            "financial_role": m.get("financial_role"),
        }

    roster.nafaqah_provider_id = household_nafaqah_provider_id(client, household_id)
    owner = household_owner_id(client, household_id)
    if owner and roster.is_admin(owner):
        roster.primary_admin_id = owner
    else:
        admins = sorted(
            (m for m in roster.members.values() if m["role"] == ADMIN),
            key=lambda m: (m["joined_at"], m["user_id"]),
        )
        roster.primary_admin_id = admins[0]["user_id"] if admins else None
    return roster


def _require_member(roster: HouseholdRoster, user_id: str) -> None:
    if not roster.is_member(user_id):
        raise PermissionDeniedError("Not a member of this household.")


def _require_admin(roster: HouseholdRoster, user_id: str) -> None:
    _require_member(roster, user_id)
    if not roster.is_admin(user_id):
        raise PermissionDeniedError("Household admin privileges are required.")


def _require_target(roster: HouseholdRoster, user_id: str) -> None:
    if not roster.is_member(user_id):
        raise MemberNotFoundError("That user is not a member of this household.")


# ─── Transactions ─────────────────────────────────────────────────────────────

def member_role(household_id: str, user_id: str) -> Optional[str]:
    row = first_row(
        supabase_client.get_client()
        .table("household_memberships")
        .select("role")
        .eq("household_id", household_id)
        .eq("user_id", user_id)
    )
    if not row:
        return None
    return ADMIN if row.get("role") == ADMIN else MEMBER


def assert_can_modify_transaction(household_id: str, transaction_id: str, actor_user_id: Optional[str]) -> Dict[str, Any]:
    """
    Load ``transaction_id`` inside ``household_id`` and check the actor may edit or delete it.
    Raises TransactionNotFoundError (not in this household) or PermissionDeniedError.
    """
    if not actor_user_id:
        raise PermissionDeniedError(TRANSACTION_FORBIDDEN)
    tx = first_row(
        supabase_client.get_client()
        .table("transactions")
        .select("id, household_id, user_id")
        .eq("id", transaction_id)
        .eq("household_id", household_id)
    )
    if not tx:
        raise TransactionNotFoundError("Transaction not found in this household.")
    role = member_role(household_id, actor_user_id)
    if not can_modify_transaction(actor_user_id, role, tx.get("user_id")):
        raise PermissionDeniedError(TRANSACTION_FORBIDDEN)
    return tx


# ─── Role management ──────────────────────────────────────────────────────────

def _member_view(roster: HouseholdRoster, member: Dict[str, Any], caller_id: str) -> Dict[str, Any]:
    uid = member["user_id"]
    return {
        "user_id": uid,
        "display_name": member.get("display_name"),
        "role": member["role"],
        "financial_role": member.get("financial_role"),
        "is_primary": roster.is_primary(uid),
        "is_nafaqah_provider": bool(roster.nafaqah_provider_id) and uid == roster.nafaqah_provider_id,
        "is_self": uid == str(caller_id),
        "joined_at": member.get("joined_at") or None,
    }


def list_members(household_id: str, caller_id: str) -> Dict[str, Any]:
    """Members with roles, primary admin first, plus what the caller may change."""
    roster = load_roster(household_id)
    _require_member(roster, caller_id)
    ordered = sorted(
        roster.members.values(),
        key=lambda m: (not roster.is_primary(m["user_id"]), m["role"] != ADMIN, m["joined_at"], m["user_id"]),
    )
    caller_is_admin = roster.is_admin(caller_id)
    return {
        "household_id": household_id,
        "primary_admin_user_id": roster.primary_admin_id,
        "caller_role": roster.role_of(caller_id),
        "caller_is_primary": roster.is_primary(caller_id),
        "can_manage_admins": caller_is_admin,
        "can_transfer_primary": roster.is_primary(caller_id),
        # The Nafaqah provider (husband) is a separate role from the primary admin; any admin
        # changes it (PUT /households/{id}/nafaqah/provider) to a non-spouse member.
        "nafaqah_provider_user_id": roster.nafaqah_provider_id,
        "can_set_nafaqah_provider": caller_is_admin,
        "members": [_member_view(roster, m, caller_id) for m in ordered],
    }


def _map_rpc_error(exc: Exception) -> Exception:
    fields = db_error_fields(exc)
    message, code = fields["message"], fields["code"]
    if "sole admin" in message.lower():
        return InvalidRoleChangeError("A household needs at least one admin.")
    if code == "42501" or message.startswith("Forbidden") or "primary admin" in message.lower():
        return PermissionDeniedError("Not allowed for this household member.")
    if code == "P0002" or "not a member" in message.lower():
        return MemberNotFoundError("That user is not a member of this household.")
    if code in ("22023", "23514"):
        return InvalidRoleChangeError("The database rejected the role change.")
    return exc


def _call_role_rpc(name: str, params: Dict[str, Any]) -> Any:
    try:
        res = supabase_client.get_client().rpc(name, params).execute()
    except Exception as exc:
        mapped = _map_rpc_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc
    return getattr(res, "data", None)


def promote_member(household_id: str, actor_id: str, target_id: str) -> Dict[str, Any]:
    """Any admin (primary or co-admin) makes another member an admin."""
    roster = load_roster(household_id)
    _require_admin(roster, actor_id)
    _require_target(roster, target_id)
    if not roster.is_admin(target_id):
        _call_role_rpc(
            "promote_member_to_admin",
            {"p_household_id": household_id, "p_user_id": target_id, "p_actor_user_id": actor_id},
        )
    return list_members(household_id, actor_id)


def revoke_admin(household_id: str, actor_id: str, target_id: str) -> Dict[str, Any]:
    """Any admin revokes a co-admin (themselves included); never the primary admin or the last admin."""
    roster = load_roster(household_id)
    _require_admin(roster, actor_id)
    _require_target(roster, target_id)
    if roster.is_primary(target_id):
        raise PermissionDeniedError(PRIMARY_PROTECTED)
    if roster.is_admin(target_id):
        if roster.admin_ids() == [str(target_id)]:
            raise InvalidRoleChangeError("A household needs at least one admin.")
        _call_role_rpc(
            "revoke_admin",
            {"p_household_id": household_id, "p_user_id": target_id, "p_actor_user_id": actor_id},
        )
    return list_members(household_id, actor_id)


def transfer_primary_admin(household_id: str, actor_id: str, new_primary_id: str) -> Dict[str, Any]:
    """Only the primary admin hands primary ownership to another member (made an admin if needed)."""
    roster = load_roster(household_id)
    _require_admin(roster, actor_id)
    if not roster.is_primary(actor_id):
        raise PermissionDeniedError(PRIMARY_ONLY_TRANSFER)
    _require_target(roster, new_primary_id)
    if str(new_primary_id) == str(actor_id):
        raise InvalidRoleChangeError("Choose another member of this household.")
    _call_role_rpc(
        "transfer_primary_admin",
        {"p_household_id": household_id, "p_new_primary_user_id": new_primary_id, "p_actor_user_id": actor_id},
    )
    return list_members(household_id, actor_id)
