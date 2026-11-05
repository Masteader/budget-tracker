"""The account deletion worker, with every outside service mocked.

The fake client answers in the shapes supabase/migrations/20261105000300 and 000400 return, and
test_rpc_calls_match_the_migrations checks the worker's calls against those files.
"""

from __future__ import annotations

import pathlib
import re
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

import account_deletion_notices as notices
import account_deletion_worker as worker
import mail_service

MIGRATIONS = pathlib.Path(__file__).resolve().parents[2] / "supabase" / "migrations"

REQ = "11111111-1111-4111-8111-111111111111"
USER = "22222222-2222-4222-8222-222222222222"
MEMBER = "33333333-3333-4333-8333-333333333333"
MEMBER2 = "44444444-4444-4444-8444-444444444444"
HH = "55555555-5555-4555-8555-555555555555"
EMAIL = "leaving.person@example.com"
TOKEN = "token-value-never-log-this"

DESTRUCTIVE_RPCS = {
    "claim_due_account_deletions",
    "prepare_account_purge",
    "mark_account_purge_storage_done",
    "complete_account_purge",
    "record_account_purge_failure",
    "mark_account_deletion_notice_sent",
    "purge_expired_account_deletion_inquiries",
    "record_account_deletion_worker_run",
}


class ApiError(Exception):
    """Shaped like postgrest.APIError: ``str()`` is the body, attributes carry the fields."""

    def __init__(self, message: str, hint: str = "", code: str = "22023"):
        super().__init__(message)
        self.message, self.hint, self.code, self.details = message, hint, code, ""


class AuthError(Exception):
    def __init__(self, message: str, status: int, code: str = ""):
        super().__init__(message)
        self.message, self.status, self.code = message, status, code


class Bucket:
    def __init__(self, client, name):
        self.client, self.name = client, name

    def list(self, path=None, options=None):
        self.client.calls.append(("storage.list", self.name, path, dict(options or {})))
        self.client.maybe_fail(f"storage.list:{path}")
        limit = (options or {}).get("limit", 100)
        offset = (options or {}).get("offset", 0)
        return self.client.folders.get(path, [])[offset:offset + limit]

    def remove(self, paths):
        self.client.calls.append(("storage.remove", self.name, list(paths)))
        self.client.maybe_fail("storage.remove")
        return [{"name": p} for p in paths]


class FakeClient:
    """Records every outside call in order. There is no .table: the worker is RPC only."""

    def __init__(self, jobs=None):
        self.calls: list = []
        self.jobs = list(jobs or [])
        self.results: dict = {}
        self.failures: dict = {}
        self.folders: dict = {}
        self.emails = {USER: EMAIL, MEMBER: "member.one@example.com", MEMBER2: "member.two@example.com"}
        self.auth = SimpleNamespace(admin=SimpleNamespace(delete_user=self._delete_user, get_user_by_id=self._get_user))
        self.storage = SimpleNamespace(from_=lambda name: Bucket(self, name))

    def maybe_fail(self, key):
        exc = self.failures.get(key)
        if exc is not None:
            raise exc

    def rpc(self, name, params=None):
        return SimpleNamespace(execute=lambda: self._rpc(name, params or {}))

    def _rpc(self, name, params):
        self.calls.append(("rpc", name, params))
        self.maybe_fail(name)
        if name == "claim_due_account_deletions":
            return SimpleNamespace(data=[self.jobs.pop(0)] if self.jobs else [])
        if name in self.results:
            return SimpleNamespace(data=self.results[name])
        return SimpleNamespace(data=DEFAULT_RESULTS.get(name))

    def _delete_user(self, uid, should_soft_delete=False):
        self.calls.append(("auth.delete", uid, should_soft_delete))
        self.maybe_fail("auth.delete")

    def _get_user(self, uid):
        self.calls.append(("auth.get", uid))
        self.maybe_fail("auth.get")
        email = self.emails.get(uid)
        if email is None:
            raise AuthError("User not found", 404, "user_not_found")
        return SimpleNamespace(user=SimpleNamespace(email=email))

    def names(self):
        out = []
        for call in self.calls:
            if call[0] == "rpc":
                out.append(call[1])
            elif call[0] == "storage.list":
                continue
            else:
                out.append(call[0])
        return out

    def rpc_params(self, name):
        return [c[2] for c in self.calls if c[0] == "rpc" and c[1] == name]


