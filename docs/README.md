# Budget Tracker — Documentation Hub

Welcome to the central documentation hub for **Budget Tracker**, the AI-powered household financial operating system engineered for Saudi families and shared living communities.

---

## Quick Links

- 📋 **[Full Project Details](PROJECT_DETAILS.md)** — Comprehensive architecture, feature breakdown, database schemas, and roadmap.
- 📐 **[Design Specifications](superpowers/specs/)** — Architectural blueprints and functional specifications.
- 🛠️ **[Implementation Plans](superpowers/plans/)** — Task-by-task execution plans and verified milestones.
- 🔐 **[Operational Runbooks](runbooks/)** — Security, secret rotation, and deployment guides.
- 📜 **[Project Rules](../.agents/rules/)** — Core engineering, design, security, and fintech standards.

---

## 1. Documentation Structure

```
docs/
├── README.md                                          # This Master Documentation Index
├── PROJECT_DETAILS.md                                 # Full Project Dossier (Applied vs Planned)
├── runbooks/
│   └── security-secret-rotation.md                    # Key rotation & emergency procedure
└── superpowers/
    ├── specs/                                         # Architectural Design Specifications
    │   ├── 2026-10-02-salary-cycle-rollover-sub-budgets-design.md
    │   ├── 2026-10-05-mobile-modularization-and-offline-sync-design.md
    │   ├── 2026-10-08-receipt-image-and-qr-storage-design.md
    │   ├── 2026-10-09-user-guide-and-support-hub-design.md
    │   ├── 2026-10-10-multilingual-theming-support-and-quick-budget-design.md
    │   ├── 2026-10-11-dependents-and-hybrid-subcategories-design.md
    │   ├── 2026-10-11-hybrid-category-lifecycle-and-landing-refresh-design.md
    │   ├── 2026-10-15-family-nafaqah-and-multi-roommate-splits-design.md
    │   ├── 2026-10-15-manual-members-and-claim-merge-design.md
    │   └── 2026-10-18-multi-source-income-and-accounts-balances-design.md
    └── plans/                                         # Implementation Plans & Checklists
        ├── 2026-09-25-realtime-chat-receipt-ingestion.md
        ├── 2026-10-02-salary-cycle-rollover-sub-budgets.md
        ├── 2026-10-02-sub-category-budget-allocations.md
        ├── 2026-10-05-bnpl-installments-tracker.md
        ├── 2026-10-05-mobile-modularization-part-2.md
        ├── 2026-10-05-offline-sqlite-sync-engine.md
        ├── 2026-10-05-recurring-bills-predictor.md
        ├── 2026-10-07-render-cloud-backend-and-remove-local-fastapi.md
        ├── 2026-10-08-receipt-image-and-qr-storage.md
        ├── 2026-10-09-user-guide-and-support-hub.md
        ├── 2026-10-10-multilingual-theming-support-and-quick-budget.md
        ├── 2026-10-11-dependents-and-hybrid-subcategories.md
        ├── 2026-10-11-hybrid-category-lifecycle-and-landing-refresh.md
        ├── 2026-10-11-landing-page-redesign.md
        ├── 2026-10-12-bugfix-budgets-theme-l10n-installments.md
        ├── 2026-10-13-multilingual-l10n-and-category-analytics.md
        ├── 2026-10-15-family-nafaqah-and-multi-roommate-splits.md
        ├── 2026-10-15-manual-members-and-claim-merge.md
        ├── 2026-10-15-security-hardening.md
        └── 2026-10-18-multi-source-income-and-accounts-balances.md
```

---

## 2. Design Specifications Catalog

| Spec Document | Date | Subsystem / Focus | Core Innovation |
|---|---|---|---|
| [Multi-Source Income & Accounts Balances](superpowers/specs/2026-10-18-multi-source-income-and-accounts-balances-design.md) | 2026-10-18 | Accounts, Income, Capacity | Bank/Wallet ledger, payday distribution assistant, budget capacity deficit validation. |
| [Manual Members & Claim Merge](superpowers/specs/2026-10-15-manual-members-and-claim-merge-design.md) | 2026-10-15 | Household Onboarding | Pre-account placeholder member profiles claimed via targeted invite codes on join. |
| [Family Nafaqah & Multi-Roommate Splits](superpowers/specs/2026-10-15-family-nafaqah-and-multi-roommate-splits-design.md) | 2026-10-15 | Settlements & Sharia | Prohibiting arbitrary 50/50 spousal splits; tracking wife reimbursement debt; multi-way roommate debt graph. |
| [Hybrid Category Lifecycle](superpowers/specs/2026-10-11-hybrid-category-lifecycle-and-landing-refresh-design.md) | 2026-10-11 | Categories & Budgets | Standard vs Custom categories with archiving, re-activation, and inactive category transaction resolution. |
| [Dependents & Subcategories](superpowers/specs/2026-10-11-dependents-and-hybrid-subcategories-design.md) | 2026-10-11 | Household Dependents | Child allowances, dependent expense attribution, sub-budget allocations per child. |
| [Multilingual Theming Support](superpowers/specs/2026-10-10-multilingual-theming-support-and-quick-budget-design.md) | 2026-10-10 | UI / Localization | Trilingual support (Arabic RTL, English, Urdu) and Sovereign OS / Iced Ocean theme tokens. |
| [User Guide & Support Hub](superpowers/specs/2026-10-09-user-guide-and-support-hub-design.md) | 2026-10-09 | Onboarding & Support | 5-step interactive walkthrough dialog and integrated AI support assistant. |
| [Receipt Image & QR Storage](superpowers/specs/2026-10-08-receipt-image-and-qr-storage-design.md) | 2026-10-08 | Scanner & Storage | Supabase Storage `receipts` bucket, photo strip preview, full-screen zoomable photo viewer. |
| [Mobile Modularization & Offline Sync](superpowers/specs/2026-10-05-mobile-modularization-and-offline-sync-design.md) | 2026-10-05 | Client Architecture | Offline SQLite transaction buffer, network state listener, background sync engine. |
| [Salary Cycle Rollover & Sub-Budgets](superpowers/specs/2026-10-02-salary-cycle-rollover-sub-budgets-design.md) | 2026-10-02 | Financial Engine | Saudi 27th payday cycle, sub-category allocations, Option A/C rollover strategies. |

