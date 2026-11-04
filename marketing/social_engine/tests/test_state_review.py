"""What Round 2's review of the state store proved, and the fixes (spec Sections 3.3, 3.5)."""

import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import timedelta, timezone
from pathlib import Path

import pytest
from state_support import (
    TWO_PLATFORMS,
    Bench,
    Clock,
    live_config,
    make_video,
    prove_render,
    shipped_config,
    tap,
)

from core.locks import EngineLock, LockHeld
from core.state import (
    ENGINE_LOCK_NAME,
    SEND_GRACE,
    ActionRefused,
    PostOutcome,
    PostStatus,
    ReelState,
    RefusalReason,
    StateDatabaseLost,
    StateError,
    StateStore,
    TapAction,
    TapOutcome,
    VerifiedOwnerTap,
)

S = ReelState
P = PostStatus
INSTAGRAM, TIKTOK = TWO_PLATFORMS


@pytest.fixture
def bench(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        yield Bench(store, live_config(tmp_path), make_video(tmp_path), clock)


def status_of(bench, reel, platform=INSTAGRAM) -> PostStatus:
    return next(p.status for p in bench.store.posts_for(reel.reel_id) if p.platform == platform)


def assert_refused(result, reason):
    assert result.outcome == TapOutcome.REFUSED
    assert result.reason == reason


def refusal_of(call) -> RefusalReason:
    with pytest.raises(ActionRefused) as refused:
        call()
    return refused.value.reason


# --- 1. Double posting: the lock proves who owns a send ------------------------------------------


def test_recovery_refuses_a_lock_that_is_not_the_engine_lock(bench, tmp_path):
    reel = bench.publishing((INSTAGRAM,))
    with bench.store.engine_lock() as live_send:
        claim = bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, live_send)
        with EngineLock(tmp_path / "somewhere_else.lock") as other:
            with pytest.raises(StateError, match="lock"):
                bench.store.recover_interrupted(other)
        assert status_of(bench, reel) == P.IN_FLIGHT
        assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real") is True
    assert status_of(bench, reel) == P.POSTED


def test_a_send_with_no_lock_is_refused_and_changes_nothing(bench, tmp_path):
    reel = bench.publishing()
    unheld = bench.store.engine_lock()
    for lock in (None, unheld, "tick.lock"):
        with pytest.raises(StateError, match="lock"):
            bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, lock)
    with EngineLock(tmp_path / "another.lock") as another:
        with pytest.raises(StateError, match="lock"):
            bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, another)
    post = bench.store.posts_for(reel.reel_id)[0]
    assert (post.status, post.attempts) == (P.PENDING, 0)


def test_a_look_alike_lock_is_refused(bench):
    class Forged(EngineLock):
        @property
        def held(self) -> bool:
            return True

    reel = bench.publishing()
    with pytest.raises(StateError, match="lock"):
        bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, Forged(bench.store.lock_path))
    with pytest.raises(StateError, match="lock"):
        bench.store.recover_interrupted(Forged(bench.store.lock_path))


def test_the_engine_lock_sits_beside_the_database(tmp_path):
    with StateStore(tmp_path / "state" / "engine.db") as store:
        assert store.lock_path == tmp_path / "state" / ENGINE_LOCK_NAME
        assert store.engine_lock().path == store.lock_path


def test_recovery_cannot_get_the_lock_while_a_send_holds_it(bench):
    reel = bench.publishing((INSTAGRAM,))
    with bench.store.engine_lock() as live_send:
        claim = bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, live_send)
        with pytest.raises(LockHeld):
            bench.store.engine_lock().acquire()
        assert status_of(bench, reel) == P.IN_FLIGHT
        assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real") is True
    assert bench.refresh(reel).state == S.POSTED


def test_recovery_leaves_a_send_made_under_the_same_holding_of_the_lock(bench):
    reel = bench.publishing((INSTAGRAM,))
    with bench.store.engine_lock() as lock:
        claim = bench.store.begin_post(reel.reel_id, INSTAGRAM, bench.config, lock)
        assert bench.store.recover_interrupted(lock) == []
        assert status_of(bench, reel) == P.IN_FLIGHT
        assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real") is True


def test_each_holding_of_the_lock_has_its_own_token(tmp_path):
    lock = EngineLock(tmp_path / "tick.lock")
    assert lock.token is None
    with lock:
        first = lock.token
        assert first
    assert lock.token is None
    with lock:
        assert lock.token != first


def test_a_new_holding_of_the_lock_recovers_what_an_old_one_left(bench):
    reel = bench.publishing((INSTAGRAM,))
    bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        assert [row.platform for row in bench.store.recover_interrupted(lock)] == [INSTAGRAM]
    assert status_of(bench, reel) == P.UNKNOWN_OUTCOME


def test_a_success_arriving_after_recovery_is_kept_and_stops_a_second_send(bench):
    reel = bench.publishing((INSTAGRAM,))
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)

    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real-id") is True

    post = bench.store.posts_for(reel.reel_id)[0]
    assert (post.status, post.remote_id, post.posted_at) == (P.POSTED, "real-id", bench.clock())
    assert bench.refresh(reel).state == S.POSTED
    retry = bench.store.apply_tap(tap(reel, TapAction.RETRY, platform=INSTAGRAM), bench.config)
    assert_refused(retry, RefusalReason.NOT_PUBLISHING)
    late = [e for e in bench.store.events_for(reel.reel_id) if e.kind == "late_success"]
    assert [event.detail for event in late] == ["attempt 1 posted as real-id"]


