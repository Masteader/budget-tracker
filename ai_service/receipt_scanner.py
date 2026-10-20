"""
Multimodal receipt and invoice scanner using Gemini 3.5/3.8 Flash Vision.
Supports:
1. Multi-photo capture for long receipts (60+ items across multiple shots)
2. Saudi ZATCA e-invoicing Base64 TLV QR code decoding
3. Item-by-item extraction without truncation
"""

from __future__ import annotations
import base64
import binascii
import json
import logging
import math
import re
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from urllib.parse import unquote

import litellm
from dotenv import load_dotenv

from dedup_engine import find_duplicate_candidate, enrich_transaction_items, compute_zatca_fingerprint
from nafaqah_service import resolve_expense_nafaqah

from supabase_client import (
    get_client,
    fetch_all_cost_control_codes,
    match_category,
    insert_transaction,
    fetch_budget,
    fetch_flexible_budgets,
    reallocate_budget,
)

from utils import litellm_model, riyadh_today, riyadh_date_for_timestamp  # noqa: E402

logger = logging.getLogger(__name__)

# ─── Upload validation ───────────────────────────────────────────────────────
MAX_RECEIPT_IMAGES = 8
MAX_RECEIPT_IMAGE_BYTES = 8 * 1024 * 1024
MAX_RECEIPT_PIXELS = 40_000_000  # per image; guards PIL decompression bombs during stitching
_IMAGE_MAGIC = (
    (b"\xff\xd8\xff", "jpeg"),
    (b"\x89PNG\r\n\x1a\n", "png"),
    (b"RIFF", "webp"),
)
_LEGACY_STORAGE_URL_RE = re.compile(
    r"^https?://[^/]+/storage/v1/object/(?:public|sign|authenticated)/receipts/([^?#]+)(?:[?#].*)?$"
)
_RECEIPT_FILE_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}\.(?:jpg|jpeg|png|webp|heic)$", re.IGNORECASE)


def normalize_receipt_path(receipt_url: Optional[str], household_id: str) -> Optional[str]:
    """
    Normalise a client-supplied receipt reference to a storage path inside the caller's
    household folder ``{household_id}/{file}.{jpg|jpeg|png|webp|heic}``. Legacy public/signed
    Supabase URLs are converted to that path. Anything else (another household's folder,
    traversal incl. URL-encoded, absolute paths, foreign URLs, non-image extensions) raises
    ValueError. Previously the value was stored verbatim on the transaction.
    """
    if receipt_url is None or not str(receipt_url).strip():
        return None
    value = str(receipt_url).strip()
    legacy = _LEGACY_STORAGE_URL_RE.match(value)
    if legacy:
        value = legacy.group(1)
    for _ in range(3):  # decode nested percent-encoding (%252e → %2e → .)
        decoded = unquote(value)
        if decoded == value:
            break
        value = decoded
    if "://" in value or value.startswith("/") or "\\" in value or ".." in value or "\x00" in value:
        raise ValueError("receipt_url must be a storage path inside the household folder.")
    parts = value.split("/")
    if len(parts) != 2 or parts[0].lower() != str(household_id).lower() or not _RECEIPT_FILE_RE.match(parts[1]):
        raise ValueError("receipt_url must be a storage path inside the household folder.")
    return value