DEFAULT_RESULTS = {
    "get_account_deletion_queue_summary": {"due": 3, "in_progress": 1, "failed": 2, "overdue": 1},
    "list_account_deletion_notices_due": [],
    "list_account_deletion_alerts_due": [],
    "prepare_account_purge": {"prepared": True, "deferred": False, "deleted_households": 0},
    "list_account_purge_storage": [],
    "purge_expired_account_deletion_inquiries": 0,
}


def job(stage="none", attempts=1, locale="en", user_id=USER):
    return {"request_id": REQ, "user_id": user_id, "stage": stage, "attempts": attempts, "locale": locale}


@pytest.fixture()
def enabled(monkeypatch):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")


@pytest.fixture()
def emails_off(monkeypatch):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    monkeypatch.delenv("ACCOUNT_DELETION_EMAILS_ENABLED", raising=False)


@pytest.fixture()
def mailer(monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.delenv("SMTP_HOST", raising=False)
    send = AsyncMock(return_value="resend")
    monkeypatch.setattr(mail_service, "send_email", send)
    return send


@pytest.fixture()
def no_provider(monkeypatch):
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    monkeypatch.delenv("SMTP_HOST", raising=False)
    send = AsyncMock(side_effect=AssertionError("must not send without a provider"))
    monkeypatch.setattr(mail_service, "send_email", send)
    return send


def _recipients(send: AsyncMock) -> list:
    return [c.kwargs.get("to_override") for c in send.await_args_list]


# ── The safety switch ──────────────────────────────────────────────────────


@pytest.mark.parametrize("value", [None, "", "0", "true", "TRUE", "yes", "on", "2", "1 "[:0]])
def test_disabled_makes_no_destructive_call_of_any_kind(monkeypatch, caplog, mailer, value):
    if value is None:
        monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    else:
        monkeypatch.setenv(worker.ENABLE_ENV, value)

    # Everything destructive would fail loudly if it were reached.
    client = FakeClient(jobs=[job()])
    boom = AssertionError("a destructive call was made while disabled")
    for name in DESTRUCTIVE_RPCS | {"list_account_purge_storage", "list_account_deletion_notices_due",
                                    "list_account_deletion_alerts_due", "auth.delete", "auth.get", "storage.remove"}:
        client.failures[name] = boom

    with caplog.at_level("INFO"):
        assert worker.run_once(client) == 0

    # Exactly one call was made, and it is the read-only summary.
    assert client.calls == [("rpc", "get_account_deletion_queue_summary", {})]
    assert len(client.jobs) == 1, "the due job must still be unclaimed"
    mailer.assert_not_awaited()
    assert "due=3" in caplog.text
    assert "disabled" in caplog.text.lower()


def test_only_the_exact_value_1_enables(monkeypatch):
    monkeypatch.setenv(worker.ENABLE_ENV, "1")
    assert worker.purge_enabled() is True
    for value in ("0", "true", "01", "yes", ""):
        monkeypatch.setenv(worker.ENABLE_ENV, value)
        assert worker.purge_enabled() is False


def test_disabled_summary_failure_is_a_failed_run_and_still_touches_nothing(monkeypatch, mailer):
    monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    client = FakeClient(jobs=[job()])
    client.failures["get_account_deletion_queue_summary"] = ApiError("no such function")
    assert worker.run_once(client) == 1
    assert client.calls == [("rpc", "get_account_deletion_queue_summary", {})]


# ── The job ────────────────────────────────────────────────────────────────


def test_happy_path_runs_every_step_in_order(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [
        {"bucket": "receipts", "path": f"{HH}/a.jpg", "is_prefix": False},
    ]
    assert worker.run_once(client) == 0
    names = client.names()
    purge = names[names.index("claim_due_account_deletions"):]
    assert purge[:9] == [
        "claim_due_account_deletions",
        "prepare_account_purge",
        "list_account_purge_storage",
        "storage.remove",
        "mark_account_purge_storage_done",
        "auth.get",
        "auth.delete",
        "mark_account_deletion_notice_sent",
        "complete_account_purge",
    ]
    assert client.rpc_params("prepare_account_purge") == [{"p_request_id": REQ}]
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]
    assert ("auth.delete", USER, False) in client.calls, "a hard delete, never a soft one"
    assert client.rpc_params("record_account_deletion_worker_run")[0]["p_completed"] == 1
    assert client.rpc_params("record_account_deletion_worker_run")[0]["p_failed"] == 0
    assert client.rpc_params("record_account_purge_failure") == []


def test_claim_takes_one_job_at_a_time_up_to_the_run_limit(enabled, mailer, monkeypatch):
    monkeypatch.setattr(worker, "MAX_JOBS_PER_RUN", 2)
    client = FakeClient(jobs=[job(), job(), job()])
    assert worker.run_once(client) == 0
    assert client.rpc_params("claim_due_account_deletions") == [
        {"p_limit": 1, "p_lease_minutes": worker.LEASE_MINUTES},
        {"p_limit": 1, "p_lease_minutes": worker.LEASE_MINUTES},
    ]
    assert len(client.jobs) == 1


def test_auth_404_counts_as_already_deleted(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["auth.delete"] = AuthError("User not found", 404, "user_not_found")
    assert worker.run_once(client) == 0
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]
    assert client.rpc_params("record_account_purge_failure") == []


def test_auth_other_error_is_a_failure_and_never_completes(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["auth.delete"] = AuthError("Database error deleting user", 500)
    assert worker.run_once(client) == 1
    assert client.rpc_params("complete_account_purge") == []
    assert client.rpc_params("record_account_purge_failure") == [{"p_request_id": REQ, "p_error_code": "auth_failed"}]


@pytest.mark.parametrize(
    "failing, code, must_not_run",
    [
        ("prepare_account_purge", "prepare_failed",
         ["list_account_purge_storage", "mark_account_purge_storage_done", "auth.delete", "complete_account_purge"]),
        ("list_account_purge_storage", "storage_failed",
         ["mark_account_purge_storage_done", "auth.delete", "complete_account_purge"]),
        ("storage.remove", "storage_failed",
         ["mark_account_purge_storage_done", "auth.delete", "complete_account_purge"]),
        ("mark_account_purge_storage_done", "storage_failed", ["auth.delete", "complete_account_purge"]),
        ("auth.delete", "auth_failed", ["complete_account_purge"]),
        ("complete_account_purge", "complete_failed", []),
    ],
)
def test_failure_at_each_stage_stops_the_job_and_records_a_code(enabled, mailer, failing, code, must_not_run):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/a.jpg", "is_prefix": False}]
    client.failures[failing] = ApiError("boom")
    assert worker.run_once(client) == 1
    names = client.names()
    for later in must_not_run:
        assert later not in names, later
    assert client.rpc_params("record_account_purge_failure") == [{"p_request_id": REQ, "p_error_code": code}]
    assert client.rpc_params("record_account_deletion_worker_run")[0]["p_failed"] == 1


def test_a_database_hint_becomes_the_error_code(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["prepare_account_purge"] = ApiError(
        "A surviving pool balance or budget would have moved; nothing was purged",
        hint="purge_ledger_invariant", code="23514")
    assert worker.run_once(client) == 1
    assert client.rpc_params("record_account_purge_failure")[0]["p_error_code"] == "purge_ledger_invariant"


def test_a_free_text_hint_is_not_used_as_a_code(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["prepare_account_purge"] = ApiError("nope", hint="Perhaps you meant to reference something else.")
    assert worker.run_once(client) == 1
    assert client.rpc_params("record_account_purge_failure")[0]["p_error_code"] == "prepare_failed"


def test_retry_after_prepare_resumes_with_the_storage_queue(enabled, mailer):
    """A retried job re-runs every step; the SQL makes each one a no-op when it is already done."""
    client = FakeClient(jobs=[job(stage="db_prepared", attempts=2)])
    client.results["prepare_account_purge"] = {
        "prepared": True, "deferred": False, "already_prepared": True, "stage": "db_prepared"}
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/a.jpg", "is_prefix": False}]
    assert worker.run_once(client) == 0
    assert ("storage.remove", "receipts", [f"{HH}/a.jpg"]) in client.calls
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


def test_retry_after_auth_delete_completes_without_a_second_email(enabled, mailer):
    client = FakeClient(jobs=[job(stage="storage_done", attempts=3)])
    client.results["prepare_account_purge"] = {
        "prepared": True, "deferred": False, "already_prepared": True, "stage": "storage_done"}
    client.emails.pop(USER)  # The Auth delete already happened on the earlier attempt.
    client.failures["auth.delete"] = AuthError("User not found", 404, "user_not_found")
    assert worker.run_once(client) == 0
    mailer.assert_not_awaited()
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


def test_deferred_is_not_a_failure_and_purges_nothing(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["prepare_account_purge"] = {
        "prepared": False, "deferred": True, "scheduled_for": "2026-12-01T00:00:00+00:00", "households": [HH]}
    assert worker.run_once(client) == 0
    names = client.names()
    for later in ("list_account_purge_storage", "storage.remove", "auth.delete", "complete_account_purge"):
        assert later not in names, later
    assert client.rpc_params("record_account_purge_failure") == []
    run = client.rpc_params("record_account_deletion_worker_run")[0]
    assert (run["p_claimed"], run["p_completed"], run["p_failed"]) == (1, 0, 0)


def test_a_user_deleted_out_of_band_still_completes(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["prepare_account_purge"] = {
        "prepared": True, "deferred": False, "user_missing": True, "deleted_households": 0}
    client.emails.pop(USER)
    client.failures["auth.delete"] = AuthError("User not found", 404, "user_not_found")
    assert worker.run_once(client) == 0
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


def test_one_failed_job_does_not_stop_the_next(enabled, mailer):
    other = "66666666-6666-4666-8666-666666666666"
    client = FakeClient(jobs=[job(), {**job(), "request_id": other}])
    original = client._rpc

    def fail_first_prepare(name, params):
        if name == "prepare_account_purge" and params["p_request_id"] == REQ:
            client.calls.append(("rpc", name, params))
            raise ApiError("boom")
        return original(name, params)

    client._rpc = fail_first_prepare
    assert worker.run_once(client) == 1
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": other}]
    run = client.rpc_params("record_account_deletion_worker_run")[0]
    assert (run["p_claimed"], run["p_completed"], run["p_failed"]) == (2, 1, 1)


def test_a_failure_that_cannot_be_recorded_still_counts(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["prepare_account_purge"] = ApiError("boom")
    client.failures["record_account_purge_failure"] = ApiError("also boom")
    assert worker.run_once(client) == 1
    assert client.rpc_params("record_account_deletion_worker_run")[0]["p_failed"] == 1


# ── Storage ────────────────────────────────────────────────────────────────


def test_exact_paths_are_removed_in_batches(enabled, mailer, monkeypatch):
    monkeypatch.setattr(worker, "STORAGE_BATCH_SIZE", 2)
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [
        {"bucket": "receipts", "path": f"{HH}/{n}.jpg", "is_prefix": False} for n in range(5)
    ]
    assert worker.run_once(client) == 0
    removed = [c[2] for c in client.calls if c[0] == "storage.remove"]
    assert [len(batch) for batch in removed] == [2, 2, 1]
    assert sorted(p for batch in removed for p in batch) == [f"{HH}/{n}.jpg" for n in range(5)]


def test_a_household_folder_is_paged_through_including_subfolders(enabled, mailer, monkeypatch):
    monkeypatch.setattr(worker, "STORAGE_PAGE_SIZE", 2)
    monkeypatch.setattr(worker, "STORAGE_BATCH_SIZE", 3)
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/", "is_prefix": True}]
    client.folders[HH] = [
        {"name": "a.jpg", "id": "1"},
        {"name": "b.jpg", "id": "2"},
        {"name": "sub", "id": None},
        {"name": "c.jpg", "id": "3"},
        {"name": "d.jpg", "id": "4"},
    ]
    client.folders[f"{HH}/sub"] = [{"name": "e.jpg", "id": "5"}]
    assert worker.run_once(client) == 0

    pages = [c for c in client.calls if c[0] == "storage.list" and c[2] == HH]
    assert [c[3]["offset"] for c in pages] == [0, 2, 4]
    removed = [p for c in client.calls if c[0] == "storage.remove" for p in c[2]]
    assert sorted(removed) == sorted([f"{HH}/a.jpg", f"{HH}/b.jpg", f"{HH}/c.jpg", f"{HH}/d.jpg", f"{HH}/sub/e.jpg"])
    assert all(len(c[2]) <= 3 for c in client.calls if c[0] == "storage.remove")
    # Listing first keeps the offsets valid: nothing is removed between two pages.
    last_list = max(i for i, c in enumerate(client.calls) if c[0] == "storage.list")
    first_remove = min(i for i, c in enumerate(client.calls) if c[0] == "storage.remove")
    assert last_list < first_remove


def test_an_empty_prefix_never_means_the_whole_bucket(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": "/", "is_prefix": True}]
    assert worker.run_once(client) == 1
    assert [c for c in client.calls if c[0] in ("storage.list", "storage.remove")] == []
    assert "auth.delete" not in client.names()
    assert client.rpc_params("record_account_purge_failure")[0]["p_error_code"] == "storage_failed"


def test_an_empty_or_already_removed_folder_is_fine(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/", "is_prefix": True}]
    assert worker.run_once(client) == 0
    assert [c for c in client.calls if c[0] == "storage.remove"] == []
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


# ── What reaches the logs ──────────────────────────────────────────────────


@pytest.mark.parametrize(
    "failing",
    ["prepare_account_purge", "list_account_purge_storage", "storage.remove", "mark_account_purge_storage_done",
     "auth.get", "auth.delete", "complete_account_purge", "list_account_deletion_notices_due",
     "list_account_deletion_alerts_due", "record_account_deletion_worker_run", "purge_expired_account_deletion_inquiries"],
)
def test_raw_errors_emails_and_tokens_are_never_logged(enabled, mailer, caplog, failing):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/a.jpg", "is_prefix": False}]
    client.failures[failing] = ApiError(f"insert failed for {EMAIL} using {TOKEN} on user {USER}")
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ] if failing != "list_account_deletion_notices_due" else []
    with caplog.at_level("DEBUG"):
        worker.run_once(client)
    assert EMAIL not in caplog.text
    assert TOKEN not in caplog.text
    assert USER not in caplog.text
    assert "insert failed" not in caplog.text


def test_mail_failure_text_is_never_logged(enabled, monkeypatch, caplog):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.setattr(mail_service, "send_email", AsyncMock(side_effect=RuntimeError(f"refused {EMAIL} {TOKEN}")))
    client = FakeClient(jobs=[job()])
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    with caplog.at_level("DEBUG"):
        worker.run_once(client)
    assert EMAIL not in caplog.text
    assert TOKEN not in caplog.text


def test_main_silences_the_http_client_log_that_would_print_user_ids(monkeypatch):
    """httpx logs every URL at INFO, and the Auth Admin URL contains the user id."""
    import logging

    monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    monkeypatch.setattr(worker, "get_client", lambda: FakeClient())
    assert worker.main() == 0
    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING
    assert logging.getLogger("httpcore").getEffectiveLevel() >= logging.WARNING


def test_main_reports_an_unusable_client_as_a_failed_run_without_its_text(monkeypatch, caplog):
    monkeypatch.setattr(worker, "get_client", lambda: (_ for _ in ()).throw(RuntimeError(TOKEN)))
    with caplog.at_level("DEBUG"):
        assert worker.main() == 1
    assert TOKEN not in caplog.text


# ── Mail ───────────────────────────────────────────────────────────────────


def test_mail_failure_does_not_block_the_purge(enabled, monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.setattr(mail_service, "send_email", AsyncMock(side_effect=mail_service.MailDeliveryError("down")))
    client = FakeClient(jobs=[job()])
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    assert worker.run_once(client) == 0
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


def test_missing_provider_is_logged_and_does_not_block_the_purge(enabled, no_provider, caplog):
    client = FakeClient(jobs=[job()])
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    with caplog.at_level("INFO"):
        assert worker.run_once(client) == 0
    no_provider.assert_not_awaited()
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]
    assert client.rpc_params("mark_account_deletion_notice_sent") == [], "not sent, so not marked"
    assert "provider" in caplog.text.lower()


def test_holder_notice_goes_to_their_own_address_and_is_marked_once(enabled, mailer):
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "ur", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    assert worker.run_once(client) == 0
    assert _recipients(mailer) == [EMAIL]
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "holder_t7"}]


def test_member_notice_reaches_each_member_once_across_households(enabled, mailer):
    rows = [
        {"request_id": REQ, "user_id": MEMBER, "notice": "member_marked", "locale": "ar", "scheduled_for": "2026-12-01T00:00:00+00:00"},
        {"request_id": REQ, "user_id": MEMBER2, "notice": "member_marked", "locale": "ar", "scheduled_for": "2026-12-01T00:00:00+00:00"},
        # The same member again, through a second household of the same request.
        {"request_id": REQ, "user_id": MEMBER, "notice": "member_marked", "locale": "ar", "scheduled_for": "2026-12-01T00:00:00+00:00"},
    ]
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = rows
    assert worker.run_once(client) == 0
    assert sorted(_recipients(mailer)) == ["member.one@example.com", "member.two@example.com"]
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "member_marked"}]


def test_one_bad_address_does_not_resend_to_everyone_next_hour(enabled, monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")

    async def fail_one(message, to_override=None):
        if to_override == "member.two@example.com":
            raise mail_service.MailDeliveryError("bounced")
        return "resend"

    monkeypatch.setattr(mail_service, "send_email", fail_one)
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": MEMBER, "notice": "member_t7", "locale": "ar", "scheduled_for": "2026-12-01T00:00:00+00:00"},
        {"request_id": REQ, "user_id": MEMBER2, "notice": "member_t7", "locale": "ar", "scheduled_for": "2026-12-01T00:00:00+00:00"},
    ]
    assert worker.run_once(client) == 0
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "member_t7"}]


def test_a_notice_nobody_received_is_retried_next_run(enabled, monkeypatch):
    monkeypatch.setenv("RESEND_API_KEY", "re_test_dummy_key")
    monkeypatch.setattr(mail_service, "send_email", AsyncMock(side_effect=mail_service.MailDeliveryError("down")))
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t1", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    assert worker.run_once(client) == 0
    assert client.rpc_params("mark_account_deletion_notice_sent") == []


def test_a_user_with_no_address_does_not_retry_forever(enabled, mailer):
    client = FakeClient()
    client.emails.pop(USER)
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    assert worker.run_once(client) == 0
    mailer.assert_not_awaited()
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "holder_t7"}]