def test_a_success_arriving_after_a_retry_tap_stops_the_second_send(bench):
    reel = bench.publishing((INSTAGRAM,))
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied
    assert status_of(bench, reel) == P.PENDING

    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real-id") is True

    assert status_of(bench, reel) == P.POSTED
    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.NOT_PUBLISHING


def test_a_success_from_an_old_attempt_wins_over_a_later_one_in_flight(bench):
    reel = bench.publishing((INSTAGRAM,))
    first = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied
    second = bench.claim(reel.reel_id, INSTAGRAM)

    assert bench.store.record_post_result(first, PostOutcome.POSTED, remote_id="old") is True
    assert status_of(bench, reel) == P.POSTED

    # The later attempt cannot take that back, and a failure from it says nothing new.
    assert bench.store.record_post_result(second, PostOutcome.FAILED) is False
    assert status_of(bench, reel) == P.POSTED
    assert bench.store.posts_for(reel.reel_id)[0].remote_id == "old"


def test_two_successes_put_the_duplicate_on_the_record(bench):
    reel = bench.publishing((INSTAGRAM,))
    first = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied
    second = bench.claim(reel.reel_id, INSTAGRAM)
    assert bench.store.record_post_result(second, PostOutcome.POSTED, remote_id="two") is True

    assert bench.store.record_post_result(first, PostOutcome.POSTED, remote_id="one") is False

    assert bench.store.posts_for(reel.reel_id)[0].remote_id == "two"
    duplicates = [e for e in bench.store.events_for(reel.reel_id) if e.kind == "duplicate_post"]
    assert [event.detail for event in duplicates] == ["attempt 1 posted as one"]


def test_the_same_success_reported_twice_is_no_duplicate(bench):
    reel = bench.publishing((INSTAGRAM,))
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="one") is True
    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="one") is False
    assert not [e for e in bench.store.events_for(reel.reel_id) if e.kind == "duplicate_post"]


def test_a_success_on_a_row_later_skipped_is_kept(bench):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied
    assert bench.store.skip_platform(reel.reel_id, INSTAGRAM) is True

    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="real") is True

    assert status_of(bench, reel) == P.POSTED


def test_a_success_with_no_remote_id_after_recovery_stays_a_question(bench):
    reel = bench.publishing((INSTAGRAM,))
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    with bench.store.engine_lock() as lock:
        bench.store.recover_interrupted(lock)
    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id=" ") is False
    assert status_of(bench, reel) == P.UNKNOWN_OUTCOME


def test_a_success_on_a_reel_sent_back_meanwhile_is_kept(bench):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)

    assert bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="live") is True

    assert status_of(bench, reel) == P.POSTED
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


# --- 2. An emptied or missing database never opens as new ----------------------------------------


def posted_store(tmp_path: Path) -> tuple[Path, Bench]:
    clock = Clock()
    db = tmp_path / "state" / "engine.db"
    store = StateStore(db, clock=clock)
    bench = Bench(store, live_config(tmp_path), make_video(tmp_path), clock)
    reel = bench.publishing((INSTAGRAM,))
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    store.record_post_result(claim, PostOutcome.POSTED, remote_id="r1")
    store.close()
    return db, bench


def test_an_emptied_database_is_refused(tmp_path):
    db, _ = posted_store(tmp_path)
    db.write_bytes(b"")
    with pytest.raises(StateDatabaseLost, match="is empty"):
        StateStore(db)
    assert db.read_bytes() == b""


def test_a_missing_database_is_refused_and_not_created(tmp_path):
    db, _ = posted_store(tmp_path)
    db.unlink()
    with pytest.raises(StateDatabaseLost, match="is missing"):
        StateStore(db)
    assert not db.exists()


def test_a_wiped_state_folder_is_refused(tmp_path):
    db, _ = posted_store(tmp_path)
    shutil.rmtree(db.parent)
    with pytest.raises(StateDatabaseLost):
        StateStore(db)


def test_a_new_empty_database_put_in_its_place_is_refused(tmp_path):
    db, _ = posted_store(tmp_path)
    db.unlink()
    sqlite3.connect(db).execute("CREATE TABLE stray (x)").connection.close()
    with pytest.raises(StateDatabaseLost, match="holds no tables"):
        StateStore(db)


def test_an_old_backup_with_fewer_reels_is_refused(tmp_path):
    clock = Clock()
    db = tmp_path / "state" / "engine.db"
    with StateStore(db, clock=clock) as store:
        bench = Bench(store, live_config(tmp_path), make_video(tmp_path), clock)
        bench.new_reel()
    backup = tmp_path / "backup.db"
    shutil.copyfile(db, backup)
    with StateStore(db, clock=clock) as store:
        bench = Bench(store, live_config(tmp_path), make_video(tmp_path), clock)
        bench.store.create_reel(
            slot_key="the-slot-that-was-posted",
            topic_id="t",
            tier="global",
            template="DailyTip",
            language="ar",
            target_duration=30,
            is_test=False,
        )
    shutil.copyfile(backup, db)
    with pytest.raises(StateDatabaseLost, match="holds 1 reel"):
        StateStore(db)


def test_the_refusal_says_what_happened_and_what_to_do(tmp_path):
    db, _ = posted_store(tmp_path)
    db.write_bytes(b"")
    with pytest.raises(StateDatabaseLost) as refused:
        StateStore(db)
    message = str(refused.value)
    assert "1 reel(s) existed" in message
    assert "second reel" in message
    assert "backup" in message
    assert str(tmp_path / "state.engine.db.reels-existed") in message


