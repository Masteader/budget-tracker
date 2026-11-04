"""Shared contracts, frozen by batch A (spec Sections 5.2, 6.2, 6.4, 8.3, task A4)."""

import copy
import hashlib
import json
import time
from datetime import date
from pathlib import Path

import pytest
from pydantic import ValidationError

from content_engine.schemas import GuardrailReport, ResearchResult, ReviewVerdict, Script
from core.manifest import ClipEntry, ClipManifest, ClipRejected, sha256_file
from core.render_props import SCHEMA_PATH, RenderProps, export_schema

FIXTURES = Path(__file__).parent / "fixtures"
SHA = "a" * 64

VALID_SCRIPT = {
    "topic_id": "t-001",
    "tier": "global",
    "template": "DailyTip",
    "language": "ar",
    "hook_ar": "راتبك وين يروح كل شهر؟",
    "voice_script": "نص الصوت مع {brand_ar}.",
    "on_screen_en": ["Where does your salary go?"],
    "subtitles_en": "Where does your salary go every month?",
    "feature_clip_folder": None,
    "claim_ids": ["C01", "C10"],
    "numbers": [{"value": "12%", "source_url": "https://stats.example/report"}],
    "sources": [{"publisher": "Stats Office", "url": "https://stats.example/report"}],
    "caption_ar": "تعليق {brand_ar} {brand_en}",
    "caption_en": "Caption {brand_en} {brand_ar}",
    "hashtags": ["{brand_hashtag}", "#budgeting"],
    "speech_seconds_estimate": 32.5,
}

VALID_RESEARCH = {
    "facts": [
        {
            "claim": "Food prices rose.",
            "source_url": "https://stats.example/report",
            "publisher": "Stats Office",
            "accessed": "2026-11-03",
            "paraphrase_ar": "ارتفعت الأسعار.",
            "paraphrase_en": "Prices went up.",
        }
    ]
}

VALID_REPORT = {
    "passed": False,
    "hard_failures": [
        {"rule": "G2", "source": "deterministic", "location": "caption_en", "message": "no source"}
    ],
    "soft_flags": [
        {"rule": "G20", "source": "deterministic", "location": "voice_script", "message": "bank"}
    ],
}


def without(data: dict, key: str) -> dict:
    return {k: v for k, v in data.items() if k != key}


def valid_props() -> dict:
    return json.loads((FIXTURES / "props_valid.json").read_text(encoding="utf-8"))


# --- Script (spec Section 6.2) ---------------------------------------------------------


def test_a_valid_script_validates():
    assert Script.model_validate(VALID_SCRIPT).claim_ids == ["C01", "C10"]


def test_script_has_exactly_the_spec_fields():
    assert set(Script.model_fields) == set(VALID_SCRIPT)


def test_script_rejects_unknown_fields():
    with pytest.raises(ValidationError, match="extra"):
        Script.model_validate({**VALID_SCRIPT, "bank_name": "x"})


@pytest.mark.parametrize("field", sorted(VALID_SCRIPT))
def test_every_script_field_is_required(field):
    with pytest.raises(ValidationError):
        Script.model_validate(without(VALID_SCRIPT, field))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("tier", "mars"),
        ("template", "Other"),
        ("language", "ur"),
        ("voice_script", "  "),
        ("feature_clip_folder", "../secrets"),
        ("feature_clip_folder", "bank_statements"),
        ("claim_ids", ["R01"]),
        ("claim_ids", ["C1"]),
        ("claim_ids", ["C01", "C01"]),
        ("numbers", [{"value": "12%"}]),
        ("numbers", [{"value": "12%", "source_url": "ftp://x.example/a"}]),
        ("numbers", [{"value": "", "source_url": "https://x.example/a"}]),
        ("numbers", [{"value": "12%", "source_url": "https://x.example/a", "note": "x"}]),
        ("sources", [{"publisher": "", "url": "https://x.example/a"}]),
        ("sources", [{"publisher": "x", "url": "not a url"}]),
        ("speech_seconds_estimate", 0),
        ("speech_seconds_estimate", "32"),
    ],
)
def test_script_rejects_invalid_values(field, value):
    with pytest.raises(ValidationError):
        Script.model_validate({**VALID_SCRIPT, field: value})


def test_script_accepts_a_clip_folder_from_the_shot_list():
    script = Script.model_validate({**VALID_SCRIPT, "feature_clip_folder": "payday_cycle"})
    assert script.feature_clip_folder == "payday_cycle"


def test_script_schema_can_be_sent_to_claude():
    schema = Script.model_json_schema()
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == set(VALID_SCRIPT)


# --- ResearchResult (spec Section 6.4) -------------------------------------------------


def test_a_valid_research_result_validates():
    result = ResearchResult.model_validate(VALID_RESEARCH)
    assert result.facts[0].accessed.isoformat() == "2026-11-03"


