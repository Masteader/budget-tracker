// A plan the viewer no longer reads (owner decision 2026-11-06: the plan of
// a wife's personal purchase is read only by her, her husband and an admin
// who is not a wife) cannot be deleted by them: RLS filters it out without an
// error, so a delete reaches no row. The app must not report that as a
// deletion: it says the record no longer exists and reloads the list.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/widgets/dashboard/installment_plans_card.dart';

class _Provider extends ChangeNotifier implements InstallmentProvider {
  _Provider(this._delete);

  final Future<bool> Function(String planId) _delete;
  int fetches = 0;

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
  Future<void> fetchPlans({bool silent = false}) async => fetches++;

  @override
  Future<InstallmentPlan> createPlan(Map<String, dynamic> planData) async => throw UnimplementedError();

  @override
  Future<bool> recordPayment(String planId) async => true;

  @override
  Future<bool> deletePlan(String planId) => _delete(planId);

  @override
  Future<InstallmentPlan> updatePlan(String planId, Map<String, dynamic> updateData) async =>
      throw UnimplementedError();

  @override
  void setPlansForTesting(List<InstallmentPlan> testPlans, {String? householdId}) {}

  @override
  void reset() {}
}

final _plan = InstallmentPlan(
  id: 'plan_1',
  householdId: 'hh_1',
  merchant: 'Tabby Boutique',
  provider: 'Tabby',
  totalAmount: 800.0,
  installmentCount: 4,
  monthlyAmount: 200.0,
  paidInstallments: 1,
  dayOfMonth: 27,
  startDate: '2026-10-01',
  status: 'ACTIVE',
);

Future<void> _deleteFromCard(WidgetTester tester, _Provider provider) async {
  provider.plans = [_plan];
  await tester.pumpWidget(
    ChangeNotifierProvider<InstallmentProvider>.value(
      value: provider,
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
            child: InstallmentPlansCard(plans: [_plan], now: DateTime.utc(2026, 10, 21, 9)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  // The confirmation dialog's own Delete button.
  await tester.tap(find.text('Delete').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('InstallmentProvider.deletePlan', () {
    test('a delete that reached its row is a deletion', () async {
      final provider = InstallmentProvider(deleteRow: (id) async => [
            {'id': id}
          ]);
      expect(await provider.deletePlan('plan_1'), isTrue);
    });

    test('a delete that reached no row (not read, or gone) is not a deletion', () async {
      final provider = InstallmentProvider(deleteRow: (id) async => const []);
      expect(await provider.deletePlan('plan_1'), isFalse);
    });

    test('a failed delete is reported as a failure, not as gone', () async {
      final provider = InstallmentProvider(deleteRow: (id) async => throw Exception('offline'));
      await expectLater(provider.deletePlan('plan_1'), throwsA(isA<Exception>()));
    });
  });

  group('InstallmentPlansCard delete', () {
    testWidgets('a plan the viewer no longer reads: says it no longer exists, never "deleted"', (tester) async {
      final provider = _Provider((id) async => false);
      await _deleteFromCard(tester, provider);
      expect(find.text('This record no longer exists. Refresh and try again.'), findsOneWidget);
      expect(find.text('Installment plan deleted'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a deleted plan: says it was deleted', (tester) async {
      final provider = _Provider((id) async => true);
      await _deleteFromCard(tester, provider);
      expect(find.text('Installment plan deleted'), findsOneWidget);
      expect(find.text('This record no longer exists. Refresh and try again.'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a failed delete: shows the failure, never "deleted"', (tester) async {
      final provider = _Provider((id) async => throw Exception('offline'));
      await _deleteFromCard(tester, provider);
      expect(find.text('Installment plan deleted'), findsNothing);
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
