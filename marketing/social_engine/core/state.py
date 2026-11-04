"""The reel state store: one SQLite file, outside OneDrive (spec Sections 3.3 to 3.5).

One reel must never be posted twice, even after a crash. So every change is a compare-and-swap
in a transaction, and the rules are written twice: here, and as constraints and triggers in the
database, which still hold if code above them is wrong.

Who may do what:
- `apply_tap` is the only way to `approved`, and it takes only a VerifiedOwnerTap, which only the
  Telegram callback handler builds, after its owner check (invariant 1, enforced by a source scan
  in tests/test_approval_path.py).
- `begin_post` commits `in_flight` before a provider is called, and it is the only way to get the
  claim an adapter needs. It repeats every pre-check itself, so no caller can skip one.
- `recover_interrupted` turns a leftover `in_flight` into `unknown_outcome`. Nothing sends such a
  row again without the owner's tap.

Decisions the spec's table leaves open, taken on the safer side:
- A file that changes after approval sends the reel back, as invariant 2 says, from `approved`,
  `scheduled` or `publishing`. The owner must tap again, even if the old file later returns.
- Retry works on `unknown_outcome` as well as `failed` (Sections 3.5 and 9.3), on the owner's tap.
- `/requeue` returns an expired reel to `awaiting_approval` and restarts its expiry clock.
- Re-voice is a new revision through `regenerating`. It uses no Claude, so it does not count
  against `max_regenerations`, and it is offered only on F0 audio that may not go public.
- `test_delivered` is terminal, so a test reel has no Regenerate, whatever its message shows.
"""

from __future__ import annotations

import hashlib
import os
import sqlite3
import time
import uuid
from collections.abc import Callable, Iterable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from typing import TYPE_CHECKING

from core.brand_gate import (
    approval_allowed,
    approve_button_allowed,
    publish_allowed,
    render_decision,
)
from core.cadence import GeneratedReel
from core.locks import EngineLock

if TYPE_CHECKING:
    from core.config import EngineConfig

SCHEMA_VERSION = 1

_BUSY_TIMEOUT_SECONDS = 30
_WAL_SWITCH_TRIES = 150
_WAL_SWITCH_PAUSE_SECONDS = 0.1
_HASH_CHUNK_BYTES = 1024 * 1024
_NOTE_MAX_CHARS = 1000
_PAUSED_KEY = "paused"


class StateError(RuntimeError):
    """The state store cannot be used. The message says why."""


class IllegalTransition(StateError):
    """The state machine has no such move, or this method is not the way to make it."""


class OwnerTapRequired(IllegalTransition):
    """Only the owner can make this move, through `apply_tap`."""


class RefusalReason(StrEnum):
    UNKNOWN_REEL = "unknown_reel"
    NOT_AWAITING = "not_awaiting"
    NOT_PUBLISHING = "not_publishing"
    NOT_PENDING = "not_pending"
    TEST_REEL = "test_reel"
    NOT_TEST_REEL = "not_test_reel"
    BRAND_GATE = "brand_gate"
    F0_AUDIO = "f0_audio"
    NOT_F0 = "not_f0"
    HASH_CHANGED = "hash_changed"
    LIMIT_REACHED = "limit_reached"
    NO_APPROVAL = "no_approval"
    PAUSED = "paused"
    STALE_REVISION = "stale_revision"


class ActionRefused(StateError):
    """A rule said no. Nothing was posted, and any state change is described by the reason."""

    def __init__(self, reason: RefusalReason, reel_id: str = "") -> None:
        super().__init__(f"{reason.value}: {reel_id}" if reel_id else reason.value)
        self.reason = reason


class ReelState(StrEnum):
    DRAFT = "draft"
    BLOCKED_GUARDRAILS = "blocked_guardrails"
    VOICED = "voiced"
    RENDERED = "rendered"
    AWAITING_APPROVAL = "awaiting_approval"
    TEST_DELIVERED = "test_delivered"
    APPROVED = "approved"
    REGENERATING = "regenerating"
    REJECTED = "rejected"
    EXPIRED = "expired"
    SCHEDULED = "scheduled"
    PUBLISHING = "publishing"
    POSTED = "posted"
    NEEDS_ATTENTION = "needs_attention"
    FAILED = "failed"


class PostStatus(StrEnum):
    PENDING = "pending"
    IN_FLIGHT = "in_flight"
    POSTED = "posted"
    FAILED = "failed"
    UNKNOWN_OUTCOME = "unknown_outcome"
    SKIPPED = "skipped"


class PostOutcome(StrEnum):
    POSTED = "posted"
    FAILED = "failed"  # a definite rejection
    UNKNOWN = "unknown"  # a crash, a timeout or an unclear answer


class TapAction(StrEnum):
    APPROVE = "approve"
    REGENERATE = "regenerate"
    REVOICE = "revoice"
    REJECT = "reject"
    POSTED = "posted"  # also the "Already posted" button
    RETRY = "retry"


class TapOutcome(StrEnum):
    APPLIED = "applied"
    DUPLICATE = "duplicate"
    STALE = "stale"
    REFUSED = "refused"


class Actor(StrEnum):
    ENGINE = "engine"
    OWNER = "owner"


PLATFORMS = ("instagram", "facebook", "tiktok", "youtube")
_VOICE_TIERS = ("F0", "S0")
_PLATFORM_ACTIONS = (TapAction.POSTED, TapAction.RETRY)


@dataclass(frozen=True)
class VerifiedOwnerTap:
    """Proof that the owner tapped a button. Only `approval/telegram_bot.py` builds one, after it
    has checked the sender and the private chat (spec Section 9.4)."""

    reel_id: str
    revision: int
    action: TapAction
    telegram_user_id: int
    callback_query_id: str
    platform: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.reel_id, str) or not self.reel_id:
            raise ValueError(f"bad reel id: {self.reel_id!r}")
        if type(self.revision) is not int or self.revision < 1:
            raise ValueError(f"bad revision: {self.revision!r}")
        if type(self.telegram_user_id) is not int or self.telegram_user_id < 1:
            raise ValueError("bad telegram user id")
        if not isinstance(self.callback_query_id, str) or not self.callback_query_id:
            raise ValueError("bad callback query id")
        if not isinstance(self.action, TapAction):
            raise TypeError(f"bad tap action: {self.action!r}")
        if self.action in _PLATFORM_ACTIONS:
            if self.platform not in PLATFORMS:
                raise ValueError(f"{self.action} needs a known platform, got {self.platform!r}")
        elif self.platform is not None:
            raise ValueError(f"{self.action} takes no platform")


@dataclass(frozen=True)
class TapResult:
    outcome: TapOutcome
    reason: RefusalReason | None = None

    @property
    def applied(self) -> bool:
        return self.outcome == TapOutcome.APPLIED


@dataclass(frozen=True)
class Reel:
    reel_id: str
    slot_key: str
    state: ReelState
    revision: int
    tier: str
    template: str
    topic_id: str
    target_duration: float
    language: str
    is_test: bool
    created_at: datetime
    state_changed_at: datetime
    content_hash: str | None
    mp4_path: Path | None
    mp4_sha256: str | None
    voice_tier: str | None
    regenerations: int
    regenerate_kind: str | None
    scheduled_for: datetime | None


