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

4. The household type ('family' | 'roommates', owner decision D1, migration
   ``20261020900000``) is chosen at creation; an admin changes it (``set_household_type``) and sets
   members' financial roles within it (``set_member_financial_role``: family -> spouse,
   family_member, dependent; roommates -> peer). Role invites must fit the type.

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


class HouseholdConflictError(HouseholdPermissionError):
    """A refused change with a machine-readable ``code`` (HTTP 409 ``{code, message}``)."""

    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


class InvalidFinancialRoleError(HouseholdPermissionError):
    """A financial role (or household type) that does not exist or does not fit (HTTP 422)."""

    code = "financial_role_not_allowed"

    def __init__(self, message: str, code: Optional[str] = None):
        super().__init__(message)
        if code:
            self.code = code


FAMILY = "family"
ROOMMATES = "roommates"
HOUSEHOLD_TYPES = (FAMILY, ROOMMATES)
FINANCIAL_ROLES = ("provider", "spouse", "peer", "family_member", "dependent")
# Roles an admin may assign with set_member_financial_role (the provider is chosen separately).
ASSIGNABLE_FINANCIAL_ROLES = {FAMILY: ("spouse", "family_member", "dependent"), ROOMMATES: ("peer",)}
# Roles a membership (and so a role invite) may hold in each household type.
MEMBERSHIP_FINANCIAL_ROLES = {FAMILY: ("provider", "spouse", "family_member", "dependent"), ROOMMATES: ("peer",)}

TYPE_CHANGE_BLOCKED = "type_change_blocked"
INVITE_ROLE_MISMATCH = "invite_role_mismatch"


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
    household_type: str = FAMILY

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


def household_type_of(client, household_id: str, financial_roles=()) -> str:
    """
    households.household_type ('family' | 'roommates'); before the column exists (or on a read
    error) the migration's backfill rule: any peer member -> roommates, else family.
    """
    from nafaqah_service import normalize_household_type

    try:
        row = first_row(client.table("households").select("household_type").eq("id", household_id))
    except Exception as exc:
        logger.warning("Could not read households.household_type: %s", exc)
        row = None
    return normalize_household_type((row or {}).get("household_type"), financial_roles)


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
    roster.household_type = household_type_of(
        client, household_id, [m.get("financial_role") for m in roster.members.values()]
    )
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
        # 'family' | 'roommates' (D1); admins change it (PUT /households/{id}/type) and set
        # financial roles within it (PUT /households/{id}/members/{user_id}/financial-role).
        "household_type": roster.household_type,
        "can_change_household_type": caller_is_admin,
        "can_set_financial_roles": caller_is_admin,
        "assignable_financial_roles": list(ASSIGNABLE_FINANCIAL_ROLES[roster.household_type]),
        "primary_admin_user_id": roster.primary_admin_id,
        "caller_role": roster.role_of(caller_id),
        "caller_is_primary": roster.is_primary(caller_id),
        "can_manage_admins": caller_is_admin,
        "can_transfer_primary": roster.is_primary(caller_id),
        # The Nafaqah provider (husband) is a separate role from the primary admin; any admin
        # changes it (PUT /households/{id}/nafaqah/provider) to a non-spouse member.
        "nafaqah_provider_user_id": roster.nafaqah_provider_id,
        "can_set_nafaqah_provider": caller_is_admin and roster.household_type == FAMILY,
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


# ─── Household type and financial roles (owner decision D1, FABLE2-DB-07) ─────

def _rpc_hint(exc: Exception) -> str:
    return db_error_fields(exc)["hint"]


