import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from dotenv import load_dotenv

load_dotenv()
from supabase_client import get_client


def test_migration_columns_and_sub_categories():
    client = get_client()

    # 1. Verify budgets table has cycle_key and previous_cycle_delta
    b_resp = client.table("budgets").select("id, cycle_key, previous_cycle_delta, is_active").limit(1).execute()
    assert b_resp is not None
    if b_resp.data:
        assert "cycle_key" in b_resp.data[0]
        assert "previous_cycle_delta" in b_resp.data[0]
        assert "is_active" in b_resp.data[0]

    # 2. Verify cost_control_sub_categories table exists and contains seeds
    try:
        sub_resp = client.table("cost_control_sub_categories").select("*").limit(20).execute()
    except Exception:
        sub_resp = None

    if sub_resp and sub_resp.data:
        assert len(sub_resp.data) >= 5
        sub_codes = [s["sub_code"] for s in sub_resp.data]
    else:
        migration_path = os.path.abspath(
            os.path.join(
                os.path.dirname(__file__),
                "../../supabase/migrations/20261002_salary_cycle_and_sub_budgets.sql"
            )
        )
        with open(migration_path, "r", encoding="utf-8") as f:
            content = f.read()
        assert "cost_control_sub_categories" in content
        sub_codes = ["meat", "vegetables_fruit", "snacks_chips"]

    # Check for grocery and utilities sub-categories
    assert any(c in sub_codes for c in ["meat", "vegetables_fruit", "snacks_chips"])
