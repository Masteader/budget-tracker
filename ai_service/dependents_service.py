"""
Household Dependents Management Service.
Manages children and dependents for households, supporting both Supabase persistence
and in-memory fallback cache.
"""

from __future__ import annotations
import logging
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)

# In-memory storage cache keyed by household_id
_memory_dependents: Dict[str, List[Dict[str, Any]]] = {}


def get_household_dependents(household_id: str) -> List[Dict[str, Any]]:
    """Fetches dependents for a household."""
    from supabase_client import get_client
    try:
        client = get_client()
        res = client.table("household_dependents").select("*").eq("household_id", household_id).order("created_at").execute()
        if res.data:
            return res.data
    except Exception as exc:
        logger.debug("Falling back to local cache for household_dependents (%s)", exc)

    return _memory_dependents.get(household_id, [])


def create_household_dependent(
    household_id: str,
    name: str,
    avatar_icon: Optional[str] = "child",
    relationship: Optional[str] = "child",
    monthly_allowance: Optional[float] = 0.0,
) -> Dict[str, Any]:
    """Creates a new member/dependent for a household."""
    from supabase_client import get_client
    now_iso = datetime.now(timezone.utc).isoformat()
    record = {
        "id": str(uuid.uuid4()),
        "household_id": household_id,
        "name": name.strip(),
        "avatar_icon": avatar_icon or "child",
        "relationship": relationship or "child",
        "monthly_allowance": round(float(monthly_allowance or 0.0), 2),
        "linked_user_id": None,
        "created_at": now_iso,
    }

    try:
        client = get_client()
        res = client.table("household_dependents").insert({
            "id": record["id"],
            "household_id": record["household_id"],
            "name": record["name"],
            "avatar_icon": record["avatar_icon"],
            "relationship": record["relationship"],
            "monthly_allowance": record["monthly_allowance"],
        }).execute()
        if res.data and len(res.data) > 0:
            record = res.data[0]
    except Exception as exc:
        logger.debug("Persisting dependent to local cache (%s)", exc)

    if household_id not in _memory_dependents:
        _memory_dependents[household_id] = []
    _memory_dependents[household_id].append(record)
    return record


def delete_household_dependent(household_id: str, dependent_id: str) -> bool:
    """Deletes a dependent from a household."""
    from supabase_client import get_client
    try:
        client = get_client()
        client.table("household_dependents").delete().eq("household_id", household_id).eq("id", dependent_id).execute()
    except Exception as exc:
        logger.debug("Deleting dependent from local cache (%s)", exc)

    if household_id in _memory_dependents:
        _memory_dependents[household_id] = [
            d for d in _memory_dependents[household_id] if d.get("id") != dependent_id
        ]
    return True


def link_dependent_user(household_id: str, dependent_id: str, user_id: str) -> Optional[Dict[str, Any]]:
    """Links a pre-created member/dependent record to a live user account."""
    from supabase_client import get_client
    updated = None

    try:
        client = get_client()
        res = (
            client.table("household_dependents")
            .update({"linked_user_id": user_id})
            .eq("id", dependent_id)
            .execute()
        )
        if res.data and len(res.data) > 0:
            updated = res.data[0]
    except Exception as exc:
        logger.debug("Linking dependent user in local cache (%s)", exc)

    if household_id in _memory_dependents:
        for dep in _memory_dependents[household_id]:
            if dep.get("id") == dependent_id:
                dep["linked_user_id"] = user_id
                if not updated:
                    updated = dep
                break

    return updated
