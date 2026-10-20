# Full Project Details — Budget Tracker

> **Document Version:** 1.0.0  
> **Date:** October 18, 2026  
> **Status:** Active / Production-Ready  
> **Project Repository:** `Masteader/budget-tracker`  
> **Primary Target Market:** Saudi Arabia (KSA) & GCC Households  

---

## Table of Contents

1. [Executive Summary & Vision](#1-executive-summary--vision)
2. [High-Level Architecture & Tech Stack](#2-high-level-architecture--tech-stack)
3. [Current Applied Features (100% Implemented)](#3-current-applied-features-100-implemented)
   - 3.1 [Multi-Source Income, Accounts & Balances Ledger](#31-multi-source-income-accounts--balances-ledger)
   - 3.2 [Saudi Payday (27th) Cycle Engine & Automation](#32-saudi-payday-27th-cycle-engine--automation)
   - 3.3 [Account-Linked Budget Capacity & Deficit Engine](#33-account-linked-budget-capacity--deficit-engine)
   - 3.4 [ZATCA Phase 2 QR Decoder & Vision OCR Scanner](#34-zatca-phase-2-qr-decoder--vision-ocr-scanner)
   - 3.5 [Conversational AI & Saudi Dialect Voice Logging](#35-conversational-ai--saudi-dialect-voice-logging)
   - 3.6 [Islamic Family Nafaqah & Multi-Roommate Settlements](#36-islamic-family-nafaqah--multi-roommate-settlements)
   - 3.7 [Recurring Bills Predictor & BNPL Installment Tracker](#37-recurring-bills-predictor--bnpl-installment-tracker)
   - 3.8 [Household Management & Targeted Claim-on-Join](#38-household-management--targeted-claim-on-join)
   - 3.9 [Grocery Price Intelligence & Smart Basket](#39-grocery-price-intelligence--smart-basket)
   - 3.10 [Offline SQLite Engine & Network Resilience](#310-offline-sqlite-engine--network-resilience)
   - 3.11 [Sovereign OS & Iced Ocean Theme (Light/Dark + RTL)](#311-sovereign-os--iced-ocean-theme-lightdark--rtl)
   - 3.12 [React Daylight Coastal Landing Page & Payday Simulator](#312-react-daylight-coastal-landing-page--payday-simulator)
   - 3.13 [Trilingual Localization (Arabic, English, Urdu)](#313-trilingual-localization-arabic-english-urdu)
   - 3.14 [Security Hardening & Zero SMS Interception Policy](#314-security-hardening--zero-sms-interception-policy)
4. [Planned Features & Strategic Roadmap](#4-planned-features--strategic-roadmap)
5. [Database Schema & Migrations Index](#5-database-schema--migrations-index)
6. [Test Suite & Quality Verification](#6-test-suite--quality-verification)
7. [Documentation, Specifications & Rules Index](#7-documentation-specifications--rules-index)

---

## 1. Executive Summary & Vision

**Budget Tracker** is an enterprise-grade, culturally tailored household financial operating system engineered specifically for Saudi households, expat families, and shared roommate communities in the GCC.

Unlike Western budgeting tools that assume generic calendar-month paydays, arbitrary 50/50 couple splits, and Western merchant categorization, Budget Tracker addresses the distinct cultural, legal, and financial realities of the Saudi market:
- **The 27th Payday Cycle:** Public and private sector payrolls in Saudi Arabia align with the 27th of each Gregorian month.
- **Islamic Family Finance (*Nafaqah*):** Under Islamic law, the husband carries legal financial responsibility for household maintenance. Personal spending by the wife is tracked as reimbursable debt owed to her rather than arbitrarily splitting costs.
- **ZATCA Phase 2 E-Invoicing:** Automated camera scanning extracts Base64 TLV data (seller, VAT ID, timestamp, VAT totals) in milliseconds without cloud delay.
- **Multi-Source Liquid Accounts:** Modern Saudi consumers split liquid wealth between traditional banks (Al Rajhi, SNB), e-wallets (STC Pay, Urpay), crypto exchanges (Binance), and physical cash. Budget Tracker links budgets directly to account balances to guarantee spending capacity.
- **Zero SMS Interception:** Maximum privacy without requesting intrusive SMS permissions or running background listeners.

---

## 2. High-Level Architecture & Tech Stack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             CLIENT ECOSYSTEM                                │
├──────────────────────────────────────┬──────────────────────────────────────┤
│          Flutter Mobile App          │           React Web Portal           │
│    (iOS / Android - Sovereign OS)    │   (Daylight Coastal Exploding Flow)  │
│  • Dart 3.x, Flutter 3.22+           │  • React 18, TypeScript, Vite        │
│  • Provider / ChangeNotifier         │  • TailwindCSS, Framer Motion        │
│  • Camera, Audio, Google Fonts       │  • Interactive Payday Simulator      │
│  • SQLite Offline Engine (`sqflite`) │  • RTL Arabic & LTR English          │
└──────────────────┬───────────────────┴──────────────────┬───────────────────┘
                   │                                      │
                   ▼                                      ▼
┌──────────────────────────────────────┐  ┌───────────────────────────────────┐
│          Supabase Platform           │  │         Python AI Service         │
│         (PostgreSQL 15 + RLS)        │  │         (FastAPI + Uvicorn)       │
│  • 19 Relational Migrations          │  │  • Gemini 2.5 Flash Vision OCR    │
│  • Row Level Security (RLS)          │◄─┤  • Dialect Chat Agent (LiteLLM)   │
│  • Realtime CDC Data Stream          │  │  • Heuristic Recurring Detector   │
│  • Supabase Storage (Receipts)       │  │  • Multi-Roommate Debt Solver     │
│  • Database Triggers & Audit Logs    │  │  • PDF Statement Generator        │
└──────────────────────────────────────┘  └───────────────────────────────────┘
```

---

## 3. Current Applied Features (100% Implemented)

### 3.1 Multi-Source Income, Accounts & Balances Ledger
- **Account Types:** Supports Traditional Banks (`bank`), E-Wallets (`e_wallet`), Crypto (`crypto`), Physical Cash (`cash`), and Shared Household Pools (`shared_pool`).
- **Liquid Asset Dashboard Card:** Summarizes total household liquidity with a discreet privacy eye toggle for public use.
- **Inter-Account Transfers:** Atomic funds transfers with fee recording (e.g. gas fees or transfer charges) and automatic balance updates.
- **Multi-Source Income Logging:** Itemizes incoming cash flow by source (Base Salary, Overtime, Bonus, Side Gig, Roommate Share, Other) with deduction/GOSI subtractions.
- **Account Reconciliation:** 1-tap reconcile dialog compares app balance with actual banking apps and records adjustment records with variance calculations.

### 3.2 Saudi Payday (27th) Cycle Engine & Automation
- **27th Payday Alignment:** Cycles automatically transition on the 27th of each month (e.g. `2026-10` covers Oct 27 to Nov 26).
- **Payday Check-in Modal:** On payday arrival, a contextual check-in banner prompts the user to enter their net salary deposit and overtime/bonuses.
- **Salary Distribution Assistant:** 1-tap distribution assistant identifies deficits across secondary wallets (e.g. STC Pay grocery allowance) and executes batch transfers from the primary salary bank.
- **Cycle Rollover Invariant:** Offers explicit user choice:
  - **Option A (Category Cushion):** Rollover unspent category budget as an additional cushion in the next cycle (`previous_cycle_delta`).
  - **Option C (Sweep to Savings):** Sweep all leftover category funds into an emergency savings account and reset category caps.

### 3.3 Account-Linked Budget Capacity & Deficit Engine
- **Account-to-Budget Linkage:** Each spending category is explicitly mapped to a funding account (e.g., Groceries $\to$ STC Pay; Utilities $\to$ Al Rajhi Bank).
- **Capacity Formula:** $\text{Capacity Margin} = \text{Account Balance} - \sum \text{Allocated Category Budgets}$.
- **Status Indicators:**
  - `🟢 Zero-Based (100% Allocated)`: Balance exactly equals allocated budget.
  - `🔵 Surplus Buffer (+SAR X.XX)`: Available liquidity exceeds commitments.
  - `🔴 Deficit Shortfall (-SAR X.XX)`: Account balance is lower than budgeted spending.
- **1-Tap Quick Transfer:** Tapping a deficit alert pre-populates an account transfer sheet with the exact shortage amount from the account with the largest surplus.

### 3.4 ZATCA Phase 2 QR Decoder & Vision OCR Scanner
- **Base64 TLV Hardware Decoding:** Instant on-device parsing of Saudi ZATCA QR codes using mobile camera or gallery pickers:
  - Tag 1 (Seller Name), Tag 2 (15-digit VAT ID), Tag 3 (Timestamp), Tag 4 (Total Amount), Tag 5 (15% VAT Amount).
- **Gemini 2.5 Flash Vision OCR:** Multi-page receipt scanner analyzes paper invoices, extracts merchant names, purchase date, payment method, and line items with unit prices.
- **Receipt Storage & Viewer:** Images stored securely in Supabase Storage (`receipts` bucket) with thumbnail strips and zoomable full-screen preview.
- **Duplicate Prevention:** Heuristic duplicate candidate detection alerts users if a receipt with identical merchant, total, and timestamp was previously ingested.

### 3.5 Conversational AI & Saudi Dialect Voice Logging
- **Natural Dialect Chat:** Powered by LiteLLM and Gemini, accepting natural Saudi Arabic phrasing (e.g., *"تقضينا من بنده بـ ٢٥٠ ريال من بطاقة الراجحي"*).
- **Voice Entry Banner:** Hands-free speech-to-text recording with real-time listening visualization.
- **Interactive Action Cards:**
  - `PendingExpenseConfirmationCard`: Previews parsed items before database persistence.
  - `PurchaseSimulationCard`: Real-time affordability check checking current cycle budget and salary countdown before buying.
  - `DuplicateResolutionCard`: Resolves potential duplicate submissions interactively.

### 3.6 Islamic Family Nafaqah & Multi-Roommate Settlements
- **Islamic Nafaqah Enforcement (family mode, rules 1–4 in `.agents/rules/02-…`):**
  - No 50/50 or any percentage split between the spouses: shared family expenses are the husband's Nafaqah.
  - The wife paying for something shared from her own money is tagged `transactions.nafaqah_class = 'wife_reimbursable'` and becomes a debt the husband owes her; the app shows the outstanding balance and history and records partial or full repayments (overpayment rejected).
  - Her personal purchases are tagged `wife_personal` and charged to her **personal allowance ("مصروفها")** per salary cycle, set by the husband/admin; allocated / spent / remaining is shown, overspend goes negative and is never blocked.
  - Expense entry (manual, chat review, edit) offers "Husband paid", "Shared for family (husband reimburses)" or "Personal (from my/her allowance)"; the chat parser suggests the class (e.g. «اشتريت لنفسي…» → personal, «دفعت فاتورة البيت / أغراض البيت / للعيال» → reimbursable).
  - API: `GET /households/{id}/nafaqah` (summary for the caller), `GET|POST /households/{id}/nafaqah/reimbursements` (ledger / record repayment), `GET|PUT /households/{id}/nafaqah/allowance` (status / set). All require the caller's JWT and household membership; `POST /households/{id}/reimbursements` writes the Nafaqah ledger in family households.
- **Multi-Roommate Settlement Engine:**
  - Solves multi-way debts between flatmates (Rent, Cleaning, Fiber Internet, Utilities).
  - Graph-based debt simplification minimizes transaction count (e.g. 5 debts simplified into 2 direct payments).
  - Shared Pool accounts (`is_shared_pool = true`) allow roommates to pool monthly contributions and view real-time pool health.

### 3.7 Recurring Bills Predictor & BNPL Installment Tracker
- **Recurring Bill Detector:** Analyzes transaction history to identify monthly recurring payments (Electricity/SEC, Water/NWC, Fiber Internet, Gym memberships, Streaming).
- **Payday Bill Reserves:** Automatically reserves necessary cash from the salary deposit so bills are never defaulted.
- **BNPL Tracker:** Integrates Tabby, Tamara, and bank installment plans with remaining payment count, installment amount, and next due date countdown.

### 3.8 Household Management & Targeted Claim-on-Join
- **Role Hierarchy:** Household Admin, Contributing Member, Dependent (Child/Elderly).
- **Placeholder Member Profiles:** Admins can create placeholder member profiles for family members who do not yet possess a smartphone or app account.
- **Targeted Claim-on-Join:** When a family member joins using an invite code with a `target_member_id`, their newly created authenticated user profile automatically merges and claims their pre-existing history and allowance settings.

### 3.9 Grocery Price Intelligence & Smart Basket
- **Price Tracking Engine:** Tracks historical unit prices for standard grocery items across Saudi supermarket chains (Panda, Lulu, Carrefour, Danube, Othaim).
- **Smart Shopping Basket:** Interactive shopping list sheet computes estimated total bill based on past scanned receipt averages and highlights potential store savings.

### 3.10 Offline SQLite Engine & Network Resilience
- **Offline Transaction Buffer:** Full local SQLite database (`budget_tracker_offline.db` / `sqflite`) captures expense entries, transfers, and notes when disconnected from the internet.
- **Background Auto-Sync:** Connectivity listener automatically flushes the local offline queue to Supabase as soon as network connection is restored.

### 3.11 Sovereign OS & Iced Ocean Theme (Light/Dark + RTL)
- **Aesthetic Direction:** Sovereign tactical HUD with glacial Iced Ocean accents (`#00E5BF` cyan mint, `#0A0F1D` midnight abyss, frosty glass panels, and crisp arctic light mode).
- **Floating Tactical Dock:** Customized bottom navigation bar with quick-action speed dial FAB (Record Income, Transfer Funds, Add Expense).

### 3.12 React Daylight Coastal Landing Page & Payday Simulator
- **Modern Web Architecture:** React 18, Vite, TypeScript, and TailwindCSS deployed on cloud hosting.
- **Daylight Coastal Exploding Flow Aesthetic:** High-energy daylight ocean theme with dynamic floating cards and live interactive elements.
- **Interactive Payday Simulator:** Custom salary input slider with live countdown to the 27th payday and budget distribution preview.

### 3.13 Trilingual Localization (Arabic, English, Urdu)
- **RTL Primary:** Native Arabic typography with correct RTL mirroring.
- **Trilingual Dictionary:** Complete coverage of all labels, dialogs, sheets, and error states in Arabic (`ar`), English (`en`), and Urdu (`ur`).
- **Zero Hardcoded Strings:** Every UI element references `AppLocalizations.of(context)`.

### 3.14 Security Hardening & Zero SMS Interception Policy
- **Zero SMS Interception:** Completely standalone without background SMS listeners or invasive SMS permissions.
- **Key Segregation:** `SUPABASE_SERVICE_ROLE_KEY` is strictly confined to the backend server; client uses the restricted `SUPABASE_ANON_KEY`.
- **Row Level Security (RLS):** All 19 database tables enforce household tenancy isolation.
- **Webhook & Firewall Protection:** HMAC-SHA256 signature verification and firewall token middleware on backend API endpoints.

---

## 4. Planned Features & Strategic Roadmap

While the core functionality is 100% operational and verified, the following features are planned for subsequent milestones:

| Phase | Planned Feature | Description | Architecture / Dependency |
|---|---|---|---|
| **v1.1** | **SAMA Open Banking Integration** | Direct read-only bank feed connectivity via the Saudi Central Bank (SAMA) Open Banking API framework (Tarabut Gateway / Lean Tech). | Requires SAMA sandbox partnership & PSD2-compliant OAuth. |
| **v1.1** | **Live Multi-Currency FX Feeds** | Real-time exchange rate auto-conversion between SAR, USD, and USDT for multi-currency accounts. | Integration with Saudi Central Bank / open FX rate API. |
| **v1.2** | **WhatsApp & Splitwise Deep-Linking** | 1-tap WhatsApp message generator to send payment reminders and settlement breakdown links to roommates. | URI scheme generator (`https://wa.me/?text=...`). |
| **v1.2** | **ML Bill Spike & Price Anomaly Alerts** | Predictive anomaly model alerting users when utility bills (e.g. summer AC electricity spike) exceed 30% of 3-month moving average. | Python backend statistical time-series model in `ai_service`. |
| **v1.3** | **Multi-Household Switching** | Allows a single user to toggle between managing their primary family home, parents' home, and personal bachelor flat. | Schema extension to support multiple household memberships per user. |
| **v1.3** | **Automated Push Notifications (FCM)** | Firebase Cloud Messaging alerts for upcoming BNPL payment dates, 27th payday arrival, and account deficit alerts. | Supabase Database Webhooks + FCM service worker. |
| **v1.4** | **Wearable Companion App** | Apple Watch & WearOS micro-app for instant 1-tap voice expense logging while shopping. | Flutter wear / standalone watchOS extension. |

---

## 5. Database Schema & Migrations Index

The database layer consists of 19 incremental, backward-compatible SQL migrations in `supabase/migrations/`:

| Migration File | Date | Tables & Objects Affected | Core Purpose |
|---|---|---|---|
| `20260925_add_line_items_and_sources.sql` | 2026-09-25 | `transactions` | Adds line items JSONB and receipt input source columns. |
| `20260925_add_transaction_edit_delete_triggers.sql` | 2026-09-25 | `transactions`, Triggers | Recomputes budget spent totals on transaction insert/update/delete. |
| `20260930_fix_transactions_rls_and_columns.sql` | 2026-09-30 | `transactions`, RLS | Hardens tenancy RLS and fixes user association columns. |
| `20261002_add_sub_allocations_to_budgets.sql` | 2026-10-02 | `budgets` | Adds `sub_allocations` JSONB column for sub-category caps. |
| `20261002_salary_cycle_and_sub_budgets.sql` | 2026-10-02 | `households`, `budgets` | Introduces `payday_day`, `cycle_key`, and rollover tracking columns. |
| `20261003_allow_select_sub_categories.sql` | 2026-10-03 | `cost_control_sub_categories` | RLS policy allowing authenticated selection of subcategories. |
| `20261005_add_installment_plans.sql` | 2026-10-05 | `installment_plans` | Creates table for Tabby/Tamara BNPL tracking. |
| `20261005_query_performance_and_indexes.sql` | 2026-10-05 | Indexes | Composite indexes on `household_id`, `cycle_key`, and timestamps. |
| `20261008_add_household_payday.sql` | 2026-10-08 | `households` | Default payday setting (27th) and migration helpers. |
| `20261008_add_qr_code_raw_to_transactions.sql` | 2026-10-08 | `transactions` | Stores raw ZATCA TLV string for audit compliance. |
| `20261008_create_receipts_bucket_and_policies.sql` | 2026-10-08 | Supabase Storage | Provisions `receipts` storage bucket and security policies. |
| `20261009_fix_storage_policies_and_receipt_cleanup.sql` | 2026-10-09 | Storage, Triggers | Cascade deletion of receipt image files when transactions are deleted. |
| `20261009_hardened_security_and_storage_policies.sql` | 2026-10-09 | Storage, RLS | Enforces strict folder-level isolation (`household_id/year/month/file`). |
| `20261010_add_household_monthly_income.sql` | 2026-10-10 | `households` | Adds baseline monthly income baseline for budgeting. |
| `20261011_household_dependents_and_subcategories.sql` | 2026-10-11 | `household_dependents` | Tracks children/dependents, allowances, and attribution. |
| `20261011_hybrid_category_lifecycle.sql` | 2026-10-11 | `categories` | Supports standard vs custom category lifecycles and archiving. |
| `20261015_family_nafaqah_and_multi_roommate_settlement.sql` | 2026-10-15 | `reimbursement_debts` | Tracks husband-to-wife Nafaqah debt and roommate debts. |
| `20261015_manual_members_and_claim_merge.sql` | 2026-10-15 | `users`, `household_invites`| Supports pre-account placeholder members and claim-on-join. |
| `20261018_multi_source_income_and_accounts.sql` | 2026-10-18 | `accounts`, `transfers`, `income_records` | Introduces liquid accounts, transfers, multi-source income, and budget links. |
| `20261020300000_nafaqah_wife_allowance_and_reimbursements.sql` | 2026-10-20 | `transactions.nafaqah_class` / `nafaqah_spouse_id`, `member_allowances`, `spouse_reimbursements`, RPCs `set_member_allowance`, `get_member_allowance_status`, `record_spouse_reimbursement`, `get_spouse_reimbursement_balance` | Family Nafaqah (UI-24): wife reimbursement ledger (append-only, overpayment rejected under an advisory lock) and per-cycle wife allowance; RLS read inside the household, writes only via `SECURITY DEFINER` RPCs with pinned `search_path`; proof test `supabase/tests/19_nafaqah_allowance_and_reimbursements.sql`. |

---

## 6. Test Suite & Quality Verification

### 6.1 Flutter Mobile Test Suite
- **Result:** `128 passed` across unit, model, and widget integration tests.
- **Coverage Areas:**
  - Account capacity status calculations (Zero-Based, Surplus Buffer, Deficit).
  - Inter-account transfer balances and fee handling.
  - Payday income logging and salary breakdown.
  - Rollover settings (Option A cushion vs Option C savings sweep).
  - Targeted member claim-on-join welcome banners.
  - Nafaqah spousal reimbursement metrics and debt display.
  - Multi-roommate debt simplification calculations.
  - ZATCA TLV barcode parsing and status badge rendering.
  - Offline sync queue behavior and SQLite persistence.
- **Static Analysis:** `flutter analyze` runs with **0 issues found**.

### 6.2 Python AI Service Test Suite
- **Pytest Suite:** 121 collected tests covering OCR parsing, ZATCA TLV validation, salary cycle date math, duplicate candidate heuristics, and Arabic dialect chat parsing.

---

## 7. Documentation, Specifications & Rules Index

### 7.1 Engineering Rules (`.agents/rules/`)
- **[01. Architecture & Tech Stack](../.agents/rules/01-architecture-and-tech-stack.md)**: System topology, frameworks, communication protocols.
- **[02. Saudi Fintech & Islamic Compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**: 27th payday rules, ZATCA standard, Nafaqah debt enforcement.
- **[03. UI/UX & Design System](../.agents/rules/03-ui-ux-and-design-system.md)**: Sovereign OS & Iced Ocean palette, Daylight Coastal web theme, RTL trilingual rules.
- **[04. Security & Privacy](../.agents/rules/04-security-and-privacy.md)**: Zero SMS interception, Key segregation, RLS multi-tenancy.
- **[05. Code Quality & Testing](../.agents/rules/05-code-quality-and-testing.md)**: TDD workflow, zero analyzer warnings, production integrity.

### 7.2 Design Specifications (`docs/superpowers/specs/`)
- [Multi-Source Income & Accounts Balances Design (2026-10-18)](superpowers/specs/2026-10-18-multi-source-income-and-accounts-balances-design.md)
- [Manual Members & Claim Merge Design (2026-10-15)](superpowers/specs/2026-10-15-manual-members-and-claim-merge-design.md)
- [Family Nafaqah & Multi-Roommate Splits Design (2026-10-15)](superpowers/specs/2026-10-15-family-nafaqah-and-multi-roommate-splits-design.md)
- [Hybrid Category Lifecycle Design (2026-10-11)](superpowers/specs/2026-10-11-hybrid-category-lifecycle-and-landing-refresh-design.md)
- [Dependents & Subcategories Design (2026-10-11)](superpowers/specs/2026-10-11-dependents-and-hybrid-subcategories-design.md)
- [Multilingual Theming Support Design (2026-10-10)](superpowers/specs/2026-10-10-multilingual-theming-support-and-quick-budget-design.md)
- [User Guide & Support Hub Design (2026-10-09)](superpowers/specs/2026-10-09-user-guide-and-support-hub-design.md)
- [Receipt Image & QR Storage Design (2026-10-08)](superpowers/specs/2026-10-08-receipt-image-and-qr-storage-design.md)
- [Mobile Modularization & Offline Sync Design (2026-10-05)](superpowers/specs/2026-10-05-mobile-modularization-and-offline-sync-design.md)
- [Salary Cycle Rollover & Sub-Budgets Design (2026-10-02)](superpowers/specs/2026-10-02-salary-cycle-rollover-sub-budgets-design.md)

### 7.3 Implementation Plans (`docs/superpowers/plans/`)
- All 20 implementation plans are cataloged and linked in **[`docs/README.md`](README.md)**.
