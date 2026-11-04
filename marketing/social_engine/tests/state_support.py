"""Shared helpers for the state store tests, and the child process the restart tests kill.

Run as a script, this is that child: `python state_support.py <folder> <how to die>`. It is
kept apart from the test files so a child needs no pytest, which makes the many kills quick.
"""

from __future__ import annotations

import itertools
import json
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import yaml

from core.config import DEFAULT_CONFIG_PATH, EngineConfig, load_config
from core.locks import EngineLock
from core.state import (
    PostOutcome,
    PostStatus,
    Reel,
    ReelState,
    StateStore,
    TapAction,
    VerifiedOwnerTap,
)

OWNER = 777001
HOURS_TO_EXPIRE = 72
START = datetime(2026, 11, 5, 9, 0, tzinfo=UTC)
TWO_PLATFORMS = ("instagram", "tiktok")
KILLED = 91  # the exit code that proves the child died at the planned point

_callback_numbers = itertools.count(1)


@dataclass
class Clock:
    now: datetime = START

    def __call__(self) -> datetime:
        return self.now

    def advance(self, **delta) -> None:
        self.now += timedelta(**delta)


def live_config(folder: Path, **voice_overrides) -> EngineConfig:
    """A config that meets the launch gate. Only tests ever build one of these."""
    logo = folder / "approved_logo.svg"
    logo.parent.mkdir(parents=True, exist_ok=True)
    logo.write_text("<svg/>", encoding="utf-8")
    with DEFAULT_CONFIG_PATH.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    chosen_on = date(2026, 11, 3)
    data["engine"]["mode"] = "live"
    data["brand"]["logo_path"] = str(logo)
    data["brand"]["handles"] = {
        "instagram": "@qawam_money",
        "facebook": "qawam.money",
        "tiktok": "@qawammoney",
        "youtube": "@qawammoney",
    }
    data["brand"]["hashtags"] = ["#QawamMoney"]
    data["brand"]["clearance"] = dict.fromkeys(data["brand"]["clearance"], chosen_on)
    data["voice"].update(voice_overrides)
    return EngineConfig.model_validate(data)


def shipped_config() -> EngineConfig:
    return load_config()


def make_video(folder: Path, content: bytes = b"reel bytes", name: str = "reel.mp4") -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    video = folder / name
    video.write_bytes(content)
    return video


def tap(
    reel: Reel,
    action: TapAction,
    *,
    platform: str | None = None,
    callback: str | None = None,
    revision: int | None = None,
) -> VerifiedOwnerTap:
    return VerifiedOwnerTap(
        reel_id=reel.reel_id,
        revision=reel.revision if revision is None else revision,
        action=action,
        telegram_user_id=OWNER,
        callback_query_id=callback or f"cb-{next(_callback_numbers)}",
        platform=platform,
    )


