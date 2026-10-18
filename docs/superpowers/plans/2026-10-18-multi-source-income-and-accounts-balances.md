# Multi-Source Income, Accounts & Balances, and Linked Budgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a unified multi-source income, accounts & balances ledger, and account-linked budget capacity system with payday check-in automation and inter-account transfers.

**Architecture:** Extend Supabase schema with `accounts`, `account_transfers`, and `income_records`. Link budgets and transactions to accounts with automated balance consumption. Deliver a dedicated `AccountsOverviewScreen`, speed-dial action sheets (Income, Transfer), payday check-in sheet with salary distribution, and budget capacity deficit alerts with 1-tap resolution shortcuts.

**Tech Stack:** Flutter 3.x, Dart 3.x, Supabase (PostgreSQL + RLS), Google Fonts, Provider / Stateful widgets, Python FastAPI backend helper endpoints.

**Spec:** `docs/superpowers/specs/2026-10-18-multi-source-income-and-accounts-balances-design.md`

## Global Constraints
- Target currency: SAR default with multi-currency support (SAR, USD, USDT).
- Maintain backward compatibility with existing transactions and budgets where `account_id` may be null initially.
- Preserve existing salary cycle engine (`payday_day` default 27th, `cycle_key`, `previous_cycle_delta`).
- Full localization in English, Arabic, and Urdu via `app_localizations.dart`.
- No placeholders (no TODO/TBD).

---

### Task 1: Supabase Database Migration & Ledger Functions

**Files:**
- Create: `supabase/migrations/20261018_multi_source_income_and_accounts.sql`
- Test: `supabase/tests/20261018_accounts_test.sql`

**Interfaces:**
- Consumes: `public.households`, `public.users`, `public.budgets`, `public.transactions`
- Produces: `public.accounts`, `public.account_transfers`, `public.income_records`, columns `budgets.account_id`, `transactions.account_id`

- [x] **Step 1: Write SQL migration file**

```sql
-- Migration: Multi-source income, accounts & balances, and linked budgets
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

ALTER TABLE public.budgets 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_budgets_account ON public.budgets(account_id);

ALTER TABLE public.transactions 
    ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES public.accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_account ON public.transactions(account_id);

-- RLS setup
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view personal accounts and shared pools" ON public.accounts;
CREATE POLICY "Users can view personal accounts and shared pools" ON public.accounts
    FOR SELECT TO authenticated
    USING (owner_user_id = auth.uid() OR is_shared_pool = true);

DROP POLICY IF EXISTS "Users can manage personal accounts" ON public.accounts;
CREATE POLICY "Users can manage personal accounts" ON public.accounts
    FOR ALL TO authenticated
    USING (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Household members view transfers" ON public.account_transfers;
CREATE POLICY "Household members view transfers" ON public.account_transfers
    FOR ALL TO authenticated
    USING (household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Household members view income" ON public.income_records;
CREATE POLICY "Household members view income" ON public.income_records
    FOR ALL TO authenticated
    USING (household_id IN (SELECT household_id FROM public.users WHERE id = auth.uid()));
```

- [x] **Step 2: Commit migration file**

```bash
git add supabase/migrations/20261018_multi_source_income_and_accounts.sql
git commit -m "feat(db): add accounts, transfers, and multi-source income tables"
```

---

### Task 2: Data Models & Account Service Layer in Flutter

**Files:**
- Create: `flutter_app/lib/models/account.dart`
- Modify: `flutter_app/lib/models/models.dart:1-50` (add `accountId` to `Transaction` & `Budget`)
- Create: `flutter_app/lib/services/account_service.dart`
- Create: `flutter_app/test/account_models_test.dart`

**Interfaces:**
- Consumes: Supabase database tables `accounts`, `account_transfers`, `income_records`
- Produces: `Account`, `AccountType`, `AccountTransfer`, `IncomeRecord`, `AccountService` singleton

