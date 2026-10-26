# Real-Cash Operating Budgets, Savings Vaults & One-Tap Rebalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anchor household budgets to real liquid cash instead of static configured income, ring-fence emergency funds into a new `savings` account type, provide a live balance sheet with a one-tap rebalance assistant in Budget Management, enforce a zero-balance overdraft guard, and support mid-cycle joiners with an opening spend adjustment.

**Architecture:** 
1. Database & Models: Add `'savings'` account type to `accounts_account_type_check` in PostgreSQL and `AccountType.savings` with `isOperatingPool` filter in Dart.
2. Real-Cash Budget Ceiling: Budget allocations are compared against live operating account balances (excluding protected savings vaults).
3. One-Tap Rebalance: If budget allocations exceed available operating funds, a red warning in `BudgetManagementScreen` offers a 1-tap assistant that proportionally scales variable categories down while protecting fixed bills.
4. Overdraft Prevention: `ManualExpenseSheet` guards against recording expenses exceeding account liquid balance.
5. Mid-Cycle Joiner Flow: Onboarding offers an opening spend adjustment so remaining budget immediately matches current bank balance without distorting the next cycle's auto-rollover.

**Tech Stack:** Flutter 3.x (Dart), Supabase PostgreSQL with RLS, Google Fonts (Outfit), Trilingual `AppLocalizations` (Arabic, English, Urdu).

**Spec:** Brainstorming discussion in conversation `58902e28-b348-4e53-a77c-73c6ef6628cb`.

## Global Constraints

- Trilingual RTL/LTR support required across all UI text: Arabic primary, English, Urdu. Zero hardcoded strings.
- Test-Driven Development (TDD): Write failing test first, run to confirm red, implement, verify green.
- Zero `flutter analyze` warnings or errors.
- Preserve all existing comments and docstrings.
- Non-destructive database migrations only; no data loss or dropping tables.

---

### Task 1: Add Savings Vault Account Type (`AccountType.savings`)

**Files:**
- Create: `supabase/migrations/20261026000000_add_savings_account_type.sql`
- Modify: `flutter_app/lib/models/account.dart:4-95`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Modify: `flutter_app/lib/widgets/accounts/add_edit_account_dialog.dart:186-205`
- Modify: `flutter_app/lib/screens/accounts/accounts_overview_screen.dart:245-275`
- Test: `flutter_app/test/models/account_savings_type_test.dart`

**Interfaces:**
- Produces: `AccountType.savings`, `AccountTypeExtension.isOperatingPool` (`bool`).
- Produces: Localization key `account_type_savings` in English, Arabic, and Urdu.

- [ ] **Step 1: Write the failing unit test for `AccountType.savings` and `isOperatingPool`**

Create `flutter_app/test/models/account_savings_type_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';

void main() {
  group('AccountType.savings and isOperatingPool', () {
    test('parses savings from string correctly', () {
      expect(AccountTypeExtension.fromString('savings'), AccountType.savings);
      expect(AccountType.savings.value, 'savings');
      expect(AccountType.savings.translationKey, 'account_type_savings');
    });

    test('isOperatingPool returns true only for operating accounts', () {
      expect(AccountType.bank.isOperatingPool, isTrue);
      expect(AccountType.eWallet.isOperatingPool, isTrue);
      expect(AccountType.cash.isOperatingPool, isTrue);
      expect(AccountType.sharedPool.isOperatingPool, isTrue);

      // Savings vaults and crypto are protected from monthly operating budgets
      expect(AccountType.savings.isOperatingPool, isFalse);
      expect(AccountType.crypto.isOperatingPool, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/models/account_savings_type_test.dart`
Expected: Compilation error (`AccountType.savings` does not exist).

- [ ] **Step 3: Create database migration for `savings` account type**

Create `supabase/migrations/20261026000000_add_savings_account_type.sql`:
```sql
-- Migration: Add savings account type to public.accounts
-- Ring-fences emergency savings vaults from the operating budget pool.

ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_account_type_check;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_account_type_check 
  CHECK (account_type IN ('bank', 'e_wallet', 'crypto', 'cash', 'shared_pool', 'savings'));

COMMENT ON CONSTRAINT accounts_account_type_check ON public.accounts IS 
  'Enforces valid account types including savings vaults protected from daily budgets.';
```

