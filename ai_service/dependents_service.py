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
        if res.data is not None:
            return res.data
    except Exception as exc:
        logger.debug("Falling back to local cache for household_dependents (%s)", exc)

    return _memory_dependents.get(household_id, [])


def create_household_dependent(
    household_id: str,
    name: str,
    avatar_icon: Optional[str] = "child"
) -> Dict[str, Any]:
    """Creates a new dependent for a household."""
    from supabase_client import get_client
    now_iso = datetime.now(timezone.utc).isoformat()
    record = {
        "id": str(uuid.uuid4()),
        "household_id": household_id,
        "name": name.strip(),
        "avatar_icon": avatar_icon or "child",
        "created_at": now_iso,
    }

    try:
        client = get_client()
        res = client.table("household_dependents").insert({
            "id": record["id"],
            "household_id": record["household_id"],
            "name": record["name"],
            "avatar_icon": record["avatar_icon"],
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
