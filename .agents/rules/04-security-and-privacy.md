# Security & Privacy Rules

## 1. Zero SMS Policy

- **Manifest-Level Zero-SMS Policy:**
  - The Flutter application MUST NOT declare, request, or use any SMS-related permissions (`RECEIVE_SMS`, `READ_SMS`, `SEND_SMS`).
  - Google Play and Apple App Store compliance: the application strictly ingests financial data via user-initiated channels (camera scan, photo upload, voice transcription, or direct form entry).
  - Legacy `raw_sms` columns in the database are retained exclusively as free-text audit trail notes (e.g. Chat entry text, OCR extraction summaries).

## 2. API Key & Secret Management

- **Client-Side Restrictions:**
  - The Flutter application and web app must ONLY hold the Supabase **Publishable (Anon) Key** (`SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_ANON_KEY`).
  - NEVER embed the `SUPABASE_SECRET_KEY` (or `SUPABASE_SERVICE_ROLE_KEY`), `WEBHOOK_SECRET`, or AI model keys in client-side code, configuration files, or committed assets.
- **Backend Secrets:**
  - The Python AI microservice accesses Supabase using the service role key and stores secrets in environment variables (`.env`).
  - Never commit `.env` files to git. Use `.env.example` templates with redacted placeholders.

## 3. Database Multi-Tenancy & Row Level Security (RLS)