def test_completion_email_waits_for_the_auth_delete(enabled, mailer):
    """The list offers holder_completion once prepared, but saying 'deleted' early would be false."""
    client = FakeClient(jobs=[job()])
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_completion", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    client.failures["auth.delete"] = AuthError("Database error deleting user", 500)
    assert worker.run_once(client) == 1
    mailer.assert_not_awaited()
    assert client.rpc_params("mark_account_deletion_notice_sent") == []


def test_completion_email_uses_the_address_read_before_the_delete(enabled, mailer):
    client = FakeClient(jobs=[job(locale="ar")])
    assert worker.run_once(client) == 0
    assert _recipients(mailer) == [EMAIL]
    message = mailer.await_args.args[0]
    assert "قوام المال" in message.subject
    names = client.names()
    assert names.index("auth.get") < names.index("auth.delete")
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "holder_completion"}]


# ── The email switch ───────────────────────────────────────────────────────


def _due_notices():
    date = "2026-12-01T00:00:00+00:00"
    return [
        {"request_id": REQ, "user_id": USER, "notice": name, "locale": "en", "scheduled_for": date}
        for name in ("holder_t7", "holder_t1")
    ] + [
        {"request_id": REQ, "user_id": MEMBER, "notice": name, "locale": "en", "scheduled_for": date}
        for name in ("member_marked", "member_t7")
    ]


