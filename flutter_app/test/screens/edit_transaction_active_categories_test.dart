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

  _FakeBudgetProvider({List<CategoryItem> activeCategories = const []})
      : _activeCategories = activeCategories;

  @override
  List<CategoryItem> get activeCategories => _activeCategories;

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
  required double amount,
  String? merchant,
}) {
  return Transaction(
    id: id,
    householdId: 'h1',
    amount: amount,
    currency: 'SAR',
    categoryCode: categoryCode,
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
  group('EditTransactionSheet Category Dropdown Scoping Tests (Issue 3)', () {
    final activeHouseholdCategories = [
      const CategoryItem(
        code: 'OPEX-GROCERY',
        name: 'Groceries & Supermarkets',
        isSystem: true,
        isActive: true,
      ),
      const CategoryItem(
        code: 'OPEX-DINING',
        name: 'Dining & Cafes',
        isSystem: true,
        isActive: true,
      ),
      const CategoryItem(
        code: 'OPEX-HEALTH',
        name: 'Health & Pharmacy',
        isSystem: true,
        isActive: true,
      ),
    ];

    testWidgets('scopes dropdown to active household categories and excludes inactive global codes', (tester) async {
      final tx = _makeTx(
        id: 'tx-1',
        categoryCode: 'OPEX-GROCERY',
        amount: 150.0,
        merchant: 'Tamimi Markets',
      );

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeHouseholdCategories,
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

      // Active categories must be present
      expect(find.text('Groceries & Supermarkets').last, findsOneWidget);
      expect(find.text('Dining & Cafes').last, findsOneWidget);
      expect(find.text('Health & Pharmacy').last, findsOneWidget);

      // Inactive taxonomy categories (e.g. Fuel OPEX-FUEL) must NOT be present
      expect(find.text('Fuel'), findsNothing);
      expect(find.text('Entertainment'), findsNothing);
    });

    testWidgets('retains unbudgeted transaction category (e.g. Fuel) with (Unbudgeted) tag', (tester) async {
      // Transaction has OPEX-FUEL, which is NOT in activeHouseholdCategories
      final tx = _makeTx(
        id: 'tx-2',
        categoryCode: 'OPEX-FUEL',
        amount: 85.0,
        merchant: 'Sasco Fuel Station',
      );

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeHouseholdCategories,
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

      // Initial value shows Fuel with unbudgeted tag
      expect(find.textContaining('Fuel (Unbudgeted)'), findsOneWidget);

      // Open dropdown to verify list contains both Fuel (Unbudgeted) and active categories
      final dropdownFinder = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Fuel (Unbudgeted)'), findsWidgets);
      expect(find.text('Groceries & Supermarkets').last, findsOneWidget);
      expect(find.text('Dining & Cafes').last, findsOneWidget);
    });

    testWidgets('unbudgeted category displays Arabic localized tag (غير مدرج في الميزانية) in Arabic locale', (tester) async {
      final tx = _makeTx(
        id: 'tx-ar',
        categoryCode: 'OPEX-FUEL',
        amount: 85.0,
        merchant: 'ساسكو',
      );

      final fakeBudgetProvider = _FakeBudgetProvider(
        activeCategories: activeHouseholdCategories,
      );

      await tester.pumpWidget(
        _wrapWithApp(
          budgetProvider: fakeBudgetProvider,
          locale: const Locale('ar'),
          child: EditTransactionSheet(
            transaction: tx,
            loadNafaqahFields: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Arabic tag: الوقود (غير مدرج في الميزانية)
      expect(find.textContaining('غير مدرج في الميزانية'), findsOneWidget);
    });

    testWidgets('falls back gracefully to global taxonomy if activeCategories is empty', (tester) async {
      final tx = _makeTx(
        id: 'tx-empty',
        categoryCode: 'OPEX-GROCERY',
        amount: 50.0,
        merchant: 'Supermarket',
      );

      // Provider with empty active categories
      final fakeBudgetProvider = _FakeBudgetProvider(activeCategories: const []);

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

      // Open dropdown
      final dropdownFinder = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Fallback taxonomy codes should be visible without throwing duplicate key errors
      expect(find.text('Groceries & Supermarkets').last, findsOneWidget);
      expect(find.text('Fuel').last, findsOneWidget);
    });
  });
}
