"""A reel can never be posted twice, whatever dies and whenever (spec Section 3.5, task B4).

The kills here are real. A child process runs the whole pipeline and calls `os._exit` at a chosen
point, including just as SQLite starts each statement in turn, so there is no rollback and no
cleanup. Then the pipeline runs again from what is on disk, and the provider's own durable record
of sends is the evidence.
"""

import json
import os
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest
from state_support import (
    APPROVE_CALLBACK,
    KILLED,
    OWNER,
    REGENERATE_CALLBACK,
    TWO_PLATFORMS,
    Bench,
    Clock,
    Provider,
    live_config,
    make_video,
    run_pipeline,
    tap,
)

from core.locks import EngineLock, LockHeld
from core.state import (
    ActionRefused,
    PostOutcome,
    PostStatus,
    ReelState,
    RefusalReason,
    StateError,
    StateStore,
    TapAction,
    VerifiedOwnerTap,
)

ENGINE_ROOT = Path(__file__).resolve().parents[1]
SUPPORT = Path(__file__).with_name("state_support.py")
SWEEP_WORKERS = 6  # each kill is a new process, so a one-at-a-time sweep takes minutes

S = ReelState
P = PostStatus


def child_env() -> dict[str, str]:
    return os.environ | {"PYTHONPATH": str(ENGINE_ROOT), "PYTHONDONTWRITEBYTECODE": "1"}


