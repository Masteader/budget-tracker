# Full Project Details — Budget Tracker

> **Document Version:** 1.1.0  
> **Last verified against code:** November 7, 2026 (branch `release/2026-11-07`)  
> **Project Repository:** `Masteader/budget-tracker`  
> **Primary Target Market:** Saudi Arabia (KSA) & GCC Households  

Setup, environment variables, test commands and the deployment order are in the root
[`README.md`](../README.md); this document describes what the system does. For a plain walk-through of
roles, households, accounts, the wife ledger, who sees what and account deletion, read
[`HOW_IT_WORKS.md`](HOW_IT_WORKS.md).

---

## Table of Contents

1. [Executive Summary & Vision](#1-executive-summary--vision)
2. [High-Level Architecture & Tech Stack](#2-high-level-architecture--tech-stack)
3. [Applied Features](#3-applied-features)
4. [Planned Features & Strategic Roadmap](#4-planned-features--strategic-roadmap)
5. [API Endpoints](#5-api-endpoints)
6. [Database Schema & Migrations Index](#6-database-schema--migrations-index)
7. [Test Suites & Quality Verification](#7-test-suites--quality-verification)
8. [Documentation, Specifications & Rules Index](#8-documentation-specifications--rules-index)

---

## 1. Executive Summary & Vision

**Budget Tracker** is a household finance app built for Saudi households, expat families and shared
roommate homes in the GCC. It addresses realities that generic budgeting tools ignore:

- **Payday cycles:** budgets follow the household's payday (default the 27th, the common Saudi
  payroll date), not the calendar month.
- **Islamic Family Finance (*Nafaqah*):** the husband carries the household's maintenance. There is
  no percentage split between spouses; what the wife pays for shared needs is tracked as a debt owed
  to her, and her personal spending comes from an allowance he sets.
- **ZATCA Phase 2 E-Invoicing:** QR codes on Saudi receipts are decoded (seller, VAT number,
  timestamp, totals) on the device.
- **Multi-Source Accounts:** banks, e-wallets, crypto and cash are tracked as accounts and budgets
  are linked to the account that funds them.
- **Zero SMS Interception:** no SMS permissions, listeners or SMS ingestion.

---

## 2. High-Level Architecture & Tech Stack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             CLIENT ECOSYSTEM                                │
├──────────────────────────────────────┬──────────────────────────────────────┤
│          Flutter Mobile App          │     React Web App (web_app/)         │
│    (iOS / Android - Sovereign OS)    │   (Daylight Coastal Exploding Flow)  │
│  • Dart 3.x                          │  • React 19, TypeScript, Vite        │
│  • Provider / ChangeNotifier         │  • TailwindCSS                       │
│  • Camera, Speech, Google Fonts      │  • Landing, portal, /delete-account  │
│  • SQLite Offline Queue (`sqflite`)  │  • Served by ai_service at `/`       │
└──────┬──────────────────────┬────────┴──────────────────┬───────────────────┘
       │ publishable key,     │ HTTPS + user JWT          │ POST /public/inquiries
       │ RLS, Realtime        ▼                           ▼
       │            ┌───────────────────────────────────────────────┐
       │            │       Python AI Service (FastAPI + Uvicorn)   │
       │            │  • Receipt OCR & dialect chat (LiteLLM)       │
       │            │  • Salary cycles, settlements, Nafaqah        │
       │            │  • Recurring bills, price tracker, PDF        │
       │            │  • Support / VIP inquiry email (Resend/SMTP)  │
       │            └──────────────────────┬────────────────────────┘
       ▼                                   ▼ secret key + explicit membership/admin checks
┌─────────────────────────────────────────────────────────────────────────────┐
│ Supabase: PostgreSQL + RLS on every table · SECURITY DEFINER RPCs · Storage │
│ (private `receipts` bucket) · Realtime · 69 migrations in supabase/migrations│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Applied Features

### 3.1 Multi-Source Income, Accounts & Balances Ledger
- **Account Types:** `bank`, `e_wallet`, `crypto`, `cash`, `savings`, `shared_pool`, and `wife` (a
  husband's account assigned to one wife, §3.6).
- **Liquid Asset Dashboard Card:** total household liquidity with a privacy eye toggle.
- **Inter-Account Transfers:** atomic `transfer_between_accounts` RPC with fee recording. Only
  admins move money out of a shared pool; a personal account is debited only by its owner. A wife
  account is funded only by its owner or her ledger's managers, and nothing is transferred out of it.
- **Multi-Source Income Logging:** `income_records.source_type` is `salary`, `overtime`, `bonus`,
  `side_gig`, `roommate_share` or `other`, with deductions; income records are append-only.
- **Account Reconciliation:** compares the app balance with the bank and records an adjustment.

### 3.2 Household Payday Cycle Engine
- **Payday per household:** `households.payday_day` (1–31, default 27; admins change it via
  `PUT /households/{id}/payday`). Dates are Asia/Riyadh; a payday past the month's end is clamped.
- **Cycle key:** with payday 27 the cycle 27 Oct → 26 Nov 2026 is `2026-11` (payday > 15 names the
  month the cycle ends in; payday ≤ 15 the month it starts in; payday 1 is the calendar month).
  SQL, Python and Dart produce the same key and triggers keep `transactions.cycle_key` consistent.
- **Payday Check-in:** from the household's payday the dashboard prompts for the net salary,
  overtime and bonuses, for up to 8 days (it closes 7 days after payday, counted on a 31-day month,
  so payday 27 runs to the 3rd), unless a salary was logged in the last 20 days.
- **Salary Distribution Assistant:** proposes transfers from the salary account to under-funded accounts.
- **Rollover rule** (`households.rollover_rule`, `GET|PUT /households/{id}/rollover-rule`):
  `send_to_savings` (default), `rollover_to_categories` (adds `previous_cycle_delta`) or `fresh_start`.

### 3.3 Account-Linked Budget Capacity & Deficit Engine
- **Account-to-Budget Linkage:** each category budget can name its funding account (`budgets.account_id`).
- **Capacity Formula:** $\text{Capacity Margin} = \text{Account Balance} - \sum \text{Allocated Category Budgets}$.
- **Status Indicators:** `🟢 Zero-Based (100% Allocated)`, `🔵 Surplus Buffer (+SAR X.XX)`,
  `🔴 Deficit Shortfall (-SAR X.XX)`.
- **1-Tap Quick Transfer:** a deficit alert pre-fills a transfer of the shortage from the account
  with the largest surplus.

### 3.4 ZATCA Phase 2 QR Decoder & Vision OCR Scanner
- **TLV decoding** on the device (`flutter_app/lib/services/zatca_decoder.dart`) and as a hint on the
  server (`receipt_scanner.decode_zatca_tlv`): Tag 1 seller, 2 VAT number, 3 timestamp, 4 total,
  5 VAT amount.
- **Vision OCR:** `POST /agent/scan-receipt` sends receipt pages to the model configured in
  `LITELLM_MODEL` (Gemini by default) and extracts merchant, date, payment method and line items.
- **Receipt Storage & Viewer:** images in the **private** `receipts` bucket under the household's
  folder (size and MIME limits), photo strips and a zoomable viewer. The server uploads a photo
  only after the transaction row exists (never for a preview, a duplicate prompt or a refused insert).
- **One model call per expense:** the preview of a chat message or receipt returns a server-signed
  `preview_token` (HMAC with `PREVIEW_TOKEN_SECRET`, 15 minutes, bound to the user, household and
  input). A commit that sends it back is saved from the signed result without a second model call;
  edits go through the same validation. Tampered: 422 `invalid_preview_token`; expired: parsed again
  (a receipt commit without photos then answers 422 `preview_token_expired`). OCR runs at temperature 0.1.
- **Duplicate Prevention:** `dedup_engine.py` flags candidates (QR fingerprint, merchant, total, time).

### 3.5 Conversational AI & Saudi Dialect Voice Logging
- **Natural Dialect Chat:** `POST /agent/chat-transaction` (LiteLLM) parses phrases such as
  *"تقضينا من بنده بـ ٢٥٠ ريال من بطاقة الراجحي"* (Arabic, English and Urdu); in family households it also
  suggests the Nafaqah class. Categories include housing, education, domestic help, family support,
  charity, transport, insurance and remittances (`OPEX-HOUSING` … `OPEX-REMITTANCE`).
- **Voice Entry:** on-device speech-to-text (`speech_to_text`).
- **Interactive Action Cards:** `PendingExpenseConfirmationCard`, `PurchaseSimulationCard`
  (`POST /budgets/simulate-affordability`), `DuplicateResolutionCard`.

### 3.6 Islamic Family Nafaqah & Multi-Roommate Settlements
- **Family mode, rules 1–4 in [`.agents/rules/02-…`](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md):**
  - No 50/50 or any percentage split between the spouses: shared family expenses are the husband's Nafaqah.
  - The wife paying for something shared from her own money is tagged `transactions.nafaqah_class = 'wife_reimbursable'` and becomes a debt the husband owes her; the app shows the outstanding balance and history and records partial or full repayments (overpayment rejected). Each repayment moves the amount from an account of his (or a pool, if he is an admin) into her wife account; she can instead mark "I received X", a pending request he approves or declines; corrections are reversals, never edits or deletions (migration `20261105001300`).
  - Her personal purchases are tagged `wife_personal` and charged to her **personal allowance ("مصروفها")** per salary cycle, set by the husband or an admin (never by a wife, not even a co-wife who is an admin) and seen only by her, her husband and the admins who are not wives; allocated / spent / remaining is shown, overspend goes negative and is never blocked. The same people alone read her personal purchases themselves (the rows, their receipt photos and any total that includes them; owner decision 2026-11-06), the transfers of her personal accounts and the installment plans of her personal purchases: a co-wife, even an admin, and an ordinary member do not (balances are unchanged). The owner of an account still reads the transfers of his own account with her, and a plan stays hers after her purchase is deleted; after her account is deleted her plans are read only by her husband and the admins who are not wives. Nobody updates or deletes a row they cannot read (owner decision 2026-11-06, review R3B). A repayment's own transfer rows are read only by her, her ledger's managers and the owner of the account it left; only her ledger's manager reverses a repayment, so a replaced husband or a demoted admin no longer reverses even his own; and only her ledger's managers (or she, clearing her own) change the wife or class of her advance.
  - **The wife account** (owner decisions 2026-11-06, migration `20261105001300` section 12): her husband creates an account of kind `wife`, his, assigned to one wife ("Add wife account" on his accounts screen). She spends from it (her personal purchases and her advances); he funds it and does not spend from it; nothing is transferred out of it. Every repayment to her moves the amount from his account into one of her wife accounts (his pick; on her request, hers, which he may switch to another of hers), and a reversal takes it back (refused when she has spent it, or the account is archived). With none, the app offers him to create one (`wife_account_required`). Only she, its owner and her ledger's managers see it. Her account deletion archives it (his, naming nobody); his passes it to the household's primary admin, or to her when that admin is a co-wife.
  - Expense entry (manual, chat review, edit) offers "Husband paid", "Shared for family (husband reimburses)" or "Personal (from my/her allowance)".
  - API: see [§5](#5-api-endpoints) (`/households/{id}/nafaqah…`). All require the caller's JWT and household membership. In a family household the older `POST /households/{id}/reimbursements` records only the husband's repayment to his wife, with the account it is paid from (without one it answers 426 `app_update_required`; a wife gets 403 `wife_must_request`).
- **Multi-Roommate Settlement Engine:** equal splits between roommates, graph-based debt
  simplification (`settlement_engine.simplify_debts`), shared pool accounts (`is_shared_pool = true`),
  and a settle message that can be copied for WhatsApp.

### 3.7 Recurring Bills Predictor & BNPL Installment Tracker
- **Recurring Bill Detector:** finds monthly recurring payments in transaction history
  (`GET /budgets/recurring-bills/candidates`) and reserves them against the next payday.
- **BNPL Tracker:** Tabby, Tamara and bank installment plans (`installment_plans`) with remaining
  count, amount and next due date.

### 3.8 Households, Roles & Targeted Claim-on-Join
- **Roles:** `household_memberships.role` is `admin` or `member`. The **primary admin**
  (`households.owner_user_id`) and any number of **co-admins** share admin rights; co-admins cannot
  demote or remove the primary admin. Members edit only their own transactions; admins any
  transaction of the household that they can read (a row hidden from them, such as a wife's
  personal purchase from a co-wife admin, is out of their reach). Role changes go only through RPCs
  (`promote_member_to_admin`, `revoke_admin`, `transfer_primary_admin`); details in
  [`.agents/rules/04-security-and-privacy.md`](../.agents/rules/04-security-and-privacy.md) §4.
- **Dependents** (children, elderly) are `household_dependents` profiles with allowances, not app users.
- **Placeholder members & claim-on-join:** an invite with `target_member_id` lets the person who joins
  claim the placeholder's history and allowance.
- **Multiple households:** a user can belong to several households and switch the active one
  (`switch_active_household`). Creating a household is refused once the user is admin of 5.

### 3.9 Grocery Price Intelligence & Smart Basket
- **Price history** of grocery items from scanned receipts across Saudi chains (Panda, Lulu, Danube,
  Othaim, Tamimi): `GET /analytics/price-history`.
- **Smart Basket:** `POST /analytics/shopping-basket-optimize` estimates the bill and cheaper stores.

### 3.10 Offline SQLite Engine & Network Resilience
- **Offline Transaction Buffer:** local SQLite (`budget_tracker_offline.db`, `sqflite`) queues entries while offline.
- **Background Auto-Sync:** a connectivity listener flushes the queue when the network returns.

### 3.11 Sovereign OS & Iced Ocean Theme (Light/Dark + RTL)
- **Aesthetic Direction:** tactical HUD with Iced Ocean accents (`#00E5BF`, `#0A0F1D`, glass panels, light mode).
- **Floating Dock:** bottom navigation with a speed-dial FAB (Record Income, Transfer Funds, Add Expense).

### 3.12 React Daylight Coastal Landing Page & Payday Simulator
- **Stack:** React 19, Vite, TypeScript, TailwindCSS; the production build is committed in
  `ai_service/static/` and served at `/`.
- **Pages:** the landing page at `/`, a signed-in portal, and the public account deletion page
  `/delete-account` (Arabic, English and Urdu, the same RPCs as the app; see §3.16).
- **Landing, plain copy (Arabic first):** hero with an illustrative payday card (pick a payday,
  see the real cycle dates and days left, with sample amounts), four benefits (salary cycle,
  chat/receipt entry, Nafaqah, roommate split), a Nafaqah explainer, a privacy section that names
  the AI processor (Google Gemini), FAQ, early access and footer. No invented metrics.
- **VIP early-access form:** posts to `POST /public/inquiries` (`VITE_API_BASE_URL`).

### 3.13 Trilingual Localization (Arabic, English, Urdu)
- **RTL Primary:** Arabic typography with RTL mirroring.
- **Dictionary:** `flutter_app/lib/l10n/app_localizations.dart` (`ar`, `en`, `ur`), used via `context.tr('key')`.
- **Zero Hardcoded Strings** in the UI.

### 3.14 Security Hardening & Zero SMS Policy
- **Zero SMS:** no SMS permissions, listeners, parsers, routes or `sms` transaction source
  (`ai_service/tests/test_sms_removal.py`, `supabase/tests/18_remove_sms_artifacts.sql`).
- **Key Segregation:** `SUPABASE_SECRET_KEY` / `SUPABASE_SERVICE_ROLE_KEY` only on the backend; the
  app uses `SUPABASE_PUBLISHABLE_KEY` and rejects privileged keys at startup.
- **Row Level Security:** enabled on every `public` table (guardrail test `14_audit_catalog_guardrails.sql`).
- **Authentication:** every user route verifies the caller's Supabase JWT. `X-Signature`
  (HMAC-SHA256, `WEBHOOK_SECRET`) is optional defense in depth: with a valid JWT a bad signature is
  logged and ignored. `X-App-Token` is only a legacy firewall pass for old builds.
- **Rate limits and quotas:** per-user API quota in the database (`api_quota`), sliding-window limits
  (Redis when `REDIS_URL` is set).

### 3.15 Support & VIP Early-Access Email
- `POST /public/inquiries` (anonymous, web/landing) and `POST /support/inquiries` (in-app, JWT) email
  the team through Resend or SMTP; without a provider they answer 503 and never fake success.
- `POST /support/chat` and `POST /agent/support-chat` answer in-app questions with the support agent.

### 3.16 Account Deletion
- **Request and cancel** in the app (Settings) or on the web page `/delete-account`, only through the
  `request_account_deletion`, `cancel_account_deletion`, `get_account_deletion_status` and
  `get_account_deletion_preflight` RPCs, which act on the signed-in user alone. A request needs a
  sign-in from the last 15 minutes and a typed word; the account is deleted 30 days later; Cancel
  works until the purge starts deleting data; signing in cancels nothing.
- **Households:** a primary admin with other members hands each household over or deletes it; a
  marked household takes no new members or invites and shows every member a banner with the date and
  an export hint. A wife's deletion leaves an anonymous `former_member_debts` line for what is still
  owed to her, closed by a payment or her waiver.
- **Purge:** only `ai_service/account_deletion_worker.py`, off until `ACCOUNT_DELETION_PURGE_ENABLED=1`;
  deletion emails also need `ACCOUNT_DELETION_EMAILS_ENABLED=1`. Rules: [rule 04 §6](../.agents/rules/04-security-and-privacy.md#6-account-deletion);
  operations: [`runbooks/account-deletion-purge.md`](runbooks/account-deletion-purge.md); walk-through:
  [`HOW_IT_WORKS.md` §18](HOW_IT_WORKS.md#18-account-deletion).

---

## 4. Planned Features & Strategic Roadmap

| Phase | Planned Feature | Description | Architecture / Dependency |
|---|---|---|---|
| **v1.1** | **SAMA Open Banking Integration** | Read-only bank feeds via the Saudi Central Bank (SAMA) Open Banking framework (Tarabut Gateway / Lean Tech). | Requires SAMA sandbox partnership & OAuth. |
| **v1.1** | **Live Multi-Currency FX Feeds** | Exchange-rate conversion between SAR, USD and USDT for multi-currency accounts. | Open FX rate API. |
| **v1.2** | **WhatsApp Deep-Linking** | Open WhatsApp directly with settlement reminders (today the message is copied). | URI scheme (`https://wa.me/?text=...`). |
| **v1.2** | **ML Bill Spike & Price Anomaly Alerts** | Alert when a utility bill exceeds its 3-month moving average by 30%. | Statistical model in `ai_service`. |
| **v1.3** | **Automated Push Notifications (FCM)** | Remote alerts for BNPL due dates, payday and deficits (today: local notifications only). | Supabase Database Webhooks + FCM. |
| **v1.4** | **Wearable Companion App** | Apple Watch & WearOS voice expense logging. | Flutter wear / watchOS extension. |

Removed from the roadmap because it shipped: multi-household switching (§3.8).

### 4.1 Known Gaps & Owner-Approved Exceptions

**Smart Basket uses placeholder store prices** (grep: `TODO(smart-basket-real-prices)`)
- **What is fake:** the per-store prices for Panda, Danube, Tamimi, Othaim and Lulu are hard-coded
  numbers, not live or sourced store prices. Items not in that table fall back to a made-up default of
  20 SAR (with invented per-store multipliers).
- **Where:** `ai_service/price_tracker.py` — `BENCHMARK_STORE_PRICES` and the fallback branches in
  `optimize_shopping_basket` (served by `POST /analytics/shopping-basket-optimize`).
- **User impact:** whenever a household has no recorded price for an item, app users currently see
  these placeholder numbers as the store comparison and "cheapest store" result.
- **Decision:** the owner decided on 2026-11-04 to keep them for now, including for filming demo
  clips, and to fix later. This is a tracked, owner-approved exception to the no-placeholder rule in
  [`.agents/rules/05-code-quality-and-testing.md`](../.agents/rules/05-code-quality-and-testing.md).
- **What the fix needs:** a real price source (scraped, licensed or crowd-sourced receipt data) with
  freshness dates, removal of the 20 SAR default (show "no price data" instead), and no public claim
  about store prices or savings until this is done.

---

## 5. API Endpoints

Generated from the FastAPI app object (`app.openapi()`, `ENV=development`). Every route except the
`ops` group and `POST /public/inquiries` needs `Authorization: Bearer <Supabase JWT>`; household
routes also check membership, and settings changes need an admin.

| Area | Endpoints |
|---|---|
| ops (public) | `GET /`, `GET /health`, `GET /auth/confirm`, `GET /auth/callback`, `GET /delete-account`, `GET /favicon.svg`, static assets; `/docs`, `/redoc`, `/openapi.json` only when `ENV` is non-production |
| budgets | `GET /budgets/salary-cycle-forecast`, `GET /budgets/cycles`, `POST /budgets/recalculate`, `GET /budgets/breakdown`, `POST /budgets/categories`, `POST /budgets/categories/replace`, `DELETE /budgets/categories/{category_code}`, `POST /budgets/sub-allocations`, `GET\|POST\|PATCH\|DELETE /budgets/sub-categories`, `POST /budgets/simulate-affordability` |
| recurring & installments | `GET /budgets/recurring-bills`, `POST /budgets/recurring-bills/toggle`, `GET /budgets/recurring-bills/candidates`, `GET\|POST /budgets/installments`, `PUT /budgets/installments/{plan_id}`, `POST /budgets/installments/{plan_id}/pay` |
| households | `GET\|PUT /households/{id}/payday`, `PUT /households/{id}/type`, `GET\|PUT /households/{id}/income`, `GET\|PUT /households/{id}/rollover-rule`, `GET /households/{id}/savings-summary`, `POST /households/{id}/invites`, `GET /households/invites/{invite_code}`, `POST /households/invites/{invite_code}/claim` |
| members & admins | `GET /households/{id}/members`, `POST\|DELETE /households/{id}/members/{member_user_id}/admin`, `PUT /households/{id}/members/{member_user_id}/financial-role`, `POST /households/{id}/primary-admin` |
| dependents & categories | `GET\|POST /households/{id}/dependents`, `DELETE /households/{id}/dependents/{dependent_id}`, `GET /households/{id}/categories`, `POST /households/{id}/categories/toggle`, `POST /households/{id}/categories/custom` |
| settlement | `GET /households/{id}/settlement`, `GET /households/{id}/settlement-v2`, `POST /households/{id}/reimbursements` |
| nafaqah | `GET /households/{id}/nafaqah`, `PUT /households/{id}/nafaqah/provider`, `GET\|POST /households/{id}/nafaqah/reimbursements`, `POST .../reimbursements/{reimbursement_id}/reversal`, `GET\|POST /households/{id}/nafaqah/reimbursement-requests`, `POST .../reimbursement-requests/{request_id}/approve\|decline\|cancel`, `POST .../former-member-debts/{debt_id}/payments`, `POST .../former-member-debts/{debt_id}/payments/{event_id}/reversal`, `POST .../former-member-debts/{debt_id}/waiver`, `GET\|PUT /households/{id}/nafaqah/allowance`, `GET\|POST /households/{id}/nafaqah/wife-accounts`, `PUT .../wife-accounts/{account_id}/assignment`, `POST .../wife-accounts/{account_id}/archive` |
| AI | `POST /agent/scan-receipt`, `POST /agent/chat-transaction` |
| analytics & reports | `GET /analytics/price-history`, `POST /analytics/shopping-basket-optimize`, `GET /reports/statement-pdf` |
| support & inquiries | `POST /support/chat`, `POST /agent/support-chat`, `POST /support/inquiries`, `POST /public/inquiries` (anonymous) |

There is no SMS or webhook ingestion route, and no HTTP route deletes or purges an account: deletion
is requested through Supabase RPCs and carried out by the worker (§3.16).

---

## 6. Database Schema & Migrations Index

Base schema: `supabase/schema.sql` + `supabase/seed.sql`, then 69 migrations in
`supabase/migrations/`, applied in filename order (exception: `20261018_multi_source_income_and_accounts.sql`
before `20261018_membership_sync_and_shared_account_policies.sql`; `supabase/tests/run_tests.py`
holds the exact replay order and the production rollout order). Proof tests are in `supabase/tests/`.

| Migration File | Objects | Purpose |
|---|---|---|
| `20260925_add_line_items_and_sources.sql` | `transactions` | Line items JSONB and input source columns. |
| `20260925_add_transaction_edit_delete_triggers.sql` | `transactions` triggers | Recompute budget spent totals on update/delete. |
| `20260930_fix_transactions_rls_and_columns.sql` | `transactions`, RLS | Household-scoped RLS and user association columns. |
| `20261002_add_sub_allocations_to_budgets.sql` | `budgets` | `sub_allocations` JSONB for sub-category caps. |
| `20261002_salary_cycle_and_sub_budgets.sql` | `budgets`, `transactions`, `cost_control_sub_categories` | `cycle_key`, `previous_cycle_delta`, sub-category catalog. |
| `20261003_allow_select_sub_categories.sql` | `cost_control_sub_categories` | Read policy for sub-categories. |
| `20261005_add_installment_plans.sql` | `installment_plans` | BNPL plans (Tabby/Tamara/bank). |
| `20261005_query_performance_and_indexes.sql` | indexes | Covering and lookup indexes. |
| `20261008_add_household_payday.sql` | `households`, `users` | `payday_day` (1–31, default 27). |
| `20261008_add_qr_code_raw_to_transactions.sql` | `transactions` | Raw ZATCA TLV string. |
| `20261008_create_receipts_bucket_and_policies.sql` | Storage | `receipts` bucket and policies. |
| `20261009_fix_storage_policies_and_receipt_cleanup.sql` | Storage, triggers | Delete receipt images with their transaction. |
| `20261009_hardened_security_and_storage_policies.sql` | Storage, RLS | Household folder isolation for receipts. |
| `20261010_add_household_monthly_income.sql` | `households` | `monthly_income` baseline. |
| `20261011_household_dependents_and_subcategories.sql` | `household_dependents` | Dependents, allowances, attribution. |
| `20261011_hybrid_category_lifecycle.sql` | `cost_control_codes`, `household_category_settings` | Standard vs custom categories, archiving. |
| `20261015_family_nafaqah_and_multi_roommate_settlement.sql` | `users.financial_role`, `household_invites`, `transactions` settlement columns | Role-aware settlements and invites. |
| `20261015_manual_members_and_claim_merge.sql` | `household_dependents`, `household_invites.target_member_id` | Placeholder members and claim-on-join. |
| `20261018_household_memberships_and_switching.sql` | `household_memberships`, `switch_active_household` | Several households per user. |
| `20261018_multi_source_income_and_accounts.sql` | `accounts`, `account_transfers`, `income_records`, `budgets.account_id` | Accounts, transfers, multi-source income. |
| `20261018_membership_sync_and_shared_account_policies.sql` | policies, triggers, RPCs | Membership sync; shared pool policies. |
| `20261019030000_sec01_sec02_household_takeover_prevention.sql` | `users`, `household_invites`, RPCs | SEC-01/02: no self-promotion; single-use, expiring invites with lockout. |
| `20261019060000_sec06_private_receipts_bucket.sql` | Storage, `transactions` | SEC-06: private bucket, relative storage paths. |
| `20261019070000_sec07_api_quota_and_rate_limits.sql` | `api_quota` | SEC-07: persistent API quota. |
| `20261019080000_bug02_payday_cycle_parity_and_triggers.sql` | `get_saudi_cycle_for_timestamp`, triggers | BUG-02: SQL cycle parity, automatic `cycle_key`. |
| `20261019090000_sec05_accounts_security_and_transfers.sql` | `accounts`, transfers, income | SEC-05: account RLS, atomic transfers, balance triggers. |
| `20261019100000_sec08_round6_hardening.sql` | several | SEC-08: round-6 hardening. |
| `20261020005000_preflight_live_alignment.sql` | live-only objects | Captures live drift before the audit batch. |
| `20261020010000_audit_invites_rls_and_targeted_claims.sql` | `household_invites` | DB-01: RLS on invites, targeted claims. |
| `20261020020000_audit_membership_policy_recursion.sql` | `household_memberships` | DB-02: non-recursive membership policies. |
| `20261020030000_audit_reallocate_budget_authz.sql` | `reallocate_budget` | DB-03: authorization and amount checks. |
| `20261020040000_audit_cost_control_codes_policies.sql` | `cost_control_codes` | DB-04: household-scoped category writes. |
| `20261020050000_audit_ledger_precision_and_income_append_only.sql` | transfers, `income_records` | DB-06: 2-decimal amounts, append-only income. |
| `20261020060000_audit_transaction_cycle_key_integrity.sql` | `transactions` | DB-08: `cycle_key` cannot be forged. |
| `20261020070000_audit_definer_search_path_and_household_insert.sql` | functions, `households` | DB-09/10: pinned `search_path`, household insert rules. |
| `20261020080000_audit_receipts_bucket_limits.sql` | Storage | DB-11: size and MIME limits. |
| `20261020090000_audit_sole_admin_account_deletion.sql` | memberships, auth cascade | DB-12: deleting a sole admin's account. |
| `20261020100000_audit_rls_initplan_and_fk_indexes.sql` | policies, indexes | DB-13: `(SELECT auth.uid())` policies, FK indexes. |
| `20261020200000_remove_sms_artifacts.sql` | `transactions`, schema | API-25: SMS leftovers removed; `source = 'sms'` rejected. |
| `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` | `transactions.nafaqah_class` / `nafaqah_spouse_id`, `member_allowances`, `spouse_reimbursements`, Nafaqah RPCs | UI-24: wife reimbursement ledger (append-only, overpayment rejected under an advisory lock) and per-cycle wife allowance; writes only via pinned `SECURITY DEFINER` RPCs. |
| `20261020400000_admin_permissions_and_co_admins.sql` | `households.owner_user_id`, `transactions.user_id`, role RPCs | DB-16/18: primary admin, co-admins, creator-bound transactions, admin-only shared pool debits. |
| `20261020500000_review_lock_financial_role.sql` | `users.financial_role` | FR-B-04: clients cannot set their own financial role. |
| `20261020600000_e2e_helper_rpcs_and_sub_category_visibility.sql` | helper RPCs, sub-categories | E2E-04/05: helper grants, sub-category visibility. |
| `20261020700000_fable_db_hardening.sql` | several | Independent review hardening (section B). |
| `20261020750000_installment_pay_atomic.sql` | installment payments | FABLE-API-10: atomic installment payment. |
| `20261020800000_household_roles_and_nafaqah_integrity.sql` | memberships, Nafaqah RPCs | Per-household roles and Nafaqah ledger integrity. |
| `20261020900000_household_type_and_round2_fixes.sql` | `households.household_type`, `nafaqah_provider_user_id` | Family or roommates type, explicit Nafaqah provider. |
| `20261021000000_saudi_taxonomy_and_bnpl_schedule.sql` | categories, `installment_plans` | Saudi category taxonomy, BNPL schedules. |
| `20261024000000_create_inquiries_table.sql` | `inquiries` | Stored support and early-access inquiries. |
| `20261026000000_add_savings_account_type.sql` | `accounts` | `savings` account type. |
| `20261026120000_household_autonomous_taxonomy.sql` | templates, sub-categories, replace RPC | Household category catalog and category replacement. |
| `20261101000000_nafaqah_wife_no_account.sql` | `transactions` | Unlink legacy wife rows from accounts that are not hers. |
| `20261101000100_nafaqah_wife_account_owner_guard.sql` | `trg_enforce_wife_class_account` | Wife-class rows only on her own accounts or none. |
| `20261102000000_cleanup_database_jargon_and_zombie_columns.sql` | `transactions` | `raw_sms` renamed to `notes`; unused columns dropped. |
| `20261102010000_void_income_record_rpc.sql` | `void_income_record` | Void an income record with its balance reversal. |
| `20261105000000_account_deletion_ledger_fks.sql` | ledger foreign keys | Account deletion task 1: ledgers survive a deleted user. |
| `20261105000100_account_deletion_schema.sql` | deletion tables, guards | Account deletion task 2: requests, queues, pending-user blocks. |
| `20261105000200_account_deletion_rpcs.sql` | deletion RPCs | Account deletion task 3: request, cancel, status, preflight. |
| `20261105000300_account_deletion_purge.sql` | purge functions | Account deletion task 4: the service-only purge. |
| `20261105000400_account_deletion_worker_support.sql` | worker functions | Account deletion task 5: leases, runs, alerts. |
| `20261105000500_void_income_single_subtraction.sql` | `void_income_record` | Subtract a voided income once. |
| `20261105000600_limit_anonymous_contact_form.sql` | `inquiries`, grants | The anonymous contact form goes through the API only; `anon` gets nothing in `public`. |
| `20261105000700_sub_categories_household_scope.sql` | sub-categories | Household-scoped sub-category reads. |
| `20261105000800_account_deletion_operator_request.sql` | operator functions | Operator path for people who cannot sign in. |
| `20261105000900_account_deletion_notice_windows.sql` | notices | Deletion notice and reminder windows. |
| `20261105001000_inactive_category_budgets.sql` | budgets | Expenses in an inactive category still count under it. |
| `20261105001100_last_admin_household_lock.sql` | memberships | A household is never left with members and no admin. |
| `20261105001200_account_deletion_former_member_debt.sql` | `former_member_debts` | What a deleted wife is still owed: payment, waiver, reversal. |
| `20261105001300_wife_repayment_debit.sql` | wife account, requests, reversals, read policies | Tracked repayments from an account into her wife account, requests, reversals, and who sees her ledger and private rows. |

Do not use `supabase db push` on an existing project until the history is re-baselined (DB-15).

---

## 7. Test Suites & Quality Verification

Commands and flags: root [`README.md`](../README.md#running-the-tests). Counts as of 2026-11-07
(branch `release/2026-11-07`):

| Suite | Location | Result |
|---|---|---|
| Flutter unit/widget tests | `flutter_app/test/` | 2,902 passed; `flutter analyze`: no issues |
| API (pytest, hermetic) | `ai_service/tests/` | 3,092 passed, 4 skipped (peak-memory checks) |
| Database (SQL proof tests) | `supabase/tests/NN_*.sql` via `run_tests.py --rebuild` | 71 files passed on a fresh PostgreSQL 17 rebuild, and again in the rollout (71), drift (28) and live (71) orders |
| Web | `web_app/` | `npm run lint` clean, `npm run build` OK (no unit tests) |
| End-to-end | `tests/e2e/` | Local services and mocks only |

---

## 8. Documentation, Specifications & Rules Index

### 8.1 Engineering Rules (`.agents/rules/`)
- **[01. Architecture & Tech Stack](../.agents/rules/01-architecture-and-tech-stack.md)**: topology, frameworks, communication.
- **[02. Saudi Fintech & Islamic Compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**: household payday cycles, ZATCA, Nafaqah rules 1–4.
- **[03. UI/UX & Design System](../.agents/rules/03-ui-ux-and-design-system.md)**: palette, web theme, trilingual RTL rules.
- **[04. Security & Privacy](../.agents/rules/04-security-and-privacy.md)**: zero SMS, key segregation, RLS, admin/co-admin model, JWT auth.
- **[05. Code Quality & Testing](../.agents/rules/05-code-quality-and-testing.md)**: TDD, all suites, analyzer.
- **[06. PR & Multi-Agent Audit Pipeline](../.agents/rules/06-pr-and-audit-pipeline.md)**: review rounds, sensitive tasks, the owner's scope waiver (2026-11-06).

### 8.2 Review & Audit (`docs/review/`)
- [Master audit report](review/audit/MASTER_AUDIT_REPORT.md), [fix log](review/FIX_LOG.md), [owner actions](review/OWNER_ACTIONS.md), [live DB pre-flight](review/audit/live_db_preflight.md).

### 8.3 Design Specifications & Plans (historical)
All 11 specs and 21 plans in `docs/superpowers/` are cataloged in **[`docs/README.md`](README.md)**.