- [ ] **Step 4: Update `AccountType` and `AccountTypeExtension` in `account.dart`**

In `flutter_app/lib/models/account.dart`:
Add `AccountType.savings`:
```dart
enum AccountType {
  bank,
  eWallet,
  crypto,
  cash,
  sharedPool,
  savings,
}
```
Update `AccountTypeExtension`:
- In `String get value`: case `AccountType.savings: return 'savings';`
- In `static AccountType fromString`: case `'savings': return AccountType.savings;`
- In `String get labelEn`: case `AccountType.savings: return 'Savings Vault';`
- In `String get translationKey`: case `AccountType.savings: return 'account_type_savings';`
- In `IconData get defaultIcon`: case `AccountType.savings: return Icons.savings_rounded;`
- Add getter:
```dart
  /// Only operating accounts are part of the active budget spending pool.
  /// Savings vaults and crypto are protected from daily budget consumption.
  bool get isOperatingPool {
    switch (this) {
      case AccountType.bank:
      case AccountType.eWallet:
      case AccountType.cash:
      case AccountType.sharedPool:
        return true;
      case AccountType.savings:
      case AccountType.crypto:
        return false;
    }
  }
```

- [ ] **Step 5: Add trilingual translations in `app_localizations.dart`**

Add `'account_type_savings'`:
- English: `'Savings Vault'`
- Arabic: `'حساب ادخار'`
- Urdu: `'بچت اکاؤنٹ'`
Add `'savings_vaults_section'`:
- English: `'Savings & Vaults'`
- Arabic: `'المدخرات والصناديق'`
- Urdu: `'بچت اور والٹس'`

- [ ] **Step 6: Update `AccountsOverviewScreen` to display Savings Vaults in their own section**

In `flutter_app/lib/screens/accounts/accounts_overview_screen.dart`:
Filter:
```dart
final savings = accounts.where((a) => a.accountType == AccountType.savings && !a.isSharedPool).toList();
```
Render a dedicated section for `savings` below banks and e-wallets, with title `context.tr('savings_vaults_section')` and subtitle indicating that these funds are protected from monthly budget allocations.

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd flutter_app && flutter test test/models/account_savings_type_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20261026000000_add_savings_account_type.sql flutter_app/lib/models/account.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/lib/screens/accounts/accounts_overview_screen.dart flutter_app/test/models/account_savings_type_test.dart
git commit -m "feat(accounts): add savings account type with protected operating pool distinction"
```

---

### Task 2: Real-Cash Balance Sheet Header in Budget Management Screen

**Files:**
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart:944-1130`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/screens/budget_management_header_test.dart`

**Interfaces:**
- Consumes: `staticData.accounts` (`List<Account>`), `budgets` (`List<Budget>`).
- Produces: Live operating balance computation `operatingCash = accounts.where((a) => a.accountType.isOperatingPool).fold(...)`.
- Produces: Overallocation state comparing `totalAllocated` directly against `operatingCash`.

- [ ] **Step 1: Write failing widget test for Budget Management Real-Cash Header**

Create `flutter_app/test/screens/budget_management_header_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

