"""Zero-SMS policy guard for the AI service.

The product never reads SMS: expenses come only from receipt photos, ZATCA QR codes,
chat/voice and manual entry. These tests fail if an SMS ingestion route, SMS parsing
module, SMS simulator or an "sms" transaction channel is reintroduced.
"""
import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)

SERVICE_DIR = Path(__file__).resolve().parent.parent
TESTS_DIR = SERVICE_DIR / "tests"

# Identifiers of the removed SMS pipeline (webhook, LangGraph graph, simulators, dedup).
SMS_INGESTION_PATTERNS = re.compile(
    r"webhook/sms|SMSWebhook|is_duplicate_sms|def receive_sms|def send_sms|"
    r"raw_sms\s*:\s*str\s*=\s*Field|READ_SMS|RECEIVE_SMS|SMS_RECEIVED|langgraph",
)


def _service_python_files():
    for path in SERVICE_DIR.rglob("*.py"):
        if TESTS_DIR in path.parents or ".venv" in path.parts or "static" in path.parts:
            continue
        yield path


def test_sms_webhook_endpoint_removed():
    """POST /webhook/sms must not exist."""
    response = client.post(
        "/webhook/sms",
        json={"raw_sms": "test", "sender": "SNB", "received_at": "2026-01-01", "household_id": "test"},
    )
    assert response.status_code in (404, 405)


def test_no_route_mentions_sms():
    paths = [getattr(route, "path", "") for route in app.routes]
    assert not [p for p in paths if "sms" in p.lower()], paths


def test_no_sms_or_simulator_modules_in_service():
    names = [p.name for p in _service_python_files()]
    offenders = [n for n in names if "sms" in n.lower() or n in ("graph.py", "batch_simulate.py")]
    assert offenders == []


def test_no_manual_dev_scripts_at_service_root():
    """Root-level test_*.py dev scripts (live server / real LLM callers) were removed (API-25)."""
    offenders = sorted(p.name for p in SERVICE_DIR.glob("test_*.py"))
    assert offenders == []


def test_service_code_has_no_sms_ingestion_identifiers():
    offenders = []
    for path in _service_python_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in SMS_INGESTION_PATTERNS.finditer(text):
            offenders.append(f"{path.relative_to(SERVICE_DIR)}: {match.group(0)}")
    assert offenders == []


def test_requirements_have_no_sms_pipeline_dependency():
    requirements = (SERVICE_DIR / "requirements.txt").read_text(encoding="utf-8").lower()
    assert "langgraph" not in requirements


def test_dockerignore_does_not_reference_deleted_sms_scripts():
    dockerignore = (SERVICE_DIR / ".dockerignore").read_text(encoding="utf-8")
    for name in ("send_simulated_sms.py", "batch_simulate.py", "graph.py", "test_chat_endpoint.py"):
        assert name not in dockerignore


def test_insert_transaction_rejects_sms_source():
    from supabase_client import TRANSACTION_SOURCES, insert_transaction

    assert "sms" not in TRANSACTION_SOURCES
    with pytest.raises(ValueError):
        insert_transaction(
            household_id="f860188e-23b5-4749-b180-868c956151a6",
            amount=10.0,
            currency="SAR",
            merchant="Panda",
            category_code="OPEX-GROCERY",
            timestamp="2026-10-20T09:00:00Z",
            raw_sms="note",
            source="sms",
        )


def test_insert_transaction_defaults_to_manual_source(fake_supabase):
    from supabase_client import insert_transaction

    insert_transaction(
        household_id="f860188e-23b5-4749-b180-868c956151a6",
        amount=10.0,
        currency="SAR",
        merchant="Panda",
        category_code="OPEX-GROCERY",
        timestamp="2026-10-20T09:00:00Z",
        raw_sms="Manual: Panda",
    )
    assert fake_supabase.tables["transactions"][0]["source"] == "manual"


def test_health_still_works():
    response = client.get("/health")
    assert response.status_code == 200

