import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/widgets/dashboard/installment_plans_card.dart';

class MockInstallmentProvider extends ChangeNotifier implements InstallmentProvider {
  InstallmentPlan? lastUpdatedPlan;
  Map<String, dynamic>? lastUpdateData;
  bool updateCalled = false;

  @override
  List<InstallmentPlan> plans = [];

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  DateTime? lastUpdated;

  @override
  bool get hasLoaded => true;

  @override
  String? get householdId => 'hh_1';

  @override
  bool get isInitialized => true;

  @override
  Future<void> init(String householdId) async {}

  @override
  Future<void> fetchPlans({bool silent = false}) async {}

  @override
  Future<InstallmentPlan> createPlan(Map<String, dynamic> planData) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> recordPayment(String planId) async => true;

  @override
  Future<bool> deletePlan(String planId) async => true;

  @override
  Future<InstallmentPlan> updatePlan(String planId, Map<String, dynamic> updateData) async {
    updateCalled = true;
    lastUpdateData = updateData;
    final plan = plans.firstWhere((p) => p.id == planId);
    final updated = plan.copyWith(
      merchant: updateData['merchant'] as String? ?? plan.merchant,
      totalAmount: (updateData['total_amount'] as num?)?.toDouble() ?? plan.totalAmount,
    );
    lastUpdatedPlan = updated;
    return updated;
  }

  @override
  void setPlansForTesting(List<InstallmentPlan> testPlans, {String? householdId}) {
    plans = testPlans;
    notifyListeners();
  }

  @override
  void reset() {}
}

void main() {
  testWidgets('InstallmentPlansCard shows edit option and opens edit dialog', (tester) async {
    final mockProvider = MockInstallmentProvider();
    final testPlan = InstallmentPlan(
      id: 'plan_1',
      householdId: 'hh_1',
      merchant: 'eXtra Electronics',
      provider: 'Tamara',
      totalAmount: 4000.0,
      installmentCount: 4,
      monthlyAmount: 1000.0,
      paidInstallments: 1,
      dayOfMonth: 27,
      startDate: '2026-10-01',
      status: 'ACTIVE',
    );
    mockProvider.plans = [testPlan];

    await tester.pumpWidget(
      ChangeNotifierProvider<InstallmentProvider>.value(
        value: mockProvider,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(
                plans: [testPlan],
                now: DateTime.utc(2026, 10, 21, 9),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Installments & BNPL'), findsOneWidget);
    expect(find.text('eXtra Electronics'), findsOneWidget);
    // Find the 3-dots popup menu
    final menuBtn = find.byIcon(Icons.more_vert);
    expect(menuBtn, findsOneWidget);
    await tester.tap(menuBtn);
    await tester.pumpAndSettle();

    // Verify Edit option is present in popup menu
    final editOption = find.text('Edit');
    expect(editOption, findsOneWidget);

    // Tap Edit
    await tester.tap(editOption);
    await tester.pumpAndSettle();

    // Verify Edit Dialog opens with title
    expect(find.text('Edit Installment Plan'), findsOneWidget);
    expect(find.text('eXtra Electronics'), findsNWidgets(2));

    // Change merchant name
    final merchantField = find.byType(TextFormField).first;
    await tester.enterText(merchantField, 'eXtra Flagship Store');
    await tester.pump();

    // Tap Save
    final saveBtn = find.text('Save');
    expect(saveBtn, findsOneWidget);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    // Verify provider updatePlan was called
    expect(mockProvider.updateCalled, isTrue);
    expect(mockProvider.lastUpdateData?['merchant'], 'eXtra Flagship Store');
  });

  testWidgets('Edit dialog auto-recalculates monthly amount and provides frequency selector (CRITICAL-01)', (tester) async {
    final mockProvider = MockInstallmentProvider();
    final testPlan = InstallmentPlan(
      id: 'plan_2',
      householdId: 'hh_1',
      merchant: 'IKEA Furniture',
      provider: 'Tabby',
      totalAmount: 4000.0,
      installmentCount: 4,
      monthlyAmount: 1000.0,
      paidInstallments: 1,
      dayOfMonth: 27,
      startDate: '2026-10-01',
      frequency: 'monthly',
      status: 'ACTIVE',
    );
    mockProvider.plans = [testPlan];

    await tester.pumpWidget(
      ChangeNotifierProvider<InstallmentProvider>.value(
        value: mockProvider,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: InstallmentPlansCard(
                plans: [testPlan],
                now: DateTime.utc(2026, 10, 21, 9),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open popup menu and tap Edit
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // Verify frequency options exist
    expect(find.text('Monthly'), findsWidgets);
    expect(find.text('Bi-weekly'), findsWidgets);

    // Tap Bi-weekly
    await tester.tap(find.text('Bi-weekly'));
    await tester.pumpAndSettle();

    // Find TextFormFields:
    // 0: merchant, 1: total_amount, 2: monthly_amount, 3: count, 4: paid, 5: day
    final fields = find.byType(TextFormField);
    final totalField = fields.at(1);
    final monthlyField = fields.at(2);
    final countField = fields.at(3);

    // Change total from 4000 to 6000
    await tester.enterText(totalField, '6000');
    await tester.pumpAndSettle();

    // Monthly field should auto-recalculate to 1500.00 (6000 / 4)
    final monthlyWidget = tester.widget<TextFormField>(monthlyField);
    expect(monthlyWidget.controller?.text, '1500.00');

    // Change count to 6
    await tester.enterText(countField, '6');
    await tester.pumpAndSettle();

    // Monthly field should auto-recalculate to 1000.00 (6000 / 6)
    final monthlyWidgetAfterCount = tester.widget<TextFormField>(monthlyField);
    expect(monthlyWidgetAfterCount.controller?.text, '1000.00');

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(mockProvider.updateCalled, isTrue);
    expect(mockProvider.lastUpdateData?['frequency'], 'biweekly');
    expect(mockProvider.lastUpdateData?['total_amount'], 6000.0);
    expect(mockProvider.lastUpdateData?['installment_count'], 6);
    expect(mockProvider.lastUpdateData?['monthly_amount'], 1000.0);
  });
}
