"""Seed topics and the content mix (spec Section 6.1, decisions D5, D29, D32, task C6).

The mix is 50% global, 30% regional Arab and 20% Saudi launch. Seeds are education first, carry
no bank name, no 30% figure, no click count, no fixed 27th and no "link in bio", and every one
passes the deterministic guardrails before the owner reads them at LIVE-6.
"""

import json
import re
from collections import Counter

import pytest

from content_engine import denylists
from content_engine.cta import compose_voice
from content_engine.guardrails import (
    GuardrailContext,
    check_claim_ids,
    check_script,
    check_text,
    lexicon_form,
    load_claims_register,
)
from content_engine.schemas import Script
from content_engine.topics import (
    TOPICS_PATH,
    NoTopicAvailable,
    Topic,
    load_topics,
    select_next,
    tier_shares,
)
from core.brand_gate import ReelBrand
from core.config import load_config
from core.paths import RAW_RECORDING_FOLDERS

TOPICS = load_topics()
MIX = load_config().content.mix
POINTS_ALLOWED = 5  # "within a few points" (spec Section 6.1)
TEXT_FIELDS = ("title_ar", "title_en", "hook_ar")


def _context(topic: Topic) -> GuardrailContext:
    return GuardrailContext(
        claim_ids=frozenset(topic.claim_ids),
        basket=topic.feature == "smart_basket",
        family="C11" in topic.claim_ids,
    )


def _rolling_shares(selected: list[str], by_id: dict[str, Topic], window: int = 30):
    for end in range(window, len(selected) + 1):
        tiers = Counter(by_id[topic_id].tier for topic_id in selected[end - window : end])
        yield {tier: 100 * tiers[tier] / window for tier in MIX}


def _run(count: int, topics=TOPICS, mix=MIX, **kwargs) -> list[str]:
    history: list[str] = []
    for _ in range(count):
        history.append(select_next(topics, history, mix=mix, **kwargs).id)
    return history


# --- The seeds -------------------------------------------------------------------------------


def test_there_are_about_100_topics():
    assert 95 <= len(TOPICS) <= 105


def test_topic_ids_are_unique_and_fit_the_script_schema():
    ids = [topic.id for topic in TOPICS]
    assert len(set(ids)) == len(ids)
    assert all(re.fullmatch(r"[a-z]\d{3}", topic_id) for topic_id in ids)


def test_the_tier_shares_are_near_the_mix():
    shares = tier_shares(TOPICS)
    for tier, target in MIX.items():
        assert abs(shares[tier] - target) <= POINTS_ALLOWED, f"{tier}: {shares[tier]}"


def test_the_mix_is_the_owners_50_30_20():
    assert MIX == {"global": 50, "regional": 30, "saudi": 20}


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
def test_each_tag_is_valid(topic):
    assert topic.tier in {"global", "regional", "saudi"}
    assert topic.region in {"global", "arab", "gulf", "saudi"}
    assert topic.season in {"any", "ramadan", "eid", "summer", "back_to_school", "year_end"}
    assert topic.templates
    assert set(topic.templates) <= {"FeatureDemo", "DailyTip", "MythVsFact"}
    assert topic.feature is None or topic.feature in RAW_RECORDING_FOLDERS


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
def test_each_claim_id_is_valid_and_backed_by_code(topic):
    assert check_claim_ids(topic.claim_ids, load_claims_register()) == []


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
def test_each_feature_topic_carries_a_claim_for_that_feature(topic):
    register = load_claims_register()
    if topic.feature is None:
        assert "FeatureDemo" not in topic.templates, "FeatureDemo needs a clip"
        return
    assert topic.claim_ids, "a topic that leads to a feature needs its claim"
    claims = register.claims.values()
    allowed = {claim.id for claim in claims if topic.feature in claim.clip_folders}
    assert set(topic.claim_ids) & allowed


def test_the_tiers_lead_to_the_feature_mix_the_spec_describes():
    assert any(topic.feature for topic in TOPICS if topic.tier == "saudi")
    assert any("C12" in topic.claim_ids for topic in TOPICS if topic.tier == "global")
    assert any("C11" in topic.claim_ids for topic in TOPICS if topic.tier == "regional")
    assert any("C05" in topic.claim_ids for topic in TOPICS if topic.tier == "saudi")
    assert any("C09" in topic.claim_ids for topic in TOPICS if topic.tier == "saudi")


def test_seasonal_topics_cover_ramadan_and_eid():
    seasons = Counter(topic.season for topic in TOPICS)
    assert seasons["ramadan"] >= 3
    assert seasons["eid"] >= 2


