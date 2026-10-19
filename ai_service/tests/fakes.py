"""
In-memory fake of the supabase-py client used by the hermetic test suite.

The real client talks to the network; tests must never do that (they previously
reached whatever SUPABASE_URL a developer's .env pointed at, i.e. production).
The fake implements just the PostgREST query-builder surface the service uses:
select / eq / neq / in_ / gt / gte / lt / lte / is_ / contains / order / limit /
single / maybe_single / insert / update / upsert / delete / execute, plus rpc()
and storage.from_(bucket).upload().
"""

from __future__ import annotations

import copy
import uuid
from typing import Any, Callable, Dict, List, Optional


class FakeResponse:
    def __init__(self, data: Any = None, count: Optional[int] = None):
        self.data = data
        self.count = count


class FakeQuery:
    def __init__(self, client: "FakeSupabaseClient", table: str):
        self._client = client
        self._table = table
        self._op = "select"
        self._payload: Any = None
        self._filters: List[Callable[[dict], bool]] = []
        self._order: Optional[tuple[str, bool]] = None
        self._limit: Optional[int] = None
        self._single = False
        self._maybe_single = False
        self._on_conflict: Optional[str] = None

    # ── verbs ──────────────────────────────────────────────────────────────
    def select(self, *_cols: str, **_kw: Any) -> "FakeQuery":
        self._op = "select"
        return self

    def insert(self, payload: Any, **_kw: Any) -> "FakeQuery":
        self._op = "insert"
        self._payload = payload
        return self

    def update(self, payload: dict, **_kw: Any) -> "FakeQuery":
        self._op = "update"
        self._payload = payload
        return self

    def upsert(self, payload: Any, on_conflict: Optional[str] = None, **_kw: Any) -> "FakeQuery":
        self._op = "upsert"
        self._payload = payload
        self._on_conflict = on_conflict
        return self

    def delete(self, **_kw: Any) -> "FakeQuery":
        self._op = "delete"
        return self

    # ── filters ────────────────────────────────────────────────────────────
    def eq(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) == val)
        return self

    def neq(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) != val)
        return self

    def in_(self, col: str, vals: list) -> "FakeQuery":
        allowed = list(vals)
        self._filters.append(lambda r: r.get(col) in allowed)
        return self

    def gt(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) is not None and r.get(col) > val)
        return self

    def gte(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) is not None and r.get(col) >= val)
        return self

    def lt(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) is not None and r.get(col) < val)
        return self

    def lte(self, col: str, val: Any) -> "FakeQuery":
        self._filters.append(lambda r: r.get(col) is not None and r.get(col) <= val)
        return self

    def is_(self, col: str, val: Any) -> "FakeQuery":
        target = None if val in (None, "null") else val
        self._filters.append(lambda r: r.get(col) is target)
        return self

    def contains(self, col: str, vals: Any) -> "FakeQuery":
        self._filters.append(lambda r: all(v in (r.get(col) or []) for v in vals))
        return self

    def order(self, col: str, desc: bool = False, **_kw: Any) -> "FakeQuery":
        self._order = (col, desc)
        return self

    def limit(self, n: int) -> "FakeQuery":
        self._limit = n
        return self

    def single(self) -> "FakeQuery":
        self._single = True
        return self

    def maybe_single(self) -> "FakeQuery":
        self._maybe_single = True
        return self

    # ── execution ──────────────────────────────────────────────────────────
    def _matches(self, row: dict) -> bool:
        return all(f(row) for f in self._filters)

    def execute(self) -> FakeResponse:
        rows = self._client.tables.setdefault(self._table, [])
        if self._op == "insert":
            items = self._payload if isinstance(self._payload, list) else [self._payload]
            inserted = []
            for item in items:
                row = copy.deepcopy(item)
                row.setdefault("id", str(uuid.uuid4()))
                rows.append(row)
                inserted.append(copy.deepcopy(row))
            return FakeResponse(inserted)
        if self._op == "upsert":
            items = self._payload if isinstance(self._payload, list) else [self._payload]
            keys = [k.strip() for k in (self._on_conflict or "id").split(",")]
            out = []
            for item in items:
                existing = next((r for r in rows if all(r.get(k) == item.get(k) for k in keys)), None)
                if existing is not None:
                    existing.update(copy.deepcopy(item))
                    out.append(copy.deepcopy(existing))
                else:
                    row = copy.deepcopy(item)
                    row.setdefault("id", str(uuid.uuid4()))
                    rows.append(row)
                    out.append(copy.deepcopy(row))
            return FakeResponse(out)
        matched = [r for r in rows if self._matches(r)]
        if self._op == "update":
            for r in matched:
                r.update(copy.deepcopy(self._payload))
            return FakeResponse([copy.deepcopy(r) for r in matched])
        if self._op == "delete":
            self._client.tables[self._table] = [r for r in rows if not self._matches(r)]
            return FakeResponse([copy.deepcopy(r) for r in matched])

        result = [copy.deepcopy(r) for r in matched]
        if self._order:
            col, desc = self._order
            result.sort(key=lambda r: (r.get(col) is None, r.get(col)), reverse=desc)
        if self._limit is not None:
            result = result[: self._limit]
        if self._single:
            if len(result) != 1:
                raise RuntimeError(f"single() expected exactly one row from {self._table}, got {len(result)}")
            return FakeResponse(result[0])
        if self._maybe_single:
            return FakeResponse(result[0] if result else None)
        return FakeResponse(result)


class FakeRpc:
    def __init__(self, client: "FakeSupabaseClient", name: str, params: dict):
        self._client = client
        self._name = name
        self._params = params

    def execute(self) -> FakeResponse:
        self._client.rpc_calls.append((self._name, dict(self._params)))
        handler = self._client.rpc_handlers.get(self._name)
        if handler is None:
            return FakeResponse(None)
        return FakeResponse(handler(self._params))


class FakeBucket:
    def __init__(self, client: "FakeSupabaseClient", bucket: str):
        self._client = client
        self._bucket = bucket

    def upload(self, path: str, data: bytes, file_options: Optional[dict] = None) -> dict:
        self._client.storage_objects[(self._bucket, path)] = data
        return {"Key": f"{self._bucket}/{path}"}


class FakeStorage:
    def __init__(self, client: "FakeSupabaseClient"):
        self._client = client

    def from_(self, bucket: str) -> FakeBucket:
        return FakeBucket(self._client, bucket)


class FakeSupabaseClient:
    def __init__(self) -> None:
        self.tables: Dict[str, List[dict]] = {}
        self.rpc_handlers: Dict[str, Callable[[dict], Any]] = {"consume_quota": lambda _p: True}
        self.rpc_calls: List[tuple[str, dict]] = []
        self.storage_objects: Dict[tuple[str, str], bytes] = {}
        self.storage = FakeStorage(self)

    def table(self, name: str) -> FakeQuery:
        return FakeQuery(self, name)

    def rpc(self, name: str, params: Optional[dict] = None) -> FakeRpc:
        return FakeRpc(self, name, params or {})

    def seed(self, table: str, rows: List[dict]) -> None:
        self.tables.setdefault(table, []).extend(copy.deepcopy(rows))