def spawn(folder: Path, *arguments: str) -> subprocess.Popen:
    return subprocess.Popen(
        [sys.executable, str(SUPPORT), str(folder), *arguments],
        env=child_env(),
        cwd=ENGINE_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_child(folder: Path, *arguments: str) -> subprocess.CompletedProcess:
    process = spawn(folder, *arguments)
    out, err = process.communicate(timeout=120)
    return subprocess.CompletedProcess(process.args, process.returncode, out, err)


def fresh_folder(tmp_path: Path, name: str) -> Path:
    folder = tmp_path / name
    make_video(folder)
    return folder


def resolve_everything(store, config, folder):
    """The owner answers what the bot asks, and the pipeline runs until nothing is left to do."""
    for _ in range(len(TWO_PLATFORMS) + 2):
        reel = run_pipeline(store, config, folder)
        if reel.state == S.POSTED:
            return reel
        unresolved = [
            post
            for post in store.posts_for(reel.reel_id)
            if post.status in (P.UNKNOWN_OUTCOME, P.FAILED)
        ]
        assert reel.state == S.NEEDS_ATTENTION, (reel.state, unresolved)
        sent = Provider(folder).sends()
        for post in unresolved:
            # The owner looks at the platform: tap Posted if it went out, Retry if it did not.
            action = TapAction.POSTED if post.platform in sent else TapAction.RETRY
            result = store.apply_tap(tap(reel, action, platform=post.platform), config)
            assert result.applied, result
    raise AssertionError("the reel never finished")


def assert_exactly_one_clean_reel(folder: Path, store) -> None:
    db = store._db
    assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert db.execute("SELECT COUNT(*) FROM reels").fetchone()[0] == 1
    reel_id = db.execute("SELECT reel_id FROM reels").fetchone()[0]
    reel = store.get_reel(reel_id)
    assert reel.state == S.POSTED
    assert reel.revision == 2, "one regenerate tap must make exactly one new revision"
    assert reel.regenerations == 1
    actions = sorted(row.action for row in store.approvals_for(reel_id))
    assert actions.count("regenerate") == 1
    assert actions.count("approve") == 1
    callbacks = {row.callback_query_id for row in store.approvals_for(reel_id)}
    assert {REGENERATE_CALLBACK, APPROVE_CALLBACK} <= callbacks
    posts = store.posts_for(reel_id)
    assert sorted(post.platform for post in posts) == sorted(TWO_PLATFORMS)
    assert all(post.status == P.POSTED for post in posts)
    sends = Provider(folder).sends()
    assert sorted(sends) == sorted(set(sends)), f"a platform got the reel twice: {sends}"


def finish_after_kill(folder: Path) -> None:
    config = live_config(folder)
    with StateStore(folder / "engine.db") as store:
        resolve_everything(store, config, folder)
        sends_at_the_end = Provider(folder).sends()
        run_pipeline(store, config, folder)  # one more re-run finds everything already done
        assert Provider(folder).sends() == sends_at_the_end
        assert_exactly_one_clean_reel(folder, store)


# --- Hard kills -------------------------------------------------------------------------


def test_a_run_with_no_kill_posts_once_per_platform(tmp_path):
    folder = fresh_folder(tmp_path, "clean")
    assert run_child(folder, "count").returncode == 0
    finish_after_kill(folder)
    assert sorted(Provider(folder).sends()) == sorted(TWO_PLATFORMS)


def test_a_kill_at_every_single_statement_never_double_posts(tmp_path):
    counted = fresh_folder(tmp_path, "count")
    result = run_child(counted, "count")
    assert result.returncode == 0, result.stderr
    statements = int(result.stdout)
    assert statements > 100, "the sweep must really walk the pipeline"

    def kill_at(number: int) -> None:
        folder = fresh_folder(tmp_path, f"kill-{number}")
        killed = run_child(folder, f"statement:{number}")
        assert killed.returncode == KILLED, f"statement {number}: {killed.stderr}"
        try:
            finish_after_kill(folder)
        except AssertionError as error:
            raise AssertionError(f"after a kill at statement {number}: {error}") from error
        shutil.rmtree(folder)  # hundreds of finished runs would only take up disk

    with ThreadPoolExecutor(max_workers=SWEEP_WORKERS) as pool:
        for finished in pool.map(kill_at, range(1, statements + 1)):
            assert finished is None


def test_a_kill_with_in_flight_committed_and_nothing_sent_stays_for_the_owner(tmp_path):
    folder = fresh_folder(tmp_path, "before")
    assert run_child(folder, "before_send").returncode == KILLED
    assert Provider(folder).sends() == []

    config = live_config(folder)
    with StateStore(folder / "engine.db") as store:
        reel = run_pipeline(store, config, folder)

        assert reel.state == S.NEEDS_ATTENTION
        statuses = {post.platform: post.status for post in store.posts_for(reel.reel_id)}
        assert statuses[TWO_PLATFORMS[0]] == P.UNKNOWN_OUTCOME
        assert Provider(folder).sends() == [], "an unknown outcome is never retried by itself"

        for _ in range(3):
            run_pipeline(store, config, folder)
        assert Provider(folder).sends() == []

        resolve_everything(store, config, folder)
    assert Provider(folder).sends().count(TWO_PLATFORMS[0]) == 1


def test_a_kill_right_after_the_provider_took_it_is_not_sent_again(tmp_path):
    folder = fresh_folder(tmp_path, "after")
    assert run_child(folder, "after_send").returncode == KILLED
    assert Provider(folder).sends() == [TWO_PLATFORMS[0]]

    config = live_config(folder)
    with StateStore(folder / "engine.db") as store:
        reel = run_pipeline(store, config, folder)
        assert reel.state == S.NEEDS_ATTENTION
        for _ in range(3):
            run_pipeline(store, config, folder)
        assert Provider(folder).sends() == [TWO_PLATFORMS[0]]
    finish_after_kill(folder)
    assert sorted(Provider(folder).sends()) == sorted(TWO_PLATFORMS)


# --- Startup recovery -------------------------------------------------------------------


@pytest.fixture
def bench(tmp_path):
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as store:
        yield Bench(store, live_config(tmp_path), make_video(tmp_path), clock)


def test_in_flight_becomes_unknown_outcome_at_startup(bench, tmp_path):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, TWO_PLATFORMS[0])

    with EngineLock(tmp_path / "tick.lock") as lock:
        recovered = bench.store.recover_interrupted(lock)

    assert [(row.reel_id, row.platform) for row in recovered] == [(reel.reel_id, claim.platform)]
    post = bench.store.posts_for(reel.reel_id)[0]
    assert post.status == P.UNKNOWN_OUTCOME
    assert bench.refresh(reel).state == S.NEEDS_ATTENTION
    assert bench.store.unresolved_posts()[0].platform == claim.platform


def test_recovery_refuses_to_run_without_the_lock(bench, tmp_path):
    # Another process could really be mid-send, so this may only run with the lock in hand.
    reel = bench.publishing()
    bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    released = EngineLock(tmp_path / "tick.lock")

    with pytest.raises(StateError, match="lock"):
        bench.store.recover_interrupted(released)
    with pytest.raises(StateError, match="lock"):
        bench.store.recover_interrupted(None)

    assert bench.store.posts_for(reel.reel_id)[0].status == P.IN_FLIGHT