@dataclass
class Bench:
    """A store with everything needed to walk a reel along the state machine."""

    store: StateStore
    config: EngineConfig
    video: Path
    clock: Clock = field(default_factory=Clock)
    _slots: itertools.count = field(default_factory=lambda: itertools.count(1))

    def new_reel(self, *, is_test: bool = False, language: str = "ar") -> Reel:
        reel, created = self.store.create_reel(
            slot_key=f"slot-{next(self._slots)}",
            topic_id="topic-1",
            tier="global",
            template="DailyTip",
            language=language,
            target_duration=30,
            is_test=is_test,
        )
        assert created
        return reel

    def refresh(self, reel: Reel) -> Reel:
        fresh = self.store.get_reel(reel.reel_id)
        assert fresh is not None
        return fresh

    def voiced(self, voice_tier: str = "S0", *, is_test: bool = False) -> Reel:
        reel = self.new_reel(is_test=is_test)
        assert self.store.record_voiced(reel.reel_id, reel.revision, voice_tier)
        return self.refresh(reel)

    def rendered(self, voice_tier: str = "S0", *, is_test: bool = False) -> Reel:
        reel = self.voiced(voice_tier, is_test=is_test)
        assert self.store.record_rendered(
            reel.reel_id, reel.revision, self.video, "content-hash", self.config
        )
        return self.refresh(reel)

    def awaiting(self, voice_tier: str = "S0") -> Reel:
        reel = self.rendered(voice_tier)
        assert self.store.offer_for_approval(reel.reel_id, reel.revision, self.config)
        return self.refresh(reel)

    def approved(self) -> Reel:
        reel = self.awaiting()
        result = self.store.apply_tap(tap(reel, TapAction.APPROVE), self.config)
        assert result.applied, result
        return self.refresh(reel)

    def scheduled(self) -> Reel:
        reel = self.approved()
        assert self.store.schedule_reel(reel.reel_id, reel.revision, self.clock() + timedelta(1))
        return self.refresh(reel)

    def publishing(self, platforms: tuple[str, ...] = TWO_PLATFORMS) -> Reel:
        reel = self.scheduled()
        assert self.store.start_publishing(reel.reel_id, reel.revision, platforms, self.config)
        return self.refresh(reel)

    def needs_attention(self, outcome: PostOutcome = PostOutcome.FAILED) -> Reel:
        reel = self.publishing()
        claim = self.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], self.config)
        self.store.record_post_result(claim, outcome)
        return self.refresh(reel)

    def walk_to(self, target: ReelState) -> Reel:
        """A fresh reel in the target state, reached only through the public methods."""
        steps = {
            ReelState.DRAFT: self.new_reel,
            ReelState.BLOCKED_GUARDRAILS: self._blocked,
            ReelState.VOICED: self.voiced,
            ReelState.RENDERED: self.rendered,
            ReelState.AWAITING_APPROVAL: self.awaiting,
            ReelState.TEST_DELIVERED: self._test_delivered,
            ReelState.APPROVED: self.approved,
            ReelState.REGENERATING: self._regenerating,
            ReelState.REJECTED: self._rejected,
            ReelState.EXPIRED: self._expired,
            ReelState.SCHEDULED: self.scheduled,
            ReelState.PUBLISHING: self.publishing,
            ReelState.POSTED: self._posted,
            ReelState.NEEDS_ATTENTION: self.needs_attention,
            ReelState.FAILED: self._failed,
        }
        reel = steps[target]()
        assert reel.state == target
        return reel

    def _blocked(self) -> Reel:
        reel = self.new_reel()
        assert self.store.transition(reel.reel_id, ReelState.DRAFT, ReelState.BLOCKED_GUARDRAILS)
        return self.refresh(reel)

    def _failed(self) -> Reel:
        reel = self.new_reel()
        assert self.store.transition(reel.reel_id, ReelState.DRAFT, ReelState.FAILED)
        return self.refresh(reel)

    def _test_delivered(self) -> Reel:
        reel = self.rendered(is_test=True)
        assert self.store.mark_test_delivered(reel.reel_id, reel.revision)
        return self.refresh(reel)

    def _regenerating(self) -> Reel:
        reel = self.awaiting()
        result = self.store.apply_tap(tap(reel, TapAction.REGENERATE), self.config)
        assert result.applied, result
        return self.refresh(reel)

    def _rejected(self) -> Reel:
        reel = self.awaiting()
        result = self.store.apply_tap(tap(reel, TapAction.REJECT), self.config)
        assert result.applied, result
        return self.refresh(reel)

    def _expired(self) -> Reel:
        reel = self.awaiting()
        self.clock.advance(hours=HOURS_TO_EXPIRE)
        assert reel.reel_id in self.store.expire_overdue(HOURS_TO_EXPIRE)
        return self.refresh(reel)

    def _posted(self) -> Reel:
        reel = self.publishing(TWO_PLATFORMS[:1])
        claim = self.store.begin_post(reel.reel_id, TWO_PLATFORMS[0], self.config)
        self.store.record_post_result(claim, PostOutcome.POSTED, remote_id="remote-1")
        return self.refresh(reel)


# --- The pipeline the restart tests kill ------------------------------------------------


SLOT = "2026-11-05"
REGENERATE_CALLBACK = "cb-regenerate"
APPROVE_CALLBACK = "cb-approve"


class Provider:
    """Stands in for a social platform: a durable record of every send it ever received."""

    def __init__(self, folder: Path) -> None:
        self.log = folder / "provider_sends.txt"

    def send(self, platform: str) -> None:
        with self.log.open("a", encoding="utf-8") as handle:
            handle.write(platform + "\n")
            handle.flush()
            os.fsync(handle.fileno())

    def sends(self) -> list[str]:
        return self.log.read_text(encoding="utf-8").splitlines() if self.log.exists() else []


def owner_tap(reel_id: str, revision: int, action: TapAction, callback: str) -> VerifiedOwnerTap:
    return VerifiedOwnerTap(
        reel_id=reel_id,
        revision=revision,
        action=action,
        telegram_user_id=OWNER,
        callback_query_id=callback,
    )


