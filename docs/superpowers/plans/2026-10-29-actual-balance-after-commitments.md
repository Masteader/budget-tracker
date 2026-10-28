# Implementation Plan: Actual Available Balance After Commitments

Calculates the actual uncommitted liquid balance (Total Liquid Cash minus pending Recurring Bills and active Installments) and renders a responsive tip pill directly under the current available balance on the Dashboard's Accounts & Balances card.

## Proposed Changes

### Localization & Copy

#### [app_localizations.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/l10n/app_localizations.dart)
Add keys for the new tip across English, Arabic, and Urdu:
- `tip_actual_balance_after_commitments`:
  - EN: `'After commitments ({commitments}): {actual} actual available'`
  - AR: `'الرصيد الفعلي بعد الالتزامات ({commitments}): {actual}'`
  - UR: `'واجبات کے بعد اصل دستیاب رقم ({commitments}): {actual}'`
- `tip_balance_deficit`:
  - EN: `'Deficit: commitments exceed balance by {deficit}'`
  - AR: `'عجز: الالتزامات تتجاوز الرصيد بمقدار {deficit}'`
  - UR: `'خسارہ: واجبات بیلنس سے {deficit} زیادہ ہیں'`
- `tip_no_pending_commitments`:
  - EN: `'No pending commitments: full balance available'`
  - AR: `'لا توجد التزامات معلقة: كامل الرصيد متاح'`
  - UR: `'کوئی زیرِ التواء واجبات نہیں: مکمل رقم دستیاب ہے'`

---

### Dashboard Widgets

#### [accounts_summary_card.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/widgets/dashboard/accounts_summary_card.dart)
- Accept optional callback: `final VoidCallback? onCommitmentsTap;`
- Read or watch `RecurringBillsProvider` and `InstallmentProvider` via `context.watch<T>()` or optional overrides for testing.
- Compute:
  - `totalUnpaidBills`: sum of `averageAmount` for bills in `recurringBillsSummary.bills` where `!b.isPaid`.
  - `totalInstallmentsDues`: sum of `installmentAmount` for plans in `installmentProvider.plans` where `!p.isCompleted`.
  - `totalCommitments = totalUnpaidBills + totalInstallmentsDues`.
  - `actualAvailable = totalLiquidity - totalCommitments`.
- Render the tip pill under the `totalLiquidity` balance Wrap:
  - If `totalCommitments > 0` and `actualAvailable >= 0`: Green/teal/accent badge showing actual balance and total commitments, tappable to jump to commitments.
  - If `totalCommitments > 0` and `actualAvailable < 0`: Amber/red deficit alert showing shortfall.
  - If `totalCommitments == 0`: Subtle text indicating 100% of balance is unencumbered.

#### [dashboard_screen.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/lib/screens/home/dashboard_screen.dart)
- Pass `onCommitmentsTap: _scrollToCommitments` to `AccountsSummaryCard`.

---

### Automated Tests

#### [accounts_summary_card_test.dart](file:///c:/Users/WinDows/OneDrive/Python%20projects/budget-tracker/flutter_app/test/widgets/accounts_summary_card_test.dart)
- Unit and widget tests verifying:
  1. Tip displays correct deducted balance when unpaid recurring bills and active installments exist.
  2. Deficit badge renders when commitments exceed available liquidity.
  3. Clean zero-commitments state when no bills or installments are pending.
  4. Tapping the tip triggers `onCommitmentsTap`.

---

## Verification Plan

### Automated Tests
1. **Flutter Analysis**:
   ```powershell
   cd flutter_app
   flutter analyze
   ```
2. **Accounts Summary Card Tests**:
   ```powershell
   cd flutter_app
   flutter test test/widgets/accounts_summary_card_test.dart
   ```
3. **Dashboard Integration Tests**:
   ```powershell
   cd flutter_app
   flutter test test/widgets/card_error_states_test.dart test/widgets/partner_settlement_card_test.dart
   ```
