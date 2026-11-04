"""What may be rendered, and where the safety values come from (spec Sections 5.2, 8.3, 12, 13,
guardrails G15, G16, G19, task G1)."""

import inspect
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
from render_support import Rig, complete_live_data, shipped_data

import core.render as render_module
from core.brand_gate import FULL_NAME_AR, FULL_NAME_EN, ReelBrand
from core.manifest import ClipManifest, sha256_file
from core.render import ClipUse, RenderRefused, RenderRequest, render_reel
from core.render_props import FocalPoint

SIGNED_MASK = {"x": 0.05, "y": 0.2, "width": 0.9, "height": 0.08}


@pytest.fixture
def rig(tmp_path, monkeypatch) -> Rig:
    return Rig(tmp_path, monkeypatch)


def render(rig: Rig, request: RenderRequest | None = None, *, test_reel: bool = True):
    rig.reels.is_test = test_reel  # the flag on the stored row, the only place it comes from
    return render_reel(
        request if request is not None else rig.request(),
        store=rig.reels,
        config=rig.config,
        paths=rig.paths,
        engine_root=rig.engine,
    )


def props_sent(rig: Rig) -> dict:
    return rig.fake.renders[-1].props


def assert_refused_with_no_side_effects(rig: Rig, request=None, *, test_reel=True, match=None):
    with pytest.raises(RenderRefused, match=match):
        render(rig, request, test_reel=test_reel)
    assert rig.fake.subprocess_count == 0
    assert list(rig.paths.renders.iterdir()) == []
    assert not (rig.paths.remotion_work / "public").exists()


def write_manifest(rig: Rig, entry: dict) -> None:
    rig.paths.manifest.write_text(json.dumps({"clips": [entry]}), encoding="utf-8")


# --- G15: only signed clips with a matching hash ---------------------------------------


def test_a_signed_clip_renders(rig):
    rig.add_clip()
    render(rig, rig.request(clips=[rig.clip_use()]))
    assert props_sent(rig)["clips"][0]["src"] == "clips/payday_cycle/clip_01.mp4"


def test_a_clip_not_in_the_manifest_is_refused(rig):
    file = rig.paths.raw_recordings / "payday_cycle" / "clip_01.mp4"
    file.write_bytes(b"clip bytes")
    assert_refused_with_no_side_effects(
        rig, rig.request(clips=[rig.clip_use()]), match="not in the manifest"
    )


def test_an_unsigned_clip_is_refused(rig):
    file = rig.paths.raw_recordings / "payday_cycle" / "clip_01.mp4"
    file.write_bytes(b"clip bytes")
    write_manifest(
        rig,
        {
            "path": "payday_cycle/clip_01.mp4",
            "sha256": sha256_file(file),
            "privacy_checked": False,
            "app_version": "1.0.0",
        },
    )
    assert_refused_with_no_side_effects(
        rig, rig.request(clips=[rig.clip_use()]), match="privacy_checked"
    )


def test_a_changed_clip_is_refused(rig):
    entry = rig.add_clip()
    (rig.paths.raw_recordings / entry.path).write_bytes(b"swapped afterwards")
    assert_refused_with_no_side_effects(
        rig, rig.request(clips=[rig.clip_use()]), match="signed hash"
    )


def test_a_clip_changed_after_the_check_is_refused_when_it_is_copied(rig, monkeypatch):
    entry = rig.add_clip()
    real = ClipManifest.verified_clip

    def verify_then_swap(self, clip_path, recordings_root):
        verified = real(self, clip_path, recordings_root)
        (rig.paths.raw_recordings / entry.path).write_bytes(b"swapped after the check")
        return verified

    monkeypatch.setattr(ClipManifest, "verified_clip", verify_then_swap)
    with pytest.raises(RenderRefused, match="changed"):
        render(rig, rig.request(clips=[rig.clip_use()]))
    assert rig.fake.renders == []
    assert not (rig.paths.remotion_work / "public" / "clips" / entry.path).exists()


def test_a_missing_clip_is_refused(rig):
    entry = rig.add_clip()
    (rig.paths.raw_recordings / entry.path).unlink()
    assert_refused_with_no_side_effects(rig, rig.request(clips=[rig.clip_use()]), match="missing")


