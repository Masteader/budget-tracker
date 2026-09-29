import base64

def make_tlv(tag: int, val: str) -> bytes:
    b = val.encode("utf-8")
    return bytes([tag, len(b)]) + b

def decode_zatca_tlv(b64_str: str) -> dict:
    try:
        raw = base64.b64decode(b64_str.strip())
        tags = {}
        idx = 0
        while idx < len(raw):
            tag = raw[idx]
            length = raw[idx + 1]
            val = raw[idx + 2 : idx + 2 + length].decode("utf-8", errors="replace")
            tags[tag] = val
            idx += 2 + length
        return {
            "seller_name": tags.get(1),
            "vat_number": tags.get(2),
            "timestamp": tags.get(3),
            "total_amount": float(tags.get(4, 0)) if tags.get(4) else None,
            "vat_amount": float(tags.get(5, 0)) if tags.get(5) else None,
        }
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    sample = make_tlv(1, "Tamimi Markets") + make_tlv(2, "300000000000003") + make_tlv(3, "2026-09-27 17:40") + make_tlv(4, "185.50") + make_tlv(5, "24.20")
    b64 = base64.b64encode(sample).decode("ascii")
    print("ZATCA QR:", b64)
    print("Decoded:", decode_zatca_tlv(b64))
