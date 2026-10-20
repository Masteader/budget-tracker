# Security & Privacy Rules

## 1. Zero SMS Interception Policy

- **Core Privacy Invariant:** The application is strictly standalone and privacy-first.
- **Strict Prohibition:**
  - DO NOT implement background SMS interceptors, SMS listeners, or broadcast receivers.
  - DO NOT request `READ_SMS` or `RECEIVE_SMS` Android permissions.
  - All expense tracking happens via ZATCA Phase 2 QR camera scan, Gemini Vision receipt OCR, natural voice dictation, conversational chat, or manual entry.

## 2. Supabase API Key Segregation

- **Anon Public Key (`SUPABASE_ANON_KEY` / `SUPABASE_PUBLISHABLE_KEY`):**
  - Safe for client distribution (Flutter mobile app, React web app).
  - All queries are strictly constrained by PostgreSQL Row Level Security (RLS).
- **Service Role Secret Key (`SUPABASE_SERVICE_ROLE_KEY`):**
  - STRICTLY FORBIDDEN from being embedded or compiled into the Flutter mobile app or client-side assets.
  - Only stored in server-side `.env` and used exclusively by the Python `ai_service` for administrative background tasks, webhooks, and migrations.

## 3. Household Multi-Tenancy & Row Level Security (RLS)

- Every sensitive relational table (`transactions`, `budgets`, `accounts`, `account_transfers`, `income_records`, `recurring_bills`, `installment_plans`, `household_dependents`, `reimbursement_debts`) MUST have Row Level Security enabled.
- Queries and RLS policies must strictly enforce tenancy isolation:
  ```sql
  household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid())
  ```
- Personal accounts are restricted to the owner:
  ```sql
  owner_user_id = auth.uid() OR is_shared_pool = true
  ```
- Never bypass RLS in client requests.

## 4. Household Roles & Permissions (owner decision on DB-16 / DB-18)

Applies to family and roommate households alike. The database enforces every rule; `ai_service` (service role, bypasses RLS) re-checks them explicitly with the verified JWT user; the app only hides actions the server would refuse and explains a 403.

- **Roles:** `household_memberships.role` is `admin` or `member`. The **primary admin** is `households.owner_user_id` (backfilled from the longest-standing admin; passes to the longest-standing remaining admin when their membership ends). Other admins are **co-admins** with the same rights, except that they can never demote or remove the primary admin.
- **Transactions:** the creator is `transactions.user_id = auth.uid()`, bound at insert (filled in when a client omits it, rejected when it names someone else) and never changed. A member edits or deletes only their own transactions; an admin any transaction of the household. Rows without a creator are admin-only. API-created transactions must carry the verified JWT user; enrichment, installment linking and settlements check owner-or-admin (`ai_service/household_permissions.py`).
- **Money movement:** only admins move money out of a shared pool (`transfer_between_accounts`); a personal account is debited only by its owner. Members may still pay into the pool and move money between their own accounts.
- **Role changes:** only through the SECURITY DEFINER RPCs `promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin` (and `set_member_role` / `remove_member`), each with a pinned `search_path`, an actor check (`p_actor_user_id` is honoured only for the service role) and household scoping. Clients hold no write privilege on `household_memberships`, `users.role` or `households.owner_user_id`. Any admin promotes members and revokes co-admins; only the primary admin transfers primary admin. The last admin can never be demoted, and a sole admin cannot leave while members remain.
- **API endpoints:** `GET /households/{id}/members` (any member), `POST|DELETE /households/{id}/members/{user_id}/admin` (admins), `POST /households/{id}/primary-admin` (primary admin). Never take the acting user from a request body.
- **Family Nafaqah:** the wife's allowance is set by the husband or any admin (co-admins included), never by the wife herself; the husband is the provider member, preferring the primary admin.

## 5. API & Webhook Security

- **Webhook Signature Verification:** Webhooks sent to `ai_service` must validate an `X-Webhook-Secret` HMAC-SHA256 signature.
- **Firewall Token Middleware:** Backend static assets and API routes must enforce firewall token authentication where applicable.
- **Receipt Storage Privacy:** Receipt images stored in Supabase Storage (`receipts` bucket) must enforce authenticated access policies ensuring only household members can view receipts uploaded within their household folder.