@dataclass(frozen=True)
class PostRow:
    reel_id: str
    platform: str
    status: PostStatus
    idempotency_key: str
    remote_id: str | None
    attempts: int
    posted_at: datetime | None


@dataclass(frozen=True)
class PostClaim:
    """What an adapter needs for one send. Only `begin_post` gives one out."""

    reel_id: str
    platform: str
    revision: int
    mp4_path: Path
    mp4_sha256: str
    idempotency_key: str
    attempt: int


@dataclass(frozen=True)
class ApprovalRow:
    reel_id: str
    revision: int
    mp4_sha256: str
    telegram_user_id: int
    action: str
    platform: str | None
    callback_query_id: str
    at: datetime


@dataclass(frozen=True)
class EventRow:
    reel_id: str | None
    revision: int | None
    kind: str
    from_state: str | None
    to_state: str | None
    platform: str | None
    actor: str
    detail: str
    at: datetime


@dataclass(frozen=True)
class MetricRow:
    reel_id: str
    platform: str
    views: int
    saves: int
    shares: int
    at: datetime


@dataclass(frozen=True)
class RunClaim:
    already_done: bool
    attempts: int
    reel_id: str | None


def post_idempotency_key(reel_id: str, platform: str) -> str:
    """`sha256(reel_id + platform)`, from spec Section 3.5. A retry sends the same key, so a
    provider that supports one can refuse the second copy itself."""
    return hashlib.sha256(f"{reel_id}{platform}".encode()).hexdigest()


def sha256_of_file(path: Path) -> str | None:
    """None if the file cannot be read, which every caller treats as a changed file."""
    digest = hashlib.sha256()
    try:
        with Path(path).open("rb") as handle:
            while chunk := handle.read(_HASH_CHUNK_BYTES):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


_S = ReelState

# The spec's diagram and table in Section 3.3, plus the send-back in invariant 2.
_BEFORE_APPROVAL_WORK = (_S.DRAFT, _S.BLOCKED_GUARDRAILS, _S.VOICED, _S.RENDERED, _S.REGENERATING)
_APPROVED_FILE_STATES = (_S.APPROVED, _S.SCHEDULED, _S.PUBLISHING)

OWNER_ONLY_TRANSITIONS = frozenset(
    {
        (_S.AWAITING_APPROVAL, _S.APPROVED),
        (_S.AWAITING_APPROVAL, _S.REGENERATING),
        (_S.AWAITING_APPROVAL, _S.REJECTED),
        (_S.NEEDS_ATTENTION, _S.PUBLISHING),
        (_S.NEEDS_ATTENTION, _S.POSTED),
    }
)
ENGINE_TRANSITIONS = frozenset(
    {
        (_S.DRAFT, _S.BLOCKED_GUARDRAILS),
        (_S.BLOCKED_GUARDRAILS, _S.DRAFT),
        (_S.DRAFT, _S.VOICED),
        (_S.VOICED, _S.RENDERED),
        (_S.RENDERED, _S.AWAITING_APPROVAL),
        (_S.RENDERED, _S.TEST_DELIVERED),
        (_S.AWAITING_APPROVAL, _S.EXPIRED),
        (_S.EXPIRED, _S.AWAITING_APPROVAL),
        (_S.REGENERATING, _S.DRAFT),
        (_S.APPROVED, _S.SCHEDULED),
        (_S.SCHEDULED, _S.PUBLISHING),
        (_S.PUBLISHING, _S.POSTED),
        (_S.PUBLISHING, _S.NEEDS_ATTENTION),
        *((state, _S.FAILED) for state in _BEFORE_APPROVAL_WORK),
        *((state, _S.AWAITING_APPROVAL) for state in _APPROVED_FILE_STATES),
    }
)
ALLOWED_TRANSITIONS = OWNER_ONLY_TRANSITIONS | ENGINE_TRANSITIONS
# The moves that need nothing but the decision. Every other move carries data or a check, and has
# a method of its own.
PLAIN_TRANSITIONS = frozenset(
    {(_S.DRAFT, _S.BLOCKED_GUARDRAILS), *((state, _S.FAILED) for state in _BEFORE_APPROVAL_WORK)}
)

_P = PostStatus
_OWNER_CAN_RESOLVE = (_P.FAILED, _P.UNKNOWN_OUTCOME)
_DONE = (_P.POSTED, _P.SKIPPED)
ALLOWED_POST_CHANGES = frozenset(
    {
        (_P.PENDING, _P.IN_FLIGHT),
        (_P.PENDING, _P.POSTED),  # telegram_only: the owner uploaded by hand and tapped Posted
        (_P.PENDING, _P.SKIPPED),
        (_P.IN_FLIGHT, _P.POSTED),
        (_P.IN_FLIGHT, _P.FAILED),
        (_P.IN_FLIGHT, _P.UNKNOWN_OUTCOME),
        (_P.FAILED, _P.PENDING),  # owner taps Retry
        (_P.FAILED, _P.POSTED),  # owner taps Already posted
        (_P.UNKNOWN_OUTCOME, _P.PENDING),
        (_P.UNKNOWN_OUTCOME, _P.POSTED),
    }
)


def _sql_list(values) -> str:
    return ", ".join(f"'{value}'" for value in values)


def _sql_pairs(pairs) -> str:
    return _sql_list(sorted(f"{old}>{new}" for old, new in pairs))


def _refuse_rewrites(table: str) -> str:
    return f"""
    CREATE TRIGGER {table}_no_delete BEFORE DELETE ON {table}
    BEGIN SELECT RAISE(ABORT, '{table} rows are never deleted'); END;
    """


_STATES_SQL = _sql_list(ReelState)
_STATUSES_SQL = _sql_list(PostStatus)
_PLATFORMS_SQL = _sql_list(PLATFORMS)

