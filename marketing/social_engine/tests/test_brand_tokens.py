"""Brand assets and studio rules that hold without running Remotion (spec Sections 8.1, 8.4, 8.5).

The Dart theme is the source of truth for colours (G16). No logo ships in the repo: the only
image here is the plain TEST mark, and a real logo arrives later through config (D1).
"""

import hashlib
import json
import re
from pathlib import Path

import pytest

from core.render_props import RenderProps

ENGINE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ENGINE_ROOT.parents[1]
BRANDING = ENGINE_ROOT / "assets" / "branding"
STUDIO = ENGINE_ROOT / "remotion_studio"
DART_THEME = REPO_ROOT / "flutter_app" / "lib" / "core" / "theme" / "velvet_burgundy_theme.dart"
APP_CAIRO = REPO_ROOT / "flutter_app" / "assets" / "fonts" / "cairo"

BANNED_GOLD = "#" + "C9933B"
HEX_COLOUR = re.compile(r"#[0-9A-Fa-f]{6}\b")
TEXT_SUFFIXES = {".ts", ".tsx", ".mjs", ".json", ".svg", ".md", ".txt"}

# Spec Section 8.5, by the name the token has in the Dart file.
EXPECTED_TOKENS = {
    "canvasDark": "#110509",
    "canvasDarkBg": "#0A0205",
    "surfaceDark": "#1E0B12",
    "surfaceDarkGradientStart": "#240E17",
    "surfaceDarkGradientEnd": "#17080E",
    "primaryLight": "#4A0E1E",
    "primaryDarkMaroon": "#2A050E",
    "primaryLightGradient": "#6C162F",
    "roseGold": "#E598B0",
    "roseGoldGlow": "#F0A3BC",
    "accentRose": "#B83253",
    "emeraldSafe": "#10B981",
    "coralDanger": "#F43F5E",
    "amberCaution": "#F59E0B",
    "textPrimaryDark": "#FDF8FA",
    "textSecondaryDark": "#C7AEB6",
}


def _dart_colours() -> dict[str, str]:
    text = DART_THEME.read_text(encoding="utf-8")
    found = re.findall(r"static const Color (\w+) = Color\(0x([0-9A-Fa-f]{8})\)", text)
    return {name: f"#{value[2:].upper()}" for name, value in found if value[:2].upper() == "FF"}


def _tokens() -> dict:
    return json.loads((BRANDING / "brand_tokens.json").read_text(encoding="utf-8"))


def _studio_text_files() -> list[Path]:
    return [
        path
        for path in STUDIO.rglob("*")
        if path.is_file()
        and path.suffix in TEXT_SUFFIXES
        and "node_modules" not in path.parts
        and path.name != "package-lock.json"
    ]


def test_tokens_are_the_ones_in_the_spec():
    assert _tokens()["colors"] == EXPECTED_TOKENS


def test_every_token_matches_the_dart_theme():
    dart = _dart_colours()
    assert len(dart) > 20, "the theme file was not parsed"
    for name, value in _tokens()["colors"].items():
        assert dart.get(name) == value, f"{name} differs from the Dart theme"


def test_the_withdrawn_gold_is_nowhere_in_the_brand_or_the_studio():
    branding = [path for path in BRANDING.rglob("*") if path.suffix in TEXT_SUFFIXES]
    scanned = [*_studio_text_files(), *branding]
    assert scanned
    for path in scanned:
        assert BANNED_GOLD.lower() not in path.read_text(encoding="utf-8").lower(), path


def test_the_studio_source_writes_no_colour_outside_the_tokens():
    """Every colour goes through the tokens, so a template cannot drift off brand (G16)."""
    allowed = {value.lower() for value in _tokens()["colors"].values()}
    sources = [p for p in (STUDIO / "src").rglob("*") if p.suffix in {".ts", ".tsx"}]
    assert sources
    for path in sources:
        for colour in HEX_COLOUR.findall(path.read_text(encoding="utf-8")):
            assert colour.lower() in allowed, f"{path.name} writes {colour}"