- [x] **Step 1: Write failing unit test for Account models and calculations**

```dart
// flutter_app/test/account_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';

void main() {
  test('Account calculates capacity margin and status correctly', () {
    final acc = Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'STC Pay',
      accountType: AccountType.eWallet,
      currency: 'SAR',
      balance: 1800.0,
    );

    // Margin = balance (1800) - committed (2300) = -500 (Deficit)
    expect(acc.calculateMargin(2300.0), -500.0);
    expect(acc.getStatus(2300.0), AccountCapacityStatus.deficit);

    // Margin = balance (1800) - committed (1800) = 0 (Zero-based)
    expect(acc.calculateMargin(1800.0), 0.0);
    expect(acc.getStatus(1800.0), AccountCapacityStatus.zeroBased);

    // Margin = balance (1800) - committed (1500) = +300 (Surplus)
    expect(acc.calculateMargin(1500.0), 300.0);
    expect(acc.getStatus(1500.0), AccountCapacityStatus.surplus);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd flutter_app; flutter test test/account_models_test.dart
```

- [x] **Step 3: Implement `Account`, `AccountTransfer`, and `IncomeRecord` models**

Create `flutter_app/lib/models/account.dart` with enum `AccountType`, model `Account`, `AccountTransfer`, `IncomeRecord`, and capacity status helpers.
Update `flutter_app/lib/models/models.dart` to include `accountId` in `Budget` and `Transaction`.

- [x] **Step 4: Implement `AccountService`**

Create `flutter_app/lib/services/account_service.dart`:
- `Stream<List<Account>> streamAccounts(String householdId)`
- `Future<Account> createAccount(...)`
- `Future<void> updateBalance(String accountId, double newBalance)`
- `Future<void> transferFunds({required String fromAccountId, required String toAccountId, required double amount, double fee = 0, String? notes})`
- `Future<void> logIncome({required String accountId, required String cycleKey, required String sourceType, required String title, required double baseAmount, double overtime = 0, double bonus = 0, double deductions = 0, String? notes})`

- [x] **Step 5: Run tests and verify PASS**

```bash
cd flutter_app; flutter test test/account_models_test.dart
```

- [x] **Step 6: Commit models & service**

```bash
git add flutter_app/lib/models/ flutter_app/lib/services/account_service.dart flutter_app/test/account_models_test.dart
git commit -m "feat(models): add Account, Transfer, IncomeRecord models and AccountService"
```

---

### Task 3: Speed Dial FAB Action Sheets (Income & Transfer)

**Files:**
- Create: `flutter_app/lib/widgets/accounts/record_income_sheet.dart`
- Create: `flutter_app/lib/widgets/accounts/account_transfer_sheet.dart`
- Modify: `flutter_app/lib/widgets/dashboard/app_speed_dial_fab.dart`
- Modify: `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart`

**Interfaces:**
- Consumes: `AccountService`, `Account`
- Produces: Interactive bottom sheets for logging income, transferring between accounts, and picking payment account in manual expense

- [x] **Step 1: Create `RecordIncomeSheet`**
Allows user to log received money:
- Select destination account
- Select source type (Salary, Overtime, Bonus, Side Gig, Roommate Share, Other)
- Amount, date, notes
- Saves to `income_records` and increments destination `account.balance`.

- [x] **Step 2: Create `AccountTransferSheet`**
Allows transferring between accounts:
- Source account dropdown (with current balance displayed)
- Destination account dropdown
- Amount & optional transfer/gas fee
- Executes transfer atomically and refreshes both account balances.

- [x] **Step 3: Update `ManualExpenseSheet`**
Add "Payment Account" dropdown:
- Pre-selects the category's mapped account.
- Allows user to override if another account was used.
- Decrements the chosen account balance when expense is saved.

- [x] **Step 4: Wire up `AppSpeedDialFab`**
Add 1-tap options:
- 💰 Record Income -> opens `RecordIncomeSheet`
- 🔄 Transfer Funds -> opens `AccountTransferSheet`