def test_a_broken_manifest_is_refused(rig):
    rig.paths.manifest.write_text("{not json", encoding="utf-8")
    assert_refused_with_no_side_effects(rig, match="manifest")


def test_a_clip_path_cannot_climb_out_of_the_recordings_folder(rig):
    (rig.paths.raw_recordings.parent / "secret.mp4").write_bytes(b"private")
    use = ClipUse(path="../secret.mp4", start_ms=0, end_ms=1000)
    assert_refused_with_no_side_effects(rig, rig.request(clips=[use]), match="not in the manifest")


def test_a_test_reel_gets_no_exception_from_the_clip_checks(rig):
    entry = rig.add_clip()
    (rig.paths.raw_recordings / entry.path).write_bytes(b"swapped")
    assert_refused_with_no_side_effects(rig, rig.request(clips=[rig.clip_use()]), test_reel=True)


# --- G19: Smart Basket -----------------------------------------------------------------


def basket_entry(rig: Rig, **overrides) -> dict:
    file = rig.paths.raw_recordings / "smart_basket" / "clip_01.mp4"
    file.write_bytes(b"basket bytes")
    entry = {
        "path": "smart_basket/clip_01.mp4",
        "sha256": sha256_file(file),
        "privacy_checked": True,
        "app_version": "1.0.0",
        "store_names_masked": True,
        "mask_regions": [SIGNED_MASK],
    }
    entry.update(overrides)
    return entry


def test_the_focal_point_of_a_clip_reaches_the_props(rig):
    rig.add_basket_clip()
    use = rig.clip_use("smart_basket/clip_01.mp4").model_copy(
        update={"focal_point": FocalPoint(x=0.25, y=0.6)}
    )
    render(rig, rig.request(clips=[use]))
    assert props_sent(rig)["clips"][0]["focal_point"] == {"x": 0.25, "y": 0.6}


def test_a_clip_with_no_focal_point_sends_null(rig):
    rig.add_basket_clip()
    render(rig, rig.request(clips=[rig.clip_use("smart_basket/clip_01.mp4")]))
    assert props_sent(rig)["clips"][0]["focal_point"] is None


def test_a_masked_and_signed_basket_clip_renders_with_its_masks(rig):
    rig.add_basket_clip()
    render(rig, rig.request(clips=[rig.clip_use("smart_basket/clip_01.mp4")]))
    assert props_sent(rig)["clips"][0]["mask_regions"] == [SIGNED_MASK]


@pytest.mark.parametrize(
    ("overrides", "problem"),
    [
        ({"mask_regions": []}, "mask_regions"),
        ({"store_names_masked": False}, "store_names_masked"),
    ],
    ids=["no mask regions", "no mask sign-off"],
)
@pytest.mark.parametrize("test_reel", [True, False], ids=["test reel", "live reel"])
def test_a_basket_clip_without_masks_or_sign_off_is_refused(rig, overrides, problem, test_reel):
    if not test_reel:
        rig.use_live_config()
    write_manifest(rig, basket_entry(rig, **overrides))
    request = rig.request(clips=[rig.clip_use("smart_basket/clip_01.mp4")])
    assert_refused_with_no_side_effects(rig, request, test_reel=test_reel, match=problem)


# --- Where mask_regions and watermark come from ---------------------------------------


def test_the_function_has_no_way_to_pass_the_safety_values():
    names = set(inspect.signature(render_reel).parameters)
    assert names == {"request", "store", "config", "paths", "engine_root"}


@pytest.mark.parametrize(
    "field",
    ["watermark", "mask_regions", "brand", "logo_src", "device_frame", "safe_zones", "sha256"],
)
def test_the_request_refuses_the_safety_values(rig, field):
    with pytest.raises(ValidationError):
        rig.request(**{field: False})


@pytest.mark.parametrize("field", ["mask_regions", "sha256", "folder", "src", "store_names_masked"])
def test_a_clip_use_refuses_the_clip_safety_values(field):
    with pytest.raises(ValidationError):
        ClipUse(path="smart_basket/clip_01.mp4", start_ms=0, end_ms=1000, **{field: []})


