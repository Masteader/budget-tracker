import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/utils/refresh_app_data.dart';

class MockAccountProvider extends ChangeNotifier implements AccountProvider {
  bool refreshed = false;
  @override
  Future<void> refresh() async {
    refreshed = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockBudgetProvider extends ChangeNotifier implements BudgetProvider {
  bool refreshed = false;
  @override
  Future<void> refresh() async {
    refreshed = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTransactionProvider extends ChangeNotifier implements TransactionProvider {
  bool fetched = false;
  @override
  Future<void> fetchTransactions() async {
    fetched = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockInstallmentProvider extends ChangeNotifier implements InstallmentProvider {
  bool fetched = false;
  @override
  Future<void> fetchPlans({bool silent = false}) async {
    fetched = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockRecurringBillsProvider extends ChangeNotifier implements RecurringBillsProvider {
  bool fetched = false;
  @override
  Future<void> fetchBills({bool silent = false}) async {
    fetched = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('refreshGlobalAppData calls refresh/fetch on all registered providers in parallel', (tester) async {
    final mockAccount = MockAccountProvider();
    final mockBudget = MockBudgetProvider();
    final mockTx = MockTransactionProvider();
    final mockInstallment = MockInstallmentProvider();
    final mockBills = MockRecurringBillsProvider();

    late BuildContext testContext;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: mockAccount),
          ChangeNotifierProvider<BudgetProvider>.value(value: mockBudget),
          ChangeNotifierProvider<TransactionProvider>.value(value: mockTx),
          ChangeNotifierProvider<InstallmentProvider>.value(value: mockInstallment),
          ChangeNotifierProvider<RecurringBillsProvider>.value(value: mockBills),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await refreshGlobalAppData(testContext);

    expect(mockAccount.refreshed, isTrue);
    expect(mockBudget.refreshed, isTrue);
    expect(mockTx.fetched, isTrue);
    expect(mockInstallment.fetched, isTrue);
    expect(mockBills.fetched, isTrue);
  });
}
