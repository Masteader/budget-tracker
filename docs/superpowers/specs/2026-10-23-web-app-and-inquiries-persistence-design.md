# Hybrid Web Application & Persistent Lead Capture Design Spec

**Date:** 2026-10-23  
**Status:** Approved Design Spec  
**Target Areas:** 
- `web_app/` (React 19, TypeScript, Tailwind, Supabase JS Client)
- `ai_service/routes/inquiries.py` & `ai_service/mail_service.py`
- `supabase/migrations/20261024000000_create_inquiries_table.sql`

---

## 1. Executive Summary

### 1.1 Context
The Budget Tracker platform currently consists of:
1. A mobile application built in Flutter with 100% test coverage and Saudi fintech compliance (Payday cycles, ZATCA TLV barcode parsing, Nafaqah rules).
2. A FastAPI microservice (`ai_service`) deployed on Railway at `https://budget.fmsco.com.sa`.
3. A static marketing landing page built in React 19 + Vite (`web_app`).

### 1.2 Identified Problems
1. **Fragile Early-Access Lead Capture:** When unauthenticated visitors submit the VIP early-access form on the landing page, the backend previously relied exclusively on outbound email delivery (Resend / SMTP). Without configured mail provider credentials, the API returned `HTTP 503`, causing lead submissions to fail and be permanently lost.
2. **Missing Web Application Access:** Users who sign up cannot access or view their financial dashboard, active installment plans, recurring bills, or budgets from a desktop browser; they were strictly limited to the mobile APK.

### 1.3 Target Solution
1. **Persistent Lead Capture Layer:** Store all marketing leads and inquiries in a new `public.inquiries` PostgreSQL table in Supabase before attempting outbound email delivery. Early access signups succeed reliably (`200 OK`) and remain permanently recorded in the database.
2. **Hybrid Web Application:** Turn `web_app` into a seamless hybrid application:
   - **Unauthenticated Visitors:** Experience the fast, SEO-optimized marketing landing page with feature showcases and the early-access form.
   - **Authenticated Users:** Instantly transition into the Sovereign-styled Web HUD with three focused views:
     - **Dashboard:** Payday cycle countdown (27th), total income/spent/balance, active BNPL/installments cards, and recurring bills.
     - **Transactions Ledger:** Searchable, filterable ledger with quick manual entry.
     - **Budgets & Allocations:** Category budgets with visual progress bars, wife personal allowance ("مصروف الزوجة"), and sub-allocations.

---

## 2. Lead Capture & Inquiries Persistence

### 2.1 Database Schema (`supabase/migrations/20261024000000_create_inquiries_table.sql`)

```sql
CREATE TABLE IF NOT EXISTS public.inquiries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    type TEXT NOT NULL CHECK (type IN ('vip_early_access', 'support', 'contact')),
    email TEXT NOT NULL,
    name TEXT,
    message TEXT,
    locale TEXT DEFAULT 'ar',
    source TEXT DEFAULT 'web',
    reference TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'captured' CHECK (status IN ('captured', 'delivered', 'failed')),
    delivery_provider TEXT,
    error_detail TEXT
);

-- Indexes for rapid deduplication and audit sorting
CREATE INDEX IF NOT EXISTS idx_inquiries_email_type ON public.inquiries (email, type);
CREATE INDEX IF NOT EXISTS idx_inquiries_created_at ON public.inquiries (created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;

-- Anonymous public visitors can insert new inquiries (with rate-limiting enforced by backend)
CREATE POLICY "Public insert for inquiries"
    ON public.inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

-- No public SELECT: inquiries contain customer emails and are accessible only to service-role admins
```

### 2.2 Backend Pipeline Flow (`ai_service/routes/inquiries.py`)
1. **Validation & Honeypot:** Check email format; discard bot submissions silently if the honeypot field is filled.
2. **Guaranteed DB Capture:** Write the inquiry record to Supabase `public.inquiries` with status `captured`.
3. **Outbound Notification (Resend):** If `RESEND_API_KEY` is present, attempt delivery via `mail_service.send_email()`.
   - On success: update row status to `delivered`.
   - On failure or missing key: record error log, but keep the record saved in `public.inquiries`.
4. **Client Response:** Returns `{ "status": "captured", "reference": reference }` with `HTTP 200 OK`.

---

## 3. Hybrid Web Architecture & Navigation