def test_the_request_is_frozen(rig):
    with pytest.raises(ValidationError):
        rig.request().hook_text = "changed"


def test_masks_and_hash_come_from_the_manifest_even_past_the_schema(rig):
    # model_copy skips validation, so this is the closest a caller can get to forcing values in.
    entry = rig.add_basket_clip()
    use = rig.clip_use("smart_basket/clip_01.mp4").model_copy(
        update={"mask_regions": [], "sha256": "0" * 64, "folder": "payday_cycle"}
    )
    request = rig.request(clips=[use])
    render(rig, request)
    sent = props_sent(rig)["clips"][0]
    assert sent["mask_regions"] == [SIGNED_MASK]
    assert sent["sha256"] == entry.sha256
    assert sent["folder"] == "smart_basket"


def test_masks_change_only_when_the_manifest_changes(rig):
    other = {"x": 0.1, "y": 0.5, "width": 0.8, "height": 0.1}
    write_manifest(rig, basket_entry(rig, mask_regions=[other]))
    render(rig, rig.request(clips=[rig.clip_use("smart_basket/clip_01.mp4")]))
    assert props_sent(rig)["clips"][0]["mask_regions"] == [other]


def test_a_clip_outside_the_basket_folder_is_sent_with_no_masks(rig):
    rig.add_clip()
    render(rig, rig.request(clips=[rig.clip_use()]))
    assert props_sent(rig)["clips"][0]["mask_regions"] == []


def test_a_test_reel_always_carries_the_watermark_and_the_test_brand(rig):
    render(rig)
    props = props_sent(rig)
    assert props["watermark"] is True
    assert props["brand"]["name_en"] == rig.config.test_brand.name_en
    assert props["brand"]["logo_src"] == "test_logo.svg"


def test_a_test_reel_carries_the_watermark_even_with_a_complete_real_brand(rig):
    rig.use_live_config()
    render(rig, test_reel=True)
    props = props_sent(rig)
    assert props["watermark"] is True
    assert props["brand"]["name_en"] == rig.config.test_brand.name_en


def test_a_test_reel_cannot_lose_the_watermark_past_the_schema(rig):
    request = rig.request().model_copy(update={"watermark": False, "brand": {"name_en": "x"}})
    render(rig, request, test_reel=True)
    assert props_sent(rig)["watermark"] is True


def test_the_watermark_is_exactly_the_brand_is_test_flag(rig):
    rig.use_live_config()
    render(rig, test_reel=False)
    props = props_sent(rig)
    assert props["watermark"] is False
    assert (props["brand"]["name_en"], props["brand"]["name_ar"]) == (FULL_NAME_EN, FULL_NAME_AR)


@pytest.mark.parametrize("test_reel", [True, False])
def test_a_brand_that_disagrees_with_the_reel_kind_is_refused(rig, monkeypatch, test_reel):
    rig.use_live_config()
    wrong = ReelBrand("اسم", "Name", "#tag", "assets/branding/test_logo.svg", is_test=not test_reel)
    monkeypatch.setattr(render_module, "brand_for_reel", lambda config, test_reel: wrong)
    assert_refused_with_no_side_effects(rig, test_reel=test_reel, match="is_test")


# --- G16: colours ----------------------------------------------------------------------


def test_a_brand_colour_passes_in_any_letter_case(rig):
    render(rig, rig.request(highlight_color="#e598b0"))
    assert props_sent(rig)["highlight_color"] == "#e598b0"


@pytest.mark.parametrize("colour", ["#123456", "#C9933B", "#c9933b", "red", "#E598B", ""])
def test_a_non_brand_colour_is_refused(rig, colour):
    assert_refused_with_no_side_effects(rig, rig.request(highlight_color=colour), match="G16")


def test_the_banned_colour_is_refused_even_if_the_tokens_list_it(rig):
    tokens = rig.engine / "assets" / "branding" / "brand_tokens.json"
    tokens.write_text(json.dumps({"gold": "#C9933B", "rose": "#E598B0"}), encoding="utf-8")
    assert_refused_with_no_side_effects(rig, match="G16")