def test_only_the_exact_value_1_turns_emails_on(monkeypatch):
    monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")
    assert worker.emails_enabled() is True
    for value in ("", "0", "true", "TRUE", "yes", "on", "2", " 1"):
        monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", value)
        assert worker.emails_enabled() is False, value
    monkeypatch.delenv("ACCOUNT_DELETION_EMAILS_ENABLED")
    assert worker.emails_enabled() is False


def test_the_purge_switch_does_not_turn_emails_on(emails_off, mailer):
    assert worker.purge_enabled() is True
    assert worker.emails_enabled() is False


def test_off_no_notice_is_sent_or_marked_or_looked_up(emails_off, mailer, caplog):
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = _due_notices()
    with caplog.at_level("INFO"):
        assert worker.run_once(client) == 0
    mailer.assert_not_awaited()
    assert client.rpc_params("mark_account_deletion_notice_sent") == []
    assert "auth.get" not in client.names()
    assert "4" in caplog.text and worker.EMAILS_ENV in caplog.text
    assert USER not in caplog.text and MEMBER not in caplog.text


def test_off_the_completion_email_is_skipped_and_the_job_still_completes(emails_off, mailer):
    client = FakeClient(jobs=[job()])
    assert worker.run_once(client) == 0
    mailer.assert_not_awaited()
    names = client.names()
    assert "auth.get" not in names, "no address is read when nothing will be sent"
    assert names.index("auth.delete") < names.index("complete_account_purge")
    assert client.rpc_params("mark_account_deletion_notice_sent") == []


