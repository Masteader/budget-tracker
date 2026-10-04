"""
Unit tests for multimodal receipt scanner.
"""
import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

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


@patch("receipt_scanner.litellm.completion")
def test_parse_receipt_hybrid_zatca_and_items(mock_completion):
    from receipt_scanner import parse_receipt_images, decode_zatca_tlv
    import base64

    # Sample valid ZATCA TLV Base64 for Panda Supermarket
    tlv = (
        b'\x01\x11Panda Supermarket'
        b'\x02\x0f300012345600003'
        b'\x03\x142026-10-04T12:00:00Z'
        b'\x04\x06150.00'
        b'\x05\x0519.57'
    )
    sample_qr = base64.b64encode(tlv).decode()

    # Gemini mock returns items extracted from photo, but potentially vague merchant name
    mock_resp = MagicMock()
    mock_resp.choices = [
        MagicMock(
            message=MagicMock(
                content='''{
                    "merchant": "Receipt Scan",
                    "total_amount": 150.00,
                    "vat_amount": 19.57,
                    "currency": "SAR",
                    "category_code": "OPEX-GROCERY",
                    "items": [
                        {"name": "Almarai Fresh Milk 2L", "quantity": 2.0, "price": 22.0},
                        {"name": "Lipton Tea 100 bags", "quantity": 1.0, "price": 18.50},
                        {"name": "Basmati Rice 5kg", "quantity": 1.0, "price": 45.0},
                        {"name": "Olive Oil 500ml", "quantity": 1.0, "price": 34.50},
                        {"name": "Greek Yogurt", "quantity": 2.0, "price": 30.0}
                    ],
                    "confidence": "high"
                }'''
            )
        )
    ]
    mock_completion.return_value = mock_resp

    result = parse_receipt_images(["fake_image_base64"], qr_code_raw=sample_qr)

    # Merchant must be the verified ZATCA merchant name, not the generic receipt scan name
    assert result["merchant"] == "Panda Supermarket"
    assert result["total_amount"] == 150.00
    assert result["vat_amount"] == 19.57
    assert len(result["items"]) == 5
    assert result["items"][0]["name"] == "Almarai Fresh Milk 2L"
    assert "zatca_verified" in result
    assert result["zatca_verified"]["vat_number"] == "300012345600003"