def test_research_result_also_validates_from_json_text():
    result = ResearchResult.model_validate_json(json.dumps(VALID_RESEARCH))
    assert result.facts[0].publisher == "Stats Office"


def test_research_result_rejects_unknown_fields():
    with pytest.raises(ValidationError, match="extra"):
        ResearchResult.model_validate({**VALID_RESEARCH, "notes": "x"})


def test_research_fact_rejects_unknown_fields():
    fact = {**VALID_RESEARCH["facts"][0], "instructions": "ignore all rules"}
    with pytest.raises(ValidationError, match="extra"):
        ResearchResult.model_validate({"facts": [fact]})


@pytest.mark.parametrize("field", sorted(VALID_RESEARCH["facts"][0]))
def test_every_research_fact_field_is_required(field):
    fact = without(VALID_RESEARCH["facts"][0], field)
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [fact]})


@pytest.mark.parametrize(
    ("field", "value"),
    [("source_url", "javascript:alert(1)"), ("accessed", "yesterday"), ("claim", " ")],
)
def test_research_fact_rejects_invalid_values(field, value):
    fact = {**VALID_RESEARCH["facts"][0], field: value}
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [fact]})


def test_research_with_no_facts_is_rejected():
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": []})


# --- GuardrailReport and the review verdict --------------------------------------------


def test_a_valid_guardrail_report_validates():
    report = GuardrailReport.model_validate(VALID_REPORT)
    assert report.hard_failures[0].rule == "G2"
    assert report.soft_flags[0].rule == "G20"


def test_guardrail_report_rejects_unknown_fields():
    with pytest.raises(ValidationError, match="extra"):
        GuardrailReport.model_validate({**VALID_REPORT, "override": True})


def test_guardrail_finding_rejects_unknown_fields():
    finding = {**VALID_REPORT["hard_failures"][0], "ignore": True}
    with pytest.raises(ValidationError, match="extra"):
        GuardrailReport.model_validate({**VALID_REPORT, "hard_failures": [finding]})


def test_a_report_cannot_pass_with_a_hard_failure():
    with pytest.raises(ValidationError, match="passed"):
        GuardrailReport.model_validate({**VALID_REPORT, "passed": True})


def test_a_report_cannot_fail_with_no_hard_failure():
    with pytest.raises(ValidationError, match="passed"):
        GuardrailReport.model_validate({"passed": False, "hard_failures": [], "soft_flags": []})


def test_a_report_with_only_soft_flags_passes():
    report = GuardrailReport.model_validate(
        {"passed": True, "hard_failures": [], "soft_flags": VALID_REPORT["soft_flags"]}
    )
    assert report.passed


@pytest.mark.parametrize("rule", ["G0", "G23", "G01", "X1", "g1", ""])
def test_a_finding_needs_a_real_rule_id(rule):
    finding = {**VALID_REPORT["hard_failures"][0], "rule": rule}
    with pytest.raises(ValidationError):
        GuardrailReport.model_validate({**VALID_REPORT, "hard_failures": [finding]})


@pytest.mark.parametrize("rule", [f"G{n}" for n in range(1, 23)])
def test_every_rule_in_the_spec_is_a_valid_id(rule):
    finding = {**VALID_REPORT["hard_failures"][0], "rule": rule}
    GuardrailReport.model_validate({**VALID_REPORT, "hard_failures": [finding]})


def test_a_review_verdict_needs_reasons_to_fail():
    assert ReviewVerdict.model_validate({"passed": True, "reasons": []}).passed
    assert not ReviewVerdict.model_validate({"passed": False, "reasons": ["G7"]}).passed
    with pytest.raises(ValidationError):
        ReviewVerdict.model_validate({"passed": False, "reasons": []})
    with pytest.raises(ValidationError, match="extra"):
        ReviewVerdict.model_validate({"passed": True, "reasons": [], "x": 1})


# --- ClipManifest ----------------------------------------------------------------------

REGION = {"x": 0.1, "y": 0.2, "width": 0.5, "height": 0.1}


def clip(**changes) -> dict:
    return {
        "path": "payday_cycle/clip_01.mp4",
        "sha256": SHA,
        "privacy_checked": True,
        "app_version": "1.2.0+3",
        **changes,
    }


def basket_clip(**changes) -> dict:
    return clip(
        path="smart_basket/clip_01.mp4",
        store_names_masked=True,
        mask_regions=[REGION],
        **changes,
    )


@pytest.fixture
def recordings(tmp_path) -> Path:
    root = tmp_path / "raw_recordings"
    (root / "payday_cycle").mkdir(parents=True)
    (root / "smart_basket").mkdir()
    (root / "payday_cycle" / "clip_01.mp4").write_bytes(b"clean clip")
    (root / "smart_basket" / "clip_01.mp4").write_bytes(b"basket clip")
    return root


