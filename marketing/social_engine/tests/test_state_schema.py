"""The state store's tables and what the database itself refuses (spec Section 3.4, task B1).

These tests write raw SQL on purpose: the protections here must hold even if engine code
above them is wrong.
"""

import sqlite3

import pytest

from core.state import SCHEMA_VERSION, StateError, StateStore

SPEC_COLUMNS = {
    "reels": {
        "reel_id",
        "state",
        "revision",
        "tier",
        "template",
        "topic_id",
        "target_duration",
        "created_at",
        "content_hash",
        "mp4_path",
        "mp4_sha256",
    },
    "approvals": {
        "reel_id",
        "revision",
        "mp4_sha256",
        "telegram_user_id",
        "action",
        "callback_query_id",
        "at",
    },
    "platform_posts": {
        "reel_id",
        "platform",
        "status",
        "idempotency_key",
        "remote_id",
        "attempts",
        "posted_at",
    },
    "runs": {"run_key", "step"},
    "events": {"reel_id", "from_state", "to_state", "at"},
}


@pytest.fixture
def store(tmp_path):
    with StateStore(tmp_path / "state" / "engine.db") as opened:
        yield opened


def add_reel(db, reel_id="r1", slot_key="2026-11-05", state="draft", is_test=0):
    db.execute(
        "INSERT INTO reels (reel_id, slot_key, state, revision, tier, template, topic_id, "
        "target_duration, language, is_test, created_at, state_changed_at) "
        "VALUES (?, ?, ?, 1, 'global', 'DailyTip', 't1', 30, 'ar', ?, 'x', 'x')",
        (reel_id, slot_key, state, is_test),
    )


def add_post(db, reel_id="r1", platform="instagram", key="k1", status="pending"):
    db.execute(
        "INSERT INTO platform_posts (reel_id, platform, status, idempotency_key) "
        "VALUES (?, ?, ?, ?)",
        (reel_id, platform, status, key),
    )


def add_approval(db, callback_query_id="cb1", reel_id="r1"):
    db.execute(
        "INSERT INTO approvals (reel_id, revision, mp4_sha256, telegram_user_id, action, "
        "callback_query_id, at) VALUES (?, 1, 'h', 1, 'reject', ?, 'x')",
        (reel_id, callback_query_id),
    )


def add_event(db, reel_id="r1"):
    db.execute(
        "INSERT INTO events (reel_id, kind, actor, at) VALUES (?, 'note', 'engine', 'x')",
        (reel_id,),
    )


def columns(db, table):
    return {row[1] for row in db.execute(f"PRAGMA table_info({table})")}


@pytest.mark.parametrize(("table", "expected"), SPEC_COLUMNS.items(), ids=SPEC_COLUMNS)
def test_each_spec_table_has_its_columns(store, table, expected):
    assert expected <= columns(store._db, table)


def test_the_database_is_where_it_was_asked_to_be(tmp_path):
    path = tmp_path / "deep" / "state" / "engine.db"
    with StateStore(path):
        assert path.is_file()


def test_wal_mode_is_on_and_stays_on_for_a_second_connection(store, tmp_path):
    assert store._db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    other = sqlite3.connect(tmp_path / "state" / "engine.db")
    try:
        assert other.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    finally:
        other.close()


def test_every_commit_is_synced_to_disk(store):
    # FULL is 2. An `in_flight` row that a power cut could lose would allow a double post.
    assert store._db.execute("PRAGMA synchronous").fetchone()[0] == 2


def test_foreign_keys_are_enforced(store):
    assert store._db.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    with pytest.raises(sqlite3.IntegrityError):
        add_post(store._db, reel_id="no-such-reel")


