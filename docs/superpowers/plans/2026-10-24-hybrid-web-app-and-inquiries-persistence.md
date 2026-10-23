# Hybrid Web Application & Persistent Lead Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent PostgreSQL lead-capture layer for landing page signups and transform the React 19 web app into a hybrid application where unauthenticated visitors see the marketing landing page and logged-in users access their account Dashboard, Transactions ledger, and Budgets/Allowance.

**Architecture:** A new Supabase `public.inquiries` table stores early access and contact inquiries prior to Resend email delivery. In `web_app/`, `@supabase/supabase-js` provides client authentication. When unauthenticated, visitors see the Daylight Coastal landing page; once logged in, the app switches to an authenticated portal shell with 3 tabs: Dashboard (Payday countdown, balances, BNPL installments, recurring bills), Transactions (searchable ledger and logging), and Budgets & Allocations (category progress bars and wife personal allowance).

**Tech Stack:** React 19, TypeScript, Tailwind CSS (Daylight Coastal palette: `ink`, `teal`, `teal-dark`, `line`, `bg`, `sand`), `@supabase/supabase-js`, Python FastAPI, Supabase PostgreSQL with RLS.

**Spec:** [`docs/superpowers/specs/2026-10-23-web-app-and-inquiries-persistence-design.md`](docs/superpowers/specs/2026-10-23-web-app-and-inquiries-persistence-design.md)

## Global Constraints
- UI Theme: Must use the website's existing Daylight Coastal palette (`#006575` teal, `#004b57` teal-dark, `#0c2530` ink, `#46616b` muted, `#d5e5e9` line, `#f4fafb` bg) and typography (`"IBM Plex Sans Arabic"`, `"IBM Plex Sans"`).
- Strict RTL/LTR support: Dynamic document direction switching (`dir="rtl"` for Arabic, `dir="ltr"` for English).
- Zero SMS / Zero live API secrets in client: Only public Supabase URL and anon key used on frontend; all private operations protected by Supabase RLS.
- Database Multi-Tenancy: All user data queries must isolate by authenticated user's `household_id`.
- Zero compiler or lint errors: `oxlint` and `tsc -b` must pass with zero issues.

---

### Task 1: Supabase Inquiries Migration & Security Policies

**Files:**
- Create: `supabase/migrations/20261024000000_create_inquiries_table.sql`
- Create: `supabase/tests/20_inquiries_persistence.sql`

**Interfaces:**
- Consumes: PostgreSQL `gen_random_uuid()`, Supabase auth schema
- Produces: `public.inquiries` table accessible for anonymous INSERT, read-protected from public

- [ ] **Step 1: Write the database migration**

```sql
-- Migration: 20261024000000_create_inquiries_table.sql
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

CREATE INDEX IF NOT EXISTS idx_inquiries_email_type ON public.inquiries (email, type);
CREATE INDEX IF NOT EXISTS idx_inquiries_created_at ON public.inquiries (created_at DESC);

ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous and authenticated insert into inquiries"
    ON public.inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);
```

- [ ] **Step 2: Write verification SQL test**

