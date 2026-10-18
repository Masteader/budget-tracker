# Multi-Source Income, Accounts & Balances, and Linked Budgets Design

**Date:** 2026-10-18  
**Author:** Pair Programming Session with User  
**Status:** Validated Design Spec  
**Target File / Migration:** `supabase/migrations/20261018_multi_source_income_and_accounts.sql`

---

## 1. Executive Summary & Problem Statement

### 1.1 Context
Previously, the application tracked income as a single static numeric value (`households.monthly_income`) and managed budgets as theoretical category caps for each salary cycle (e.g. 27th to 27th). 

### 1.2 Limitations of the Old Model
1. **Single Income Limitation:** Real-world users have multiple streams of income (Base Salary, Overtime, Bonuses, Side Gigs, Roommate Contributions, Crypto withdrawals).
2. **Disconnected from Real Cash Balances:** Users maintain multiple financial accounts (Traditional banks like Al Rajhi or SNB, E-wallets like STC Pay or Urpay, Crypto exchanges like Binance, and Physical Cash). The old budget system did not track where money actually resides.
3. **No Account Liquidity Verification:** A user could allocate 2,000 SAR to Groceries on STC Pay when STC Pay only had 800 SAR, causing unexpected card declines or off-app scrambling.
4. **Roommate Pooling Gap:** Flatmates or shared households need to track a shared contribution pool (e.g. 4 roommates × 350 SAR = 1,400 SAR) and verify if shared bills match this pool.

### 1.3 Target Solution
Introduce an **Accounts & Balances System** tightly integrated with **Budget Management** and **Payday Cycles**:
- **Multi-Source Income Streams:** Record detailed incoming funds into specific accounts.
- **Account Ledger & Balances:** Track Banks, E-wallets, Crypto, Cash, and Shared Household Pools.
- **Budget-to-Account Mapping:** Every category budget is mapped to a designated account that it consumes from.
- **Strict Capacity Validation:** Accounts must have sufficient balance to cover the total allocated budgets mapped to them. The app highlights deficits and provides 1-tap resolution shortcuts.
- **Payday Cycle Check-in:** On payday (e.g. the 27th), an automated prompt enables easy logging of salary with overtime, bonuses, deductions, and 1-tap inter-account distribution.
- **Cycle Rollover:** Provides explicit user choice for unspent funds (Option A: Category rollover cushion or Option C: Sweep into Savings).

---

## 2. Architecture & Data Model

### 2.1 Database Schema (`supabase/migrations/20261018_multi_source_income_and_accounts.sql`)

```sql
-- 1. Accounts Table
CREATE TABLE IF NOT EXISTS public.accounts (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id   UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    owner_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    account_type   TEXT NOT NULL CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool')),
    currency       TEXT NOT NULL DEFAULT 'SAR',
    balance        NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    is_shared_pool BOOLEAN NOT NULL DEFAULT false,
    color_hex      TEXT DEFAULT '#00E5BF',
    icon_name      TEXT DEFAULT 'account_balance_rounded',
    is_archived    BOOLEAN NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accounts_household ON public.accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_accounts_owner ON public.accounts(owner_user_id);

-- 2. Inter-Account Transfers Table
CREATE TABLE IF NOT EXISTS public.account_transfers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    from_account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    to_account_id   UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    amount          NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    fee             NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (fee >= 0),
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_transfers_household ON public.account_transfers(household_id);

-- 3. Multi-Source Income Records Table
CREATE TABLE IF NOT EXISTS public.income_records (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id  UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    account_id    UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    cycle_key     TEXT NOT NULL,
    source_type   TEXT NOT NULL CHECK (source_type IN ('salary', 'overtime', 'bonus', 'side_gig', 'roommate_share', 'other')),
    title         TEXT NOT NULL,
    base_amount   NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    overtime      NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    bonus         NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    deductions    NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    net_amount    NUMERIC(14, 2) NOT NULL,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_income_records_cycle ON public.income_records(household_id, cycle_key);

-- 4. Budget & Transaction Linkage
ALTER TABLE public.budgets 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_budgets_account ON public.budgets(account_id);

ALTER TABLE public.transactions 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_account ON public.transactions(account_id);
```

### 2.2 Row Level Security (RLS) Rules
- **Accounts:**
  - Owner users can view, insert, and update their personal accounts (`owner_user_id = auth.uid()`).
  - Household members can view accounts if `is_shared_pool = true` and `household_id` matches.
  - Admins can manage shared pools.
- **Transfers & Income Records:**
  - Household members can insert/view records associated with their accounts within their household.

---

## 3. Budget-to-Account Mapping & Capacity Validation

### 3.1 Mathematical Invariant
For every account $A$:
$$\text{Total Allocated Budgets}(A) = \sum_{B \in \text{Budgets where } B.\text{account\_id} = A.\text{id}} B.\text{allocated\_amount}$$
$$\text{Capacity Margin}(A) = A.\text{balance} - \text{Total Allocated Budgets}(A)$$

### 3.2 Capacity States & UI Indicators
1. **Healthy / Zero-Based ($\text{Margin} = 0$):**
   - Every single SAR in the account is allocated to a planned purpose.
   - Status Badge: `🟢 100% Allocated (Zero-Based)`.
2. **Surplus Buffer ($\text{Margin} > 0$):**
   - Unallocated funds remain in the account.
   - Status Badge: `🔵 +SAR X.XX Surplus Buffer`.
   - Actions: Keep as buffer, assign to savings, or transfer.