def validate_receipt_images(images_base64: List[str]) -> None:
    """Reject too many images, oversized/invalid base64 and payloads that are not JPEG/PNG/WebP."""
    if len(images_base64) > MAX_RECEIPT_IMAGES:
        raise ValueError(f"A receipt can have at most {MAX_RECEIPT_IMAGES} photos.")
    for img in images_base64:
        data = img.split(",", 1)[1] if isinstance(img, str) and "," in img else img
        if not isinstance(data, str) or len(data) > (MAX_RECEIPT_IMAGE_BYTES * 4) // 3 + 4:
            raise ValueError("Receipt photo is too large or malformed.")
        try:
            raw = base64.b64decode(data, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("Receipt photo is not valid base64.")
        if not any(raw.startswith(magic) for magic, _ in _IMAGE_MAGIC):
            raise ValueError("Receipt photo must be a JPEG, PNG or WebP image.")
        if raw.startswith(b"RIFF") and raw[8:12] != b"WEBP":
            raise ValueError("Receipt photo must be a JPEG, PNG or WebP image.")


def decode_zatca_tlv(b64_str: str) -> Optional[Dict[str, Any]]:
    """
    Decodes Saudi ZATCA e-invoicing Phase 1 & 2 Base64 TLV QR code.
    Tag 1: Seller Name
    Tag 2: VAT Registration Number (15 digits)
    Tag 3: Invoice Timestamp (ISO)
    Tag 4: Total Amount (with VAT)
    Tag 5: VAT Amount
    """
    if not b64_str or len(b64_str) < 10 or len(b64_str) > 4096:
        return None
    raw = _decode_qr_base64(b64_str)
    if raw is None:
        return None
    # Phase 1 encoders use a single length byte (0-255); some Phase 2 encoders emit BER
    # long-form lengths (0x81 n / 0x82 hi lo) for values >= 128 bytes. Each interpretation
    # must parse completely AND yield valid fields before it is accepted.
    for ber_lengths in (False, True):
        tags = _parse_tlv(raw, ber_lengths=ber_lengths)
        result = _interpret_zatca_tags(tags) if tags else None
        if result:
            return result
    logger.debug("ZATCA TLV decode failed: no valid interpretation")
    return None


def _interpret_zatca_tags(tags: Dict[int, bytes]) -> Optional[Dict[str, Any]]:
    try:
        seller = tags[1].decode("utf-8").strip() if 1 in tags else None
        vat_no = tags[2].decode("utf-8").strip() if 2 in tags else None
        ts = tags[3].decode("utf-8").strip() if 3 in tags else None
    except UnicodeDecodeError:
        return None
    total = _parse_sar_amount(tags.get(4))
    if not seller or not total:
        return None
    return {
        "seller_name": seller,
        "vat_number": vat_no,
        "timestamp": ts,
        "total_amount": total,
        "vat_amount": _parse_sar_amount(tags.get(5)),
    }


_B64_STD_RE = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")
_B64_URL_RE = re.compile(r"^[A-Za-z0-9_-]+={0,2}$")
_SAR_AMOUNT_RE = re.compile(r"^\d{1,9}(?:\.\d{1,6})?$")


def _decode_qr_base64(value: str) -> Optional[bytes]:
    """Strict base64 (standard or URL-safe, padding optional); invalid characters are an error
    rather than being silently discarded (b64decode's default) and yielding garbage TLV."""
    text = "".join(value.split())
    padded = text + "=" * (-len(text) % 4)
    try:
        if _B64_STD_RE.match(text):
            return base64.b64decode(padded, validate=True)
        if _B64_URL_RE.match(text):
            return base64.urlsafe_b64decode(padded)
    except (binascii.Error, ValueError):
        return None
    return None


def _parse_tlv(raw: bytes, ber_lengths: bool) -> Optional[Dict[int, bytes]]:
    """Parse the whole buffer as TLV; None on any truncation (the old parser silently accepted
    short values). The first occurrence of a tag wins."""
    tags: Dict[int, bytes] = {}
    idx, n = 0, len(raw)
    while idx < n:
        if idx + 2 > n:
            return None
        tag = raw[idx]
        length = raw[idx + 1]
        idx += 2
        if ber_lengths and length & 0x80:
            num = length & 0x7F
            if num == 0 or num > 2 or idx + num > n:
                return None
            length = int.from_bytes(raw[idx: idx + num], "big")
            idx += num
        if idx + length > n:
            return None
        tags.setdefault(tag, raw[idx: idx + length])
        idx += length
    return tags


def _parse_sar_amount(value: Optional[bytes]) -> Optional[float]:
    """Decimal amount in SAR; None for anything non-numeric, negative, NaN/inf or exponent form."""
    if not value:
        return None
    try:
        text = value.decode("ascii").strip().replace(",", "")
    except UnicodeDecodeError:
        return None
    if not _SAR_AMOUNT_RE.match(text):
        return None
    from decimal import Decimal, ROUND_HALF_UP
    return float(Decimal(text).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def stitch_images_vertically(images_base64: List[str]) -> bytes:
    """
    Decodes base64 receipt images and stitches them vertically into a single continuous JPEG.
    If only one image is supplied, decodes and returns it directly.
    """
    if not images_base64:
        return b""

    import io
    from PIL import Image

    raw_bytes_list: List[bytes] = []
    for img_data in images_base64:
        if "," in img_data:
            img_data = img_data.split(",", 1)[1]
        try:
            raw_bytes_list.append(base64.b64decode(img_data))
        except Exception:
            pass

    if not raw_bytes_list:
        return b""

    if len(raw_bytes_list) == 1:
        return raw_bytes_list[0]

    try:
        opened = [Image.open(io.BytesIO(b)) for b in raw_bytes_list]  # lazy: header only
        if any(img.width * img.height > MAX_RECEIPT_PIXELS for img in opened):
            raise ValueError("Receipt photo dimensions exceed the stitching limit.")
        pil_images = [img.convert("RGB") for img in opened]
        base_width = pil_images[0].width
        resized = []
        total_height = 0
        for img in pil_images:
            if img.width != base_width:
                w_percent = base_width / float(img.width)
                h_size = int(float(img.height) * float(w_percent))
                img = img.resize((base_width, h_size), Image.Resampling.LANCZOS)
            resized.append(img)
            total_height += img.height

        combined = Image.new("RGB", (base_width, total_height))
        y_offset = 0
        for img in resized:
            combined.paste(img, (0, y_offset))
            y_offset += img.height

        out = io.BytesIO()
        combined.save(out, format="JPEG", quality=85)
        return out.getvalue()
    except Exception as e:
        logger.warning("Vertical stitching failed, falling back to first image: %s", e)
        return raw_bytes_list[0]


RECEIPT_PROMPT = """You are an expert financial receipt & invoice analyzer for Saudi Arabia.
Inspect the attached receipt/invoice photo(s) carefully.
NOTE: If there are multiple photos, they represent sequential parts of a single LONG receipt (e.g. top, middle, bottom of a 60+ item grocery receipt).
When multiple photos are provided, sequential photos may have overlapping items where the shots meet.
You MUST stitch the receipt segments seamlessly and DEDUPLICATE overlapping items so that each physical item appears exactly once.
Cross-check that the sum of item prices matches the printed invoice total.

Analyze ALL photos together and extract:
1. Merchant name (store, supermarket, restaurant, or company name)
2. Total amount (including VAT)
3. VAT amount (15% Saudi VAT if displayed)
4. Invoice date and time
5. Complete itemized breakdown:
   - Extract EVERY SINGLE item item-by-item from start to finish.
   - Do NOT abbreviate or truncate the list. If there are 60 items, list all 60 items.
   - For each item, provide name, quantity, and total item price in SAR.
6. Category code (choose best match):
   - OPEX-GROCERY (supermarket, food, grocery)
   - OPEX-DINING (restaurant, cafe, bakery)
   - OPEX-FUEL (petrol, transport)
   - OPEX-UTILITIES (bills, telecom)
   - OPEX-SHOPPING (retail, electronics, clothes)
   - OPEX-ENTERTAINMENT (movies, games)
   - OPEX-HEALTH (pharmacy, hospital)
   - OPEX-MISC (other)
7. If a ZATCA QR code is visible on any photo, read its encoded text or base64 if possible.

Return STRICTLY a JSON object conforming to:
{
  "merchant": "Store Name",
  "total_amount": 0.0,
  "vat_amount": 0.0,
  "currency": "SAR",
  "date": "YYYY-MM-DD HH:MM:SS or null",
  "category_code": "OPEX-...",
  "zatca_qr_raw": "base64 string if found or null",
  "items": [
    {
      "name": "Item Description",
      "quantity": 1.0,
      "price": 0.0
    }
  ],
  "confidence": "high | medium | low"
}
"""

def parse_receipt_images(
    images_base64: List[str],
    qr_code_raw: Optional[str] = None,
) -> Dict[str, Any]:
    """Call Gemini multimodal vision API with 1 or more receipt images."""
    model = litellm_model()
    
    prompt_text = RECEIPT_PROMPT
    if qr_code_raw:
        zatca_hint = decode_zatca_tlv(qr_code_raw)
        if zatca_hint and zatca_hint.get("seller_name"):
            prompt_text += (
                f"\n\nPRIORITY CONTEXT: This receipt is verified via Saudi ZATCA e-invoicing for store: "
                f"'{zatca_hint['seller_name']}' with total: SAR {zatca_hint.get('total_amount', 0.0)} "
                f"and 15% VAT: SAR {zatca_hint.get('vat_amount', 0.0)}. "
                f"Focus especially on accurately extracting all individual line items, their quantities, "
                f"and their individual prices under this store."
            )

    content: List[Dict[str, Any]] = [
        {"type": "text", "text": prompt_text}
    ]

    for img in images_base64:
        clean_img = img.split(",", 1)[1] if "," in img else img
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:image/jpeg;base64,{clean_img}"}
        })

    response = litellm.completion(
        model=model,
        messages=[{"role": "user", "content": content}],
        response_format={"type": "json_object"},
        temperature=1.0,
    )

    result_json = response.choices[0].message.content
    parsed: Dict[str, Any] = json.loads(result_json)

    # Check for ZATCA QR passed from client or extracted by Gemini
    qr_to_check = qr_code_raw or parsed.get("zatca_qr_raw")
    if qr_to_check:
        zatca = decode_zatca_tlv(qr_to_check)
        if zatca:
            logger.info("ZATCA QR decoded successfully: %s", zatca)
            parsed["zatca_verified"] = zatca
            if zatca.get("seller_name"):
                parsed["merchant"] = zatca["seller_name"]
            if zatca.get("total_amount"):
                parsed["total_amount"] = zatca["total_amount"]
            if zatca.get("vat_amount"):
                parsed["vat_amount"] = zatca["vat_amount"]
            if zatca.get("timestamp"):
                parsed["date"] = zatca["timestamp"]

    return validate_ocr_receipt_payload(parsed)


