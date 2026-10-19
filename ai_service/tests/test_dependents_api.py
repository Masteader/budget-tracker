import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_dependents_crud_endpoints(monkeypatch):
    from dependents_service import _memory_dependents
    household_id = "f860188e-23b5-4749-b180-868c956151a6"
    headers = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}
    _memory_dependents.clear()

    storage = []

    class MockQuery:
        def __init__(self, items):
            self.items = items
            self._filtered = list(items)

        def select(self, *args, **kwargs):
            return self

        def eq(self, col, val):
            self._filtered = [x for x in self._filtered if x.get(col) == val]
            return self

        def order(self, *args, **kwargs):
            return self

        def insert(self, payload):
            if isinstance(payload, list):
                self.items.extend(payload)
                self._res = payload
            else:
                self.items.append(payload)
                self._res = [payload]
            return self

        def delete(self):
            for item in list(self._filtered):
                if item in self.items:
                    self.items.remove(item)
            self._res = []
            return self

        def execute(self):
            res = MagicMock()
            res.data = getattr(self, "_res", self._filtered)
            return res

    class MockClient:
        def table(self, name):
            return MockQuery(storage)

    mock_c = MockClient()
    monkeypatch.setattr("supabase_client.get_client", lambda: mock_c)

    # 1. Create dependent
    post_res = client.post(
        f"/households/{household_id}/dependents",
        json={"name": "Sarah", "avatar_icon": "child"},
        headers=headers,
    )
    assert post_res.status_code == 200
    data = post_res.json()
    assert data["status"] == "success"
    dep = data["dependent"]
    assert dep["name"] == "Sarah"
    assert dep["household_id"] == household_id
    dep_id = dep["id"]

    # 2. List dependents
    get_res = client.get(f"/households/{household_id}/dependents", headers=headers)
    assert get_res.status_code == 200
    deps = get_res.json()["dependents"]
    assert len(deps) >= 1
    assert any(d["name"] == "Sarah" for d in deps)

    # 3. Delete dependent
    del_res = client.delete(f"/households/{household_id}/dependents/{dep_id}", headers=headers)
    assert del_res.status_code == 200
    assert del_res.json()["status"] == "success"

    # 4. Verify removed
    get_res2 = client.get(f"/households/{household_id}/dependents", headers=headers)
    deps2 = get_res2.json()["dependents"]
    assert not any(d["id"] == dep_id for d in deps2)