Create `supabase/tests/20_inquiries_persistence.sql` testing:
1. Anonymous insert succeeds.
2. Select by anonymous role is denied by RLS.
3. Reference uniqueness constraint is enforced.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20261024000000_create_inquiries_table.sql supabase/tests/20_inquiries_persistence.sql
git commit -m "feat(db): add inquiries table migration and RLS policies"
```

---

### Task 2: Backend Persistent Inquiries Capture in `ai_service`

**Files:**
- Modify: `ai_service/routes/inquiries.py`
- Test: `ai_service/tests/test_inquiries_db_persistence.py`

**Interfaces:**
- Consumes: `PublicInquiry` model, `supabase_client`
- Produces: `POST /public/inquiries` recording to DB first, returning `{ "status": "captured", "reference": "..." }`

- [ ] **Step 1: Write the failing unit test**

Create `ai_service/tests/test_inquiries_db_persistence.py`:
```python
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_public_inquiry_persists_to_db_even_if_resend_fails():
    with patch("routes.inquiries._persist_inquiry") as mock_db, \
         patch("mail_service.active_provider", return_value=None):
        mock_db.return_value = True
        response = client.post(
            "/public/inquiries",
            json={
                "type": "vip_early_access",
                "email": "lead@example.com",
                "locale": "ar",
                "source": "web"
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert data["status"] in ("captured", "sent")
        assert "reference" in data
        mock_db.assert_called_once()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ai_service && python -m pytest tests/test_inquiries_db_persistence.py`
Expected: FAIL (`_persist_inquiry` does not exist or 503 returned)

- [ ] **Step 3: Implement database persistence in `routes/inquiries.py`**

Add `_persist_inquiry(...)` helper to insert inquiry record into Supabase `inquiries` table before calling `_deliver(...)`. If `mail_service.active_provider()` is None or Resend fails, log the provider status and return `{"status": "captured", "reference": reference}` with status 200 instead of failing with 503.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ai_service && python -m pytest tests/test_inquiries_db_persistence.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ai_service/routes/inquiries.py ai_service/tests/test_inquiries_db_persistence.py
git commit -m "feat(api): persist early-access inquiries to database before email dispatch"
```

---

### Task 3: Install `@supabase/supabase-js` and Auth Context in `web_app`

**Files:**
- Modify: `web_app/package.json`
- Create: `web_app/src/lib/supabaseClient.ts`
- Create: `web_app/src/context/AuthContext.tsx`
- Test: `web_app/src/lib/supabaseClient.test.ts`

**Interfaces:**
- Consumes: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
- Produces: `supabase` client instance, `useAuth()` hook with `{ user, session, loading, signOut, signIn, signUp }`

- [ ] **Step 1: Install `@supabase/supabase-js`**

Run: `cd web_app && npm install @supabase/supabase-js`

- [ ] **Step 2: Implement `web_app/src/lib/supabaseClient.ts`**

Initialize Supabase client using public URL `https://qnhyiszgiymsypcwnntu.supabase.co` and anon key fallback.

- [ ] **Step 3: Implement `web_app/src/context/AuthContext.tsx`**

Create React Context providing:
- `session: Session | null`
- `user: User | null`
- `loading: boolean`
- `householdId: string | null` (resolved from `public.users` table)
- `signIn(email, password)`
- `signUp(email, password, displayName)`
- `signOut()`
- `refreshHousehold()`

- [ ] **Step 4: Verify TypeScript compilation**

Run: `cd web_app && npm run build`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add web_app/package.json web_app/package-lock.json web_app/src/lib/supabaseClient.ts web_app/src/context/AuthContext.tsx
git commit -m "feat(web): add supabase client and AuthContext provider"
```

---

### Task 4: Daylight Coastal Auth Modal Component

**Files:**
- Create: `web_app/src/components/auth/AuthModal.tsx`
- Modify: `web_app/src/components/Header.tsx`
- Modify: `web_app/src/i18n/translations.ts`

**Interfaces:**
- Consumes: `useAuth()`, `dict` translations, `lang`
- Produces: Modal with Tab toggles ("تسجيل الدخول / Sign In" vs "إنشاء حساب / Sign Up"), form inputs, validation error alerts

- [ ] **Step 1: Add authentication translation strings**

Update `web_app/src/i18n/translations.ts` with bilingual strings for Sign In, Sign Up, Email, Password, Name, Submit, Error, and Switch Tab.

- [ ] **Step 2: Implement `web_app/src/components/auth/AuthModal.tsx`**

Build dialog with:
- Backdrop blur with `bg-ink/40`.
- Card container styled with `bg-white border border-line rounded-3xl p-6 sm:p-8 shadow-xl`.
- Tab switcher: Sign In / Create Account.
- Form fields with `focus:ring-2 focus:ring-teal`.
- Error messages in soft red container.
- Close button (Escape key and click outside).

- [ ] **Step 3: Connect "Sign In" button in `Header.tsx`**

Add "تسجيل الدخول / Sign In" button to `Header.tsx` navbar that triggers `setAuthModalOpen(true)`.

- [ ] **Step 4: Verify build and lint**

Run: `cd web_app && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add web_app/src/components/auth/AuthModal.tsx web_app/src/components/Header.tsx web_app/src/i18n/translations.ts
git commit -m "feat(web): add Daylight Coastal AuthModal and login trigger in Header"
```

---

### Task 5: Authenticated Portal Shell & HUD Navigation

**Files:**
- Create: `web_app/src/components/portal/PortalHeader.tsx`
- Create: `web_app/src/components/portal/PortalShell.tsx`
- Modify: `web_app/src/App.tsx`

**Interfaces:**
- Consumes: `useAuth()`, active tab state (`'dashboard' | 'transactions' | 'budgets'`)
- Produces: Authenticated app shell rendering active view, top navigation, household badge, language toggle, and logout

- [ ] **Step 1: Implement `PortalHeader.tsx`**

Header with:
- Logo + "Budget Tracker" title.
- Household indicator chip (`bg-teal-soft text-teal-dark rounded-full px-3 py-1`).
- Navigation tabs: `Dashboard` (لوحة التحكم), `Transactions` (سجل العمليات), `Budgets` (الميزانيات والمخصصات).
- Arabic / English toggle button.
- User email chip and "خروج / Sign Out" button.

- [ ] **Step 2: Implement `PortalShell.tsx`**

Manages active tab state and wraps portal views in `min-h-screen bg-bg text-ink`.

- [ ] **Step 3: Update `web_app/src/App.tsx`**

Wrap app with `<AuthProvider>`. If `session` is present, render `<PortalShell />`; if `session` is null, render the existing marketing landing page (`<Header>`, `<Hero>`, `<Features>`, `<EarlyAccess>`, etc.).

- [ ] **Step 4: Verify build and lint**

Run: `cd web_app && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add web_app/src/components/portal/PortalHeader.tsx web_app/src/components/portal/PortalShell.tsx web_app/src/App.tsx
git commit -m "feat(web): implement hybrid switching between landing page and authenticated portal shell"
```

---

### Task 6: Tab 1 — Dashboard View (Payday Cycle, Balances, BNPL Installments & Recurring Bills)

**Files:**
- Create: `web_app/src/components/portal/DashboardView.tsx`
- Create: `web_app/src/lib/cycleUtils.ts`

**Interfaces:**
- Consumes: `householdId` from `useAuth()`, Supabase queries for `installment_plans`, `transactions`, `recurring_bills`
- Produces: Rich dashboard view displaying payday countdown, 3 summary cards, installments card, and recurring bills card

- [ ] **Step 1: Implement cycle arithmetic utility `web_app/src/lib/cycleUtils.ts`**

Calculate days remaining until next 27th (Saudi payday), cycle start/end dates, and cycle key (e.g. `2026-10-27`).

- [ ] **Step 2: Implement `DashboardView.tsx`**

Build:
1. **Payday Countdown Banner:** Days remaining with visual calendar indicator.
2. **Account Balances Grid:** Monthly Income, Total Spent, and Net Remaining balance formatted with `ر.س`.
3. **Active Installment Plans Card:** Query `public.installment_plans` for `status = 'ACTIVE'`; display merchant, provider badge (Tamara / Tabby), monthly amount, due date, and installment progress (e.g. *القسط 2 من 4*).
4. **Recurring Bills Card:** Display recurring obligations with status tags (*مسددة Paid* vs *مستحقة Due*).
5. **Recent Transactions Preview:** Table preview of latest 5 transactions.

- [ ] **Step 3: Verify build and lint**

Run: `cd web_app && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add web_app/src/components/portal/DashboardView.tsx web_app/src/lib/cycleUtils.ts
git commit -m "feat(web): add Dashboard view with payday cycle, balances, installments, and bills"
```

---

### Task 7: Tab 2 — Transactions Ledger View & Quick Logging Modal

**Files:**
- Create: `web_app/src/components/portal/TransactionsView.tsx`
- Create: `web_app/src/components/portal/NewTransactionModal.tsx`

**Interfaces:**
- Consumes: Supabase `transactions` table
- Produces: Filterable transactions table with search, category filtering, and "+ New Transaction" modal

- [ ] **Step 1: Implement `TransactionsView.tsx`**

Features:
- Real-time search bar (by description/merchant).
- Category filter dropdown.
- Responsive table with Date, Description, Category Badge, Payment Method (Mada, Apple Pay, Cash), and Amount.
- "+ إضافة عملية / New Transaction" trigger button.

- [ ] **Step 2: Implement `NewTransactionModal.tsx`**

Form modal:
- Inputs: Amount (SAR), Description, Category select, Date picker, Payment method.
- Submits directly to Supabase `transactions` table with current `household_id`.
- Automatically refreshes the transactions feed upon success.

- [ ] **Step 3: Verify build and lint**

Run: `cd web_app && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add web_app/src/components/portal/TransactionsView.tsx web_app/src/components/portal/NewTransactionModal.tsx
git commit -m "feat(web): add Transactions ledger view and new transaction modal"
```

---

### Task 8: Tab 3 — Budgets & Allocations View

**Files:**
- Create: `web_app/src/components/portal/BudgetsView.tsx`

**Interfaces:**
- Consumes: Supabase `budgets`, `member_allowances` tables
- Produces: Category budgets progress bars, wife personal allowance card, and sub-allocations

- [ ] **Step 1: Implement `BudgetsView.tsx`**

Features:
1. **Category Budgets Grid:** Card for each budget category showing allocated vs spent with percentage progress bar and health status tag (Green normal, Amber warning, Red exceeded).
2. **Wife Personal Allowance Card ("مصروف الزوجة"):** Fetches allowance from `public.member_allowances`; computes total spent from `wife_personal` transactions; shows remaining balance.
3. **Sub-Allocations Breakdown:** Displays allocated amounts for household dependents and custom sub-categories.

- [ ] **Step 2: Verify build and lint**

Run: `cd web_app && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add web_app/src/components/portal/BudgetsView.tsx
git commit -m "feat(web): add Budgets and Allocations view with wife allowance integration"
```

---

### Task 9: Full Verification Gate & Build Validation

**Files:**
- Touch: All modified/created files

- [ ] **Step 1: Run Python tests in `ai_service`**

Run: `cd ai_service && python -m pytest tests/test_inquiries_db_persistence.py -v`
Expected: All tests pass (100% green).

- [ ] **Step 2: Run Flutter tests to ensure no regressions**

Run: `cd flutter_app && flutter analyze && flutter test test/services/client_config_test.dart`
Expected: 0 analyze issues, all tests pass.

- [ ] **Step 3: Run web linting and production build**

Run: `cd web_app && npm run lint && npm run build`
Expected: 0 lint issues, production bundle built cleanly in `web_app/dist/`.

- [ ] **Step 4: Final verification commit**

```bash
git status
git commit -am "chore: complete verification for hybrid web app and inquiries persistence"
```
