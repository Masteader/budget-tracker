import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/household_role_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/budget_management_screen.dart';
import 'package:budget_tracker/widgets/app_shimmer.dart';
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
    test('budget_management_screen.dart source code contains NO references to BudgetRepairService', () {
      final src = File('lib/screens/home/budget_management_screen.dart').readAsStringSync();
      expect(
        src.contains('BudgetRepairService'),
        isFalse,
        reason: 'BudgetRepairService must not be referenced in budget_management_screen.dart',
      );
    });

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
  });
}
