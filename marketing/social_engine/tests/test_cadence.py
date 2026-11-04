"""When a reel is generated, and in which language (spec Sections 3.5 and 10.5, D24, D28, B5)."""

import random
from collections import Counter
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from core.cadence import (
    CadenceReason,
    GeneratedReel,
    decide_generation,
    language_for_position,
    latest_due_slot,
    slot_days,
    week_start,
)
from core.config import Cadence, Schedule, load_config

RIYADH = ZoneInfo("Asia/Riyadh")
MAX_WAITING = 3

# 2026-11-01 is a Sunday, so this week's slots at the default cadence are Nov 1, 3 and 5.
SUNDAY = date(2026, 11, 1)


def at(day: date, hour: int = 12, minute: int = 0) -> datetime:
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=RIYADH)


def schedule_with(reels_per_week: int = 3, days: tuple[str, ...] = ("sun", "tue", "thu")):
    shipped = load_config().schedule
    return shipped.model_copy(
        update={"cadence": Cadence(reels_per_week=reels_per_week, generation_days=list(days))}
    )


THURSDAY_BEFORE = date(2026, 10, 29)


class Laptop:
    """Runs a tick every 30 minutes while it is on, keeping the record the store would keep."""

    def __init__(self, schedule: Schedule, *, made_last_thursday: bool = False) -> None:
        self.schedule = schedule
        self.earlier = (
            [GeneratedReel(THURSDAY_BEFORE.isoformat(), at(THURSDAY_BEFORE, 9, 30))]
            if made_last_thursday
            else []
        )
        self.generated: list[GeneratedReel] = []
        self.waiting = 0

    def tick(self, now: datetime) -> None:
        decision = decide_generation(
            now,
            self.schedule,
            self.earlier + self.generated,
            waiting=self.waiting,
            max_waiting=MAX_WAITING,
        )
        if decision.slot is not None:
            self.generated.append(GeneratedReel(decision.slot.key, now))

    def run(self, start: datetime, end: datetime) -> None:
        now = start
        while now < end:
            self.tick(now)
            now += timedelta(minutes=30)

    def per_week(self) -> Counter:
        return Counter(week_start(reel.created_at, self.schedule) for reel in self.generated)


# --- Slots -------------------------------------------------------------------------------


def test_the_shipped_schedule_makes_three_slots_on_its_generation_days():
    assert slot_days(load_config().schedule.cadence) == ("sun", "tue", "thu")


def test_a_week_of_running_makes_a_reel_on_each_generation_day_and_no_more():
    laptop = Laptop(schedule_with())
    laptop.run(at(SUNDAY, 9), at(SUNDAY + timedelta(days=7), 9))
    assert [reel.slot_key for reel in laptop.generated] == [
        "2026-11-01",
        "2026-11-03",
        "2026-11-05",
    ]
    assert len(laptop.generated) == 3


def test_ten_weeks_never_go_over_three_a_week():
    laptop = Laptop(schedule_with())
    laptop.run(at(SUNDAY, 9), at(SUNDAY + timedelta(weeks=10), 9))
    counts = laptop.per_week()
    assert len(counts) == 10
    assert set(counts.values()) == {3}


def test_at_seven_a_week_it_is_one_a_day():
    laptop = Laptop(schedule_with(7, ("sun", "mon", "tue", "wed", "thu", "fri", "sat")))
    laptop.run(at(SUNDAY, 9), at(SUNDAY + timedelta(days=14), 9))
    days = [reel.slot_key for reel in laptop.generated]
    assert len(days) == 14
    assert len(set(days)) == 14


def test_raising_only_the_count_to_seven_still_gives_one_a_day():
    # D24: "The owner makes that change in config", and that may be this one number.
    laptop = Laptop(schedule_with(7))
    laptop.run(at(SUNDAY, 9), at(SUNDAY + timedelta(days=7), 9))
    assert len({reel.slot_key for reel in laptop.generated}) == 7


def test_a_count_below_the_listed_days_uses_the_earliest_of_them():
    assert slot_days(Cadence(reels_per_week=2, generation_days=["thu", "sun", "tue"])) == (
        "sun",
        "tue",
    )


def test_a_count_above_the_listed_days_keeps_them_and_fills_from_the_rest():
    days = slot_days(Cadence(reels_per_week=4, generation_days=["sun", "tue", "thu"]))
    assert len(days) == 4
    assert {"sun", "tue", "thu"} <= set(days)