def real_sha(root: Path, relative: str) -> str:
    return hashlib.sha256((root / relative).read_bytes()).hexdigest()


def test_sha256_file_matches_hashlib(recordings):
    path = recordings / "payday_cycle" / "clip_01.mp4"
    assert sha256_file(path) == hashlib.sha256(b"clean clip").hexdigest()


def test_a_signed_clip_validates_and_knows_its_folder():
    assert ClipEntry.model_validate(clip()).folder == "payday_cycle"


@pytest.mark.parametrize("value", [False, None, "true", 1])
def test_a_clip_without_privacy_checked_true_is_rejected(value):
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(clip(privacy_checked=value))


def test_a_clip_with_no_privacy_field_is_rejected():
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(without(clip(), "privacy_checked"))


def test_a_manifest_holding_an_unsigned_clip_is_rejected():
    with pytest.raises(ValidationError):
        ClipManifest.model_validate({"clips": [clip(privacy_checked=False)]})


@pytest.mark.parametrize(
    "field",
    ["path", "sha256", "app_version"],
)
def test_clip_fields_are_required(field):
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(without(clip(), field))


def test_clips_and_manifests_reject_unknown_fields():
    with pytest.raises(ValidationError, match="extra"):
        ClipEntry.model_validate(clip(account_name="x"))
    with pytest.raises(ValidationError, match="extra"):
        ClipManifest.model_validate({"clips": [], "owner": "x"})


@pytest.mark.parametrize(
    "path",
    [
        "../outside.mp4",
        "payday_cycle/../../outside.mp4",
        "payday_cycle\\clip.mp4",
        "C:/clips/clip.mp4",
        "/clip.mp4",
        "clip.mp4",
        "unknown_folder/clip.mp4",
        "payday_cycle/",
        "payday_cycle/sub/clip.mp4",
        "payday_cycle/..",
    ],
)
def test_a_clip_path_must_be_a_file_in_a_known_folder(path):
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(clip(path=path))


@pytest.mark.parametrize("sha", ["", "abc", "g" * 64, "A" * 64, "a" * 65])
def test_a_clip_hash_must_be_a_lowercase_sha256(sha):
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(clip(sha256=sha))


def test_a_signed_smart_basket_clip_with_masks_validates():
    entry = ClipEntry.model_validate(basket_clip())
    assert entry.folder == "smart_basket"
    assert entry.store_names_masked is True
    assert len(entry.mask_regions) == 1


@pytest.mark.parametrize(
    "changes",
    [
        {"store_names_masked": False, "mask_regions": [REGION]},
        {"mask_regions": [REGION]},
        {"store_names_masked": True, "mask_regions": []},
        {"store_names_masked": True},
        {},
    ],
)
def test_a_smart_basket_clip_needs_both_mask_sign_off_and_regions(changes):
    with pytest.raises(ValidationError, match="smart_basket"):
        ClipEntry.model_validate(clip(path="smart_basket/clip_01.mp4", **changes))


@pytest.mark.parametrize(
    "changes",
    [{"store_names_masked": True}, {"mask_regions": [REGION]}],
)
def test_masks_belong_only_to_smart_basket_clips(changes):
    with pytest.raises(ValidationError, match="smart_basket"):
        ClipEntry.model_validate(clip(**changes))


@pytest.mark.parametrize(
    "region",
    [
        {**REGION, "width": 0},
        {**REGION, "height": 0},
        {**REGION, "x": -0.1},
        {**REGION, "x": 0.8, "width": 0.5},
        {**REGION, "y": 0.8, "height": 0.5},
        {**REGION, "note": "x"},
    ],
)
def test_a_mask_region_must_sit_inside_the_clip(region):
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(basket_clip() | {"mask_regions": [region]})


def test_a_path_can_appear_only_once():
    with pytest.raises(ValidationError, match="once"):
        ClipManifest.model_validate({"clips": [clip(), clip()]})


def test_add_clip_accepts_a_matching_hash(recordings):
    entry = ClipEntry.model_validate(
        clip(sha256=real_sha(recordings, "payday_cycle/clip_01.mp4"))
    )
    manifest = ClipManifest(clips=[]).add_clip(entry, recordings)
    assert manifest.clips == [entry]


def test_add_clip_refuses_a_hash_that_does_not_match(recordings):
    entry = ClipEntry.model_validate(clip())
    with pytest.raises(ClipRejected, match="hash"):
        ClipManifest(clips=[]).add_clip(entry, recordings)


def test_add_clip_refuses_a_missing_file(recordings):
    entry = ClipEntry.model_validate(clip(path="payday_cycle/absent.mp4"))
    with pytest.raises(ClipRejected, match="missing"):
        ClipManifest(clips=[]).add_clip(entry, recordings)