_SCHEMA = f"""
CREATE TABLE reels (
    reel_id TEXT PRIMARY KEY,
    slot_key TEXT NOT NULL UNIQUE,
    state TEXT NOT NULL CHECK (state IN ({_STATES_SQL})),
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
    tier TEXT NOT NULL CHECK (tier IN ('global', 'regional', 'saudi')),
    template TEXT NOT NULL,
    topic_id TEXT NOT NULL,
    target_duration REAL NOT NULL CHECK (target_duration > 0),
    language TEXT NOT NULL CHECK (language IN ('ar', 'en')),
    is_test INTEGER NOT NULL CHECK (is_test IN (0, 1)),
    created_at TEXT NOT NULL,
    state_changed_at TEXT NOT NULL,
    content_hash TEXT,
    mp4_path TEXT,
    mp4_sha256 TEXT,
    voice_tier TEXT CHECK (voice_tier IN ('F0', 'S0')),
    regenerations INTEGER NOT NULL DEFAULT 0,
    regenerate_kind TEXT CHECK (regenerate_kind IN ('script', 'voice')),
    scheduled_for TEXT
) STRICT;

CREATE TABLE approvals (
    approval_id INTEGER PRIMARY KEY,
    reel_id TEXT NOT NULL REFERENCES reels (reel_id),
    revision INTEGER NOT NULL,
    mp4_sha256 TEXT NOT NULL,
    telegram_user_id INTEGER NOT NULL,
    action TEXT NOT NULL CHECK (action IN ({_sql_list(TapAction)})),
    platform TEXT,
    callback_query_id TEXT NOT NULL UNIQUE,
    at TEXT NOT NULL
) STRICT;

CREATE TABLE platform_posts (
    reel_id TEXT NOT NULL REFERENCES reels (reel_id),
    platform TEXT NOT NULL CHECK (platform IN ({_PLATFORMS_SQL})),
    status TEXT NOT NULL CHECK (status IN ({_STATUSES_SQL})),
    idempotency_key TEXT NOT NULL UNIQUE,
    remote_id TEXT,
    attempts INTEGER NOT NULL DEFAULT 0,
    posted_at TEXT,
    UNIQUE (reel_id, platform)
) STRICT;

CREATE TABLE runs (
    run_key TEXT NOT NULL,
    step TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('started', 'done')),
    attempts INTEGER NOT NULL DEFAULT 0,
    reel_id TEXT,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    UNIQUE (run_key, step)
) STRICT;

CREATE TABLE events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    reel_id TEXT,
    revision INTEGER,
    kind TEXT NOT NULL,
    from_state TEXT,
    to_state TEXT,
    platform TEXT,
    actor TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    at TEXT NOT NULL
) STRICT;

CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;

CREATE TABLE metrics (
    metric_id INTEGER PRIMARY KEY,
    reel_id TEXT NOT NULL REFERENCES reels (reel_id),
    platform TEXT NOT NULL CHECK (platform IN ({_PLATFORMS_SQL})),
    views INTEGER NOT NULL CHECK (views >= 0),
    saves INTEGER NOT NULL CHECK (saves >= 0),
    shares INTEGER NOT NULL CHECK (shares >= 0),
    at TEXT NOT NULL
) STRICT;

CREATE INDEX reels_by_state ON reels (state);
CREATE INDEX approvals_by_reel ON approvals (reel_id, revision);
CREATE INDEX events_by_reel ON events (reel_id);

-- A BEFORE INSERT check runs ahead of conflict handling, so REPLACE cannot wipe a row either.
CREATE TRIGGER reels_insert BEFORE INSERT ON reels
WHEN NEW.state <> 'draft' OR NEW.revision <> 1
    OR EXISTS (SELECT 1 FROM reels WHERE reel_id = NEW.reel_id OR slot_key = NEW.slot_key)
BEGIN SELECT RAISE(ABORT, 'a reel starts as draft, once per slot'); END;

CREATE TRIGGER reels_state_change BEFORE UPDATE OF state ON reels
WHEN NEW.state <> OLD.state
    AND OLD.state || '>' || NEW.state NOT IN ({_sql_pairs(ALLOWED_TRANSITIONS)})
BEGIN SELECT RAISE(ABORT, 'reel state change not allowed'); END;

CREATE TRIGGER reels_approved_needs_tap BEFORE UPDATE OF state ON reels
WHEN NEW.state = 'approved' AND OLD.state <> 'approved' AND (
    OLD.is_test <> 0 OR NOT EXISTS (
        SELECT 1 FROM approvals
        WHERE reel_id = OLD.reel_id AND revision = OLD.revision
            AND mp4_sha256 = OLD.mp4_sha256 AND action = 'approve'
    )
)
BEGIN SELECT RAISE(ABORT, 'approved needs the owner tap on this revision and file'); END;

CREATE TRIGGER reels_test_stays_test BEFORE UPDATE OF state ON reels
WHEN (NEW.state = 'awaiting_approval' AND OLD.is_test <> 0)
    OR (NEW.state = 'test_delivered' AND OLD.is_test = 0)
BEGIN SELECT RAISE(ABORT, 'a test reel is delivered, and only a test reel'); END;

CREATE TRIGGER reels_fixed_columns BEFORE UPDATE OF reel_id, slot_key, is_test ON reels
WHEN NEW.reel_id <> OLD.reel_id OR NEW.slot_key <> OLD.slot_key OR NEW.is_test <> OLD.is_test
BEGIN SELECT RAISE(ABORT, 'reel identity and test flag never change'); END;

CREATE TRIGGER reels_revision_only_goes_up BEFORE UPDATE OF revision ON reels
WHEN NEW.revision <> OLD.revision AND NOT (
    NEW.revision = OLD.revision + 1 AND NEW.state = 'draft'
    AND OLD.state IN ('regenerating', 'blocked_guardrails')
)
BEGIN SELECT RAISE(ABORT, 'revision moves up by one, only on the way back to draft'); END;

CREATE TRIGGER reels_file_is_bound BEFORE UPDATE OF mp4_path, mp4_sha256 ON reels
WHEN (NEW.mp4_path IS NOT OLD.mp4_path OR NEW.mp4_sha256 IS NOT OLD.mp4_sha256)
    AND NOT (OLD.state = 'voiced' AND NEW.state = 'rendered')
    AND NOT (NEW.revision = OLD.revision + 1)
BEGIN SELECT RAISE(ABORT, 'the file changes only at render or with a new revision'); END;

{_refuse_rewrites("reels")}

CREATE TRIGGER approvals_insert BEFORE INSERT ON approvals
WHEN EXISTS (SELECT 1 FROM approvals WHERE callback_query_id = NEW.callback_query_id)
BEGIN SELECT RAISE(ABORT, 'callback_query_id already used'); END;

CREATE TRIGGER approvals_no_update BEFORE UPDATE ON approvals
BEGIN SELECT RAISE(ABORT, 'approvals are append-only'); END;

{_refuse_rewrites("approvals")}

CREATE TRIGGER platform_posts_insert BEFORE INSERT ON platform_posts
WHEN NEW.status <> 'pending'
    OR EXISTS (
        SELECT 1 FROM platform_posts
        WHERE (reel_id = NEW.reel_id AND platform = NEW.platform)
            OR idempotency_key = NEW.idempotency_key
    )
BEGIN SELECT RAISE(ABORT, 'one pending row per reel and platform'); END;

CREATE TRIGGER platform_posts_status_change BEFORE UPDATE OF status ON platform_posts
WHEN NEW.status <> OLD.status
    AND OLD.status || '>' || NEW.status NOT IN ({_sql_pairs(ALLOWED_POST_CHANGES)})
BEGIN SELECT RAISE(ABORT, 'post status change not allowed'); END;

CREATE TRIGGER platform_posts_fixed_columns
BEFORE UPDATE OF reel_id, platform, idempotency_key ON platform_posts
WHEN NEW.reel_id <> OLD.reel_id OR NEW.platform <> OLD.platform
    OR NEW.idempotency_key <> OLD.idempotency_key
BEGIN SELECT RAISE(ABORT, 'a post row keeps its reel, platform and key'); END;

{_refuse_rewrites("platform_posts")}

CREATE TRIGGER events_no_update BEFORE UPDATE ON events
BEGIN SELECT RAISE(ABORT, 'events are append-only'); END;

{_refuse_rewrites("events")}
"""


def _timestamp(moment: datetime) -> str:
    if moment.tzinfo is None:
        raise ValueError("a time without a time zone cannot be stored")
    # One fixed width in UTC, so that SQL can compare these as text.
    return moment.astimezone(UTC).isoformat(timespec="microseconds")


