import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from datetime import date
from unittest.mock import MagicMock, patch
import pytest

from installment_service import (
    calculate_installment_terms,
    InstallmentPlanCreate,
    InstallmentPlan,
)


def test_calculate_installment_terms():
    # eXtra purchase of SAR 7,408 across 4 months
    terms = calculate_installment_terms(
        total_amount=7408.0,
        installment_count=4,
        start_date=date(2026, 10, 1),
        day_of_month=27,
    )
    assert terms["monthly_amount"] == 1852.0
    assert terms["total_amount"] == 7408.0
    assert terms["installment_count"] == 4
    assert terms["remaining_amount"] == 5556.0  # 7408 - 1852
    assert terms["paid_installments"] == 1
    assert terms["remaining_installments"] == 3


def test_installment_plan_status_transition():
    plan = InstallmentPlan(
        id="inst_1",
        household_id="hh_1",
        merchant="United Electronics Co. eXtra",
        provider="Tamara",
        total_amount=7408.0,
        installment_count=4,
        monthly_amount=1852.0,
        paid_installments=1,
        day_of_month=27,
        status="ACTIVE",
    )
    assert plan.status == "ACTIVE"
    assert plan.remaining_amount == 5556.0

    # Advance payment to 4
    plan.record_payment()
    assert plan.paid_installments == 2
    assert plan.status == "ACTIVE"

    plan.record_payment()
    assert plan.paid_installments == 3
    assert plan.status == "ACTIVE"

    plan.record_payment()
    assert plan.paid_installments == 4
    assert plan.status == "COMPLETED"
    assert plan.remaining_amount == 0.0


def test_installments_api(tmp_path, monkeypatch, fake_supabase):
    # The payment RPC re-checks that the (mocked) caller is a member (migration 20261020750000).
    fake_supabase.seed("household_memberships", [{
        "household_id": "f860188e-23b5-4749-b180-868c956151a6", "user_id": "00000000-0000-0000-0000-000000000001",
        "role": "admin",
    }])

    from starlette.testclient import TestClient
    from main import app

    client = TestClient(app)

    # 1. Missing household_id returns 400
    res = client.get("/budgets/installments")
    assert res.status_code == 422 or res.status_code == 400

    # 2. Create installment plan
    hid = "f860188e-23b5-4749-b180-868c956151a6"
    headers = {"X-App-Token": os.environ.get("APP_AUTH_TOKEN", "test_token_for_ci_only")}
    payload = {
        "household_id": hid,
        "merchant": "United Electronics Co. eXtra",
        "provider": "Tamara",
        "total_amount": 7408.0,
        "installment_count": 4,
        "monthly_amount": 1852.0,
        "paid_installments": 1,
        "category_code": "OPEX-SHOPPING",
        "adjust_original_transaction": False,
    }
    create_res = client.post("/budgets/installments", json=payload, headers=headers)
    assert create_res.status_code == 200
    created_data = create_res.json()
    assert created_data["merchant"] == "United Electronics Co. eXtra"
    assert created_data["monthly_amount"] == 1852.0
    assert created_data["paid_installments"] == 1
    plan_id = created_data["id"]

    # 3. List plans
    list_res = client.get(f"/budgets/installments?household_id={hid}", headers=headers)
    assert list_res.status_code == 200
    data = list_res.json()
    assert "plans" in data
    plans = data["plans"]
    assert any(p["id"] == plan_id for p in plans)

    # 4. Pay installment
    pay_res = client.post(f"/budgets/installments/{plan_id}/pay", headers=headers)
    assert pay_res.status_code == 200
    paid_data = pay_res.json()
    assert paid_data["paid_installments"] == 2

    # 5. Edit / update installment plan (PUT /budgets/installments/{plan_id})
    update_payload = {
        "merchant": "eXtra Store Flagship",
        "total_amount": 8000.0,
        "monthly_amount": 2000.0,
        "paid_installments": 2,
        "installment_count": 4,
        "day_of_month": 28,
        "provider": "Tabby",
    }
    update_res = client.put(f"/budgets/installments/{plan_id}", json=update_payload, headers=headers)
    assert update_res.status_code == 200
    updated_data = update_res.json()
    assert updated_data["merchant"] == "eXtra Store Flagship"
    assert updated_data["total_amount"] == 8000.0
    assert updated_data["monthly_amount"] == 2000.0
    assert updated_data["provider"] == "Tabby"
    assert updated_data["day_of_month"] == 28

    # 6. Reject invalid paid_installments exceeding count
    bad_res = client.put(f"/budgets/installments/{plan_id}", json={"paid_installments": 10, "installment_count": 4}, headers=headers)
    assert bad_res.status_code in (400, 422)

    # 7. Complete plan by updating paid == count
    complete_res = client.put(f"/budgets/installments/{plan_id}", json={"paid_installments": 4, "installment_count": 4}, headers=headers)
    assert complete_res.status_code == 200
    assert complete_res.json()["status"] == "COMPLETED"