@pytest.mark.parametrize("folder", ["cairo", "outfit", "tajawal"])
def test_each_font_folder_has_its_licence_and_a_font(folder):
    path = BRANDING / "fonts" / folder
    licence = (path / "OFL.txt").read_text(encoding="utf-8")
    assert "SIL Open Font License" in licence
    assert list(path.glob("*.ttf")), f"{folder} has no font file"


def test_every_font_folder_is_a_licensed_one():
    folders = {path.name for path in (BRANDING / "fonts").iterdir() if path.is_dir()}
    assert folders == {"cairo", "outfit", "tajawal"}


def test_the_licence_record_covers_each_font_and_remotion():
    record = (BRANDING / "fonts" / "LICENCES.md").read_text(encoding="utf-8")
    for name in ("Cairo", "Outfit", "Tajawal", "SIL Open Font License"):
        assert name in record
    studio_record = (STUDIO / "LICENCES.md").read_text(encoding="utf-8")
    for fact in ("Free License", "an individual", "D27", "licenseKey", "4.0.540"):
        assert fact in studio_record, fact


@pytest.mark.parametrize(
    "name", ["Cairo-Regular.ttf", "Cairo-SemiBold.ttf", "Cairo-Bold.ttf", "OFL.txt"]
)
def test_cairo_is_the_apps_own_copy(name):
    ours = (BRANDING / "fonts" / "cairo" / name).read_bytes()
    theirs = (APP_CAIRO / name).read_bytes()
    assert hashlib.sha256(ours).hexdigest() == hashlib.sha256(theirs).hexdigest()


def test_the_only_image_in_the_branding_folder_is_the_test_mark():
    """No logo baked in. The withdrawn logo and launcher icons have no way in (D1)."""
    images = [
        path.name
        for path in BRANDING.rglob("*")
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".svg"}
    ]
    assert images == ["test_logo.svg"]


def test_the_test_mark_is_plain_and_on_brand():
    text = (BRANDING / "test_logo.svg").read_text(encoding="utf-8")
    assert "<title>TEST</title>" in text
    assert "<text" not in text, "text would fall back to a system font inside an image"
    assert "<image" not in text and "href" not in text, "the mark must not embed anything"
    allowed = set(EXPECTED_TOKENS.values())
    colours = set(HEX_COLOUR.findall(text))
    assert colours and colours <= allowed


def test_the_studio_ships_no_image_or_media_except_golden_frames():
    heavy = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".mp4", ".mov", ".wav", ".mp3"}
    for path in STUDIO.rglob("*"):
        if path.suffix.lower() in heavy and "node_modules" not in path.parts:
            assert path.parent == STUDIO / "golden" and path.suffix == ".png", path


def _sample_props() -> list[Path]:
    return sorted((STUDIO / "test_data").glob("sample_*.json"))


def test_there_are_samples_for_each_template_and_language():
    loaded = [json.loads(path.read_text(encoding="utf-8")) for path in _sample_props()]
    assert {sample["template"] for sample in loaded} == {"FeatureDemo", "DailyTip", "MythVsFact"}
    assert {sample["language"] for sample in loaded} == {"ar", "en"}


@pytest.mark.parametrize("path", _sample_props(), ids=lambda path: path.stem)
def test_each_studio_sample_is_valid_against_the_real_contract(path):
    props = RenderProps.model_validate_json(path.read_text(encoding="utf-8"))
    assert props.watermark is True, "samples are test reels and must carry the watermark"
    assert props.brand.logo_src == "test_logo.svg"


def test_the_studio_never_passes_a_licence_key():
    """Remotion sends a usage event only when a key is passed, so none is, ever (LICENCES.md)."""
    for path in _studio_text_files():
        if path.name == "LICENCES.md":
            continue
        text = path.read_text(encoding="utf-8")
        assert "licenseKey" not in text and "LicenseKey" not in text, path
        assert "free-license" not in text, path
