"""
Regression tests for the 2026-10 ai_service security & logic audit (API-xx findings).

This module is excluded from the conftest auth mock: requests carry real HS256
Supabase-style JWTs verified by auth._decode_token, and household membership is
resolved from the in-memory FakeSupabaseClient.
"""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient
from jose import jwt

from main import app

TEST_SECRET = "super-secret-test-jwt-key-32bytes-long!"
ISSUER = "https://mockproject.supabase.co/auth/v1"

HH_A = "aaaaaaaa-0000-4000-8000-000000000001"
HH_B = "bbbbbbbb-0000-4000-8000-000000000002"
USER_A = "00000000-0000-4000-8000-0000000000a1"
USER_A_MEMBER = "00000000-0000-4000-8000-0000000000a2"
USER_B = "00000000-0000-4000-8000-0000000000b1"
TX_B = "cccccccc-0000-4000-8000-0000000000b9"

client = TestClient(app)


def make_token(sub: str, **overrides) -> str:
    now = int(time.time())
    claims = {
        "sub": sub,
        "aud": "authenticated",
        "iss": ISSUER,
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, TEST_SECRET, algorithm="HS256")


def bearer(sub: str) -> dict:
    return {"Authorization": f"Bearer {make_token(sub)}"}


@pytest.fixture()
def two_households(fake_supabase):
    fake_supabase.seed("household_memberships", [
        {"user_id": USER_A, "household_id": HH_A, "role": "admin"},
        {"user_id": USER_A_MEMBER, "household_id": HH_A, "role": "member"},
        {"user_id": USER_B, "household_id": HH_B, "role": "admin"},
    ])
    fake_supabase.seed("transactions", [
        {"id": TX_B, "household_id": HH_B, "amount": 500.0, "merchant": "Jarir", "raw_sms": "manual", "items": []},
    ])
    return fake_supabase


# ─── API-02: installment payment IDOR ────────────────────────────────────────

def test_pay_installment_requires_authentication(two_households):
    two_households.seed("installment_plans", [{
        "id": "dddddddd-0000-4000-8000-000000000001", "household_id": HH_B, "merchant": "eXtra",
        "provider": "Tamara", "total_amount": 400.0, "installment_count": 4, "monthly_amount": 100.0,
        "paid_installments": 1, "day_of_month": 27, "start_date": "2026-10-01", "status": "ACTIVE",
    }])
    resp = client.post("/budgets/installments/dddddddd-0000-4000-8000-000000000001/pay")
    assert resp.status_code == 401
    assert two_households.tables["installment_plans"][0]["paid_installments"] == 1


def test_pay_installment_of_foreign_household_is_forbidden(two_households):
    two_households.seed("installment_plans", [{
        "id": "dddddddd-0000-4000-8000-000000000001", "household_id": HH_B, "merchant": "eXtra",
        "provider": "Tamara", "total_amount": 400.0, "installment_count": 4, "monthly_amount": 100.0,
        "paid_installments": 1, "day_of_month": 27, "start_date": "2026-10-01", "status": "ACTIVE",
    }])
    resp = client.post("/budgets/installments/dddddddd-0000-4000-8000-000000000001/pay", headers=bearer(USER_A))
    assert resp.status_code == 403
    assert two_households.tables["installment_plans"][0]["paid_installments"] == 1

    ok = client.post("/budgets/installments/dddddddd-0000-4000-8000-000000000001/pay", headers=bearer(USER_B))
    assert ok.status_code == 200
    assert ok.json()["paid_installments"] == 2


# ─── API-03: global sub-category rename / read without auth ──────────────────