def test_off_developer_alerts_still_go_out_and_are_marked(emails_off, mailer):
    client = FakeClient()
    client.results["list_account_deletion_alerts_due"] = [{"request_id": REQ, "alert": "ops_failed"}]
    client.results["list_account_deletion_notices_due"] = _due_notices()
    assert worker.run_once(client) == 0
    assert mailer.await_count == 1
    assert _recipients(mailer) == [None], "the developer, never a user"
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "ops_failed"}]


def test_on_with_the_purge_off_notices_go_and_no_job_is_touched(monkeypatch, mailer):
    monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")
    client = FakeClient(jobs=[job()])
    boom = AssertionError("a destructive call was made while the purge is off")
    for name in DESTRUCTIVE_RPCS | {"list_account_purge_storage", "auth.delete", "storage.remove"}:
        client.failures[name] = boom
    client.results["list_account_deletion_notices_due"] = _due_notices()[:1]
    assert worker.run_once(client) == 0
    assert _recipients(mailer) == [EMAIL]
    assert client.rpc_params("mark_account_deletion_notice_sent") == [{"p_request_id": REQ, "p_notice": "holder_t7"}]
    assert len(client.jobs) == 1


def test_on_with_the_purge_off_and_no_provider_changes_nothing(monkeypatch, no_provider):
    monkeypatch.delenv(worker.ENABLE_ENV, raising=False)
    monkeypatch.setenv("ACCOUNT_DELETION_EMAILS_ENABLED", "1")
    client = FakeClient()
    client.results["list_account_deletion_notices_due"] = _due_notices()
    assert worker.run_once(client) == 0
    assert client.rpc_params("mark_account_deletion_notice_sent") == []