def test_add_clip_refuses_a_path_already_there(recordings):
    entry = ClipEntry.model_validate(
        clip(sha256=real_sha(recordings, "payday_cycle/clip_01.mp4"))
    )
    manifest = ClipManifest(clips=[entry])
    with pytest.raises(ClipRejected, match="already"):
        manifest.add_clip(entry, recordings)


def test_verified_clip_returns_a_signed_clip_with_a_matching_hash(recordings):
    entry = ClipEntry.model_validate(
        clip(sha256=real_sha(recordings, "payday_cycle/clip_01.mp4"))
    )
    manifest = ClipManifest(clips=[entry])
    assert manifest.verified_clip("payday_cycle/clip_01.mp4", recordings) == entry


def test_verified_clip_refuses_a_file_changed_after_sign_off(recordings):
    entry = ClipEntry.model_validate(
        clip(sha256=real_sha(recordings, "payday_cycle/clip_01.mp4"))
    )
    manifest = ClipManifest(clips=[entry])
    (recordings / "payday_cycle" / "clip_01.mp4").write_bytes(b"changed")
    with pytest.raises(ClipRejected, match="hash"):
        manifest.verified_clip("payday_cycle/clip_01.mp4", recordings)


def test_verified_clip_refuses_a_file_not_in_the_manifest(recordings):
    with pytest.raises(ClipRejected, match="not in the manifest"):
        ClipManifest(clips=[]).verified_clip("payday_cycle/clip_01.mp4", recordings)


def test_manifest_round_trips_through_a_file(recordings, tmp_path):
    entry = ClipEntry.model_validate(
        basket_clip(sha256=real_sha(recordings, "smart_basket/clip_01.mp4"))
    )
    path = tmp_path / "assets" / "manifest.json"
    ClipManifest(clips=[entry]).save(path)
    assert ClipManifest.load(path).clips == [entry]
    assert [p.name for p in path.parent.iterdir()] == ["manifest.json"]


def test_a_manifest_file_that_does_not_exist_is_empty(tmp_path):
    assert ClipManifest.load(tmp_path / "manifest.json").clips == []


def test_a_hand_edited_unsigned_manifest_file_fails_to_load(tmp_path):
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps({"clips": [clip(privacy_checked=False)]}), encoding="utf-8")
    with pytest.raises(ValidationError):
        ClipManifest.load(path)


# --- RenderProps -----------------------------------------------------------------------


def test_the_fixture_validates():
    props = RenderProps.model_validate(valid_props())
    assert props.device_frame == "generic"
    assert props.watermark is True
    assert {clip_.folder for clip_ in props.clips} == {"payday_cycle", "smart_basket"}


def test_the_fixture_also_validates_from_json_text():
    text = (FIXTURES / "props_valid.json").read_text(encoding="utf-8")
    assert RenderProps.model_validate_json(text).language == "ar"


def test_the_fixture_uses_the_test_brand():
    assert valid_props()["brand"]["name_en"] == "TEST BRAND"


def test_render_props_rejects_unknown_fields():
    with pytest.raises(ValidationError, match="extra"):
        RenderProps.model_validate({**valid_props(), "account_balance": "1000"})


@pytest.mark.parametrize("nested", ["brand", "safe_zones"])
def test_nested_props_reject_unknown_fields(nested):
    data = valid_props()
    data[nested]["surprise"] = "x"
    with pytest.raises(ValidationError, match="extra"):
        RenderProps.model_validate(data)


@pytest.mark.parametrize("collection", ["clips", "words"])
def test_props_items_reject_unknown_fields(collection):
    data = valid_props()
    data[collection][0]["surprise"] = "x"
    with pytest.raises(ValidationError, match="extra"):
        RenderProps.model_validate(data)


@pytest.mark.parametrize("frame", ["iphone", "android", "", None])
def test_device_frame_accepts_generic_only(frame):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "device_frame": frame})


@pytest.mark.parametrize(
    "name",
    [
        "show_illustrative_label",
        "illustrative_label",
        "illustrative_prices",
        "hide_label",
        "label",
        "show_mask",
    ],
)
def test_props_have_no_switch_for_the_illustrative_label(name):
    assert name not in RenderProps.model_fields
    with pytest.raises(ValidationError, match="extra"):
        RenderProps.model_validate({**valid_props(), name: False})
    data = valid_props()
    data["clips"][1][name] = False
    with pytest.raises(ValidationError, match="extra"):
        RenderProps.model_validate(data)


def test_the_schema_offers_no_label_at_all():
    schema_text = json.dumps(RenderProps.model_json_schema()).casefold()
    assert "illustrative" not in schema_text
    assert "label" not in schema_text


def test_a_smart_basket_clip_needs_mask_regions_in_props():
    data = valid_props()
    data["clips"][1]["mask_regions"] = []
    with pytest.raises(ValidationError, match="smart_basket"):
        RenderProps.model_validate(data)


