import 'package:flutter/material.dart';

import '../../screens/accounts/accounts_overview_screen.dart';
import '../../screens/home/budget_management_screen.dart';
import '../accounts/record_income_sheet.dart';
import '../dashboard/household_setup_card.dart';
import '../settings/household_roles_card.dart';

/// What a setup tutor step's button opens.
enum TutorAction {
  /// The household's payday editor (admins).
  payday,

  /// **Record Income**.
  income,

  /// **Accounts & Balances**.
  accounts,

  /// The Budgets screen (admins).
  budgets,

  /// **Members & Admins** (admins).
  roles,
}

/// Opens the screen or sheet of a [TutorAction] from the context of the
/// screen that showed the tutor, after the tutor dialog has closed.
class TutorNavigator {
  const TutorNavigator();

  /// Whether [action] needs the household's id.
  static bool needsHousehold(TutorAction action) => action != TutorAction.budgets;

  Future<void> open(BuildContext context, TutorAction action, String householdId) async {
    switch (action) {
      case TutorAction.payday:
        await HouseholdSetupCard.openPaydayEditor(context, householdId: householdId);
      case TutorAction.income:
        await RecordIncomeSheet.show(context, householdId: householdId);
      case TutorAction.accounts:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AccountsOverviewScreen(householdId: householdId)),
        );
      case TutorAction.budgets:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BudgetManagementScreen()),
        );
      case TutorAction.roles:
        await HouseholdSetupCard.showEditorSheet(context, HouseholdRolesCard(householdId: householdId));
    }
  }
}
