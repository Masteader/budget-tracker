"""
Finishes account deletions that have come due. Runs once and exits: python account_deletion_worker.py

Meant for a Railway Cron service using this image (docs/runbooks/account-deletion-purge.md). The
API process never imports it and has no route to it.

Two switches, each only on with the exact value 1, each independent of the other:

ACCOUNT_DELETION_PURGE_ENABLED: without it the worker reads one summary and logs the counts: no
claim, no storage or Auth call, no developer alert.

ACCOUNT_DELETION_EMAILS_ENABLED: without it no account holder or household member gets an email
(T-7, T-1, completion, member marked, member T-7), and no notice is marked sent, so reminders still
in their window go out when it comes on. A completion email is skipped: the job still completes,
and that email is never sent, because the address goes with the account. Developer alerts do not
depend on this switch.

With both off a run writes nothing.

One job, each step safe to repeat: claim, prepare_account_purge (all database work), remove the
queued storage objects, delete the user through the Auth Admin API (404 counts as done), then
complete_account_purge, which checks the user is gone. A failure records a code and the database
schedules the retry; after 5 attempts the job is 'failed' and the developer gets an email.

A missing or failing mail provider never blocks a purge and does not fail the run. The exit code is
non-zero when a job or a run-level database call failed, so Railway shows the run as failed.

Logs carry request ids and error codes only. Raw errors can quote emails, tokens and user ids.
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from dotenv import load_dotenv

import account_deletion_notices as notices
import mail_service
from postgrest_compat import db_error_fields
from supabase_client import get_client

logger = logging.getLogger("account_deletion_worker")

ENABLE_ENV = "ACCOUNT_DELETION_PURGE_ENABLED"
EMAILS_ENV = "ACCOUNT_DELETION_EMAILS_ENABLED"
MAX_JOBS_PER_RUN = 20
LEASE_MINUTES = 30
STORAGE_PAGE_SIZE = 100
STORAGE_BATCH_SIZE = 100
INQUIRY_RETENTION_DAYS = 90

_ERROR_CODE_RE = re.compile(r"^[a-z0-9_]{1,64}$")


def purge_enabled() -> bool:
    return os.environ.get(ENABLE_ENV) == "1"


def emails_enabled() -> bool:
    return os.environ.get(EMAILS_ENV) == "1"


def _rpc(client: Any, name: str, params: Optional[Dict[str, Any]] = None) -> Any:
    return client.rpc(name, params or {}).execute().data


def _error_code(exc: BaseException, default: str) -> str:
    """The database's machine-readable hint when it has one, else the failing step."""
    hint = db_error_fields(exc)["hint"]
    return hint if _ERROR_CODE_RE.match(hint) else default


def _is_not_found(exc: BaseException) -> bool:
    return getattr(exc, "status", None) == 404 or getattr(exc, "code", None) == "user_not_found"


def _lookup_email(client: Any, user_id: str) -> Optional[str]:
    """The address on the Auth user, None when the user is gone. Other errors propagate."""
    try:
        response = client.auth.admin.get_user_by_id(user_id)
    except Exception as exc:  # noqa: BLE001 - classified here, re-raised unless it means "gone"
        if _is_not_found(exc):
            return None
        raise
    return getattr(getattr(response, "user", None), "email", None) or None


def _send(message: mail_service.OutboundEmail, to_address: Optional[str] = None) -> bool:
    """True when the provider accepted the message. Failures are logged by type, never by text."""
    try:
        if to_address is None:
            asyncio.run(mail_service.send_email(message))
        else:
            asyncio.run(mail_service.send_email(message, to_override=to_address))
        return True
    except Exception as exc:  # noqa: BLE001 - mail never blocks a purge
        logger.warning("Account deletion email not delivered (%s).", type(exc).__name__)
        return False


# ── Storage ──────────────────────────────────────────────────────────────────


def _list_folder_files(bucket: Any, folder: str) -> List[str]:
    """Every file under folder. Lists before anything is removed, so the offsets stay valid."""
    files: List[str] = []
    subfolders: List[str] = []
    offset = 0
    while True:
        entries = bucket.list(folder, {
            "limit": STORAGE_PAGE_SIZE,
            "offset": offset,
            "sortBy": {"column": "name", "order": "asc"},
        }) or []
        for entry in entries:
            path = f"{folder}/{entry['name']}"
            # Storage reports a folder as an entry without an id.
            if entry.get("id") is None:
                subfolders.append(path)
            else:
                files.append(path)
        if len(entries) < STORAGE_PAGE_SIZE:
            break
        offset += STORAGE_PAGE_SIZE
    for subfolder in subfolders:
        files.extend(_list_folder_files(bucket, subfolder))
    return files