def test_sub_category_routes_require_authentication(two_households):
    assert client.get("/budgets/sub-categories", params={"parent_code": "OPEX-GROCERY"}).status_code == 401
    resp = client.patch("/budgets/sub-categories", json={"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "pwned"})
    assert resp.status_code == 401


def test_rename_of_shared_system_sub_category_is_forbidden(two_households):
    two_households.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-GROCERY", "category": "Groceries", "keywords": [], "is_flexible": True, "household_id": None, "is_system": True},
    ])
    two_households.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "Meat & Poultry", "name_ar": "اللحوم"},
    ])
    resp = client.patch(
        "/budgets/sub-categories",
        json={"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "pwned"},
        headers=bearer(USER_A),
    )
    assert resp.status_code == 403
    assert two_households.tables["cost_control_sub_categories"][0]["name_en"] == "Meat & Poultry"


def test_rename_of_own_custom_sub_category_by_admin_succeeds(two_households):
    two_households.seed("cost_control_codes", [
        {"id": "c2", "code": "CUSTOM-PETS", "category": "Pets", "keywords": [], "is_flexible": True, "household_id": HH_A, "is_system": False},
    ])
    two_households.seed("cost_control_sub_categories", [
        {"parent_code": "CUSTOM-PETS", "sub_code": "food", "name_en": "Food", "name_ar": "Food"},
    ])
    member = client.patch(
        "/budgets/sub-categories",
        json={"parent_code": "CUSTOM-PETS", "sub_code": "food", "name_en": "Cat food"},
        headers=bearer(USER_A_MEMBER),
    )
    assert member.status_code == 403
    outsider = client.patch(
        "/budgets/sub-categories",
        json={"parent_code": "CUSTOM-PETS", "sub_code": "food", "name_en": "Cat food"},
        headers=bearer(USER_B),
    )
    assert outsider.status_code == 403
    admin = client.patch(
        "/budgets/sub-categories",
        json={"parent_code": "CUSTOM-PETS", "sub_code": "food", "name_en": "Cat food"},
        headers=bearer(USER_A),
    )
    assert admin.status_code == 200
    assert two_households.tables["cost_control_sub_categories"][0]["name_en"] == "Cat food"


# ─── API-04: enrichment IDOR across households ───────────────────────────────

def test_chat_enrichment_cannot_touch_foreign_transaction(two_households, monkeypatch):
    from chat_parser import ParsedChatExpense, ChatLineItem, process_chat_transaction

    monkeypatch.setattr("chat_parser.parse_chat_expense", lambda _msg: ParsedChatExpense(
        merchant="Attacker", total_amount=1.0, items=[ChatLineItem(name="pwned", quantity=1, price=1.0)],
    ))
    res = process_chat_transaction(household_id=HH_A, message="x", user_id=USER_A, enrich_tx_id=TX_B)
    assert res["status"] == "error"
    assert two_households.tables["transactions"][0]["items"] == []


def test_receipt_enrichment_cannot_touch_foreign_transaction(two_households, monkeypatch):
    from receipt_scanner import process_receipt_scan

    monkeypatch.setattr("receipt_scanner.parse_receipt_image", lambda *_a, **_k: {
        "merchant": "Attacker", "total_amount": 10.0, "items": [{"name": "pwned", "quantity": 1, "price": 10.0}],
    })
    res = process_receipt_scan(household_id=HH_A, images_base64=["aGVsbG8="], user_id=USER_A,
                               enrich_tx_id=TX_B, preview_only=True)
    assert res["status"] == "error"
    assert two_households.tables["transactions"][0]["items"] == []


# ─── API-05: installment creation rewrites a foreign transaction ─────────────

def test_installment_creation_cannot_adjust_foreign_transaction(two_households):
    payload = {
        "household_id": HH_A, "merchant": "eXtra", "provider": "Tamara", "total_amount": 400.0,
        "installment_count": 4, "original_transaction_id": TX_B, "adjust_original_transaction": True,
    }
    resp = client.post("/budgets/installments", json=payload, headers=bearer(USER_A))
    assert resp.status_code in (400, 403, 404)
    assert two_households.tables["transactions"][0]["amount"] == 500.0


def test_installment_creation_requires_household_and_auth(two_households):
    payload = {"merchant": "eXtra", "total_amount": 400.0}
    assert client.post("/budgets/installments", json=payload).status_code == 401
    assert client.post("/budgets/installments", json=payload, headers=bearer(USER_A)).status_code in (400, 422)


def test_installment_adjusts_own_transaction_and_recalculates(two_households):
    tx_a = "cccccccc-0000-4000-8000-0000000000a9"
    two_households.seed("transactions", [{"id": tx_a, "household_id": HH_A, "amount": 400.0, "raw_sms": "", "items": []}])
    payload = {
        "household_id": HH_A, "merchant": "eXtra", "provider": "Tamara", "total_amount": 400.0,
        "installment_count": 4, "original_transaction_id": tx_a, "adjust_original_transaction": True,
    }
    resp = client.post("/budgets/installments", json=payload, headers=bearer(USER_A))
    assert resp.status_code == 200
    row = next(t for t in two_households.tables["transactions"] if t["id"] == tx_a)
    assert row["amount"] == 100.0
    assert "Financed via Tamara" in row["raw_sms"]


# ─── API-06: cross-tenant category tampering ─────────────────────────────────

def test_add_category_does_not_modify_shared_system_category(two_households):
    two_households.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-GROCERY", "category": "Groceries", "keywords": ["panda"], "is_flexible": True, "household_id": None, "is_system": True},
    ])
    resp = client.post("/budgets/categories", headers=bearer(USER_A), json={
        "household_id": HH_A, "code": "OPEX-GROCERY", "category": "pwned", "keywords": ["x"], "allocated_amount": 50.0,
    })
    assert resp.status_code == 200
    system_row = two_households.tables["cost_control_codes"][0]
    assert system_row["category"] == "Groceries" and system_row["keywords"] == ["panda"]


