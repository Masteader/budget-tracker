import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_public_inquiry_persists_to_db_even_if_email_provider_is_none():
    with patch("routes.inquiries._persist_inquiry", return_value=True) as mock_db, \
         patch("mail_service.active_provider", return_value=None):
        response = client.post(
            "/public/inquiries",
            json={
                "type": "vip_early_access",
                "email": "lead_test@example.com",
                "locale": "ar",
                "source": "web"
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert data["status"] in ("captured", "sent")
        assert "reference" in data
        mock_db.assert_called_once()


def test_public_inquiry_with_email_delivery_marks_delivered():
    with patch("routes.inquiries._persist_inquiry", return_value=True), \
         patch("routes.inquiries._update_inquiry_status") as mock_update, \
         patch("mail_service.active_provider", return_value="resend"), \
         patch("mail_service.send_email", return_value="resend"):
        response = client.post(
            "/public/inquiries",
            json={
                "type": "vip_early_access",
                "email": "lead_delivered@example.com",
                "locale": "ar",
                "source": "web"
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "sent"
        assert "reference" in data
        mock_update.assert_called_once()


def test_persist_inquiry_uses_correct_postgres_schema_columns():
    from routes.inquiries import _persist_inquiry, _update_inquiry_status

    mock_client = MagicMock()
    mock_table = MagicMock()
    mock_client.table.return_value = mock_table

    with patch("routes.inquiries.get_client", return_value=mock_client):
        result = _persist_inquiry(
            reference="ref123",
            inquiry_type="vip_early_access",
            email="lead@example.com",
            name="Test User",
            message="Interested in app",
            locale="ar",
            source="web",
        )
        assert result is True
        mock_client.table.assert_called_with("inquiries")
        insert_args = mock_table.insert.call_args[0][0]
        assert insert_args["reference"] == "ref123"
        assert insert_args["type"] == "vip_early_access"
        assert insert_args["email"] == "lead@example.com"
        assert insert_args["status"] == "captured"
        assert "inquiry_type" not in insert_args
        assert "delivery_status" not in insert_args

        _update_inquiry_status(reference="ref123", status="delivered", provider="resend")
        update_args = mock_table.update.call_args[0][0]
        assert update_args["status"] == "delivered"
        assert update_args["delivery_provider"] == "resend"
        assert "mail_provider" not in update_args
        assert "delivery_status" not in update_args

