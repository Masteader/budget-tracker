import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from dotenv import load_dotenv

load_dotenv()
from supabase_client import get_client


def test_migration_sql_file_exists():
    """Verify migration file exists and defines household_dependents table and RLS policies."""
    migration_path = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "../../supabase/migrations/20261011_household_dependents_and_subcategories.sql"
        )
    )
    assert os.path.exists(migration_path)
    with open(migration_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "CREATE TABLE IF NOT EXISTS public.household_dependents" in content
    assert "ENABLE ROW LEVEL SECURITY" in content
    assert "idx_dependents_household" in content


def test_dining_keywords_expanded():
    """Verify restaurants_dinners subcategory keywords include shawarma, broasted, and plural forms."""
    client = get_client()
    res = client.table("cost_control_sub_categories").select("keywords").eq("parent_code", "OPEX-DINING").eq("sub_code", "restaurants_dinners").execute()
    assert len(res.data) > 0
    keywords = res.data[0]["keywords"] or []
    assert any("شاورما" in kw for kw in keywords)
    assert any("مطاعم" in kw for kw in keywords)