# ── Alerts, retention, heartbeat ───────────────────────────────────────────


def test_failed_and_overdue_jobs_alert_the_developer_without_user_data(enabled, mailer):
    other = "77777777-7777-4777-8777-777777777777"
    client = FakeClient()
    client.results["list_account_deletion_alerts_due"] = [
        {"request_id": REQ, "alert": "ops_failed"},
        {"request_id": other, "alert": "ops_overdue"},
    ]
    assert worker.run_once(client) == 0
    assert mailer.await_count == 1
    assert _recipients(mailer) == [None], "goes to CONTACT_RECIPIENT_EMAIL, never a user"
    message = mailer.await_args.args[0]
    assert REQ in message.body and other in message.body
    assert USER not in message.body and EMAIL not in message.body
    assert client.rpc_params("mark_account_deletion_notice_sent") == [
        {"p_request_id": REQ, "p_notice": "ops_failed"},
        {"p_request_id": other, "p_notice": "ops_overdue"},
    ]


def test_an_alert_that_was_not_sent_is_not_marked(enabled, no_provider, caplog):
    client = FakeClient()
    client.results["list_account_deletion_alerts_due"] = [{"request_id": REQ, "alert": "ops_failed"}]
    with caplog.at_level("INFO"):
        assert worker.run_once(client) == 0
    assert client.rpc_params("mark_account_deletion_notice_sent") == []
    assert "ops_failed" in caplog.text or "alert" in caplog.text.lower()


