"""
Zero-row lookups must not depend on postgrest-py's maybe_single() behaviour.

- postgrest-py 2.x (installed: 2.33) returns ``None`` instead of a response when maybe_single()
  matches no row, so ``resp.data`` raises AttributeError.
- postgrest-py 0.19.1-1.1.x (still allowed: supabase 2.16.0 pins ``postgrest>0.19,<1.2``) asks the
  server for a single object and only maps the error to ``None`` when its details text says
  "The result contains 0 rows"; otherwise it raises APIError("Missing response").

These tests drive the real installed supabase/postgrest client against a mocked PostgREST
(``respx``; no network), plus the in-memory fake for the old-client failure mode.
"""

from __future__ import annotations

import httpx
import pytest
import respx

import auth
import salary_cycle
import supabase_client

URL = "https://mockproject.supabase.co"
HH = "aaaaaaaa-0000-4000-8000-000000000020"
USER = "00000000-0000-4000-8000-0000000000c1"


@pytest.fixture()
def real_client(monkeypatch):
    """A real supabase client whose REST calls are answered from ``tables`` (empty by default)."""
    from supabase import create_client

    client = create_client(URL, "sb_secret_mock_value_for_tests_only")
    tables: dict = {}
    seen: list = []

    def handler(request: httpx.Request):
        table = request.url.path.rsplit("/", 1)[-1]
        seen.append((table, dict(request.url.params)))
        return httpx.Response(200, json=tables.get(table, []))

    router = respx.mock(assert_all_called=False)
    router.route(url__startswith=f"{URL}/rest/v1/").mock(side_effect=handler)
    router.start()
    monkeypatch.setattr(supabase_client, "_client", client)
    monkeypatch.setattr(salary_cycle, "get_client", lambda: client)
    monkeypatch.setattr(auth, "get_client", lambda: client)
    yield tables, seen
    router.stop()


def test_installed_postgrest_maybe_single_returns_none_for_zero_rows(real_client):
    """Documents the library behaviour the fixes guard against (``res.data`` is unsafe)."""
    import postgrest

    res = supabase_client.get_client().table("budgets").select("*").eq("id", "x").maybe_single().execute()
    if int(postgrest.__version__.split(".")[0]) >= 2:
        assert res is None  # 2.x: no response object at all
    else:
        # 0.19-1.1 request a single object; a real PostgREST answers 406, which becomes None or
        # APIError depending on the error text. This mock answers 200 [], which yields data=[].
        assert res is None or not res.data


def test_first_row_returns_first_match_or_none(real_client):
    tables, seen = real_client
    query = lambda: supabase_client.get_client().table("households").select("payday_day").eq("id", HH)  # noqa: E731
    assert supabase_client.first_row(query()) is None
    tables["households"] = [{"payday_day": 10}]
    assert supabase_client.first_row(query()) == {"payday_day": 10}
    assert seen[-1][1].get("limit") == "1"


def test_affordability_with_no_budget_row_for_the_category_does_not_crash(real_client, monkeypatch):
    monkeypatch.setattr(salary_cycle, "get_salary_cycle_forecast", lambda _hid: {
        "total_remaining": 5000.0, "daily_remaining_allowance": 250.0,
        "cycle": {"days_remaining": 20, "payday": "2026-11-27", "cycle_key": "2026-11"},
    })
    monkeypatch.setattr(salary_cycle, "fetch_flexible_budgets", lambda *a, **k: [])
    res = salary_cycle.simulate_affordability(HH, 300.0, item_name="Shoes", category_code="OPEX-SHOPPING")
    assert res["verdict"] in ("caution", "unaffordable")
    assert res["target_amount"] == 300.0


def test_affordability_reads_the_category_budget_of_the_current_cycle(real_client, monkeypatch):
    tables, seen = real_client
    tables["budgets"] = [{"category_code": "OPEX-SHOPPING", "cycle_key": "2026-11", "remaining_amount": 2000.0}]
    monkeypatch.setattr(salary_cycle, "get_salary_cycle_forecast", lambda _hid: {
        "total_remaining": 5000.0, "daily_remaining_allowance": 250.0,
        "cycle": {"days_remaining": 20, "payday": "2026-11-27", "cycle_key": "2026-11"},
    })
    monkeypatch.setattr(salary_cycle, "fetch_flexible_budgets", lambda *a, **k: [])
    res = salary_cycle.simulate_affordability(HH, 1200.0, item_name="iPad", category_code="OPEX-SHOPPING")
    assert res["verdict"] == "comfortable"
    budget_queries = [params for table, params in seen if table == "budgets"]
    assert budget_queries[0].get("cycle_key") == "eq.2026-11"


def test_missing_membership_is_no_access_with_the_real_client(real_client):
    tables, _ = real_client
    tables["users"] = [{"household_id": HH, "role": "admin"}]  # stale cache column
    assert auth._get_user_membership(USER, HH) is None
    tables["household_memberships"] = [{"role": "member", "household_id": HH}]
    assert auth._get_user_membership(USER, HH) == {"role": "member", "household_id": HH}


def test_old_client_zero_row_error_does_not_fall_back_to_stale_users_row(fake_supabase, monkeypatch):
    """postgrest <= 1.1 raises on a zero-row maybe_single(); that must not reach the API-13 fallback."""
    from fakes import FakeQuery

    original_execute = FakeQuery.execute

    def old_client_execute(self):
        if self._maybe_single:
            rows = [r for r in self._client.tables.get(self._table, []) if self._matches(r)]
            if not rows:
                raise RuntimeError("APIError: Missing response (code 204)")
        return original_execute(self)

    monkeypatch.setattr(FakeQuery, "execute", old_client_execute)
    fake_supabase.seed("users", [{"id": USER, "household_id": HH, "role": "admin"}])
    assert auth._get_user_membership(USER, HH) is None


@pytest.mark.parametrize("getter, expected", [
    (supabase_client.get_household_payday, 27),
    (supabase_client.get_household_income, 0.0),
    (supabase_client.get_household_rollover_rule, supabase_client.DEFAULT_ROLLOVER_RULE),
])
def test_household_setting_getters_fall_back_cleanly_when_the_row_is_missing(real_client, getter, expected, caplog):
    assert getter(HH) == expected


def test_household_setting_getters_read_the_row_with_the_real_client(real_client):
    tables, _ = real_client
    tables["households"] = [{"payday_day": 10, "monthly_income": 12000, "rollover_rule": supabase_client.DEFAULT_ROLLOVER_RULE,
                             "accumulated_savings": 50.5, "last_rollover_surplus": 5, "last_rollover_cycle": "2026-10"}]
    assert supabase_client.get_household_payday(HH) == 10
    assert supabase_client.get_household_income(HH) == 12000.0
    state = supabase_client.get_household_savings_summary(HH)
    assert state["accumulated_savings"] == 50.5 and state["last_rollover_cycle"] == "2026-10"