def test_a_slot_is_not_due_before_generate_after():
    schedule = schedule_with()
    assert latest_due_slot(at(SUNDAY, 8, 59), schedule).key == "2026-10-29"  # the Thursday before
    assert latest_due_slot(at(SUNDAY, 9, 0), schedule).key == "2026-11-01"


def test_the_day_turns_over_in_riyadh_rather_than_in_utc():
    schedule = schedule_with()
    # 22:00 UTC on Saturday is 01:00 on Sunday in Riyadh, and still before 09:00 there.
    saturday_night_utc = datetime(2026, 10, 31, 22, 0, tzinfo=UTC)
    assert latest_due_slot(saturday_night_utc, schedule).key == "2026-10-29"
    # 06:00 UTC on Sunday is exactly 09:00 in Riyadh.
    sunday_morning_utc = datetime(2026, 11, 1, 6, 0, tzinfo=UTC)
    assert latest_due_slot(sunday_morning_utc, schedule).key == "2026-11-01"


def test_a_naive_time_is_refused_rather_than_guessed():
    with pytest.raises(ValueError, match="time zone"):
        latest_due_slot(datetime(2026, 11, 1, 12, 0), schedule_with())


def test_the_slot_due_time_is_in_riyadh():
    slot = latest_due_slot(at(SUNDAY, 12), schedule_with())
    assert slot.due_at == at(SUNDAY, 9)


# --- Decisions -----------------------------------------------------------------------------


def decide(now, generated=(), waiting=0, schedule=None):
    return decide_generation(
        now, schedule or schedule_with(), generated, waiting=waiting, max_waiting=MAX_WAITING
    )


def test_a_due_slot_is_returned_once_and_a_re_run_finds_it_done():
    first = decide(at(SUNDAY))
    assert first.reason == CadenceReason.DUE
    assert first.slot.key == "2026-11-01"

    again = decide(at(SUNDAY, 13), [GeneratedReel(first.slot.key, at(SUNDAY))])

    assert again.slot is None
    assert again.reason == CadenceReason.ALREADY_GENERATED


def test_a_laptop_off_for_three_days_gives_one_reel_not_four():
    # Off from last Thursday until Wednesday noon: the Sunday and Tuesday slots were missed.
    laptop = Laptop(schedule_with(), made_last_thursday=True)
    laptop.run(at(SUNDAY + timedelta(days=3), 12), at(SUNDAY + timedelta(days=4), 9))
    assert [reel.slot_key for reel in laptop.generated] == ["2026-11-03"]


def test_a_laptop_off_for_a_week_gives_one_reel():
    laptop = Laptop(schedule_with(), made_last_thursday=True)
    laptop.run(at(SUNDAY + timedelta(days=7), 12), at(SUNDAY + timedelta(days=7), 18))
    assert [reel.slot_key for reel in laptop.generated] == ["2026-11-08"]


def test_a_laptop_off_for_a_week_on_a_day_with_no_slot_still_gives_one_reel():
    laptop = Laptop(schedule_with(), made_last_thursday=True)
    monday_after = SUNDAY + timedelta(days=8)
    laptop.run(at(monday_after, 12), at(monday_after, 18))
    assert [reel.slot_key for reel in laptop.generated] == ["2026-11-08"]


def test_a_missed_slot_is_never_backfilled_afterwards():
    laptop = Laptop(schedule_with(), made_last_thursday=True)
    # Sunday was missed. Tuesday's slot runs, and the days after find nothing to go back to.
    laptop.run(at(SUNDAY + timedelta(days=2), 12), at(SUNDAY + timedelta(days=4), 8))
    assert [reel.slot_key for reel in laptop.generated] == ["2026-11-03"]


def test_a_late_slot_from_last_week_counts_towards_the_week_it_was_made_in():
    # Off from last Thursday. A tick at 08:59 on Sunday makes last Thursday's reel, and this week
    # can then only make two more, so this week never goes over three.
    made_late = GeneratedReel("2026-10-29", at(SUNDAY, 8, 59))
    sunday = GeneratedReel("2026-11-01", at(SUNDAY, 9, 30))
    tuesday = GeneratedReel("2026-11-03", at(SUNDAY + timedelta(days=2), 9, 30))

    decision = decide(at(SUNDAY + timedelta(days=4), 9, 30), [made_late, sunday, tuesday])

    assert decision.slot is None
    assert decision.reason == CadenceReason.WEEK_CAP