3. **Deficit / Over-Allocated ($\text{Margin} < 0$):**
   - The account balance is less than the budgets mapped to it.
   - Status Badge: `🔴 ⚠️ Deficit: -SAR X.XX`.
   - **Action Shortcuts in Alert Card:**
     - `[⚡ Quick Transfer]`: Opens Account Transfer sheet with destination pre-set to this account, source pre-set to the account with maximum surplus, and amount pre-set to the exact deficit.
     - `[📉 Adjust Budgets]`: Opens category allocation editor for this account's categories.
     - `[🔄 Re-link Category]`: Change category mapping to an account that has available funds.

### 3.3 Transaction Spending & Consumption
- When an expense is recorded:
  - If the user selects category $C$, the transaction form's `Payment Account` field automatically defaults to $C$'s mapped `account_id`.
  - The user can override the payment account if a different card was used.
  - The transaction increments $C.\text{spent\_amount}$ and decrements $A.\text{balance}$.

---

## 4. Payday Cycle & Next-Cycle Transfer Workflow

### 4.1 Payday Cycle Detection
- Leverages existing `households.payday_day` (default 27).
- If the local date reaches or passes the 27th, and no `salary` income record exists for the new cycle (e.g. `2026-11`), a dismissible **Payday Check-in Sheet** is presented.

### 4.2 Payday Check-in Modal
- **Fields:**
  - Destination Account (defaults to primary bank e.g. Al Rajhi).
  - Base Salary (pre-filled from user preference or previous cycle).
  - Overtime (+)
  - Bonuses (+)
  - Deductions / GOSI (-)
  - Calculated Net Deposit.
- **Result:**
  - Creates an `income_records` entry.
  - Updates destination `accounts.balance` by `net_amount`.

### 4.3 Unspent Funds / Previous Cycle Delta Handling
When copying budgets to the new cycle:
- Mapped accounts are preserved across cycles.
- For categories with unspent balances, the user chooses between two options:
  - **Option A (Category Rollover):** Leftover funds rollover into the new cycle's category cushion (`previous_cycle_delta = +unspent`).
  - **Option C (Sweep to Savings):** Leftover funds are swept into an emergency/savings account reserve, starting the new cycle clean.

### 4.4 1-Tap Inter-Account Salary Distribution Assistant
Following payday deposit, the user is offered a distribution helper:
- Detects the required allocations for external spending accounts (e.g., STC Pay for Groceries/Dining, Binance for DCA).
- Suggests transfers from primary salary account to target accounts.
- Executes all transfers with a single confirmation tap.

---

## 5. Shared Household / Roommate Pool Specification

### 5.1 Shared Pool Architecture
- A shared account record with `is_shared_pool = true` and `account_type = 'shared_pool'`.
- Roommates record monthly contributions (e.g., SAR 350 each) as `source_type = 'roommate_share'`.
- Shared categories (Rent, Utilities, Cleaning, WiFi) are mapped to this pool.

### 5.2 Roommate Transparency
- All household members can view the pool's balance and linked budgets.
- Surplus (e.g., pool balance SAR 3,000, budgets SAR 2,900 = +SAR 100) displays as **Shared Emergency Cushion**.
- If spending or allocations exceed contributions, an alert prompts members to contribute.

---

## 6. UI/UX & Component Architecture

### 6.1 New Screen: `AccountsOverviewScreen` (`flutter_app/lib/screens/accounts/accounts_overview_screen.dart`)
- **Total Net Assets Card:** Displays sum of all liquid balances, with a privacy eye toggle to obscure figures.
- **Account Groups:** Banks, E-Wallets, Crypto & Exchanges, Cash, and Shared Pools.
- **Account Cards:** Show balance, mapped budget commitments, margin badge, 1-tap reconcile, and quick transfer.
- **FAB / Top Bar Action:** Add Account.

### 6.2 Speed Dial FAB Enhancements (`AppSpeedDialFab`)
- Adds:
  - 💳 **Add Expense** (Pre-selects mapped account).
  - 💰 **Record Income** (Salary, Overtime, Bonus, Side Gig, Roommate Share).
  - 🔄 **Transfer Between Accounts** (Inter-account transfer sheet).

### 6.3 Budget Management Integration (`budget_management_screen.dart`)
- Category tiles display mapped account chip (`[📱 STC Pay]`).
- Tapping chip opens account selector bottom sheet.
- Top banner displays account health and deficit alerts.

### 6.4 Settings Screen Integration (`flutter_app/lib/screens/settings/...`)
- Adds `Accounts & Balances` tile for navigation and account management.

---

## 7. Migration & Backward Compatibility

1. **Existing Transactions & Budgets:**
   - Existing categories will have `account_id = NULL` initially.
   - Upon first launching the new version, a friendly one-time migration prompt lets the user designate their Primary Bank (e.g. Al Rajhi) and assign existing categories.
2. **Existing `monthly_income` Field:**
   - Retained on `households` for backward compatibility, kept in sync with the primary salary baseline.

---

## 8. Verification & Test Plan

1. **Unit & Widget Tests:**
   - Account capacity formula tests (Surplus, Zero-based, Deficit).
   - Transfer logic tests (balance decrements on source, increments on destination, fee deduction).
   - Income logging and net calculation tests.
2. **Integration Verification:**
   - Record an income deposit -> verify account balance updates and reflects in total liquidity.
   - Map budget to account -> verify capacity margin updates.
   - Induce deficit -> verify 1-tap transfer pre-fills and resolves deficit.
   - Rollover test: verify Option A cushion vs Option C savings sweep.
