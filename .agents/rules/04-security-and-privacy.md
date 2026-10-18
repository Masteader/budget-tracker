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

## 4. API & Webhook Security

- **Webhook Signature Verification:** Webhooks sent to `ai_service` must validate an `X-Webhook-Secret` HMAC-SHA256 signature.
- **Firewall Token Middleware:** Backend static assets and API routes must enforce firewall token authentication where applicable.
- **Receipt Storage Privacy:** Receipt images stored in Supabase Storage (`receipts` bucket) must enforce authenticated access policies ensuring only household members can view receipts uploaded within their household folder.