def _remove_storage(client: Any, items: List[Dict[str, Any]]) -> None:
    by_bucket: Dict[str, List[str]] = {}
    for item in items:
        name = item["bucket"]
        paths = by_bucket.setdefault(name, [])
        if item.get("is_prefix"):
            folder = str(item["path"]).strip("/")
            # An empty prefix would mean the whole bucket.
            if not folder:
                raise ValueError("refusing an empty storage prefix")
            paths.extend(_list_folder_files(client.storage.from_(name), folder))
        else:
            paths.append(item["path"])
    for name, paths in by_bucket.items():
        bucket = client.storage.from_(name)
        for start in range(0, len(paths), STORAGE_BATCH_SIZE):
            bucket.remove(paths[start:start + STORAGE_BATCH_SIZE])


# ── One job ──────────────────────────────────────────────────────────────────


def _completion_address(client: Any, request_id: str, user_id: str) -> Optional[str]:
    """The address for the completion email, read before the delete. None means no email."""
    if not emails_enabled():
        return None
    try:
        return _lookup_email(client, user_id)
    except Exception as exc:  # noqa: BLE001 - mail never blocks a purge
        logger.warning("Account deletion job %s: address lookup failed (%s).", request_id, type(exc).__name__)
        return None


def _delete_auth_user(client: Any, user_id: str) -> None:
    try:
        client.auth.admin.delete_user(user_id, should_soft_delete=False)
    except Exception as exc:  # noqa: BLE001 - classified here
        if not _is_not_found(exc):
            raise


def _run_job(client: Any, job: Dict[str, Any]) -> str:
    """'completed', 'deferred' or 'failed'."""
    request_id = job["request_id"]
    user_id = job["user_id"]
    params = {"p_request_id": request_id}
    step = "prepare_failed"
    try:
        prepared = _rpc(client, "prepare_account_purge", params) or {}
        if prepared.get("deferred"):
            logger.info("Account deletion job %s deferred: a household gets 7 days' notice.", request_id)
            return "deferred"

        step = "storage_failed"
        _remove_storage(client, _rpc(client, "list_account_purge_storage", params) or [])
        _rpc(client, "mark_account_purge_storage_done", params)

        # The address goes with the Auth user, and "your account has been deleted" must not be
        # sent before it is true. A retry after the delete finds no address and sends nothing.
        email = _completion_address(client, request_id, user_id)

        step = "auth_failed"
        _delete_auth_user(client, user_id)

        if email and mail_service.active_provider() is not None:
            if _send(notices.compose("holder_completion", job.get("locale")), email):
                _mark_notice(client, request_id, "holder_completion")

        step = "complete_failed"
        _rpc(client, "complete_account_purge", params)
    except Exception as exc:  # noqa: BLE001 - one job never stops the next
        code = _error_code(exc, step)
        logger.error("Account deletion job %s failed: %s (%s).", request_id, code, type(exc).__name__)
        try:
            _rpc(client, "record_account_purge_failure", {"p_request_id": request_id, "p_error_code": code})
        except Exception as record_exc:  # noqa: BLE001 - the lease expires and the job is retried
            logger.error("Account deletion job %s: could not record the failure (%s).", request_id, type(record_exc).__name__)
        return "failed"

    logger.info("Account deletion job %s completed.", request_id)
    return "completed"


# ── Notices and alerts ───────────────────────────────────────────────────────


def _mark_notice(client: Any, request_id: str, notice: str) -> None:
    try:
        _rpc(client, "mark_account_deletion_notice_sent", {"p_request_id": request_id, "p_notice": notice})
    except Exception as exc:  # noqa: BLE001 - the notice comes due again next run
        logger.warning("Account deletion job %s: could not mark %s (%s).", request_id, notice, type(exc).__name__)


