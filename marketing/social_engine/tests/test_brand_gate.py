"""The launch gate at the function level ("Brand gate" row, spec Sections 12 and 13, task A2)."""

import copy
from datetime import date, timedelta

import pytest
import yaml

from core.brand_gate import (
    approval_allowed,
    approve_button_allowed,
    brand_display,
    brand_for_reel,
    gate_failures,
    is_gate_met,
    publish_allowed,
    render_decision,
)
from core.config import DEFAULT_CONFIG_PATH, EngineConfig, load_config

CALLERS_AFTER_RENDER = [approve_button_allowed, approval_allowed, publish_allowed]

NAME_CHOSEN_ON = date(2026, 11, 3)  # decision D1 in the spec


def shipped_data() -> dict:
    with DEFAULT_CONFIG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def complete_live_data() -> dict:
    data = shipped_data()
    data["engine"]["mode"] = "live"
    data["brand"]["logo_path"] = "assets/branding/approved_logo.svg"
    data["brand"]["handles"] = {
        "instagram": "@qawam_money",
        "facebook": "qawam.money",
        "tiktok": "@qawammoney",
        "youtube": "@qawammoney",
    }
    data["brand"]["hashtags"] = ["#QawamMoney", "#قوام_المال"]
    data["brand"]["clearance"] = {
        "google_play_checked_on": NAME_CHOSEN_ON,
        "app_store_checked_on": NAME_CHOSEN_ON,
        "saip_checked_on": NAME_CHOSEN_ON,
        "approved_by_owner_on": NAME_CHOSEN_ON,
    }
    return data


def build(data: dict) -> EngineConfig:
    return EngineConfig.model_validate(copy.deepcopy(data))


# name, logo, handles, hashtags and each clearance field, emptied in turn
EMPTIED = [
    ("name_en", ("name_en",), ""),
    ("name_en blank", ("name_en",), "   "),
    ("name_ar", ("name_ar",), ""),
    ("logo", ("logo_path",), ""),
    ("logo blank", ("logo_path",), "  "),
    ("instagram", ("handles", "instagram"), ""),
    ("facebook", ("handles", "facebook"), ""),
    ("tiktok", ("handles", "tiktok"), ""),
    ("youtube", ("handles", "youtube"), ""),
    ("hashtags", ("hashtags",), []),
    ("hashtags blank", ("hashtags",), ["  "]),
    ("google play", ("clearance", "google_play_checked_on"), None),
    ("app store", ("clearance", "app_store_checked_on"), None),
    ("saip", ("clearance", "saip_checked_on"), None),
    ("owner approval", ("clearance", "approved_by_owner_on"), None),
]


@pytest.fixture(params=EMPTIED, ids=[row[0] for row in EMPTIED])
def incomplete_live(request) -> EngineConfig:
    _, keys, value = request.param
    data = complete_live_data()
    node = data["brand"]
    for key in keys[:-1]:
        node = node[key]
    node[keys[-1]] = value
    return build(data)


@pytest.fixture
def shipped_flipped_to_live() -> EngineConfig:
    data = shipped_data()
    data["engine"]["mode"] = "live"
    return build(data)


# --- The gate itself -------------------------------------------------------------------


def test_complete_brand_in_live_mode_meets_the_gate():
    assert is_gate_met(build(complete_live_data()))
    assert gate_failures(build(complete_live_data())) == ()


def test_any_empty_field_fails_the_gate(incomplete_live):
    assert not is_gate_met(incomplete_live)
    assert gate_failures(incomplete_live)


def test_shipped_config_as_live_fails_the_gate_and_names_each_gap(shipped_flipped_to_live):
    failures = " ".join(gate_failures(shipped_flipped_to_live))
    assert not is_gate_met(shipped_flipped_to_live)
    for expected in [
        "logo_path",
        "handles.instagram",
        "handles.facebook",
        "handles.tiktok",
        "handles.youtube",
        "hashtags",
        "clearance.google_play_checked_on",
        "clearance.app_store_checked_on",
        "clearance.saip_checked_on",
        "clearance.approved_by_owner_on",
    ]:
        assert expected in failures
    assert "name_en" not in failures


def test_test_mode_never_meets_the_gate_even_with_a_complete_brand():
    data = complete_live_data()
    data["engine"]["mode"] = "test"
    assert not is_gate_met(build(data))


# --- A non-test reel with an incomplete brand ------------------------------------------


def test_non_test_render_is_refused(incomplete_live):
    decision = render_decision(incomplete_live, test_reel=False)
    assert not decision.allowed
    assert decision.reasons


def test_no_approve_button_is_offered(incomplete_live):
    assert not approve_button_allowed(incomplete_live, test_reel=False)


def test_a_forged_approve_is_refused(incomplete_live):
    assert not approval_allowed(incomplete_live, test_reel=False)


def test_the_publisher_refuses(incomplete_live):
    assert not publish_allowed(incomplete_live, test_reel=False)