def test_lowering_the_count_mid_week_stops_generation_at_the_new_cap():
    already = [GeneratedReel("2026-11-01", at(SUNDAY))]
    decision = decide(at(SUNDAY + timedelta(days=2)), already, schedule=schedule_with(1))
    # At one a week the only slot day is Sunday, and it is already made.
    assert decision.slot is None


@pytest.mark.parametrize("seed", range(5))
def test_random_power_cuts_never_break_the_limits(seed):
    rng = random.Random(seed)
    schedule = schedule_with()
    laptop = Laptop(schedule)
    now = at(SUNDAY, 0)
    end = now + timedelta(weeks=26)
    while now < end:
        on_for = timedelta(hours=rng.randint(1, 72))
        laptop.run(now, min(now + on_for, end))
        now += on_for + timedelta(hours=rng.randint(0, 24 * 9))

    slots = [reel.slot_key for reel in laptop.generated]
    assert len(slots) == len(set(slots)), "two reels for one slot"
    assert max(laptop.per_week().values()) <= 3
    assert slots == sorted(slots), "an earlier slot was filled after a later one"
    sunday_tuesday_thursday = {6, 1, 3}  # as date.weekday() numbers them
    for reel in laptop.generated:
        assert date.fromisoformat(reel.slot_key).weekday() in sunday_tuesday_thursday


# --- Waiting -------------------------------------------------------------------------------


def test_generation_pauses_at_max_waiting():
    decision = decide(at(SUNDAY), waiting=MAX_WAITING)
    assert decision.slot is None
    assert decision.reason == CadenceReason.WAITING_LIMIT


def test_generation_runs_just_below_max_waiting():
    assert decide(at(SUNDAY), waiting=MAX_WAITING - 1).slot is not None


def test_a_slot_passed_over_while_waiting_is_not_made_up_later():
    laptop = Laptop(schedule_with(), made_last_thursday=True)
    laptop.waiting = MAX_WAITING
    laptop.run(at(SUNDAY, 9), at(SUNDAY + timedelta(days=3), 12))
    assert laptop.generated == []

    laptop.waiting = 0
    laptop.run(at(SUNDAY + timedelta(days=3), 12), at(SUNDAY + timedelta(days=3), 18))
    assert [reel.slot_key for reel in laptop.generated] == ["2026-11-03"]


def test_the_shipped_config_says_three_waiting():
    assert load_config().approval.max_waiting == MAX_WAITING


# --- Week edges ----------------------------------------------------------------------------


@pytest.mark.parametrize("offset", range(7))
def test_the_week_starts_on_sunday_in_riyadh(offset):
    schedule = schedule_with()
    assert week_start(at(SUNDAY + timedelta(days=offset)), schedule) == SUNDAY


def test_the_next_sunday_is_a_new_week():
    assert week_start(at(SUNDAY + timedelta(days=7)), schedule_with()) == date(2026, 11, 8)


# --- Language ------------------------------------------------------------------------------


def languages(count: int, share: float) -> list[str]:
    return [language_for_position(position, share) for position in range(count)]


def test_one_in_five_is_exactly_one_english_reel_in_each_rolling_five():
    sequence = languages(200, 0.2)
    for start in range(len(sequence) - 4):
        assert sequence[start : start + 5].count("en") == 1


def test_the_shipped_share_gives_one_in_five():
    share = load_config().content.english_audio_share
    assert languages(10, share).count("en") == 2


def test_the_first_reels_are_arabic_since_arabic_is_the_default():
    assert languages(4, 0.2) == ["ar", "ar", "ar", "ar"]
    assert language_for_position(4, 0.2) == "en"


@pytest.mark.parametrize(("share", "english"), [(0.0, 0), (1.0, 50), (0.5, 25), (0.1, 5)])
def test_other_shares_hold_over_a_long_run(share, english):
    assert languages(50, share).count("en") == english


def test_a_position_cannot_be_negative():
    with pytest.raises(ValueError, match="position"):
        language_for_position(-1, 0.2)


@pytest.mark.parametrize("share", [-0.1, 1.1])
def test_a_share_outside_zero_and_one_is_refused(share):
    with pytest.raises(ValueError, match="share"):
        language_for_position(0, share)