- **100% RLS Coverage:** Every table in the `public` schema must have Row Level Security enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`).
- **InitPlan Optimization:** Policies must wrap helper functions in `(SELECT ...)` to prevent per-row evaluation:
  ```sql
  household_id = (SELECT public.get_auth_user_household_id())
  ```
- Personal accounts are visible to their owner; shared pools to the household, and only admins change them:
  ```sql
  owner_user_id = (SELECT auth.uid())
    OR (is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id()))
  ```
- `SECURITY DEFINER` functions pin `search_path`; no policy targets `PUBLIC`/`anon`, and `anon` can execute no function in `public` (same guardrail test).
- Never bypass RLS in client requests.
- **Client-Side RLS Deletion Verification:** Providers must not treat 0 deleted rows (caused by RLS denial) as success. They must verify row mutation count, roll back optimistic UI mutations on 0-row response, and set `lastWriteDenied` to inform the user.

## 4. Household Roles & Permissions (owner decision on DB-16 / DB-18)

Applies to family and roommate households alike. The database enforces every rule; `ai_service` (service role, bypasses RLS) re-checks them explicitly with the verified JWT user; the app only hides actions the server would refuse and explains a 403.

- **Roles:** `household_memberships.role` is `admin` or `member`. The **primary admin** is `households.owner_user_id` (backfilled from the longest-standing admin; passes to the longest-standing remaining admin when their membership ends). Other admins are **co-admins** with the same rights, except that they can never demote or remove the primary admin.
- **Transactions:** the creator is `transactions.user_id = auth.uid()`, bound at insert (filled in when a client omits it, rejected when it names someone else) and never changed. A member edits or deletes only their own transactions; an admin any transaction of the household. Rows without a creator are admin-only. API-created transactions must carry the verified JWT user; enrichment, installment linking and settlements check owner-or-admin (`ai_service/household_permissions.py`).
- **Money movement:** only admins move money out of a shared pool (`transfer_between_accounts`); a personal account is debited only by its owner. Members may still pay into the pool and move money between their own accounts.
- **Role changes:** only through the SECURITY DEFINER RPCs `promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin` (and `set_member_role` / `remove_member`), each with a pinned `search_path`, an actor check (`p_actor_user_id` is honoured only for the service role) and household scoping. Clients hold no write privilege on `household_memberships`, `users.role` or `households.owner_user_id`. Any admin promotes members and revokes co-admins; only the primary admin transfers primary admin. The last admin can never be demoted, and a sole admin cannot leave while members remain.
- **API endpoints:** `GET /households/{id}/members` (any member), `POST|DELETE /households/{id}/members/{user_id}/admin` (admins), `POST /households/{id}/primary-admin` (primary admin). Never take the acting user from a request body.
- **Family Nafaqah:** the wife's allowance is set by the husband or an admin (co-admins included), never by a wife: not herself, and not a co-wife who is an admin (owner decision 2026-11-06); it is read only by her, her husband and the admins who are not wives (rule 02, family mode rule 3), and so are her personal purchases (`wife_personal` transactions), their receipt photos and anything summed from them, the transfers of her personal accounts (`account_transfers`; the owner of the account on the other side reads that row too, a shared pool's owner nothing more) and the installment plans of her personal purchases (also after the purchase is deleted: the plan keeps her as its owner), in the database (the transactions, receipts, transfers and installment plans read policies), the API (every service-role answer built from transactions filters by the caller) and the app; the husband is the household's explicit Nafaqah provider (`households.nafaqah_provider_user_id`, default the primary admin, changed only by an admin through `set_nafaqah_provider`). Invite codes are readable by admins only, and an existing member can never claim an invite of their own household.

## 5. API & Webhook Security

- **User authentication:** every non-public `ai_service` route verifies the caller's Supabase JWT itself (`auth.get_current_user_id` / `verify_household_access`). Never take the acting user from the body or from a shared secret.
- **Request signatures (`X-Signature`, HMAC-SHA256 of the exact body with `WEBHOOK_SECRET`):** defense in depth on user routes, NEVER their authentication. `auth.verify_signature_if_present` runs on every router in `main.py`: when a valid Supabase JWT authenticates the request, an invalid, malformed or unverifiable signature (including `WEBHOOK_SECRET` unset in production) MUST NOT reject it; it is logged (rate limited, route and a hash of the user id, never secret values) and the request continues. Without a valid JWT a bad signature is 401. Reason: `WEBHOOK_SECRET` has been rotated and every installed app build signs with the old value. A genuine server-to-server webhook route that has no user JWT MUST require a valid signature (`utils.verify_signature`, missing signature = reject). The Flutter app signs only when built with the optional `--dart-define=WEBHOOK_SECRET` and must never fail to start without it.
- **Firewall Token Middleware:** requests arriving through a proxy/tunnel need a verified Bearer JWT (401 + `WWW-Authenticate: Bearer` otherwise). `X-App-Token` (`APP_AUTH_TOKEN`) is accepted there only as a legacy pass for old app builds and is never user authentication; current clients do not send it. Public paths are an explicit allow-list in `main.py`: `/delete-account` is listed as that exact path, and there is deliberately no generic SPA fallback.
- **Receipt Storage Privacy:** Receipt images stored in Supabase Storage (`receipts` bucket) must enforce authenticated access policies ensuring only household members can view receipts uploaded within their household folder; the photo of a wife's personal purchase only by her, her husband and an admin who is not a wife (`nafaqah_receipt_hidden`, owner decision 2026-11-06).

## 6. Account Deletion

Plan: `docs/superpowers/plans/2026-11-05-account-deletion-corrected.md`. Operations: `docs/runbooks/account-deletion-purge.md`.

- **Requesting and cancelling:** only through `request_account_deletion`, `cancel_account_deletion`, `get_account_deletion_status` and `get_account_deletion_preflight`, which act on `auth.uid()` alone; no argument can name another user. A request needs a login from the last 15 minutes (the JWT's `session_id` must match a recent `auth.sessions` row of this user) and the typed word, both checked by the server. Cancel needs no re-auth. Signing in cancels nothing.
- **Purging:** only `ai_service/account_deletion_worker.py`, through service-only functions that are revoked from `anon` and `authenticated` and refuse any caller with a JWT subject. It does nothing destructive without `ACCOUNT_DELETION_PURGE_ENABLED=1` (that exact value, on the Cron service only). Never add an HTTP route that purges. Enabling it needs explicit user approval.
- **Deletion emails:** every email to an account holder or household member needs both `ACCOUNT_DELETION_EMAILS_ENABLED=1` and `ACCOUNT_DELETION_PURGE_ENABLED=1` (those exact values), because a reminder names a date a stopped purge would not meet. The email switch needs its own user approval. Off with the purge on, no notice is sent or marked sent, a completion email is skipped and the job still completes, and developer alerts still go out. Never promise these emails unconditionally in user-facing copy.
- **Deletion tables:** `account_deletion_requests`, `account_deletion_storage_queue` and `account_deletion_worker_runs` have RLS on, no policies and no client privileges; clients reach them only through the RPCs. Add no deletion columns to `users`, because `users_select_household` would show them to housemates.
- **Pending users and marked households:** triggers, plus a check in `transfer_primary_admin`, block a pending user from joining, creating a household, being promoted, receiving primary admin or becoming Nafaqah provider, and block a marked household from taking new members or invites. They must keep covering RPC and service-role paths.
- **Household deletion** happens only in `prepare_account_purge`. A delete of `auth.users` by any other path hands the household over and never deletes it.
- **Public request form:** `POST /public/inquiries` with type `account_deletion` only stores a row and emails the developer. It never looks up an account or mails the submitted address, and its answer must not vary by whether an account exists. It must never imply the account was deleted.
- **Operator path:** a developer who has verified someone who cannot sign in schedules or cancels the same 30-day deletion only with `ai_service/scripts/account_deletion_operator.py`, a dry run unless `--execute` is given, through service-only functions that share the scheduler with `request_account_deletion` and refuse to guess a household choice. It has no HTTP route and must never get one. Verification is a reply from the address on the account, never only the address typed in the form; see the runbook.
- **Logs:** the worker logs request ids and error codes only, never raw errors, emails, tokens or user ids.