def test_shipped_config_as_live_refuses_all_four(shipped_flipped_to_live):
    assert not render_decision(shipped_flipped_to_live, test_reel=False).allowed
    for caller in CALLERS_AFTER_RENDER:
        assert not caller(shipped_flipped_to_live, test_reel=False)


# --- A non-test reel with the gate met -------------------------------------------------


def test_complete_brand_in_live_mode_allows_a_non_test_reel_with_no_watermark():
    config = build(complete_live_data())
    decision = render_decision(config, test_reel=False)
    assert decision.allowed
    assert decision.watermark is False
    for caller in CALLERS_AFTER_RENDER:
        assert caller(config, test_reel=False)


def test_test_mode_refuses_a_reel_not_marked_as_test():
    # Spec Section 13: in test mode every reel is marked as test.
    data = complete_live_data()
    data["engine"]["mode"] = "test"
    config = build(data)
    assert not render_decision(config, test_reel=False).allowed
    for caller in CALLERS_AFTER_RENDER:
        assert not caller(config, test_reel=False)


# --- A test reel -----------------------------------------------------------------------


@pytest.mark.parametrize(
    "config",
    [
        pytest.param(load_config(), id="shipped"),
        pytest.param(build(complete_live_data()), id="complete brand, live"),
    ],
)
def test_a_test_reel_renders_with_the_watermark_and_can_never_be_approved(config):
    decision = render_decision(config, test_reel=True)
    assert decision.allowed
    assert decision.watermark is True
    for caller in CALLERS_AFTER_RENDER:
        assert not caller(config, test_reel=True)


# --- Which brand, and in what order ----------------------------------------------------


def test_a_test_reel_uses_the_test_brand_even_with_a_complete_brand():
    brand = brand_for_reel(build(complete_live_data()), test_reel=True)
    assert brand.is_test
    assert brand.name_en == "TEST BRAND"
    assert brand.name_ar == "علامة تجريبية"
    assert brand.hashtag == "#test"
    assert brand.logo_path == "assets/branding/test_logo.svg"


def test_a_live_reel_uses_the_real_brand():
    brand = brand_for_reel(build(complete_live_data()), test_reel=False)
    assert not brand.is_test
    assert brand.name_en == "Qawam Money"
    assert brand.hashtag == "#QawamMoney"
    assert brand.logo_path == "assets/branding/approved_logo.svg"


def test_the_real_brand_cannot_be_used_while_the_gate_fails():
    with pytest.raises(ValueError, match="gate"):
        brand_for_reel(load_config(), test_reel=False)


@pytest.mark.parametrize(
    ("language", "expected"),
    [("ar", "قوام المال Qawam Money"), ("en", "Qawam Money قوام المال")],
)
def test_brand_order_follows_the_language(language, expected):
    brand = brand_for_reel(build(complete_live_data()), test_reel=False)
    assert brand_display(brand, language) == expected


@pytest.mark.parametrize(
    ("language", "expected"),
    [("ar", "علامة تجريبية TEST BRAND"), ("en", "TEST BRAND علامة تجريبية")],
)
def test_test_brand_order_follows_the_language(language, expected):
    brand = brand_for_reel(load_config(), test_reel=True)
    assert brand_display(brand, language) == expected


def test_an_unknown_language_is_refused():
    brand = brand_for_reel(load_config(), test_reel=True)
    with pytest.raises(ValueError):
        brand_display(brand, "ur")


# --- Values that look filled in and are not --------------------------------------------


def live_with(**brand_fields) -> EngineConfig:
    data = complete_live_data()
    data["brand"].update(brand_fields)
    return build(data)


def handles(value: str) -> dict:
    return {key: value for key in ("instagram", "facebook", "tiktok", "youtube")}


INVISIBLE = ["\u200b", "\u200c", "\u200f", "\u2060", "\ufeff", "\u202e", "\u00ad", " \u200b "]


@pytest.mark.parametrize("char", INVISIBLE)
@pytest.mark.parametrize(
    "field", ["name_en", "name_ar", "logo_path", "hashtags", "handles"]
)
def test_invisible_only_values_fail_the_gate(field, char):
    value = {"hashtags": [char], "handles": handles(char)}.get(field, char)
    assert not is_gate_met(live_with(**{field: value}))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("name_en", "Qawam\u200b Money"),
        ("name_ar", "قوام\u200f المال"),
        ("hashtags", ["#Qawam\u200bMoney"]),
        ("handles", handles("@qawam\u200bmoney")),
        ("logo_path", "assets/branding/logo\u202e.svg"),
    ],
)
def test_an_invisible_character_inside_a_value_fails_the_gate(field, value):
    assert not is_gate_met(live_with(**{field: value}))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("logo_path", "TBD"),
        ("logo_path", "todo"),
        ("logo_path", "N/A"),
        ("logo_path", "none"),
        ("logo_path", "null"),
        ("logo_path", "-"),
        ("logo_path", "TBD.svg"),
        ("logo_path", "assets/branding/placeholder.png"),
        ("logo_path", "assets/branding/logo.txt"),
        ("name_en", "null"),
        ("name_en", "TBD"),
        ("hashtags", ["#"]),
        ("hashtags", ["TBD"]),
        ("hashtags", ["QawamMoney"]),
        ("hashtags", ["#QawamMoney", "#"]),
        ("handles", handles("TBD")),
        ("handles", handles("-")),
        ("handles", handles("N/A")),
        ("handles", handles("none")),
        ("handles", handles("@")),
    ],
)
def test_placeholders_fail_the_gate(field, value):
    assert not is_gate_met(live_with(**{field: value}))


