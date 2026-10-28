import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/sub_budget_allocation_dialog.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';

void main() {
  final fakeApi = ApiService(
    budget: BudgetApiClient(
      baseClient: BaseApiClient(
        client: MockClient((request) async {
          return http.Response('{"status": "success", "sub_categories": []}', 200);
        }),
      ),
    ),
  );

  Widget buildHarness({
    required String categoryCode,
    required String categoryName,
    Map<String, double>? subAllocations,
    Map<String, dynamic>? metadata,
  }) {
    Budget? budget;
    if (subAllocations != null || metadata != null) {
      budget = Budget(
        id: 'b-sf-1',
        householdId: 'h-sf-123',
        categoryCode: categoryCode,
        allocatedAmount: subAllocations?.values.fold<double>(0.0, (a, b) => a + b) ?? 200.0,
        spentAmount: 0.0,
        remainingAmount: 200.0,
        month: '2026-10-01',
        subAllocations: subAllocations ?? {},
        metadata: metadata ?? {},
      );
    }

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizationsDelegate()],
      home: Scaffold(
        body: SubBudgetAllocationDialog(
          householdId: 'h-sf-123',
          categoryCode: categoryCode,
          categoryName: categoryName,
          existingBudget: budget,
          apiService: fakeApi,
        ),
      ),
    );
  }

  testWidgets('renders Sinking Fund chips and toggles accumulation on sub-categories', (tester) async {
    await tester.pumpWidget(buildHarness(
      categoryCode: 'OPEX-FUEL',
      categoryName: 'Fuel',
      subAllocations: {
        'gas_fuel': 150.0,
        'car_maintenance': 100.0,
      },
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SubBudgetAllocationDialog), findsOneWidget);

    // Initial state: sinking fund toggles should be visible on sub-categories
    final sfToggles = find.text('Accumulate unspent (Sinking fund)');
    expect(sfToggles, findsWidgets);

    // Tap first toggle chip
    await tester.tap(sfToggles.first);
    await tester.pumpAndSettle();

    // Now should show active badge
    expect(find.text('Sinking Fund'), findsOneWidget);
  });

  testWidgets('pre-populates active sinking fund from budget metadata', (tester) async {
    await tester.pumpWidget(buildHarness(
      categoryCode: 'OPEX-FUEL',
      categoryName: 'Fuel',
      subAllocations: {
        'gas_fuel': 150.0,
        'car_maintenance': 200.0,
      },
      metadata: {
        '_sinking_fund': {
          'car_maintenance': {'accumulate': true, 'base_amount': 100.0},
        },
      },
    ));
    await tester.pumpAndSettle();

    // Should already display the Sinking Fund active badge for car_maintenance
    expect(find.text('Sinking Fund'), findsOneWidget);
  });

  testWidgets('renders Sinking Fund switch on parent category without sub-categories', (tester) async {
    await tester.pumpWidget(buildHarness(
      categoryCode: 'CUSTOM-DONATIONS',
      categoryName: 'Charity & Donations',
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Carries over unspent funds each cycle; resets to base when spent.'), findsOneWidget);

    // Toggle parent switch
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });
}
