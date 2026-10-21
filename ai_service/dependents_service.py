"""
Household Dependents Management Service.

Children and other members without an account (``household_dependents``). The database is the
only store (product review 4.1): the in-memory fallback cache diverged between API instances and
vanished on restart, so a failed read or write now raises DependentsUnavailable instead of
answering from (or "saving" to) process memory.
"""

from __future__ import annotations
import logging
import uuid
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)


class DependentsUnavailable(RuntimeError):
    """household_dependents could not be read or written (database unreachable or refused)."""

    PUBLIC_MESSAGE = "Household members are temporarily unavailable. Please try again."

    def __init__(self, operation: str):
        super().__init__(f"{self.PUBLIC_MESSAGE} ({operation})")
        self.operation = operation


def get_household_dependents(household_id: str) -> List[Dict[str, Any]]:
    """The dependents of a household, oldest first."""
    from supabase_client import get_client
    try:
        res = (
            get_client().table("household_dependents").select("*").eq("household_id", household_id)
            .order("created_at").execute()
        )
    except Exception as exc:
        logger.error("Could not read household_dependents for %s: %s", household_id, exc)
        raise DependentsUnavailable("read") from exc
    return list(res.data or [])


def create_household_dependent(
    household_id: str,
    name: str,
    avatar_icon: Optional[str] = "child",
    relationship: Optional[str] = "child",
    monthly_allowance: Optional[float] = 0.0,
) -> Dict[str, Any]:
    """Creates a new member/dependent for a household and returns the stored row."""
    from supabase_client import get_client
    record = {
        "id": str(uuid.uuid4()),
        "household_id": household_id,
        "name": name.strip(),
        "avatar_icon": avatar_icon or "child",
        "relationship": relationship or "child",
        "monthly_allowance": round(float(monthly_allowance or 0.0), 2),
    }
    try:
        res = get_client().table("household_dependents").insert(record).execute()
    except Exception as exc:
        logger.error("Could not insert a household_dependents row for %s: %s", household_id, exc)
        raise DependentsUnavailable("create") from exc
    if res.data:
        return res.data[0]
    return {**record, "linked_user_id": None}


def delete_household_dependent(household_id: str, dependent_id: str) -> bool:
    """Deletes a dependent from a household."""
    from supabase_client import get_client
    try:
        get_client().table("household_dependents").delete().eq("household_id", household_id).eq(
            "id", dependent_id
        ).execute()
    except Exception as exc:
        logger.error("Could not delete household_dependents %s: %s", dependent_id, exc)
        raise DependentsUnavailable("delete") from exc
    return True


def link_dependent_user(household_id: str, dependent_id: str, user_id: str) -> Optional[Dict[str, Any]]:
    """Links a pre-created member/dependent record of ``household_id`` to a live user account."""
    from supabase_client import get_client
    try:
        res = (
            get_client().table("household_dependents")
            .update({"linked_user_id": user_id})
            .eq("id", dependent_id)
            .eq("household_id", household_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Could not link household_dependents %s: %s", dependent_id, exc)
        raise DependentsUnavailable("link") from exc
    return res.data[0] if res.data else None
