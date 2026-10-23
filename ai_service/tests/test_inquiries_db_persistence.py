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