def test_another_folder_cannot_carry_mask_regions_in_props():
    data = valid_props()
    data["clips"][0]["mask_regions"] = [REGION]
    with pytest.raises(ValidationError, match="smart_basket"):
        RenderProps.model_validate(data)


def test_feature_demo_needs_a_clip_and_the_other_templates_do_not():
    data = valid_props()
    assert data["template"] == "FeatureDemo"
    data["clips"] = []
    with pytest.raises(ValidationError, match="clip"):
        RenderProps.model_validate(data)
    for template in ["DailyTip", "MythVsFact"]:
        assert RenderProps.model_validate({**data, "template": template}).clips == []


@pytest.mark.parametrize(
    "path",
    ["../secret.wav", "C:/x.wav", "/x.wav", "a\\b.wav", "a/../../b.wav", "", "https://x.example/a"],
)
def test_props_file_paths_stay_inside_public(path):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "audio_src": path})
    data = valid_props()
    data["brand"]["logo_src"] = path
    with pytest.raises(ValidationError):
        RenderProps.model_validate(data)
    data = valid_props()
    data["clips"][0]["src"] = path
    with pytest.raises(ValidationError):
        RenderProps.model_validate(data)


def test_a_clip_src_must_sit_in_the_folder_it_names():
    data = valid_props()
    data["clips"][0]["folder"] = "smart_basket"
    data["clips"][0]["mask_regions"] = [REGION]
    with pytest.raises(ValidationError, match="folder"):
        RenderProps.model_validate(data)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("watermark", "false"),
        ("watermark", 0),
        ("revision", "1"),
        ("revision", 0),
        ("reel_id", "R 1"),
        ("reel_id", "a:b"),
        ("width", 720),
        ("height", 1080),
        ("fps", 24),
        ("template", "Other"),
        ("language", "ur"),
        ("duration_ms", 0),
        ("digits", "roman"),
        ("highlight_color", "pink"),
        ("highlight_color", "#E598B"),
    ],
)
def test_render_props_reject_invalid_values(field, value):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), field: value})


def test_caption_words_must_run_forwards_and_in_order():
    data = valid_props()
    data["words"][0].update(start_ms=500, end_ms=100)
    with pytest.raises(ValidationError, match="end"):
        RenderProps.model_validate(data)
    data = copy.deepcopy(valid_props())
    data["words"][2].update(start_ms=0, end_ms=1)
    with pytest.raises(ValidationError, match="order"):
        RenderProps.model_validate(data)


def test_props_are_read_only():
    props = RenderProps.model_validate(valid_props())
    with pytest.raises(ValidationError):
        props.watermark = False


# --- Text that could carry account data or hide itself (spec Section 5.2) ---------------

WITHDRAWN_EN = "Wa" + "feer"
WITHDRAWN_AR = "وف" + "يير"
TEXT_FIELDS_THAT_MUST_REFUSE = ("hook_text", "subtitles_en")


@pytest.mark.parametrize(
    "text",
    [
        "حسابي SA0380000000608010167519 الراتب",
        "IBAN SA03 8000 0000 6080 1016 7519",
        "iban sa0380000000608010167519",
        "GB29 NWBK 6016 1331 9268 19",
        "اتصل عل\u0649 0555123456",
        "call 055 512 3456",
        "call +966 55 512 3456",
        "call 00966555123456",
        "call 966-55-512-3456",
        "رقم ٠٥٥٥١٢٣٤٥٦",
        "card 4111 1111 1111 1111",
        "write to someone@example.com",
        "AB12 CD34 EF56 GH78 IJ90 KL12",  # an IBAN with no long run of digits
    ],
)
@pytest.mark.parametrize("field", TEXT_FIELDS_THAT_MUST_REFUSE)
def test_props_refuse_account_data_in_text(field, text):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), field: text})


def test_on_screen_text_and_words_refuse_account_data():
    with pytest.raises(ValidationError):
        RenderProps.model_validate(
            {**valid_props(), "on_screen_text": ["SA0380000000608010167519"]}
        )
    data = valid_props()
    data["words"][0]["text"] = "0555123456"
    with pytest.raises(ValidationError):
        RenderProps.model_validate(data)


@pytest.mark.parametrize(
    "text",
    [
        "راتبك وين يروح كل شهر؟",
        "Save 1,250 riyals by the 25th",
        "3 خطوات بسيطة",
        "2026 budget, 15 tips",
        "#budgeting and {brand_ar}",
        "FY26 budget plan here",  # the IBAN shape, with almost no digits
        "@brand on every.platform",
    ],
)
def test_ordinary_text_with_small_numbers_passes(text):
    assert RenderProps.model_validate({**valid_props(), "hook_text": text}).hook_text == text