def test_the_marker_is_outside_the_database_folder(tmp_path):
    db, _ = posted_store(tmp_path)
    assert (tmp_path / "state.engine.db.reels-existed").is_file()
    assert [path.name for path in db.parent.glob("*reels-existed*")] == []


def test_deleting_the_marker_is_the_deliberate_way_to_start_over(tmp_path):
    db, _ = posted_store(tmp_path)
    db.write_bytes(b"")
    (tmp_path / "state.engine.db.reels-existed").unlink()
    with StateStore(db) as store:
        assert store.count_reels() == 0


def test_a_database_with_no_reels_yet_can_start_again_freely(tmp_path):
    db = tmp_path / "state" / "engine.db"
    StateStore(db).close()
    assert not (tmp_path / "state.engine.db.reels-existed").exists()
    db.write_bytes(b"")
    StateStore(db).close()


@pytest.mark.parametrize("content", ["", "not json", '{"reels": 0}', '{"reels": true}', "[]", "{}"])
def test_a_marker_that_cannot_be_read_keeps_the_database_closed(tmp_path, content):
    db, _ = posted_store(tmp_path)
    (tmp_path / "state.engine.db.reels-existed").write_text(content, encoding="utf-8")
    with pytest.raises(StateError, match="marker"):
        StateStore(db)


def test_a_crash_between_the_commit_and_the_marker_is_caught_up_on_the_next_open(tmp_path):
    db, _ = posted_store(tmp_path)
    marker = tmp_path / "state.engine.db.reels-existed"
    marker.unlink()  # as if the process died right after the commit
    StateStore(db).close()
    assert marker.is_file()
    db.write_bytes(b"")
    with pytest.raises(StateDatabaseLost):
        StateStore(db)


def test_the_marker_is_written_before_create_reel_returns(tmp_path):
    clock = Clock()
    db = tmp_path / "state" / "engine.db"
    with StateStore(db, clock=clock) as store:
        Bench(store, live_config(tmp_path), make_video(tmp_path), clock).new_reel()
        assert (tmp_path / "state.engine.db.reels-existed").read_text("utf-8") == '{"reels": 1}'


def test_a_database_with_its_triggers_removed_is_refused(tmp_path):
    db, _ = posted_store(tmp_path)
    raw = sqlite3.connect(db)
    raw.execute("DROP TRIGGER reels_state_change")
    raw.execute("DROP TRIGGER platform_posts_status_change")
    raw.commit()
    raw.close()
    with pytest.raises(StateError, match="triggers"):
        StateStore(db)


def test_a_trigger_quietly_rewritten_is_refused(tmp_path):
    db, _ = posted_store(tmp_path)
    raw = sqlite3.connect(db)
    raw.execute("DROP TRIGGER reels_approved_needs_tap")
    raw.execute(
        "CREATE TRIGGER reels_approved_needs_tap BEFORE UPDATE OF state ON reels "
        "WHEN 0 BEGIN SELECT 1; END"
    )
    raw.commit()
    raw.close()
    with pytest.raises(StateError, match="triggers"):
        StateStore(db)


def test_a_corrupted_page_gives_a_state_error(tmp_path):
    db, _ = posted_store(tmp_path)
    data = bytearray(db.read_bytes())
    page = int.from_bytes(data[16:18], "big")
    for index in range(page, len(data), 7):  # keep the header, damage everything after it
        data[index] = 0xAB
    db.write_bytes(bytes(data))
    with pytest.raises(StateError):
        StateStore(db)


# --- 3. Never before the window, never late, and a way to move on --------------------------------


def test_publishing_before_the_window_is_refused_and_the_reel_stays_scheduled(bench):
    reel = bench.scheduled()
    bench.clock.now = reel.scheduled_for - timedelta(seconds=1)
    start = lambda: bench.store.start_publishing(  # noqa: E731
        reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config
    )
    assert refusal_of(start) == RefusalReason.BEFORE_WINDOW
    assert bench.refresh(reel).state == S.SCHEDULED
    assert bench.store.posts_for(reel.reel_id) == []


def test_publishing_after_the_window_is_refused_and_the_reel_stays_scheduled(bench):
    reel = bench.scheduled()
    bench.clock.now = reel.scheduled_for + SEND_GRACE + timedelta(seconds=1)
    start = lambda: bench.store.start_publishing(  # noqa: E731
        reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config
    )
    assert refusal_of(start) == RefusalReason.WINDOW_PASSED
    assert bench.refresh(reel).state == S.SCHEDULED


def test_a_tick_every_30_minutes_always_lands_inside_the_grace():
    assert SEND_GRACE >= timedelta(minutes=30)


def test_publishing_at_the_very_edges_of_the_window_works(bench):
    early = bench.scheduled()
    bench.clock.now = early.scheduled_for
    assert bench.store.start_publishing(early.reel_id, early.revision, (INSTAGRAM,), bench.config)
    late = bench.scheduled()
    bench.clock.now = late.scheduled_for + SEND_GRACE
    assert bench.store.start_publishing(late.reel_id, late.revision, (INSTAGRAM,), bench.config)


def test_a_claim_30_days_after_a_crash_in_publishing_is_refused(bench):
    reel = bench.publishing()
    bench.clock.advance(days=30)
    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.WINDOW_PASSED
    post = bench.store.posts_for(reel.reel_id)[0]
    assert (post.status, post.attempts) == (P.PENDING, 0)
    assert bench.refresh(reel).state == S.PUBLISHING


