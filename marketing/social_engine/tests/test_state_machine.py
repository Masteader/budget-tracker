"""The reel state machine, table-driven from spec Section 3.3 (task B2).

The table is written out again here, on purpose, rather than imported from `core.state`: a
wrong edge in the code must show up as a difference from the spec.
"""

import sqlite3
from datetime import timedelta
from itertools import product

import pytest
from state_support import HOURS_TO_EXPIRE, TWO_PLATFORMS, Bench, Clock, live_config, make_video, tap

from core.state import (
    ALLOWED_POST_CHANGES,
    ALLOWED_TRANSITIONS,
    OWNER_ONLY_TRANSITIONS,
    PLAIN_TRANSITIONS,
    ActionRefused,
    IllegalTransition,
    OwnerTapRequired,
    PostOutcome,
    PostStatus,
    ReelState,
    StateStore,
    TapAction,
)

S = ReelState


def _engine_plain(bench, reel, target):
    assert bench.store.transition(reel.reel_id, reel.state, target)


def _retry_after_block(bench, reel, _target):
    assert bench.store.retry_after_block(reel.reel_id, reel.revision, max_regenerations=3)


def _record_voiced(bench, reel, _target):
    assert bench.store.record_voiced(reel.reel_id, reel.revision, "S0")


def _record_rendered(bench, reel, _target):
    bench.prove(reel.reel_id, reel.revision)
    assert bench.store.record_rendered(
        reel.reel_id, reel.revision, bench.video, "content-hash", bench.config
    )


def _offer(bench, reel, _target):
    assert bench.store.offer_for_approval(reel.reel_id, reel.revision, bench.config)


def _test_delivered(bench, reel, _target):
    assert bench.store.mark_test_delivered(reel.reel_id, reel.revision)


def _tapping(action, platform=None):
    def perform(bench, reel, _target):
        result = bench.store.apply_tap(tap(reel, action, platform=platform), bench.config)
        assert result.applied, result

    return perform


def _expire(bench, reel, _target):
    bench.clock.advance(hours=HOURS_TO_EXPIRE)
    assert reel.reel_id in bench.store.expire_overdue(HOURS_TO_EXPIRE)


def _requeue(bench, reel, _target):
    assert bench.store.requeue(reel.reel_id, bench.config)


def _finish_regeneration(bench, reel, _target):
    assert bench.store.finish_regeneration(reel.reel_id, reel.revision)


def _schedule(bench, reel, _target):
    assert bench.store.schedule_reel(
        reel.reel_id, reel.revision, bench.clock() + timedelta(hours=1)
    )


def _start_publishing(bench, reel, _target):
    bench.clock.now = reel.scheduled_for
    assert bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)


def _next_window(bench, reel, _target):
    assert bench.store.reschedule(reel.reel_id, reel.revision, bench.clock() + timedelta(days=1))


def _every_platform_posted(bench, reel, _target):
    for platform in TWO_PLATFORMS:
        claim = bench.claim(reel.reel_id, platform)
        bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="remote-1")


def _platform_failed(bench, reel, _target):
    claim = bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    bench.store.record_post_result(claim, PostOutcome.FAILED)


def _owner_confirms_the_last_platform(bench, reel, _target):
    assert bench.store.skip_platform(reel.reel_id, TWO_PLATFORMS[1])
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION
    result = bench.store.apply_tap(
        tap(reel, TapAction.POSTED, platform=TWO_PLATFORMS[0]), bench.config
    )
    assert result.applied, result


def _file_changed_before_publishing(bench, reel, _target):
    bench.video.write_bytes(b"swapped after the owner approved")
    if reel.state == S.PUBLISHING:
        with pytest.raises(ActionRefused, match="hash_changed"):
            bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    elif reel.state == S.SCHEDULED:
        with pytest.raises(ActionRefused, match="hash_changed"):
            bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)
    else:
        assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)


