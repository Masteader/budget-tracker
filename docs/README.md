# Budget Tracker — Documentation Hub

Central documentation index for **Budget Tracker**, the AI-powered household finance app for Saudi
families and shared homes. Setup, environment variables, test commands and the deployment order
live in the root [`README.md`](../README.md).

---

## Quick Links

- 📋 **[Full Project Details](PROJECT_DETAILS.md)** — architecture, features, API endpoints, migrations and test suites.
- 🔐 **[Operational Runbooks](runbooks/)** — secret rotation.
- 🔎 **[Review & Audit](review/)** — audit reports, fix log, owner actions, live DB pre-flight and rollback snapshots.
- 📜 **[Project Rules](../.agents/rules/)** — engineering, design, security and fintech standards.
- 📐 **[Design Specifications](superpowers/specs/)** and 🛠️ **[Implementation Plans](superpowers/plans/)** — historical; the code and the rules above win where they differ.

---

## 1. Documentation Structure

```
docs/
├── README.md                    # This index
├── PROJECT_DETAILS.md           # Project dossier (features, API, migrations, tests)
├── runbooks/
│   └── security-secret-rotation.md
├── review/                      # Audit work (maintained by the review agents)
│   ├── FIX_LOG.md               # Finding → proof test → fix → applied to live?
│   ├── OWNER_ACTIONS.md         # Key rotation, keystore, email DNS for the owner
│   ├── audit/                   # MASTER_AUDIT_REPORT.md, per-area reports, live DB pre-flight
│   └── rollback/                # Rollback snapshots for applied migration batches
└── superpowers/                 # Historical specs and plans (not updated after the fact)
    ├── specs/                   # 11 design specifications
    └── plans/                   # 21 implementation plans
```

---

## 2. Design Specifications Catalog

| Spec Document | Date | Subsystem / Focus | Core Idea |
|---|---|---|---|
| [Multi-Household & Advanced Scanner](superpowers/specs/2026-10-18-multi-household-and-advanced-scanner-design.md) | 2026-10-18 | Households, Scanner | Household switching via memberships, on-device OCR fallback, sequential batch scanning. |
| [Multi-Source Income & Accounts Balances](superpowers/specs/2026-10-18-multi-source-income-and-accounts-balances-design.md) | 2026-10-18 | Accounts, Income, Capacity | Bank/wallet ledger, payday distribution assistant, budget capacity deficit validation. |
| [Manual Members & Claim Merge](superpowers/specs/2026-10-15-manual-members-and-claim-merge-design.md) | 2026-10-15 | Household Onboarding | Placeholder member profiles claimed via targeted invite codes on join. |
| [Family Nafaqah & Multi-Roommate Settlement](superpowers/specs/2026-10-15-family-nafaqah-and-multi-roommate-settlement-design.md) | 2026-10-15 | Settlements & Sharia | No 50/50 spousal splits; wife reimbursement debt; multi-way roommate debt graph. Superseded in detail by rules 1–4 in [`02-…`](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md). |
| [Hybrid Category Lifecycle & Library](superpowers/specs/2026-10-11-hybrid-category-lifecycle-and-library-design.md) | 2026-10-11 | Categories & Budgets | Standard vs custom categories with archiving, re-activation and inactive-category resolution. |
| [Dependents & Subcategories](superpowers/specs/2026-10-11-dependents-and-hybrid-subcategories-design.md) | 2026-10-11 | Household Dependents | Child allowances, dependent expense attribution, sub-budget allocations per child. |
| [Multilingual Theming Support & Savings](superpowers/specs/2026-10-10-multilingual-theming-support-and-savings-design.md) | 2026-10-10 | UI / Localization | Trilingual support (Arabic RTL, English, Urdu) and theme tokens. |
| [User Guide & Support Hub](superpowers/specs/2026-10-09-user-guide-and-support-hub-design.md) | 2026-10-09 | Onboarding & Support | Interactive walkthrough and integrated AI support assistant. |
| [Receipt Image & QR Storage](superpowers/specs/2026-10-08-receipt-image-and-qr-storage-design.md) | 2026-10-08 | Scanner & Storage | `receipts` storage bucket (now private), photo strip, zoomable viewer. |
| [Mobile Modularization & Offline Sync](superpowers/specs/2026-10-05-mobile-modularization-and-offline-sync-design.md) | 2026-10-05 | Client Architecture | Offline SQLite transaction buffer, network listener, background sync. |
| [Salary Cycle Rollover & Sub-Budgets](superpowers/specs/2026-10-02-salary-cycle-rollover-sub-budgets-design.md) | 2026-10-02 | Financial Engine | Payday cycles (now per household), sub-category allocations, rollover strategies. |