def test_recovery_with_nothing_in_flight_changes_nothing(bench, tmp_path):
    reel = bench.publishing()
    before = bench.store.events_for(reel.reel_id)
    with EngineLock(tmp_path / "tick.lock") as lock:
        assert bench.store.recover_interrupted(lock) == []
    assert bench.store.events_for(reel.reel_id) == before
    assert bench.refresh(reel).state == S.PUBLISHING


def test_an_unknown_outcome_blocks_a_new_send_until_the_owner_answers(bench):
    reel = bench.needs_attention(PostOutcome.UNKNOWN)

    with pytest.raises(ActionRefused) as refused:
        bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    assert refused.value.reason == RefusalReason.NOT_PUBLISHING
    with pytest.raises(ActionRefused):
        bench.claim(reel.reel_id, TWO_PLATFORMS[1])


@pytest.mark.parametrize("late", [PostOutcome.FAILED, PostOutcome.UNKNOWN])
def test_a_late_failure_after_recovery_does_not_overrule_it(bench, tmp_path, late):
    reel = bench.publishing()
    claim = bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    with EngineLock(tmp_path / "tick.lock") as lock:
        bench.store.recover_interrupted(lock)

    assert bench.store.record_post_result(claim, late) is False

    assert bench.store.posts_for(reel.reel_id)[0].status == P.UNKNOWN_OUTCOME


def test_a_durable_state_survives_closing_without_a_clean_shutdown(tmp_path):
    clock = Clock()
    store = StateStore(tmp_path / "engine.db", clock=clock)
    bench = Bench(store, live_config(tmp_path), make_video(tmp_path), clock)
    reel = bench.publishing()
    bench.claim(reel.reel_id, TWO_PLATFORMS[0])
    store.close()

    with StateStore(tmp_path / "engine.db") as reopened:
        assert reopened.posts_for(reel.reel_id)[0].status == P.IN_FLIGHT


# --- Exceptions roll back -----------------------------------------------------------------


def test_an_error_inside_a_transaction_leaves_nothing_behind(bench, monkeypatch):
    # The approval row and the state change commit together, or not at all.
    reel = bench.awaiting()
    before = bench.store.events_for(reel.reel_id)
    real_event = bench.store._write_event

    def failing_event(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(bench.store, "_write_event", failing_event)
    with pytest.raises(OSError, match="disk went away"):
        bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config)
    monkeypatch.setattr(bench.store, "_write_event", real_event)

    assert bench.refresh(reel).state == S.AWAITING_APPROVAL
    assert bench.store.approvals_for(reel.reel_id) == []
    assert bench.store.events_for(reel.reel_id) == before
    assert bench.store.apply_tap(tap(reel, TapAction.APPROVE), bench.config).applied


# --- Idempotent reel creation and runs ----------------------------------------------------


def _create(store, slot="slot-a", **overrides):
    values = {
        "slot_key": slot,
        "topic_id": "topic-1",
        "tier": "global",
        "template": "DailyTip",
        "language": "ar",
        "target_duration": 30,
        "is_test": False,
    }
    return store.create_reel(**(values | overrides))


def test_creating_for_the_same_slot_twice_gives_the_same_reel(bench):
    first, created = _create(bench.store)
    again, created_again = _create(bench.store, topic_id="another-topic")
    assert (created, created_again) == (True, False)
    assert again == first
    assert bench.store.count_reels() == 1


def test_reel_ids_fit_the_telegram_callback_limit(bench):
    reel, _ = _create(bench.store)
    longest = f"v1:{reel.reel_id}:99:regenerate"
    assert len(longest.encode()) <= 64


def test_a_run_key_that_finished_is_found_done(bench):
    first = bench.store.begin_run("2026-11-05", "script")
    assert (first.already_done, first.attempts) == (False, 1)
    bench.store.finish_run("2026-11-05", "script", reel_id="r1")

    again = bench.store.begin_run("2026-11-05", "script")

    assert again.already_done is True
    assert again.reel_id == "r1"
    assert again.attempts == 1


def test_a_run_that_died_can_start_again_and_counts_its_tries(bench):
    bench.store.begin_run("2026-11-05", "script")
    assert bench.store.begin_run("2026-11-05", "script").attempts == 2
    assert bench.store.begin_run("2026-11-05", "voice").attempts == 1


