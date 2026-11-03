"""Config validation (spec Sections 6.3, 6.7, 7.1, 10.5, 11.3, 13, task A2)."""

import copy
from pathlib import Path

import pytest
import yaml

from core.config import DEFAULT_CONFIG_PATH, ConfigError, load_config

ENGINE_ROOT = Path(__file__).resolve().parents[1]

# Assembled, so that tests/test_boundaries.py does not flag this file.
WITHDRAWN_EN = "Wa" + "feer"
WITHDRAWN_AR = "وف" + "يير"
OTHER_LLM = "gem" + "ini"
OTHER_LLM_ROUTER = "lite" + "llm"
OTHER_VOICE = "eleven" + "labs"
OTHER_VOICE_2 = "edge" + "_tts"

SPEC_11_3_TOP_LEVEL_KEYS = {
    "engine",
    "brand",
    "test_brand",
    "paths",
    "capture",
    "llm",
    "voice",
    "render",
    "captions",
    "audio",
    "content",
    "cta",
    "approval",
    "guardrails",
    "publishing_mode",
    "schedule",
    "retention",
}


@pytest.fixture
def shipped() -> dict:
    with DEFAULT_CONFIG_PATH.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load(tmp_path, data):
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    return load_config(path)


def changed(data: dict, dotted: str, value) -> dict:
    result = copy.deepcopy(data)
    node = result
    *parents, leaf = dotted.split(".")
    for key in parents:
        node = node[key]
    node[leaf] = value
    return result


def refused(tmp_path, data, *expected_in_message):
    with pytest.raises(ConfigError) as caught:
        load(tmp_path, data)
    message = str(caught.value)
    for expected in expected_in_message:
        assert expected in message, f"{expected!r} not in clear message: {message}"
    return message


# --- Shipped file ----------------------------------------------------------------------


def test_default_path_is_the_shipped_file():
    assert DEFAULT_CONFIG_PATH == ENGINE_ROOT / "config.yaml"


def test_shipped_config_loads_in_test_mode_with_the_name_set():
    config = load_config()
    assert config.engine.mode == "test"
    assert config.brand.name_en == "Qawam Money"
    assert config.brand.name_ar == "قوام المال"
    assert config.brand.tagline_en == "Spend in balance"
    assert config.brand.tagline_ar == "لا إسراف ولا تقتير"


def test_shipped_config_has_logo_handles_hashtags_and_clearance_empty():
    config = load_config()
    assert config.brand.logo_path == ""
    assert config.brand.hashtags == []
    assert set(config.brand.handles.model_dump().values()) == {""}
    assert set(config.brand.clearance.model_dump().values()) == {None}


def test_shipped_clearance_fields_are_literally_null(shipped):
    assert shipped["brand"]["clearance"] == {
        "google_play_checked_on": None,
        "app_store_checked_on": None,
        "saip_checked_on": None,
        "approved_by_owner_on": None,
    }


def test_shipped_config_holds_every_key_in_spec_11_3(shipped):
    assert SPEC_11_3_TOP_LEVEL_KEYS <= set(shipped)
    assert shipped["render"]["fps"] == 30
    assert shipped["render"]["video_kbps_cap"] == 8000
    assert shipped["render"]["audio_kbps"] == 192
    assert shipped["render"]["max_mb"] == 48
    assert shipped["captions"]["digits"] == "western"
    assert shipped["audio"]["music_enabled"] is False
    assert shipped["audio"]["music_library"] is None
    assert shipped["content"]["mix"] == {"global": 50, "regional": 30, "saudi": 20}
    assert shipped["content"]["english_audio_share"] == 0.2
    assert shipped["approval"] == {
        "expire_after_hours": 72,
        "max_regenerations": 3,
        "max_waiting": 3,
    }
    assert shipped["guardrails"]["max_copied_words"] == 12
    assert shipped["publishing_mode"] == "telegram_only"
    assert shipped["retention"]["auto_delete"] is False
    assert shipped["paths"]["data_root"] == "%LOCALAPPDATA%/SocialEngine"
    assert (
        shipped["capture"]["adb_path"]
        == "%LOCALAPPDATA%/Android/Sdk/platform-tools/adb.exe"
    )


def test_shipped_config_adds_the_plan_keys(shipped):
    assert shipped["render"]["ffmpeg_path"] == ""
    assert shipped["voice"]["pronunciation"] == {}