def test_a_claim_just_inside_the_deadline_works_and_just_outside_is_refused(bench):
    reel = bench.publishing()
    deadline = reel.scheduled_for + SEND_GRACE
    assert bench.store.posts_for(reel.reel_id)[0].send_by == deadline
    bench.clock.now = deadline
    assert bench.claim(reel.reel_id, INSTAGRAM).attempt == 1
    bench.clock.now = deadline + timedelta(microseconds=1)
    assert refusal_of(lambda: bench.claim(reel.reel_id, TIKTOK)) == RefusalReason.WINDOW_PASSED


def test_a_clock_set_back_before_the_window_cannot_claim(bench):
    reel = bench.publishing()
    bench.clock.now = reel.scheduled_for - timedelta(days=1)
    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.BEFORE_WINDOW


def test_a_stranded_reel_moves_to_the_next_window_and_then_goes_out(bench):
    reel = bench.publishing()
    done = bench.claim(reel.reel_id, INSTAGRAM)
    bench.store.record_post_result(done, PostOutcome.POSTED, remote_id="kept")
    bench.clock.advance(days=30)
    next_window = bench.clock() + timedelta(hours=5)

    assert bench.store.reschedule(reel.reel_id, reel.revision, next_window) is True

    fresh = bench.refresh(reel)
    assert (fresh.state, fresh.scheduled_for) == (S.SCHEDULED, next_window)
    assert status_of(bench, reel, INSTAGRAM) == P.POSTED, "what went out stays out"

    bench.clock.now = next_window
    assert bench.store.start_publishing(reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config)
    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.NOT_PENDING
    assert bench.claim(reel.reel_id, TIKTOK).attempt == 1
    assert bench.store.posts_for(reel.reel_id)[1].send_by == next_window + SEND_GRACE


def test_a_reel_with_a_send_in_flight_cannot_move_window(bench):
    reel = bench.publishing()
    bench.claim(reel.reel_id, INSTAGRAM)
    later = bench.clock() + timedelta(days=1)
    assert bench.store.reschedule(reel.reel_id, reel.revision, later) is False
    assert bench.refresh(reel).state == S.PUBLISHING


def test_a_reel_waiting_for_an_answer_cannot_move_window(bench):
    reel = bench.needs_attention()
    later = bench.clock() + timedelta(days=1)
    assert bench.store.reschedule(reel.reel_id, reel.revision, later) is False
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION


@pytest.mark.parametrize("state", [S.DRAFT, S.AWAITING_APPROVAL, S.APPROVED, S.POSTED, S.REJECTED])
def test_a_reel_elsewhere_has_no_window_to_move(bench, state):
    reel = bench.walk_to(state)
    assert bench.store.reschedule(reel.reel_id, reel.revision, bench.clock()) is False
    assert bench.refresh(reel) == reel


def test_an_old_revision_cannot_move_the_window(bench):
    reel = bench.publishing()
    assert bench.store.reschedule(reel.reel_id, reel.revision + 1, bench.clock()) is False


def test_a_retry_tap_gives_that_row_a_new_window_and_no_other(bench):
    reel = bench.needs_attention()
    bench.clock.advance(days=3)
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied

    assert refusal_of(lambda: bench.claim(reel.reel_id, TIKTOK)) == RefusalReason.WINDOW_PASSED
    assert bench.claim(reel.reel_id, INSTAGRAM).attempt == 2


def test_a_hand_upload_can_still_be_reported_after_the_window(bench):
    reel = bench.publishing((INSTAGRAM,))
    bench.clock.advance(days=3)
    posted = tap(reel, TapAction.POSTED, platform=INSTAGRAM)
    assert bench.store.apply_tap(posted, bench.config).applied
    assert bench.refresh(reel).state == S.POSTED


def test_a_window_given_in_another_time_zone_means_the_same_moment(bench):
    riyadh = timezone(timedelta(hours=3))
    reel = bench.approved()
    window = (bench.clock() + timedelta(hours=2)).astimezone(riyadh)
    assert bench.store.schedule_reel(reel.reel_id, reel.revision, window)
    fresh = bench.refresh(reel)
    assert fresh.scheduled_for == window
    assert fresh.scheduled_for.utcoffset() == timedelta(0)

    bench.clock.now = (window - timedelta(seconds=1)).astimezone(riyadh)
    start = lambda: bench.store.start_publishing(  # noqa: E731
        reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config
    )
    assert refusal_of(start) == RefusalReason.BEFORE_WINDOW
    bench.clock.now = window.astimezone(timezone(timedelta(hours=-5)))
    assert start() is True


def test_expiry_compares_moments_when_the_clock_reports_another_time_zone(bench):
    reel = bench.awaiting()
    bench.clock.now = (bench.clock() + timedelta(hours=71)).astimezone(timezone(timedelta(hours=3)))
    assert bench.store.expire_overdue(72) == []
    bench.clock.advance(hours=1)
    assert bench.store.expire_overdue(72) == [reel.reel_id]


# --- 4. A question for the owner always has an answer --------------------------------------------


