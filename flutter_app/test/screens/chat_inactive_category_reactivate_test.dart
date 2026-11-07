// Reactivating an inactive category from the chat reports a refusal, and on success
// clears the cached category list so other screens see the category as active.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/screens/chat/chat_entry_screen.dart';
import 'package:budget_tracker/services/api_service.dart';
import '../support/localized_app.dart';

class _FakeApi extends ApiService {
  _FakeApi({required this.accept});
  final bool accept;
  final List<String> toggles = [];

  @override
  Future<Map<String, List<CategoryItem>>> fetchHouseholdCategories(String householdId) async => {
        'active': const [],
        'inactive': const [CategoryItem(code: 'OPEX-FUEL', name: 'Fuel', isSystem: true, isActive: false)],
      };

  @override
  Future<Map<String, dynamic>> postChatTransaction({
    required String message,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = true,
    String? merchant,
    String? spentBy,
    String? categoryCode,
    String? subCategory,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? accountId,
  }) async =>
      {
        'status': 'pending_confirmation',
        'is_category_inactive': true,
        'category_code': 'OPEX-FUEL',
        'amount': 80.0,
        'merchant': 'ALDREES',
        'message': 'Confirm?',
      };

  @override
  Future<bool> toggleCategoryStatus({
    required String householdId,
    required String categoryCode,
    required bool isActive,
  }) async {
    toggles.add('$categoryCode=$isActive');
    return accept;
  }
}

Future<BudgetProvider> _reactivateFromChat(WidgetTester tester, _FakeApi api) async {
  final original = ApiService.instance;
  ApiService.instance = api;
  addTearDown(() => ApiService.instance = original);
  final budgets = BudgetProvider(api: api);
  await budgets.getHouseholdCategories('hh-1');

  await tester.pumpWidget(ChangeNotifierProvider<BudgetProvider>.value(
    value: budgets,
    child: localizedApp(const ChatEntryScreen(householdId: 'hh-1'), lang: 'en', scaffold: false),
  ));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'fuel 80 aldrees');
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();

  expect(find.text('Inactive Category Detected'), findsOneWidget);
  await tester.tap(find.text('Reactivate Category'));
  await tester.pumpAndSettle();
  return budgets;
}

void main() {
  testWidgets('a refused reactivation says it failed and keeps the cached list', (tester) async {
    final api = _FakeApi(accept: false);
    final budgets = await _reactivateFromChat(tester, api);

    expect(api.toggles, ['OPEX-FUEL=true']);
    expect(find.text('Failed to update category'), findsOneWidget);
    expect(budgets.cachedCategories, isNotNull);
  });

  testWidgets('an accepted reactivation clears the cached category list', (tester) async {
    final api = _FakeApi(accept: true);
    final budgets = await _reactivateFromChat(tester, api);

    expect(api.toggles, ['OPEX-FUEL=true']);
    expect(find.text('Failed to update category'), findsNothing);
    expect(budgets.cachedCategories, isNull, reason: 'the stale "inactive" list must not be reused');
  });
}