# (from, to): how the spec says it happens. Sections 3.3 and 9.3.
SPEC_ENGINE_EDGES = {
    (S.DRAFT, S.BLOCKED_GUARDRAILS): _engine_plain,
    (S.BLOCKED_GUARDRAILS, S.DRAFT): _retry_after_block,
    (S.DRAFT, S.VOICED): _record_voiced,
    (S.VOICED, S.RENDERED): _record_rendered,
    (S.RENDERED, S.AWAITING_APPROVAL): _offer,
    (S.RENDERED, S.TEST_DELIVERED): _test_delivered,
    (S.AWAITING_APPROVAL, S.EXPIRED): _expire,
    (S.EXPIRED, S.AWAITING_APPROVAL): _requeue,
    (S.REGENERATING, S.DRAFT): _finish_regeneration,
    (S.APPROVED, S.SCHEDULED): _schedule,
    (S.SCHEDULED, S.PUBLISHING): _start_publishing,
    # Section 3.5: "It moves to the next window", also for a reel a crash left part way out.
    (S.PUBLISHING, S.SCHEDULED): _next_window,
    (S.PUBLISHING, S.POSTED): _every_platform_posted,
    (S.PUBLISHING, S.NEEDS_ATTENTION): _platform_failed,
    # "Any step before approval on repeated error"
    (S.DRAFT, S.FAILED): _engine_plain,
    (S.BLOCKED_GUARDRAILS, S.FAILED): _engine_plain,
    (S.VOICED, S.FAILED): _engine_plain,
    (S.RENDERED, S.FAILED): _engine_plain,
    (S.REGENERATING, S.FAILED): _engine_plain,
    # Invariant 2: "A mismatch sends the reel back to awaiting_approval"
    (S.APPROVED, S.AWAITING_APPROVAL): _file_changed_before_publishing,
    (S.SCHEDULED, S.AWAITING_APPROVAL): _file_changed_before_publishing,
    (S.PUBLISHING, S.AWAITING_APPROVAL): _file_changed_before_publishing,
}
SPEC_OWNER_EDGES = {
    (S.AWAITING_APPROVAL, S.APPROVED): _tapping(TapAction.APPROVE),
    (S.AWAITING_APPROVAL, S.REGENERATING): _tapping(TapAction.REGENERATE),
    (S.AWAITING_APPROVAL, S.REJECTED): _tapping(TapAction.REJECT),
    (S.NEEDS_ATTENTION, S.PUBLISHING): _tapping(TapAction.RETRY, TWO_PLATFORMS[0]),
    (S.NEEDS_ATTENTION, S.POSTED): _owner_confirms_the_last_platform,
}
SPEC_EDGES = SPEC_ENGINE_EDGES | SPEC_OWNER_EDGES
ALL_PAIRS = [(old, new) for old, new in product(S, S) if old != new]
REFUSED_PAIRS = [pair for pair in ALL_PAIRS if pair not in SPEC_EDGES]


def edge_id(pair) -> str:
    return f"{pair[0]}>{pair[1]}"


