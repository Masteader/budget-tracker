"""Build ZATCA (Phase 1/2) Base64 TLV QR payloads like a Saudi POS prints them."""

from __future__ import annotations

import base64


def tlv_qr(seller: str, vat_number: str, timestamp: str, total: str, vat: str) -> str:
    out = b""
    for tag, value in enumerate((seller, vat_number, timestamp, total, vat), start=1):
        raw = value.encode("utf-8")
        out += bytes([tag, len(raw)]) + raw
    return base64.b64encode(out).decode("ascii")