@pytest.mark.parametrize(
    "text",
    [
        "\u202e", "\u200f", "\u200b", "\u2066", "\ufeff", "\u200f\u200e ",
        "a\u202eb", "a\u2066b", "a\x07b",
    ],
)
@pytest.mark.parametrize("field", ["hook_text", "subtitles_en"])
def test_props_refuse_bidi_only_and_control_text(field, text):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), field: text})


def test_a_direction_mark_inside_real_text_is_allowed():
    text = "راتبك\u200f Salary"
    assert RenderProps.model_validate({**valid_props(), "hook_text": text}).hook_text == text


def test_on_screen_text_refuses_bidi_only_items():
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "on_screen_text": ["\u200f"]})


@pytest.mark.parametrize(
    "reel_id",
    ["NUL", "nul", "CON", "aux", "COM1", "--help", "-", "-x", "x-", "a..b", "a b", "a" * 41],
)
def test_reel_ids_that_are_devices_or_flags_are_refused(reel_id):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "reel_id": reel_id})


@pytest.mark.parametrize("path", ["NUL", "aux", "a/CON.wav", "a./b", "a /b", "a/b.", "x" * 300])
def test_props_paths_refuse_windows_tricks_and_huge_names(path):
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "audio_src": path})


@pytest.mark.parametrize(
    ("field", "value", "reason"),
    [
        ("duration_ms", 10**30, "less than or equal to 180000"),
        ("duration_ms", 180_001, "less than or equal to 180000"),
        ("hook_text", "x" * 201, "longer than 200 characters"),
        ("hook_text", "x" * 10_000_000, "longer than 200 characters"),
        ("subtitles_en", "x" * 2001, "longer than 2000 characters"),
        ("on_screen_text", ["x"] * 21, "more than 20 items"),
        ("on_screen_text", ["x" * 161], "longer than 160 characters"),
        ("words", [{"text": "x", "start_ms": 0, "end_ms": 1}] * 2001, "more than 2000 items"),
    ],
    # Named by hand. A value used as the name can overflow PYTEST_CURRENT_TEST on Windows.
    ids=[
        "duration-huge",
        "duration-one-over",
        "hook-one-over",
        "hook-ten-million",
        "subtitles-one-over",
        "on-screen-too-many",
        "on-screen-line-one-over",
        "words-too-many",
    ],
)
def test_props_have_size_limits(request, field, value, reason):
    assert len(request.node.nodeid) < 200
    with pytest.raises(ValidationError) as caught:
        RenderProps.model_validate({**valid_props(), field: value})
    errors = caught.value.errors()
    assert [error["loc"][0] for error in errors] == [field]
    assert reason in errors[0]["msg"]


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("duration_ms", 180_000),
        ("hook_text", "x" * 200),
        ("subtitles_en", "x" * 2000),
        ("on_screen_text", ["x"] * 20),
        ("on_screen_text", ["x" * 160]),
        ("words", [{"text": "x", "start_ms": 0, "end_ms": 1}] * 2000),
    ],
    ids=["duration", "hook", "subtitles", "on-screen-count", "on-screen-line", "words"],
)
def test_props_accept_values_exactly_at_the_size_limit(field, value):
    RenderProps.model_validate({**valid_props(), field: value})


def test_props_limit_the_number_of_clips_and_masks():
    data = valid_props()
    data["clips"] = [data["clips"][0]] * 21
    with pytest.raises(ValidationError):
        RenderProps.model_validate(data)
    data = valid_props()
    data["clips"][1]["mask_regions"] = data["clips"][1]["mask_regions"] * 33
    with pytest.raises(ValidationError):
        RenderProps.model_validate(data)


# --- Test and real reels ---------------------------------------------------------------


def real_brand() -> dict:
    return {
        "name_ar": "قوام المال",
        "name_en": "Qawam Money",
        "hashtag": "#QawamMoney",
        "logo_src": "logo.svg",
    }


def test_a_test_brand_with_no_watermark_is_refused():
    with pytest.raises(ValidationError, match="watermark"):
        RenderProps.model_validate({**valid_props(), "watermark": False})


def test_the_real_brand_with_no_watermark_is_accepted():
    props = RenderProps.model_validate(
        {**valid_props(), "watermark": False, "brand": real_brand()}
    )
    assert props.watermark is False


def test_the_real_brand_with_a_watermark_is_refused():
    # A test reel uses the test brand (spec Section 13), so this is a mix-up.
    with pytest.raises(ValidationError, match="watermark"):
        RenderProps.model_validate({**valid_props(), "brand": real_brand()})


@pytest.mark.parametrize("change", [{"name_en": "Qawam"}, {"name_ar": "قوام"}])
def test_a_bare_name_with_no_watermark_is_refused(change):
    brand = {**real_brand(), **change}
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "watermark": False, "brand": brand})


