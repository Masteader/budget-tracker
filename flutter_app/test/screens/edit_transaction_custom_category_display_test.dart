import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';

class _FakeBudgetProvider extends ChangeNotifier implements BudgetProvider {
  List<CategoryItem> _activeCategories;
  final List<CategoryBreakdownItem> _categories;

  _FakeBudgetProvider({
    List<CategoryItem> activeCategories = const [],
    List<CategoryBreakdownItem> categories = const [],
  })  : _activeCategories = activeCategories,
        _categories = categories;

  @override
  List<CategoryItem> get activeCategories => _activeCategories;

  @override
  List<CategoryBreakdownItem> get categories => _categories;

  void setActiveCategories(List<CategoryItem> list) {
    _activeCategories = list;
    notifyListeners();
  }

  @override
  Future<Map<String, List<CategoryItem>>> getHouseholdCategories(
    String householdId, {
    bool forceRefresh = false,
  }) async {
    return {'active': _activeCategories, 'inactive': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Transaction _makeTx({
  required String id,
  required String categoryCode,
  String? subCategory,
  required double amount,
  String? merchant,
}) {
  return Transaction(
    id: id,
    householdId: 'h1',
    amount: amount,
    currency: 'SAR',
    categoryCode: categoryCode,
    subCategory: subCategory,
    merchant: merchant,
    timestamp: DateTime.utc(2026, 11, 2, 10),
    isReallocated: false,
    createdAt: DateTime.utc(2026, 11, 2, 10),
  );
}

Widget _wrapWithApp({
  required Widget child,
  required BudgetProvider budgetProvider,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BudgetProvider>.value(value: budgetProvider),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('EditTransactionSheet Custom Category & Sub-allocation Display', () {
    testWidgets('Custom category displays human name in dropdown and humanizes fallback code', (tester) async {
      final activeCategories = [
        const CategoryItem(
          code: 'CUSTOM-CAR_TRANSPORT',
          name: 'Car and Transport',
          isSystem: false,
          isActive: true,
          subAllocations: {'sub-gas': 400.0, 'sub-maintenance': 200.0},
        ),
        const CategoryItem(
          code: 'custom_gym_membership',
          name: 'custom_gym_membership', // Raw code name should be humanized
          isSystem: false,
          isActive: true,
        ),
        const CategoryItem(
          code: 'OPEX-GROCERY',
          name: 'Groceries & Supermarkets',
          isSystem: true,
          isActive: true,
        ),
      ];

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeCategories,
      );

      final tx = _makeTx(
        id: 'tx-custom-1',
        categoryCode: 'CUSTOM-CAR_TRANSPORT',
        amount: 250.0,
        merchant: 'Aramco Gas Station',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          budgetProvider: fakeBudgetProvider,
          child: EditTransactionSheet(
            transaction: tx,
            loadNafaqahFields: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Category dropdown
      final dropdownFinder = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // 1. Verify "Car and Transport" is displayed instead of "CUSTOM-CAR_TRANSPORT"
      expect(find.text('Car and Transport').last, findsOneWidget);
      expect(find.text('CUSTOM-CAR_TRANSPORT'), findsNothing);

      // 2. Verify "custom_gym_membership" is humanized to "Gym Membership"
      expect(find.text('Gym Membership').last, findsOneWidget);
      expect(find.text('custom_gym_membership'), findsNothing);

      // 3. Verify system category "Groceries & Supermarkets" is present
      expect(find.text('Groceries & Supermarkets').last, findsOneWidget);
    });

    testWidgets('Subcategories from subAllocations appear in dropdown for custom category', (tester) async {
      final activeCategories = [
        const CategoryItem(
          code: 'CUSTOM-CAR_TRANSPORT',
          name: 'Car and Transport',
          isSystem: false,
          isActive: true,
          subAllocations: {'sub-gas': 400.0, 'sub-maintenance': 200.0},
        ),
      ];

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeCategories,
      );

      final tx = _makeTx(
        id: 'tx-custom-2',
        categoryCode: 'CUSTOM-CAR_TRANSPORT',
        amount: 120.0,
        merchant: 'Shell Gas',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          budgetProvider: fakeBudgetProvider,
          child: EditTransactionSheet(
            transaction: tx,
            loadNafaqahFields: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Sub-Category dropdown
      final subCatDropdownFinder = find.byType(DropdownButtonFormField<String?>).last;
      await tester.tap(subCatDropdownFinder);
      await tester.pumpAndSettle();

      // Subcategories synthesized from subAllocations ('sub-gas' -> 'Gas', 'sub-maintenance' -> 'Maintenance')
      expect(find.text('Gas').last, findsOneWidget);
      expect(find.text('Maintenance').last, findsOneWidget);
    });

    testWidgets('Category race condition: stale subcategories are dropped if category changed', (tester) async {
      final activeCategories = [
        const CategoryItem(
          code: 'CUSTOM-CAR_TRANSPORT',
          name: 'Car and Transport',
          isSystem: false,
          isActive: true,
          subAllocations: {'sub-gas': 400.0},
        ),
        const CategoryItem(
          code: 'OPEX-GROCERY',
          name: 'Groceries & Supermarkets',
          isSystem: true,
          isActive: true,
          subAllocations: {'sub-produce': 150.0},
        ),
      ];

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeCategories,
      );

      final tx = _makeTx(
        id: 'tx-race-1',
        categoryCode: 'CUSTOM-CAR_TRANSPORT',
        amount: 50.0,
      );

      await tester.pumpWidget(
        _wrapWithApp(
          budgetProvider: fakeBudgetProvider,
          child: EditTransactionSheet(
            transaction: tx,
            loadNafaqahFields: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change category to OPEX-GROCERY
      final catDropdownFinder = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(catDropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Groceries & Supermarkets').last);
      await tester.pumpAndSettle();

      // Open subcategory dropdown
      final subCatDropdownFinder = find.byType(DropdownButtonFormField<String?>).last;
      await tester.tap(subCatDropdownFinder);
      await tester.pumpAndSettle();

      // "Produce" from OPEX-GROCERY should be present, "Gas" from stale CAT should NOT be present
      expect(find.text('Produce').last, findsOneWidget);
      expect(find.text('Gas'), findsNothing);
    });
  });
}
