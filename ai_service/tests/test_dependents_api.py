import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_dependents_crud_endpoints(monkeypatch):
    from dependents_service import _memory_dependents
    household_id = "test-household-001"
    _memory_dependents.clear()

    # 1. Create dependent
    post_res = client.post(
        f"/households/{household_id}/dependents",
        json={"name": "Sarah", "avatar_icon": "child"}
    )
    assert post_res.status_code == 200
    data = post_res.json()
    assert data["status"] == "success"
    dep = data["dependent"]
    assert dep["name"] == "Sarah"
    assert dep["household_id"] == household_id
    dep_id = dep["id"]

    # 2. List dependents
    get_res = client.get(f"/households/{household_id}/dependents")
    assert get_res.status_code == 200
    deps = get_res.json()["dependents"]
    assert len(deps) >= 1
    assert any(d["name"] == "Sarah" for d in deps)

    # 3. Delete dependent
    del_res = client.delete(f"/households/{household_id}/dependents/{dep_id}")
    assert del_res.status_code == 200
    assert del_res.json()["status"] == "success"

    # 4. Verify removed
    get_res2 = client.get(f"/households/{household_id}/dependents")
    deps2 = get_res2.json()["dependents"]
    assert not any(d["id"] == dep_id for d in deps2)