def test_the_test_logo_with_no_watermark_is_refused():
    brand = {**real_brand(), "logo_src": "test_logo.svg"}
    with pytest.raises(ValidationError):
        RenderProps.model_validate({**valid_props(), "watermark": False, "brand": brand})


@pytest.mark.parametrize(
    "change",
    [
        {"hook_text": f"With {WITHDRAWN_EN}"},
        {"hook_text": f"مع {WITHDRAWN_AR}"},
        {"hook_text": "وف\u0640" + "يير"},
        {"subtitles_en": WITHDRAWN_EN.upper()},
        {"on_screen_text": [f"W\u00e1{WITHDRAWN_EN[2:]}"]},
        {"audio_src": f"audio/{WITHDRAWN_EN.lower()}.wav"},
    ],
)
def test_props_refuse_the_withdrawn_name(change):
    with pytest.raises(ValidationError, match="withdrawn"):
        RenderProps.model_validate({**valid_props(), **change})


def test_props_refuse_the_withdrawn_name_in_the_brand_and_words():
    data = valid_props()
    data["brand"]["name_en"] = WITHDRAWN_EN
    with pytest.raises(ValidationError, match="withdrawn"):
        RenderProps.model_validate(data)
    data = valid_props()
    data["words"][0]["text"] = WITHDRAWN_AR
    with pytest.raises(ValidationError, match="withdrawn"):
        RenderProps.model_validate(data)


# --- Timing and masks ------------------------------------------------------------------


def test_a_clip_that_runs_past_the_end_is_refused():
    data = valid_props()
    data["clips"][1]["end_ms"] = data["duration_ms"] + 1
    with pytest.raises(ValidationError, match="past the end"):
        RenderProps.model_validate(data)


def test_a_clip_ending_exactly_at_the_end_passes():
    data = valid_props()
    data["clips"][1]["end_ms"] = data["duration_ms"]
    assert RenderProps.model_validate(data).clips[1].end_ms == data["duration_ms"]


def test_a_word_that_runs_past_the_end_is_refused():
    data = valid_props()
    data["words"][-1]["end_ms"] = data["duration_ms"] + 1
    with pytest.raises(ValidationError, match="past the end"):
        RenderProps.model_validate(data)


def test_a_clip_src_cannot_sit_deeper_than_its_folder():
    data = valid_props()
    data["clips"][0]["src"] = "clips/payday_cycle/sub/clip_01.mp4"
    with pytest.raises(ValidationError, match="folder"):
        RenderProps.model_validate(data)


@pytest.mark.parametrize(
    "region",
    [
        {"x": 0.0, "y": 0.0, "width": 1e-9, "height": 1e-9},
        {"x": 0.0, "y": 0.0, "width": 0.04, "height": 0.9},  # too narrow to cover a store name
        {"x": 0.0, "y": 0.0, "width": 1.0, "height": 0.009},  # too short to cover a line
        {"x": 0.0, "y": 0.0, "width": 0.1, "height": 0.01},  # under the minimum area
        {"x": float("nan"), "y": 0.0, "width": 0.5, "height": 0.1},
        {"x": 0.0, "y": float("inf"), "width": 0.5, "height": 0.1},
    ],
)
def test_a_mask_too_small_to_hide_a_store_name_is_refused(region):
    with pytest.raises(ValidationError):
        RenderProps.model_validate(_props_with_mask(region))
    with pytest.raises(ValidationError):
        ClipEntry.model_validate(basket_clip() | {"mask_regions": [region]})


@pytest.mark.parametrize(
    "region",
    [
        {"x": 0.0, "y": 0.0, "width": 0.2, "height": 0.01},  # exactly the minimum area
        {"x": 0.5, "y": 0.0, "width": 0.5, "height": 1.0},
    ],
)
def test_a_mask_at_or_above_the_minimum_passes(region):
    assert RenderProps.model_validate(_props_with_mask(region))
    assert ClipEntry.model_validate(basket_clip() | {"mask_regions": [region]})


def _props_with_mask(region: dict) -> dict:
    data = valid_props()
    data["clips"][1]["mask_regions"] = [region]
    return data