- [x] **Step 5: Verify via widget test or flutter analyze**

```bash
cd flutter_app; flutter analyze lib/widgets/dashboard/app_speed_dial_fab.dart lib/widgets/accounts/
```

- [x] **Step 6: Commit FAB & transaction sheets**

```bash
git add flutter_app/lib/widgets/
git commit -m "feat(ui): add record income, account transfer sheets, and speed dial actions"
```

---

### Task 4: Accounts & Balances Overview Screen

**Files:**
- Create: `flutter_app/lib/screens/accounts/accounts_overview_screen.dart`
- Create: `flutter_app/lib/widgets/accounts/account_card.dart`
- Create: `flutter_app/lib/widgets/accounts/add_edit_account_dialog.dart`
- Create: `flutter_app/lib/widgets/accounts/reconcile_balance_dialog.dart`

**Interfaces:**
- Consumes: `AccountService`, Supabase real-time `accounts` & `budgets`
- Produces: Dedicated accounts management screen

- [x] **Step 1: Implement `AccountCard` widget**
Displays:
- Account icon, name, currency badge
- Balance (with eye privacy toggle)
- Committed Budgets sum
- Capacity status badge (Zero-based, Surplus Buffer, Deficit)
- If in deficit: `[⚡ Quick Transfer]` button that opens `AccountTransferSheet` with pre-filled deficit amount!
- Reconcile balance button.

- [x] **Step 2: Implement `ReconcileBalanceDialog`**
Allows user to enter actual bank app balance, computes variance, and saves adjustment.

- [x] **Step 3: Implement `AccountsOverviewScreen`**
Displays:
- Total Liquid Net Worth header card
- Grouped accounts (Banks, E-wallets, Crypto, Cash, Shared Pool)
- Add Account button

- [x] **Step 4: Test & Verify screen compilation**

```bash
cd flutter_app; flutter analyze lib/screens/accounts/
```

- [x] **Step 5: Commit Accounts screen**

```bash
git add flutter_app/lib/screens/accounts/ flutter_app/lib/widgets/accounts/
git commit -m "feat(screens): add AccountsOverviewScreen with capacity status and quick transfer"
```

---

### Task 5: Budget Management Screen Integration & Mapped Accounts

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Create: `flutter_app/lib/widgets/budgets/link_account_sheet.dart`

**Interfaces:**
- Consumes: `budgets.account_id`, `accounts`
- Produces: Category account badge, account re-linking sheet, deficit alert banner, Option A/C rollover prompt

- [x] **Step 1: Add Mapped Account Badge to Category Cards**
In `budget_management_screen.dart`, render a chip on each category item: e.g. `[📱 STC Pay]`. Tapping opens `LinkAccountSheet` to switch account.

- [x] **Step 2: Add Top Account Deficit Banner**
If any mapped account has $\text{balance} < \text{allocated}$, display red/amber banner:
`⚠️ STC Pay is short by SAR 500.00 for active budgets. [⚡ Fix with Transfer]`.

- [x] **Step 3: Upgrade Cycle Rollover Prompt (`_copyFromPreviousMonth`)**
When copying budgets to the new cycle, prompt user for leftover unspent category funds:
- `[Option A]`: Roll over unspent funds into this cycle's category cushion (`previous_cycle_delta`).
- `[Option C]`: Sweep unspent funds into an account Savings/Reserve buffer.

- [x] **Step 4: Test & Verify compilation**

```bash
cd flutter_app; flutter analyze lib/screens/home/budget_management_screen.dart
```

- [x] **Step 5: Commit budget integration**

```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/widgets/budgets/
git commit -m "feat(budgets): integrate account mapping, deficit alerts, and Option A/C rollover"
```

---

### Task 6: Payday Cycle Check-in Sheet & Distribution Assistant

