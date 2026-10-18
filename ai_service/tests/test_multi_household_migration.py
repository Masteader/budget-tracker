import os
import pytest

def test_migration_sql_syntax():
    migration_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "supabase",
        "migrations",
        "20261018_household_memberships_and_switching.sql",
    )
    assert os.path.exists(migration_path), f"Migration file not found at {migration_path}"
    with open(migration_path, "r", encoding="utf-8") as f:
        sql = f.read()

    assert "CREATE TABLE IF NOT EXISTS public.household_memberships" in sql
    assert "switch_active_household" in sql
    assert "get_user_households" in sql
    assert "INSERT INTO public.household_memberships" in sql
    assert "ALTER TABLE public.household_memberships ENABLE ROW LEVEL SECURITY" in sql
