"""
Helpers that behave the same across the postgrest-py versions ``supabase>=2.5.0`` allows.

* ``first_row``: ``.maybe_single()`` returns ``None`` for zero rows only in recent releases
  (2.x). postgrest-py 0.14-1.0 return ``None`` only when PostgREST's error detail text is exactly
  "The result contains 0 rows"; otherwise, and for every other error (a missing column, a
  permission error), they raise ``APIError(code="204", message="Missing response")``, which
  hides the real cause. ``.limit(1).execute()`` returns a plain list in every version.
* ``db_error_fields``: ``postgrest.exceptions.APIError`` exposes ``code`` / ``message`` /
  ``hint`` / ``details`` attributes (verified for 0.14 through 2.33), but ``str(exc)`` is the
  ``repr`` of the error dict and wrapped or re-raised errors carry only that string or the dict
  itself. This reads the fields from whichever shape arrives.
"""

from __future__ import annotations

import ast
import json
from typing import Any, Dict, Optional

_FIELDS = ("code", "message", "hint", "details")


def first_row(query: Any) -> Optional[Dict[str, Any]]:
    """Execute ``query`` limited to one row; the row as a dict, or None when there is none."""
    res = query.limit(1).execute()
    data = getattr(res, "data", None) if res is not None else None
    if isinstance(data, list):
        return data[0] if data and isinstance(data[0], dict) else None
    return data if isinstance(data, dict) else None


def _as_error_dict(value: Any) -> Optional[Dict[str, Any]]:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str):
        return None
    text = value.strip()
    if not (text.startswith("{") and text.endswith("}")):
        return None
    for parse in (json.loads, ast.literal_eval):
        try:
            parsed = parse(text)
        except (ValueError, SyntaxError, TypeError, MemoryError, RecursionError):
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


def db_error_fields(exc: BaseException) -> Dict[str, str]:
    """``{"code", "message", "hint", "details"}`` of a database error, '' when absent."""
    found: Dict[str, Any] = {f: getattr(exc, f, None) for f in _FIELDS}
    if not all(found[f] for f in ("code", "message")):
        candidates = list(getattr(exc, "args", ()) or ())
        to_json = getattr(exc, "json", None)
        if callable(to_json):
            try:
                candidates.insert(0, to_json())
            except Exception:  # noqa: BLE001 - best effort; the other shapes still apply
                pass
        candidates.append(str(exc))
        for candidate in candidates:
            parsed = _as_error_dict(candidate)
            if parsed:
                for f in _FIELDS:
                    if not found[f] and parsed.get(f) is not None:
                        found[f] = parsed.get(f)
                break
    fields = {f: str(found[f]) if found[f] is not None else "" for f in _FIELDS}
    if not fields["message"]:
        fields["message"] = str(exc)
    return fields
