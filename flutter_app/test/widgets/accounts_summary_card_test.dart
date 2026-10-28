import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/widgets/dashboard/accounts_summary_card.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/recurring_bill.dart';

class FakeAccountService extends AccountService {
  final StreamController<List<Account>> _controller = StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> streamAccounts(String householdId) => _controller.stream;

  @override
  Future<List<Account>> getAccounts(String householdId) async => [];

  void emit(List<Account> accounts) {
    _controller.add(accounts);
  }

  void close() {
    _controller.close();
  }
}

void main() {
  group('AccountsSummaryCard Widget Tests', () {
    late FakeAccountService fakeService;

    setUp(() {
      fakeService = FakeAccountService();
      AccountService.instance = fakeService;
    });

    tearDown(() {
      fakeService.close();
      AccountService.instance = AccountService();
    });

    testWidgets('Initializes with subscription, renders data on emit, and disposes cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(
            body: AccountsSummaryCard(householdId: 'test-household-id'),
          ),
        ),
      );
      await tester.pump();

      // Initially empty accounts list returns SizedBox.shrink()
      expect(find.byType(AccountsSummaryCard), findsOneWidget);
      expect(find.text('Accounts & Liquidity'), findsNothing);

      // Emit account data from the stream
      fakeService.emit([
        const Account(
          id: 'acc-1',
          householdId: 'test-household-id',
          ownerUserId: 'u-1',
          name: 'Al Rajhi Main',
          accountType: AccountType.bank,
          balance: 15400.0,
        ),
      ]);
      await tester.pump();

      // Card is now rendered with total liquidity
      expect(find.text('Accounts & Balances'), findsOneWidget);
      // Shown twice: the total-liquidity headline (one Text.rich so the
      // unit can sit on the locale-appropriate side) and the account pill.
      expect(find.text('SAR 15,400.00'), findsNWidgets(2));
      expect(find.text('Al Rajhi Main'), findsOneWidget);

      // Verify clean unmount / cancellation of StreamSubscription without throwing
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
      expect(find.byType(AccountsSummaryCard), findsNothing);
    });

    testWidgets('minAccounts hides the card on the dashboard until there are two accounts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(body: AccountsSummaryCard(householdId: 'h', minAccounts: 2)),
        ),
      );
      await tester.pump();
      const one = Account(id: 'a1', householdId: 'h', ownerUserId: 'u', name: 'Cash', accountType: AccountType.cash, balance: 100);
      const two = Account(id: 'a2', householdId: 'h', ownerUserId: 'u', name: 'STC Pay', accountType: AccountType.eWallet, balance: 50);
      fakeService.emit([one]);
      await tester.pump();
      expect(find.text('Accounts & Balances'), findsNothing);
      fakeService.emit([one, two]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Accounts & Balances'), findsOneWidget);
    });

    testWidgets('renders tip with actual balance deducted when unpaid bills and active installments exist, and triggers onCommitmentsTap', (tester) async {
      bool commitmentsTapped = false;
      const bills = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: '',
        totalRecurringMonthly: 2000.0,
        paidThisCycle: 500.0,
        reservedAmount: 1500.0,
        bills: [
          RecurringBillItem(
            merchant: 'STC',
            normalizedMerchant: 'stc',
            categoryCode: 'OPEX-BILLS',
            averageAmount: 500.0,
            expectedDayOfMonth: 10,
            status: 'PAID_THIS_CYCLE',
          ),
          RecurringBillItem(
            merchant: 'SEC Electric',
            normalizedMerchant: 'sec',
            categoryCode: 'OPEX-BILLS',
            averageAmount: 1500.0,
            expectedDayOfMonth: 28,
            status: 'UPCOMING',
          ),
        ],
      );
      final installments = [
        InstallmentPlan(
          id: 'p1',
          householdId: 'h',
          merchant: 'Jarir Bookstore',
          totalAmount: 4000.0,
          monthlyAmount: 1000.0,
          startDate: '2026-09-01',
          status: 'ACTIVE',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: AccountsSummaryCard(
              householdId: 'h',
              billsSummaryOverride: bills,
              installmentPlansOverride: installments,
              onCommitmentsTap: () => commitmentsTapped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      fakeService.emit([
        const Account(
          id: 'a1',
          householdId: 'h',
          ownerUserId: 'u',
          name: 'Al Rajhi',
          accountType: AccountType.bank,
          balance: 10000.0,
        ),
      ]);
      await tester.pump();

      // Total commitments = 1500 (unpaid bill) + 1000 (installment) = 2500
      // Actual available = 10000 - 2500 = 7500
      expect(find.byKey(const Key('accounts_commitments_tip')), findsOneWidget);
      expect(find.textContaining('7,500.00'), findsOneWidget);
      expect(find.textContaining('2,500.00'), findsOneWidget);

      // Tap commitments tip
      await tester.tap(find.byKey(const Key('accounts_commitments_tip')));
      expect(commitmentsTapped, isTrue);
    });

    testWidgets('renders deficit alert when commitments exceed total liquidity', (tester) async {
      const bills = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: '',
        totalRecurringMonthly: 3000.0,
        paidThisCycle: 0.0,
        reservedAmount: 3000.0,
        bills: [
          RecurringBillItem(
            merchant: 'Rent',
            normalizedMerchant: 'rent',
            categoryCode: 'OPEX-HOUSING',
            averageAmount: 3000.0,
            expectedDayOfMonth: 1,
            status: 'UPCOMING',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(
            body: AccountsSummaryCard(
              householdId: 'h',
              billsSummaryOverride: bills,
              installmentPlansOverride: [],
            ),
          ),
        ),
      );
      await tester.pump();

      fakeService.emit([
        const Account(
          id: 'a1',
          householdId: 'h',
          ownerUserId: 'u',
          name: 'Cash',
          accountType: AccountType.cash,
          balance: 1000.0,
        ),
      ]);
      await tester.pump();

      // Total commitments = 3000, Available = 1000, Deficit = 2000
      expect(find.byKey(const Key('accounts_commitments_tip')), findsOneWidget);
      expect(find.textContaining('Deficit'), findsOneWidget);
      expect(find.textContaining('2,000.00'), findsOneWidget);
    });

    testWidgets('renders clean no-commitments state when no bills or installments are pending', (tester) async {
      const bills = RecurringBillsSummary(
        cycleKey: '2026-10',
        cycleLabel: '',
        totalRecurringMonthly: 500.0,
        paidThisCycle: 500.0,
        reservedAmount: 0.0,
        bills: [
          RecurringBillItem(
            merchant: 'Paid Bill',
            normalizedMerchant: 'paid',
            categoryCode: 'OPEX-BILLS',
            averageAmount: 500.0,
            expectedDayOfMonth: 1,
            status: 'PAID_THIS_CYCLE',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(
            body: AccountsSummaryCard(
              householdId: 'h',
              billsSummaryOverride: bills,
              installmentPlansOverride: [],
            ),
          ),
        ),
      );
      await tester.pump();

      fakeService.emit([
        const Account(
          id: 'a1',
          householdId: 'h',
          ownerUserId: 'u',
          name: 'Main Bank',
          accountType: AccountType.bank,
          balance: 8000.0,
        ),
      ]);
      await tester.pump();

      expect(find.byKey(const Key('accounts_no_commitments_tip')), findsOneWidget);
      expect(find.text('No pending commitments: full balance available'), findsOneWidget);
    });
  });
}