def test_the_banned_colour_in_the_templates_is_refused(rig):
    source = rig.engine / "remotion_studio" / "src" / "Root.tsx"
    source.write_text('const gold = "#c9933b";', encoding="utf-8")
    assert_refused_with_no_side_effects(rig, match="G16")


@pytest.mark.parametrize("content", [None, "{not json", "{}", '{"name": "no colours"}'])
def test_missing_or_empty_tokens_are_refused(rig, content):
    tokens = rig.engine / "assets" / "branding" / "brand_tokens.json"
    if content is None:
        tokens.unlink()
    else:
        tokens.write_text(content, encoding="utf-8")
    assert_refused_with_no_side_effects(rig, match="G16")


# --- The launch gate -------------------------------------------------------------------


def test_a_live_render_while_the_gate_fails_is_refused(rig):
    data = shipped_data()
    data["engine"]["mode"] = "live"
    rig.use_live_config(data)
    assert_refused_with_no_side_effects(rig, test_reel=False, match="launch gate")


@pytest.mark.parametrize(
    "change",
    [
        lambda brand: brand.update(logo_path=""),
        lambda brand: brand.update(hashtags=[]),
        lambda brand: brand["handles"].update(tiktok=""),
        lambda brand: brand["clearance"].update(saip_checked_on=None),
    ],
    ids=["logo", "hashtags", "handle", "clearance"],
)
def test_any_gap_in_the_brand_refuses_a_live_render(rig, change):
    data = complete_live_data()
    change(data["brand"])
    rig.use_live_config(data)
    assert_refused_with_no_side_effects(rig, test_reel=False, match="launch gate")


def test_a_non_test_reel_in_test_mode_is_refused(rig):
    assert_refused_with_no_side_effects(rig, test_reel=False, match="launch gate")


def test_a_live_render_with_the_gate_met_uses_the_real_logo(rig):
    rig.use_live_config()
    render(rig, test_reel=False)
    assert props_sent(rig)["brand"]["logo_src"] == "approved_logo.svg"
    assert "approved_logo.svg" in rig.fake.renders[-1].public_files


# --- No real user data in the inputs (spec Section 5.2) --------------------------------


@pytest.mark.parametrize(
    "field",
    ["hook_text", "subtitles_en"],
)
@pytest.mark.parametrize(
    "text",
    [
        "SA0380000000608010167519",
        "call 0512345678 now",
        "+966 51 234 5678",
        "٠٥١٢٣٤٥٦٧٨",
        "owner@example.com",
        "4111 1111 1111 1111",
    ],
)
def test_text_that_looks_like_account_data_is_refused(rig, field, text):
    assert_refused_with_no_side_effects(
        rig, rig.request(**{field: text}), match="account data"
    )


def test_account_data_on_screen_is_refused_and_not_repeated_in_the_message(rig):
    request = rig.request(on_screen_text=["Fine", "SA0380000000608010167519"])
    with pytest.raises(RenderRefused, match="on_screen_text") as caught:
        render(rig, request)
    assert "SA0380000000608010167519" not in str(caught.value)
    assert caught.value.__cause__ is None
    assert caught.value.__suppress_context__ is True


def test_account_data_in_a_caption_word_is_refused(rig):
    with pytest.raises(ValidationError, match="account data"):
        rig.request(words=[{"text": "owner@example.com", "start_ms": 0, "end_ms": 10}])


@pytest.mark.parametrize("field", ["household_id", "user_email", "account", "balance", "notes"])
def test_the_request_has_no_field_for_account_data(rig, field):
    with pytest.raises(ValidationError):
        rig.request(**{field: "x"})


@pytest.mark.parametrize(
    "voiceover",
    ["../manifest.json", "..\\manifest.json", "C:/Windows/win.ini", "/etc/hosts", ".env"],
)
def test_a_voiceover_outside_the_voiceovers_folder_is_refused(rig, voiceover):
    with pytest.raises(ValidationError):
        rig.request(voiceover=voiceover)


@pytest.mark.parametrize("name", ["notes.json", "engine.db", "secrets.txt", "clip.mp4"])
def test_a_voiceover_must_be_an_audio_file(rig, name):
    (rig.paths.voiceovers / name).write_bytes(b"x")
    assert_refused_with_no_side_effects(rig, rig.request(voiceover=name), match="audio")


