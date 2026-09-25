"""
Unit tests for multimodal receipt scanner.
"""
from unittest.mock import patch, MagicMock
from receipt_scanner import parse_receipt_image

@patch("receipt_scanner.litellm.completion")
def test_parse_receipt_image_mocked(mock_completion):
    mock_resp = MagicMock()
    mock_resp.choices = [
        MagicMock(
            message=MagicMock(
                content='''{
                    "merchant": "Starbucks Coffee",
                    "total_amount": 34.50,
                    "vat_amount": 4.50,
                    "currency": "SAR",
                    "date": "2026-09-25 14:30:00",
                    "category_code": "OPEX-DINING",
                    "items": [
                        {"name": "Caramel Macchiato", "quantity": 1.0, "price": 24.0},
                        {"name": "Croissant", "quantity": 1.0, "price": 10.50}
                    ],
                    "confidence": "high"
                }'''
            )
        )
    ]
    mock_completion.return_value = mock_resp

    data = parse_receipt_image("fake_base64_string")
    assert data["merchant"] == "Starbucks Coffee"
    assert data["total_amount"] == 34.50
    assert len(data["items"]) == 2
    assert data["category_code"] == "OPEX-DINING"