def _parse_time(text: str | None) -> datetime | None:
    return None if text is None else datetime.fromisoformat(text)


def _as_path(text: str | None) -> Path | None:
    return None if text is None else Path(text)


def _reel_from(row: sqlite3.Row) -> Reel:
    return Reel(
        reel_id=row["reel_id"],
        slot_key=row["slot_key"],
        state=ReelState(row["state"]),
        revision=row["revision"],
        tier=row["tier"],
        template=row["template"],
        topic_id=row["topic_id"],
        target_duration=row["target_duration"],
        language=row["language"],
        is_test=bool(row["is_test"]),
        created_at=_parse_time(row["created_at"]),
        state_changed_at=_parse_time(row["state_changed_at"]),
        content_hash=row["content_hash"],
        mp4_path=_as_path(row["mp4_path"]),
        mp4_sha256=row["mp4_sha256"],
        voice_tier=row["voice_tier"],
        regenerations=row["regenerations"],
        regenerate_kind=row["regenerate_kind"],
        scheduled_for=_parse_time(row["scheduled_for"]),
    )


def _post_from(row: sqlite3.Row) -> PostRow:
    return PostRow(
        reel_id=row["reel_id"],
        platform=row["platform"],
        status=PostStatus(row["status"]),
        idempotency_key=row["idempotency_key"],
        remote_id=row["remote_id"],
        attempts=row["attempts"],
        posted_at=_parse_time(row["posted_at"]),
    )


def _voice_refused(reel: Reel, config: EngineConfig) -> bool:
    """Invariant 6. A reel with no recorded tier counts as free audio."""
    return reel.voice_tier != "S0" and not (
        reel.voice_tier == "F0" and config.voice.allow_public_on_f0
    )