def test_shipped_llm_voice_and_schedule_match_the_spec(shipped):
    assert shipped["llm"]["backend"] == "claude_cli"
    assert shipped["llm"]["auth"] == "subscription"
    assert shipped["llm"]["model"] == "opus"
    assert shipped["llm"]["max_turns"] == 12
    assert shipped["llm"]["max_budget_usd"] == 2.0
    assert shipped["voice"]["provider"] == "azure_speech"
    assert shipped["voice"]["azure_tier"] == "F0"
    assert shipped["voice"]["monthly_char_cap"] == 400000
    assert shipped["voice"]["allow_public_on_f0"] is False
    assert shipped["voice"]["output_format"] == "riff-48khz-16bit-mono-pcm"
    assert shipped["schedule"]["timezone"] == "Asia/Riyadh"
    assert shipped["schedule"]["cadence"] == {
        "reels_per_week": 3,
        "generation_days": ["sun", "tue", "thu"],
    }
    assert shipped["schedule"]["payday_boost"]["enabled"] is False


def test_shipped_cta_is_coming_soon_with_no_url(shipped):
    assert shipped["cta"]["mode"] == "coming_soon"
    assert shipped["cta"]["landing_url"] is None
    assert shipped["cta"]["early_access"] is None
    assert shipped["cta"]["coming_soon"]["voice_en"] == "{brand_en}, coming soon."


def test_shipped_config_names_no_secret_values(shipped):
    assert "api_key" not in shipped["llm"]
    assert not {"token", "key", "secret"} & set(shipped)


# --- Unknown keys ----------------------------------------------------------------------


@pytest.mark.parametrize(
    "dotted",
    [
        "surprise",
        "engine.surprise",
        "brand.surprise",
        "brand.handles.threads",
        "brand.clearance.surprise",
        "test_brand.surprise",
        "llm.api_key",
        "voice.surprise",
        "render.surprise",
        "render.safe_zones.surprise",
        "captions.surprise",
        "audio.surprise",
        "content.surprise",
        "cta.surprise",
        "cta.coming_soon.surprise",
        "approval.surprise",
        "guardrails.surprise",
        "schedule.surprise",
        "schedule.cadence.surprise",
        "schedule.payday_boost.surprise",
        "retention.surprise",
    ],
)
def test_unknown_keys_are_refused_at_every_level(tmp_path, shipped, dotted):
    refused(tmp_path, changed(shipped, dotted, "x"), dotted)