def test_retry_does_not_reopen_sending_while_another_question_is_open(bench):
    reel = bench.publishing()
    first = bench.claim(reel.reel_id, INSTAGRAM)
    second = bench.claim(reel.reel_id, TIKTOK)
    bench.store.record_post_result(first, PostOutcome.UNKNOWN)
    bench.store.record_post_result(second, PostOutcome.FAILED)
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION

    retry = tap(reel, TapAction.RETRY, platform=TIKTOK)
    assert bench.store.apply_tap(retry, bench.config).applied

    assert bench.refresh(reel).state == S.NEEDS_ATTENTION, "Instagram is still unanswered"
    assert refusal_of(lambda: bench.claim(reel.reel_id, TIKTOK)) == RefusalReason.NOT_PUBLISHING

    answer = tap(reel, TapAction.POSTED, platform=INSTAGRAM)
    assert bench.store.apply_tap(answer, bench.config).applied
    assert bench.refresh(reel).state == S.PUBLISHING
    assert bench.claim(reel.reel_id, TIKTOK).attempt == 2


@pytest.mark.parametrize("action", [TapAction.POSTED, TapAction.RETRY])
@pytest.mark.parametrize("outcome", [PostOutcome.FAILED, PostOutcome.UNKNOWN])
def test_a_reel_sent_back_can_still_answer_the_question(bench, action, outcome):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.store.record_post_result(claim, outcome)
    assert [row.platform for row in bench.store.unresolved_posts()] == [INSTAGRAM]

    result = bench.store.apply_tap(tap(reel, action, platform=INSTAGRAM), bench.config)

    assert result.applied
    assert bench.store.unresolved_posts() == []
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


@pytest.mark.parametrize("action", [TapAction.POSTED, TapAction.RETRY])
def test_a_rejected_reel_leaves_no_question_the_owner_cannot_answer(bench, action):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.store.record_post_result(claim, PostOutcome.UNKNOWN)
    assert bench.store.apply_tap(tap(reel, TapAction.REJECT), bench.config).applied
    assert bench.refresh(reel).state == S.REJECTED

    result = bench.store.apply_tap(tap(reel, action, platform=INSTAGRAM), bench.config)

    assert result.applied
    assert bench.store.unresolved_posts() == []
    assert bench.refresh(reel).state == S.REJECTED, "rejected is terminal"


def test_retry_on_a_rejected_reel_can_never_send(bench):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.store.record_post_result(claim, PostOutcome.UNKNOWN)
    assert bench.store.apply_tap(tap(reel, TapAction.REJECT), bench.config).applied
    retry = tap(reel, TapAction.RETRY, platform=INSTAGRAM)
    assert bench.store.apply_tap(retry, bench.config).applied

    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.NOT_PUBLISHING


def test_a_reel_live_on_a_platform_cannot_become_rejected(bench):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.store.record_post_result(claim, PostOutcome.POSTED, remote_id="live-on-instagram")

    result = bench.store.apply_tap(tap(reel, TapAction.REJECT), bench.config)

    assert_refused(result, RefusalReason.ALREADY_LIVE)
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_a_stale_button_on_a_question_only_says_so_and_a_new_one_answers(bench):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, INSTAGRAM)
    bench.store.record_post_result(claim, PostOutcome.UNKNOWN)
    old = tap(reel, TapAction.POSTED, platform=INSTAGRAM, revision=reel.revision + 1)
    assert bench.store.apply_tap(old, bench.config).outcome == TapOutcome.STALE
    assert status_of(bench, reel) == P.UNKNOWN_OUTCOME
    assert bench.store.apply_tap(
        tap(reel, TapAction.POSTED, platform=INSTAGRAM), bench.config
    ).applied


def test_posted_on_a_pending_row_still_needs_a_reel_that_is_publishing(bench):
    reel = bench.publishing()
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    result = bench.store.apply_tap(tap(reel, TapAction.POSTED, platform=INSTAGRAM), bench.config)
    assert_refused(result, RefusalReason.NOT_PUBLISHING)


# --- 5. The test flag belongs to the stored row --------------------------------------------------


@pytest.mark.parametrize("is_test", [False, True], ids=["live row", "test row"])
def test_a_file_with_the_wrong_watermark_is_refused_even_with_the_gate_met(bench, is_test):
    reel = bench.voiced(is_test=is_test)
    prove_render(bench.video, reel.reel_id, reel.revision, "h", watermark=not is_test)

    refused = refusal_of(
        lambda: bench.store.record_rendered(
            reel.reel_id, reel.revision, bench.video, "h", bench.config
        )
    )

    assert refused == RefusalReason.WATERMARK_MISMATCH
    assert bench.refresh(reel).state == S.VOICED


def test_a_file_with_the_right_watermark_is_recorded(bench):
    for is_test in (False, True):
        reel = bench.voiced(is_test=is_test)
        prove_render(bench.video, reel.reel_id, reel.revision, "h", watermark=is_test)
        assert bench.store.record_rendered(
            reel.reel_id, reel.revision, bench.video, "h", bench.config
        )


def test_a_file_no_render_vouches_for_is_refused(bench, tmp_path):
    reel = bench.voiced()
    empty = tmp_path / "empty.mp4"
    empty.write_bytes(b"")
    refused = refusal_of(
        lambda: bench.store.record_rendered(reel.reel_id, reel.revision, empty, "x", bench.config)
    )
    assert refused == RefusalReason.RENDER_UNPROVEN