def run_pipeline(
    store: StateStore,
    config: EngineConfig,
    folder: Path,
    *,
    before_send=lambda platform: None,
    after_send=lambda platform: None,
) -> Reel:
    """What the tick and the bot do together, written so it is safe to run again from any point.
    The owner regenerates revision 1 and approves revision 2. The same two taps are delivered
    again at each start, because Telegram re-sends an update it was not sure we received."""
    video = folder / "reel.mp4"
    provider = Provider(folder)
    with EngineLock(folder / "tick.lock") as lock:
        store.recover_interrupted(lock)
        reel, _ = store.create_reel(
            slot_key=SLOT,
            topic_id="topic-1",
            tier="global",
            template="DailyTip",
            language="ar",
            target_duration=30,
            is_test=False,
        )
        rid = reel.reel_id
        regenerate = owner_tap(rid, 1, TapAction.REGENERATE, REGENERATE_CALLBACK)
        approve = owner_tap(rid, 2, TapAction.APPROVE, APPROVE_CALLBACK)
        store.apply_tap(regenerate, config)
        store.apply_tap(approve, config)
        for _ in range(50):
            reel = store.get_reel(rid)
            match reel.state:
                case ReelState.DRAFT:
                    store.record_voiced(rid, reel.revision, "S0")
                case ReelState.VOICED:
                    store.record_rendered(rid, reel.revision, video, "content-hash", config)
                case ReelState.RENDERED:
                    store.offer_for_approval(rid, reel.revision, config)
                case ReelState.AWAITING_APPROVAL:
                    store.apply_tap(regenerate if reel.revision == 1 else approve, config)
                case ReelState.REGENERATING:
                    store.finish_regeneration(rid, reel.revision)
                case ReelState.APPROVED:
                    store.schedule_reel(rid, reel.revision, datetime(2026, 11, 6, tzinfo=UTC))
                case ReelState.SCHEDULED:
                    store.start_publishing(rid, reel.revision, TWO_PLATFORMS, config)
                case ReelState.PUBLISHING:
                    waiting = [
                        post.platform
                        for post in store.posts_for(rid)
                        if post.status == PostStatus.PENDING
                    ]
                    if not waiting:
                        return reel
                    claim = store.begin_post(rid, waiting[0], config)
                    before_send(waiting[0])
                    provider.send(waiting[0])
                    after_send(waiting[0])
                    store.record_post_result(claim, PostOutcome.POSTED, remote_id="remote-id")
                case _:
                    return reel
        raise AssertionError(f"the pipeline did not settle, stuck in {reel.state}")


def _die(_platform: str | None = None) -> None:
    os._exit(KILLED)


def _die_on_statement(store: StateStore, number: int) -> None:
    """A hard kill just as SQLite starts statement `number`: no rollback, no cleanup, nothing."""
    seen = itertools.count(1)

    def trace(_statement: str) -> None:
        if next(seen) == number:
            _die()

    store._db.set_trace_callback(trace)


def _count_statements(store: StateStore) -> itertools.count:
    seen = itertools.count(1)
    store._db.set_trace_callback(lambda _statement: next(seen))
    return seen


def _child_pipeline(folder: Path, how: str) -> int:
    config = live_config(folder)
    with StateStore(folder / "engine.db") as store:
        if how == "count":
            seen = _count_statements(store)
            run_pipeline(store, config, folder)
            store._db.set_trace_callback(None)
            print(next(seen) - 1)
            return 0
        if how.startswith("statement:"):
            _die_on_statement(store, int(how.split(":", 1)[1]))
            run_pipeline(store, config, folder)
        elif how == "before_send":
            run_pipeline(store, config, folder, before_send=_die)
        elif how == "after_send":
            run_pipeline(store, config, folder, after_send=_die)
        else:
            raise SystemExit(f"unknown way to die: {how}")
    return 0


def _wait_for_start(folder: Path) -> None:
    (folder / f"ready-{os.getpid()}").touch()
    deadline = time.monotonic() + 60
    while not (folder / "go").exists():
        if time.monotonic() > deadline:
            raise SystemExit("never told to start")
        time.sleep(0.001)


def _child_race(folder: Path, kind: str, argument: str) -> int:
    """Waits for the starter's signal, then does one thing at the same moment as its rivals, and
    reports what happened to it as JSON."""
    config = live_config(folder)
    _wait_for_start(folder)
    with StateStore(folder / "engine.db") as store:
        if kind == "create":
            reel, created = store.create_reel(
                slot_key=SLOT,
                topic_id="topic-1",
                tier="global",
                template="DailyTip",
                language="ar",
                target_duration=30,
                is_test=False,
            )
            print(json.dumps({"won": created, "reel_id": reel.reel_id}))
        elif kind == "approve":
            reel = store.get_reel(argument)
            result = store.apply_tap(
                owner_tap(reel.reel_id, reel.revision, TapAction.APPROVE, f"cb-{os.getpid()}"),
                config,
            )
            print(json.dumps({"won": result.applied}))
        elif kind == "begin_post":
            try:
                store.begin_post(argument, TWO_PLATFORMS[0], config)
            except Exception as error:
                print(json.dumps({"won": False, "error": type(error).__name__}))
            else:
                print(json.dumps({"won": True}))
        elif kind == "open":
            print(json.dumps({"won": True}))
        else:
            raise SystemExit(f"unknown race: {kind}")
    return 0


def _child_hold_lock(folder: Path) -> int:
    lock = EngineLock(folder / "tick.lock")
    lock.acquire()
    (folder / "lock-held").touch()
    while not (folder / "go").exists():
        time.sleep(0.005)
    _die()
    return 0


def main(arguments: list[str]) -> int:
    folder = Path(arguments[0])
    if arguments[1] == "race":
        return _child_race(folder, arguments[2], arguments[3] if len(arguments) > 3 else "")
    if arguments[1] == "hold_lock":
        return _child_hold_lock(folder)
    return _child_pipeline(folder, arguments[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