def test_a_duplicated_key_is_refused_rather_than_last_one_wins(tmp_path):
    text = DEFAULT_CONFIG_PATH.read_text(encoding="utf-8")
    path = tmp_path / "config.yaml"
    path.write_text(text + "\nengine: {mode: live}\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="engine"):
        load_config(path)


def test_a_missing_file_gives_a_clear_message(tmp_path):
    with pytest.raises(ConfigError, match="not found"):
        load_config(tmp_path / "nope.yaml")


def test_a_file_that_is_not_a_mapping_gives_a_clear_message(tmp_path):
    path = tmp_path / "config.yaml"
    path.write_text("- just\n- a list\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="mapping"):
        load_config(path)


def test_broken_yaml_gives_a_clear_message(tmp_path):
    path = tmp_path / "config.yaml"
    path.write_text("engine: {mode: test", encoding="utf-8")
    with pytest.raises(ConfigError, match="YAML"):
        load_config(path)


# --- Claude only, Azure only -----------------------------------------------------------


@pytest.mark.parametrize(
    "provider", [OTHER_VOICE, OTHER_VOICE_2, "chattts", "", "AZURE_SPEECH", None]
)
def test_a_voice_provider_other_than_azure_is_refused(tmp_path, shipped, provider):
    refused(tmp_path, changed(shipped, "voice.provider", provider), "voice.provider")


@pytest.mark.parametrize(
    "backend", [OTHER_LLM, OTHER_LLM_ROUTER, "openai", "ollama", "", None]
)
def test_a_non_claude_backend_is_refused(tmp_path, shipped, backend):
    refused(tmp_path, changed(shipped, "llm.backend", backend), "llm.backend")


@pytest.mark.parametrize(
    "model",
    [
        OTHER_LLM,
        f"{OTHER_LLM}-2.5-pro",
        "gpt-5",
        "llama-4",
        f"{OTHER_LLM_ROUTER}/claude-opus",
        "mistral-large",
        "claude",
        "claude-",
        "",
    ],
)
def test_a_non_claude_model_is_refused(tmp_path, shipped, model):
    refused(tmp_path, changed(shipped, "llm.model", model), "llm.model")


@pytest.mark.parametrize(
    "model", ["opus", "sonnet", "haiku", "fable", "claude-opus-5-5", "claude-sonnet-4-5-20250929"]
)
def test_claude_models_are_accepted(tmp_path, shipped, model):
    assert load(tmp_path, changed(shipped, "llm.model", model)).llm.model == model


@pytest.mark.parametrize("backend", ["claude_cli", "anthropic_api"])
def test_both_claude_backends_validate(tmp_path, shipped, backend):
    assert load(tmp_path, changed(shipped, "llm.backend", backend)).llm.backend == backend


@pytest.mark.parametrize("auth", ["subscription", "api_key"])
def test_both_auth_routes_validate(tmp_path, shipped, auth):
    assert load(tmp_path, changed(shipped, "llm.auth", auth)).llm.auth == auth


def test_an_unknown_auth_route_is_refused(tmp_path, shipped):
    refused(tmp_path, changed(shipped, "llm.auth", "shared"), "llm.auth")


# --- Withdrawn name and logo -----------------------------------------------------------


@pytest.mark.parametrize(
    ("dotted", "value"),
    [
        ("brand.name_en", WITHDRAWN_EN),
        ("brand.name_en", WITHDRAWN_EN.upper()),
        ("brand.name_en", f"{WITHDRAWN_EN} Money"),
        ("brand.name_ar", WITHDRAWN_AR),
        ("brand.name_ar", "وَف" + "ِيير"),
        ("brand.tagline_en", f"Spend with {WITHDRAWN_EN}"),
        ("brand.handles.instagram", f"@{WITHDRAWN_EN.lower()}_app"),
        ("brand.hashtags", [f"#{WITHDRAWN_EN}"]),
        ("test_brand.name_en", WITHDRAWN_EN),
        ("cta.coming_soon.caption_en", f"{WITHDRAWN_EN} is coming soon."),
        ("captions.disclaimer", f"{WITHDRAWN_AR} info"),
    ],
)
def test_the_withdrawn_name_is_refused_everywhere(tmp_path, shipped, dotted, value):
    refused(tmp_path, changed(shipped, dotted, value), "withdrawn")


@pytest.mark.parametrize(
    "path",
    [
        f"flutter_app/assets/images/{WITHDRAWN_EN.lower()}_logo.png",
        f"..\\..\\flutter_app\\assets\\images\\{WITHDRAWN_EN.lower()}_logo.png",
        f"assets/branding/{WITHDRAWN_EN}_Logo.png",
        "flutter_app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png",
        "C:/repo/flutter_app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
        "assets/branding/ic_launcher.png",
        "flutter_app/assets/images/anything.png",
    ],
)
@pytest.mark.parametrize("field", ["brand.logo_path", "test_brand.logo_path"])
def test_the_withdrawn_logo_and_launcher_icons_are_refused(tmp_path, shipped, field, path):
    refused(tmp_path, changed(shipped, field, path), "withdrawn")


def test_a_new_logo_path_is_accepted(tmp_path, shipped):
    config = load(tmp_path, changed(shipped, "brand.logo_path", "assets/branding/logo.svg"))
    assert config.brand.logo_path == "assets/branding/logo.svg"


# --- CTA -------------------------------------------------------------------------------

WORDING = {
    "bio_ar": "نص",
    "bio_en": "text",
    "caption_ar": "نص",
    "caption_en": "text",
    "voice_ar": "نص",
    "voice_en": "text",
}


@pytest.mark.parametrize("mode", ["early_access", "store"])
@pytest.mark.parametrize("url", [None, "", "   "])
def test_early_access_or_store_with_no_url_is_refused(tmp_path, shipped, mode, url):
    data = changed(changed(shipped, "cta.mode", mode), "cta.landing_url", url)
    data["cta"][mode] = WORDING
    refused(tmp_path, data, "landing_url")


@pytest.mark.parametrize("mode", ["early_access", "store"])
def test_early_access_or_store_with_no_wording_is_refused(tmp_path, shipped, mode):
    data = changed(changed(shipped, "cta.mode", mode), "cta.landing_url", "https://a.example/x")
    data["cta"][mode] = None
    refused(tmp_path, data, mode)


@pytest.mark.parametrize("mode", ["early_access", "store"])
def test_early_access_or_store_with_url_and_wording_loads(tmp_path, shipped, mode):
    data = changed(changed(shipped, "cta.mode", mode), "cta.landing_url", "https://a.example/x")
    data["cta"][mode] = WORDING
    assert load(tmp_path, data).cta.mode == mode


def test_coming_soon_with_a_url_is_refused(tmp_path, shipped):
    data = changed(shipped, "cta.landing_url", "https://a.example/x")
    refused(tmp_path, data, "coming_soon", "landing_url")


@pytest.mark.parametrize("url", ["", "   "])
def test_a_blank_url_counts_as_empty_in_coming_soon(tmp_path, shipped, url):
    assert load(tmp_path, changed(shipped, "cta.landing_url", url)).cta.landing_url is None


@pytest.mark.parametrize("url", ["a.example", "http://a.example", "ftp://a.example", "https://"])
def test_a_landing_url_must_be_https(tmp_path, shipped, url):
    data = changed(changed(shipped, "cta.mode", "early_access"), "cta.landing_url", url)
    data["cta"]["early_access"] = WORDING
    refused(tmp_path, data, "landing_url")


def test_an_unknown_cta_mode_is_refused(tmp_path, shipped):
    refused(tmp_path, changed(shipped, "cta.mode", "link_in_bio"), "cta.mode")


# --- Cadence, music and other values ---------------------------------------------------


@pytest.mark.parametrize("value", [0, 8, -1, 3.5, "3"])
def test_reels_per_week_outside_1_to_7_is_refused(tmp_path, shipped, value):
    data = changed(shipped, "schedule.cadence.reels_per_week", value)
    refused(tmp_path, data, "reels_per_week")


@pytest.mark.parametrize("value", [1, 7])
def test_reels_per_week_at_the_limits_loads(tmp_path, shipped, value):
    data = changed(shipped, "schedule.cadence.reels_per_week", value)
    assert load(tmp_path, data).schedule.cadence.reels_per_week == value


@pytest.mark.parametrize("library", [None, "", "  "])
def test_music_enabled_with_no_library_is_refused(tmp_path, shipped, library):
    data = changed(changed(shipped, "audio.music_enabled", True), "audio.music_library", library)
    refused(tmp_path, data, "music_library")


def test_music_enabled_with_a_library_loads(tmp_path, shipped):
    data = changed(changed(shipped, "audio.music_enabled", True), "audio.music_library", "Lib")
    assert load(tmp_path, data).audio.music_library == "Lib"


@pytest.mark.parametrize(
    ("dotted", "value"),
    [
        ("engine.mode", "production"),
        ("engine.mode", True),
        ("voice.azure_tier", "S1"),
        ("voice.allow_public_on_f0", "true"),
        ("voice.monthly_char_cap", 0),
        ("render.fps", 24),
        ("render.max_mb", 51),
        ("render.video_kbps_cap", 0),
        ("captions.digits", "roman"),
        ("captions.ai_voice_disclosure", ""),
        ("content.english_audio_share", 1.5),
        ("content.mix", {"global": 50, "regional": 30, "saudi": 30}),
        ("content.mix", {"global": 70, "regional": 30}),
        ("content.mix", {"global": 50, "regional": 30, "saudi": 10, "mars": 10}),
        ("approval.expire_after_hours", 0),
        ("approval.max_waiting", 0),
        ("guardrails.max_copied_words", 0),
        ("publishing_mode", "ayrshare"),
        ("schedule.timezone", "Mars/Olympus"),
        ("schedule.generate_after", "25:00"),
        ("schedule.cadence.generation_days", []),
        ("schedule.cadence.generation_days", ["sun", "sun"]),
        ("schedule.cadence.generation_days", ["funday"]),
        ("schedule.windows", []),
        ("schedule.windows", [{"name": "x", "start": "14:00", "end": "13:00"}]),
        ("schedule.payday_boost.days_of_month", [32]),
        ("retention.auto_delete", "no"),
        ("brand.clearance.saip_checked_on", ""),
        ("brand.clearance.saip_checked_on", "soon"),
    ],
)
def test_invalid_values_are_refused(tmp_path, shipped, dotted, value):
    refused(tmp_path, changed(shipped, dotted, value), dotted.split(".")[0])


def test_a_clearance_date_loads_as_a_date(tmp_path):
    text = DEFAULT_CONFIG_PATH.read_text(encoding="utf-8").replace(
        "saip_checked_on: null", "saip_checked_on: 2026-12-01"
    )
    path = tmp_path / "config.yaml"
    path.write_text(text, encoding="utf-8")
    assert load_config(path).brand.clearance.saip_checked_on.isoformat() == "2026-12-01"


def test_the_config_is_read_only_once_loaded():
    config = load_config()
    with pytest.raises(ValueError):
        config.engine.mode = "live"