**Files:**
- Create: `flutter_app/lib/widgets/salary/payday_income_sheet.dart`
- Create: `flutter_app/lib/widgets/salary/salary_distribution_assistant_sheet.dart`
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart` (trigger payday check-in if 27th+)

**Interfaces:**
- Consumes: `payday_day`, `cycle_key`, `income_records`, `accounts`, `budgets`
- Produces: Automated payday prompt, itemized salary breakdown, 1-tap salary distribution

- [x] **Step 1: Implement `PaydayIncomeSheet`**
Form with:
- Destination Account (defaults to primary bank)
- Base Salary + Overtime + Bonus - Deductions
- Net deposit amount
- Submits to `income_records` and updates destination account balance.

- [x] **Step 2: Implement `SalaryDistributionAssistantSheet`**
Detects funding deficits across external accounts (e.g. STC Pay needs SAR 2,000 for groceries; Binance needs SAR 1,000).
Provides 1-tap `[⚡ Execute Transfers]` button that generates the inter-account transfers from the primary salary bank.

- [x] **Step 3: Hook Payday Detection in `DashboardScreen`**
If today is on or after the household's `payday_day` and no salary record exists for the current `cycle_key`, present `PaydayIncomeSheet`.

- [x] **Step 4: Test & Verify**

```bash
cd flutter_app; flutter analyze lib/widgets/salary/ lib/screens/home/dashboard_screen.dart
```

- [x] **Step 5: Commit payday automation**

```bash
git add flutter_app/lib/widgets/salary/ flutter_app/lib/screens/home/dashboard_screen.dart
git commit -m "feat(payday): add payday check-in sheet and salary distribution assistant"
```

---

### Task 7: Navigation Entry Points & Localization

**Files:**
- Modify: `flutter_app/lib/screens/home/dashboard_screen.dart` (Add Accounts summary card)
- Modify: `flutter_app/lib/screens/settings/ingestion_settings_screen.dart` (Add Accounts tile)
- Modify: `flutter_app/lib/l10n/app_localizations.dart` (EN, AR, UR translations)

**Interfaces:**
- Consumes: `AccountsOverviewScreen`
- Produces: User access via Dashboard, Budgets header, Settings, and multilingual text

- [x] **Step 1: Add Accounts Summary Card on Dashboard**
Renders net liquid assets, total accounts count, and deficit alert pill. Tapping navigates to `AccountsOverviewScreen`.

- [x] **Step 2: Add Accounts Tile in Settings**
Add `Accounts & Balances` tile navigating to `AccountsOverviewScreen`.

- [x] **Step 3: Add Localization Strings in `app_localizations.dart`**
Add translation keys for:
- `accounts_and_balances`
- `total_liquid_assets`
- `record_income`
- `transfer_funds`
- `payday_checkin`
- `deficit_alert`
- `surplus_buffer`
- `zero_based`
- `quick_transfer`
(In English, Arabic, and Urdu).

- [x] **Step 4: Run full flutter analyze**

```bash
cd flutter_app; flutter analyze
```

- [x] **Step 5: Commit navigation & localization**

```bash
git add flutter_app/lib/screens/ flutter_app/lib/l10n/app_localizations.dart
git commit -m "feat(ui): add dashboard accounts card, settings tile, and full localization"
```

---

### Task 8: End-to-End Verification & Automated Test Suite

**Files:**
- Test: `flutter_app/test/account_models_test.dart`
- Test: `flutter_app/test/accounts_overview_test.dart`

- [x] **Step 1: Write integration widget test for accounts and capacity alerts**
- [x] **Step 2: Run all Flutter tests**

```bash
cd flutter_app; flutter test
```
Verify: All unit and widget tests PASS with zero errors.

- [x] **Step 3: Commit verified test suite**

```bash
git add flutter_app/test/
git commit -m "test: add comprehensive unit and widget tests for accounts and capacity engine"
```
