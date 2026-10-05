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


def test_installments_api():
    from starlette.testclient import TestClient
    from main import app

    client = TestClient(app)

    # 1. Missing household_id returns 400
    res = client.get("/budgets/installments")
    assert res.status_code == 422 or res.status_code == 400

    # 2. Create installment plan
    payload = {
        "household_id": "hh_test_123",
        "merchant": "United Electronics Co. eXtra",
        "provider": "Tamara",
        "total_amount": 7408.0,
        "installment_count": 4,
        "monthly_amount": 1852.0,
        "paid_installments": 1,
        "category_code": "OPEX-SHOPPING",
        "adjust_original_transaction": False,
    }
    create_res = client.post("/budgets/installments", json=payload)
    assert create_res.status_code == 200
    created_data = create_res.json()
    assert created_data["merchant"] == "United Electronics Co. eXtra"
    assert created_data["monthly_amount"] == 1852.0
    assert created_data["paid_installments"] == 1
    plan_id = created_data["id"]

    # 3. List plans
    list_res = client.get("/budgets/installments?household_id=hh_test_123")
    assert list_res.status_code == 200
    data = list_res.json()
    assert "plans" in data
    plans = data["plans"]
    assert any(p["id"] == plan_id for p in plans)

    # 4. Pay installment
    pay_res = client.post(f"/budgets/installments/{plan_id}/pay")
    assert pay_res.status_code == 200
    paid_data = pay_res.json()
    assert paid_data["paid_installments"] == 2
