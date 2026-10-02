import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from dotenv import load_dotenv
load_dotenv()

import pytest
from supabase_client import get_client

def test_budgets_table_has_sub_allocations_column():
    sb = get_client()
    res = sb.table("budgets").select("id, sub_allocations").limit(1).execute()
    assert res.data is not None
    if len(res.data) > 0:
        assert "sub_allocations" in res.data[0]