@pytest.fixture
def bench(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        yield Bench(store, live_config(tmp_path), make_video(tmp_path), clock)


def test_the_code_table_is_exactly_the_spec_table():
    assert set(ALLOWED_TRANSITIONS) == set(SPEC_EDGES)
    assert set(OWNER_ONLY_TRANSITIONS) == set(SPEC_OWNER_EDGES)


@pytest.mark.parametrize("edge", SPEC_EDGES, ids=edge_id)
def test_every_allowed_transition_works_and_writes_an_event(bench, edge):
    old, new = edge
    reel = bench.rendered(is_test=True) if new == S.TEST_DELIVERED else bench.walk_to(old)
    events_before = len(bench.store.events_for(reel.reel_id))

    SPEC_EDGES[edge](bench, reel, new)

    assert bench.refresh(reel).state == new
    changes = [
        event
        for event in bench.store.events_for(reel.reel_id)[events_before:]
        if event.kind == "transition"
    ]
    assert (changes[-1].from_state, changes[-1].to_state) == (old, new)


@pytest.mark.parametrize("edge", REFUSED_PAIRS, ids=edge_id)
def test_every_other_transition_is_refused_and_leaves_no_trace(bench, edge):
    old, new = edge
    reel = bench.walk_to(old)
    events_before = bench.store.events_for(reel.reel_id)

    with pytest.raises(IllegalTransition):
        bench.store.transition(reel.reel_id, old, new)

    assert bench.refresh(reel) == reel
    assert bench.store.events_for(reel.reel_id) == events_before


@pytest.mark.parametrize("edge", REFUSED_PAIRS, ids=edge_id)
def test_every_other_transition_also_fails_at_the_database(bench, edge):
    old, new = edge
    reel = bench.walk_to(old)
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(
            "UPDATE reels SET state = ? WHERE reel_id = ?", (new, reel.reel_id)
        )
    assert bench.refresh(reel) == reel


@pytest.mark.parametrize("edge", SPEC_OWNER_EDGES, ids=edge_id)
def test_the_plain_method_cannot_make_an_owner_only_move(bench, edge):
    old, new = edge
    reel = bench.walk_to(old)
    with pytest.raises(OwnerTapRequired):
        bench.store.transition(reel.reel_id, old, new)
    assert bench.refresh(reel) == reel


@pytest.mark.parametrize(
    "edge", sorted(set(SPEC_ENGINE_EDGES) - PLAIN_TRANSITIONS), ids=edge_id
)
def test_a_move_that_carries_data_or_checks_cannot_go_through_the_plain_method(bench, edge):
    old, new = edge
    reel = bench.walk_to(old)
    with pytest.raises(IllegalTransition):
        bench.store.transition(reel.reel_id, old, new)
    assert bench.refresh(reel) == reel


@pytest.mark.parametrize("old", [S.POSTED, S.REJECTED, S.TEST_DELIVERED, S.FAILED])
def test_a_terminal_state_never_changes(bench, old):
    reel = bench.walk_to(old)
    for new in S:
        if new != old:
            with pytest.raises(IllegalTransition):
                bench.store.transition(reel.reel_id, old, new)
            with pytest.raises(sqlite3.IntegrityError):
                bench.store._db.execute(
                    "UPDATE reels SET state = ? WHERE reel_id = ?", (new, reel.reel_id)
                )
    assert bench.refresh(reel).state == old


@pytest.mark.parametrize(
    ("actual", "claimed", "target"),
    [
        (S.VOICED, S.DRAFT, S.FAILED),
        (S.FAILED, S.DRAFT, S.BLOCKED_GUARDRAILS),
        (S.BLOCKED_GUARDRAILS, S.VOICED, S.FAILED),
    ],
)
def test_a_compare_and_swap_with_the_wrong_state_changes_nothing(bench, actual, claimed, target):
    reel = bench.walk_to(actual)
    events_before = bench.store.events_for(reel.reel_id)

    assert bench.store.transition(reel.reel_id, claimed, target) is False

    assert bench.refresh(reel) == reel
    assert bench.store.events_for(reel.reel_id) == events_before


def test_the_second_of_two_identical_moves_finds_it_already_done(bench):
    reel = bench.new_reel()
    assert bench.store.transition(reel.reel_id, S.DRAFT, S.FAILED) is True
    assert bench.store.transition(reel.reel_id, S.DRAFT, S.FAILED) is False
    changes = [e for e in bench.store.events_for(reel.reel_id) if e.to_state == S.FAILED]
    assert len(changes) == 1


@pytest.mark.parametrize(
    "call",
    [
        lambda bench, reel: bench.store.record_voiced(reel.reel_id, reel.revision + 1, "S0"),
        lambda bench, reel: bench.store.record_voiced("no-such-reel", 1, "S0"),
    ],
    ids=["old revision", "unknown reel"],
)
def test_a_stale_or_unknown_engine_step_changes_nothing(bench, call):
    reel = bench.new_reel()
    assert call(bench, reel) is False
    assert bench.refresh(reel) == reel


def test_a_transition_on_an_unknown_reel_changes_nothing(bench):
    assert bench.store.transition("no-such-reel", S.DRAFT, S.FAILED) is False


def test_a_new_reel_starts_as_draft_at_revision_one_with_a_creation_event(bench):
    reel = bench.new_reel()
    assert (reel.state, reel.revision) == (S.DRAFT, 1)
    created = bench.store.events_for(reel.reel_id)[0]
    assert (created.from_state, created.to_state) == (None, S.DRAFT)


def test_going_back_to_draft_raises_the_revision_and_drops_the_old_file(bench):
    reel = bench.walk_to(S.REGENERATING)
    assert reel.mp4_sha256 is not None

    assert bench.store.finish_regeneration(reel.reel_id, reel.revision)

    fresh = bench.refresh(reel)
    assert fresh.revision == reel.revision + 1
    assert (fresh.mp4_path, fresh.mp4_sha256, fresh.content_hash, fresh.voice_tier) == (
        None,
        None,
        None,
        None,
    )


def test_a_blocked_reel_cannot_retry_past_the_regeneration_limit(bench):
    reel = bench.walk_to(S.BLOCKED_GUARDRAILS)
    assert bench.store.retry_after_block(reel.reel_id, reel.revision, max_regenerations=1)
    fresh = bench.refresh(reel)
    assert bench.store.transition(fresh.reel_id, S.DRAFT, S.BLOCKED_GUARDRAILS)

    assert (
        bench.store.retry_after_block(fresh.reel_id, fresh.revision, max_regenerations=1) is False
    )

    assert bench.refresh(fresh).state == S.BLOCKED_GUARDRAILS


def test_only_awaiting_reels_past_the_limit_expire(bench):
    young = bench.walk_to(S.AWAITING_APPROVAL)
    bench.clock.advance(hours=HOURS_TO_EXPIRE - 1)
    newer = bench.walk_to(S.AWAITING_APPROVAL)
    bench.clock.advance(hours=1)

    assert bench.store.expire_overdue(HOURS_TO_EXPIRE) == [young.reel_id]

    assert bench.refresh(newer).state == S.AWAITING_APPROVAL


def test_a_requeued_reel_gets_a_fresh_expiry_clock(bench):
    reel = bench.walk_to(S.EXPIRED)
    assert bench.store.requeue(reel.reel_id, bench.config)
    assert bench.store.expire_overdue(HOURS_TO_EXPIRE) == []
    bench.clock.advance(hours=HOURS_TO_EXPIRE)
    assert bench.store.expire_overdue(HOURS_TO_EXPIRE) == [reel.reel_id]


def test_rescheduling_moves_the_window_and_leaves_the_state(bench):
    reel = bench.walk_to(S.SCHEDULED)
    later = reel.scheduled_for + timedelta(days=1)

    assert bench.store.reschedule(reel.reel_id, reel.revision, later)

    fresh = bench.refresh(reel)
    assert (fresh.state, fresh.scheduled_for) == (S.SCHEDULED, later)


def test_a_naive_time_is_refused_rather_than_guessed(bench):
    reel = bench.walk_to(S.APPROVED)
    with pytest.raises(ValueError, match="time zone"):
        bench.store.schedule_reel(reel.reel_id, reel.revision, reel.created_at.replace(tzinfo=None))


# --- Platform rows ----------------------------------------------------------------------

P = PostStatus
SPEC_POST_CHANGES = {
    (P.PENDING, P.IN_FLIGHT),
    (P.PENDING, P.POSTED),
    (P.PENDING, P.SKIPPED),
    (P.IN_FLIGHT, P.POSTED),
    (P.IN_FLIGHT, P.FAILED),
    (P.IN_FLIGHT, P.UNKNOWN_OUTCOME),
    (P.FAILED, P.PENDING),
    (P.FAILED, P.POSTED),
    (P.UNKNOWN_OUTCOME, P.PENDING),
    (P.UNKNOWN_OUTCOME, P.POSTED),
    (P.SKIPPED, P.POSTED),
}


LEGAL_ROUTE_TO = {
    P.PENDING: (),
    P.IN_FLIGHT: (P.IN_FLIGHT,),
    P.POSTED: (P.POSTED,),
    P.SKIPPED: (P.SKIPPED,),
    P.FAILED: (P.IN_FLIGHT, P.FAILED),
    P.UNKNOWN_OUTCOME: (P.IN_FLIGHT, P.UNKNOWN_OUTCOME),
}


def test_the_post_status_table_is_exactly_the_spec_table():
    assert set(ALLOWED_POST_CHANGES) == SPEC_POST_CHANGES


@pytest.mark.parametrize(
    ("old", "new"),
    [pair for pair in product(P, P) if pair[0] != pair[1] and pair not in SPEC_POST_CHANGES],
    ids=edge_id,
)
def test_every_other_post_status_change_fails_at_the_database(bench, old, new):
    reel = bench.walk_to(S.PUBLISHING)
    update = "UPDATE platform_posts SET status = ? WHERE reel_id = ? AND platform = ?"
    for status in LEGAL_ROUTE_TO[old]:
        bench.store._db.execute(update, (status, reel.reel_id, TWO_PLATFORMS[0]))
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(update, (new, reel.reel_id, TWO_PLATFORMS[0]))