def test_a_missing_voiceover_is_refused(rig):
    assert_refused_with_no_side_effects(rig, rig.request(voiceover="gone.wav"), match="gone.wav")


def test_a_voiceover_link_to_another_folder_is_refused(rig, tmp_path):
    from conftest import make_junction

    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    (elsewhere / "private.wav").write_bytes(b"private")
    make_junction(rig.paths.voiceovers / "linked", elsewhere)
    assert_refused_with_no_side_effects(
        rig, rig.request(voiceover="linked/private.wav"), match="outside"
    )


def test_music_is_refused_while_it_is_turned_off(rig):
    (rig.paths.bg_music / "track.mp3").write_bytes(b"x")
    assert_refused_with_no_side_effects(rig, rig.request(music="track.mp3"), match="music")


def test_licensed_music_comes_only_from_the_music_folder(rig):
    def change(data):
        data["audio"].update(music_enabled=True, music_library="Licensed Library")

    rig.use_config(change)
    (rig.paths.bg_music / "track.mp3").write_bytes(b"licensed")
    render(rig, rig.request(music="track.mp3"))
    assert props_sent(rig)["music_src"] == "audio/music/track.mp3"
    assert "audio/music/track.mp3" in rig.fake.renders[-1].public_files


def test_only_allow_listed_files_reach_the_render(rig):
    rig.add_clip()
    rig.add_clip("price_tracker/signed_but_unused.mp4", b"unused")
    # None of these may reach the build folder.
    (rig.paths.raw_recordings / "payday_cycle" / "unsigned.mp4").write_bytes(b"unsigned")
    (rig.paths.screenshots / "real_screen.png").write_bytes(b"png")
    rig.data_root.joinpath(".env").write_text("TOKEN=MARKER-IN-ENV-FILE", encoding="utf-8")
    rig.paths.state_db.write_bytes(b"MARKER-IN-DATABASE")
    (rig.paths.logs / "engine.log").write_text("MARKER-IN-LOG", encoding="utf-8")

    render(rig, rig.request(clips=[rig.clip_use()]))

    assert set(rig.fake.renders[-1].public_files) == {
        "approved_logo.svg",  # the rig's branding folder holds it, as the repo's will
        "audio/voice.wav",
        "brand_tokens.json",
        "clips/payday_cycle/clip_01.mp4",
        "test_logo.svg",
    }


def test_a_clip_left_from_an_earlier_reel_is_gone_before_the_next_render(rig):
    rig.add_clip()
    render(rig, rig.request(clips=[rig.clip_use()]))
    render(rig, rig.request(revision=2))
    assert "clips/payday_cycle/clip_01.mp4" not in rig.fake.renders[-1].public_files


def test_props_hold_no_machine_paths_or_secrets(rig, monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "MARKER-TOKEN")
    rig.add_clip()
    render(rig, rig.request(clips=[rig.clip_use()]))
    text = json.dumps(props_sent(rig), ensure_ascii=False)
    assert str(rig.data_root).replace("\\", "\\\\") not in text
    assert "MARKER-TOKEN" not in text
    assert not Path(props_sent(rig)["audio_src"]).is_absolute()


def test_npx_can_never_download_a_package(rig):
    render(rig)
    for call in [*rig.fake.renders, *rig.fake.conforms]:
        assert call.command[1] == "--no"


# --- Values from config ----------------------------------------------------------------


def test_format_values_come_from_config(rig):
    render(rig)
    props = props_sent(rig)
    assert props["fps"] == rig.config.render.fps
    assert props["digits"] == rig.config.captions.digits
    assert props["device_frame"] == "generic"
    assert (props["width"], props["height"]) == (1080, 1920)
    assert props["safe_zones"] == rig.config.render.safe_zones.strictest().model_dump()
    assert props["duck_under_voice"] == rig.config.audio.duck_under_voice
    assert props["duck_in_pauses"] == rig.config.audio.duck_in_pauses


def test_an_inconsistent_request_is_refused_before_any_side_effect(rig):
    # FeatureDemo needs a clip, and the props schema says so.
    assert_refused_with_no_side_effects(rig, rig.request(template="FeatureDemo"), match="clip")
