"""When a reel is generated, and in which language (spec Sections 3.5 and 10.5, D24, D28).

Each tick asks one question: is the latest due slot still unmade? Earlier slots are never looked
at, so a laptop that was off for a week makes one reel and not a pile. All of this works in the
configured time zone, and the time is passed in. Weeks run Sunday to Saturday.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from enum import StrEnum
from fractions import Fraction
from math import floor
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

if TYPE_CHECKING:
    from core.config import Cadence, Schedule

WEEK = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")


class CadenceReason(StrEnum):
    DUE = "due"
    ALREADY_GENERATED = "already_generated"
    WAITING_LIMIT = "waiting_limit"
    WEEK_CAP = "week_cap"


@dataclass(frozen=True)
class Slot:
    key: str  # the slot's date, which also names its run and its reel in the state store
    due_at: datetime


@dataclass(frozen=True)
class GeneratedReel:
    slot_key: str
    created_at: datetime


@dataclass(frozen=True)
class CadenceDecision:
    slot: Slot | None
    reason: CadenceReason


def slot_days(cadence: Cadence) -> tuple[str, ...]:
    """The listed days set the slots. A count below the list uses its earliest days. A count above
    it fills from the rest of the week, so raising `reels_per_week` to 7 alone means one a day."""
    listed = [day for day in WEEK if day in cadence.generation_days]
    others = [day for day in WEEK if day not in cadence.generation_days]
    chosen = (listed + others)[: cadence.reels_per_week]
    return tuple(day for day in WEEK if day in chosen)


def _day_name(day: date) -> str:
    return WEEK[(day.weekday() + 1) % 7]


def _local(moment: datetime, schedule: Schedule) -> datetime:
    if moment.tzinfo is None:
        raise ValueError("a time without a time zone cannot be placed on the schedule")
    return moment.astimezone(ZoneInfo(schedule.timezone))


def latest_due_slot(now: datetime, schedule: Schedule) -> Slot:
    """Config guarantees at least one slot day, so one always falls within the last 7 days."""
    local = _local(now, schedule)
    days = slot_days(schedule.cadence)
    due_time = time.fromisoformat(schedule.generate_after)
    candidates = (local.date() - timedelta(days=back) for back in range(8))
    for day in candidates:
        due_at = datetime.combine(day, due_time, tzinfo=local.tzinfo)
        if _day_name(day) in days and due_at <= local:
            return Slot(day.isoformat(), due_at)
    raise AssertionError("the cadence has no slot days")  # config refuses this on load


def week_start(moment: datetime, schedule: Schedule) -> date:
    day = _local(moment, schedule).date()
    return day - timedelta(days=WEEK.index(_day_name(day)))


def decide_generation(
    now: datetime,
    schedule: Schedule,
    generated: Iterable[GeneratedReel],
    *,
    waiting: int,
    max_waiting: int,
) -> CadenceDecision:
    """The weekly cap counts reels by the week they were made in, not the week of their slot, so
    a reel made late from last week's slot still uses up this week's allowance."""
    slot = latest_due_slot(now, schedule)
    made = list(generated)
    if any(reel.slot_key == slot.key for reel in made):
        return CadenceDecision(None, CadenceReason.ALREADY_GENERATED)
    if waiting >= max_waiting:
        return CadenceDecision(None, CadenceReason.WAITING_LIMIT)
    this_week = week_start(now, schedule)
    made_this_week = sum(week_start(reel.created_at, schedule) == this_week for reel in made)
    if made_this_week >= schedule.cadence.reels_per_week:
        return CadenceDecision(None, CadenceReason.WEEK_CAP)
    return CadenceDecision(slot, CadenceReason.DUE)


def language_for_position(position: int, english_audio_share: float) -> str:
    """The language of the reel with this many reels before it. Spacing the English reels evenly
    is what puts exactly 1 in each rolling 5 at a share of 0.2 (D28), where a random pick or a
    per-week count would not. The share is read through its decimal text, as 0.2 is not exact."""
    if position < 0:
        raise ValueError("a reel position cannot be negative")
    if not 0 <= english_audio_share <= 1:
        raise ValueError("the English audio share must be between 0 and 1")
    share = Fraction(str(english_audio_share))
    return "en" if floor((position + 1) * share) > floor(position * share) else "ar"