def validate_ocr_receipt_payload(parsed: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validates and sanitizes OCR-parsed receipt payload:
    - total_amount: rejects negative values, rejects amounts > 10,000,000 SAR.
    - line items: price must be >= 0 and <= 10,000,000; quantity must be > 0 and <= 10,000.
    - merchant: strips ASCII and Unicode control characters.
    """
    import re

    # Merchant sanitization: strip control characters (0x00-0x1F, 0x7F-0x9F)
    merchant = parsed.get("merchant") or "Scanned Merchant"
    merchant = re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(merchant)).strip()
    if not merchant:
        merchant = "Scanned Merchant"
    parsed["merchant"] = merchant

    # Total amount validation
    try:
        raw_total = float(parsed.get("total_amount") or 0.0)
    except (ValueError, TypeError):
        raw_total = 0.0

    if not math.isfinite(raw_total):
        raise ValueError("Receipt total amount is not a finite number.")
    if raw_total < 0:
        raise ValueError(f"Invalid negative receipt total amount: {raw_total}")
    if raw_total > 10_000_000:
        raise ValueError(f"Astronomical receipt total amount exceeding 10,000,000 SAR: {raw_total}")
    parsed["total_amount"] = round(raw_total, 2)

    # Line items validation
    raw_items = parsed.get("items") or []
    valid_items: List[Dict[str, Any]] = []

    for it in raw_items:
        if not isinstance(it, dict):
            continue
        name = re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(it.get("name", "Item"))).strip()
        try:
            qty = float(it.get("quantity", 1.0))
        except (ValueError, TypeError):
            qty = 1.0
        try:
            price = float(it.get("price", 0.0))
        except (ValueError, TypeError):
            price = 0.0

        if not (math.isfinite(qty) and math.isfinite(price)):
            raise ValueError("Receipt item quantity and price must be finite numbers.")
        if qty <= 0 or qty > 10_000:
            raise ValueError(f"Invalid receipt item quantity ({qty}). Must be between 0 and 10,000.")
        if price < 0 or price > 10_000_000:
            raise ValueError(f"Invalid receipt item price ({price}). Must be between 0 and 10,000,000 SAR.")

        valid_items.append({
            "name": name or "Item",
            "quantity": round(qty, 2),
            "price": round(price, 2),
        })

    parsed["items"] = valid_items
    return parsed


def parse_receipt_image(
    image_base64: str,
    qr_code_raw: Optional[str] = None,
) -> Dict[str, Any]:
    """Single image wrapper for backwards compatibility."""
    return parse_receipt_images([image_base64], qr_code_raw=qr_code_raw)


def process_receipt_scan(
    household_id: str,
    images_base64: Optional[List[str]] = None,
    qr_code_raw: Optional[str] = None,
    user_id: Optional[str] = None,
    allow_duplicate: bool = False,
    enrich_tx_id: Optional[str] = None,
    preview_only: bool = False,
    override_merchant: Optional[str] = None,
    override_spent_by: Optional[str] = None,
    receipt_url: Optional[str] = None,
    occurred_at: Optional[datetime] = None,
    paid_by: Optional[str] = None,
    beneficiary: Optional[str] = None,
    override_nafaqah_class: Optional[str] = None,
    override_nafaqah_spouse_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Process scanned receipt image(s) or ZATCA QR code:
    1. Parse via Gemini Vision across multiple images if photos provided
    2. Decode ZATCA QR code if provided (or if photos omitted)
    3. Check for duplicate against recent chat/manual entries
    4. Auto-enrich or insert transaction

    Family households (Islamic Nafaqah) are classified exactly like chat expenses: ``paid_by`` /
    ``beneficiary`` default to the recorder paying for the household ('me' / 'both'), so a
    receipt the wife scans is her shared advance (``wife_reimbursable``, the husband owes it)
    unless she chooses her allowance (``wife_personal``) or says her husband paid ('none'). The
    preview returns the suggestion; the commit stores the class (resolve_expense_nafaqah raises
    InvalidNafaqahRequest for a contradicting choice or a missing wife).
    """
    images_base64 = images_base64 or []

    try:
        receipt_url = normalize_receipt_path(receipt_url, household_id)
        validate_receipt_images(images_base64)
    except ValueError as invalid:
        return {"status": "error", "message": str(invalid)}

    # If client could not upload directly (e.g. Storage RLS restriction), upload server-side using service role
    # IMPORTANT: Only upload when committing/saving (not during preview) and if client hasn't already uploaded
    if not preview_only and not receipt_url and images_base64:
        try:
            import time, uuid
            client = get_client()
            raw_bytes = stitch_images_vertically(images_base64)
            ts = int(time.time() * 1000)
            u = uuid.uuid4().hex[:8]
            storage_path = f"{household_id}/{ts}_{u}.jpg"
            client.storage.from_("receipts").upload(
                storage_path,
                raw_bytes,
                file_options={"content-type": "image/jpeg", "upsert": "true"},
            )
            receipt_url = storage_path
            logger.info("Auto-uploaded receipt photo (stitched %d shots) to storage path: %s", len(images_base64), receipt_url)
        except Exception as upload_err:
            logger.warning("Could not auto-upload receipt image: %s", upload_err)

    if images_base64:
        try:
            if len(images_base64) == 1:
                parsed = parse_receipt_image(images_base64[0], qr_code_raw=qr_code_raw)
            else:
                parsed = parse_receipt_images(images_base64, qr_code_raw=qr_code_raw)
        except Exception as exc:
            # Provider exceptions can carry API URLs, model ids or key fragments: log, don't echo.
            logger.error("Failed to parse receipt image(s): %s", exc, exc_info=True)
            return {
                "status": "error",
                "message": "Failed to analyze receipt. Please try again or enter the expense manually.",
            }
    elif qr_code_raw:
        zatca = decode_zatca_tlv(qr_code_raw)
        if not zatca:
            return {
                "status": "error",
                "message": "Could not decode ZATCA QR code. Please ensure it is a valid Base64 TLV code.",
            }
        seller = zatca.get("seller_name") or "VAT Tax Invoice"
        total_val = float(zatca.get("total_amount") or 0.0)
        vat_val = float(zatca.get("vat_amount") or 0.0)
        if vat_val == 0.0 and total_val > 0:
            vat_val = round(total_val * 0.15 / 1.15, 2)

        parsed = {
            "merchant": seller,
            "total_amount": total_val,
            "vat_amount": vat_val,
            "category_code": "OPEX-GROCERY",
            "items": [
                {
                    "name": f"Tax Invoice Total (15% VAT {vat_val:.2f} SAR)",
                    "quantity": 1.0,
                    "price": total_val,
                }
            ],
            "zatca_verified": zatca,
            "date": zatca.get("timestamp"),
        }
    else:
        return {
            "status": "error",
            "message": "Please provide receipt image(s) or a ZATCA QR code.",
        }

    try:
        parsed = validate_ocr_receipt_payload(parsed)
    except ValueError as val_err:
        return {
            "status": "error",
            "message": f"Invalid receipt content: {str(val_err)}",
            "parsed_data": parsed,
        }

    resolved_qr = qr_code_raw or parsed.get("zatca_qr_raw")
    merchant = (override_merchant or parsed.get("merchant") or "Scanned Merchant").strip()
    spent_by = (override_spent_by or "both").lower()
    if spent_by not in ("me", "partner", "both"):
        spent_by = "both"
    total_amount = float(parsed.get("total_amount") or 0.0)
    category_code = parsed.get("category_code") or "OPEX-MISC"
    raw_items = parsed.get("items") or []

    # Clean items formatting
    raw_formatted: List[Dict[str, Any]] = []
    for it in raw_items:
        if isinstance(it, dict):
            raw_formatted.append({
                "name": str(it.get("name", "Item")),
                "quantity": float(it.get("quantity", 1.0)),
                "price": float(it.get("price", 0.0)),
            })

    # Stitch & deduplicate overlapping items from multi-page shots
    items: List[Dict[str, Any]] = []
    seen_item_keys = set()
    for it in raw_formatted:
        clean_name = it["name"].strip().lower()
        key = (clean_name, round(it["price"], 2), round(it["quantity"], 2))
        if key in seen_item_keys:
            continue
        seen_item_keys.add(key)
        items.append(it)

    items_sum = sum(it["price"] for it in items)
    if total_amount <= 0 and items:
        # Sum items if total wasn't explicitly detected
        total_amount = round(items_sum, 2)
    elif total_amount > 0 and items:
        # Subtotal cross-check
        if abs(items_sum - total_amount) > 1.0:
            logger.info("Subtotal cross-check note: item sum is %.2f vs total %.2f", items_sum, total_amount)

    if total_amount <= 0:
        return {
            "status": "error",
            "message": "Could not detect a valid total amount on the scanned receipt.",
            "parsed_data": parsed,
        }

    # Compute deterministic ZATCA fingerprint if ZATCA QR was decoded
    zatca_info = parsed.get("zatca_verified")
    zatca_fp = None
    if zatca_info and zatca_info.get("vat_number"):
        zatca_fp = compute_zatca_fingerprint(
            vat_number=zatca_info.get("vat_number"),
            invoice_timestamp=zatca_info.get("timestamp"),
            total_amount=total_amount,
        )

    # Explicit enrichment
    if enrich_tx_id:
        success = enrich_transaction_items(enrich_tx_id, items, household_id=household_id, actor_user_id=user_id)
        if not success:
            return {
                "status": "error",
                "transaction_id": enrich_tx_id,
                "message": "Transaction to enrich was not found in this household.",
            }
        return {
            "status": "enriched",
            "transaction_id": enrich_tx_id,
            "merchant": merchant,
            "amount": total_amount,
            "category_code": category_code,
            "spent_by": spent_by,
            "items": items,
            "zatca_verified": parsed.get("zatca_verified"),
            "message": f"Successfully attached {len(items)} scanned receipt items to existing transaction.",
        }

    attributed_paid_by = (paid_by or "me").strip().lower()
    if attributed_paid_by not in ("me", "partner"):
        attributed_paid_by = "me"
    nafaqah = resolve_expense_nafaqah(
        household_id,
        user_id,
        attributed_paid_by,
        (beneficiary or "both").strip() or "both",
        override_class=override_nafaqah_class,
        override_spouse_id=override_nafaqah_spouse_id,
        attribution_explicit=paid_by is not None or beneficiary is not None,
        require_spouse=not preview_only,
    )
    nafaqah_fields = {
        "paid_by": nafaqah["paid_by"],
        "beneficiary": nafaqah["beneficiary"],
        "household_mode": nafaqah["household_mode"],
        "recorder_role": nafaqah["recorder_role"],
        "nafaqah_class": nafaqah["nafaqah_class"],
        "nafaqah_spouse_id": nafaqah["nafaqah_spouse_id"],
        "nafaqah_spouse_required": nafaqah["nafaqah_spouse_required"],
        "wives": nafaqah["wives"],
    }

    # Deduplication check (evaluated during BOTH preview and save unless allow_duplicate=True)
    candidate = None
    if not allow_duplicate:
        candidate = find_duplicate_candidate(
            household_id=household_id,
            amount=total_amount,
            merchant=merchant,
            zatca_fingerprint=zatca_fp,
        )

    if candidate:
        logger.info("Duplicate candidate found for scanned receipt: %s", candidate["id"])
        cand_ts = str(candidate.get("timestamp") or candidate.get("created_at") or "")[:10]
        ts_suffix = f" on {cand_ts}" if cand_ts else ""
        return {
            "status": "duplicate_candidate",
            "candidate_transaction_id": candidate["id"],
            "candidate_merchant": candidate.get("merchant"),
            "candidate_amount": candidate.get("amount"),
            "candidate_timestamp": candidate.get("timestamp"),
            "candidate_source": candidate.get("source"),
            "parsed_data": {
                "merchant": merchant,
                "amount": total_amount,
                "category_code": category_code,
                "spent_by": spent_by,
                "items": items,
                "zatca_verified": parsed.get("zatca_verified"),
                "receipt_url": receipt_url,
                "qr_code_raw": resolved_qr,
            },
            "items": items,
            "merchant": merchant,
            "amount": total_amount,
            "category_code": category_code,
            "spent_by": spent_by,
            "receipt_url": receipt_url,
            "qr_code_raw": resolved_qr,
            **nafaqah_fields,
            "message": (
                f"A transaction of SAR {candidate.get('amount')} at '{candidate.get('merchant')}' "
                f"was already recorded{ts_suffix}. "
                f"Would you like to attach these {len(items)} items or log as separate expense?"
            ),
        }

    # Match category with keyword taxonomy
    codes = fetch_all_cost_control_codes()
    matched = match_category(merchant, codes)
    if matched:
        category_code = matched.code

    # Check if category is inactive for this household
    is_inactive = False
    try:
        from salary_cycle import get_household_categories
        hh_cats = get_household_categories(household_id)
        inactive_codes = {c["code"] for c in hh_cats.get("inactive", [])}
        is_inactive = category_code in inactive_codes
    except Exception as exc:
        logger.warning(f"Could not check category active status: {exc}")

    # If preview only (and no duplicate candidate found), return structured data before inserting
    if preview_only:
        return {
            "status": "preview",
            "merchant": merchant,
            "amount": total_amount,
            "vat_amount": float(parsed.get("vat_amount") or 0.0),
            "category_code": category_code,
            "is_category_inactive": is_inactive,
            "suggested_alternative": "OPEX-MISC" if is_inactive else None,
            "spent_by": spent_by,
            "items": items,
            "zatca_verified": parsed.get("zatca_verified"),
            "receipt_url": receipt_url,
            "qr_code_raw": resolved_qr,
            **nafaqah_fields,
            "message": f"Scanned invoice: SAR {total_amount:.2f} at {merchant} ({len(items)} items).",
        }

    # A replayed offline commit carries the client-side event time (validated by the route).
    event_time = occurred_at or datetime.now(timezone.utc)
    now_iso = event_time.isoformat()
    now_date = riyadh_date_for_timestamp(event_time)

    # Check budget
    budget = fetch_budget(household_id, category_code, now_date)
    is_reallocated = False
    reallocated_from_id = None

    if budget and budget.remaining_amount < total_amount:
        deficit = total_amount - budget.remaining_amount
        flexible = fetch_flexible_budgets(household_id, now_date, exclude_code=category_code)
        if flexible and flexible[0].remaining_amount >= deficit:
            if reallocate_budget(flexible[0].id, budget.id, deficit):
                is_reallocated = True
                reallocated_from_id = flexible[0].id

    items_summary = ", ".join(f"{it['quantity']}x {it['name']} ({it['price']} SAR)" for it in items[:10])
    if len(items) > 10:
        items_summary += f" ...and {len(items) - 10} more items"
    audit_text = f"Receipt Scan: {merchant} ({len(items)} items) | Items: [{items_summary}]"

    tx_id = insert_transaction(
        household_id=household_id,
        amount=total_amount,
        currency="SAR",
        merchant=merchant,
        category_code=category_code,
        timestamp=now_iso,
        raw_sms=audit_text,
        is_reallocated=is_reallocated,
        reallocated_from_budget_id=reallocated_from_id,
        source="receipt_scan",
        items=items,
        spent_by=spent_by,
        paid_by=nafaqah["paid_by"],
        beneficiary=nafaqah["beneficiary"],
        nafaqah_class=nafaqah["nafaqah_class"],
        nafaqah_spouse_id=nafaqah["nafaqah_spouse_id"],
        dedup_fingerprint=zatca_fp,
        receipt_url=receipt_url,
        qr_code_raw=resolved_qr,
        user_id=user_id,
    )

    if items:
        enrich_transaction_items(tx_id, items, household_id=household_id)

    return {
        "status": "success",
        "transaction_id": tx_id,
        "merchant": merchant,
        "amount": total_amount,
        "category_code": category_code,
        "items": items,
        "zatca_verified": parsed.get("zatca_verified"),
        "receipt_url": receipt_url,
        "qr_code_raw": resolved_qr,
        "is_reallocated": is_reallocated,
        "paid_by": nafaqah["paid_by"],
        "beneficiary": nafaqah["beneficiary"],
        "nafaqah_class": nafaqah["nafaqah_class"],
        "nafaqah_spouse_id": nafaqah["nafaqah_spouse_id"],
        "message": f"Recorded SAR {total_amount:.2f} ({len(items)} items) from scanned receipt ({merchant}).",
    }
