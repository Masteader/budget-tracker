// A sub-category the server refuses (403) or fails to save is not shown as added:
// it would vanish on the next load and its amount would never be saved.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';

class _FakeApi extends ApiService {
  _FakeApi({required this.refuse, this.status = 'success'});
  final bool refuse;
  final String status;
  final List<String> added = [];

  @override
  Future<Map<String, dynamic>> addSubCategory({
    required String householdId,
    required String parentCode,
    required String nameEn,
    double allocatedAmount = 0.0,
    String? subCode,
    String? cycleKey,
  }) async {
    if (refuse) throw Exception('403 Forbidden');
    added.add(nameEn);
    return {'status': status};
  }

  // No network in tests: the dialog loads the category's sub-categories.
  @override
  Future<List<Map<String, dynamic>>> getSubCategories(String parentCode, {String? householdId}) async => const [];
}

Future<void> _addToys(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(
      body: SubBudgetAllocationDialog(
        householdId: 'h-1',
        categoryCode: 'CUSTOM-PETS',
        categoryName: 'Pets',
        existingBudget: Budget(
          id: 'b-1',
          householdId: 'h-1',
          categoryCode: 'CUSTOM-PETS',
          allocatedAmount: 50,
          spentAmount: 0,
          remainingAmount: 50,
          month: '2026-11-01',
          subAllocations: {'sub-food': 50.0},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Add Custom Sub-Category'));
  await tester.pumpAndSettle();
  final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), 'Toys');
  await tester.enterText(fields.at(1), '20');
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add')));
  await tester.pumpAndSettle();
}

void main() {
  late ApiService original;
  setUp(() => original = ApiService.instance);
  tearDown(() => ApiService.instance = original);

  testWidgets('a refused sub-category is not added and the failure is shown', (tester) async {
    final api = _FakeApi(refuse: true);
    ApiService.instance = api;
    await _addToys(tester);

    expect(find.text('Add Failed'), findsOneWidget);
    expect(find.text('Toys'), findsNothing);
  });

  testWidgets('a sub-category the server did not save is not added', (tester) async {
    final api = _FakeApi(refuse: false, status: 'error');
    ApiService.instance = api;
    await _addToys(tester);

    expect(find.text('Add Failed'), findsOneWidget);
    expect(find.text('Toys'), findsNothing);
  });

  testWidgets('a saved sub-category is added', (tester) async {
    final api = _FakeApi(refuse: false);
    ApiService.instance = api;
    await _addToys(tester);

    expect(api.added, ['Toys']);
    expect(find.text('Toys'), findsWidgets);
    expect(find.text('Add Failed'), findsNothing);
  });
}