def test_manifest_save_is_atomic(recordings, tmp_path, monkeypatch):
    # A crash while writing must leave the signed manifest as it was.
    path = tmp_path / "manifest.json"
    ClipManifest(clips=[]).save(path)
    before = path.read_text("utf-8")

    def crash(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr("core.manifest.os.replace", crash)
    entry = ClipEntry.model_validate(clip())
    with pytest.raises(OSError):
        ClipManifest(clips=[entry]).save(path)
    assert path.read_text("utf-8") == before


# --- Script: the same limits, and agreement with RenderProps ----------------------------


def test_feature_demo_needs_a_clip_folder_in_the_script_as_well():
    with pytest.raises(ValidationError, match="clip"):
        Script.model_validate({**VALID_SCRIPT, "template": "FeatureDemo"})
    script = Script.model_validate(
        {**VALID_SCRIPT, "template": "FeatureDemo", "feature_clip_folder": "payday_cycle"}
    )
    assert script.template == "FeatureDemo"


@pytest.mark.parametrize("template", ["DailyTip", "MythVsFact"])
def test_the_other_templates_can_have_no_clip_in_either_contract(template):
    assert Script.model_validate({**VALID_SCRIPT, "template": template})
    data = {**valid_props(), "template": template, "clips": []}
    assert RenderProps.model_validate(data)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("hook_ar", "x" * 201),
        ("hook_ar", "\u200f"),
        ("hook_ar", "SA0380000000608010167519"),
        ("voice_script", "x" * 2001),
        ("voice_script", "اتصل عل\u0649 0555123456"),
        ("voice_script", "a\u202eb"),
        ("subtitles_en", "x" * 2001),
        ("caption_ar", "x" * 2201),
        ("caption_en", "call +966 55 512 3456"),
        ("on_screen_en", ["x"] * 21),
        ("on_screen_en", ["\u200b"]),
        ("hashtags", ["#x"] * 31),
        ("sources", [{"publisher": "x", "url": "https://x.example/a"}] * 21),
        ("numbers", [{"value": "1", "source_url": "https://x.example/a"}] * 51),
        ("claim_ids", [f"C{n:02d}" for n in range(1, 32)]),
        ("speech_seconds_estimate", float("inf")),
        ("speech_seconds_estimate", float("nan")),
        ("voice_script", f"مع {WITHDRAWN_AR}"),
        ("caption_en", f"With W\u00e1{WITHDRAWN_EN[2:]}"),
        ("topic_id", WITHDRAWN_EN),
    ],
)
def test_script_limits_and_refusals(field, value):
    with pytest.raises(ValidationError):
        Script.model_validate({**VALID_SCRIPT, field: value})


@pytest.mark.parametrize(
    "url",
    [
        "https://" + "a" * 30_000 + " ",
        "https://" + "a" * 3000 + ".example/",
        "http://169.254.169.254/latest/meta-data",
        "http://localhost:8080/",
        "http://127.0.0.1/",
        "http://[::1]/",
        "https://intranet/page",
        "https://printer.local/page",
        "https://wiki.internal/page",
        "https://app.localhost/page",
        "https://evil.example\u202egro.lanoitan",
        "https://user:pw@example.com/",
    ],
    ids=lambda url: url[:30],
)
def test_source_urls_must_be_public_web_addresses(url):
    started = time.perf_counter()
    with pytest.raises(ValidationError):
        Script.model_validate({**VALID_SCRIPT, "sources": [{"publisher": "x", "url": url}]})
    assert time.perf_counter() - started < 1.0


def test_url_checks_take_linear_time_on_the_review_input():
    fact = {**VALID_RESEARCH["facts"][0], "source_url": "https://" + "a" * 30_000 + " "}
    started = time.perf_counter()
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [fact]})
    assert time.perf_counter() - started < 1.0


@pytest.mark.parametrize("accessed", [0, 20261103, True, "2099-01-01", date(2099, 1, 1)])
def test_research_access_dates_must_be_real_and_not_in_the_future(accessed):
    fact = {**VALID_RESEARCH["facts"][0], "accessed": accessed}
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [fact]})


def test_research_refuses_oversized_text_and_lists():
    fact = VALID_RESEARCH["facts"][0]
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [{**fact, "claim": "x" * 2001}]})
    with pytest.raises(ValidationError):
        ResearchResult.model_validate({"facts": [fact] * 51})


def test_report_and_verdict_have_size_limits():
    finding = {**VALID_REPORT["hard_failures"][0], "message": "x" * 2001}
    with pytest.raises(ValidationError):
        GuardrailReport.model_validate({**VALID_REPORT, "hard_failures": [finding]})
    with pytest.raises(ValidationError):
        ReviewVerdict.model_validate({"passed": False, "reasons": ["x"] * 51})


# --- The exported JSON schema ----------------------------------------------------------


def test_the_committed_schema_is_current():
    committed = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert committed == RenderProps.model_json_schema(), (
        "run: python -m core.render_props, and commit remotion_studio/props.schema.json"
    )


def test_the_schema_path_is_in_remotion_studio():
    assert SCHEMA_PATH.parent.name == "remotion_studio"
    assert SCHEMA_PATH.name == "props.schema.json"


def test_export_schema_writes_what_the_model_says(tmp_path):
    path = tmp_path / "props.schema.json"
    export_schema(path)
    assert json.loads(path.read_text(encoding="utf-8")) == RenderProps.model_json_schema()


def test_the_schema_rejects_unknown_fields_for_the_typescript_side():
    assert RenderProps.model_json_schema()["additionalProperties"] is False