def test_alerts_run_after_the_jobs_so_a_new_failure_is_seen(enabled, mailer):
    client = FakeClient(jobs=[job()])
    names_before = client.names()
    assert names_before == []
    assert worker.run_once(client) == 0
    names = client.names()
    assert names.index("complete_account_purge") < names.index("list_account_deletion_alerts_due")


def test_inquiry_retention_runs_when_enabled_with_90_days(enabled, mailer):
    client = FakeClient()
    assert worker.run_once(client) == 0
    assert client.rpc_params("purge_expired_account_deletion_inquiries") == [{"p_days": 90}]


def test_heartbeat_carries_counts_and_a_start_time(enabled, mailer):
    client = FakeClient(jobs=[job()])
    assert worker.run_once(client) == 0
    run = client.rpc_params("record_account_deletion_worker_run")[0]
    assert set(run) == {"p_started_at", "p_claimed", "p_completed", "p_failed"}
    assert (run["p_claimed"], run["p_completed"], run["p_failed"]) == (1, 1, 0)
    assert datetime.fromisoformat(run["p_started_at"]) <= datetime.now(timezone.utc)


@pytest.mark.parametrize(
    "failing",
    ["claim_due_account_deletions", "record_account_deletion_worker_run", "purge_expired_account_deletion_inquiries"],
)
def test_run_level_database_failures_exit_non_zero(enabled, mailer, failing):
    client = FakeClient()
    client.failures[failing] = ApiError("boom")
    assert worker.run_once(client) == 1


