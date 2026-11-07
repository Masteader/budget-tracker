import 'package:flutter/material.dart';

import '../../models/tutor_viewer.dart';
import '../../screens/accounts/accounts_overview_screen.dart';
import '../../screens/home/budget_management_screen.dart';
import '../../services/api_service.dart';
import '../accounts/record_income_sheet.dart';
import '../dashboard/household_setup_card.dart';
import '../settings/household_roles_card.dart';

/// Opens the screen or sheet of a [TutorAction] from the context of the
/// screen that showed the tutor, after the tutor dialog has closed.
class TutorNavigator {
  const TutorNavigator();

  /// Whether [action] needs the household's id.
  static bool needsHousehold(TutorAction action) => tutorActionNeedsHousehold(action);

  /// [paydayDay] is the household's payday when the caller knows it; else
  /// it is read from the server, so the editor never starts on the phone's
  /// cached payday of another household (review R2-2).
  Future<void> open(BuildContext context, TutorAction action, String householdId, {int? paydayDay}) async {
    switch (action) {
      case TutorAction.payday:
        var day = paydayDay;
        if (day == null) {
          try {
            day = await ApiService.instance.getHouseholdPayday(householdId);
          } catch (_) {
            day = null;
          }
        }
        if (!context.mounted) return;
        await HouseholdSetupCard.openPaydayEditor(context, householdId: householdId, initialPayday: day);
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