---

## 3. Implementation Plans by Domain

### 💰 Accounts, Income & Budgets
- **[2026-10-18: Multi-Source Income & Accounts Balances](superpowers/plans/2026-10-18-multi-source-income-and-accounts-balances.md)**
- **[2026-10-02: Salary Cycle Rollover Sub-Budgets](superpowers/plans/2026-10-02-salary-cycle-rollover-sub-budgets.md)**
- **[2026-10-02: Sub-Category Budget Allocations](superpowers/plans/2026-10-02-sub-category-budget-allocations.md)**

### 🧾 Scanner, OCR & Conversational AI
- **[2026-09-25: Realtime Chat Receipt Ingestion](superpowers/plans/2026-09-25-realtime-chat-receipt-ingestion.md)** — Vision OCR, ZATCA TLV decoder, Saudi dialect chat parser.
- **[2026-10-08: Receipt Image & QR Storage](superpowers/plans/2026-10-08-receipt-image-and-qr-storage.md)** — Multi-page scanning, photo strips, storage bucket.
- **[2026-10-18: Multi-Household & Advanced Scanner](superpowers/plans/2026-10-18-multi-household-and-advanced-scanner.md)** — Household switching, OCR fallback, batch scanning.

### 👨‍👩‍👧‍👦 Household, Nafaqah & Roommate Settlements
- **[2026-10-15: Family Nafaqah & Multi-Roommate Settlement](superpowers/plans/2026-10-15-family-nafaqah-and-multi-roommate-settlement.md)**
- **[2026-10-15: Manual Members & Claim Merge](superpowers/plans/2026-10-15-manual-members-and-claim-merge.md)**
- **[2026-10-11: Dependents & Hybrid Subcategories](superpowers/plans/2026-10-11-dependents-and-hybrid-subcategories.md)**
- **[2026-10-11: Hybrid Category Lifecycle & Library](superpowers/plans/2026-10-11-hybrid-category-lifecycle-and-library.md)**

### 🔄 Recurring Bills & BNPL Installments
- **[2026-10-05: Recurring Bills Predictor](superpowers/plans/2026-10-05-recurring-bills-predictor.md)**
- **[2026-10-05: BNPL Installments Tracker](superpowers/plans/2026-10-05-bnpl-installments-tracker.md)** — Tabby, Tamara and bank installment plans.

### 📱 Mobile Architecture & Offline
- **[2026-10-05: Mobile Modularization Part 2](superpowers/plans/2026-10-05-mobile-modularization-part-2.md)**
- **[2026-10-05: Offline SQLite Sync Engine](superpowers/plans/2026-10-05-offline-sqlite-sync-engine.md)**

### 🎨 UI, Localization & Web
- **[2026-10-11: Landing Page Redesign](superpowers/plans/2026-10-11-landing-page-redesign.md)** (historical: the generated landing it describes was removed; the landing page is `web_app/`)
- **[2026-10-10: Multilingual Theming Support & Savings](superpowers/plans/2026-10-10-multilingual-theming-support-and-savings.md)**
- **[2026-10-13: Multilingual L10n & Category Dedup](superpowers/plans/2026-10-13-multilingual-l10n-and-category-dedup.md)**
- **[2026-10-12: Bugfix — Budgets, Theme, L10n, Installments](superpowers/plans/2026-10-12-bugfix-budgets-theme-l10n-installments.md)**
- **[2026-10-09: User Guide & Support Hub](superpowers/plans/2026-10-09-user-guide-and-support-hub.md)**

### 🔒 Security & Infrastructure
- **[2026-10-15: Security Hardening](superpowers/plans/2026-10-15-security-hardening.md)**
- **[2026-10-07: Render Cloud Backend & Remove SMS](superpowers/plans/2026-10-07-render-cloud-backend-and-remove-sms.md)** — Cloud backend and removal of SMS ingestion.

Later security, database and permission work (October 19–20) is recorded in
[`review/FIX_LOG.md`](review/FIX_LOG.md) and [`review/audit/MASTER_AUDIT_REPORT.md`](review/audit/MASTER_AUDIT_REPORT.md).

---

## 4. Engineering Standards & Rules

- **[01. Architecture & Tech Stack](../.agents/rules/01-architecture-and-tech-stack.md)**
- **[02. Saudi Fintech & Islamic Compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**
- **[03. UI/UX & Design System](../.agents/rules/03-ui-ux-and-design-system.md)**
- **[04. Security & Privacy](../.agents/rules/04-security-and-privacy.md)**
- **[05. Code Quality & Testing](../.agents/rules/05-code-quality-and-testing.md)**