def test_a_usage_limit_gives_the_try_back(bench):
    bench.store.begin_run("2026-11-05", "script")
    bench.store.give_back_attempt("2026-11-05", "script")
    assert bench.store.begin_run("2026-11-05", "script").attempts == 1


def test_finishing_a_run_never_started_is_an_error(bench):
    with pytest.raises(StateError):
        bench.store.finish_run("2026-11-05", "script")


# --- Locks --------------------------------------------------------------------------------


def test_a_second_holder_in_the_same_process_is_refused(tmp_path):
    with EngineLock(tmp_path / "tick.lock"):
        with pytest.raises(LockHeld):
            EngineLock(tmp_path / "tick.lock").acquire()


def test_the_lock_is_free_again_after_release(tmp_path):
    lock = EngineLock(tmp_path / "tick.lock")
    lock.acquire()
    assert lock.held
    lock.release()
    assert not lock.held
    with EngineLock(tmp_path / "tick.lock"):
        pass


def test_acquiring_twice_on_one_object_is_refused(tmp_path):
    lock = EngineLock(tmp_path / "tick.lock")
    lock.acquire()
    try:
        with pytest.raises(LockHeld):
            lock.acquire()
    finally:
        lock.release()


def test_release_when_not_held_does_nothing(tmp_path):
    EngineLock(tmp_path / "tick.lock").release()


def test_a_second_holder_in_another_process_is_refused_and_a_dead_holder_frees_it(tmp_path):
    folder = tmp_path / "shared"
    folder.mkdir()
    holder = spawn(folder, "hold_lock")
    deadline = time.monotonic() + 60
    while not (folder / "lock-held").exists():
        assert holder.poll() is None, holder.communicate()
        assert time.monotonic() < deadline
        time.sleep(0.01)

    with pytest.raises(LockHeld):
        EngineLock(folder / "tick.lock").acquire()

    (folder / "go").touch()  # the holder now dies with no chance to release anything
    holder.communicate(timeout=60)
    assert holder.returncode == KILLED

    with EngineLock(folder / "tick.lock"):  # no stale lock left behind
        pass


def test_the_lock_creates_its_folder(tmp_path):
    with EngineLock(tmp_path / "a" / "b" / "tick.lock"):
        assert (tmp_path / "a" / "b" / "tick.lock").exists()


# --- Real concurrent access ---------------------------------------------------------------


def start_race(folder: Path, runners: int, *arguments: str) -> list[dict]:
    processes = [spawn(folder, "race", *arguments) for _ in range(runners)]
    deadline = time.monotonic() + 90
    while len(list(folder.glob("ready-*"))) < runners:
        assert time.monotonic() < deadline, "the runners never got ready"
        for process in processes:
            assert process.poll() is None, process.communicate()
        time.sleep(0.01)
    (folder / "go").touch()
    reports = []
    for process in processes:
        out, err = process.communicate(timeout=120)
        assert process.returncode == 0, err
        reports.append(json.loads(out))
    return reports


RUNNERS = 6


def test_processes_opening_a_new_database_together_all_succeed(tmp_path):
    folder = fresh_folder(tmp_path, "open")
    reports = start_race(folder, RUNNERS, "open")
    assert all(report["won"] for report in reports)
    with StateStore(folder / "engine.db") as store:
        assert store._db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"


def test_racing_processes_create_one_reel_for_a_slot(tmp_path):
    folder = fresh_folder(tmp_path, "create")
    reports = start_race(folder, RUNNERS, "create")
    assert sum(report["won"] for report in reports) == 1
    assert len({report["reel_id"] for report in reports}) == 1
    with StateStore(folder / "engine.db") as store:
        assert store.count_reels() == 1


def _prepared_reel(folder: Path, state: S) -> str:
    clock = Clock()
    with StateStore(folder / "engine.db", clock=clock) as store:
        bench = Bench(store, live_config(folder), folder / "reel.mp4", clock)
        return bench.walk_to(state).reel_id


