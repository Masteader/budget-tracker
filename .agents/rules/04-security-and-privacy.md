# Security & Privacy Rules

## 1. Zero SMS Interception Policy

- **Core Privacy Invariant:** The application is strictly standalone and privacy-first.
- **Strict Prohibition:**
  - DO NOT implement background SMS interceptors, SMS listeners, or broadcast receivers.
  - DO NOT request `READ_SMS` or `RECEIVE_SMS` Android permissions.
  - All expense tracking happens via ZATCA Phase 2 QR camera scan, Gemini Vision receipt OCR, natural voice dictation, conversational chat, or manual entry.

## 2. Supabase API Key Segregation

- **Publishable / Anon Key (`SUPABASE_PUBLISHABLE_KEY`, alias `SUPABASE_ANON_KEY`):**
  - Safe for client distribution (the Flutter app; `web_app` does not talk to Supabase at all).
  - All queries are strictly constrained by PostgreSQL Row Level Security (RLS).
- **Secret / Service Role Key (`SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY`):**
  - An `sb_secret_…` key or a legacy `service_role` JWT, in either variable (`ai_service/supabase_client.py` `describe_supabase_key`: an `sb_secret_` key wins over a legacy JWT; anon/publishable values are never used and are logged as ignored). Requires `supabase>=2.16.0`.
  - STRICTLY FORBIDDEN from being embedded or compiled into the Flutter mobile app or client-side assets (the app rejects such keys at startup).
  - Only stored in server-side environment variables and used exclusively by the Python `ai_service`, which bypasses RLS and therefore re-checks the verified JWT user's household membership and admin rights on every route. Migrations are applied in the Supabase SQL editor (database first, then backend, then app), never by the service.

## 3. Household Multi-Tenancy & Row Level Security (RLS)

- **Every** `public` table MUST have Row Level Security enabled (today: `users`, `households`, `household_memberships`, `household_invites`, `invite_attempt_log`, `household_dependents`, `household_category_settings`, `cost_control_codes`, `cost_control_sub_categories`, `transactions`, `budgets`, `accounts`, `account_transfers`, `income_records`, `installment_plans`, `member_allowances`, `spouse_reimbursements`, `api_quota`). `supabase/tests/14_audit_catalog_guardrails.sql` checks the catalog.
- Policies scope rows to the caller's active household through the helper, wrapped in `SELECT` so it is evaluated once per statement (DB-13):
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

## 4. Household Roles & Permissions (owner decision on DB-16 / DB-18)

Applies to family and roommate households alike. The database enforces every rule; `ai_service` (service role, bypasses RLS) re-checks them explicitly with the verified JWT user; the app only hides actions the server would refuse and explains a 403.

- **Roles:** `household_memberships.role` is `admin` or `member`. The **primary admin** is `households.owner_user_id` (backfilled from the longest-standing admin; passes to the longest-standing remaining admin when their membership ends). Other admins are **co-admins** with the same rights, except that they can never demote or remove the primary admin.
- **Transactions:** the creator is `transactions.user_id = auth.uid()`, bound at insert (filled in when a client omits it, rejected when it names someone else) and never changed. A member edits or deletes only their own transactions; an admin any transaction of the household. Rows without a creator are admin-only. API-created transactions must carry the verified JWT user; enrichment, installment linking and settlements check owner-or-admin (`ai_service/household_permissions.py`).
- **Money movement:** only admins move money out of a shared pool (`transfer_between_accounts`); a personal account is debited only by its owner. Members may still pay into the pool and move money between their own accounts.
- **Role changes:** only through the SECURITY DEFINER RPCs `promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin` (and `set_member_role` / `remove_member`), each with a pinned `search_path`, an actor check (`p_actor_user_id` is honoured only for the service role) and household scoping. Clients hold no write privilege on `household_memberships`, `users.role` or `households.owner_user_id`. Any admin promotes members and revokes co-admins; only the primary admin transfers primary admin. The last admin can never be demoted, and a sole admin cannot leave while members remain.
- **API endpoints:** `GET /households/{id}/members` (any member), `POST|DELETE /households/{id}/members/{user_id}/admin` (admins), `POST /households/{id}/primary-admin` (primary admin). Never take the acting user from a request body.
- **Family Nafaqah:** the wife's allowance is set by the husband or any admin (co-admins included), never by the wife herself; the husband is the household's explicit Nafaqah provider (`households.nafaqah_provider_user_id`, default the primary admin, changed only by an admin through `set_nafaqah_provider`). Invite codes are readable by admins only, and an existing member can never claim an invite of their own household.

## 5. API & Webhook Security

- **User authentication:** every non-public `ai_service` route verifies the caller's Supabase JWT itself (`auth.get_current_user_id` / `verify_household_access`). Never take the acting user from the body or from a shared secret.
- **Request signatures (`X-Signature`, HMAC-SHA256 of the exact body with `WEBHOOK_SECRET`):** defense in depth on user routes, NEVER their authentication. `auth.verify_signature_if_present` runs on every router in `main.py`: when a valid Supabase JWT authenticates the request, an invalid, malformed or unverifiable signature (including `WEBHOOK_SECRET` unset in production) MUST NOT reject it; it is logged (rate limited, route and a hash of the user id, never secret values) and the request continues. Without a valid JWT a bad signature is 401. Reason: `WEBHOOK_SECRET` has been rotated and every installed app build signs with the old value. A genuine server-to-server webhook route that has no user JWT MUST require a valid signature (`utils.verify_signature`, missing signature = reject). The Flutter app signs only when built with the optional `--dart-define=WEBHOOK_SECRET` and must never fail to start without it.
- **Firewall Token Middleware:** requests arriving through a proxy/tunnel need a verified Bearer JWT (401 + `WWW-Authenticate: Bearer` otherwise). `X-App-Token` (`APP_AUTH_TOKEN`) is accepted there only as a legacy pass for old app builds and is never user authentication; current clients do not send it.
- **Receipt Storage Privacy:** Receipt images stored in Supabase Storage (`receipts` bucket) must enforce authenticated access policies ensuring only household members can view receipts uploaded within their household folder.
