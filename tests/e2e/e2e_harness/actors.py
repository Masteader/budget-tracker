"""Simulated users and households driven through the public HTTP surfaces."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import httpx
import psycopg
from psycopg.rows import dict_row

from . import config
from .tokens import anon_key, user_token


class DB:
    """Superuser access to the e2e database for fixtures (auth signup) and assertions only."""

    def query(self, sql: str, params: Any = None) -> List[Dict[str, Any]]:
        with psycopg.connect(config.pg_dsn(), autocommit=True, row_factory=dict_row) as conn:
            cur = conn.execute(sql, params)
            return cur.fetchall() if cur.description else []

    def one(self, sql: str, params: Any = None) -> Optional[Dict[str, Any]]:
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def scalar(self, sql: str, params: Any = None) -> Any:
        row = self.one(sql, params)
        return next(iter(row.values())) if row else None


@dataclass
class User:
    id: str
    email: str
    display_name: str
    token: str
    api: httpx.Client
    rest: httpx.Client

    def rpc(self, name: str, params: Optional[dict] = None) -> httpx.Response:
        """Call a Postgres function through PostgREST as this user (what the Flutter app does)."""
        return self.rest.post(f"/rpc/{name}", json=params or {})


@dataclass
class Household:
    id: str
    name: str
    admin: User
    members: List[User] = field(default_factory=list)

    @property
    def everyone(self) -> List[User]:
        return [self.admin, *self.members]


class World:
    def __init__(self, app_url: str, gateway_url: str):
        self.app_url = app_url
        self.gateway_url = gateway_url
        self.db = DB()
        self._clients: List[httpx.Client] = []

    # ── clients ─────────────────────────────────────────────────────────────
    def _client(self, base_url: str, headers: Dict[str, str]) -> httpx.Client:
        client = httpx.Client(base_url=base_url, headers=headers, timeout=60.0, trust_env=False)
        self._clients.append(client)
        return client

    def anonymous_api(self, **headers) -> httpx.Client:
        return self._client(self.app_url, dict(headers))

    def close(self) -> None:
        for c in self._clients:
            c.close()

    # ── users ───────────────────────────────────────────────────────────────
    def signup(self, display_name: str, financial_role: Optional[str] = None) -> User:
        """GoTrue signup equivalent: an auth.users row (the trigger creates public.users)."""
        uid = str(uuid.uuid4())
        email = f"{display_name.lower().replace(' ', '.')}.{uid[:6]}@e2e.test"
        self.db.query(
            "INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES (%s, %s, jsonb_build_object('display_name', %s::text))",
            (uid, email, display_name),
        )
        if financial_role:
            self.db.query("UPDATE public.users SET financial_role = %s WHERE id = %s", (financial_role, uid))
        token = user_token(self.gateway_url, uid, email)
        api = self._client(self.app_url, {"Authorization": f"Bearer {token}"})
        rest = self._client(
            f"{self.gateway_url}/rest/v1",
            {"Authorization": f"Bearer {token}", "apikey": anon_key(), "Content-Type": "application/json"},
        )
        return User(id=uid, email=email, display_name=display_name, token=token, api=api, rest=rest)

    def token_for(self, user: User, **extra) -> str:
        return user_token(self.gateway_url, user.id, user.email, **extra)

    # ── households ──────────────────────────────────────────────────────────
    def create_household(self, admin: User, name: str, household_type: Optional[str] = None) -> Household:
        """create_household_and_claim as the app calls it; no type = the released app's {p_name} call (family)."""
        params = {"p_name": name}
        if household_type:
            params["p_household_type"] = household_type
        res = admin.rpc("create_household_and_claim", params)
        assert res.status_code == 200, res.text
        return Household(id=res.json()["id"], name=name, admin=admin)

    def invite(self, inviter: User, household: Household, role: str = "peer") -> str:
        res = inviter.api.post(f"/households/{household.id}/invites", json={"role": role})
        assert res.status_code == 200, res.text
        return res.json()["invite_code"]

    def join(self, user: User, household: Household, invite_code: str) -> dict:
        res = user.api.post(f"/households/invites/{invite_code}/claim")
        assert res.status_code == 200, res.text
        household.members.append(user)
        return res.json()

    def family(self, tag: str = "") -> Household:
        """Husband (primary admin, provider) + wife (member, spouse) joined by a spouse invite."""
        husband = self.signup(f"Husband{tag}")
        wife = self.signup(f"Wife{tag}")
        hh = self.create_household(husband, f"Family {tag or uuid.uuid4().hex[:4]}")
        self.join(wife, hh, self.invite(husband, hh, "spouse"))
        return hh

    def roommates(self, tag: str = "", n_members: int = 2) -> Household:
        admin = self.signup(f"RoomAdmin{tag}")
        hh = self.create_household(admin, f"Flat {tag or uuid.uuid4().hex[:4]}", household_type="roommates")
        for i in range(n_members):
            mate = self.signup(f"Roommate{i + 1}{tag}")
            self.join(mate, hh, self.invite(admin, hh, "peer"))
        return hh

    # ── chat commit helper ──────────────────────────────────────────────────
    def chat_commit(self, user: User, household: Household, llm, *, merchant: str, amount: float,
                    category_code: str = "OPEX-DINING", paid_by: str = "me", beneficiary: str = "both",
                    extra_body: Optional[dict] = None, occurred_at: Optional[str] = None,
                    headers: Optional[dict] = None) -> httpx.Response:
        llm.queue_json({
            "is_transaction": True,
            "merchant": merchant,
            "total_amount": amount,
            "currency": "SAR",
            "category_code": category_code,
            "spent_by": "me",
            "paid_by": paid_by,
            "beneficiary": beneficiary,
            "items": [{"name": merchant, "quantity": 1, "price": amount}],
        })
        body = {"household_id": household.id, "message": f"{merchant} {amount} SAR", "allow_duplicate": True}
        if occurred_at:
            body["client_occurred_at"] = occurred_at
        body.update(extra_body or {})
        return user.api.post("/agent/chat-transaction", json=body, headers=headers or {})