def set_household_type(household_id: str, actor_id: str, household_type: str) -> Dict[str, Any]:
    """
    An admin switches the household between 'family' and 'roommates' (public.set_household_type
    re-checks with the verified caller). family -> roommates is refused while a wife or any
    Nafaqah record exists (HouseholdConflictError ``type_change_blocked``); roommates -> family
    turns peers into family members and the primary admin into the default Nafaqah provider.
    """
    roster = load_roster(household_id)
    _require_admin(roster, actor_id)
    wanted = str(household_type or "").strip().lower()
    if wanted not in HOUSEHOLD_TYPES:
        raise InvalidFinancialRoleError("household_type must be 'family' or 'roommates'.", "invalid_household_type")
    try:
        res = supabase_client.get_client().rpc(
            "set_household_type",
            {"p_household_id": household_id, "p_household_type": wanted, "p_actor_user_id": actor_id},
        ).execute()
    except Exception as exc:
        if _rpc_hint(exc) == TYPE_CHANGE_BLOCKED:
            raise HouseholdConflictError(
                "A family household with a wife or Nafaqah records cannot become a roommates household.",
                TYPE_CHANGE_BLOCKED,
            ) from exc
        mapped = _map_rpc_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc
    data = getattr(res, "data", None)
    data = data if isinstance(data, dict) else {}
    return {
        "status": "success",
        "household_id": household_id,
        "household_type": data.get("household_type") or wanted,
    }


def set_member_financial_role(household_id: str, actor_id: str, target_id: str, financial_role: str) -> Dict[str, Any]:
    """
    An admin sets a member's financial role within the household type (family: spouse,
    family_member, dependent; roommates: peer) through public.set_member_financial_role.
    403 not an admin, 404 not a member, 422 role not available here, 409 the Nafaqah provider
    as a spouse (``provider_is_spouse``) or a wife with ledger records (``spouse_has_ledger``).
    """
    roster = load_roster(household_id)
    _require_admin(roster, actor_id)
    _require_target(roster, target_id)
    role = str(financial_role or "").strip().lower()
    if role not in ASSIGNABLE_FINANCIAL_ROLES[roster.household_type]:
        raise InvalidFinancialRoleError(
            f"Financial role {role!r} is not available in a {roster.household_type} household."
        )
    if role == "spouse" and roster.nafaqah_provider_id and str(target_id) == roster.nafaqah_provider_id:
        raise HouseholdConflictError("The Nafaqah provider cannot be a spouse member.", "provider_is_spouse")
    try:
        res = supabase_client.get_client().rpc(
            "set_member_financial_role",
            {
                "p_household_id": household_id,
                "p_user_id": target_id,
                "p_financial_role": role,
                "p_actor_user_id": actor_id,
            },
        ).execute()
    except Exception as exc:
        hint = _rpc_hint(exc)
        if hint == "financial_role_not_allowed":
            raise InvalidFinancialRoleError(
                f"Financial role {role!r} is not available in this household."
            ) from exc
        if hint == "provider_is_spouse":
            raise HouseholdConflictError("The Nafaqah provider cannot be a spouse member.", hint) from exc
        if hint == "spouse_has_ledger":
            raise HouseholdConflictError(
                "This wife has Nafaqah records in the household; her role cannot change.", hint
            ) from exc
        mapped = _map_rpc_error(exc)
        if mapped is exc:
            raise
        raise mapped from exc
    data = getattr(res, "data", None)
    data = data if isinstance(data, dict) else {}
    return {
        "status": "success",
        "household_id": household_id,
        "user_id": str(target_id),
        "financial_role": data.get("financial_role") or role,
    }


def assert_invite_role_fits(household_id: str, role: str) -> None:
    """
    A role invite must fit the household type (D1): no spouse/provider/family invite in a
    roommates household, no peer invite in a family household. The claim RPCs refuse a mismatch
    too (an invite issued before a type change); this gives the admin a clear answer up front.
    """
    client = supabase_client.get_client()
    household_type = household_type_of(client, household_id)
    norm = str(role or "").strip().lower()
    if norm in FINANCIAL_ROLES and norm not in MEMBERSHIP_FINANCIAL_ROLES[household_type]:
        raise HouseholdConflictError(
            f"A {norm!r} invite does not fit a {household_type} household.", INVITE_ROLE_MISMATCH
        )
