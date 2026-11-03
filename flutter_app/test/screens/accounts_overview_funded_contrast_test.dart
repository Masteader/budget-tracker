import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import '../support/localized_app.dart';

class _MockAccountService extends AccountService {
  final Map<String, double> testCommitted;
  final List<Account> testAccounts;
  final double testIncome;

  _MockAccountService({
    required this.testCommitted,
    required this.testAccounts,
    required this.testIncome,
  });

  @override
  Future<List<Account>> getAccounts(String householdId) async => testAccounts;

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => testIncome;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => [];

  @override
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async => testCommitted;

  @override
  Future<void> reconcileUnlinkedTransactions(
    String householdId, {
    required bool callerIsAdmin,
    String? currentUserId,
    Future<List<Account>> Function(String p1)? fetchAccounts,
    Future<List<Map<String, dynamic>>> Function(String p1)? fetchUnlinked,
    Future<void> Function(String p1, String p2)? linkTransaction,
  }) async {}
}

class _MockCommitmentsService extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async => [];
}

void main() {
  group('AccountsOverviewScreen "Funded" Badge Contrast & Theme Styling', () {
    testWidgets('Light Mode: Funded badge text uses dark emerald context.successText, NOT white', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final originalService = AccountService.instance;
      addTearDown(() => AccountService.instance = originalService);

      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Main Account',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 5000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );

      final mockService = _MockAccountService(
        testCommitted: {'acc-1': 3000.0}, // No deficit (5000 >= 3000)
        testAccounts: [acc],
        testIncome: 8000.0,
      );
      AccountService.instance = mockService;

      final accountProvider = AccountProvider(
        accounts: mockService,
        commitments: _MockCommitmentsService(),
      );
      accountProvider.bindHousehold('hh-1', paydayDay: 27);
      accountProvider.setAccountsForTesting([acc], householdId: 'hh-1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: accountProvider,
          child: localizedApp(
            const AccountsOverviewScreen(householdId: 'hh-1'),
            scaffold: false,
            lang: 'en',
            dark: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fundedTextFinder = find.text('Funded');
      expect(fundedTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(fundedTextFinder);
      expect(textWidget.style?.color, isNotNull);
      // In light mode, text MUST NOT be white (white-on-white bug)
      expect(textWidget.style?.color, isNot(equals(Colors.white)));
      // It must match context.successText in light mode: Color(0xFF065F46)
      expect(textWidget.style?.color, equals(const Color(0xFF065F46)));

      // Find the pill Container wrapping the text
      final containerFinder = find.ancestor(
        of: fundedTextFinder,
        matching: find.byType(Container),
      ).first;
      final containerWidget = tester.widget<Container>(containerFinder);
      final decoration = containerWidget.decoration as BoxDecoration;
      expect(decoration.color, equals(VelvetBurgundyColors.emeraldSafeBgLight));
    });

    testWidgets('Dark Mode: Funded badge text uses VelvetBurgundyColors.emeraldSafe', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final originalService = AccountService.instance;
      addTearDown(() => AccountService.instance = originalService);

      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Main Account',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 5000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );

      final mockService = _MockAccountService(
        testCommitted: {'acc-1': 2000.0},
        testAccounts: [acc],
        testIncome: 8000.0,
      );
      AccountService.instance = mockService;

      final accountProvider = AccountProvider(
        accounts: mockService,
        commitments: _MockCommitmentsService(),
      );
      accountProvider.bindHousehold('hh-1', paydayDay: 27);
      accountProvider.setAccountsForTesting([acc], householdId: 'hh-1');

      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: accountProvider,
          child: localizedApp(
            const AccountsOverviewScreen(householdId: 'hh-1'),
            scaffold: false,
            lang: 'en',
            dark: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fundedTextFinder = find.text('Funded');
      expect(fundedTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(fundedTextFinder);
      expect(textWidget.style?.color, equals(VelvetBurgundyColors.emeraldSafe));

      final containerFinder = find.ancestor(
        of: fundedTextFinder,
        matching: find.byType(Container),
      ).first;
      final containerWidget = tester.widget<Container>(containerFinder);
      final decoration = containerWidget.decoration as BoxDecoration;
      expect(decoration.color, equals(VelvetBurgundyColors.emeraldSafe.withValues(alpha: 0.16)));
    });

    testWidgets('Deficit Badge: uses red colors in both light and dark themes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final originalService = AccountService.instance;
      addTearDown(() => AccountService.instance = originalService);

      // Balance 1000 < Committed 3000 => deficit
      final acc = Account(
        id: 'acc-1',
        householdId: 'hh-1',
        ownerUserId: 'u-1',
        name: 'Main Account',
        accountType: AccountType.bank,
        currency: 'SAR',
        balance: 1000.0,
        isSharedPool: true,
        colorHex: '#10B981',
        iconName: 'account_balance',
        isArchived: false,
        createdAt: DateTime(2026, 1, 1),
      );

      final mockService = _MockAccountService(
        testCommitted: {'acc-1': 3000.0},
        testAccounts: [acc],
        testIncome: 8000.0,
      );
      AccountService.instance = mockService;

      final accountProvider = AccountProvider(
        accounts: mockService,
        commitments: _MockCommitmentsService(),
      );
      accountProvider.bindHousehold('hh-1', paydayDay: 27);
      accountProvider.setAccountsForTesting([acc], householdId: 'hh-1');

      // Test Light Mode Deficit
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: accountProvider,
          child: localizedApp(
            const AccountsOverviewScreen(householdId: 'hh-1'),
            scaffold: false,
            lang: 'en',
            dark: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final deficitTextFinder = find.text('1 Deficit');
      expect(deficitTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(deficitTextFinder);
      expect(textWidget.style?.color, equals(Colors.red.shade800));
    });
  });
}
