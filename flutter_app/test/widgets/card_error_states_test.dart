// UX-01 / UX-25: an API failure is an error with a retry, never an empty or
// positive state ("all installments paid", a vanished Nafaqah card, the
// first-time bills set-up). Loading, empty and error are distinct.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/installment_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:budget_tracker/widgets/card_error_state.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/dashboard/household_balances_section.dart';
import 'package:budget_tracker/widgets/dashboard/installment_plans_card.dart';
import 'package:budget_tracker/widgets/dashboard/recurring_bills_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _networkError = {'status': 'error', 'message': 'Connection refused', 'network_error': true};

class _FakeBase extends BaseApiClient {
  Map<String, dynamic> response = _networkError;

  @override
  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async =>
      response;
}

/// A budget client whose list calls fail until [failing] is cleared.
class _FakeBudgetApi extends BudgetApiClient {
  bool failing = true;
  int billCalls = 0;
  int planCalls = 0;
  List<InstallmentPlan> plans = const [];

  @override
  Future<RecurringBillsSummary> fetchRecurringBills({required String householdId, String? asOfDate}) async {
    billCalls++;
    if (failing) throw const ApiRequestException('Connection refused');
    return const RecurringBillsSummary(
      cycleKey: '2026-11',
      cycleLabel: '',
      totalRecurringMonthly: 350,
      paidThisCycle: 0,
      reservedAmount: 350,
      bills: [
        RecurringBillItem(
          merchant: 'Saudi Electricity Co.',
          normalizedMerchant: 'saudi electricity co.',
          categoryCode: 'OPEX-UTILITIES',
          subCode: 'electricity',
          averageAmount: 350,
          expectedDayOfMonth: 28,
          status: 'UPCOMING',
        ),
      ],
    );
  }

  @override
  Future<List<InstallmentPlan>> fetchInstallments({required String householdId}) async {
    planCalls++;
    if (failing) throw const ApiRequestException('Connection refused');
    return plans;
  }
}

InstallmentPlan _plan({String status = 'ACTIVE', int paid = 1}) => InstallmentPlan(
      id: 'p1',
      householdId: 'hh',
      merchant: 'eXtra',
      provider: 'Tamara',
      totalAmount: 1200,
      installmentCount: 4,
      monthlyAmount: 300,
      paidInstallments: paid,
      dayOfMonth: 27,
      startDate: '2026-10-01',
      status: status,
    );

