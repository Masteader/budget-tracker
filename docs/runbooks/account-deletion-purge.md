# Account deletion purge

The worker that finishes account deletions after the 30-day grace period. It is not deployed yet, and turning it on needs explicit user approval for each step in section 6 of [the plan](../superpowers/plans/2026-11-05-account-deletion-corrected.md).

## What runs

`python account_deletion_worker.py` in `ai_service/`, once an hour, then it exits. The API process never imports it and has no route to it.

Each run, when enabled:

1. Sends the reminders that are due.
2. Claims due jobs one at a time, up to 20, and for each one:
   1. `prepare_account_purge`: all database work in one transaction.
   2. Removes the queued receipts through the Storage API.
   3. Deletes the user through the Auth Admin API. A 404 counts as done.
   4. Emails the completion notice to the address it read before the delete.
   5. `complete_account_purge`: checks the user is gone and leaves a record with no identifiers.
3. Emails the developer about jobs that failed or are more than 48 hours overdue.
4. Removes `account_deletion` inquiries older than 90 days.
5. Records a heartbeat in `account_deletion_worker_runs`.

Every step is safe to repeat. A failure records a code, and the job retries with a growing delay (1, 2, 4, then 8 hours). After 5 attempts it stays `failed` until someone looks at it.

## Setup (owner)

Create a Railway Cron service from the same image as the API:

| Setting | Value |
|---|---|
| Start command | `python account_deletion_worker.py` |
| Schedule | `17 * * * *` (UTC) |
| `SUPABASE_URL`, `SUPABASE_SECRET_KEY` | Same as the API |
| `RESEND_API_KEY` or `SMTP_*`, `MAIL_FROM`, `CONTACT_RECIPIENT_EMAIL` | Same as the API. Without a provider, no reminders or alerts go out, and purges still run. |
| `ACCOUNT_DELETION_PURGE_ENABLED` | Leave unset until approved. Only the exact value `1` enables it. |

Railway does not start a run while the previous one is active. Apply the migrations first (rule 01), because the worker calls functions they create.

## The safety switch

Without `ACCOUNT_DELETION_PURGE_ENABLED=1` the worker calls one read-only function, logs the counts and exits 0:

```
Account deletion purge is disabled (ACCOUNT_DELETION_PURGE_ENABLED is not 1); nothing was changed. due=0 in_progress=0 failed=0 overdue=0
```

Run it this way first. It proves the service, key and migrations work without changing anything. To stop purges in an emergency, remove the variable. A run already in progress finishes, and the next run does nothing.

## Is it healthy?

Nothing alerts if the cron itself stops, so check this in the SQL Editor. Both queries only read.

```sql
-- The last runs. Expect one an hour.
SELECT finished_at, claimed, completed, failed
FROM public.account_deletion_worker_runs
ORDER BY finished_at DESC
LIMIT 24;

-- Jobs by state, with no user ids.
SELECT status, stage, count(*), min(scheduled_for) AS oldest_due, array_agg(DISTINCT last_error_code) AS errors
FROM public.account_deletion_requests
WHERE status IN ('scheduled', 'processing', 'failed')
GROUP BY status, stage
ORDER BY status, stage;
```

A non-zero exit shows as a failed run in Railway. Logs carry request ids and error codes only.

## When a job fails

| `last_error_code` | Meaning | What to do |
|---|---|---|
| `purge_ledger_invariant` | The purge would have moved a surviving pool or budget, so it changed nothing. The known cause is an old `wife_personal` row debiting a pool. | Find the row, and ask the user how to treat it. Don't work around the check. |
| `prepare_failed` | Another database error before anything changed | Check the Supabase logs |
| `storage_failed` | Storage API error. The database work is done. | Check the Storage status and the service key |
| `auth_failed` | Auth Admin API error. Often a database trigger refusing the delete. | Check the Auth logs |
| `complete_failed`, `auth_user_still_exists` | The user was not gone when the job tried to finish | Check `auth.users`. The job retries by itself. |
| `lease_expired` | The worker died on this job five times | Check Railway logs for a crash or timeout |

To retry a `failed` job after fixing the cause, this needs explicit user approval, because it restarts a deletion:

```sql
UPDATE public.account_deletion_requests
SET status = 'processing', attempts = 0, lease_expires_at = now()
WHERE id = '<request id>' AND status = 'failed';
```

A user whose job has failed stays blocked from joining households and cannot cancel, because their data may already be gone.

## Requests from the public form

The form at `/delete-account` only stores a row and emails the developer. Someone who can sign in should use the app or the page's signed-in path, which needs no help. This is for someone who cannot.

**Verify first. Never act on the address typed in the form alone**, because anyone can type any address.

1. Find the account's address yourself. Reply from the developer mailbox **to the address on the account**, and ask them to confirm by replying from it.
2. If their reply comes from that address, go on.
3. If they have lost access to that email, do not proceed without other identity evidence. Escalate to the owner, and do nothing until the owner decides.
4. If they administer a household with other members, ask what should happen to it: hand it to a named member, or delete it. The choice is theirs, and the tool refuses to guess.

Run the tool from `ai_service/`, with `SUPABASE_URL` and `SUPABASE_SECRET_KEY` set. Without `--execute` it changes nothing and prints what would happen:

```bash
python scripts/account_deletion_operator.py --email ADDRESS --inquiry-id REFERENCE --verified-by HANDLE
```

`REFERENCE` is the reference in the developer's email, or the inquiry's id. `HANDLE` is your own short name, never an address. It is stored on the request. When the dry run looks right, add `--execute`. For a household that needs a choice, add one of these for each:

```bash
--choice HOUSEHOLD_ID:delete
--choice HOUSEHOLD_ID:transfer:SUCCESSOR_USER_ID
```

The tool prints only their own household ids and positions, so get the successor's user id with a read-only query once they have named the person. The database checks that the successor is a member and not pending deletion.

To undo it, run the same command with `--cancel`, as a dry run first. They can also cancel in the app if they get back in, and the request behaves like any other: same 30 days, same status, same emails, same purge.

| Exit code | Meaning |
|---|---|
| 0 | Done, nothing to do, or a dry run |
| 1 | The call failed. Check the status before retrying. |
| 2 | Refused: no matching account or inquiry, a choice is missing, or the database refused. Nothing changed. |

What is kept: `initiated_by = 'operator'`, the inquiry reference and your handle, on the request. The inquiry row is removed after 90 days as the page says, even if the job is still open, and the job does not need it. Completion removes the inquiry and the reference, and keeps `initiated_by` and your handle on the record with no identifiers.

The address you pass with `--email` stays in your shell history, so clear it afterwards.

## Limits

- After deletion a JWT stays valid until it expires, but with the row gone RLS and membership checks return nothing.
- Completion email: if the worker dies between the Auth delete and the send, that email is lost, because the address is gone.
- Developer mailbox copies, Railway logs, Supabase backups and `auth.audit_log_entries` are out of reach. The public page and the privacy policy disclose this.