@pytest.mark.parametrize(
    "spoil",
    [
        lambda bench, reel: prove_render(
            bench.video, "another-reel", reel.revision, "h", watermark=False
        ),
        lambda bench, reel: prove_render(
            bench.video, reel.reel_id, reel.revision + 1, "h", watermark=False
        ),
        lambda bench, reel: prove_render(
            bench.video, reel.reel_id, reel.revision, "other", watermark=False
        ),
        lambda bench, reel: (
            prove_render(bench.video, reel.reel_id, reel.revision, "h", watermark=False),
            bench.video.write_bytes(b"swapped after the receipt"),
        ),
        lambda bench, reel: (
            bench.video.with_name(bench.video.name + ".receipt.json").write_text(
                "{not json", encoding="utf-8"
            )
        ),
        lambda bench, reel: (
            bench.video.with_name(bench.video.name + ".receipt.json").write_text(
                '{"reel_id": 1}', encoding="utf-8"
            )
        ),
    ],
    ids=["other reel", "other revision", "other content", "other file", "bad json", "bad fields"],
)
def test_a_receipt_for_anything_else_proves_nothing(bench, spoil):
    reel = bench.voiced()
    spoil(bench, reel)
    refused = refusal_of(
        lambda: bench.store.record_rendered(
            reel.reel_id, reel.revision, bench.video, "h", bench.config
        )
    )
    assert refused == RefusalReason.RENDER_UNPROVEN
    assert bench.refresh(reel).state == S.VOICED


def test_a_receipt_whose_watermark_is_not_a_plain_flag_proves_nothing(bench):
    reel = bench.voiced()
    prove_render(bench.video, reel.reel_id, reel.revision, "h", watermark=False)
    receipt = bench.video.with_name(bench.video.name + ".receipt.json")
    receipt.write_text(receipt.read_text("utf-8").replace("false", "0"), encoding="utf-8")
    assert (
        refusal_of(
            lambda: bench.store.record_rendered(
                reel.reel_id, reel.revision, bench.video, "h", bench.config
            )
        )
        == RefusalReason.RENDER_UNPROVEN
    )


def test_the_row_keeps_its_flag_whatever_a_later_create_asks_for(bench):
    fields = {
        "slot_key": "day",
        "topic_id": "t",
        "tier": "global",
        "template": "DailyTip",
        "language": "ar",
        "target_duration": 30,
    }
    made, created = bench.store.create_reel(**fields, is_test=True)
    again, created_again = bench.store.create_reel(**fields, is_test=False)
    assert (created, created_again) == (True, False)
    assert again.reel_id == made.reel_id
    assert again.is_test is True


# --- 6. Stuck reels have a way out ---------------------------------------------------------------


def f0_scheduled(tmp_path, store, clock):
    allowed = live_config(tmp_path, allow_public_on_f0=True)
    bench = Bench(store, allowed, make_video(tmp_path), clock)
    reel = bench.awaiting("F0")
    assert store.apply_tap(tap(reel, TapAction.APPROVE), allowed).applied
    assert store.schedule_reel(reel.reel_id, 1, clock() + timedelta(days=1))
    return bench.refresh(reel)


@pytest.mark.parametrize("action", [TapAction.REJECT, TapAction.REVOICE])
def test_a_scheduled_reel_whose_voice_stopped_being_allowed_goes_back_to_the_owner(
    tmp_path, action
):
    clock = Clock()
    refused_config = live_config(tmp_path, allow_public_on_f0=False)
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        reel = f0_scheduled(tmp_path, store, clock)

        reason = refusal_of(
            lambda: store.start_publishing(reel.reel_id, 1, (INSTAGRAM,), refused_config)
        )

        assert reason == RefusalReason.F0_AUDIO
        fresh = store.get_reel(reel.reel_id)
        assert (fresh.state, fresh.scheduled_for) == (S.AWAITING_APPROVAL, None)
        assert store.apply_tap(tap(fresh, action), refused_config).applied


def test_a_publishing_reel_whose_voice_stopped_being_allowed_goes_back_too(tmp_path):
    clock = Clock()
    allowed = live_config(tmp_path, allow_public_on_f0=True)
    refused_config = live_config(tmp_path, allow_public_on_f0=False)
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        reel = f0_scheduled(tmp_path, store, clock)
        clock.now = reel.scheduled_for
        assert store.start_publishing(reel.reel_id, 1, (INSTAGRAM,), allowed)
        bench = Bench(store, refused_config, make_video(tmp_path), clock)

        assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.F0_AUDIO

        assert store.get_reel(reel.reel_id).state == S.AWAITING_APPROVAL
        assert status_of(bench, reel) == P.PENDING


def test_turning_the_setting_back_on_still_takes_a_new_approve_tap(tmp_path):
    clock = Clock()
    allowed = live_config(tmp_path, allow_public_on_f0=True)
    refused_config = live_config(tmp_path, allow_public_on_f0=False)
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        reel = f0_scheduled(tmp_path, store, clock)
        refusal_of(lambda: store.start_publishing(reel.reel_id, 1, (INSTAGRAM,), refused_config))
        assert store.start_publishing(reel.reel_id, 1, (INSTAGRAM,), allowed) is False
        fresh = store.get_reel(reel.reel_id)
        assert store.apply_tap(tap(fresh, TapAction.APPROVE), allowed).applied


