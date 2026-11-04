"""Seed topics and the rolling content mix (spec Section 6.1, decision D5).

The next topic comes from the tier furthest behind its share over the last 30 reels, so the mix
holds within a few points of 50/30/20 whatever the history. A topic rests for `topic_cooldown`
reels, and a feature for `feature_cooldown`. Choosing is deterministic: the same history gives
the same topic, so a re-run after a crash picks what the first run picked.
"""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Collection, Mapping, Sequence
from pathlib import Path
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator, model_validator

from content_engine.schemas import Tier
from core.render_props import ClipFolder, Template

TOPICS_PATH = Path(__file__).resolve().parent / "finance_topics_repository.json"

ROLLING_WINDOW = 30
DEFAULT_TOPIC_COOLDOWN = 30
DEFAULT_FEATURE_COOLDOWN = 1
NO_SEASON = "any"

Region = Literal["global", "arab", "gulf", "saudi"]
Season = Literal["any", "ramadan", "eid", "summer", "back_to_school", "year_end"]

_CLAIM_ID = re.compile(r"C\d{2}")
_TOPIC_ID = re.compile(r"[a-z]\d{3}")


class NoTopicAvailable(Exception):
    """Every topic in season is resting. The caller reports it rather than repeating one."""


def _not_blank(value: str) -> str:
    if not value.strip():
        raise ValueError("must not be empty")
    return value


SeedText = Annotated[str, AfterValidator(_not_blank)]


class Topic(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    tier: Tier
    region: Region
    season: Season
    templates: Annotated[tuple[Template, ...], Field(min_length=1)]
    feature: ClipFolder | None
    claim_ids: tuple[str, ...]
    title_ar: SeedText
    title_en: SeedText
    hook_ar: SeedText

    @field_validator("id")
    @classmethod
    def _id_has_the_seed_shape(cls, value: str) -> str:
        if not _TOPIC_ID.fullmatch(value):
            raise ValueError(f"topic ids look like g001, got {value!r}")
        return value

    @field_validator("claim_ids")
    @classmethod
    def _claim_ids_have_the_register_shape(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        if any(not _CLAIM_ID.fullmatch(claim) for claim in value):
            raise ValueError("claim ids look like C01")
        return value

    @model_validator(mode="after")
    def _a_feature_demo_has_a_clip(self) -> Topic:
        if "FeatureDemo" in self.templates and self.feature is None:
            raise ValueError(f"{self.id}: FeatureDemo needs a feature clip")
        return self


class _TopicsFile(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    schema_version: Literal[1]
    topics: tuple[Topic, ...]

    @model_validator(mode="after")
    def _ids_are_unique(self) -> _TopicsFile:
        ids = [topic.id for topic in self.topics]
        if len(set(ids)) != len(ids):
            raise ValueError("topic ids must be unique")
        return self


def load_topics(path: Path = TOPICS_PATH) -> tuple[Topic, ...]:
    return _TopicsFile.model_validate_json(Path(path).read_bytes().decode("utf-8")).topics


def tier_shares(topics: Sequence[Topic]) -> dict[str, float]:
    counts = Counter(topic.tier for topic in topics)
    return {tier: 100 * counts[tier] / len(topics) for tier in counts}


def _tiers_most_behind(
    known_recent: Sequence[Topic], mix: Mapping[str, int]
) -> list[str]:
    counts = Counter(topic.tier for topic in known_recent)
    size = len(known_recent) + 1  # the reel being chosen counts toward the window
    behind = {tier: share * size / 100 - counts[tier] for tier, share in mix.items()}
    return sorted(mix, key=lambda tier: (-behind[tier], -mix[tier], tier))


def _best_in_tier(
    pool: Sequence[Topic], history: Sequence[str], feature_cooldown: int, by_id: Mapping
) -> Topic:
    """In season first, then a feature that has rested, then the topic used longest ago."""
    last_used = {topic_id: index for index, topic_id in enumerate(history)}
    resting_features = {
        by_id[topic_id].feature
        for topic_id in (history[-feature_cooldown:] if feature_cooldown else ())
        if topic_id in by_id and by_id[topic_id].feature
    }

    def rank(topic: Topic) -> tuple[int, int, int]:
        return (
            0 if topic.season != NO_SEASON else 1,
            1 if topic.feature in resting_features else 0,
            last_used.get(topic.id, -1),
        )

    return min(pool, key=rank)  # min() keeps file order among equals


def select_next(
    topics: Sequence[Topic],
    history: Sequence[str],
    *,
    mix: Mapping[str, int],
    active_seasons: Collection[str] = frozenset({NO_SEASON}),
    topic_cooldown: int = DEFAULT_TOPIC_COOLDOWN,
    feature_cooldown: int = DEFAULT_FEATURE_COOLDOWN,
) -> Topic:
    """`history` is the topic ids already used, oldest first. Ids of retired topics are skipped."""
    by_id = {topic.id: topic for topic in topics}
    known = [topic_id for topic_id in history if topic_id in by_id]
    recent = [by_id[topic_id] for topic_id in known[-(ROLLING_WINDOW - 1) :]]
    resting = set(known[-topic_cooldown:]) if topic_cooldown else set()

    for tier in _tiers_most_behind(recent, mix):
        pool = [
            topic
            for topic in topics
            if topic.tier == tier and topic.season in active_seasons and topic.id not in resting
        ]
        if pool:
            return _best_in_tier(pool, known, feature_cooldown, by_id)
    raise NoTopicAvailable("every topic in season is resting")