### 3.1 State Diagram
```
                     ┌───────────────────────────────┐
                     │ Visitor Opens Landing Page    │
                     └──────────────┬────────────────┘
                                    │
                         [Supabase Auth Check]
                                    │
                   ┌────────────────┴────────────────┐
                   ▼                                 ▼
      [No Active Session]                   [Active Session]
                   │                                 │
                   ▼                                 ▼
        ┌──────────────────────┐          ┌──────────────────────┐
        │ Marketing Landing    │          │ Sovereign Web HUD    │
        │ - Hero & Features    │          │ - Navbar & Household │
        │ - Early Access Form  │          │ - Dashboard Tab      │
        │ - "Sign In" Button   │          │ - Transactions Tab   │
        └──────────┬───────────┘          │ - Budgets Tab        │
                   │                      └──────────┬───────────┘
            [User Signs In]                          │
                   │                           [User Logs Out]
                   └─────────────────────────────────┘
```

### 3.2 Top HUD Navigation Header
- **Brand & Household Badge:** App logo with active household name and member role (`رب الأسرة / Husband` or `Spouse / Member`).
- **Tab Switcher:**
  1. **لوحة التحكم (Dashboard)**
  2. **سجل العمليات (Transactions)**
  3. **الميزانيات والمخصصات (Budgets & Allocations)**
- **Language Switcher:** Instant toggle between Arabic (`ar`, RTL) and English (`en`, LTR).
- **User Profile & Logout:** Displays current user email and provides a 1-click logout returning to the landing page.

---

## 4. Web Application Views

### 4.1 View 1: Dashboard (Overview, Installments & Recurring Bills)
1. **Saudi Payday Cycle Card:**
   - Visual countdown to next salary (defaults to 27th of the month or household custom `payday_day`).
   - Current salary cycle window (e.g. *27 سبتمبر – 26 أكتوبر*).
2. **Account Balance Metric Cards:**
   - **Monthly Income (إجمالي الدخل):** Sum of active cycle income.
   - **Total Spent (إجمالي المصروفات):** Real-time sum of debits.
   - **Remaining Balance (الرصيد المتبقي):** Net funds with health indicator (Green >20%, Amber <20%, Red negative).
3. **Active Installment Plans Card (الأقساط الشهرية والتمويل):**
   - Active BNPL records (`Tamara`, `Tabby`, Bank financing) fetched from `installment_plans`.
   - Displays merchant name, provider tag, monthly amount (`SAR`), due day, and progress (e.g., *القسط 2 من 4*).
4. **Recurring Bills Card (الفواتير والاشتراكات الدورية):**
   - Recurring household bills (Telecom/STC, Utilities, Subscriptions).
   - Status indicators (*مسددة Paid* vs *مستحقة Due*) and total monthly obligation.
5. **Recent Transactions Preview:**
   - Quick preview of the last 5 transactions with 1-click navigation to the full ledger.

### 4.2 View 2: Transactions Ledger
1. **Search & Filtering:**
   - Real-time search across merchant, description, and notes.
   - Category filtering (*التموين, السكن, المطاعم, النقل, الشخصي*).
   - Payment method filtering (*مدى Mada, Apple Pay, STC Pay, Cash*).
2. **Interactive Ledger Table:**
   - Date, Merchant / Description, Category Badge, Payment Method, and Amount in SAR (`ر.س`).
   - Clean tabular view on desktop and responsive cards on mobile screens.
3. **"+ New Transaction" Quick Logging Modal:**
   - Fields: Amount, Category, Description, Date, Payment Method.
   - Saves directly to Supabase `transactions` with automatic household tenancy enforcement.

### 4.3 View 3: Budgets & Allocations
1. **Category Budgets:**
   - Visual progress bars comparing Allocated vs Spent per category.
   - Color health thresholds: Green (<80%), Amber (80–100%), Red (>100% exceeded).
2. **Wife Personal Allowance Card ("مصروف الزوجة"):**
   - Displays designated personal allowance for the current cycle.
   - Displays total personal expenses logged and remaining allowance.
3. **Sub-Allocations / Dependents:**
   - Itemized view of allocations designated for family members or specialized sub-categories.

---

## 5. Security & Multi-Tenancy

1. **Client Security:** Uses `@supabase/supabase-js` initialized only with the public anon key. The user's authenticated Supabase JWT is passed with every request.
2. **Row Level Security (RLS):** All data queries for `transactions`, `installment_plans`, `budgets`, and `member_allowances` strictly enforce `household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid())`.
3. **Anonymous Protection:** Inquiries table allows anonymous inserts but completely forbids anonymous reads to protect customer contact data.

---

## 6. Verification & Testing Plan

1. **Database & Migrations:** Verify migration syntax, table creation, and RLS policies using local PostgreSQL scripts.
2. **Backend Tests:** Run `pytest` on `ai_service` to confirm inquiry persistence and Resend delivery mocking.
3. **Web Build & Linting:** Run `npm run lint` (`oxlint`) and `npm run build` in `web_app/` to ensure 0 TypeScript or styling issues.
4. **End-to-End User Flow:** Test public landing page view $\rightarrow$ auth modal $\rightarrow$ authenticated dashboard rendering $\rightarrow$ logout transition.