@pytest.mark.parametrize("damage", ["changed", "deleted"])
def test_a_changed_file_has_a_route_past_the_regeneration_limit(tmp_path, damage):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        config = live_config(tmp_path)
        bench = Bench(store, config, make_video(tmp_path), clock)
        reel = bench.awaiting()
        for _ in range(config.approval.max_regenerations):
            assert store.apply_tap(tap(reel, TapAction.REGENERATE), config).applied
            assert store.finish_regeneration(reel.reel_id, reel.revision)
            reel = bench.refresh(reel)
            assert store.record_voiced(reel.reel_id, reel.revision, "S0")
            bench.prove(reel.reel_id, reel.revision)
            assert store.record_rendered(
                reel.reel_id, reel.revision, bench.video, "content-hash", config
            )
            assert store.offer_for_approval(reel.reel_id, reel.revision, config)
            reel = bench.refresh(reel)
        original = bench.video.read_bytes()
        if damage == "changed":
            bench.video.write_bytes(b"changed")
        else:
            bench.video.unlink()
        assert_refused(
            store.apply_tap(tap(reel, TapAction.APPROVE), config), RefusalReason.HASH_CHANGED
        )
        assert_refused(
            store.apply_tap(tap(reel, TapAction.REGENERATE), config), RefusalReason.LIMIT_REACHED
        )

        assert store.apply_tap(tap(reel, TapAction.RERENDER), config).applied

        waiting = bench.refresh(reel)
        assert (waiting.state, waiting.regenerate_kind) == (S.REGENERATING, "render")
        assert waiting.regenerations == reel.regenerations, "no Claude was used, so nothing counts"
        assert store.finish_regeneration(reel.reel_id, reel.revision)
        again = bench.refresh(reel)
        assert (again.state, again.revision) == (S.DRAFT, reel.revision + 1)
        assert again.regenerate_kind == "render"
        assert store.record_voiced(reel.reel_id, again.revision, "S0")
        bench.video.write_bytes(original)
        bench.prove(reel.reel_id, again.revision)
        assert store.record_rendered(
            reel.reel_id, again.revision, bench.video, "content-hash", config
        )
        assert store.offer_for_approval(reel.reel_id, again.revision, config)
        assert store.apply_tap(tap(bench.refresh(reel), TapAction.APPROVE), config).applied


def test_render_again_is_refused_on_a_file_that_has_not_changed(bench):
    reel = bench.awaiting()
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.RERENDER), bench.config),
        RefusalReason.FILE_UNCHANGED,
    )
    assert bench.refresh(reel) == reel


@pytest.mark.parametrize("state", [S.DRAFT, S.APPROVED, S.REJECTED, S.POSTED, S.TEST_DELIVERED])
def test_render_again_works_only_while_awaiting(bench, state):
    reel = bench.walk_to(state)
    assert_refused(
        bench.store.apply_tap(tap(reel, TapAction.RERENDER), bench.config),
        RefusalReason.NOT_AWAITING,
    )


# --- 7. A spent tap stays spent ------------------------------------------------------------------


def test_a_replayed_tap_that_was_refused_stays_spent_after_requeue(bench):
    reel = bench.awaiting()
    bench.clock.advance(hours=72)
    assert reel.reel_id in bench.store.expire_overdue(72)
    old = tap(reel, TapAction.APPROVE, callback="cb-from-before-expiry")
    assert bench.store.apply_tap(old, bench.config).outcome == TapOutcome.REFUSED
    assert bench.store.requeue(reel.reel_id, bench.config)

    assert bench.store.apply_tap(old, bench.config).outcome == TapOutcome.DUPLICATE

    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert bench.store.approvals_for(reel.reel_id) == []
    assert bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config).applied


def test_a_refused_tap_replayed_after_the_file_returned_stays_spent(bench):
    reel = bench.awaiting()
    original = bench.video.read_bytes()
    bench.video.write_bytes(b"changed")
    old = tap(reel, TapAction.APPROVE)
    assert_refused(bench.store.apply_tap(old, bench.config), RefusalReason.HASH_CHANGED)
    bench.video.write_bytes(original)
    assert bench.store.apply_tap(old, bench.config).outcome == TapOutcome.DUPLICATE
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_a_stale_tap_replayed_stays_spent(bench):
    reel = bench.awaiting()
    stale = tap(reel, TapAction.APPROVE, revision=reel.revision + 1)
    assert bench.store.apply_tap(stale, bench.config).outcome == TapOutcome.STALE
    assert bench.store.apply_tap(stale, bench.config).outcome == TapOutcome.DUPLICATE


def test_a_tap_on_an_unknown_reel_replayed_stays_spent(bench):
    unknown = VerifiedOwnerTap("no-such-reel", 1, TapAction.REJECT, 1, "cb-unknown")
    assert bench.store.apply_tap(unknown, bench.config).outcome == TapOutcome.REFUSED
    assert bench.store.apply_tap(unknown, bench.config).outcome == TapOutcome.DUPLICATE


def test_spent_taps_survive_a_restart(tmp_path):
    clock = Clock()
    path = tmp_path / "engine.db"
    with StateStore(path, clock=clock) as store:
        bench = Bench(store, live_config(tmp_path), make_video(tmp_path), clock)
        reel = bench.rendered()
        old = tap(reel, TapAction.APPROVE, callback="cb-kept")
        assert store.apply_tap(old, bench.config).outcome == TapOutcome.REFUSED
        assert store.offer_for_approval(reel.reel_id, reel.revision, bench.config)
    with StateStore(path, clock=clock) as store:
        assert store.apply_tap(old, bench.config).outcome == TapOutcome.DUPLICATE
        assert store.get_reel(reel.reel_id).state == S.AWAITING_APPROVAL


@pytest.mark.parametrize(
    "statement",
    [
        "DELETE FROM spent_taps",
        "UPDATE spent_taps SET outcome = 'applied'",
        "INSERT OR REPLACE INTO spent_taps VALUES ('cb-spent', 'r', 'x', 'x')",
    ],
)
def test_the_database_keeps_a_spent_tap_spent(bench, statement):
    reel = bench.awaiting()
    spent = tap(reel, TapAction.APPROVE, callback="cb-spent", revision=reel.revision + 1)
    bench.store.apply_tap(spent, bench.config)
    with pytest.raises(sqlite3.IntegrityError):
        bench.store._db.execute(statement)