Widget _app(Widget child, {List<ChangeNotifierProvider> providers = const []}) {
  final app = MaterialApp(
    localizationsDelegates: const [AppLocalizationsDelegate()],
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  return providers.isEmpty ? app : MultiProvider(providers: providers, child: app);
}

void main() {
  group('API clients report failures instead of empty results', () {
    test('recurring bills: an error answer throws', () async {
      final client = BudgetApiClient(baseClient: _FakeBase());
      expect(() => client.fetchRecurringBills(householdId: 'hh'), throwsA(isA<ApiRequestException>()));
    });

    test('installments: an error answer throws; an empty answer is an empty list', () async {
      final base = _FakeBase();
      final client = BudgetApiClient(baseClient: base);
      expect(() => client.fetchInstallments(householdId: 'hh'), throwsA(isA<ApiRequestException>()));
      base.response = {'status': 'success', 'plans': []};
      expect(await client.fetchInstallments(householdId: 'hh'), isEmpty);
    });

    test('settlement v2: an error answer throws instead of a "standard" summary', () async {
      final client = BudgetApiClient(baseClient: _FakeBase());
      expect(() => client.fetchSettlementV2(householdId: 'hh'), throwsA(isA<ApiRequestException>()));
    });
  });

  group('providers keep the error', () {
    test('installments: a failure is an error, not an empty list from a fallback', () async {
      final fake = _FakeBudgetApi();
      final provider = InstallmentProvider(api: ApiService(budget: fake));
      await provider.init('hh');
      expect(provider.error, isNotNull);
      expect(provider.hasLoaded, isFalse);

      fake
        ..failing = false
        ..plans = [_plan()];
      await provider.fetchPlans();
      expect(provider.error, isNull);
      expect(provider.hasLoaded, isTrue);
      expect(provider.plans, hasLength(1));

      // A later failure keeps the last plans and says they are stale.
      fake.failing = true;
      await provider.fetchPlans(silent: true);
      expect(provider.error, isNotNull);
      expect(provider.plans, hasLength(1));
      expect(provider.lastUpdated, isNotNull);
    });

    test('recurring bills: a failure keeps no summary and an error', () async {
      final fake = _FakeBudgetApi();
      final provider = RecurringBillsProvider(api: ApiService(budget: fake));
      await provider.init('hh');
      expect(provider.error, isNotNull);
      expect(provider.summary, isNull);
    });
  });

  group('cards', () {
    testWidgets('recurring bills: error with retry, not the first-time set-up', (tester) async {
      final fake = _FakeBudgetApi();
      final bills = RecurringBillsProvider(api: ApiService(budget: fake));
      await tester.pumpWidget(_app(
        const RecurringBillsCard(householdId: 'hh'),
        providers: [
          ChangeNotifierProvider<RecurringBillsProvider>.value(value: bills),
          ChangeNotifierProvider<TransactionProvider>.value(value: TransactionProvider()),
          ChangeNotifierProvider<BudgetProvider>.value(value: BudgetProvider()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CardErrorState), findsOneWidget);
      expect(find.text("Couldn't load your recurring bills. Check your connection."), findsOneWidget);
      expect(find.text('Configure'), findsNothing, reason: 'the set-up state is for a household without bills');

      fake.failing = false;
      await tester.tap(find.byKey(const Key('card_error_retry')));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsNothing);
      expect(find.text('Saudi Electricity Co.'), findsOneWidget);
    });

    testWidgets('installments: error with retry, never "all installments cleared"', (tester) async {
      final fake = _FakeBudgetApi();
      final plans = InstallmentProvider(api: ApiService(budget: fake));
      await tester.pumpWidget(_app(
        InstallmentPlansCard(householdId: 'hh', now: DateTime.utc(2026, 10, 21, 9)),
        providers: [
          ChangeNotifierProvider<InstallmentProvider>.value(value: plans),
          ChangeNotifierProvider<TransactionProvider>.value(value: TransactionProvider()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CardErrorState), findsOneWidget);
      expect(find.text("Couldn't load your installments. Check your connection."), findsOneWidget);
      expect(find.text('All installments cleared'), findsNothing);
      expect(find.text('No Active BNPL Installments'), findsNothing);

      fake
        ..failing = false
        ..plans = [_plan()];
      await tester.tap(find.byKey(const Key('card_error_retry')));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsNothing);
      expect(find.text('eXtra'), findsOneWidget);
    });

    testWidgets('UX-25: no plans reads "No installments"; all paid reads "all cleared"', (tester) async {
      await tester.pumpWidget(_app(const InstallmentPlansCard(plans: [])));
      await tester.pumpAndSettle();
      expect(find.text('No installments'), findsOneWidget);
      expect(find.text('All installments cleared'), findsNothing);

      await tester.pumpWidget(_app(InstallmentPlansCard(plans: [_plan(status: 'COMPLETED', paid: 4)])));
      await tester.pumpAndSettle();
      expect(find.text('All installments cleared'), findsOneWidget);
    });

    testWidgets('Nafaqah card: a failed load shows the card title, the error and a retry', (tester) async {
      var fail = true;
      NafaqahSummary? reported;
      Future<NafaqahSummary> loader(String hid) async {
        if (fail) throw const NafaqahApiException('network', 'down');
        return NafaqahSummary.fromMap({
          'mode': 'family_nafaqah',
          'caller_role': 'husband',
          'caller_user_id': 'u-h',
          'cycle_key': '2026-11',
          'wives': [
            {
              'id': 'u-w',
              'display_name': 'Sara',
              'reimbursement': {'gross_advanced': 686.4, 'reimbursed': 300, 'outstanding': 386.4},
              'allowance': {'is_set': true, 'allocated': 1000, 'spent': 645, 'remaining': 355},
            }
          ],
        });
      }

      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        loadSummary: loader,
        onSummaryLoaded: (s) => reported = s,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsOneWidget);
      expect(find.text('Family Expenses & Wife Reimbursements'), findsOneWidget);
      expect(find.text("Couldn't load what is owed to the wife. Check your connection."), findsOneWidget);
      expect(reported, isNull);

      fail = false;
      await tester.tap(find.byKey(const Key('card_error_retry')));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsNothing);
      expect(find.text('SAR 386.40'), findsOneWidget);
      expect(reported?.wives.single.reimbursement.outstanding, 386.4);
    });

    testWidgets('balances: a failed settlement load is an error card, not a silent family card', (tester) async {
      var fail = true;
      Future<SettlementV2Summary> loadSettlement(String hid) async {
        if (fail) throw const ApiRequestException('down');
        return const SettlementV2Summary(mode: 'multi_roommate');
      }

      await tester.pumpWidget(_app(HouseholdBalancesSection(
        householdId: 'hh',
        loadSettlement: loadSettlement,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsOneWidget);
      expect(find.text("Couldn't load household balances. Check your connection."), findsOneWidget);
      expect(find.byType(FamilyReimbursementCard), findsNothing);

      fail = false;
      await tester.tap(find.byKey(const Key('card_error_retry')));
      await tester.pumpAndSettle();
      expect(find.byType(CardErrorState), findsNothing);
      expect(find.text('All Settled'), findsWidgets);
    });

    testWidgets('error state shows the last update time when stale data exists', (tester) async {
      await tester.pumpWidget(_app(CardErrorBanner(
        lastUpdated: DateTime(2026, 10, 21, 21, 40),
        onRetry: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't refresh"), findsOneWidget);
      expect(find.textContaining('9:40 PM'), findsOneWidget);
    });
  });
}
