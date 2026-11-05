"""Dropped claims stay out of everything that ends up on screen (spec Section 12, D29, D32).

Seed topics are checked in `test_topics.py`. This covers the templates, their sample data, the
config and the asset lists: none may hold a rejected sample, a bank name or dropped wording.
"""

import json
from pathlib import Path

import pytest
import yaml

from content_engine.guardrails import check_text, lexicon_form, load_claims_register
from core.paths import ENGINE_ROOT, RAW_RECORDING_FOLDERS
from phone_capture.ingest import CHECKLIST

STUDIO = ENGINE_ROOT / "remotion_studio"
SCANNED_RULES = {"G4", "G5", "G11", "G19", "G20", "G21", "G22"}
SAMPLES = [
    (row.id, sample)
    for row in load_claims_register().rejected
    for sample in (*row.samples_ar, *row.samples_en)
]


def _template_files() -> list[Path]:
    files = [*(STUDIO / "src").rglob("*"), *(STUDIO / "test_data").rglob("*")]
    return sorted(path for path in files if path.suffix in {".ts", ".tsx"})


def _data_files() -> list[Path]:
    return [
        *sorted((STUDIO / "test_data").rglob("*.json")),
        STUDIO / "props.schema.json",
        ENGINE_ROOT / "assets" / "branding" / "brand_tokens.json",
    ]


TEMPLATES = _template_files()
DATA_FILES = _data_files()


def _values(node) -> list[str]:
    """The text a data file holds. Its keys are field names, which a viewer never reads."""
    if isinstance(node, str):
        return [node]
    if isinstance(node, dict):
        node = list(node.values())
    if isinstance(node, list):
        return [text for item in node for text in _values(item)]
    return []


def _rule_problems(lines: list[str], *, in_code: bool) -> list[str]:
    found = []
    for line in lines:
        for finding in check_text(line).hard_failures:
            # In code, 30% is a layout value such as `top: '30%'`, and a dotted word is a file
            # path or a property, so neither G2 nor the web address check reads code.
            is_web_address = "no link of any kind" in finding.message
            if in_code and (finding.rule == "G2" or is_web_address):
                continue
            if finding.rule in SCANNED_RULES or "30%" in finding.message:
                found.append(f"{finding.rule} in {line.strip()[:80]!r}: {finding.message}")
    return found


def _problems_in(text: str, *, in_code: bool = False) -> list[str]:
    form = lexicon_form(text)
    found = [row_id for row_id, sample in SAMPLES if lexicon_form(sample) in form]
    return found + _rule_problems(text.splitlines(), in_code=in_code)


def _name(path: Path) -> str:
    return path.relative_to(ENGINE_ROOT).as_posix()


def test_the_scan_covers_the_templates_and_the_asset_lists():
    assert {"ReelShell.tsx", "DailyTip.tsx", "IllustrativePricesLabel.tsx"} <= {
        path.name for path in TEMPLATES
    }
    assert "sample_basket_ar.json" in {path.name for path in DATA_FILES}
    assert CHECKLIST
    assert RAW_RECORDING_FOLDERS


@pytest.mark.parametrize("path", TEMPLATES, ids=_name)
def test_no_template_holds_a_dropped_claim_or_a_bank_name(path):
    assert _problems_in(path.read_bytes().decode("utf-8"), in_code=True) == []


@pytest.mark.parametrize("path", DATA_FILES, ids=_name)
def test_no_sample_or_token_file_holds_a_dropped_claim_or_a_bank_name(path):
    data = json.loads(path.read_bytes().decode("utf-8"))
    assert _problems_in("\n".join(_values(data))) == []


def test_no_config_value_holds_a_dropped_claim_or_a_bank_name():
    config = yaml.safe_load((ENGINE_ROOT / "config.yaml").read_bytes().decode("utf-8"))
    values = _values(config)
    assert len(values) > 10
    assert _problems_in("\n".join(values)) == []


def test_the_capture_checklist_holds_no_dropped_claim():
    assert _problems_in("\n".join(CHECKLIST)) == []


def test_no_asset_folder_is_named_for_a_dropped_claim_or_a_bank():
    for folder in RAW_RECORDING_FOLDERS:
        assert _problems_in(folder.replace("_", " ")) == [], folder


@pytest.mark.parametrize(
    "planted",
    [
        "Save 30% with this",
        "Tracking your Al Rajhi and STC Pay balances",
        "Link in bio",
        "Done in 3 clicks",
        "Payday 27th HUD",
        "Track prices with the QR",
    ],
)
def test_the_scan_would_catch_a_dropped_claim(planted):
    assert _problems_in(planted)


@pytest.mark.parametrize(
    "planted", ["<Text>Your Al Rajhi balance</Text>", "<p>Done in 3 clicks</p>"]
)
def test_the_scan_would_catch_a_dropped_claim_in_a_template(planted):
    assert _problems_in(planted, in_code=True)
