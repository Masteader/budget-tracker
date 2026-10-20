"""
Scenario 2: chat expense commits (LLM mocked) by every member, a ZATCA QR receipt commit (no LLM)
with a Nafaqah class, and cycle_key attribution for a 27th payday and a custom 10th payday around
month boundaries and Riyadh midnight.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from e2e_harness.zatca import tlv_qr


def _tx(db, tx_id):
    return db.one(
        "SELECT household_id::text, user_id::text, amount, source, category_code, cycle_key, nafaqah_class,"
        " nafaqah_spouse_id::text, qr_code_raw, dedup_fingerprint, timestamp FROM public.transactions WHERE id = %s",
        (tx_id,),
    )


def test_chat_commit_by_every_member_of_both_households(world, db, llm):
    family = world.family("C1")
    flat = world.roommates("C1", n_members=2)
    for hh in (family, flat):
        for i, user in enumerate(hh.everyone):
            res = world.chat_commit(user, hh, llm, merchant=f"Albaik {user.display_name}", amount=23.5 + i)
            assert res.status_code == 200, res.text
            body = res.json()
            assert body["status"] == "success", body
            row = _tx(db, body["transaction_id"])
            assert row["household_id"] == hh.id
            assert row["user_id"] == user.id, "creator must be the JWT subject"
            assert float(row["amount"]) == 23.5 + i
            assert row["source"] == "chat"
            assert row["cycle_key"] == body.get("cycle_key", row["cycle_key"])
    # The mocked LLM was the only model contacted, once per commit.
    assert len(llm.calls) == 5
    assert all(c["model"] == "e2e/fake-model" for c in llm.calls)

    # Family attribution: the wife paying for the household is her advance; the husband's is not.
    wife = family.members[0]
    rows = db.query(
        "SELECT user_id::text, nafaqah_class, nafaqah_spouse_id::text FROM public.transactions WHERE household_id = %s",
        (family.id,),
    )
    by_user = {r["user_id"]: r for r in rows}
    assert by_user[wife.id]["nafaqah_class"] == "wife_reimbursable"
    assert by_user[wife.id]["nafaqah_spouse_id"] == wife.id
    assert by_user[family.admin.id]["nafaqah_class"] is None
    # Roommates are never classified.
    assert db.scalar(
        "SELECT count(*) FROM public.transactions WHERE household_id = %s AND nafaqah_class IS NOT NULL", (flat.id,)
    ) == 0


def test_chat_heuristic_fallback_when_llm_unavailable(world, db, llm):
    flat = world.roommates("C2", n_members=0)
    res = flat.admin.api.post(
        "/agent/chat-transaction",
        json={"household_id": flat.id, "message": "Starbucks coffee 18 SAR", "allow_duplicate": True},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["status"] == "success" and body["amount"] == 18.0
    assert _tx(db, body["transaction_id"])["user_id"] == flat.admin.id


def test_zatca_qr_receipt_commit_with_nafaqah_class(world, db, llm):
    family = world.family("Q1")
    wife = family.members[0]
    vat_no = "3" + uuid.uuid4().int.__str__()[:13] + "3"
    qr = tlv_qr("Panda Retail Co", vat_no, "2026-10-19T18:30:00Z", "115.00", "15.00")

    preview = wife.api.post(
        "/agent/scan-receipt",
        json={"household_id": family.id, "qr_code_raw": qr, "preview_only": True, "nafaqah_class": "wife_personal"},
    )
    assert preview.status_code == 200, preview.text
    p = preview.json()
    assert p["status"] == "preview" and p["amount"] == 115.0 and p["vat_amount"] == 15.0
    assert p["household_mode"] == "family_nafaqah" and p["nafaqah_class"] == "wife_personal"
    assert db.scalar("SELECT count(*) FROM public.transactions WHERE household_id = %s", (family.id,)) == 0

    commit = wife.api.post(
        "/agent/scan-receipt",
        json={"household_id": family.id, "qr_code_raw": qr, "nafaqah_class": "wife_personal"},
        headers={"Idempotency-Key": f"qr-{uuid.uuid4().hex}"},
    )
    assert commit.status_code == 200, commit.text
    c = commit.json()
    assert c["status"] == "success", c
    row = _tx(db, c["transaction_id"])
    assert row["user_id"] == wife.id and row["source"] == "receipt_scan"
    assert float(row["amount"]) == 115.0
    assert row["nafaqah_class"] == "wife_personal" and row["nafaqah_spouse_id"] == wife.id
    assert row["qr_code_raw"] == qr and row["dedup_fingerprint"]
    assert llm.calls == [], "a QR-only receipt must not call the LLM"

    # Scanning the same invoice again is caught by the ZATCA fingerprint.
    again = wife.api.post("/agent/scan-receipt", json={"household_id": family.id, "qr_code_raw": qr})
    assert again.status_code == 200
    assert again.json()["status"] == "duplicate_candidate"
    assert again.json()["candidate_transaction_id"] == c["transaction_id"]

    # A wife cannot mislabel her household advance with a class that contradicts the attribution.
    bad = wife.api.post(
        "/agent/scan-receipt",
        json={"household_id": family.id, "qr_code_raw": tlv_qr("Danube", vat_no, "2026-10-19T19:00:00Z", "40.00", "5.22"),
              "paid_by": "me", "beneficiary": "both", "nafaqah_class": "wife_personal"},
    )
    assert bad.status_code == 422, bad.text


# ── cycle_key attribution ─────────────────────────────────────────────────────

def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


CYCLE_CASES_27 = [
    # (UTC instant, Riyadh local wall time, expected cycle_key for payday 27)
    (datetime(2026, 9, 26, 20, 59, 0, tzinfo=timezone.utc), "Sep 26 23:59", "2026-09"),
    (datetime(2026, 9, 26, 21, 0, 30, tzinfo=timezone.utc), "Sep 27 00:00:30 (UTC still Sep 26)", "2026-10"),
    (datetime(2026, 8, 31, 21, 30, tzinfo=timezone.utc), "Sep 1 00:30 (UTC still Aug 31)", "2026-09"),
    (datetime(2026, 10, 1, 9, 0, tzinfo=timezone.utc), "Oct 1 12:00", "2026-10"),
]

CYCLE_CASES_10 = [
    (datetime(2026, 10, 9, 20, 59, tzinfo=timezone.utc), "Oct 9 23:59", "2026-09"),
    (datetime(2026, 10, 9, 21, 1, tzinfo=timezone.utc), "Oct 10 00:01 (UTC still Oct 9)", "2026-10"),
    (datetime(2026, 9, 30, 21, 30, tzinfo=timezone.utc), "Oct 1 00:30 (UTC still Sep 30)", "2026-09"),
    (datetime(2026, 9, 10, 0, 0, tzinfo=timezone.utc), "Sep 10 03:00", "2026-09"),
    (datetime(2026, 9, 9, 20, 0, tzinfo=timezone.utc), "Sep 9 23:00", "2026-08"),
]


def _seed_cycle_budgets(db, household_id, category, cycles):
    for ck in cycles:
        db.query(
            "INSERT INTO public.budgets (household_id, month, category_code, allocated_amount, cycle_key)"
            " VALUES (%s, (%s || '-01')::date, %s, 5000, %s)",
            (household_id, ck, category, ck),
        )


@pytest.mark.parametrize("payday,cases", [(27, CYCLE_CASES_27), (10, CYCLE_CASES_10)], ids=["payday27", "payday10"])
def test_cycle_key_for_payday_around_boundaries(world, db, llm, payday, cases):
    flat = world.roommates(f"P{payday}", n_members=1)
    admin, member = flat.admin, flat.members[0]
    if payday != 27:
        assert member.api.put(f"/households/{flat.id}/payday", json={"payday_day": payday}).status_code == 403
        res = admin.api.put(f"/households/{flat.id}/payday", json={"payday_day": payday})
        assert res.status_code == 200, res.text
    assert admin.api.get(f"/households/{flat.id}/payday").json()["payday_day"] == payday
    assert db.scalar("SELECT payday_day FROM public.households WHERE id = %s", (flat.id,)) == payday

    category = "OPEX-DINING"
    _seed_cycle_budgets(db, flat.id, category, sorted({c[2] for c in cases}))

    for instant, wall, expected in cases:
        res = world.chat_commit(member, flat, llm, merchant=f"Cafe {wall}", amount=10, category_code=category,
                                occurred_at=_iso(instant))
        assert res.status_code == 200, res.text
        row = _tx(db, res.json()["transaction_id"])
        assert row["cycle_key"] == expected, f"{wall} Riyadh with payday {payday}"
        assert row["timestamp"] == instant

    # Each cycle budget was charged exactly its own transactions.
    budgets = db.query(
        "SELECT cycle_key, spent_amount FROM public.budgets WHERE household_id = %s AND category_code = %s",
        (flat.id, category),
    )
    expected_spent = {}
    for _, _, ck in cases:
        expected_spent[ck] = expected_spent.get(ck, 0) + 10
    assert {b["cycle_key"]: float(b["spent_amount"]) for b in budgets} == expected_spent


def test_occurred_at_window_is_enforced(world, llm):
    flat = world.roommates("P3", n_members=0)
    future = datetime.now(timezone.utc) + timedelta(hours=1)
    res = world.chat_commit(flat.admin, flat, llm, merchant="Future", amount=5, occurred_at=_iso(future))
    assert res.status_code == 400
    too_old = datetime.now(timezone.utc) - timedelta(days=120)
    res = world.chat_commit(flat.admin, flat, llm, merchant="Old", amount=5, occurred_at=_iso(too_old))
    assert res.status_code == 400
