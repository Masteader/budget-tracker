import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/widgets/app_shimmer.dart';
import 'package:budget_tracker/models/household_setup.dart';
import 'package:budget_tracker/widgets/dashboard/household_setup_card.dart';
import '../support/localized_app.dart';

class TestHouseholdRoleProvider extends HouseholdRoleProvider {
  final String _testHid;
  final String _testRole;

  TestHouseholdRoleProvider({String householdId = 'test-hid', String role = 'admin'})
      : _testHid = householdId,
        _testRole = role;

  @override
  bool get isLoaded => true;

  @override
  String? get householdId => _testHid;

  @override
  String get role => _testRole;

  @override
  bool get isAdmin => _testRole == 'admin';
}

class MockBudgetProvider extends BudgetProvider {
  int getHouseholdCategoriesCallCount = 0;

  @override
  Future<Map<String, List<CategoryItem>>> getHouseholdCategories(
    String householdId, {
    bool forceRefresh = false,
  }) async {
    getHouseholdCategoriesCallCount++;
    return {
      'active': [
        const CategoryItem(code: 'OPEX-FOOD', name: 'Food & Dining', isSystem: true),
      ],
      'archived': [],
    };
  }
}

Widget _wrapWithProviders(
  Widget child, {
  BudgetProvider? budgetProvider,
  HouseholdRoleProvider? roleProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountProvider>(create: (_) => AccountProvider()),
      ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => budgetProvider ?? BudgetProvider()),
      ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => roleProvider ?? TestHouseholdRoleProvider()),
    ],
    child: localizedApp(child, scaffold: false),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BudgetManagementScreen Instant Load & Stale-While-Revalidate', () {
    test('budget_management_screen.dart fetches categories through BudgetProvider.getHouseholdCategories', () {
      final src = File('lib/screens/home/budget_management_screen.dart').readAsStringSync();
      expect(
        src.contains('getHouseholdCategories'),
        isTrue,
        reason: 'Must use budgetProvider.getHouseholdCategories instead of direct ApiService fetch',
      );
      expect(
        src.contains('ApiService.instance.fetchHouseholdCategories'),
        isFalse,
        reason: 'Must not call ApiService.instance.fetchHouseholdCategories directly',
      );
    });

    testWidgets('BudgetManagementScreen calls BudgetProvider.getHouseholdCategories during load', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final mockBudgetProvider = MockBudgetProvider();

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetManagementScreen(
            budgetStreamOverride: (_) => Stream.value([]),
          ),
          budgetProvider: mockBudgetProvider,
        ),
      );
      await tester.pump();

      expect(mockBudgetProvider.getHouseholdCategoriesCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('renders shimmer skeleton when no cached static data exists and data is loading', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pendingCompleter = Completer<BudgetStaticData>();

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetManagementScreen(
            initialStaticData: null,
            loadStaticDataOverride: () => pendingCompleter.future,
            budgetStreamOverride: (_) => Stream.value([]),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppShimmer), findsOneWidget);
    });

    testWidgets('when cached static data exists, BudgetManagementScreen renders without showing a full 5-item shimmer skeleton', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pendingCompleter = Completer<BudgetStaticData>();

      final cachedData = BudgetStaticData(
        householdId: 'test-hid',
        isAdmin: true,
        allCodes: [
          {'code': 'OPEX-FOOD', 'category': 'Food & Dining', 'is_system': 'true'},
        ],
        monthlyIncome: 10000.0,
        accounts: [],
      );

      await tester.pumpWidget(
        _wrapWithProviders(
          BudgetManagementScreen(
            initialStaticData: cachedData,
            loadStaticDataOverride: () => pendingCompleter.future,
            budgetStreamOverride: (_) => Stream.value([]),
          ),
        ),
      );
      await tester.pump();

      // AppShimmer skeleton must NOT be rendered when cached static data exists
      expect(find.byType(AppShimmer), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    });
    testWidgets('BudgetManagementScreen binds unbound AccountProvider with payday from HouseholdSetupPrefs', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.reset();
        HouseholdSetupPrefs.loadOverride = null;
      });

      HouseholdSetupPrefs.loadOverride = (hid) async => const HouseholdSetupData(paydayDay: 10);
      final accProvider = AccountProvider();
      expect(accProvider.householdId, isNull);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccountProvider>.value(value: accProvider),
            ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
            ChangeNotifierProvider<BudgetProvider>(create: (_) => MockBudgetProvider()),
            ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => TestHouseholdRoleProvider(householdId: 'test-hid')),
          ],
          child: localizedApp(
            BudgetManagementScreen(
              budgetStreamOverride: (_) => Stream.value([]),
            ),
            scaffold: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(accProvider.householdId, isNotNull);
      expect(accProvider.householdId, equals('test-hid'));
      expect(accProvider.paydayDay, equals(10));
    });

    test('source guard: no file hardcodes payday = 27 (Item 9)', () {
      final paths = [
        'lib/screens/home/budget_management_screen.dart',
        'lib/screens/home/dashboard_screen.dart',
        'lib/widgets/accounts/add_edit_account_dialog.dart',
      ];
      final regex = RegExp(r'[Pp]ayday(Day)?\s*=\s*27\b');
      for (final p in paths) {
        final file = File(p);
        expect(file.existsSync(), isTrue, reason: 'File $p must exist');
        final src = file.readAsStringSync();
        expect(regex.hasMatch(src), isFalse, reason: 'File $p contains hardcoded payday = 27');
      }
    });

    testWidgets('BudgetManagementScreen skips HouseholdSetupPrefs.load when AccountProvider is already bound (Item 10)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      var loadCount = 0;
      addTearDown(() {
        tester.view.reset();
        HouseholdSetupPrefs.loadOverride = null;
      });

      HouseholdSetupPrefs.loadOverride = (hid) async {
        loadCount++;
        return const HouseholdSetupData(paydayDay: 15);
      };

      final accProvider = AccountProvider();
      accProvider.bindHousehold('test-hid', paydayDay: 15);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccountProvider>.value(value: accProvider),
            ChangeNotifierProvider<TransactionProvider>(create: (_) => TransactionProvider()),
            ChangeNotifierProvider<BudgetProvider>(create: (_) => MockBudgetProvider()),
            ChangeNotifierProvider<HouseholdRoleProvider>(create: (_) => TestHouseholdRoleProvider(householdId: 'test-hid')),
          ],
          child: localizedApp(
            BudgetManagementScreen(
              budgetStreamOverride: (_) => Stream.value([]),
            ),
            scaffold: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(loadCount, equals(0));
    });
  });
}
