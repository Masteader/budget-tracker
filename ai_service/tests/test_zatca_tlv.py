"""API-15: ZATCA Phase 1/2 TLV decoder robustness."""

import base64

import pytest

from receipt_scanner import decode_zatca_tlv


def tlv(tag: int, value: str, ber: bool = False) -> bytes:
    raw = value.encode("utf-8")
    n = len(raw)
    if ber and n >= 0x80:
        length = bytes([0x81, n]) if n <= 0xFF else bytes([0x82, n >> 8, n & 0xFF])
    else:
        length = bytes([n])
    return bytes([tag]) + length + raw


def qr(seller="Tamimi Markets", vat="300000000000003", ts="2026-10-04T22:19:34Z", total="185.50", vat_amt="24.20", ber=False) -> bytes:
    return tlv(1, seller, ber) + tlv(2, vat) + tlv(3, ts) + tlv(4, total) + tlv(5, vat_amt)


def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode()


def test_decodes_standard_qr_with_arabic_seller():
    res = decode_zatca_tlv(b64(qr(seller="أسواق التميمي")))
    assert res["seller_name"] == "أسواق التميمي"
    assert res["total_amount"] == 185.50
    assert res["vat_amount"] == 24.20
    assert res["vat_number"] == "300000000000003"


def test_accepts_urlsafe_and_unpadded_base64():
    encoded = base64.urlsafe_b64encode(qr(seller="متجر؟؟>>")).decode().rstrip("=")
    assert decode_zatca_tlv(encoded)["seller_name"] == "متجر؟؟>>"


def test_rejects_garbage_base64_instead_of_decoding_noise():
    assert decode_zatca_tlv("@@@@ not base64 at all !!!!") is None


def test_rejects_truncated_value():
    raw = qr()
    assert decode_zatca_tlv(b64(raw[:-3])) is None


def test_long_seller_name_with_ber_multibyte_length():
    name = ("شركة " * 40).strip()  # ~360 bytes in UTF-8 → 0x82 two-byte BER length
    res = decode_zatca_tlv(b64(qr(seller=name, ber=True)))
    assert res is not None and res["seller_name"] == name
    short_ber = "X" * 150  # 0x81 one-byte BER length
    assert decode_zatca_tlv(b64(qr(seller=short_ber, ber=True)))["seller_name"] == short_ber


def test_long_seller_name_with_single_byte_length():
    name = "Store" * 40  # 200 bytes, Phase-1 style single byte length
    res = decode_zatca_tlv(b64(qr(seller=name)))
    assert res is not None and res["seller_name"] == name


@pytest.mark.parametrize("total", ["abc", "NaN", "inf", "-5.00", "1e309", ""])
def test_rejects_non_numeric_or_invalid_totals(total):
    assert decode_zatca_tlv(b64(qr(total=total))) is None


def test_invalid_vat_amount_is_dropped_not_fatal():
    res = decode_zatca_tlv(b64(qr(vat_amt="n/a")))
    assert res is not None and res["vat_amount"] is None


def test_phase2_extra_tags_are_ignored():
    raw = qr() + bytes([6, 3]) + b"abc" + bytes([8, 2]) + b"\x01\x02"
    assert decode_zatca_tlv(b64(raw))["total_amount"] == 185.50


def test_invalid_utf8_seller_rejected():
    raw = bytes([1, 2, 0xC3, 0x28]) + tlv(4, "10.00")
    assert decode_zatca_tlv(b64(raw)) is None
