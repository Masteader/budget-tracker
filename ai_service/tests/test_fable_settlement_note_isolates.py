"""
The app stores a settlement note whose direction marks keep "payer -> recipient"
reading correctly in right-to-left text. They must survive the server's note
handling, and the note must not create or disturb an audit tag.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from fable_world import World

LRI, FSI, PDI = "\u2066", "\u2068", "\u2069"
NOTE = f"{LRI}{FSI}أحمد{PDI} → {FSI}Omar{PDI} · cash{PDI}"


@pytest.fixture
def api():
    from main import app

    with TestClient(app) as c:
        yield c


@pytest.fixture
def w(fake_supabase):
    return World(fake_supabase, {"ahmed": ("admin", "peer"), "omar": ("member", "peer")})


def _stored_note(api, fake_supabase, w, notes: str) -> str:
    response = api.post(
        f"/households/{w.hid}/reimbursements",
        json={
            "household_id": w.hid,
            "payer_id": w.users["omar"],
            "recipient_id": w.users["ahmed"],
            "amount": 10,
            "payment_method": "cash",
            "notes": notes,
        },
        headers=w.hdr("omar"),
    )
    assert response.status_code == 200, response.text
    return [t for t in fake_supabase.tables["transactions"] if t.get("is_settlement")][0]["notes"]


def test_direction_marks_survive_the_route_and_the_stored_note(api, fake_supabase, w):
    assert _stored_note(api, fake_supabase, w, NOTE).endswith(f" | Note: {NOTE}")


def test_a_pipe_in_a_name_adds_no_tag_and_the_marks_stay(api, fake_supabase, w):
    note = f"{LRI}{FSI}A|B{PDI} → {FSI}Omar{PDI} · cash{PDI}"
    stored = _stored_note(api, fake_supabase, w, note)
    assert stored.count("|") == 4
    assert stored.endswith(f"{LRI}{FSI}A/B{PDI} → {FSI}Omar{PDI} · cash{PDI}")


def test_the_settlement_engine_still_reads_the_payer_from_the_head(api, fake_supabase, w):
    import settlement_engine

    match = settlement_engine._SETTLEMENT_HEAD_RE.match(_stored_note(api, fake_supabase, w, NOTE))
    assert match and match.group(1) == w.users["omar"]