def test_most_topics_teach_rather_than_sell():
    # "Education first" (spec Section 6.1).
    with_feature = sum(1 for topic in TOPICS if topic.feature)
    assert with_feature <= len(TOPICS) / 2


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
@pytest.mark.parametrize("field", TEXT_FIELDS)
def test_each_seed_passes_the_deterministic_guardrails(topic, field):
    report = check_text(getattr(topic, field), _context(topic), f"{topic.id}.{field}")
    assert report.hard_failures == []


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
@pytest.mark.parametrize("field", TEXT_FIELDS)
def test_no_seed_gets_a_soft_bank_flag(topic, field):
    # Seed topics carry no bank wording at all (D29), so not even the plain word.
    report = check_text(getattr(topic, field), _context(topic))
    assert [finding for finding in report.soft_flags if finding.rule == "G20"] == []


def _forbidden_in_seeds(text: str) -> list[str]:
    form = lexicon_form(text)
    found = [
        term
        for term in denylists.BANK_AND_WALLET_NAMES + denylists.BANK_WORDS
        if lexicon_form(term) in form.split()
    ]
    if re.search(r"30\s*%|%\s*30|ثلاثين|\d\s*/\s*30\s*/\s*\d", form):
        found.append("a 30% figure")
    if re.search(r"\d\s*(click|tap)|(click|tap)s\b|نقرات|ضغطات", form):
        found.append("a click count")
    if re.search(r"\b27\b|27th|السابع والعشرين", form):
        found.append("a fixed 27th")
    if re.search(r"link in bio|linkinbio|البايو", form):
        found.append("link in bio")
    return found


@pytest.mark.parametrize("topic", TOPICS, ids=lambda topic: topic.id)
def test_no_seed_holds_a_dropped_claim(topic):
    for field in TEXT_FIELDS:
        text = getattr(topic, field)
        assert _forbidden_in_seeds(text) == [], f"{topic.id}.{field}: {text}"


def test_no_seed_holds_a_rejected_sample():
    raw = TOPICS_PATH.read_bytes().decode("utf-8")
    for row in load_claims_register().rejected:
        for sample in (*row.samples_ar, *row.samples_en):
            assert sample not in raw, f"{row.id}: {sample}"


def test_the_budget_rule_seeds_do_not_lead_to_a_30_percent_figure():
    # 50/30/20 can only be explained by saying 30%, which R01 fails every time.
    for topic in TOPICS:
        for field in TEXT_FIELDS:
            assert "50/30/20" not in getattr(topic, field), topic.id
    assert {"g021", "g022"} <= {topic.id for topic in TOPICS}


CLAIM_FREE = [topic for topic in TOPICS if not topic.claim_ids]


def test_most_seeds_are_general_tips():
    assert len(CLAIM_FREE) >= 76


@pytest.mark.parametrize("topic", CLAIM_FREE, ids=lambda topic: topic.id)
def test_a_general_tip_on_each_claim_free_seed_passes_check_script(topic):
    # The engine adds the closing line, so a tip with no claims is not a product statement.
    script = Script(
        topic_id=topic.id,
        tier=topic.tier,
        template=topic.templates[0],
        language="ar",
        hook_ar=topic.hook_ar,
        voice_script=topic.title_ar,
        on_screen_en=[topic.title_en],
        subtitles_en=topic.title_en,
        feature_clip_folder=None,
        claim_ids=[],
        numbers=[],
        sources=[],
        caption_ar=topic.title_ar,
        caption_en=topic.title_en,
        hashtags=["{brand_hashtag}", "#budgeting"],
        speech_seconds_estimate=32.0,
    )
    brand = ReelBrand("قوام المال", "Qawam Money", "#QawamMoney", "logo.svg", is_test=False)
    config = load_config()
    report = check_script(script, config=config, brand=brand)
    assert report.hard_failures == []
    spoken = compose_voice(script.voice_script, "ar", config, brand)
    assert spoken.count("قوام المال") == 1


@pytest.mark.parametrize("topic_id", ["s007", "s009"])
def test_the_seeds_that_call_the_qr_al_ramz_still_pass_g21(topic_id):
    topic = next(topic for topic in TOPICS if topic.id == topic_id)
    assert "الرمز" in topic.title_ar + topic.hook_ar
    for field in TEXT_FIELDS:
        report = check_text(getattr(topic, field), _context(topic))
        assert "G21" not in {finding.rule for finding in report.hard_failures}


def test_a_transfer_fee_topic_stays_general():
    fee_topics = [topic for topic in TOPICS if "transfer" in topic.title_en.casefold()]
    assert fee_topics, "the spec lists remittances and transfer fees for Tier 2"
    for topic in fee_topics:
        assert topic.tier == "regional"
        assert _forbidden_in_seeds(topic.title_en) == []
        assert _forbidden_in_seeds(topic.title_ar) == []


