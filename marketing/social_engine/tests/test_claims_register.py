"""The approved and rejected claims register (spec Section 6.5, task C1).

Every product statement in a reel traces back to one of these rows, so the register has to
stay complete, cite real files and carry the date it was last checked against the code.
"""

import json
import re
from datetime import date
from pathlib import Path

import pytest

ENGINE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ENGINE_ROOT.parents[1]
REGISTER_PATH = ENGINE_ROOT / "content_engine" / "approved_claims.json"

CLAIM_IDS = [f"C{number:02d}" for number in range(1, 22)]
REJECTED_IDS = [f"R{number:02d}" for number in range(1, 8)]
SPEC_CATCHERS = {
    "R01": {"G2"},
    "R02": {"G22"},
    "R03": {"G5"},
    "R04": {"G11"},
    "R05": {"G21"},
    "R06": {"G4", "G20"},
    "R07": {"G13", "G19"},
}
# The code re-check of 2026-11-04 found these do not hold as the spec words them. They stay
# listed with the spec's wording, and guardrail G1 refuses them until the owner rules.
NOT_BACKED_BY_CODE = {"C02", "C03", "C06", "C08", "C17"}

ARABIC_LETTER = re.compile(r"[ء-ي]")
LATIN_LETTER = re.compile(r"[A-Za-z]")
BANK_WORD = re.compile(r"bank|بنك|بنوك|مصرف", re.IGNORECASE)


@pytest.fixture(scope="module")
def register() -> dict:
    return json.loads(REGISTER_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def claims(register) -> dict:
    return {claim["id"]: claim for claim in register["claims"]}


@pytest.fixture(scope="module")
def rejected(register) -> dict:
    return {row["id"]: row for row in register["rejected_claims"]}


def test_all_claims_are_present_once(register):
    assert [claim["id"] for claim in register["claims"]] == CLAIM_IDS


def test_all_rejected_claims_are_present_once(register):
    assert [row["id"] for row in register["rejected_claims"]] == REJECTED_IDS


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_each_claim_has_wording_in_both_languages(claims, claim_id):
    claim = claims[claim_id]
    assert ARABIC_LETTER.search(claim["wording_ar"]), "Arabic wording has no Arabic"
    assert LATIN_LETTER.search(claim["wording_en"]), "English wording has no Latin letters"
    assert not ARABIC_LETTER.search(claim["wording_en"]), "English wording holds Arabic"


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_each_claim_cites_files_that_exist(claims, claim_id):
    evidence = claims[claim_id]["evidence"]
    assert evidence, "a claim with no evidence cannot be approved"
    for path in evidence:
        assert (REPO_ROOT / path).is_file(), f"{claim_id} cites a missing file: {path}"


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_each_claim_cites_code_and_not_only_documents(claims, claim_id):
    # docs/PROJECT_DETAILS.md was last verified on 2026-10-20, so it cannot be the only proof.
    code = [
        path
        for path in claims[claim_id]["evidence"]
        if path.startswith(("flutter_app/", "ai_service/"))
    ]
    assert code, f"{claim_id} cites no code"


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_each_claim_records_when_it_was_checked(claims, claim_id):
    checked = date.fromisoformat(claims[claim_id]["last_checked"])
    assert date(2026, 11, 4) <= checked <= date.today()


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_each_claim_records_the_code_check_outcome(claims, claim_id):
    claim = claims[claim_id]
    assert claim["code_check"] in {"supported", "not_supported"}
    if claim["code_check"] == "not_supported":
        assert len(claim["code_note"]) > 20, "say what the code does instead"


def test_the_claims_the_code_does_not_back_are_the_known_ones(claims):
    # A change here is an owner ruling or a code change, so it has to be deliberate.
    held = {claim_id for claim_id, claim in claims.items() if claim["code_check"] != "supported"}
    assert held == NOT_BACKED_BY_CODE


def test_c09_has_no_bank_wording(claims):
    for key in ("meaning", "wording_ar", "wording_en"):
        assert not BANK_WORD.search(claims["C09"][key]), f"C09 {key} mentions a bank (D29)"


def test_c09_says_by_hand_in_both_languages(claims):
    assert "by hand" in claims["C09"]["wording_en"]
    assert "يدوي" in claims["C09"]["wording_ar"]


def test_c15_says_line_items_from_your_own_receipts(claims):
    english = claims["C15"]["wording_en"]
    assert "line items" in english
    assert "your own" in english
    assert "not the ZATCA QR" in english
    arabic = claims["C15"]["wording_ar"]
    assert "بنود" in arabic
    assert "فواتيرك" in arabic


def test_c21_calls_its_prices_illustrative_in_both_languages(claims):
    assert "illustrative" in claims["C21"]["wording_en"]
    assert "توضيحية" in claims["C21"]["wording_ar"]


def test_c01_treats_the_27th_as_a_changeable_default(claims):
    english = claims["C01"]["wording_en"]
    assert "default" in english
    assert "change" in english


@pytest.mark.parametrize("claim_id", CLAIM_IDS)
def test_no_claim_wording_names_the_brand(claims, claim_id):
    # Scripts carry tokens, and config fills them (G12).
    for key in ("wording_ar", "wording_en"):
        assert "قوام" not in claims[claim_id][key]
        assert "qawam" not in claims[claim_id][key].casefold()


@pytest.mark.parametrize("rejected_id", REJECTED_IDS)
def test_each_rejected_claim_has_samples_in_both_languages(rejected, rejected_id):
    row = rejected[rejected_id]
    assert row["samples_ar"], "no Arabic failing sample"
    assert row["samples_en"], "no English failing sample"
    assert all(ARABIC_LETTER.search(sample) for sample in row["samples_ar"])
    assert all(LATIN_LETTER.search(sample) for sample in row["samples_en"])


@pytest.mark.parametrize("rejected_id", REJECTED_IDS)
def test_each_rejected_claim_names_the_guardrail_the_spec_gives_it(rejected, rejected_id):
    assert set(rejected[rejected_id]["caught_by"]) == SPEC_CATCHERS[rejected_id]


def test_the_register_has_no_withdrawn_or_unknown_top_level_keys(register):
    assert set(register) == {"schema_version", "claims", "rejected_claims"}