def _send_notices(client: Any) -> None:
    try:
        rows = _rpc(client, "list_account_deletion_notices_due") or []
    except Exception as exc:  # noqa: BLE001 - mail never blocks a purge
        logger.warning("Could not list account deletion notices (%s).", type(exc).__name__)
        return

    # holder_completion is sent by the job itself, after the Auth delete.
    rows = [r for r in rows if r.get("notice") != "holder_completion"]
    if not rows:
        return
    if not emails_enabled():
        logger.info("Account deletion emails are off (%s is not 1): %d notice(s) not sent, and not marked.", EMAILS_ENV, len(rows))
        return
    if mail_service.active_provider() is None:
        logger.warning("No email provider configured: %d account deletion notice(s) not sent.", len(rows))
        return

    groups: Dict[Tuple[str, str], Dict[str, Dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault((row["request_id"], row["notice"]), {}).setdefault(row["user_id"], row)

    for (request_id, notice), recipients in groups.items():
        delivered = 0
        unreachable = 0
        for user_id, row in recipients.items():
            try:
                email = _lookup_email(client, user_id)
                if email is None:
                    unreachable += 1
                    continue
                message = notices.compose(notice, row.get("locale"), row.get("scheduled_for"))
            except Exception as exc:  # noqa: BLE001 - counts as not delivered
                logger.warning("Account deletion job %s: %s not prepared (%s).", request_id, notice, type(exc).__name__)
                continue
            if _send(message, email):
                delivered += 1
        # One address that keeps bouncing must not re-send to everyone else every hour.
        if delivered or unreachable == len(recipients):
            _mark_notice(client, request_id, notice)


def _send_alerts(client: Any) -> None:
    rows = _rpc(client, "list_account_deletion_alerts_due") or []
    if not rows:
        return
    if mail_service.active_provider() is None:
        logger.error("No email provider configured: %d account deletion alert(s) not sent.", len(rows))
        return
    lines = [f"{row['alert']}: request {row['request_id']}" for row in rows]
    message = mail_service.OutboundEmail(
        subject="[Qawam Money] Account deletion needs attention",
        body=(
            "These account deletion jobs need attention. ops_failed stopped after 5 attempts; "
            "ops_overdue is more than 48 hours past its date.\n\n"
            + "\n".join(lines)
            + "\n\nSee docs/runbooks/account-deletion-purge.md.\n"
        ),
    )
    if _send(message):
        for row in rows:
            _mark_notice(client, row["request_id"], row["alert"])


# ── One run ──────────────────────────────────────────────────────────────────


def _run_disabled(client: Any) -> int:
    try:
        summary = _rpc(client, "get_account_deletion_queue_summary") or {}
    except Exception as exc:  # noqa: BLE001 - logged by type only
        logger.error("Could not read the account deletion queue (%s).", type(exc).__name__)
        return 1
    logger.info(
        "Account deletion purge is disabled (%s is not 1); no job was touched. "
        "due=%s in_progress=%s failed=%s overdue=%s",
        ENABLE_ENV, summary.get("due"), summary.get("in_progress"), summary.get("failed"), summary.get("overdue"),
    )
    # The purge switch does not govern reminders. With emails off too, this run wrote nothing.
    if emails_enabled():
        _send_notices(client)
    return 0


def run_once(client: Any) -> int:
    """One run. Returns the process exit code."""
    if not purge_enabled():
        return _run_disabled(client)

    started_at = datetime.now(timezone.utc)
    claimed = completed = failed = 0
    run_failed = False

    _send_notices(client)

    # One at a time, so each job's lease starts when its work does.
    for _ in range(MAX_JOBS_PER_RUN):
        try:
            jobs = _rpc(client, "claim_due_account_deletions", {"p_limit": 1, "p_lease_minutes": LEASE_MINUTES}) or []
        except Exception as exc:  # noqa: BLE001 - logged by type only
            logger.error("Could not claim account deletion jobs (%s).", type(exc).__name__)
            run_failed = True
            break
        if not jobs:
            break
        claimed += 1
        outcome = _run_job(client, jobs[0])
        completed += outcome == "completed"
        failed += outcome == "failed"

    # After the jobs, so a job that failed just now is reported in this run.
    try:
        _send_alerts(client)
    except Exception as exc:  # noqa: BLE001 - logged by type only
        logger.error("Could not list account deletion alerts (%s).", type(exc).__name__)
        run_failed = True

    try:
        _rpc(client, "purge_expired_account_deletion_inquiries", {"p_days": INQUIRY_RETENTION_DAYS})
    except Exception as exc:  # noqa: BLE001 - logged by type only
        logger.error("Could not remove expired deletion inquiries (%s).", type(exc).__name__)
        run_failed = True

    try:
        _rpc(client, "record_account_deletion_worker_run", {
            "p_started_at": started_at.isoformat(),
            "p_claimed": claimed,
            "p_completed": completed,
            "p_failed": failed,
        })
    except Exception as exc:  # noqa: BLE001 - logged by type only
        logger.error("Could not record the account deletion run (%s).", type(exc).__name__)
        run_failed = True

    logger.info("Account deletion run finished: claimed=%d completed=%d failed=%d", claimed, completed, failed)
    return 1 if failed or run_failed else 0


def main() -> int:
    load_dotenv()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    # httpx logs every URL at INFO, and the Auth Admin URL contains the user id.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    try:
        client = get_client()
    except Exception as exc:  # noqa: BLE001 - logged by type only
        logger.error("Could not create the Supabase client (%s).", type(exc).__name__)
        return 1
    return run_once(client)


if __name__ == "__main__":
    sys.exit(main())