@pytest.mark.parametrize(
    "bad",
    [
        "Save with Al Rajhi",
        "Link in bio",
        "Done in 3 clicks",
        "Payday on the 27th",
        "Save 30%",
        "50/30/20 explained",
    ],
)
def test_the_seed_checks_would_catch_each_dropped_claim(bad):
    assert _forbidden_in_seeds(bad) or check_text(bad).hard_failures


# --- Loading refuses a bad file -----------------------------------------------------------------


def _write_topics(tmp_path, topics: list[dict]) -> object:
    path = tmp_path / "topics.json"
    path.write_text(json.dumps({"schema_version": 1, "topics": topics}), encoding="utf-8")
    return path


def _raw_topic(**changes) -> dict:
    return {
        "id": "g001",
        "tier": "global",
        "region": "global",
        "season": "any",
        "templates": ["DailyTip"],
        "feature": None,
        "claim_ids": [],
        "title_ar": "ميزانيتك",
        "title_en": "Your budget",
        "hook_ar": "راتبك وين يروح؟",
        **changes,
    }


def test_load_reads_a_valid_file(tmp_path):
    assert load_topics(_write_topics(tmp_path, [_raw_topic()]))[0].id == "g001"


@pytest.mark.parametrize(
    "changes",
    [
        {"tier": "europe"},
        {"region": "mars"},
        {"season": "someday"},
        {"templates": []},
        {"templates": ["Unknown"]},
        {"feature": "not_a_folder"},
        {"claim_ids": ["X1"]},
        {"extra": "field"},
    ],
)
def test_load_refuses_a_bad_topic(tmp_path, changes):
    with pytest.raises(ValueError):
        load_topics(_write_topics(tmp_path, [_raw_topic(**changes)]))


def test_load_refuses_a_repeated_id(tmp_path):
    with pytest.raises(ValueError):
        load_topics(_write_topics(tmp_path, [_raw_topic(), _raw_topic()]))


# --- Selection -----------------------------------------------------------------------------------


def test_a_rolling_30_reel_selection_stays_within_a_few_points():
    selected = _run(300)
    by_id = {topic.id: topic for topic in TOPICS}
    for shares in _rolling_shares(selected, by_id):
        for tier, target in MIX.items():
            assert abs(shares[tier] - target) <= POINTS_ALLOWED, f"{tier}: {shares}"


def test_the_first_30_reels_already_hold_the_mix():
    selected = _run(30)
    by_id = {topic.id: topic for topic in TOPICS}
    tiers = Counter(by_id[topic_id].tier for topic_id in selected)
    assert tiers == {"global": 15, "regional": 9, "saudi": 6}


def test_a_topic_is_not_repeated_within_its_cooldown():
    selected = _run(300, topic_cooldown=30)
    for end in range(30, len(selected)):
        recent = selected[end - 30 : end]
        assert selected[end] not in recent


def test_a_feature_is_not_repeated_back_to_back():
    selected = _run(100, feature_cooldown=1)
    by_id = {topic.id: topic for topic in TOPICS}
    features = [by_id[topic_id].feature for topic_id in selected]
    for before, after in zip(features, features[1:], strict=False):
        assert before is None or before != after


def test_selection_is_deterministic():
    assert _run(60) == _run(60)


def test_selection_starts_from_any_history():
    history = [topic.id for topic in TOPICS if topic.tier == "global"][:10]
    next_topic = select_next(TOPICS, history, mix=MIX)
    assert next_topic.tier != "global"


def test_a_retired_id_in_the_history_is_ignored():
    assert select_next(TOPICS, ["gone", "also-gone"], mix=MIX)


def test_seasonal_topics_wait_for_their_season():
    selected = _run(100)
    by_id = {topic.id: topic for topic in TOPICS}
    assert {by_id[topic_id].season for topic_id in selected} == {"any"}


def test_a_seasonal_topic_runs_in_its_season():
    selected = _run(30, active_seasons=frozenset({"any", "ramadan"}))
    by_id = {topic.id: topic for topic in TOPICS}
    assert "ramadan" in {by_id[topic_id].season for topic_id in selected}


def test_a_short_tier_falls_back_to_the_next_most_needed_tier():
    topics = [
        Topic(**_raw_topic(id="g001")),
        Topic(**_raw_topic(id="r001", tier="regional", region="arab")),
    ]
    history: list[str] = []
    for _ in range(2):
        history.append(select_next(topics, history, mix=MIX, topic_cooldown=0).id)
    assert set(history) == {"g001", "r001"}


def test_running_out_of_topics_says_so():
    topics = [Topic(**_raw_topic(id="g001"))]
    with pytest.raises(NoTopicAvailable):
        select_next(topics, ["g001"], mix=MIX, topic_cooldown=5)
