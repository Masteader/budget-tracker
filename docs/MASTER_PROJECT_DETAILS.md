# MASTER PROJECT DETAILS — BUDGET TRACKER

> **Document Version:** 2.1.0 (Master Unified Reference)  
> **Effective Date:** November 2026  
> **Project Repository:** `Masteader/budget-tracker`  
> **Primary Target Market:** Kingdom of Saudi Arabia (KSA) & GCC Households  
> **Authoritative Baseline:** Unified synthesis of `PROJECT_DETAILS.md`, `MASTER_CODEBASE_AUDIT.md`, `FORMULA_VERDICT.md`, `PR_AUDIT_BUNDLE.md`, and Engineering Rules 01–06.  
> **Master Doc Synthesis:** [Executed by: code-implementer (Claude Opus 5.5 high)]  
> **Rule Alignment & Orchestrator Governance:** [Audited by: Claude Opus 5.5 Orchestrator | Executed by: code-implementer (Claude Opus 5.5 high)]

---

## Table of Contents

1. [Executive Summary & Product Mission](#1-executive-summary--product-mission)
2. [System Architecture & Tech Stack](#2-system-architecture--tech-stack)
3. [Database Schema, Migrations, Triggers & RLS Policies](#3-database-schema-migrations-triggers--rls-policies)
4. [Saudi Fintech & Islamic Household Finance Operating Engine](#4-saudi-fintech--islamic-household-finance-operating-engine)
5. [UI/UX Design System & Client Ecosystem](#5-uiux-design-system--client-ecosystem)
6. [Security, Privacy & Zero-SMS Hardening](#6-security-privacy--zero-sms-hardening)
7. [Comprehensive Codebase Audit Findings & Remediation Matrix](#7-comprehensive-codebase-audit-findings--remediation-matrix)
   - [7.1 Database & Migrations Security (Pass 1)](#71-database--migrations-security-pass-1-audited-by-claude-opus-55-high--executed-by-code-implementer-claude-opus-55-high)
   - [7.2 AI Microservice Backend Architecture (Pass 2)](#72-ai-microservice-backend-architecture-pass-2-audited-by-claude-opus-55-high--executed-by-code-implementer-claude-opus-55-high)
   - [7.3 Flutter Mobile App Architecture (Pass 3)](#73-flutter-mobile-app-architecture-pass-3-audited-by-claude-opus-55-high--executed-by-code-implementer-claude-opus-55-high)
   - [7.4 Cross-Cutting Compliance & UI System (Pass 4)](#74-cross-cutting-compliance--ui-system-pass-4-audited-by-claude-opus-55-high--executed-by-code-implementer-claude-opus-55-high)
   - [7.5 Lead Architect Audit & Operating Cash SSOT Implementation](#75-lead-architect-audit--operating-cash-ssot-implementation-branch-featprovider-sot-operating-cash-audited-by-gemini-argon-high--validated-by-claude-opus-55-batch--executed-by-code-implementer-gemini-38-flash-high)
   - [7.6 Database Schema Consolidation & Jargon Elimination](#76-database-schema-consolidation--jargon-elimination-branch-featprovider-sot-operating-cash-planned-by-plan-writer-claude-opus-55-high--executed-by-code-implementer-claude-opus-55-high--reviewed-by-reviewer-spec-reviewer-break-reviewer-fable)
8. [Testing, Verification Gate & Orchestrator Governance Matrix](#8-testing-verification-gate--orchestrator-governance-matrix)
   - [8.1 Verification Gate Commands](#81-verification-gate-commands)
   - [8.2 Orchestrator Governance Matrix & Delegation Pipeline](#82-orchestrator-governance-matrix--delegation-pipeline)
   - [8.3 Subagent & Module Registry](#83-subagent--module-registry)
   - [8.4 Workflow Evolution & Rule Alignment](#84-workflow-evolution--rule-alignment-audited-by-claude-opus-55-orchestrator--executed-by-code-implementer-claude-opus-55-high)
9. [Complete API Endpoints Directory](#9-complete-api-endpoints-directory)
10. [Strategic Roadmap (v1.1 – v1.4)](#10-strategic-roadmap-v11--v14)

---

## 1. Executive Summary & Product Mission

**Budget Tracker** is an autonomous, high-integrity household financial operating system engineered specifically for Saudi citizens, resident expat families, and shared roommate living groups in the Kingdom of Saudi Arabia (KSA) and the wider Gulf Cooperation Council (GCC).

Mainstream global budgeting platforms (e.g., YNAB, Mint, Monarch, Copilot) are fundamentally incompatible with the socioeconomic and legal realities of GCC households:
1. **Misaligned Payday Cycles:** Generic tools assume calendar months (1st to 30th/31st). Saudi government and corporate payrolls predominantly disburse on the **27th of each month** (or the preceding business day). Budget Tracker operates entirely on dynamic, household-configured salary cycles (`households.payday_day`, default 27th), calculating all category allocations, spending caps, and rollovers relative to the Hijri-aligned Gregorian payday.
2. **Islamic Family Finance (*Nafaqah* vs. Roommate Living):** Sharia jurisprudence places full financial maintenance (*Nafaqah*) of housing, food, sustenance, and dependents upon the husband. Automatic 50/50 spousal expense splitting is culturally and legally inappropriate for Saudi family units. Budget Tracker enforces the **4 Golden Nafaqah Rules**: spousal expenses paid by the wife are tracked as an explicit, repayable debt owed by the husband; her personal purchases are charged against her per-cycle allowance ("مصروفها"); and shared expenses paid by the husband are ordinary household overhead. For shared bachelor/student flats, the app switches to **Roommate Mode**, deploying multi-way graph debt simplification.
3. **ZATCA Phase 2 E-Invoicing Standard:** Saudi Arabia mandates electronic tax invoices featuring Base64 TLV (Tag-Length-Value) QR codes. Budget Tracker features an on-device TLV decoder and high-speed Gemini Vision OCR scanner that extracts seller identity, 15-digit VAT number, transaction timestamp, invoice total, and 15% VAT halalas without server round-trips.
4. **Multi-Source Financial Ecosystem:** GCC users maintain assets across traditional commercial banks (Al Rajhi, SNB, Riyad Bank, Alinma), digital fintech wallets (STC Pay, Urpay, Tiqmo), cash, and crypto exchanges. Budget Tracker implements a zero-based cash management engine linking every budget category directly to its funding account, surfaced through real-time liquidity indicators.
5. **Zero-SMS Hardening:** In strict compliance with modern privacy principles and Google Play / Apple App Store financial safety guidelines, the app strictly forbids background SMS reading or interception permissions. Ingestion is 100% user-directed via camera QR scan, OCR photo capture, conversational Saudi-dialect voice/text entry, or manual entry.

---

## 2. System Architecture & Tech Stack

Budget Tracker employs a decoupled client-server architecture built on four specialized tiers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             CLIENT ECOSYSTEM                                │
├──────────────────────────────────────┬──────────────────────────────────────┤
│          Flutter Mobile App          │       React Web App (web_app/)       │
│    (iOS / Android - Velvet Burgundy) │  (Daylight Coastal Exploding Flow)   │
│  • Flutter 3.22+, Dart 3.x           │  • React 19, TypeScript, Vite        │
│  • Provider / ChangeNotifier         │  • TailwindCSS, Lucide React         │
│  • Camera, Speech, Google Fonts      │  • Payday Simulator, VIP Form        │
│  • Offline SQLite (`sqflite`)        │  • Built into ai_service/static/     │
└──────┬──────────────────────┬────────┴──────────────────┬───────────────────┘
       │ publishable key,     │ HTTPS + user JWT          │ POST /public/inquiries
       │ RLS, Realtime        ▼                           ▼
       │            ┌───────────────────────────────────────────────┐
       │            │     Python AI Microservice (FastAPI + ASGI)   │
       │            │  • LiteLLM (Gemini 2.5 Flash / Vision OCR)    │
       │            │  • Saudi salary cycle & rollover math         │
       │            │  • Roommate debt graph & Nafaqah service      │
       │            │  • Recurring bill & price anomaly detector    │
       │            │  • Hermetic pytest suite (1,100+ tests)        │
       │            └──────────────────────┬────────────────────────┘
       ▼                                   ▼ secret service key + in-code RBAC
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Supabase Platform (PostgreSQL 15+)                      │
│  • 100% Row Level Security (RLS) multi-tenancy on all public tables         │
│  • SECURITY DEFINER RPCs with pinned search_path = public, pg_temp          │
│  • Private 'receipts' storage bucket with household folder isolation        │
│  • Realtime replication streams for multi-device synchronization            │
│  • 53 timestamped migrations (supabase/migrations/)                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Technology Stack Matrix

| Layer | Framework / Runtime | Key Libraries / Modules | Primary Responsibility |
|---|---|---|---|
| **Mobile Client** | Flutter 3.22+, Dart 3.x | `provider`, `sqflite`, `camera`, `speech_to_text`, `google_fonts`, `intl`, `uuid` | Cross-platform Android & iOS app. Velvet Burgundy HUD design system (with legacy Sovereign OS compatibility layer). Local offline transaction buffer and auto-sync. |
| **Web Portal** | React 19, TypeScript, Vite | `tailwindcss`, `clsx`, `lucide-react` | Daylight Coastal Exploding Flow marketing portal. Illustrative Saudi payday cycle countdown simulator and VIP early-access lead capture. Committed build served by FastAPI at `/`. |
| **AI Microservice** | Python 3.11, FastAPI, Uvicorn | `litellm`, `pydantic v2`, `httpx`, `reportlab`, `postgrest`, `python-dotenv` | Vision receipt OCR, Saudi dialect conversational expense parsing, recurring bill detection, graph debt simplification, PDF statement generation. |
| **Database & Auth** | Supabase (PostgreSQL 15+) | `pgcrypto`, `supabase-py`, PostgREST | Multi-tenant relational storage, RLS security policies, `SECURITY DEFINER` atomic RPCs, database triggers, storage buckets. |
| **Offline Cache** | SQLite (`sqflite`) | `budget_tracker_offline.db` | Local queue for offline expense capture with transactional flush and idempotency upon network reconnect. |

### 2.2 Component Contract & Communication Boundaries

1. **Client to Supabase Platform:**
   - Flutter communicates directly with Supabase via PostgREST using `SUPABASE_PUBLISHABLE_KEY` (alias `SUPABASE_ANON_KEY`).
   - Every single query, mutation, and realtime channel is governed by PostgreSQL Row Level Security (RLS).
   - Money movements, balance adjustments, and role updates NEVER execute via raw client `UPDATE` queries; they must invoke audited `SECURITY DEFINER` RPCs.
2. **Client to AI Microservice:**
   - Server-side capabilities (Vision OCR receipt scanning, conversational dialect parsing, affordability simulation, PDF statements) are called via HTTPS.
   - Every non-public request requires `Authorization: Bearer <Supabase_JWT>`. The Python service verifies the JWT algorithm, expiration, issuer, audience, and active household membership before executing any logic.
   - `X-Signature` (HMAC-SHA256 with `WEBHOOK_SECRET`) provides optional defense-in-depth: if a valid JWT is present, an invalid or missing signature logs a warning and allows the request to succeed.
3. **AI Microservice to Supabase:**
   - FastAPI connects using `SUPABASE_SECRET_KEY` (or `SUPABASE_SERVICE_ROLE_KEY`), which bypasses RLS.
   - **Strict Governance:** Because service-role bypasses RLS, the Python application layer explicitly validates household tenancy, member status, and admin rights on every single route via `household_permissions.py` before executing database calls.
   - Migrations are applied exclusively in PostgreSQL; `ai_service` never runs schema alterations.
4. **Web Portal to Backend:**
   - The React web application does not possess Supabase credentials and makes no direct database calls. It interacts solely with the anonymous public lead capture endpoint: `POST /public/inquiries`.
5. **Deployment Invariant:**
   - Database schema migrations apply first $\to$ AI microservice deploys second $\to$ Web & Flutter client builds publish third.

---

## 3. Database Schema, Migrations, Triggers & RLS Policies

### 3.1 Complete Migrations Catalog (53 Migrations)

All database evolution is captured in chronological, timestamped migration scripts in `supabase/migrations/`:

| # | Migration File | Target Objects | Core Purpose |
|---|---|---|---|
| 01 | `20260925_add_line_items_and_sources.sql` | `transactions` | Adds line items JSONB and input source attribution. |
| 02 | `20260925_add_transaction_edit_delete_triggers.sql` | `transactions` triggers | Decrements and recomputes category budget spent totals. |
| 03 | `20260930_fix_transactions_rls_and_columns.sql` | `transactions`, RLS | Enforces household-scoped multi-tenancy and user binding. |
| 04 | `20261002_add_sub_allocations_to_budgets.sql` | `budgets` | Adds `sub_allocations` JSONB for granular sub-category budgeting. |
| 05 | `20261002_salary_cycle_and_sub_budgets.sql` | `budgets`, `transactions` | Establishes `cycle_key`, `previous_cycle_delta`, and sub-category catalog. |
| 06 | `20261003_allow_select_sub_categories.sql` | `cost_control_sub_categories` | Grants SELECT policy for sub-category taxonomy. |
| 07 | `20261005_add_installment_plans.sql` | `installment_plans` | Tables and RLS for BNPL providers (Tabby, Tamara, bank plans). |
| 08 | `20261005_query_performance_and_indexes.sql` | Indexes | Covering and composite lookup indexes on foreign keys. |
| 09 | `20261008_add_household_payday.sql` | `households`, `users` | Adds `payday_day` (1–31, default 27). |
| 10 | `20261008_add_qr_code_raw_to_transactions.sql` | `transactions` | Adds `qr_code_raw` for ZATCA TLV payload storage. |
| 11 | `20261008_create_receipts_bucket_and_policies.sql` | Supabase Storage | Creates `receipts` bucket and access policies. |
| 12 | `20261009_fix_storage_policies_and_receipt_cleanup.sql` | Storage, triggers | Automatically removes receipt image when transaction is deleted. |
| 13 | `20261009_hardened_security_and_storage_policies.sql` | Storage, RLS | Enforces household folder path isolation on receipt images. |
| 14 | `20261010_add_household_monthly_income.sql` | `households` | Adds `monthly_income` baseline for budget ratios. |
| 15 | `20261011_household_dependents_and_subcategories.sql` | `household_dependents` | Introduces dependents (children, elderly) and sub-allocations. |
| 16 | `20261011_hybrid_category_lifecycle.sql` | `cost_control_codes` | Standard vs. custom household categories and archival flags. |
| 17 | `20261015_family_nafaqah_and_multi_roommate_settlement.sql` | `users`, `transactions` | Introduces `financial_role` and role-aware settlement columns. |
| 18 | `20261015_manual_members_and_claim_merge.sql` | `household_invites` | Placeholder members and targeted claim-on-join merging. |
| 19 | `20261018_household_memberships_and_switching.sql` | `household_memberships` | Multi-household membership and `switch_active_household` RPC. |
| 20 | `20261018_multi_source_income_and_accounts.sql` | `accounts`, `income_records` | Multi-source accounts, transfers, and append-only income ledger. |
| 21 | `20261018_membership_sync_and_shared_account_policies.sql` | Policies, triggers | Membership sync and shared pool permission rules. |
| 22 | `20261019030000_sec01_sec02_household_takeover_prevention.sql`| RPCs, invites | SEC-01/02: Prevents self-promotion; single-use expiring invites. |
| 23 | `20261019060000_sec06_private_receipts_bucket.sql` | Storage | SEC-06: Configures private storage bucket with signed URLs. |
| 24 | `20261019070000_sec07_api_quota_and_rate_limits.sql` | `api_quota` | SEC-07: Persistent API quota tracking table. |
| 25 | `20261019080000_bug02_payday_cycle_parity_and_triggers.sql` | Triggers, functions | BUG-02: Parity across SQL/Python `cycle_key` generation. |
| 26 | `20261019090000_sec05_accounts_security_and_transfers.sql` | `accounts`, RPCs | SEC-05: Atomic transfers and account balance triggers. |
| 27 | `20261019100000_sec08_round6_hardening.sql` | Core schema | SEC-08: General security and constraint hardening. |
| 28 | `20261020005000_preflight_live_alignment.sql` | Catalog alignment | Captures live schema drift prior to audit batch. |
| 29 | `20261020010000_audit_invites_rls_and_targeted_claims.sql` | `household_invites` | DB-01: RLS on invites and targeted member claims. |
| 30 | `20261020020000_audit_membership_policy_recursion.sql` | `household_memberships` | DB-02: Eliminates recursive RLS evaluation on memberships. |
| 31 | `20261020030000_audit_reallocate_budget_authz.sql` | `reallocate_budget` | DB-03: Admin-only authorization on budget reallocations. |
| 32 | `20261020040000_audit_cost_control_codes_policies.sql` | `cost_control_codes` | DB-04: Enforces tenant scoping on custom category writes. |
| 33 | `20261020050000_audit_ledger_precision_and_income_append_only.sql`| `income_records` | DB-06: `numeric(14,2)` precision; income ledger append-only. |
| 34 | `20261020060000_audit_transaction_cycle_key_integrity.sql` | `transactions` triggers | DB-08: Ensures clients cannot forge or tamper with `cycle_key`. |
| 35 | `20261020070000_audit_definer_search_path_and_household_insert.sql`| Functions | DB-09/10: Pins `search_path = public, pg_temp` on functions. |
| 36 | `20261020080000_audit_receipts_bucket_limits.sql` | Storage | DB-11: 10MB file size limit and image MIME-type whitelist. |
| 37 | `20261020090000_audit_sole_admin_account_deletion.sql` | Auth triggers | DB-12: Prevents orphaned households when sole admin deletes account. |
| 38 | `20261020100000_audit_rls_initplan_and_fk_indexes.sql` | Indexes, RLS | DB-13: InitPlan `(SELECT auth.uid())` wrap; missing FK indexes. |
| 39 | `20261020200000_remove_sms_artifacts.sql` | Schema | API-25: Purges legacy SMS columns; rejects `source = 'sms'`. |
| 40 | `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql`| RPCs, ledgers | UI-24: `spouse_reimbursements` append-only ledger and allowances. |
| 41 | `20261020400000_admin_permissions_and_co_admins.sql` | RBAC RPCs | DB-16/18: Primary admin, co-admins, creator-bound transactions. |
| 42 | `20261020500000_review_lock_financial_role.sql` | `users` | Locks `financial_role` to prevent self-escalation by members. |
| 43 | `20261020600000_e2e_helper_rpcs_and_sub_category_visibility.sql`| RPCs | Hardens helper RPCs against unauthorized global enumeration. |
| 44 | `20261020700000_fable_db_hardening.sql` | Constraints | FABLE-DB hardening: cascade rules, FK indexes, and null guards. |
| 45 | `20261020750000_installment_pay_atomic.sql` | `installment_plans` | FABLE-API-10: Atomic single-statement installment payment RPC. |
| 46 | `20261020800000_household_roles_and_nafaqah_integrity.sql` | `households` | Explicit `nafaqah_provider_user_id` and wife allowance guards. |
| 47 | `20261020900000_household_type_and_round2_fixes.sql` | `households` | Explicit `household_type` ('family' vs 'roommates') constraint. |
| 48 | `20261021000000_saudi_taxonomy_and_bnpl_schedule.sql` | Taxonomy | Saudi standard cost taxonomy (`OPEX-HOUSING`, `OPEX-DOMESTIC`, etc.). |
| 49 | `20261024000000_create_inquiries_table.sql` | `inquiries` | Persistent lead capture for VIP early access and support inquiries. |
| 50 | `20261026000000_add_savings_account_type.sql` | `accounts` | Adds `savings` type to protect emergency vaults from daily budgets. |
| 51 | `20261026120000_household_autonomous_taxonomy.sql` | Categories | Household autonomous taxonomy, template catalog, and replace RPC. |
| 52 | `20261101000000_nafaqah_wife_no_account.sql` | `transactions` | Initial CHECK constraint isolating wife-class transactions. |
| 53 | `20261101000100_nafaqah_wife_account_owner_guard.sql` | `transactions` | Upgrades CHECK to dynamic trigger `trg_enforce_wife_class_account`. |

### 3.2 Core Database Entities & Invariants

```
┌─────────────────────┐       ┌───────────────────────────┐       ┌────────────────────────┐
│     households      │1     *│   household_memberships   │*     1│         users          │
├─────────────────────┤───────├───────────────────────────┤───────├────────────────────────┤
│ id (PK)             │       │ id (PK)                   │       │ id (PK)                │
│ name                │       │ household_id (FK)         │       │ display_name           │
│ payday_day (1-31)   │       │ user_id (FK)              │       │ email                  │
│ owner_user_id (FK)  │       │ role (admin/member)       │       │ payday_day             │
│ nafaqah_provider_id │       │ financial_role            │       │ financial_role (cache) │
│ household_type      │       │ joined_at                 │       │ created_at             │
│ rollover_rule       │       └───────────────────────────┘       └────────────────────────┘
└──────────┬──────────┘
           │1
           │*
┌──────────┴──────────┐       ┌───────────────────────────┐       ┌────────────────────────┐
│      accounts       │1     *│       transactions        │*     1│        budgets         │
├─────────────────────┤───────├───────────────────────────┤───────├────────────────────────┤
│ id (PK)             │       │ id (PK)                   │       │ id (PK)                │
│ household_id (FK)   │       │ household_id (FK)         │       │ household_id (FK)      │
│ owner_user_id (FK)  │       │ account_id (FK, nullable) │       │ account_id (FK)        │
│ account_type        │       │ user_id (FK) [creator]    │       │ cycle_key (YYYY-MM)    │
│ balance numeric     │       │ amount numeric(14,2)      │       │ category_code          │
│ is_shared_pool bool │       │ cycle_key (trigger-set)   │       │ allocated_amount       │
│ is_archived bool    │       │ nafaqah_class             │       │ spent_amount (trigger) │
│ currency (SAR default)      │ nafaqah_spouse_id (FK)    │       │ sub_allocations JSONB  │
└─────────────────────┘       └───────────────────────────┘       └────────────────────────┘
```

### 3.3 Critical Database Triggers & Single Sources of Truth (SSOT)

1. **Cycle Key Integrity (`trg_populate_transaction_cycle_key`):**
   - Attached to `transactions` ON INSERT OR UPDATE of `timestamp`, `household_id`.
   - Derives `cycle_key` automatically via `public.get_saudi_cycle_for_timestamp(NEW.timestamp, h.payday_day)` where `h.id = NEW.household_id`.
   - **Security Invariant:** Client-supplied `cycle_key` values are overwritten unconditionally. Clients cannot forge cycle keys.
2. **Account Balance SSOT (`trg_update_account_balance_on_transaction`):**
   - Attached to `transactions` ON INSERT, UPDATE, OR DELETE.
   - On INSERT: decrements `accounts.balance = balance - NEW.amount` for `NEW.account_id`.
   - On DELETE: increments `accounts.balance = balance + OLD.amount` for `OLD.account_id`.
   - On UPDATE: atomically reverses old amount and applies new amount.
   - **Architectural Rule:** Neither Python nor Flutter ever writes `accounts.balance` directly for transaction activity. Triggers are the sole authority.
3. **Wife Account Owner & Debit Isolation Guard (`trg_enforce_wife_class_account`):**
   - Attached to `transactions` BEFORE INSERT OR UPDATE of `account_id`, `nafaqah_class`, `nafaqah_spouse_id`.
   - Rule: When `nafaqah_class IN ('wife_personal', 'wife_reimbursable')` and `account_id IS NOT NULL`, the target account **MUST** be owned by the designated wife (`a.owner_user_id = NEW.nafaqah_spouse_id`), must belong to the household, must not be archived, and **CANNOT BE A SHARED POOL** (`a.is_shared_pool = false`).
   - If an unauthorized account is provided, raises `check_violation` with constraint `transactions_wife_class_no_account`.
4. **Budget Spent Aggregator (`trg_adjust_budget_spent`):**
   - Recomputes `budgets.spent_amount` for the corresponding `(household_id, cycle_key, category_code)`.
   - **Compliance Filter:** Transactions with `is_settlement = true` or `nafaqah_class = 'wife_personal'` are strictly excluded from budget category spend.
5. **Wife Allowance Overpayment Advisory Lock (`record_spouse_reimbursement` RPC):**
   - Acquires transaction-level lock `PERFORM pg_advisory_xact_lock(hashtext('reimburse_' || p_household_id::text))`.
   - Calculates total reimbursable debt from `transactions` minus already repaid amounts in `spouse_reimbursements`.
   - Rejects any payment that exceeds outstanding debt (`RAISE EXCEPTION 'ledger_would_be_overpaid'`).

### 3.4 Row Level Security (RLS) Multi-Tenancy Architecture

- **100% RLS Coverage:** Enabled on every table in the `public` schema (`supabase/tests/14_audit_catalog_guardrails.sql` tests this via `information_schema.tables`).
- **InitPlan Optimization (DB-13):** Every tenant policy wraps the helper in a `SELECT` statement:
  ```sql
  household_id = (SELECT public.get_auth_user_household_id())
  ```
  This forces PostgreSQL query planner to execute the function once per query execution (InitPlan) rather than once per row evaluated (SubPlan), improving query performance by orders of magnitude.
- **Account Visibility & Debit Rules:**
  - Personal accounts: visible only to owner (`owner_user_id = (SELECT auth.uid())`).
  - Shared pools: visible to all household members (`is_shared_pool = true AND household_id = (SELECT public.get_auth_user_household_id())`).
  - Shared pool debits: restricted strictly to users with `role = 'admin'` via `assert_can_debit_account` in FastAPI and RPC guards.
- **Function Hardening:**
  - All `SECURITY DEFINER` functions enforce `SET search_path = public, pg_temp` to prevent malicious search-path hijacking.
  - `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon;` is applied to all sensitive business RPCs.

---

## 4. Saudi Fintech & Islamic Household Finance Operating Engine

### 4.1 Saudi Payday Cycle Arithmetic

The Saudi salary cycle is the foundational temporal unit of the system.
- **Cycle Identification (`cycle_key`, `YYYY-MM`):**
  - Configured per household in `households.payday_day` (range 1–31, default 27).
  - Calculated on the **Asia/Riyadh** calendar date.
  - If a month has fewer days than `payday_day` (e.g. 31st in February or April), it is clamped to the month's final day.
  - **Naming Convention:**
    - If `payday_day > 15`: The cycle is named after the month in which it **ends**. For example, with payday 27, the period spanning 27 October 2026 to 26 November 2026 is designated `2026-11`.
    - If `payday_day <= 15`: The cycle is named after the month in which it **starts**.
    - If `payday_day = 1`: The cycle corresponds exactly to the calendar month.
- **Cycle Rollover Handling (`households.rollover_rule`):**
  1. `send_to_savings` (Default): Leftover funds at the end of the salary cycle are swept into `households.accumulated_savings`. Category allocations reset fresh for the new cycle.
  2. `rollover_to_categories`: Unspent positive/negative deltas are rolled forward into the same categories in the new cycle (`previous_cycle_delta`).
  3. `fresh_start`: Zero carryover; allocations reset to baseline.

### 4.2 ZATCA Phase 2 E-Invoicing Engine

The mobile client includes a native, on-device TLV decoder (`flutter_app/lib/services/zatca_decoder.dart`) conforming to ZATCA Phase 2 specifications:

```
┌────────────────────────────────────────────────────────┐
│                ZATCA Phase 2 TLV Barcode               │
├─────┬──────────────────────────┬───────────────────────┤
│ Tag │ Meaning                  │ Data Type / Rule      │
├─────┼──────────────────────────┼───────────────────────┤
│ 01  │ Seller Legal Name        │ UTF-8 String          │
│ 02  │ VAT Registration Number  │ 15 Digits (Starts &   │
│     │                          │ Ends with '3')        │
│ 03  │ Invoice Timestamp        │ ISO 8601 String       │
│ 04  │ Invoice Total (with VAT) │ Decimal String (SAR)  │
│ 05  │ VAT Total Amount         │ Decimal String (15%)  │
└─────┴──────────────────────────┴───────────────────────┘
```
- **One-Model-Call Preview Token:**
  - Receipt scans and conversational chat inputs generate an ephemeral preview token signed with `PREVIEW_TOKEN_SECRET` (HMAC-SHA256, 15-minute TTL).
  - The token encapsulates extracted merchant, total, line items, and VAT.
  - Upon user confirmation, the client presents the `preview_token` to `POST /agent/chat-transaction` or `POST /agent/scan-receipt`. The server verifies the cryptographic signature and saves the record without issuing a second LLM inference call.
- **De-duplication Protection:**
  - Receipts generate a SHA-256 fingerprint combining merchant name, total halalas, and timestamp. Matches prompt the `DuplicateResolutionCard` to avoid double-charging.

### 4.3 Islamic Family Finance (Nafaqah) vs. Roommate Living Groups

The platform automatically configures its operating engine based on `households.household_type` ('family' vs 'roommates') and the presence of `financial_role = 'spouse'`:

#### The 4 Golden Nafaqah Rules (Family Mode)
1. **Nafaqah is Exclusively on the Husband:** Shared living expenses (rent, groceries, utilities, school tuition, domestic staff, family health) are the husband's sole legal responsibility. Automatic 50/50 splits or spousal percentage ratios are **strictly prohibited** across the database, APIs, mobile UI, and PDF statements.
2. **Wife Pays Shared Expense $\to$ Reimbursable Debt:** If the wife pays for shared family necessities from her personal funds:
   - The transaction is recorded with `transactions.nafaqah_class = 'wife_reimbursable'` and `nafaqah_spouse_id = <wife_user_id>`.
   - It is recorded as debt owed by the husband.
   - The wife or husband views the outstanding balance on the Family Reimbursement Card.
   - Repayments are logged via the append-only `spouse_reimbursements` ledger. Overpayment beyond outstanding debt is rejected under database lock.
3. **Wife Buys Personal Items $\to$ Allowance Deduction:** If the wife buys personal items for herself:
   - Tagged as `transactions.nafaqah_class = 'wife_personal'`.
   - This is NOT debt and does NOT hit category budgets.
   - It is charged directly against her personal monthly allowance ("مصروفها") in `member_allowances` for that cycle.
   - The allowance is configured exclusively by the husband/admin (the wife cannot set her own allowance). Overspending reflects as a negative remainder and is never blocked.
   - **Account Isolation:** Wife-class transactions may only debit her own personal non-shared account or remain unlinked (`trg_enforce_wife_class_account`).
4. **Husband Pays Shared / Personal $\to$ Standard Expense:** Normal household expenditure with no debt or special classification. Tabarru' (voluntary wife contribution without reimbursement) requires an explicit opt-in flag.

#### Roommate Living Mode (Shared Flats)
- In bachelor/student households (`household_type = 'roommates'`), shared expenses (rent, cleaning, fiber internet) use the Multi-Roommate Settlement Engine.
- Deploys graph debt simplification (`settlement_engine.simplify_debts`), converting complex $N \times N$ pairwise debts into the minimal set of bilateral settlements, preventing circular cash transfers.
- Generates 1-tap formatted settlement summaries for WhatsApp.

### 4.4 Operating Cash & Zero-Based Balance Ledger SSOT

#### The Operating Cash Formula SSOT (`FORMULA_VERDICT.md`)
A common architectural error in budgeting systems is subtracting Category Spent from Live Cash. Because Budget Tracker's database trigger `trg_update_account_balance_on_transaction` **already decrements `accounts.balance` on write**, subtracting spent amounts again constitutes double-deduction.

The canonical formulas enforced across Flutter and PostgreSQL are:

$$\text{Liquid Balance} = \sum \text{accounts.balance} \quad \Big[\text{where } \text{isOperatingPool} = \text{true}, \text{currency} = \text{'SAR'}, \text{isArchived} = \text{false}\Big]$$

$$\text{Commitments} = \sum (\text{amount\_due} - \text{amount\_paid}) \quad \Big[\text{unpaid bills and installments due } \le \text{cycle end}\Big]$$

$$\mathbf{Operating\ Cash} = \mathbf{Liquid\ Balance} - \mathbf{Commitments}$$

> [!IMPORTANT]
> **SSOT Rule:** Category Spent belongs exclusively to the **budget allocation engine** (Planned vs. Actual). It NEVER enters the **operating cash headroom formula**.

- **Zero-Based Budget Invariant:**
  - Total committed category budgets for an account must never exceed that account's actual liquid balance:
  $$\text{Capacity Margin} = \text{Account Balance} - \sum \text{Allocated Budgets}$$
  - Surfaced through dynamic HUD indicators:
    - `🟢 Zero-Based (100% Allocated)`
    - `🔵 Surplus Buffer (+SAR X.XX)`
    - `🔴 Deficit Shortfall (-SAR X.XX)` with 1-tap `[⚡ Quick Transfer]` pre-filled from the surplus account.

---

## 5. UI/UX Design System & Client Ecosystem

### 5.1 Mobile HUD Design System Evolution: Velvet Burgundy

The mobile app was originally drafted under the *Sovereign OS & Iced Ocean* aesthetic and subsequently upgraded to the **Velvet Burgundy Master Design System** (`flutter_app/lib/core/theme/velvet_burgundy_theme.dart`). 

To preserve architectural integrity across all views, `flutter_app/lib/theme/app_themes.dart` provides an authoritative compatibility layer mapping all legacy Sovereign OS tokens directly into Velvet Burgundy tokens:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Velvet Burgundy HUD Color Palette                      │
├──────────────────────────┬──────────────────────────┬───────────────────────┤
│ Token Name               │ Hex Code                 │ Semantic Purpose      │
├──────────────────────────┼──────────────────────────┼───────────────────────┤
│ canvasDark (Obsidian)    │ #110509                  │ Main Scaffold Dark    │
│ surfaceDark (Plum Card)  │ #1E0B12                  │ 3D Glass Surface Dark │
│ canvasLight (Alabaster)  │ #F8F3F5                  │ Main Scaffold Light   │
│ surfaceLight (Ceramic)   │ #FFFFFF                  │ 3D Ceramic Card Light │
│ primaryLight (Burgundy)  │ #4A0E1E                  │ Primary Brand Ink     │
│ roseGold / roseGoldGlow  │ #E598B0 / #F0A3BC        │ Primary Glow Accent   │
│ emeraldSafe              │ #10B981                  │ Surplus / Safe State  │
│ amberCaution             │ #F59E0B                  │ Pending / Due Warning │
│ coralDanger              │ #F43F5E                  │ Deficit / Danger      │
└──────────────────────────┴──────────────────────────┴───────────────────────┘
```

- **Elevation & Glassmorphism:** Subtle 1px borders using `Colors.white.withValues(alpha: 0.08)` in dark mode and `Color(0xFFF2DCE2)` in light mode. Strictly no legacy `withOpacity()`.
- **Typography:** Google Fonts pairing `Outfit` (Latin figures and English typography) with `Cairo` and `Tajawal` (Arabic typography).

### 5.2 Floating Dock & Speed Dial FAB

Bottom navigation centers around an elevated floating dock featuring the speed-dial Floating Action Button (FAB) executing the 3 core financial actions:
1. **Add Expense:** Opens `ManualExpenseSheet` with automatic role-aware payer tagging.
2. **Record Income:** Opens `RecordIncomeSheet` for salary, overtime, bonus, or gig receipts.
3. **Transfer Funds:** Opens `AccountTransferSheet` for atomic intra-household liquidity rebalancing.

Receipt scanning and voice dictation are housed directly on the top Tactical Action Bar and `DashboardActionSheet`.

### 5.3 Privacy Eye Masking

To ensure comfort when using the application in public spaces (airports, cafes, offices), a global Privacy Eye Toggle instantly masks:
- Net worth and total liquidity metrics.
- Individual bank and wallet account balances.
- Surplus buffer and deficit shortfall figures in status pills and cover buttons (`•••••• SAR`).

### 5.4 Trilingual Arabic-First & RTL Architecture

- **Primary Locale:** Arabic (`ar`) with native RTL (Right-to-Left) directional flow. English (`en`) and Urdu (`ur`) are first-class supported locales.
- **Zero Hardcoding Rule:** No user-facing text is permitted in code. All strings are accessed through `context.tr('key')` or `context.trArgs('key', {...})` via `flutter_app/lib/l10n/app_localizations.dart`.
- **RTL Directionality:** All paddings use `EdgeInsetsDirectional.only()`. Chevron navigation icons mirror naturally without manual ternary flips that cause double-mirroring.

### 5.5 Daylight Coastal Web Landing Page

The web presence (`web_app/`) is an ultra-fast, responsive landing page using the **Daylight Coastal Exploding Flow** aesthetic (crisp marine teal on fresh white). It features:
- Interactive Payday Cycle Calculator: Users choose their payday (1–31) and view real-time countdowns, active cycle dates, and sample budget allocations.
- Real Copy & AI Disclosure: Explicitly discloses Google Gemini as the underlying OCR and language intelligence engine.
- VIP Early Access Form: Connects directly to `POST /public/inquiries` for lead acquisition.

---

## 6. Security, Privacy & Zero-SMS Hardening

### 6.1 Zero-SMS Policy

Budget Tracker enforces a zero-tolerance policy against SMS interception:
- Android manifest strictly excludes `android.permission.RECEIVE_SMS` and `android.permission.READ_SMS`.
- No background broadcast receivers or native SMS listening services exist in the codebase.
- The database schema rejects any transaction with `source = 'sms'` (`supabase/migrations/20261020200000_remove_sms_artifacts.sql`).
- All financial inputs are verified and confirmed by the user.

### 6.2 API Key Segregation & Storage Hardening

1. **Publishable / Anon Key (`SUPABASE_PUBLISHABLE_KEY`):**
   - Safe for compilation into client binaries.
   - Constrained 100% by PostgreSQL RLS.
2. **Secret / Service-Role Key (`SUPABASE_SECRET_KEY`):**
   - Strictly confined to backend environment variables (`ai_service`).
   - Flutter app explicitly checks for and refuses to boot if an `sb_secret_` or service-role key is detected in client configuration.
3. **Storage Bucket Hardening:**
   - The `receipts` Supabase Storage bucket is marked private.
   - Folder structure enforces `/receipts/{household_id}/{transaction_id}.jpg`. RLS ensures only members of the specified household can download receipt images.
   - Size limit: 10MB. Whitelisted MIME types: `image/jpeg`, `image/png`, `image/webp`.

### 6.3 Authentication & Request Signatures

- **JWT Validation:** Every authenticated endpoint verifies the caller's Supabase JWT via asymmetric JWKS validation, enforcing `exp`, `iat`, `sub`, and issuer checks.
- **Signature Defense-in-Depth (`X-Signature`):** Client requests sign payloads using HMAC-SHA256 with `WEBHOOK_SECRET`. When a valid JWT is present, signature discrepancies are logged without failing the request (preventing service disruption during secret rotation on mobile builds). Genuine webhook routes without JWT mandate a valid signature.
- **Firewall Middleware:** Reverse proxy endpoints enforce constant-time token comparison.

---

## 7. Comprehensive Codebase Audit Findings & Remediation Matrix

In November 2026, an exhaustive multi-pass audit of the entire codebase was conducted across four specialized passes. Below is the authoritative register of findings, root causes, and remediation statuses:

### 7.1 Database & Migrations Security (Pass 1) [Audited by: Claude Opus 5.5 high | Executed by: code-implementer (Claude Opus 5.5 high)]

| Audit ID | Severity | Affected Component | Finding Description & Vulnerability | Remediation Status |
|---|---|---|---|---|
| **S-1** | CRITICAL | `schema.sql` $\to$ `reallocate_budget` | Unprotected `SECURITY DEFINER` function without user or household authorization allowed any user to alter budget allocations across any household. | **RESOLVED:** Dropped in `20261020030000_audit_reallocate_budget_authz.sql` and replaced with admin-only RPC with actor validation. |
| **S-2** | CRITICAL | `20261011_hybrid_category_lifecycle.sql` | `cost_control_codes` INSERT/UPDATE policies checked only `household_id IS NOT NULL`, allowing cross-tenant category pollution. | **RESOLVED:** Replaced in `20261020040000_audit_cost_control_codes_policies.sql` with strict household scoping. |
| **S-3** | CRITICAL | `20261019080000_bug02...` | Trigger on `cycle_key` fired only on `UPDATE OF timestamp, household_id`. A direct `UPDATE transactions SET cycle_key = '...'` could forge cycle keys. | **RESOLVED:** Enforced unconditional trigger overwrite in `20261020060000_audit_transaction_cycle_key_integrity.sql`. |
| **S-4** | CRITICAL | `20261018_household_memberships...` | `memberships_admin_manage` policy had self-referencing SELECT causing potential infinite recursion and allowed direct client inserts. | **RESOLVED:** Dropped in `20261020020000_audit_membership_policy_recursion.sql`; membership mutations restricted to RPCs. |
| **S-5** | CRITICAL | `20261019030000` / `20261019100000` | Any member could update or delete other members' transactions; creator `user_id` was not bound at insert. | **RESOLVED:** Bound `user_id = auth.uid()` at insert and enforced creator-or-admin edit policy in `20261020400000`. |
| **S-6** | HIGH | `20261019030000` | Client could update `users.financial_role` directly, allowing members to force or escape family mode arbitrarily. | **RESOLVED:** Column permissions revoked in `20261020500000_review_lock_financial_role.sql`. |
| **S-7** | HIGH | `20261019090000` | Non-admin members could debit shared pool accounts through direct transfers or transaction balance triggers. | **RESOLVED:** Restricted pool debits to admins in `20261020400000` and `assert_can_debit_account`. |
| **S-8** | HIGH | `20261019030000` | Members could read plaintext household invite codes. | **RESOLVED:** Restricted invite SELECT policies to admins only in `20261020010000_audit_invites_rls_and_targeted_claims.sql`. |
| **S-9** | HIGH | `20261020010000` | Existing members could claim invites to their own household; sync trigger demoted co-admins on join. | **RESOLVED:** Added membership checks and safe update logic in `20261020800000_household_roles_and_nafaqah_integrity.sql`. |
| **S-10** | HIGH | `20261019090000` | Direct client insert to `income_records` bypassed account ownership checks. | **RESOLVED:** Made `income_records` append-only via RPC and enforced account ownership in `20261020050000`. |
| **S-11** | HIGH | `20261011_household_dependents...` | Members could update `linked_user_id` on dependents, spoofing claim-merge. | **RESOLVED:** Restricted dependent updates to admins in `20261020010000`. |
| **S-12** | MEDIUM | `20261005_add_installment_plans.sql` | Unscoped RLS allowed any member to delete installment plans. | **RESOLVED:** Enforced household and creator scoping in `20261020700000_fable_db_hardening.sql`. |
| **S-14** | MEDIUM | `20261019060000` | Receipts storage bucket lacked file size and MIME-type constraints. | **RESOLVED:** Applied 10MB limit and MIME whitelist in `20261020080000_audit_receipts_bucket_limits.sql`. |
| **S-17** | LOW | `get_saudi_cycle_for_timestamp` | Function mutable search path warning. | **RESOLVED:** Pinned `search_path = public, pg_temp` in `20261020070000`. |

### 7.2 AI Microservice Backend Architecture (Pass 2) [Audited by: Claude Opus 5.5 high | Executed by: code-implementer (Claude Opus 5.5 high)]

| Audit ID | Severity | Affected Route / Function | Finding Description & Vulnerability | Remediation Status |
|---|---|---|---|---|
| **C1** | CRITICAL | `routes/chat.py`, `routes/receipts.py`, `supabase_client.py` | **Cross-Tenant Account IDOR:** Client-supplied `account_id` was not validated against caller tenancy or ownership, allowing users to debit foreign accounts. | **RESOLVED:** Added `assert_can_debit_account` in `household_permissions.py` validating household tenancy and admin rights. |
| **C2** | CRITICAL | `pdf_statement_generator.py` | Statement printed `"50 / 50 Shared Split"` and computed spousal percentages in family mode, violating Rule 02 §3.1. | **RESOLVED:** Segregated statement templates; family statements omit spousal split metrics and show Nafaqah ledger. |
| **H1** | HIGH | `supabase_client.insert_transaction` | Automatic account fallback defaulted to shared pool or first account, debiting shared pool without admin privilege. Python balance sync clamped deficits to 0. | **RESOLVED:** Deleted Python balance mutation; fallback requires caller-owned account; trigger handles balance updates. |
| **H2** | HIGH | `routes/budgets.py` | Non-admin members could pass query parameter `payday_day` and forge budget cycle forecasts. | **RESOLVED:** Stripped client override; payday is read strictly from household configuration in database. |
| **H3** | HIGH | `salary_cycle.get_cycle_breakdown` | Global unscoped query on `cost_control_codes` leaked custom categories across households. | **RESOLVED:** Scoped queries strictly to system codes (`household_id IS NULL`) and active household custom codes. |
| **H4** | HIGH | `routes/budgets.py` | Installment plan PUT endpoint did not verify caller permission on original transaction. | **RESOLVED:** Enforced `assert_can_modify_transaction` on plan updates. |
| **H5** | HIGH | `supabase_client.ensure_household_cycle_budgets` | Concurrency race condition on first-of-cycle budget generation caused duplicate rows and double savings sweeps. | **RESOLVED:** Replaced with atomic PostgreSQL RPC using transactional advisory locks. |
| **H6** | HIGH | `salary_cycle.rename_sub_category` | Sub-category override allowed cross-tenant keyword injection under shared parent codes. | **RESOLVED:** Isolated sub-category taxonomy scoping to `owner_household_id`. |
| **H7** | HIGH | `chat_parser.process_chat_transaction` | Previews (`preview_only=True`) with enrichment wrote item modifications to transaction rows. | **RESOLVED:** Gated enrichment writes strictly to commit phase (`preview_only=False`). |
| **M1** | MEDIUM | Multiple budget modules | Floating point math used for monetary amounts, risking halala rounding drift. | **RESOLVED:** Standardized on integer halalas / `Decimal` arithmetic. |
| **M2** | MEDIUM | `salary_cycle.py` | UTC vs. Asia/Riyadh timezone boundary caused transactions within 3 hours of midnight to double-count across cycles. | **RESOLVED:** Standardized all boundary parsing on explicit Asia/Riyadh calendar dates. |

### 7.3 Flutter Mobile App Architecture (Pass 3) [Audited by: Claude Opus 5.5 high | Executed by: code-implementer (Claude Opus 5.5 high)]

| Audit ID | Severity | Affected Provider / Client | Finding Description & Vulnerability | Remediation Status |
|---|---|---|---|---|
| **S1** | HIGH | API Clients (`ChatApiClient`, `ReceiptApiClient`, etc.) | Client sent `user_id` in request payloads, creating potential IDOR regression vectors. | **RESOLVED:** Stripped body `user_id`; backend resolves acting user strictly from verified Bearer JWT. |
| **S2** | HIGH | `TransactionProvider.deleteTransaction` | Treats 0 rows deleted (due to RLS rejection) as success and removes item from local UI. | **RESOLVED:** Checks returned rows; if empty, sets `lastWriteDenied = true` and rolls back local UI state. |
| **S3** | HIGH | `AccountProvider.deductExpense` | Defaulted target to shared pool for non-admins and updated balance via raw client write. | **RESOLVED:** Filtered targets by ownership; removed client-side balance write in favor of database triggers. |
| **N1** | CRITICAL | `BudgetApiClient.fetchPartnerSettlement` | Defaulted `splitRatio = 0.5` in family mode. | **RESOLVED:** Made `splitRatio` required only for roommates mode; throws client exception in family mode. |
| **N2** | HIGH | `RecurringBillsProvider.buildBillPaymentRow` | Paid bills by wife lacked `nafaqah_class = 'wife_reimbursable'`, losing debt tracking. | **RESOLVED:** Wired `NafaqahPreview` and role prompt to bill payment creation. |
| **N4** | HIGH | `Transaction.toMap` | Undo action erased `nafaqah_class` and `nafaqah_spouse_id`. | **RESOLVED:** Added full Nafaqah attribute serialization to `toMap()`. |
| **N6** | HIGH | `BudgetApiClient.fetchHouseholdPayday` | Returned fallback `27` on network failure, overwriting real payday in local cache. | **RESOLVED:** Throws `ApiRequestException`; cache retains previous valid value on failure. |
| **N7** | HIGH | `manual_expense_row.dart` | Client derived and sent `cycle_key`. | **RESOLVED:** Removed client `cycle_key` derivation; database trigger populates it authoritatively. |
| **Z1** | HIGH | `AccountProvider.deductExpense` | Clamped balance to 0, hiding deficit alerts. | **RESOLVED:** Removed clamp; deficits propagate to reveal `🔴 Deficit Shortfall`. |
| **Locale** | MEDIUM | `LocaleProvider` | Defaulted to English instead of Arabic. | **RESOLVED:** Reordered locales; Arabic (`ar`) is default initial state. |

### 7.4 Cross-Cutting Compliance & UI System (Pass 4) [Audited by: Claude Opus 5.5 high | Executed by: code-implementer (Claude Opus 5.5 high)]

| Audit ID | Severity | Affected Widget / File | Finding Description & Vulnerability | Remediation Status |
|---|---|---|---|---|
| **Theme** | HIGH | `theme/app_themes.dart` | Theme tokens aliased to Velvet Burgundy without rule update, creating documentation discrepancy. | **RESOLVED:** Formalized Velvet Burgundy design system with backward-compatible token bridges in Master Details. |
| **S1** | CRITICAL | `rebalance_budget_sheet.dart` | Widget executed non-atomic loop of client updates to `budgets` table directly. | **RESOLVED:** Migrated to atomic `rebalance_budgets` RPC with admin validation. |
| **S2/S3** | HIGH | `add_edit_account_dialog.dart`, `reconcile_balance_dialog.dart` | Non-admin members could edit or reconcile shared pool balances. | **RESOLVED:** Gated controls via `HouseholdRoleProvider`; non-admins are shown disabled states. |
| **Zero-Based** | HIGH | `computeProportionalRebalance` | Floating-point rounding resulted in allocation totals exceeding target by halalas. | **RESOLVED:** Standardized on integer halala flooring with remainder allocation. |
| **Currency** | HIGH | `accounts_summary_card.dart` | Summed mixed currencies (SAR, USD, USDT) into a single total labelled SAR. | **RESOLVED:** Restricts total liquidity to SAR accounts; renders non-SAR assets in distinct currency pills. |
| **Privacy** | HIGH | `account_card.dart` | Privacy eye toggle masked balance digits but leaked amounts in surplus/deficit status badges. | **RESOLVED:** Status badges and action buttons mask amounts (`•••••• SAR`) when privacy eye is active. |
| **Speed Dial** | HIGH | `app_speed_dial_fab.dart` | Speed dial offered Scan/Voice/Manual instead of mandated Add Expense / Record Income / Transfer Funds. | **RESOLVED:** Reconfigured speed dial to 3 primary financial actions. |

### 7.5 Lead Architect Audit & Operating Cash SSOT Implementation (Branch feat/provider-sot-operating-cash) [Audited by: gemini-argon-high | Validated by: Claude Opus 5.5 batch | Executed by: code-implementer (Gemini 3.8 Flash High)]

Following the completion of Passes 1–4, an external Lead Architect audit was executed by `gemini-argon-high` on branch `feat/provider-sot-operating-cash` (@ commit `af353b8`). The auditor evaluated the full stack against Rules 01–06 and identified 6 Critical/High issues, returning an initial verdict of `REVISE`.

In strict adherence to the project governance framework, these 6 findings were submitted to **Claude Opus 5.5** in batch mode (`msgbatch_01JUUsT4hTDjkwYNtU3QL69N`, `docs/review/task_argon_review.md`). Opus produced an authoritative architectural verdict and surgical execution plan (`docs/review/OPUS_PLAN.md`): validating the core architectural intent, rejecting dangerous instructions (such as client-side `cycle_key` forging and direct agent mutations on the live database), and mathematically locking the **Operating Cash & Provider Single Source of Truth (SSOT)**.

All 6 issues were implemented under strict Test-Driven Development (TDD) by `code-implementer (Gemini 3.8 Flash High)`, verified with 0 analyzer issues and 100% test pass rate across all suites.

#### The Operating Cash & Provider SSOT Architecture

The Operating Cash SSOT eliminates double-deduction while maintaining real-time liquidity and commitments visibility across all client and backend layers:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        CENTRAL OPERATING CASH SSOT ARCHITECTURE                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│   POSTGRESQL DATABASE TRIGGER                                                          │
│   ┌─────────────────────────────────────────────────────────┐                          │
│   │ trg_update_account_balance_on_transaction               │                          │
│   │ • On expense insert/update/delete:                      │                          │
│   │   Atomically decrements accounts.balance                │                          │
│   │ • Triggers are the SOLE authority for account balances  │                          │
│   └────────────────────────────┬────────────────────────────┘                          │
│                                │                                                       │
│                                ▼                                                       │
│   ACCOUNT PROVIDER & DOMAIN ENGINE                                                     │
│   ┌─────────────────────────────────────────────────────────┐                          │
│   │ AccountProvider (Central State Authority)               │                          │
│   │ • Reconciles unlinked expenses sequentially             │                          │
│   │ • Computes immutable OperatingCashSnapshot:             │                          │
│   │   - liquidBalance:      Σ SAR operating accounts balance│                          │
│   │   - pendingCommitments: Σ unpaid bills & BNPL in cycle  │                          │
│   │   - operatingCash:      liquidBalance - commitments     │                          │
│   │   - capacityMargin:     liquidBalance - allocatedBudgets│                          │
│   └────────────────────────────┬────────────────────────────┘                          │
│                                │                                                       │
│            ┌───────────────────┼───────────────────┐                                   │
│            ▼                   ▼                   ▼                                   │
│   BUDGET HERO CARD    BUDGET MANAGEMENT   ACCOUNTS OVERVIEW                            │
│   ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐                          │
│   │ • liquidBalance │ │ • Row 2:        │ │ • Net Worth     │                          │
│   │ • afterCommit-  │ │   liquidBalance │ │ • SAR Operating │                          │
│   │   ments SSOT    │ │ • Fallback:     │ │   Pool SSOT     │                          │
│   │ • safeDaily     │ │   liquidBalance │ │ • Parity with   │                          │
│   │   pacing        │ │   + debitedSpend│ │   Dashboard HUD │                          │
│   └─────────────────┘ └─────────────────┘ └─────────────────┘                          │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

1. **`OperatingCashSnapshot` & `OperatingCashCalculator` (`flutter_app/lib/models/operating_cash.dart`):**
   - Pure domain models holding verified financial state.
   - Calculates `liquidBalance` strictly from non-archived, SAR-denominated operating pool accounts (`isOperatingPool = true`).
   - Aggregates `pendingCommitments` as unpaid recurring bills and active BNPL installments due on or before cycle end.
   - Derives `operatingCash = liquidBalance - pendingCommitments`.
   - Exposes `capacityMargin = liquidBalance - totalAllocatedBudgets` for zero-based allocation validation.
2. **`AccountProvider` (`flutter_app/lib/providers/account_provider.dart`):**
   - Central provider holding accounts and commitments state.
   - Instantiates and broadcasts `OperatingCashSnapshot` reactively to all UI components upon any balance, account, or commitment mutation.
3. **`BudgetHeroCard` (`flutter_app/lib/widgets/dashboard/budget_hero_card.dart`):**
   - Primary dashboard financial HUD.
   - Bound to `snapshot.liquidBalance` for gross available cash and `PaydayOutlook.afterCommitments` for commitments-adjusted cash headroom and daily spend pacing (`safeDaily`).
4. **`BudgetManagementScreen` (`flutter_app/lib/screens/home/budget_management_screen.dart`):**
   - Row 2 (`displayOperatingCash`) displays `snapshot.liquidBalance` when in the active cycle with loaded accounts, preventing double-deduction of bill categories (`Utilities & Bills`).
   - Fallback cycle funding uses `snapshot.liquidBalance + householdDebitedSpend` (filtering out wife-class transactions).
5. **`AccountsOverviewScreen` (`flutter_app/lib/screens/accounts/accounts_overview_screen.dart`):**
   - Bound directly to `AccountProvider` operating cash snapshot for complete balance parity across views.

#### Lead Architect Audit Register (Issues CRITICAL-01 through HIGH-06)

| Audit ID | Severity | Affected Component / Files | Finding Description & Root Cause | Technical Remediation & Validation | Remediation Status |
|---|---|---|---|---|---|
| **CRITICAL-01** | CRITICAL | `BudgetHeroCard`, `PaydayOutlook`<br>• `payday_outlook.dart`<br>• `budget_hero_card.dart` | `BudgetHeroCard` passed `pendingCommitments: 0` and pre-subtracted `operatingCash` into `PaydayOutlook.compute`. This corrupted `outlook.safeDaily` calculation whenever monthly income was configured, and caused double-subtraction or misalignment between `outlook.left` and the commitments tip pill. | **Opus Validated Fix:** Added `final double afterCommitments;` as SSOT field directly on `PaydayOutlook`. Bound `safeDaily` strictly to `(daysLeft > 0 && afterCommitments > 0) ? afterCommitments / daysLeft : 0.0`. Bound `BudgetHeroCard` to pass `snapshot.liquidBalance` and `effectiveCommitments` into `compute()`, and bound `_HeroCommitmentsTip` to `outlook.afterCommitments`. | **RESOLVED** |
| **CRITICAL-02** | CRITICAL | `BudgetManagementScreen`, `DashboardScreen`<br>• `budget_management_screen.dart`<br>• `dashboard_screen.dart` | Row 2 (`displayOperatingCash`) on `BudgetManagementScreen` was bound to `snapshot.operatingCash` (`liquidBalance - commitments`). Because bills are already budgeted as categories (`Utilities & Bills`), subtracting commitments double-counted bills and caused Row 2 to diverge from `AccountsOverviewScreen` and `BudgetHeroCard`. Unfunded fallback `totalSpent` included non-household wife transactions. | **Opus Validated Fix:** Extracted pure helper functions `resolveDisplayOperatingCash`, `householdDebitedSpend`, and `resolveCycleFunding`. Bound Row 2 `displayOperatingCash` to `snapshot.liquidBalance`. For fallback funding when `verifiedCycleIncome <= 0`, computed `snapshot.liquidBalance + householdDebitedSpend`, strictly filtering out `wife_personal` and `wife_reimbursable` transactions which never debit household accounts. | **RESOLVED** |
| **CRITICAL-03** | CRITICAL | `BudgetManagementScreen`, PostgreSQL Check<br>• `budget_management_screen.dart`<br>• `33_prior_spend_manual_row.sql` | In `buildPriorSpendRow`, setting `source = 'prior_adjustment'` violated PostgreSQL check constraint `transactions_source_check` (`source IN ('chat', 'receipt_scan', 'manual')`, SQLSTATE 23514). Also, client-side derivation of `cycle_key` violated Rule 02 §1 (authoritative trigger stamping). | **Opus Validated Fix:** Retained `source = 'manual'` and `account_id = null` (which are already excluded from auto-reconciliation in `AccountService`). Stamped transaction timestamp at cycle start noon Asia/Riyadh (09:00 UTC) so `trg_populate_transaction_cycle_key` derives `cycle_key` authoritatively. Stripped client `cycle_key`. Created SQL regression proof test `supabase/tests/33_prior_spend_manual_row.sql`. | **RESOLVED** |
| **CRITICAL-04** | CRITICAL | `ai_service/supabase_client.py`, `chat_parser.py`, `receipt_scanner.py`, `chat_entry_screen.dart`<br>• `post_commit_sync.dart`<br>• `account_service.dart` | Unlinked chat and receipt transactions logged without explicit `account_id` inserted with `None`, failing to fire database balance triggers. In Flutter, `_refreshGlobalProviders()` executed before `reconcileUnlinkedTransactions` completed. Client auto-reconciliation lacked guard against linking wife transactions to shared pool. | **Opus Validated Fix:** Implemented `resolve_default_debitable_account(...)` in backend validating category budgets, caller permissions, and single active debitable account (returns `None` for wife-class expenses or unauthenticated actors). Wired resolver into `chat_parser.py` and `receipt_scanner.py`. Created sequential synchronization helper `reconcileThenRefresh` in `post_commit_sync.dart` guaranteeing sequential execution. Added `.isFilter('nafaqah_class', null)` in `account_service.dart`. | **RESOLVED** |
| **HIGH-05** | HIGH | `CommitmentsService`<br>• `commitments_service.dart`<br>• `commitments_service_biweekly_test.dart` | Biweekly BNPL plans (Tabby, Tamara) with `nextDueAt != null` emitted only a single `PendingCommitment`, omitting the second installment falling within the same monthly salary cycle. | **Opus Validated Fix:** Expanded biweekly frequency processing in `CommitmentsService.getPendingCommitments` to generate all due dates across `[cycleStart, cycleEnd]` via `plan.dueDates(...)` capped by `plan.remainingInstallments`, rolling overdue installments forward into the current cycle. | **RESOLVED** |
| **HIGH-06** | HIGH | Live Database Migration Verification<br>• `docs/review/HIGH06_LIVE_VERIFICATION.sql`<br>• `33_prior_spend_manual_row.sql` | Auditor proposed applying pending migrations to live Supabase via MCP from an unapproved branch. This violated Rule 04 §2 (migrations applied in Supabase SQL editor), Rule 05 §1.5 (never point runner at production DB), and Rule 06 §1 (zero production mutations without owner sign-off). | **Opus Validated Fix:** Rejected direct agent live mutations. Authored comprehensive read-only SQL inspection script `docs/review/HIGH06_LIVE_VERIFICATION.sql` for live database owner to inspect tables, triggers, constraints, and functions in Supabase SQL editor prior to merging. Verified all triggers and constraints locally in test suite `supabase/tests/33_prior_spend_manual_row.sql`. | **RESOLVED** |

#### Detailed Remediation Breakdown

##### 1. CRITICAL-01: PaydayOutlook SSOT & Hero Card Alignment
- **Root Cause:** In `budget_hero_card.dart`, `PaydayOutlook.compute` was invoked with `pendingCommitments: 0` and `effectiveOperatingCash` (which had already subtracted commitments). When `monthlyIncome` was non-null, `PaydayOutlook` computed `safeDaily` based on income remaining without deducting pending commitments, inflating safe daily burn rate. When `monthlyIncome` was null, `_HeroCommitmentsTip` subtracted commitments a second time (`outlook.left - effectiveCommitments`).
- **Implementation:**
  - Added `final double afterCommitments;` as a first-class property to `PaydayOutlook`.
  - Defined `safeDaily = (daysLeft > 0 && afterCommitments > 0) ? afterCommitments / daysLeft : 0.0` with division-by-zero protection.
  - In `budget_hero_card.dart`, passed `operatingCash: s != null ? s.liquidBalance : operatingCash` and `pendingCommitments: effectiveCommitments`.
  - Updated `_HeroCommitmentsTip` to read `actualAvailable: outlook.afterCommitments`.
- **Proof:** Verified in `flutter_app/test/models/payday_outlook_test.dart` (325 lines, covering income set, income null, deficit, and zero days left) and `flutter_app/test/widgets/budget_hero_card_test.dart`.

##### 2. CRITICAL-02: Operating Cash Synchronization Across Screens
- **Root Cause:** On `BudgetManagementScreen`, Row 2 ("Operating Cash") called `snapshot.operatingCash` (`liquidBalance - commitments`). Recurring bills are already managed as category allocations (e.g. `OPEX-HOUSING`, `OPEX-BILLS`), so subtracting commitments double-counted bills, resulting in Row 2 showing `SAR 2,208.26` while `AccountsOverviewScreen` and `BudgetHeroCard` showed `SAR 6,370.26`. Additionally, fallback cycle funding summed `totalSpent` including wife-class transactions.
- **Implementation:**
  - Created pure helper functions `resolveDisplayOperatingCash`, `householdDebitedSpend`, and `resolveCycleFunding`.
  - Bound Row 2 `displayOperatingCash` to `snapshot.liquidBalance` when `isCurrentCycle && accountProvider.hasLoaded`.
  - Computed fallback funding as `snapshot.liquidBalance + householdDebitedSpend`, strictly filtering out transactions where `nafaqah_class IN ('wife_personal', 'wife_reimbursable')` (as wife transactions never debit household accounts).
- **Proof:** Verified in `flutter_app/test/screens/budget_management_sync_math_test.dart`.

##### 3. CRITICAL-03: PostgreSQL Constraint 23514 & Cycle Key Derivation
- **Root Cause:** In `BudgetManagementScreen.buildPriorSpendRow`, setting `source = 'prior_adjustment'` caused PostgreSQL to throw SQLSTATE `23514` (`transactions_source_check` violation: only `'chat'`, `'receipt_scan'`, and `'manual'` allowed). The auditor suggested adding client-side `cycle_key`, which violated Rule 02 §1 (authoritative trigger generation).
- **Implementation:**
  - Retained `row['source'] = 'manual'` and `row['account_id'] = null`. Manual entries with null account ID are already filtered out of auto-reconciliation in `AccountService.reconcileUnlinkedTransactions`.
  - Derived the transaction timestamp at cycle start noon Asia/Riyadh (09:00 UTC), guaranteeing that trigger `trg_populate_transaction_cycle_key` calculates the exact cycle key automatically.
  - Stripped client-side `cycle_key` from insert payloads.
- **Proof:** Authored SQL proof test `supabase/tests/33_prior_spend_manual_row.sql` asserting successful insert under `source = 'manual'` and trigger-populated `cycle_key`.

##### 4. CRITICAL-04: Backend Debitable Account Resolver & Sequential Client Refresh
- **Root Cause:** Unlinked chat/receipt transactions created with `account_id = None` failed to debit account balances because `trg_update_account_balance_on_transaction` fires only when `account_id IS NOT NULL`. In Flutter, `_refreshGlobalProviders()` executed before asynchronous reconciliation completed, leaving UI balances stale. Reconciliation also lacked a guard against linking wife transactions to shared pool accounts.
- **Implementation:**
  - Added helper `resolve_default_debitable_account(household_id, user_id, category_code, nafaqah_class)` in `ai_service/supabase_client.py`:
    - Returns `None` for wife transactions (`nafaqah_class IN ('wife_personal', 'wife_reimbursable')`) or unauthenticated requests.
    - Inspects active category budget account first; falls back to the sole non-archived debitable account (shared pool or owner account) verified by `assert_account_debitable`.
    - Returns `None` if multiple candidate accounts exist (never guesses).
  - Wired resolver into `chat_parser.py` and `receipt_scanner.py` during transaction commit (`preview_only=False`).
  - Created `flutter_app/lib/services/post_commit_sync.dart` exposing `reconcileThenRefresh`, ensuring reconciliation completes sequentially before UI refresh in `try-finally`.
  - Added `.isFilter('nafaqah_class', null)` to `AccountService.reconcileUnlinkedTransactions`.
- **Proof:** Verified in `ai_service/tests/test_default_debitable_account.py` (126 lines) and `flutter_app/test/services/post_commit_sync_test.dart`.

##### 5. HIGH-05: Biweekly Installment Obligations in CommitmentsService
- **Root Cause:** In `CommitmentsService.getPendingCommitments`, when `plan.nextDueAt != null`, only a single commitment was emitted, dropping subsequent biweekly installments within the monthly salary cycle.
- **Implementation:**
  - For plans with `frequency.toLowerCase() == 'biweekly'`, the service iterates across the current cycle `[cycleStart, cycleEnd]` via `plan.dueDates(...)`, rolling overdue dates forward into the cycle.
  - Iteration is strictly capped by `plan.remainingInstallments`.
  - Emits distinct `PendingCommitment` objects with exact per-installment amounts.
- **Proof:** Verified in `flutter_app/test/services/commitments_service_biweekly_test.dart` (278 lines).

##### 6. HIGH-06: Read-Only Live Supabase Verification Script
- **Root Cause:** Direct subagent modification of live production databases via MCP is strictly prohibited by Rule 04 §2, Rule 05 §1.5, and Rule 06 §1. Live migrations must be applied through the Supabase SQL editor by the human repository owner.
- **Implementation:**
  - Authored `docs/review/HIGH06_LIVE_VERIFICATION.sql`: a non-destructive, read-only introspection script querying `information_schema.tables`, `information_schema.check_constraints`, `information_schema.triggers`, and `pg_proc`.
  - Script enables the repository owner to verify `trg_update_account_balance_on_transaction`, `trg_enforce_wife_class_account`, and `transactions_source_check` on the live database with zero risk of state corruption.
- **Proof:** Script tested and validated against local PostgreSQL catalog in `supabase/tests/33_prior_spend_manual_row.sql`.

### 7.6 Database Schema Consolidation & Jargon Elimination (Branch `feat/provider-sot-operating-cash`) [Planned by: plan-writer (Claude Opus 5.5 High) | Executed by: code-implementer (Claude Opus 5.5 High) | Reviewed by: reviewer-spec (Opus 5.5 High), reviewer-break (Opus 5.5 High), reviewer-fable (Fable High)]

Following explicit single-user authorization to address architectural root causes directly, the database schema, backend services, and client applications underwent full jargon elimination and baseline consolidation:

1. **Jargon Purge (`transactions.raw_sms` $\to$ `transactions.notes`):**
   - **Root Cause:** Historical SMS scraper jargon lingered in database column names despite the project's strict Zero-SMS Policy (Rule 04). In reality, this column stores free-text audit trail notes (Chat entries, OCR receipt summaries, manual attribution tags like `PaidBy:`, `Beneficiary:`, `[Financed via ...]`).
   - **Migration:** `supabase/migrations/20261102000000_cleanup_database_jargon_and_zombie_columns.sql` idempotently renames `raw_sms` to `notes` (type `TEXT`) and updates column documentation.
   - **Backend & Client:** All write and read paths across FastAPI (`supabase_client.py`, `chat_parser.py`, `receipt_scanner.py`, `settlement_engine.py`, `installment_service.py`, `dedup_engine.py`) and Flutter (`Transaction` model, `manual_expense_row.dart`, `edit_transaction_sheet.dart`, `receipt_scanner_sheet.dart`, `sync_worker.dart`) were refactored to `notes`.
2. **Zombie Column Elimination (`users.payday_day` Dropped):**
   - **Root Cause:** Obsolete column created in initial prototype. Payday cycle calculation strictly relies on `households.payday_day` as the Single Source of Truth (Rule 02). Zero production queries referenced `users.payday_day`.
   - **Action:** Dropped via `ALTER TABLE public.users DROP COLUMN IF EXISTS payday_day;`.
3. **Consolidation of Authoritative Baseline (`supabase/schema.sql`):**
   - Replaced obsolete 5-table prototype with complete 15-table modern baseline (`households`, `users`, `cost_control_codes`, `cost_control_sub_categories`, `cost_control_templates`, `household_category_settings`, `budgets`, `transactions`, `accounts`, `account_transfers`, `income_records`, `installment_plans`, `household_dependents`, `household_invites`, `household_memberships`), RLS policies, triggers, and publications.
4. **Offline Replay Hardening (`SyncWorker`):**
   - Sanitized queued offline SQLite payloads in `sync_worker.dart` so legacy cached rows with `'raw_sms'` map seamlessly to `'notes'` upon post-migration sync.
5. **Multi-Round Review Approvals:**
   - **Round 1 (Spec Fidelity - Opus 5.5 High):** Caught stale `payday_day` assertion in test 21, resolved and APPROVED.
   - **Round 2 (Adversarial Break Testing - Opus 5.5 High):** Caught replay chain permission grant dependency on baseline schema, resolved and APPROVED.
   - **Round 3 (Security & Invariants - Fable High):** Validated RLS multi-tenancy, Islamic Nafaqah spousal isolation, and zero-based ledger arithmetic. APPROVED.

---

## 8. Testing, Verification Gate & Orchestrator Governance Matrix

### 8.1 Verification Gate Commands

Before any pull request, commit, or subagent task sign-off, the workspace must satisfy the **Mandatory Pre-Review Verification Gate**:

| Verification Tier | Command | Acceptance Criteria | Current Verified Status |
|---|---|---|---|
| **Flutter Static Analysis** | `cd flutter_app && flutter analyze` | **0 errors, 0 warnings, 0 linter hints** (`No issues found!`) | **0 issues found** (100% clean) |
| **Flutter Unit & Widget Tests** | `cd flutter_app && flutter test` | **100% passing** (1,140+ tests green) | **1,140 passed**, 0 failed (100% green) |
| **FastAPI Backend Tests** | `cd ai_service && pytest -v` | **100% passing** (1,100+ tests green, hermetic execution) | **1,100 passed**, 4 skipped (100% green) |
| **Database Migrations & Proofs** | `python3 supabase/tests/run_tests.py --psql --rebuild --db <local_test_db>` | **100% passing** across all SQL test suites | **100% passing** (34 SQL proof suites green) |
| **Web Portal Quality** | `cd web_app && npm run lint && npm run build` | **0 lint errors**, clean production bundle build | **0 errors**, production bundle verified |

### 8.2 Orchestrator Governance Matrix & Delegation Pipeline

Development in the repository is governed by the **Claude Opus 5.5 Orchestrator & Subagent Delegation Model**:

```
                       ┌──────────────────────────────────────────────┐
                       │   USER / HUMAN STAKEHOLDER                   │
                       └──────────────────────┬───────────────────────┘
                                              │ Prompts & Review Decisions
                                              ▼
                       ┌──────────────────────────────────────────────┐
                       │   CLAUDE OPUS 5.5 ORCHESTRATOR               │
                       │   (Chat Coordinator, Plan Architect)         │
                       └──────┬───────────────────────────────┬───────┘
                              │ Task Delegation               │ Review Invocation
                              ▼                               ▼
       ┌───────────────────────────────────────────┐   ┌───────────────────────────────────────────┐
       │   IMPLEMENTATION SUBAGENT                 │   │   MULTI-ROUND AUDIT REVIEWERS             │
       │   (Claude Opus 5.5 High / Branch Worktree)│   │   (Fresh subagent per round)              │
       │   • Strict TDD: Failing tests first       │   │                                           │
       │   • Minimal clean code implementation     │   │   • Round 1: Opus 5.5 Spec Fidelity       │
       │   • Pre-review verification gate pass     │   │   • Round 2: Opus 5.5 Adversarial Break   │
       │   • Return concise summary + commit hash  │   │   • Round 3: Fable High (Sensitive Tasks) │
       └───────────────────────────────────────────┘   └───────────────────────────────────────────┘
```

#### Governance Principles & Rules
1. **Never Implement Directly in the Main Session:** The Orchestrator plans, monitors, and delegates; implementation executes on isolated branches.
2. **Strict Sensitivity Boundary (`docs/sensitive.md`):** Any task touching migrations, permissions, money, account balances, RLS policies, secrets, or data deletion is classified as **SENSITIVE** automatically.
   - Classification is **unidirectional**: The Orchestrator may escalate a task to sensitive, but never lower it.
   - Sensitive tasks mandate **Round 3 review by Fable High**.
3. **Multi-Round Code Review:**
   - **Round 1 (Claude Opus 5.5 High):** Specification fidelity and gap analysis.
   - **Round 2 (Claude Opus 5.5 High):** Adversarial break testing (permissions, race conditions, edge cases). Every claim must be proven with a failing test.
   - **Round 3 (Fable High):** Security, ledger invariants, RLS multi-tenancy, and Islamic compliance audit.
4. **Explicit User Approval Invariants:** The Orchestrator must stop and request explicit user confirmation before:
   - Deploying to any production environment.
   - Deleting data, files, or user accounts.
   - Updating secrets, keys, or environment files.
   - Incurring financial spend or third-party API costs.
5. **Context Window Guardrail (80% Threshold):** When session context reaches 80% capacity, the Orchestrator must write a structured handoff artifact (`docs/review/HANDOFF_<session>.md`) and direct the user to continue in a fresh session.

### 8.3 Subagent & Module Registry

To maintain high velocity without compromising architectural integrity, development tasks are executed by specialized, role-scoped subagents and models:

| Subagent / Module | Underlying Model / Runtime | Core Role & Responsibilities | Boundary Invariants |
|---|---|---|---|
| **`plan-writer`** | Claude Opus 5.5 (effort: high) | TDD Plan Architect & Sensitivity Classifier. Analyzes code diffs, evaluates task sensitivity against `docs/sensitive.md`, formulates failing test specifications (Red), and outlines minimal clean implementation steps (Green). | Authors plans only; never modifies runtime application code directly. |
| **`code-implementer`** | Claude Opus 5.5 (effort: high) / Gemini 3.8 Flash High | TDD Code Engineer operating on isolated branch worktrees. Implements failing test suites first, writes minimal production code to turn them green, and executes pre-review verification gates. | Constrained strictly to task branch; zero modifications to main branch or live databases. |
| **`reviewer-spec`** | Claude Opus 5.5 (effort: high) | Round 1 Spec Fidelity & Edge-Case Auditor. Audits implementation against prompt requirements, verifies acceptance criteria, checks edge cases, and inspects for architectural regression vectors. | Read-only auditor; produces structured PASS / REVISE verdicts. |
| **`reviewer-break`** | Claude Opus 5.5 (effort: high) | Round 2 Adversarial Break Tester. Actively constructs adversarial test cases to exploit race conditions, permission bypasses, precision errors, and boundary flaws. | Every reported vulnerability must be proven with a concrete failing test case. |
| **`reviewer-fable`** | Fable (effort: high) | Round 3 Security, RLS, Ledger Invariants & Islamic Fintech Auditor. Audits database multi-tenancy, RLS initplans, secret key isolation, financial double-entry invariants, and Nafaqah compliance. | Mandated for all tasks classified as SENSITIVE in `docs/sensitive.md`. |
| **`gemini-argon-high`** | Gemini Argon (effort: high) | External Lead Architect Auditor. Conducts comprehensive, holistic cross-system reviews across the mobile app, AI microservice, and Supabase database. | Serves as external independent verification checkpoint prior to production merges. |

### 8.4 Workflow Evolution & Rule Alignment [Audited by: Claude Opus 5.5 Orchestrator | Executed by: code-implementer (Claude Opus 5.5 high)]

The Budget Tracker engineering methodology underwent a comprehensive evolution to guarantee zero regression risk in financial calculations:

1. **Orchestrator-Subagent Separation of Concerns:**
   - The main chat session is reserved exclusively for the **Claude Opus 5.5 Orchestrator**. The Orchestrator plans, coordinates subagents, requests human approvals, and monitors context window health.
   - All code generation, test authoring, and bug fixing executes in isolated subagents on dedicated feature branches (e.g., `feat/provider-sot-operating-cash`).
2. **Codified Sensitivity Boundary (`docs/sensitive.md`):**
   - In accordance with Rule 06, any file or action touching database migrations, user permissions, monetary ledgers, account balances, RLS policies, secrets, or data deletion is classified as **SENSITIVE**.
   - Classification is **strictly unidirectional**: tasks may be escalated to sensitive, but never downgraded. All sensitive tasks mandate a third-round security review by `reviewer-fable`.
3. **Multi-Round Review Pipeline:**
   - No code merges without surviving a multi-round review gauntlet:
     - **Round 1 (Spec Fidelity):** Verifies adherence to user requirements, documentation, and existing patterns.
     - **Round 2 (Adversarial Break):** Actively attempts to break the implementation with adversarial scenarios.
     - **Round 3 (Fable Security & Compliance):** Exhaustive audit of RLS policies, token leakage, halala precision, and Islamic compliance.
4. **Engineering Rules 01–06 Full Alignment:**
   - **Rule 01 (Architecture):** Enforces zero-based cash engine with database triggers as the sole authority for `accounts.balance`. Mobile layers consume `OperatingCashSnapshot` as immutable SSOT.
   - **Rule 02 (Saudi Fintech & Islamic Compliance):** Enforces the 4 Golden Nafaqah Rules. Wife transactions never touch shared accounts (`trg_enforce_wife_class_account`). Cycle keys are derived authoritatively by triggers from Asia/Riyadh dates.
   - **Rule 03 (UI/UX System):** Formalizes Velvet Burgundy Master HUD design tokens with backward-compatible token bridges. Mandates Privacy Eye masking across all financial balances and surplus/deficit badges.
   - **Rule 04 (Security & Privacy):** Strictly prohibits SMS interception permissions. Mandates private storage buckets with signed URLs, asymmetric JWT verification, and strict secret key segregation.
   - **Rule 05 (Testing & Quality):** Mandates strict red-green TDD. Enforces **zero analyzer warnings** (`flutter analyze` reports 0 issues) and 100% test pass rate (1,139 Flutter tests, 1,100 Pytest tests).
   - **Rule 06 (PR & Verification Gate):** Mandates pre-review verification gates before branch push and strict owner approval before production deployment.

---

## 9. Complete API Endpoints Directory

Generated from the OpenAPI 3.1 specification (`ENV=development`). All endpoints except the `ops` group and `POST /public/inquiries` require `Authorization: Bearer <Supabase_JWT>`.

| Route Area | Method | Endpoint Path | Auth / Role Constraint | Functional Description |
|---|---|---|---|---|
| **Operations** | `GET` | `/` | Public | Serves production build of web landing page. |
| | `GET` | `/health` | Public | System health check and database ping. |
| | `GET` | `/auth/confirm` | Public | Email auth confirmation redirect handler. |
| | `GET` | `/auth/callback` | Public | OAuth callback redirect handler. |
| **Budgets** | `GET` | `/budgets/salary-cycle-forecast` | Household Member | Payday cycle forecast, burn rate, and daily spend pace. |
| | `GET` | `/budgets/cycles` | Household Member | List historical and upcoming salary cycles. |
| | `POST` | `/budgets/recalculate` | Household Admin | Recalculate spent amounts across all categories for cycle. |
| | `GET` | `/budgets/breakdown` | Household Member | Category allocations, spent amounts, and remaining halalas. |
| | `POST` | `/budgets/categories` | Household Admin | Create custom category in active household. |
| | `DELETE` | `/budgets/categories/{code}` | Household Admin | Archive custom category. |
| | `POST` | `/budgets/sub-allocations` | Household Admin | Save sub-category spending limits. |
| | `GET` | `/budgets/sub-categories` | Household Member | List sub-category catalog for active household. |
| | `POST` | `/budgets/sub-categories` | Household Admin | Create household custom sub-category. |
| | `PATCH` | `/budgets/sub-categories/{code}`| Household Admin | Rename custom sub-category. |
| | `DELETE` | `/budgets/sub-categories/{code}`| Household Admin | Delete custom sub-category. |
| | `POST` | `/budgets/simulate-affordability`| Household Member | Discretionary purchase impact simulation on safe daily spend. |
| **Recurring & BNPL** | `GET` | `/budgets/recurring-bills` | Household Member | List detected recurring monthly obligations. |
| | `POST` | `/budgets/recurring-bills/toggle`| Household Admin | Enable/disable recurring bill reservation. |
| | `GET` | `/budgets/recurring-bills/candidates`| Household Member | Suggest recurring bill candidates from transaction history. |
| | `GET` | `/budgets/installments` | Household Member | List active BNPL installment plans (Tabby, Tamara, etc.). |
| | `POST` | `/budgets/installments` | Household Member | Record new BNPL plan linked to transaction. |
| | `POST` | `/budgets/installments/{id}/pay` | Household Member | Atomic payment increment for installment plan. |
| **Households** | `GET` | `/households/{id}/payday` | Household Member | Retrieve configured payday day (1–31). |
| | `PUT` | `/households/{id}/payday` | Household Admin | Update household payday setting. |
| | `GET` | `/households/{id}/income` | Household Member | Retrieve monthly income baseline. |
| | `PUT` | `/households/{id}/income` | Household Admin | Update monthly income baseline. |
| | `GET` | `/households/{id}/rollover-rule` | Household Member | Retrieve active rollover rule. |
| | `PUT` | `/households/{id}/rollover-rule` | Household Admin | Set rollover rule (`send_to_savings`, etc.). |
| | `GET` | `/households/{id}/savings-summary`| Household Member | Retrieve total accumulated savings reserve. |
| | `POST` | `/households/{id}/invites` | Household Admin | Generate single-use expiring invite code. |
| | `GET` | `/households/invites/{code}` | Public | Inspect invite validity and target household name. |
| | `POST` | `/households/invites/{code}/claim` | Authenticated User | Claim invite and join household. |
| **Members & Admins** | `GET` | `/households/{id}/members` | Household Member | List all household members, roles, and profiles. |
| | `POST` | `/households/{id}/members/{uid}/admin` | Household Admin | Promote member to Co-Admin. |
| | `DELETE` | `/households/{id}/members/{uid}/admin` | Household Admin | Revoke Co-Admin role (cannot demote Primary Admin). |
| | `POST` | `/households/{id}/primary-admin`| Primary Admin | Transfer Primary Admin ownership. |
| **Dependents** | `GET` | `/households/{id}/dependents` | Household Member | List dependents (children, elderly) and allowances. |
| | `POST` | `/households/{id}/dependents` | Household Admin | Create dependent profile. |
| | `DELETE` | `/households/{id}/dependents/{did}`| Household Admin | Delete dependent profile. |
| **Settlement & Nafaqah**| `GET` | `/households/{id}/settlement` | Roommates Mode | Pairwise debt matrix for flatmates. |
| | `GET` | `/households/{id}/settlement-v2` | Roommates Mode | Multi-way simplified graph settlement paths. |
| | `POST` | `/households/{id}/reimbursements` | Family Mode | Record spousal reimbursement payment in Nafaqah ledger. |
| | `GET` | `/households/{id}/nafaqah` | Family Mode | Summary of outstanding spousal debt and allowances. |
| | `GET` | `/households/{id}/nafaqah/reimbursements` | Family Mode | Historical ledger of spousal repayments. |
| | `GET` | `/households/{id}/nafaqah/allowance` | Family Mode | Wife personal monthly allowance and remaining halalas. |
| | `PUT` | `/households/{id}/nafaqah/allowance` | Husband / Admin | Set wife monthly personal allowance for cycle. |
| **AI Intelligence** | `POST` | `/agent/scan-receipt` | Household Member | Gemini Vision OCR receipt page extraction & line items. |
| | `POST` | `/agent/chat-transaction` | Household Member | Conversational dialect parsing & expense classification. |
| **Analytics & Reports** | `GET` | `/analytics/price-history` | Household Member | Historical item price intelligence across Saudi grocery chains. |
| | `POST` | `/analytics/shopping-basket-optimize`| Household Member | Smart shopping basket bill estimation & store comparison. |
| | `GET` | `/reports/statement-pdf` | Household Member | Generate monthly PDF statement with verified Nafaqah tables. |
| **Support & Inquiries** | `POST` | `/support/chat` | Authenticated User | In-app support assistant conversational agent. |
| | `POST` | `/agent/support-chat` | Authenticated User | Tier-2 support problem resolution agent. |
| | `POST` | `/support/inquiries` | Authenticated User | Submit authenticated support ticket via Resend/SMTP. |
| | `POST` | `/public/inquiries` | Public (Rate Limited) | VIP early-access lead capture from web landing page. |

---

## 10. Strategic Roadmap (v1.1 – v1.4)

| Milestone | Capability | Description | Architectural Dependencies |
|---|---|---|---|
| **v1.1** | **SAMA Open Banking Integration** | Direct read-only transaction feeds from major Saudi retail banks via the Saudi Central Bank (SAMA) Open Banking Framework. | SAMA sandbox partnership, OAuth2 PKCE provider (Lean Tech / Tarabut Gateway). |
| **v1.1** | **Live Multi-Currency FX Engine** | Real-time exchange rate conversions between SAR, USD, EUR, and USDT with halala-precision tracking for multi-currency wallets. | Open FX feed with Redis caching and offline fallback. |
| **v1.2** | **WhatsApp Deep-Linking & Reminders** | 1-tap WhatsApp deep link (`https://wa.me/?text=...`) pre-populating roommate settlement balances and spousal reimbursement receipts. | URI launcher integration on client. |
| **v1.2** | **ML Bill Spike & Anomaly Detector** | Statistical anomaly detection alerting households when a DEWA, SEC electricity, or telecom bill deviates by $> 25\%$ from 3-cycle rolling average. | Python statistical worker in `ai_service`. |
| **v1.3** | **Automated Push Notifications (FCM)** | Server-side push notifications for impending BNPL installments (Tabby/Tamara), payday check-in arrival, and deficit warnings. | Supabase Database Webhooks + Firebase Cloud Messaging (FCM). |
| **v1.4** | **Smartwatch Companion App** | Apple Watch & WearOS micro-app for instant 1-tap voice expense logging and quick balance glances. | Flutter Wear OS / watchOS extension module. |

---

## Conclusion & Document Governance [Executed by: code-implementer (Claude Opus 5.5 high)]

This document, **`docs/MASTER_PROJECT_DETAILS.md`**, represents the definitive, unified master technical specification for the Budget Tracker repository. Any proposed architectural changes, schema migrations, or rule modifications must be reflected in this document following successful completion of the three-round audit review pipeline.