def test_the_database_itself_asks_for_a_new_tap_after_a_send_back(bench):
    reel = bench.scheduled()
    good = bench.video.read_bytes()
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.video.write_bytes(good)
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL

    with pytest.raises(sqlite3.IntegrityError, match="owner tap"):
        bench.store._db.execute(
            "UPDATE reels SET state = 'approved' WHERE reel_id = ?", (reel.reel_id,)
        )

    assert bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config).applied
    assert bench.refresh(reel).state == S.APPROVED


def test_the_database_asks_for_a_new_tap_after_expiry_and_requeue_too(bench):
    reel = bench.approved()
    db = bench.store._db
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    bench.clock.advance(hours=72)
    assert bench.store.expire_overdue(72) == [reel.reel_id]
    assert bench.store.requeue(reel.reel_id, bench.config)
    with pytest.raises(sqlite3.IntegrityError, match="owner tap"):
        db.execute("UPDATE reels SET state = 'approved' WHERE reel_id = ?", (reel.reel_id,))


def test_the_approval_floor_cannot_be_lowered(bench):
    reel = bench.scheduled()
    bench.video.write_bytes(b"changed")
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision)
    with pytest.raises(sqlite3.IntegrityError, match="spent approval"):
        bench.store._db.execute(
            "UPDATE reels SET approval_floor = 0 WHERE reel_id = ?", (reel.reel_id,)
        )


def test_append_only_tables_survive_insert_or_replace(bench):
    reel = bench.approved()
    db = bench.store._db
    row = db.execute("SELECT approval_id FROM approvals").fetchone()[0]
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT OR REPLACE INTO approvals (approval_id, reel_id, revision, mp4_sha256, "
            "telegram_user_id, action, platform, callback_query_id, at) "
            "VALUES (?, ?, 1, 'x', 1, 'reject', NULL, 'forged', 'now')",
            (row, reel.reel_id),
        )
    event = db.execute("SELECT event_id FROM events LIMIT 1").fetchone()[0]
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "INSERT OR REPLACE INTO events (event_id, kind, actor, at) VALUES (?, 'x', 'x', 'x')",
            (event,),
        )


# --- 9. The deleted-file send-back ---------------------------------------------------------------


def test_a_deleted_file_sends_a_scheduled_reel_back(bench):
    reel = bench.scheduled()
    bench.video.unlink()
    reason = refusal_of(
        lambda: bench.store.start_publishing(
            reel.reel_id, reel.revision, TWO_PLATFORMS, bench.config
        )
    )
    assert reason == RefusalReason.HASH_CHANGED
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL


def test_a_deleted_file_sends_a_publishing_reel_back_before_any_send(bench):
    reel = bench.publishing()
    bench.video.unlink()
    assert refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM)) == RefusalReason.HASH_CHANGED
    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert status_of(bench, reel) == P.PENDING


@pytest.mark.parametrize("state", [S.APPROVED, S.SCHEDULED, S.PUBLISHING])
def test_the_direct_check_sends_a_reel_back_when_its_file_is_gone(bench, state):
    reel = bench.walk_to(state)
    bench.video.unlink()
    assert bench.store.send_back_if_file_changed(reel.reel_id, reel.revision) is True
    fresh = bench.refresh(reel)
    assert (fresh.state, fresh.scheduled_for) == (S.AWAITING_APPROVAL, None)


# --- Other things the review tried -------------------------------------------------------------


def test_the_lock_file_cannot_be_deleted_or_moved_while_held(tmp_path):
    with EngineLock(tmp_path / "t.lock"):
        with pytest.raises(OSError):
            (tmp_path / "t.lock").unlink()
        with pytest.raises(OSError):
            (tmp_path / "t.lock").rename(tmp_path / "moved.lock")


def test_a_second_handle_in_one_process_is_refused_until_the_first_lets_go(tmp_path):
    first, second = EngineLock(tmp_path / "t.lock"), EngineLock(tmp_path / "t.lock")
    first.acquire()
    with pytest.raises(LockHeld):
        second.acquire()
    first.release()
    second.acquire()
    second.release()


def test_a_child_process_does_not_keep_a_dead_holders_lock(tmp_path):
    code = (
        "import sys,subprocess,time;sys.path.insert(0,r'{root}');"
        "from core.locks import EngineLock;"
        "l=EngineLock(r'{lock}');l.acquire();"
        "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],close_fds=False);"
        "open(r'{flag}','w').write(str(p.pid));time.sleep(30)"
    ).format(
        root=str(Path(__file__).resolve().parents[1]),
        lock=str(tmp_path / "t.lock"),
        flag=str(tmp_path / "flag"),
    )
    parent = subprocess.Popen([sys.executable, "-c", code])
    deadline = time.monotonic() + 20
    while not (tmp_path / "flag").exists() or not (tmp_path / "flag").read_text():
        assert time.monotonic() < deadline
        time.sleep(0.05)
    parent.kill()
    parent.wait()
    try:
        with EngineLock(tmp_path / "t.lock"):
            pass
    finally:
        subprocess.run(
            ["taskkill", "/F", "/PID", (tmp_path / "flag").read_text()],
            capture_output=True,
            check=False,
        )


def test_the_shipped_config_refuses_a_real_send(bench):
    reel = bench.publishing()
    reason = refusal_of(lambda: bench.claim(reel.reel_id, INSTAGRAM, shipped_config()))
    assert reason == RefusalReason.BRAND_GATE