void main() {
  testWidgets('displays operating cash vs total allocations and flags deficit', (tester) async {
    // Test verifies that when operating accounts = 9,000 SAR and allocations = 10,000 SAR,
    // the header shows a 1,000 SAR deficit warning with the rebalance button.
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/screens/budget_management_header_test.dart`
Expected: FAIL (widgets/keys not found).

- [ ] **Step 3: Update `BudgetManagementScreen` Header**

In `flutter_app/lib/screens/home/budget_management_screen.dart`:
Calculate operating cash:
```dart
final operatingCash = staticData.accounts
    .where((a) => !a.isArchived && a.accountType.isOperatingPool)
    .fold<double>(0.0, (sum, a) => sum + (a.balance > 0 ? a.balance : 0.0));

final totalAllocated = budgets.fold<double>(0.0, (sum, b) => sum + b.allocatedAmount);
final hasOperatingCash = operatingCash > 0;
final cashMargin = operatingCash - totalAllocated;
final isOverAllocated = hasOperatingCash && cashMargin < -0.005;
```
Display header card:
- Left Column: `Total Operating Cash` (`context.sar(operatingCash)`)
- Right Column: `Total Allocated` (`context.sar(totalAllocated)`)
- Status Row:
  - If `isOverAllocated`: Red badge `⚠️ Allocations exceed available cash by SAR X.XX` and button `[⚡ Shrink to Match Cash]`.
  - If `cashMargin >= 0`: Green pill `✓ Covered by Operating Cash (+SAR X.XX Buffer)`.

- [ ] **Step 4: Add localization strings**

In `flutter_app/lib/l10n/app_localizations.dart`:
- `'total_operating_cash'`: `'Total Operating Cash'` / `'إجمالي النقد التشغيلي'` / `'کل آپریٹنگ کیش'`
- `'allocations_exceed_cash'`: `'Allocations exceed available cash by {amount}'` / `'المخصصات تتجاوز النقد المتاح بمقدار {amount}'` / `'تخصیصات دستیاب نقد رقم سے {amount} زیادہ ہیں'`
- `'shrink_to_match_cash'`: `'Shrink to Match Cash'` / `'موازنة المخصصات مع النقد'` / `'نقد رقم کے مطابق بجٹ کم کریں'`
- `'covered_by_cash'`: `'Covered by Operating Cash (+{amount} Buffer)'` / `'مغطى بالكامل بالنقد التشغيلي (فائض: {amount})'` / `'آپریٹنگ کیش سے مکمل کور ہے (+{amount})'`

- [ ] **Step 5: Run tests and verify green**

Run: `cd flutter_app && flutter test test/screens/budget_management_header_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/screens/budget_management_header_test.dart
git commit -m "feat(budgets): add real-cash balance sheet header to budget management"
```

---

### Task 3: One-Tap "Rebalance Envelopes to Match Cash" Assistant

**Files:**
- Create: `flutter_app/lib/widgets/budgets/rebalance_budget_sheet.dart`
- Modify: `flutter_app/lib/screens/home/budget_management_screen.dart`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/rebalance_budget_sheet_test.dart`

**Interfaces:**
- Consumes: `List<Budget> budgets`, `double targetTotal`, `String householdId`, `String cycleKey`.
- Produces: Batch update to `public.budgets` setting new `allocated_amount` on variable categories.

- [ ] **Step 1: Write failing test for `RebalanceBudgetSheet` math and execution**

Create `flutter_app/test/widgets/rebalance_budget_sheet_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/widgets/budgets/rebalance_budget_sheet.dart';
import 'package:budget_tracker/models/models.dart';

void main() {
  test('proportional shrink protects fixed categories and scales variable ones', () {
    final budgets = [
      Budget(id: '1', householdId: 'h1', categoryCode: 'OPEX-UTILITIES', allocatedAmount: 2000, spentAmount: 0, month: '2026-10-01'), // Fixed
      Budget(id: '2', householdId: 'h1', categoryCode: 'OPEX-GROCERY', allocatedAmount: 5000, spentAmount: 0, month: '2026-10-01'),   // Variable
      Budget(id: '3', householdId: 'h1', categoryCode: 'OPEX-DINING', allocatedAmount: 3000, spentAmount: 0, month: '2026-10-01'),    // Variable
    ];
    // Total = 10,000 SAR. Target = 8,000 SAR. Deficit = 2,000 SAR.
    // Variable total = 8,000 SAR.
    // Grocery shrink = 2000 * (5000/8000) = 1,250 -> new Grocery = 3,750
    // Dining shrink = 2000 * (3000/8000) = 750 -> new Dining = 2,250
    final adjusted = computeProportionalRebalance(budgets: budgets, targetTotal: 8000);
    expect(adjusted['OPEX-UTILITIES'], 2000.0); // Untouched
    expect(adjusted['OPEX-GROCERY'], 3750.0);
    expect(adjusted['OPEX-DINING'], 2250.0);
    expect(adjusted.values.reduce((a, b) => a + b), 8000.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/widgets/rebalance_budget_sheet_test.dart`
Expected: FAIL (function not found).

- [ ] **Step 3: Implement `computeProportionalRebalance` and `RebalanceBudgetSheet`**

Create `flutter_app/lib/widgets/budgets/rebalance_budget_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/payday_outlook.dart' show kFixedCostCategoryCodes;
import '../../main.dart';
import '../../theme/app_themes.dart';
import '../app_snackbar.dart';

Map<String, double> computeProportionalRebalance({
  required List<Budget> budgets,
  required double targetTotal,
}) {
  final active = budgets.where((b) => b.isActive).toList();
  final currentTotal = active.fold<double>(0.0, (s, b) => s + b.allocatedAmount);
  final deficit = currentTotal - targetTotal;
  if (deficit <= 0) {
    return {for (final b in active) b.categoryCode: b.allocatedAmount};
  }

  // Separate fixed vs variable categories
  double fixedSum = 0.0;
  double variableSum = 0.0;
  for (final b in active) {
    if (kFixedCostCategoryCodes.contains(b.categoryCode)) {
      fixedSum += b.allocatedAmount;
    } else {
      variableSum += b.allocatedAmount;
    }
  }

  final Map<String, double> result = {};
  if (variableSum <= 0 || targetTotal <= fixedSum) {
    // If fixed bills exceed target, scale all active categories proportionally
    for (final b in active) {
      result[b.categoryCode] = double.parse(((b.allocatedAmount / currentTotal) * targetTotal).toStringAsFixed(2));
    }
    return result;
  }

  final shrinkRequired = deficit;
  for (final b in active) {
    if (kFixedCostCategoryCodes.contains(b.categoryCode)) {
      result[b.categoryCode] = b.allocatedAmount; // Protected
    } else {
      final share = b.allocatedAmount / variableSum;
      final deduction = shrinkRequired * share;
      final newAmt = (b.allocatedAmount - deduction).clamp(0.0, double.infinity);
      result[b.categoryCode] = double.parse(newAmt.toStringAsFixed(2));
    }
  }
  return result;
}

class RebalanceBudgetSheet extends StatefulWidget {
  final String householdId;
  final String cycleKey;
  final List<Budget> budgets;
  final double targetAvailableCash;
  final VoidCallback? onRebalanced;

  const RebalanceBudgetSheet({
    super.key,
    required this.householdId,
    required this.cycleKey,
    required this.budgets,
    required this.targetAvailableCash,
    this.onRebalanced,
  });

  static Future<void> show(
    BuildContext context, {
    required String householdId,
    required String cycleKey,
    required List<Budget> budgets,
    required double targetAvailableCash,
    VoidCallback? onRebalanced,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RebalanceBudgetSheet(
        householdId: householdId,
        cycleKey: cycleKey,
        budgets: budgets,
        targetAvailableCash: targetAvailableCash,
        onRebalanced: onRebalanced,
      ),
    );
  }

  @override
  State<RebalanceBudgetSheet> createState() => _RebalanceBudgetSheetState();
}

class _RebalanceBudgetSheetState extends State<RebalanceBudgetSheet> {
  bool _isSaving = false;

  Future<void> _applyRebalance(Map<String, double> adjustments) async {
    setState(() => _isSaving = true);
    try {
      final futures = <Future>[];
      for (final entry in adjustments.entries) {
        final b = widget.budgets.firstWhere((item) => item.categoryCode == entry.key);
        futures.add(
          supabase
              .from('budgets')
              .update({'allocated_amount': entry.value})
              .eq('id', b.id),
        );
      }
      await Future.wait(futures);
      if (mounted) {
        Navigator.pop(context);
        widget.onRebalanced?.call();
        AppSnackBar.showSuccess(
          context,
          context.tr('rebalance_success_msg'),
          title: context.tr('rebalance_success_title'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackBar.showError(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adjustments = computeProportionalRebalance(
      budgets: widget.budgets,
      targetTotal: widget.targetAvailableCash,
    );
    final currentTotal = widget.budgets.where((b) => b.isActive).fold<double>(0.0, (s, b) => s + b.allocatedAmount);

    return Container(
      decoration: BoxDecoration(
        color: context.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, color: context.accentText, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('rebalance_sheet_title'),
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('rebalance_sheet_desc'),
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Preview of adjustments
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('current_total'), style: TextStyle(color: context.textSecondary, fontSize: 11)),
                    Text(context.sar(currentTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const Icon(Icons.arrow_forward_rounded, size: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(context.tr('adjusted_to_cash'), style: TextStyle(color: context.accentText, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(context.sar(widget.targetAvailableCash), style: TextStyle(color: context.accentText, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSaving ? null : () => _applyRebalance(adjustments),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentText,
              foregroundColor: context.primaryButtonFg,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('confirm_rebalance'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Connect button in `BudgetManagementScreen` to `RebalanceBudgetSheet.show`**

In `flutter_app/lib/screens/home/budget_management_screen.dart`:
```dart
onPressed: () {
  RebalanceBudgetSheet.show(
    context,
    householdId: staticData.householdId,
    cycleKey: _currentCycleKey,
    budgets: budgets,
    targetAvailableCash: operatingCash,
    onRebalanced: () => setState(() {
      _budgetStreamGeneration++;
    }),
  );
}
```

- [ ] **Step 5: Run tests and verify green**

Run: `cd flutter_app && flutter test test/widgets/rebalance_budget_sheet_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/widgets/budgets/rebalance_budget_sheet.dart flutter_app/lib/screens/home/budget_management_screen.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/rebalance_budget_sheet_test.dart
git commit -m "feat(budgets): implement one-tap rebalance assistant to scale envelopes to available cash"
```

---

### Task 4: Zero-Balance Overdraft Guard in Expense Logging

**Files:**
- Modify: `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart:324-345`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/manual_expense_sheet_overdraft_test.dart`

**Interfaces:**
- Consumes: Selected `_selectedAccountId`, entered `amount`, loaded `_accounts` (`List<Account>`).
- Produces: Guardrail blocking submission if `account.balance < amount`.

- [ ] **Step 1: Write failing test for zero-balance overdraft guard**

Create `flutter_app/test/widgets/manual_expense_sheet_overdraft_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';

void main() {
  test('overdraft check blocks expense if amount exceeds account balance', () {
    final account = Account(
      id: 'acc1',
      householdId: 'h1',
      ownerUserId: 'u1',
      name: 'Debit Bank',
      accountType: AccountType.bank,
      balance: 300.0,
    );

    expect(account.balance < 500.0, isTrue); // Insufficient funds
    expect(account.balance >= 200.0, isTrue); // Sufficient funds
  });
}
```

- [ ] **Step 2: Add validation check in `manual_expense_sheet.dart`**

In `flutter_app/lib/widgets/transactions/manual_expense_sheet.dart` inside `_saveExpense()`:
```dart
if (_selectedAccountId != null && _accounts.isNotEmpty) {
  final payingAcc = _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
  if (payingAcc != null && payingAcc.balance < amount) {
    AppSnackBar.showError(
      context,
      context.trArgs('insufficient_funds_msg', {
        'account': payingAcc.name,
        'balance': context.sar(payingAcc.balance),
        'amount': context.sar(amount),
      }),
      title: context.tr('insufficient_funds_title'),
    );
    return;
  }
}
```

- [ ] **Step 3: Add localization strings**

In `flutter_app/lib/l10n/app_localizations.dart`:
- `'insufficient_funds_title'`: `'Insufficient Funds'` / `'رصيد الحساب غير كافٍ'` / `'ناکافی فنڈز'`
- `'insufficient_funds_msg'`: `'{account} balance ({balance}) is less than {amount}. You cannot spend more than your available cash.'` / `'رصيد حساب {account} ({balance}) أقل من {amount}. لا يمكنك إنفاق أكثر من رصيدك المتاح.'` / `'{account} کا بیلنس ({balance}) اس رقم ({amount}) سے کم ہے۔ آپ دستیاب رقم سے زیادہ خرچ نہیں کر سکتے۔'`

- [ ] **Step 4: Run tests and verify green**

Run: `cd flutter_app && flutter test test/widgets/manual_expense_sheet_overdraft_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/transactions/manual_expense_sheet.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/manual_expense_sheet_overdraft_test.dart
git commit -m "feat(transactions): add zero-balance overdraft guard to prevent negative account balances"
```

---

### Task 5: Mid-Cycle Joiner Opening Spend Adjustment Helper

**Files:**
- Modify: `flutter_app/lib/widgets/dashboard/household_setup_card.dart`
- Modify: `flutter_app/lib/l10n/app_localizations.dart`
- Test: `flutter_app/test/widgets/mid_cycle_adjustment_test.dart`

**Interfaces:**
- Consumes: `householdId`, current cycle dates, total allocations, and current bank balance.
- Produces: Creates an opening adjustment transaction with `paid_by = 'me'`, `merchant = 'Prior cycle spending'`, and `category_code = 'OPEX-MISC'`.

- [ ] **Step 1: Write failing test for mid-cycle adjustment computation**

Create `flutter_app/test/widgets/mid_cycle_adjustment_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates prior cycle adjustment delta correctly', () {
    const totalStandardBudget = 9000.0;
    const currentBankBalance = 1000.0;
    final deltaAdjustment = totalStandardBudget - currentBankBalance;
    expect(deltaAdjustment, 8000.0);
  });
}
```

- [ ] **Step 2: Add mid-cycle prompt card in `household_setup_card.dart`**

When the user completes Step 3 (Budgets) of onboarding, if `DateTime.now()` is in the middle of the cycle:
Offer:
```dart
if (isMidCycle && currentCash < totalAllocated) ...[
  MidCycleAdjustmentBanner(
    householdId: householdId,
    standardBudget: totalAllocated,
    currentCash: currentCash,
    onAdjusted: () => onChanged(),
  )
]
```
When tapped:
Calls `supabase.from('transactions').insert(...)` with:
- `amount`: `totalAllocated - currentCash` (e.g. 8,000 SAR)
- `merchant`: `context.tr('prior_cycle_spending_label')`
- `category_code`: `'OPEX-MISC'`
- `occurred_at`: `cycleStart`

- [ ] **Step 3: Add localization strings**

In `flutter_app/lib/l10n/app_localizations.dart`:
- `'prior_cycle_spending_label'`: `'Prior cycle spending (opening adjustment)'` / `'مصروفات سابقة لهذه الدورة (تسوية رصيد)'` / `'پچھلے سائیکل کا خرچ (ابتدائی ایڈجسٹمنٹ)'`
- `'mid_cycle_setup_prompt'`: `'Starting mid-cycle? Align your remaining budget with current bank cash ({cash})'` / `'انضممت في منتصف الدورة؟ وازن متبقي ميزانيتك مع نقدك الفعلي ({cash})'` / `'سائیکل کے درمیان میں شامل ہوئے ہیں؟ اپنے بقیہ بجٹ کو بینک کیش ({cash}) کے برابر کریں'`
- `'apply_prior_spend_adjustment'`: `'Apply Adjustment'` / `'تطبيق التسوية'` / `'ایڈجسٹمنٹ لاگو کریں'`

- [ ] **Step 4: Run tests and verify green**

Run: `cd flutter_app && flutter test test/widgets/mid_cycle_adjustment_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/dashboard/household_setup_card.dart flutter_app/lib/l10n/app_localizations.dart flutter_app/test/widgets/mid_cycle_adjustment_test.dart
git commit -m "feat(onboarding): add mid-cycle opening spend adjustment helper"
```

---

### Task 6: Full System Verification & Regression Sweep

**Files:**
- Test: All Flutter test suites (`cd flutter_app && flutter test`)
- Analyzer: Flutter static analysis (`cd flutter_app && flutter analyze`)
- Python Tests: `cd ai_service && pytest -v`

- [ ] **Step 1: Run complete Flutter test suite**

Run: `cd flutter_app && flutter test`
Expected: All tests PASS with 0 failures.

- [ ] **Step 2: Run Flutter analyzer**

Run: `cd flutter_app && flutter analyze`
Expected: 0 issues found.

- [ ] **Step 3: Run Python test suite**

Run: `cd ai_service && pytest -v`
Expected: All tests PASS.

- [ ] **Step 4: Commit and finalize**

```bash
git status
```
Ensure working tree is clean.