def test_installment_plan_update_validation():
    from installment_service import InstallmentPlanUpdate
    from pydantic import ValidationError

    # monthly_amount must be gt=0 (not 0)
    with pytest.raises(ValidationError):
        InstallmentPlanUpdate(monthly_amount=0)

    with pytest.raises(ValidationError):
        InstallmentPlanUpdate(monthly_amount=-100)

    valid = InstallmentPlanUpdate(monthly_amount=150.0)
    assert valid.monthly_amount == 150.0

    # status validation: case-insensitive ACTIVE, COMPLETED, CANCELLED
    valid_status = InstallmentPlanUpdate(status="active")
    assert valid_status.status == "ACTIVE"

    valid_comp = InstallmentPlanUpdate(status="Completed")
    assert valid_comp.status == "COMPLETED"

    with pytest.raises(ValidationError):
        InstallmentPlanUpdate(status="PENDING_UNKNOWN")


def test_installment_update_adjusts_linked_transaction(fake_supabase):
    from installment_service import InstallmentService, InstallmentPlanCreate, InstallmentPlanUpdate
    hid = "f860188e-23b5-4749-b180-868c956151a6"
    tx_id = "tx-12345678-0000-0000-0000-000000000001"

    fake_supabase.seed("transactions", [{
        "id": tx_id,
        "household_id": hid,
        "amount": 1000.0,
        "raw_sms": "Purchase at Extra",
    }])

    plan_req = InstallmentPlanCreate(
        household_id=hid,
        merchant="eXtra",
        provider="Tamara",
        total_amount=1000.0,
        installment_count=4,
        monthly_amount=250.0,
        original_transaction_id=tx_id,
        adjust_original_transaction=True,
    )
    plan = InstallmentService.create_plan(plan_req)
    assert plan.id is not None

    # Verify transaction was adjusted to 250.0
    tx_rows = fake_supabase.table("transactions").select("*").eq("id", tx_id).execute().data
    assert tx_rows[0]["amount"] == 250.0
    assert "Financed via Tamara" in tx_rows[0]["raw_sms"]

    # Now update plan monthly_amount to 300.0 and total to 1200.0
    update_req = InstallmentPlanUpdate(
        monthly_amount=300.0,
        total_amount=1200.0,
    )
    updated_plan = InstallmentService.update_plan(
        plan_id=plan.id,
        household_id=hid,
        req=update_req,
    )
    assert updated_plan is not None
    assert updated_plan.monthly_amount == 300.0
    assert updated_plan.total_amount == 1200.0

    # Linked transaction must be adjusted to 300.0
    tx_updated = fake_supabase.table("transactions").select("*").eq("id", tx_id).execute().data
    assert tx_updated[0]["amount"] == 300.0
    assert "Full price: SAR 1,200.00" in tx_updated[0]["raw_sms"]


