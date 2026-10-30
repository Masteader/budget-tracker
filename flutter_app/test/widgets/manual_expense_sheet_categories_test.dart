import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import '../support/localized_app.dart';

Widget _wrap(Widget child, {BudgetProvider? budgetProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider ?? BudgetProvider()),
      ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
      ChangeNotifierProvider<InstallmentProvider>(create: (_) => InstallmentProvider()),
    ],
    child: localizedApp(child, scaffold: false),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ManualExpenseSheet renders dynamic categories from BudgetProvider', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bp = BudgetProvider();
    // Invalidate cache
    bp.invalidateCategoriesCache();

    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: ManualExpenseSheet(
            householdId: 'hh-1',
            loadAccounts: (_) async => [],
          ),
        ),
        budgetProvider: bp,
      ),
    );
    await tester.pumpAndSettle();

    // Verify category dropdown is present
    expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
  });
}