def _in_days(days: int) -> date:
    return date.today() + timedelta(days=days)


@pytest.mark.parametrize(
    "when",
    [date(1, 1, 1), date(2026, 11, 2), date(2099, 12, 31), _in_days(2)],
    ids=["year 1", "the day before the name was chosen", "2099", "in two days"],
)
@pytest.mark.parametrize(
    "field",
    ["google_play_checked_on", "app_store_checked_on", "saip_checked_on", "approved_by_owner_on"],
)
def test_implausible_clearance_dates_fail_the_gate(field, when):
    data = complete_live_data()
    data["brand"]["clearance"][field] = when
    config = build(data)
    assert not is_gate_met(config)
    assert field in " ".join(gate_failures(config))


@pytest.mark.parametrize("when", [NAME_CHOSEN_ON, date.today()], ids=["first day", "today"])
def test_clearance_dates_from_the_first_day_to_today_pass(when):
    data = complete_live_data()
    data["brand"]["clearance"]["saip_checked_on"] = when
    assert is_gate_met(build(data))


# --- G18: always the full name ---------------------------------------------------------


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("name_en", "Qawam"),
        ("name_en", "Money"),
        ("name_ar", "قوام"),
        ("name_ar", "بقوام"),
        ("hashtags", ["#قوام"]),
        ("hashtags", ["#qawam"]),
        ("hashtags", ["#QawamMoney", "#qawam"]),
        ("handles", handles("@qawam")),
        ("handles", handles("قوام")),
        ("handles", {**handles("@qawam_money"), "youtube": "@qawam"}),
    ],
)
def test_the_bare_name_fails_the_gate(field, value):
    config = live_with(**{field: value})
    assert not is_gate_met(config)
    assert not render_decision(config, test_reel=False).allowed
    assert not publish_allowed(config, test_reel=False)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("hashtags", ["#QawamMoney"]),
        ("hashtags", ["#قوام_المال"]),
        ("hashtags", ["#Qawam_Money", "#قوام_المال"]),
        ("handles", handles("@qawam.money")),
        ("handles", handles("@qawammoney")),
        ("handles", handles("@قوام_المال")),
    ],
)
def test_the_full_name_passes_the_gate(field, value):
    assert is_gate_met(live_with(**{field: value}))


# --- Test assets cannot satisfy the live gate ------------------------------------------


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("name_en", "TEST BRAND"),
        ("name_ar", "علامة تجريبية"),
        ("hashtags", ["#test"]),
        ("logo_path", "other/place/test_logo.png"),
        ("logo_path", "OTHER\\place\\TEST_LOGO.SVG"),
    ],
)
def test_test_assets_fail_the_gate(field, value):
    assert not is_gate_met(live_with(**{field: value}))


@pytest.mark.parametrize(
    "logo",
    ["assets/branding/test_logo.svg", "ASSETS\\branding\\TEST_LOGO.SVG"],
)
def test_the_shipped_test_logo_as_the_real_logo_does_not_even_load(logo):
    with pytest.raises(ValueError, match="test_brand"):
        live_with(logo_path=logo)


def test_the_configured_test_logo_is_refused_whatever_it_is_called():
    data = complete_live_data()
    data["test_brand"]["logo_path"] = "assets/branding/mark.svg"
    data["brand"]["logo_path"] = "assets/branding/mark.svg"
    with pytest.raises(ValueError, match="test_brand"):
        build(data)


def test_the_reproducer_from_review_fails_end_to_end(tmp_path):
    text = DEFAULT_CONFIG_PATH.read_text("utf-8").replace("mode: test ", "mode: live ")
    for key in ("instagram", "facebook", "tiktok", "youtube"):
        text = text.replace(f'{key}: ""', f'{key}: "\\u200b"')
    text = text.replace("hashtags: []", 'hashtags: ["\\u200b"]')
    text = text.replace('logo_path: ""', 'logo_path: "\\u200b"')
    for key in ("google_play", "app_store", "saip", "approved_by_owner"):
        text = text.replace(f"{key}_checked_on: null", f"{key}_checked_on: 2099-12-31")
        text = text.replace(f"{key}_on: null", f"{key}_on: 2099-12-31")
    path = tmp_path / "config.yaml"
    path.write_text(text, "utf-8")
    config = load_config(path)
    assert not is_gate_met(config)
    assert not render_decision(config, test_reel=False).allowed
    assert not publish_allowed(config, test_reel=False)
    with pytest.raises(ValueError, match="gate"):
        brand_for_reel(config, test_reel=False)