---

## 3. Implementation Plans by Domain

### 💰 Accounts, Income & Budgets
- **[2026-10-18: Multi-Source Income & Accounts Balances](superpowers/plans/2026-10-18-multi-source-income-and-accounts-balances.md)** — Fully implemented & tested (128 passing tests).
- **[2026-10-02: Salary Cycle Rollover Sub-Budgets](superpowers/plans/2026-10-02-salary-cycle-rollover-sub-budgets.md)** — Implemented in backend & mobile.
- **[2026-10-02: Sub-Category Budget Allocations](superpowers/plans/2026-10-02-sub-category-budget-allocations.md)** — Implemented in schema & mobile dialogs.

### 🧾 Scanner, OCR & Conversational AI
- **[2026-09-25: Realtime Chat Receipt Ingestion](superpowers/plans/2026-09-25-realtime-chat-receipt-ingestion.md)** — Gemini Vision OCR, ZATCA TLV barcode decoder, natural Saudi dialect chat parser.
- **[2026-10-08: Receipt Image & QR Storage](superpowers/plans/2026-10-08-receipt-image-and-qr-storage.md)** — Multi-page receipt scanning, photo strips, and Supabase Storage bucket.

### 👨‍👩‍👧‍👦 Household, Nafaqah & Roommate Settlements
- **[2026-10-15: Family Nafaqah & Multi-Roommate Splits](superpowers/plans/2026-10-15-family-nafaqah-and-multi-roommate-splits.md)** — Sharia-compliant Nafaqah spousal reimbursement and roommate debt simplification.
- **[2026-10-15: Manual Members & Claim Merge](superpowers/plans/2026-10-15-manual-members-and-claim-merge.md)** — Targeted invite codes, placeholder profile linking on join.
- **[2026-10-11: Dependents & Hybrid Subcategories](superpowers/plans/2026-10-11-dependents-and-hybrid-subcategories.md)** — Children/dependents tracking and allowances.

### 🔄 Recurring Bills & BNPL Installments
- **[2026-10-05: Recurring Bills Predictor](superpowers/plans/2026-10-05-recurring-bills-predictor.md)** — Heuristic recurrence detection, payday bill reserves.
- **[2026-10-05: BNPL Installments Tracker](superpowers/plans/2026-10-05-bnpl-installments-tracker.md)** — Tabby, Tamara, and bank installment plans with remaining payment schedules.

### 🎨 UI, Theming & Web Portal
- **[2026-10-11: Landing Page Redesign](superpowers/plans/2026-10-11-landing-page-redesign.md)** — Daylight Coastal RTL web landing page in React + TailwindCSS.
- **[2026-10-10: Multilingual Theming Support & Quick Budget](superpowers/plans/2026-10-10-multilingual-theming-support-and-quick-budget.md)** — Iced Ocean / Sovereign OS theme and trilingual support.

### 🔒 Security & Infrastructure
- **[2026-10-15: Security Hardening](superpowers/plans/2026-10-15-security-hardening.md)** — Elimination of obsolete 50/50 spousal cards, API firewall tokens, and RLS audit.
- **[2026-10-07: Render Cloud Backend & Remove Local FastAPI](superpowers/plans/2026-10-07-render-cloud-backend-and-remove-local-fastapi.md)** — Cloud deployment and mobile base URL configuration.

---

## 4. Engineering Standards & Rules

Refer to the official project rules:
- **[01. Architecture & Tech Stack](../.agents/rules/01-architecture-and-tech-stack.md)**
- **[02. Saudi Fintech & Islamic Compliance](../.agents/rules/02-saudi-fintech-and-islamic-compliance.md)**
- **[03. UI/UX & Design System](../.agents/rules/03-ui-ux-and-design-system.md)**
- **[04. Security & Privacy](../.agents/rules/04-security-and-privacy.md)**
- **[05. Code Quality & Testing](../.agents/rules/05-code-quality-and-testing.md)**