def test_notice_listing_failure_is_logged_and_the_purge_still_runs(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.failures["list_account_deletion_notices_due"] = ApiError("boom")
    assert worker.run_once(client) == 0
    assert client.rpc_params("complete_account_purge") == [{"p_request_id": REQ}]


# ── Notice content ─────────────────────────────────────────────────────────

_ALL_NOTICES = ("holder_t7", "holder_t1", "holder_completion", "member_marked", "member_t7")
_SCHEDULED = "2026-12-01T22:30:00+00:00"  # 2 December in Riyadh


@pytest.mark.parametrize("notice", _ALL_NOTICES)
@pytest.mark.parametrize("locale", ["ar", "en", "ur"])
def test_every_notice_exists_in_every_language_with_the_brand(notice, locale):
    message = notices.compose(notice, locale, _SCHEDULED)
    brand = "Qawam Money" if locale == "en" else "قوام المال"
    assert brand in message.subject
    assert brand in message.body
    assert "\n" not in message.subject
    assert "Wafeer" not in message.subject + message.body
    assert message.body.strip()
    assert "{" not in message.body and "{" not in message.subject


@pytest.mark.parametrize("notice", ["holder_t7", "holder_t1", "member_marked", "member_t7"])
@pytest.mark.parametrize("locale", ["ar", "en", "ur"])
def test_notices_with_a_date_state_it_on_the_riyadh_calendar(notice, locale):
    assert "2026-12-02" in notices.compose(notice, locale, _SCHEDULED).body


@pytest.mark.parametrize("notice", ["holder_t7", "holder_t1"])
@pytest.mark.parametrize(
    "locale, phrase",
    [("en", "Signing in does not cancel"), ("ar", "تسجيل الدخول وحده لا يلغي"), ("ur", "صرف سائن ان کرنے سے")],
)
def test_holder_reminders_say_signing_in_does_not_cancel(notice, locale, phrase):
    assert phrase in notices.compose(notice, locale, _SCHEDULED).body


@pytest.mark.parametrize("notice", ["member_marked", "member_t7"])
@pytest.mark.parametrize(
    "locale, phrase",
    [("en", "Your own account stays"), ("ar", "حسابك أنت يبقى"), ("ur", "آپ کا اپنا اکاؤنٹ برقرار")],
)
def test_member_notices_say_their_account_stays(notice, locale, phrase):
    assert phrase in notices.compose(notice, locale, _SCHEDULED).body


@pytest.mark.parametrize("locale", ["fr", "", None])
def test_an_unknown_locale_falls_back_to_arabic(locale):
    assert notices.compose("holder_t7", locale, _SCHEDULED) == notices.compose("holder_t7", "ar", _SCHEDULED)


def test_an_unknown_notice_is_refused():
    with pytest.raises(ValueError):
        notices.compose("nonsense", "en", _SCHEDULED)


def test_no_notice_carries_a_split_or_a_spouse_term():
    for notice in _ALL_NOTICES:
        for locale in ("ar", "en", "ur"):
            text = notices.compose(notice, locale, _SCHEDULED).body
            assert "50/50" not in text


# ── The contract with the database and the API ─────────────────────────────


def _declared_functions() -> dict:
    """{function name: set of parameter names} from the account deletion migrations."""
    found: dict = {}
    for path in sorted(MIGRATIONS.glob("20261105*_account_deletion_*.sql")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"CREATE OR REPLACE FUNCTION public\.(\w+)\((.*?)\)\s*RETURNS", text, re.S):
            params = set(re.findall(r"\b(p_\w+)\b", match.group(2)))
            found[match.group(1)] = params
    return found


def test_rpc_calls_match_the_migrations(enabled, mailer):
    client = FakeClient(jobs=[job()])
    client.results["list_account_purge_storage"] = [{"bucket": "receipts", "path": f"{HH}/a.jpg", "is_prefix": False}]
    client.results["list_account_deletion_notices_due"] = [
        {"request_id": REQ, "user_id": USER, "notice": "holder_t7", "locale": "en", "scheduled_for": "2026-12-01T00:00:00+00:00"}
    ]
    client.results["list_account_deletion_alerts_due"] = [{"request_id": REQ, "alert": "ops_failed"}]
    assert worker.run_once(client) == 0
    client.failures["prepare_account_purge"] = ApiError("boom")
    client.jobs = [job()]
    worker.run_once(client)

    declared = _declared_functions()
    used = {(c[1], frozenset(c[2])) for c in client.calls if c[0] == "rpc"}
    assert {name for name, _ in used} >= DESTRUCTIVE_RPCS | {"list_account_deletion_notices_due"}
    for name, params in used:
        assert name in declared, f"{name} is not in the migrations"
        assert set(params) <= declared[name], f"{name}: {set(params)} vs {declared[name]}"


def test_notice_names_match_the_database():
    text = (MIGRATIONS / "20261105000400_account_deletion_worker_support.sql").read_text(encoding="utf-8")
    for notice in _ALL_NOTICES:
        assert f"'{notice}'" in text
    assert set(notices.NOTICES) == set(_ALL_NOTICES)


def test_the_web_api_gains_no_purge_route():
    from fastapi.testclient import TestClient
    from main import app

    paths = [getattr(r, "path", "") for r in app.routes]
    for path in paths:
        low = path.lower()
        assert "purge" not in low, path
        assert "worker" not in low, path
    body = TestClient(app).get("/health").json()
    assert set(body) == {"status", "version", "timestamp"}


def test_the_api_process_does_not_import_the_worker():
    source = (pathlib.Path(worker.__file__).parent / "main.py").read_text(encoding="utf-8")
    assert "account_deletion_worker" not in source