class StateStore:
    """One connection to the state database. Open one per process, and use it on one thread."""

    def __init__(self, path: Path, clock: Callable[[], datetime] | None = None) -> None:
        self.path = Path(path)
        self._clock = clock or (lambda: datetime.now(UTC))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # isolation_level=None: no hidden transactions, only the explicit ones below.
        self._db = sqlite3.connect(self.path, timeout=_BUSY_TIMEOUT_SECONDS, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        try:
            self._prepare()
        except sqlite3.DatabaseError as error:
            self._db.close()
            raise StateError(f"{self.path} cannot be used as the state store: {error}") from error
        except StateError:
            self._db.close()
            raise

    def _prepare(self) -> None:
        self._db.execute("PRAGMA foreign_keys = ON")
        self._db.execute("PRAGMA synchronous = FULL")
        self._switch_to_wal()
        with self._transaction() as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version == 0:
                for statement in _split_statements(_SCHEMA):
                    db.execute(statement)
                db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            elif version != SCHEMA_VERSION:
                raise StateError(
                    f"{self.path} has schema version {version}, and this engine "
                    f"needs {SCHEMA_VERSION}"
                )

    def _switch_to_wal(self) -> None:
        # Two processes opening a new file together can get "locked" here at once, with no wait.
        for attempt in range(_WAL_SWITCH_TRIES):
            try:
                mode = self._db.execute("PRAGMA journal_mode = WAL").fetchone()[0]
            except sqlite3.OperationalError:
                if attempt == _WAL_SWITCH_TRIES - 1:
                    raise
                time.sleep(_WAL_SWITCH_PAUSE_SECONDS)
                continue
            if mode != "wal":
                raise StateError(f"{self.path} cannot use WAL mode, it stayed in {mode}")
            return

    def close(self) -> None:
        self._db.close()

    def __enter__(self) -> StateStore:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    @contextmanager
    def _transaction(self) -> Iterator[sqlite3.Connection]:
        """BEGIN IMMEDIATE takes the write lock first, so a read inside it stays true until the
        commit. Any exception rolls everything back, as a crash would."""
        self._db.execute("BEGIN IMMEDIATE")
        try:
            yield self._db
            self._db.execute("COMMIT")
        except BaseException:
            if self._db.in_transaction:
                self._db.execute("ROLLBACK")
            raise

    # --- Shared steps, each inside a caller's transaction ---------------------------------

    def _now(self) -> str:
        return _timestamp(self._clock())

    def _write_event(
        self,
        db: sqlite3.Connection,
        reel_id: str | None,
        kind: str,
        *,
        revision: int | None = None,
        from_state: str | None = None,
        to_state: str | None = None,
        platform: str | None = None,
        actor: Actor = Actor.ENGINE,
        detail: str = "",
    ) -> None:
        db.execute(
            "INSERT INTO events (reel_id, revision, kind, from_state, to_state, platform, actor, "
            "detail, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (reel_id, revision, kind, from_state, to_state, platform, actor, detail, self._now()),
        )

    def _read_reel(self, db: sqlite3.Connection, reel_id: str) -> Reel | None:
        row = db.execute("SELECT * FROM reels WHERE reel_id = ?", (reel_id,)).fetchone()
        return None if row is None else _reel_from(row)

    def _swap(
        self,
        db: sqlite3.Connection,
        reel: Reel,
        new: ReelState,
        *,
        actor: Actor = Actor.ENGINE,
        detail: str = "",
        **columns: object,
    ) -> bool:
        """The compare-and-swap from spec Section 3.4. Zero rows changed means someone else got
        there first, and then no event is written. Column names come only from this file."""
        settings = ["state = ?", "state_changed_at = ?", *(f"{name} = ?" for name in columns)]
        cursor = db.execute(
            f"UPDATE reels SET {', '.join(settings)} "
            "WHERE reel_id = ? AND state = ? AND revision = ?",
            (new, self._now(), *columns.values(), reel.reel_id, reel.state, reel.revision),
        )
        if cursor.rowcount == 0:
            return False
        self._write_event(
            db,
            reel.reel_id,
            "transition",
            revision=columns.get("revision", reel.revision),
            from_state=reel.state,
            to_state=new,
            actor=actor,
            detail=detail,
        )
        return True

    def _set_post_status(
        self,
        db: sqlite3.Connection,
        reel_id: str,
        platform: str,
        old: PostStatus,
        new: PostStatus,
        *,
        actor: Actor = Actor.ENGINE,
        expected_attempts: int | None = None,
        **columns: object,
    ) -> bool:
        settings = ["status = ?", *(f"{name} = ?" for name in columns)]
        where = "reel_id = ? AND platform = ? AND status = ?"
        values = [new, *columns.values(), reel_id, platform, old]
        if expected_attempts is not None:
            where += " AND attempts = ?"
            values.append(expected_attempts)
        statement = f"UPDATE platform_posts SET {', '.join(settings)} WHERE {where}"
        if db.execute(statement, values).rowcount == 0:
            return False
        self._write_event(
            db, reel_id, "post", from_state=old, to_state=new, platform=platform, actor=actor
        )
        return True

    def _read_post(self, db: sqlite3.Connection, reel_id: str, platform: str) -> PostRow | None:
        row = db.execute(
            "SELECT * FROM platform_posts WHERE reel_id = ? AND platform = ?", (reel_id, platform)
        ).fetchone()
        return None if row is None else _post_from(row)

    def _settle(self, db: sqlite3.Connection, reel_id: str, actor: Actor) -> None:
        """Moves the reel to match its platform rows, in the same transaction as their change."""
        reel = self._read_reel(db, reel_id)
        if reel is None or reel.state not in (_S.PUBLISHING, _S.NEEDS_ATTENTION):
            return
        statuses = [
            PostStatus(row["status"])
            for row in db.execute("SELECT status FROM platform_posts WHERE reel_id = ?", (reel_id,))
        ]
        if statuses and all(status in _DONE for status in statuses):
            self._swap(db, reel, _S.POSTED, actor=actor)
        elif any(status in _OWNER_CAN_RESOLVE for status in statuses):
            if reel.state == _S.PUBLISHING:
                self._swap(db, reel, _S.NEEDS_ATTENTION, actor=Actor.ENGINE)
        elif reel.state == _S.NEEDS_ATTENTION:
            self._swap(db, reel, _S.PUBLISHING, actor=actor)

    def _hash_of_reel_file(self, reel_id: str) -> str | None:
        """Read before the transaction opens, so a big file never holds up other writers. Each
        caller then compares it inside the transaction, against what the row says by then."""
        reel = self.get_reel(reel_id)
        return None if reel is None or reel.mp4_path is None else sha256_of_file(reel.mp4_path)

    def _publish_refusal(
        self, db: sqlite3.Connection, reel: Reel, config: EngineConfig, file_hash: str | None
    ) -> RefusalReason | None:
        """Everything that must hold just before anything goes out (Sections 3.3 and 10.1)."""
        if reel.is_test:
            return RefusalReason.TEST_REEL
        if not publish_allowed(config, test_reel=reel.is_test):
            return RefusalReason.BRAND_GATE
        if self._paused(db):
            return RefusalReason.PAUSED
        if _voice_refused(reel, config):
            return RefusalReason.F0_AUDIO
        if file_hash is None or file_hash != reel.mp4_sha256:
            return RefusalReason.HASH_CHANGED
        approval = db.execute(
            "SELECT 1 FROM approvals WHERE reel_id = ? AND revision = ? AND mp4_sha256 = ? "
            "AND action = ?",
            (reel.reel_id, reel.revision, file_hash, TapAction.APPROVE),
        ).fetchone()
        return None if approval else RefusalReason.NO_APPROVAL

    def _send_back(self, db: sqlite3.Connection, reel: Reel) -> bool:
        return self._swap(
            db,
            reel,
            _S.AWAITING_APPROVAL,
            detail=RefusalReason.HASH_CHANGED,
            scheduled_for=None,
        )

    def _new_revision(
        self, db: sqlite3.Connection, reel: Reel, *, regenerations: int | None = None
    ) -> bool:
        """Nothing from the old revision survives, so nothing can be approved or posted from it."""
        return self._swap(
            db,
            reel,
            _S.DRAFT,
            revision=reel.revision + 1,
            regenerations=reel.regenerations if regenerations is None else regenerations,
            mp4_path=None,
            mp4_sha256=None,
            content_hash=None,
            voice_tier=None,
            scheduled_for=None,
        )

    def _paused(self, db: sqlite3.Connection) -> bool:
        row = db.execute("SELECT value FROM settings WHERE key = ?", (_PAUSED_KEY,)).fetchone()
        return row is not None and row["value"] == "1"

    # --- Creating a reel and the engine's own steps ----------------------------------------

    def create_reel(
        self,
        *,
        slot_key: str,
        topic_id: str,
        tier: str,
        template: str,
        language: str,
        target_duration: float,
        is_test: bool,
    ) -> tuple[Reel, bool]:
        """Returns the slot's reel and whether this call made it. A second call for the slot,
        such as after a crash, gets the first reel back, so one slot can never hold two."""
        now = self._now()
        with self._transaction() as db:
            row = db.execute("SELECT * FROM reels WHERE slot_key = ?", (slot_key,)).fetchone()
            if row is not None:
                return _reel_from(row), False
            reel_id = uuid.uuid4().hex  # 32 characters, to stay in callback_data's 64 bytes
            db.execute(
                "INSERT INTO reels (reel_id, slot_key, state, tier, template, topic_id, "
                "target_duration, language, is_test, created_at, state_changed_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    reel_id,
                    slot_key,
                    _S.DRAFT,
                    tier,
                    template,
                    topic_id,
                    target_duration,
                    language,
                    int(is_test),
                    now,
                    now,
                ),
            )
            self._write_event(db, reel_id, "transition", revision=1, to_state=_S.DRAFT)
            return self._read_reel(db, reel_id), True

    def transition(self, reel_id: str, old: ReelState, new: ReelState, *, detail: str = "") -> bool:
        """A plain engine move. False means the reel is not in `old` any more, and nothing changed.
        Moves that carry data or checks, and all of the owner's, are refused here."""
        if (old, new) in OWNER_ONLY_TRANSITIONS:
            raise OwnerTapRequired(f"{old} to {new} needs the owner's tap")
        if (old, new) not in PLAIN_TRANSITIONS:
            raise IllegalTransition(f"{old} to {new} is not a plain engine move")
        with self._transaction() as db:
            reel = self._read_reel(db, reel_id)
            if reel is None or reel.state != old:
                return False
            return self._swap(db, reel, new, detail=detail)

    def _current(
        self, db: sqlite3.Connection, reel_id: str, state: ReelState, revision: int
    ) -> Reel | None:
        reel = self._read_reel(db, reel_id)
        return reel if reel and reel.state == state and reel.revision == revision else None

    def record_voiced(self, reel_id: str, revision: int, voice_tier: str) -> bool:
        if voice_tier not in _VOICE_TIERS:
            raise ValueError(f"unknown voice tier: {voice_tier!r}")
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.DRAFT, revision)
            return bool(reel) and self._swap(
                db, reel, _S.VOICED, voice_tier=voice_tier, regenerate_kind=None
            )

    def record_rendered(
        self, reel_id: str, revision: int, mp4_path: Path, content_hash: str, config: EngineConfig
    ) -> bool:
        """The hash is taken here, from the file itself, and the approval binds to this value."""
        file_hash = sha256_of_file(mp4_path)
        if file_hash is None:
            raise ActionRefused(RefusalReason.HASH_CHANGED, reel_id)
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.VOICED, revision)
            if reel is None:
                return False
            refused = not render_decision(config, test_reel=reel.is_test).allowed
            if not refused:
                return self._swap(
                    db,
                    reel,
                    _S.RENDERED,
                    mp4_path=os.path.abspath(mp4_path),  # a later run may start in another folder
                    mp4_sha256=file_hash,
                    content_hash=content_hash,
                )
        raise ActionRefused(RefusalReason.BRAND_GATE, reel_id)

    def offer_for_approval(self, reel_id: str, revision: int, config: EngineConfig) -> bool:
        """Call this only after Telegram confirms the message was sent (spec Section 3.3)."""
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.RENDERED, revision)
            if reel is None:
                return False
            refusal = _offer_refusal(reel, config)
            if refusal is None:
                return self._swap(db, reel, _S.AWAITING_APPROVAL)
        raise ActionRefused(refusal, reel_id)

    def mark_test_delivered(self, reel_id: str, revision: int) -> bool:
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.RENDERED, revision)
            if reel is None:
                return False
            if reel.is_test:
                return self._swap(db, reel, _S.TEST_DELIVERED)
        raise ActionRefused(RefusalReason.NOT_TEST_REEL, reel_id)

    def finish_regeneration(self, reel_id: str, revision: int) -> bool:
        """`regenerate_kind` stays until the reel is voiced, so the tick knows how far back to go:
        a new script, or the same script with new audio."""
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.REGENERATING, revision)
            return bool(reel) and self._new_revision(db, reel)

    def retry_after_block(self, reel_id: str, revision: int, max_regenerations: int) -> bool:
        """False once the limit is used up. The reel then stays blocked for the owner to see."""
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.BLOCKED_GUARDRAILS, revision)
            if reel is None or reel.regenerations >= max_regenerations:
                return False
            return self._new_revision(db, reel, regenerations=reel.regenerations + 1)

    def expire_overdue(self, expire_after_hours: int) -> list[str]:
        cutoff = _timestamp(self._clock() - timedelta(hours=expire_after_hours))
        with self._transaction() as db:
            rows = db.execute(
                "SELECT * FROM reels WHERE state = ? AND state_changed_at <= ? ORDER BY rowid",
                (_S.AWAITING_APPROVAL, cutoff),
            ).fetchall()
            return [
                row["reel_id"] for row in rows if self._swap(db, _reel_from(row), _S.EXPIRED)
            ]

    def requeue(self, reel_id: str, config: EngineConfig) -> bool:
        """`/requeue <id>`: the only way out of `expired`. The reel is offered again, so the gate
        is checked again. Approving it still takes a new tap."""
        with self._transaction() as db:
            reel = self._read_reel(db, reel_id)
            if reel is None or reel.state != _S.EXPIRED:
                return False
            refusal = _offer_refusal(reel, config)
            if refusal is None:
                return self._swap(db, reel, _S.AWAITING_APPROVAL, actor=Actor.OWNER)
        raise ActionRefused(refusal, reel_id)

    def schedule_reel(self, reel_id: str, revision: int, at: datetime) -> bool:
        stamp = _timestamp(at)
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.APPROVED, revision)
            return bool(reel) and self._swap(db, reel, _S.SCHEDULED, scheduled_for=stamp)

    def reschedule(self, reel_id: str, revision: int, at: datetime) -> bool:
        """A passed window moves to the next one. The reel is never posted late (Section 3.5)."""
        stamp = _timestamp(at)
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.SCHEDULED, revision)
            if reel is None:
                return False
            db.execute(
                "UPDATE reels SET scheduled_for = ? WHERE reel_id = ?", (stamp, reel_id)
            )
            self._write_event(db, reel_id, "rescheduled", revision=revision, detail=stamp)
            return True

    def send_back_if_file_changed(self, reel_id: str, revision: int) -> bool:
        """Invariant 2, for callers that hold a reel between approval and publishing. True means
        the file no longer matches and the reel has gone back to the owner."""
        file_hash = self._hash_of_reel_file(reel_id)
        with self._transaction() as db:
            reel = self._read_reel(db, reel_id)
            if (
                reel is None
                or reel.revision != revision
                or reel.state not in _APPROVED_FILE_STATES
                or (file_hash is not None and file_hash == reel.mp4_sha256)
            ):
                return False
            return self._send_back(db, reel)

    # --- The owner's taps -------------------------------------------------------------------

    def apply_tap(self, tap: VerifiedOwnerTap, config: EngineConfig) -> TapResult:
        """The one way a tap changes anything. The row that burns its callback id commits with
        the state change, so a crash leaves either both or neither."""
        if type(tap) is not VerifiedOwnerTap:
            raise TypeError("apply_tap takes a verified owner tap and nothing else")
        needs_hash = tap.action == TapAction.APPROVE
        file_hash = self._hash_of_reel_file(tap.reel_id) if needs_hash else None
        with self._transaction() as db:
            seen = db.execute(
                "SELECT 1 FROM approvals WHERE callback_query_id = ?", (tap.callback_query_id,)
            ).fetchone()
            if seen:
                return TapResult(TapOutcome.DUPLICATE)
            reel = self._read_reel(db, tap.reel_id)
            if reel is None:
                return self._refuse_tap(db, tap, RefusalReason.UNKNOWN_REEL)
            if tap.revision != reel.revision:
                self._write_event(
                    db,
                    reel.reel_id,
                    "tap_stale",
                    revision=tap.revision,
                    actor=Actor.OWNER,
                    detail=RefusalReason.STALE_REVISION,
                )
                return TapResult(TapOutcome.STALE, RefusalReason.STALE_REVISION)
            refusal = self._apply_action(db, tap, reel, config, file_hash)
            if refusal is not None:
                return self._refuse_tap(db, tap, refusal)
            return TapResult(TapOutcome.APPLIED)

    def _refuse_tap(
        self, db: sqlite3.Connection, tap: VerifiedOwnerTap, reason: RefusalReason
    ) -> TapResult:
        self._write_event(
            db,
            tap.reel_id,
            "tap_refused",
            revision=tap.revision,
            platform=tap.platform,
            actor=Actor.OWNER,
            detail=reason,
        )
        return TapResult(TapOutcome.REFUSED, reason)

    def _record_tap(
        self, db: sqlite3.Connection, tap: VerifiedOwnerTap, mp4_sha256: str | None
    ) -> None:
        db.execute(
            "INSERT INTO approvals (reel_id, revision, mp4_sha256, telegram_user_id, action, "
            "platform, callback_query_id, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                tap.reel_id,
                tap.revision,
                mp4_sha256,
                tap.telegram_user_id,
                tap.action,
                tap.platform,
                tap.callback_query_id,
                self._now(),
            ),
        )

    def _apply_action(
        self,
        db: sqlite3.Connection,
        tap: VerifiedOwnerTap,
        reel: Reel,
        config: EngineConfig,
        file_hash: str | None,
    ) -> RefusalReason | None:
        if tap.action in _PLATFORM_ACTIONS:
            return self._apply_platform_action(db, tap, reel)
        if reel.state != _S.AWAITING_APPROVAL:
            return RefusalReason.NOT_AWAITING
        if tap.action == TapAction.APPROVE:
            return self._approve(db, tap, reel, config, file_hash)
        if tap.action == TapAction.REGENERATE:
            if reel.regenerations >= config.approval.max_regenerations:
                return RefusalReason.LIMIT_REACHED
            self._record_tap(db, tap, reel.mp4_sha256)
            self._swap(
                db,
                reel,
                _S.REGENERATING,
                actor=Actor.OWNER,
                regenerations=reel.regenerations + 1,
                regenerate_kind="script",
            )
            return None
        if tap.action == TapAction.REVOICE:
            if not _voice_refused(reel, config):
                return RefusalReason.NOT_F0
            self._record_tap(db, tap, reel.mp4_sha256)
            self._swap(db, reel, _S.REGENERATING, actor=Actor.OWNER, regenerate_kind="voice")
            return None
        self._record_tap(db, tap, reel.mp4_sha256)
        self._swap(db, reel, _S.REJECTED, actor=Actor.OWNER)
        return None

    def _approve(
        self,
        db: sqlite3.Connection,
        tap: VerifiedOwnerTap,
        reel: Reel,
        config: EngineConfig,
        file_hash: str | None,
    ) -> RefusalReason | None:
        if reel.is_test:
            return RefusalReason.TEST_REEL
        if not approval_allowed(config, test_reel=reel.is_test):
            return RefusalReason.BRAND_GATE
        if _voice_refused(reel, config):
            return RefusalReason.F0_AUDIO
        if file_hash is None or file_hash != reel.mp4_sha256:
            return RefusalReason.HASH_CHANGED
        self._record_tap(db, tap, file_hash)
        self._swap(db, reel, _S.APPROVED, actor=Actor.OWNER)
        return None

    def _apply_platform_action(
        self, db: sqlite3.Connection, tap: VerifiedOwnerTap, reel: Reel
    ) -> RefusalReason | None:
        """Posted reports what the owner did by hand or saw, so it needs no pre-check. Retry only
        makes a row eligible again, and `begin_post` repeats every check before a send."""
        if reel.state not in (_S.PUBLISHING, _S.NEEDS_ATTENTION):
            return RefusalReason.NOT_PUBLISHING
        post = self._read_post(db, reel.reel_id, tap.platform)
        if post is None:
            return RefusalReason.NOT_PENDING
        if tap.action == TapAction.POSTED:
            if post.status not in (_P.PENDING, *_OWNER_CAN_RESOLVE):
                return RefusalReason.NOT_PENDING
            self._record_tap(db, tap, reel.mp4_sha256)
            self._set_post_status(
                db,
                reel.reel_id,
                tap.platform,
                post.status,
                _P.POSTED,
                actor=Actor.OWNER,
                posted_at=self._now(),
            )
            self._settle(db, reel.reel_id, Actor.OWNER)
            return None
        if post.status not in _OWNER_CAN_RESOLVE:
            return RefusalReason.NOT_PENDING
        self._record_tap(db, tap, reel.mp4_sha256)
        self._set_post_status(
            db, reel.reel_id, tap.platform, post.status, _P.PENDING, actor=Actor.OWNER
        )
        if reel.state == _S.NEEDS_ATTENTION:
            self._swap(db, reel, _S.PUBLISHING, actor=Actor.OWNER)
        return None

    # --- Publishing ----------------------------------------------------------------------------

    def start_publishing(
        self, reel_id: str, revision: int, platforms: Iterable[str], config: EngineConfig
    ) -> bool:
        """The window has arrived. Rows are per reel and platform across all revisions, and rows
        from before a send-back stay as they were, so what was posted is never sent again."""
        targets = list(platforms)
        if (
            not targets
            or len(set(targets)) != len(targets)
            or any(target not in PLATFORMS for target in targets)
        ):
            raise ValueError(f"bad platforms to publish to: {targets!r}")
        file_hash = self._hash_of_reel_file(reel_id)
        with self._transaction() as db:
            reel = self._current(db, reel_id, _S.SCHEDULED, revision)
            if reel is None:
                return False
            refusal = self._publish_refusal(db, reel, config, file_hash)
            if refusal == RefusalReason.HASH_CHANGED:
                self._send_back(db, reel)
            elif refusal is None:
                self._swap(db, reel, _S.PUBLISHING)
                for platform in targets:
                    if self._read_post(db, reel_id, platform) is None:
                        self._add_post(db, reel_id, platform)
                self._settle(db, reel_id, Actor.ENGINE)
                return True
        raise ActionRefused(refusal, reel_id)

    def _add_post(self, db: sqlite3.Connection, reel_id: str, platform: str) -> None:
        db.execute(
            "INSERT INTO platform_posts (reel_id, platform, status, idempotency_key) "
            "VALUES (?, ?, ?, ?)",
            (reel_id, platform, _P.PENDING, post_idempotency_key(reel_id, platform)),
        )
        self._write_event(db, reel_id, "post", to_state=_P.PENDING, platform=platform)

    def begin_post(self, reel_id: str, platform: str, config: EngineConfig) -> PostClaim:
        """Step 1 of double-post protection: `in_flight` is on disk before this returns. Call the
        provider only with the claim this gives, and report the result to `record_post_result`.
        If the process dies in between, the row stays `in_flight` until recovery."""
        file_hash = self._hash_of_reel_file(reel_id)
        with self._transaction() as db:
            reel = self._read_reel(db, reel_id)
            refusal = self._post_refusal(db, reel, platform, config, file_hash)
            if refusal == RefusalReason.HASH_CHANGED:
                self._send_back(db, reel)
            elif refusal is None:
                self._set_post_status(db, reel_id, platform, _P.PENDING, _P.IN_FLIGHT)
                db.execute(
                    "UPDATE platform_posts SET attempts = attempts + 1 "
                    "WHERE reel_id = ? AND platform = ?",
                    (reel_id, platform),
                )
                post = self._read_post(db, reel_id, platform)
                return PostClaim(
                    reel_id=reel_id,
                    platform=platform,
                    revision=reel.revision,
                    mp4_path=reel.mp4_path,
                    mp4_sha256=reel.mp4_sha256,
                    idempotency_key=post.idempotency_key,
                    attempt=post.attempts,
                )
        raise ActionRefused(refusal, reel_id)

    def _post_refusal(
        self,
        db: sqlite3.Connection,
        reel: Reel | None,
        platform: str,
        config: EngineConfig,
        file_hash: str | None,
    ) -> RefusalReason | None:
        if reel is None:
            return RefusalReason.UNKNOWN_REEL
        if reel.state != _S.PUBLISHING:
            return RefusalReason.NOT_PUBLISHING
        refusal = self._publish_refusal(db, reel, config, file_hash)
        if refusal is not None:
            return refusal
        post = self._read_post(db, reel.reel_id, platform)
        return None if post and post.status == _P.PENDING else RefusalReason.NOT_PENDING

    def record_post_result(
        self, claim: PostClaim, outcome: PostOutcome, *, remote_id: str | None = None
    ) -> bool:
        """Steps 3 to 5 of double-post protection. A success with no remote id is an unclear
        answer. False means this attempt no longer owns the row, so its result changes nothing."""
        posted = outcome == PostOutcome.POSTED and bool(remote_id and remote_id.strip())
        new = (
            _P.POSTED
            if posted
            else _P.FAILED
            if outcome == PostOutcome.FAILED
            else _P.UNKNOWN_OUTCOME
        )
        columns = {"remote_id": remote_id, "posted_at": self._now()} if posted else {}
        with self._transaction() as db:
            changed = self._set_post_status(
                db,
                claim.reel_id,
                claim.platform,
                _P.IN_FLIGHT,
                new,
                expected_attempts=claim.attempt,
                **columns,
            )
            if changed:
                self._settle(db, claim.reel_id, Actor.ENGINE)
            return changed

    def skip_platform(self, reel_id: str, platform: str) -> bool:
        with self._transaction() as db:
            changed = self._set_post_status(db, reel_id, platform, _P.PENDING, _P.SKIPPED)
            if changed:
                self._settle(db, reel_id, Actor.ENGINE)
            return changed

    def recover_interrupted(self, lock: EngineLock) -> list[PostRow]:
        """At startup, any row still `in_flight` becomes `unknown_outcome`, for the owner to check.
        A row in flight in a live process looks the same as one left by a dead process, so this
        runs only with the lock held, when no other run can be mid-send."""
        if not isinstance(lock, EngineLock) or not lock.held:
            raise StateError("recovery needs the engine lock to be held")
        with self._transaction() as db:
            rows = [
                _post_from(row)
                for row in db.execute(
                    "SELECT * FROM platform_posts WHERE status = ?", (_P.IN_FLIGHT,)
                ).fetchall()
            ]
            for post in rows:
                self._set_post_status(
                    db, post.reel_id, post.platform, _P.IN_FLIGHT, _P.UNKNOWN_OUTCOME
                )
            for reel_id in {post.reel_id for post in rows}:
                self._settle(db, reel_id, Actor.ENGINE)
            return rows

    # --- Pause, runs, notes and metrics -----------------------------------------------------

    def set_paused(self, paused: bool) -> None:
        with self._transaction() as db:
            db.execute(
                "INSERT INTO settings (key, value) VALUES (?, ?) "
                "ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                (_PAUSED_KEY, "1" if paused else "0"),
            )
            self._write_event(db, None, "paused" if paused else "resumed", actor=Actor.OWNER)

    def is_paused(self) -> bool:
        return self._paused(self._db)

    def begin_run(self, run_key: str, step: str) -> RunClaim:
        """`runs` has one row per scheduled day and step, so a re-run finds work already done.
        Each start counts a try, so a run that keeps dying uses up its retry budget too."""
        now = self._now()
        with self._transaction() as db:
            row = db.execute(
                "SELECT * FROM runs WHERE run_key = ? AND step = ?", (run_key, step)
            ).fetchone()
            if row is None:
                db.execute(
                    "INSERT INTO runs (run_key, step, status, attempts, started_at) "
                    "VALUES (?, ?, 'started', 1, ?)",
                    (run_key, step, now),
                )
                return RunClaim(already_done=False, attempts=1, reel_id=None)
            if row["status"] == "done":
                return RunClaim(True, row["attempts"], row["reel_id"])
            db.execute(
                "UPDATE runs SET attempts = attempts + 1, started_at = ? "
                "WHERE run_key = ? AND step = ?",
                (now, run_key, step),
            )
            return RunClaim(False, row["attempts"] + 1, row["reel_id"])

    def finish_run(self, run_key: str, step: str, *, reel_id: str | None = None) -> None:
        with self._transaction() as db:
            cursor = db.execute(
                "UPDATE runs SET status = 'done', finished_at = ?, reel_id = ? "
                "WHERE run_key = ? AND step = ?",
                (self._now(), reel_id, run_key, step),
            )
            if cursor.rowcount == 0:
                raise StateError(f"run {run_key} step {step} was never started")

    def give_back_attempt(self, run_key: str, step: str) -> None:
        """A usage-limit error is not a failure, and waits for a later tick (Section 3.5)."""
        with self._transaction() as db:
            db.execute(
                "UPDATE runs SET attempts = MAX(attempts - 1, 0) WHERE run_key = ? AND step = ?",
                (run_key, step),
            )

    def add_note(self, reel_id: str, text: str) -> None:
        with self._transaction() as db:
            self._write_event(
                db, reel_id, "note", actor=Actor.OWNER, detail=text[:_NOTE_MAX_CHARS]
            )

    def record_metric(
        self, reel_id: str, platform: str, *, views: int, saves: int, shares: int
    ) -> None:
        with self._transaction() as db:
            db.execute(
                "INSERT INTO metrics (reel_id, platform, views, saves, shares, at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (reel_id, platform, views, saves, shares, self._now()),
            )

    # --- Reading -----------------------------------------------------------------------------

    def get_reel(self, reel_id: str) -> Reel | None:
        return self._read_reel(self._db, reel_id)

    def reels_in(self, *states: ReelState) -> list[Reel]:
        marks = ", ".join("?" for _ in states)
        rows = self._db.execute(
            f"SELECT * FROM reels WHERE state IN ({marks}) ORDER BY created_at, rowid", states
        ).fetchall()
        return [_reel_from(row) for row in rows]

    def count_reels(self) -> int:
        return self._db.execute("SELECT COUNT(*) FROM reels").fetchone()[0]

    def waiting_count(self) -> int:
        """Reels the owner has not answered, for `approval.max_waiting`."""
        return self._db.execute(
            "SELECT COUNT(*) FROM reels WHERE state = ?", (_S.AWAITING_APPROVAL,)
        ).fetchone()[0]

    def generated_reels(self) -> list[GeneratedReel]:
        rows = self._db.execute("SELECT slot_key, created_at FROM reels").fetchall()
        return [GeneratedReel(row["slot_key"], _parse_time(row["created_at"])) for row in rows]

    def posts_for(self, reel_id: str) -> list[PostRow]:
        rows = self._db.execute(
            "SELECT * FROM platform_posts WHERE reel_id = ? ORDER BY rowid", (reel_id,)
        ).fetchall()
        return [_post_from(row) for row in rows]

    def unresolved_posts(self) -> list[PostRow]:
        """What the bot must ask the owner about."""
        rows = self._db.execute(
            "SELECT * FROM platform_posts WHERE status IN (?, ?) ORDER BY rowid",
            _OWNER_CAN_RESOLVE,
        ).fetchall()
        return [_post_from(row) for row in rows]

    def approvals_for(self, reel_id: str) -> list[ApprovalRow]:
        rows = self._db.execute(
            "SELECT reel_id, revision, mp4_sha256, telegram_user_id, action, platform, "
            "callback_query_id, at FROM approvals WHERE reel_id = ? ORDER BY approval_id",
            (reel_id,),
        ).fetchall()
        return [ApprovalRow(**(dict(row) | {"at": _parse_time(row["at"])})) for row in rows]

    def events_for(self, reel_id: str) -> list[EventRow]:
        rows = self._db.execute(
            "SELECT reel_id, revision, kind, from_state, to_state, platform, actor, detail, at "
            "FROM events WHERE reel_id = ? ORDER BY event_id",
            (reel_id,),
        ).fetchall()
        return [EventRow(**(dict(row) | {"at": _parse_time(row["at"])})) for row in rows]

    def metrics_for(self, reel_id: str) -> list[MetricRow]:
        rows = self._db.execute(
            "SELECT reel_id, platform, views, saves, shares, at FROM metrics "
            "WHERE reel_id = ? ORDER BY metric_id",
            (reel_id,),
        ).fetchall()
        return [MetricRow(**(dict(row) | {"at": _parse_time(row["at"])})) for row in rows]


def _offer_refusal(reel: Reel, config: EngineConfig) -> RefusalReason | None:
    if reel.is_test:
        return RefusalReason.TEST_REEL
    if not approve_button_allowed(config, test_reel=reel.is_test):
        return RefusalReason.BRAND_GATE
    return None


def _split_statements(script: str) -> Iterator[str]:
    """executescript commits first, so it cannot run inside the transaction that sets up the
    tables. This keeps a half-made schema from ever being seen."""
    buffer = ""
    for line in script.splitlines(keepends=True):
        buffer += line
        if sqlite3.complete_statement(buffer):
            if buffer.strip():
                yield buffer
            buffer = ""