def test_add_new_category_is_scoped_to_household(two_households):
    resp = client.post("/budgets/categories", headers=bearer(USER_A), json={
        "household_id": HH_A, "code": "CUSTOM-GYM", "category": "Gym", "allocated_amount": 50.0,
    })
    assert resp.status_code == 200
    rows = [r for r in two_households.tables["cost_control_codes"] if r["code"] == "CUSTOM-GYM"]
    assert len(rows) == 1 and rows[0]["household_id"] == HH_A


def test_remove_sub_category_never_purges_shared_definition(two_households):
    two_households.seed("cost_control_codes", [
        {"id": "c1", "code": "OPEX-GROCERY", "category": "Groceries", "keywords": [], "is_flexible": True, "household_id": None, "is_system": True},
    ])
    two_households.seed("cost_control_sub_categories", [
        {"parent_code": "OPEX-GROCERY", "sub_code": "meat", "name_en": "Meat", "name_ar": "Meat"},
    ])
    resp = client.delete("/budgets/sub-categories", headers=bearer(USER_A),
                         params={"household_id": HH_A, "parent_code": "OPEX-GROCERY", "sub_code": "meat"})
    assert resp.status_code == 200
    assert len(two_households.tables["cost_control_sub_categories"]) == 1


# ─── Route coverage: every non-public route rejects anonymous callers ────────

PUBLIC_PATHS = {
    "/", "/auth/confirm", "/auth/callback", "/health", "/docs", "/redoc", "/openapi.json",
    "/docs/oauth2-redirect", "/hero_glacier.png", "/hero_glacier.jpg", "/favicon.svg",
    "/hero-bg.webp", "/hero-bg.jpg", "/households/invites/{invite_code}",
}


def _fill_path(path: str) -> str:
    return (path.replace("{household_id}", HH_A).replace("{plan_id}", "dddddddd-0000-4000-8000-000000000001")
            .replace("{invite_code}", "ABCDEF0123456789").replace("{dependent_id}", USER_A)
            .replace("{category_code}", "OPEX-GROCERY"))


def test_every_non_public_route_rejects_anonymous_requests(two_households):
    checked = 0
    failures = []
    for path, operations in app.openapi()["paths"].items():
        if path in PUBLIC_PATHS:
            continue
        for method in operations:
            url = _fill_path(path)
            resp = client.request(method.upper(), url, params={"household_id": HH_A, "parent_code": "OPEX-GROCERY",
                                                                "sub_code": "meat"}, json={"household_id": HH_A})
            if resp.status_code not in (401, 403, 422):
                failures.append(f"{method.upper()} {path} -> {resp.status_code}")
            checked += 1
    assert not failures, failures
    assert checked > 30