def test_racing_processes_approve_once(tmp_path):
    folder = fresh_folder(tmp_path, "approve")
    reel_id = _prepared_reel(folder, S.AWAITING_APPROVAL)

    reports = start_race(folder, RUNNERS, "approve", reel_id)

    assert sum(report["won"] for report in reports) == 1
    with StateStore(folder / "engine.db") as store:
        assert [row.action for row in store.approvals_for(reel_id)] == ["approve"]
        assert store.get_reel(reel_id).state == S.APPROVED


def test_racing_processes_get_one_claim_on_a_platform(tmp_path):
    folder = fresh_folder(tmp_path, "post")
    reel_id = _prepared_reel(folder, S.PUBLISHING)

    reports = start_race(folder, RUNNERS, "begin_post", reel_id)

    assert sum(report["won"] for report in reports) == 1
    assert {r["error"] for r in reports if not r["won"]} == {"ActionRefused"}
    with StateStore(folder / "engine.db") as store:
        post = next(p for p in store.posts_for(reel_id) if p.platform == TWO_PLATFORMS[0])
        assert (post.status, post.attempts) == (P.IN_FLIGHT, 1)


def test_threads_with_their_own_connections_race_safely(tmp_path, monkeypatch):
    # The lock is out of the way, so that only the compare-and-swap decides this race.
    monkeypatch.setattr("core.locks.msvcrt.locking", lambda *_arguments: None)
    folder = fresh_folder(tmp_path, "threads")
    reel_id = _prepared_reel(folder, S.PUBLISHING)
    config = live_config(folder)
    wins: list[str] = []
    errors: list[Exception] = []
    barrier = threading.Barrier(RUNNERS)

    def attempt() -> None:
        with StateStore(folder / "engine.db") as store:
            store._clock = lambda: store.get_reel(reel_id).scheduled_for
            barrier.wait()
            try:
                with store.engine_lock() as lock:
                    wins.append(store.begin_post(reel_id, TWO_PLATFORMS[0], config, lock).platform)
            except ActionRefused as error:
                errors.append(error)

    threads = [threading.Thread(target=attempt) for _ in range(RUNNERS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=60)

    assert wins == [TWO_PLATFORMS[0]]
    assert len(errors) == RUNNERS - 1


def test_a_reader_is_not_blocked_by_an_open_write(tmp_path):
    # This is what WAL is for: the bot can answer /status while a tick is writing.
    clock = Clock()
    with StateStore(tmp_path / "engine.db", clock=clock) as writer:
        bench = Bench(writer, live_config(tmp_path), make_video(tmp_path), clock)
        reel = bench.new_reel()
        with StateStore(tmp_path / "engine.db") as reader:
            with writer._transaction() as db:
                db.execute("UPDATE reels SET state = 'failed' WHERE reel_id = ?", (reel.reel_id,))
                assert reader.get_reel(reel.reel_id).state == S.DRAFT
            assert reader.get_reel(reel.reel_id).state == S.FAILED


def test_a_writer_waits_for_another_writer_rather_than_failing(tmp_path):
    with StateStore(tmp_path / "engine.db") as first:
        other = sqlite3.connect(tmp_path / "engine.db", timeout=0, isolation_level=None)
        try:
            with first._transaction():
                with pytest.raises(sqlite3.OperationalError):
                    other.execute("BEGIN IMMEDIATE")
        finally:
            other.close()

        results: list[str] = []
        with first._transaction():

            def later_writer() -> None:
                with StateStore(tmp_path / "engine.db") as second:
                    second.set_paused(True)
                    results.append("wrote")

            thread = threading.Thread(target=later_writer)
            thread.start()
            time.sleep(0.2)
            assert results == []
        thread.join(timeout=60)
        assert results == ["wrote"]
        assert first.is_paused() is True


def test_a_replayed_tap_across_a_restart_is_a_duplicate(tmp_path):
    clock = Clock()
    path = tmp_path / "engine.db"
    config = live_config(tmp_path)
    with StateStore(path, clock=clock) as store:
        bench = Bench(store, config, make_video(tmp_path), clock)
        reel = bench.awaiting()
        tapped = VerifiedOwnerTap(reel.reel_id, reel.revision, TapAction.APPROVE, OWNER, "cb-kept")
        assert store.apply_tap(tapped, config).applied

    with StateStore(path, clock=clock) as store:
        assert not store.apply_tap(tapped, config).applied
        assert store.get_reel(reel.reel_id).state == S.APPROVED
        assert len(store.approvals_for(reel.reel_id)) == 1
