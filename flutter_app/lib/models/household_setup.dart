/// First-run setup of a household (UX-02): what is still to do, from data the
/// app already loads (payday, income, roster, budgets). No new endpoint.
library;

import 'household_membership.dart';

enum SetupStep { payday, income, budgets, invite, provider }

class HouseholdSetupData {
  /// The household's payday (null when it could not be read).
  final int? paydayDay;

  /// The payday was confirmed on this device or differs from the default.
  final bool paydayConfirmed;

  /// Monthly income; 0 = not set; null = could not be read.
  final double? monthlyIncome;

  /// Members and the caller's rights; null when they could not be read.
  final HouseholdRoster? roster;

  /// The checklist was hidden on this device (only once budgets exist).
  final bool hidden;

  const HouseholdSetupData({
    this.paydayDay,
    this.paydayConfirmed = false,
    this.monthlyIncome,
    this.roster,
    this.hidden = false,
  });

  /// Only admins set the payday, income, budgets, invites and the provider.
  bool get isAdmin => roster?.callerIsAdmin ?? false;

  bool get isFamily => roster?.effectiveHouseholdType == kHouseholdTypeFamily;

  /// The steps for this household: the Nafaqah provider only in family mode.
  List<SetupStep> get steps => [
        SetupStep.payday,
        SetupStep.income,
        SetupStep.budgets,
        SetupStep.invite,
        if (isFamily) SetupStep.provider,
      ];

  bool isDone(SetupStep step, {required bool hasBudgets}) {
    switch (step) {
      case SetupStep.payday:
        return paydayConfirmed;
      case SetupStep.income:
        return (monthlyIncome ?? 0) > 0;
      case SetupStep.budgets:
        return hasBudgets;
      case SetupStep.invite:
        return (roster?.members.length ?? 0) > 1;
      case SetupStep.provider:
        return roster?.nafaqahProvider != null;
    }
  }

  int doneCount({required bool hasBudgets}) => steps.where((s) => isDone(s, hasBudgets: hasBudgets)).length;

  bool isComplete({required bool hasBudgets}) => doneCount(hasBudgets: hasBudgets) == steps.length;

  HouseholdSetupData copyWith({bool? paydayConfirmed, bool? hidden, double? monthlyIncome, int? paydayDay}) =>
      HouseholdSetupData(
        paydayDay: paydayDay ?? this.paydayDay,
        paydayConfirmed: paydayConfirmed ?? this.paydayConfirmed,
        monthlyIncome: monthlyIncome ?? this.monthlyIncome,
        roster: roster,
        hidden: hidden ?? this.hidden,
      );
}

/// One row of the suggested starter budget.
class StarterBudgetRow {
  final String categoryCode;

  /// Share of the monthly income.
  final double share;
  final double amount;

  const StarterBudgetRow({required this.categoryCode, required this.share, required this.amount});
}

/// The suggested shares of income for a new household, on the seeded system
/// categories only (they exist in every database). About a quarter of the
/// income is left unbudgeted for savings and the unexpected.
const List<(String, double)> kStarterBudgetShares = [
  ('OPEX-UTILITIES', 0.25),
  ('OPEX-GROCERY', 0.20),
  ('OPEX-FUEL', 0.08),
  ('OPEX-SHOPPING', 0.06),
  ('OPEX-DINING', 0.05),
  ('OPEX-MISC', 0.05),
  ('OPEX-HEALTH', 0.04),
];

/// Starter amounts from [monthlyIncome], rounded to 50 SAR; 0 without an income.
List<StarterBudgetRow> starterBudgetTemplate(double? monthlyIncome) {
  final income = monthlyIncome ?? 0;
  return [
    for (final (code, share) in kStarterBudgetShares)
      StarterBudgetRow(
        categoryCode: code,
        share: share,
        amount: income > 0 ? ((income * share) / 50).round() * 50.0 : 0.0,
      ),
  ];
}