def test_a_second_row_for_the_same_reel_and_platform_fails_at_the_database(store):
    add_reel(store._db)
    add_post(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        add_post(store._db, key="k2")


def test_a_second_platform_for_the_same_reel_is_fine(store):
    add_reel(store._db)
    add_post(store._db)
    add_post(store._db, platform="tiktok", key="k2")


@pytest.mark.parametrize("verb", ["INSERT OR REPLACE", "REPLACE"])
def test_replace_cannot_wipe_a_platform_row(store, verb):
    add_reel(store._db)
    add_post(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute(
            f"{verb} INTO platform_posts (reel_id, platform, status, idempotency_key) "
            "VALUES ('r1', 'instagram', 'pending', 'k1')"
        )
    assert store._db.execute("SELECT COUNT(*) FROM platform_posts").fetchone()[0] == 1


def test_a_platform_row_cannot_start_as_anything_but_pending(store):
    add_reel(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        add_post(store._db, status="posted")


def test_a_repeated_callback_query_id_fails_at_the_database(store):
    add_reel(store._db)
    add_approval(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        add_approval(store._db)


def test_replace_cannot_wipe_an_approval(store):
    add_reel(store._db)
    add_approval(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute(
            "INSERT OR REPLACE INTO approvals (reel_id, revision, mp4_sha256, telegram_user_id, "
            "action, callback_query_id, at) VALUES ('r1', 1, 'h', 1, 'reject', 'cb1', 'x')"
        )


def test_the_same_slot_cannot_hold_two_reels(store):
    add_reel(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        add_reel(store._db, reel_id="r2")


def test_replace_cannot_wipe_a_reel(store):
    add_reel(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute(
            "INSERT OR REPLACE INTO reels (reel_id, slot_key, state, revision, tier, template, "
            "topic_id, target_duration, language, is_test, created_at, state_changed_at) "
            "VALUES ('r1', 'other', 'draft', 1, 'global', 'DailyTip', 't', 30, 'ar', 0, 'x', 'x')"
        )


def test_a_run_key_and_step_can_appear_only_once(store):
    insert = "INSERT INTO runs (run_key, step, status, attempts, started_at) VALUES (?, ?, ?, 1, ?)"
    store._db.execute(insert, ("2026-11-05", "script", "started", "x"))
    store._db.execute(insert, ("2026-11-05", "voice", "started", "x"))
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute(insert, ("2026-11-05", "script", "started", "x"))


def test_a_reel_cannot_start_in_a_later_state(store):
    with pytest.raises(sqlite3.IntegrityError):
        add_reel(store._db, state="approved")


@pytest.mark.parametrize(
    "insert",
    [
        lambda db: add_reel(db, reel_id="r2", slot_key="s2", state="no_such_state"),
        lambda db: add_reel(db, reel_id="r2", slot_key="s2", is_test=2),
        lambda db: add_post(db, status="no_such_status"),
        lambda db: add_post(db, platform="myspace"),
    ],
    ids=["reel state", "test flag", "post status", "platform"],
)
def test_values_outside_the_spec_fail_at_the_database(store, insert):
    add_reel(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        insert(store._db)


@pytest.mark.parametrize(
    "statement",
    [
        "DELETE FROM events",
        "UPDATE events SET detail = 'rewritten'",
        "DELETE FROM approvals",
        "UPDATE approvals SET action = 'approve'",
        "DELETE FROM platform_posts",
        "DELETE FROM reels",
    ],
)
def test_the_record_cannot_be_rewritten(store, statement):
    add_reel(store._db)
    add_post(store._db)
    add_approval(store._db)
    add_event(store._db)
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute(statement)


def test_a_reopened_store_keeps_its_data(tmp_path):
    path = tmp_path / "engine.db"
    with StateStore(path) as first:
        add_reel(first._db)
    with StateStore(path) as second:
        assert second._db.execute("SELECT COUNT(*) FROM reels").fetchone()[0] == 1


def test_a_database_from_another_schema_version_is_refused(tmp_path):
    path = tmp_path / "engine.db"
    with StateStore(path) as first:
        first._db.execute(f"PRAGMA user_version = {SCHEMA_VERSION + 1}")
    with pytest.raises(StateError, match="schema version"):
        StateStore(path)


def test_a_file_that_is_not_a_database_is_refused(tmp_path):
    path = tmp_path / "engine.db"
    path.write_bytes(b"this is not a database, and it is long enough to be read as a header" * 8)
    with pytest.raises(StateError):
        StateStore(path)
    assert path.read_bytes().startswith(b"this is not")


def test_using_a_closed_store_fails_loudly(tmp_path):
    store = StateStore(tmp_path / "engine.db")
    store.close()
    with pytest.raises(sqlite3.ProgrammingError):
        store._db.execute("SELECT 1")
