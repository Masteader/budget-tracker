import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/installment_plan.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/models/recurring_bill.dart';
import 'package:budget_tracker/services/commitments_service.dart';

class FakeInstallmentSource implements InstallmentSource {
  final List<InstallmentPlan> plans;
  FakeInstallmentSource(this.plans);

  @override
  Future<List<InstallmentPlan>> getInstallments(String householdId) async => plans;
}

class FakeRecurringBillSource implements RecurringBillSource {
  final RecurringBillsSummary summary;
  FakeRecurringBillSource(this.summary);

  @override
  Future<RecurringBillsSummary> getRecurringBills(String householdId) async => summary;
}

void main() {
  group('CommitmentsService Tests', () {
    test('Case 1: payday 27, due 27 Oct 2026, gives 2026-11', () {
      final key = CommitmentsService.cycleKeyForDueDate(DateTime.utc(2026, 10, 27), 27);
      expect(key, equals('2026-11'));
    });

    test('Case 2: payday 10, due 10 Oct 2026, gives 2026-10', () {
      final key = CommitmentsService.cycleKeyForDueDate(DateTime.utc(2026, 10, 10), 10);
      expect(key, equals('2026-10'));
    });

    test('Case 3: payday 31 in February clamps to the 28th', () {
      // Non-leap year 2026 February ends on 28th
      final key28 = CommitmentsService.cycleKeyForDueDate(DateTime.utc(2026, 2, 28), 31);
      expect(key28, equals('2026-03'));

      final key27 = CommitmentsService.cycleKeyForDueDate(DateTime.utc(2026, 2, 27), 31);
      expect(key27, equals('2026-02'));
    });

    test('getPendingCommitments aggregates installments and recurring bills correctly', () async {
      const billsSummary = RecurringBillsSummary(
        cycleKey: '2026-11',
        cycleLabel: 'November 2026',
        totalRecurringMonthly: 750.0,
        paidThisCycle: 400.0,
        reservedAmount: 350.0,
        bills: [
          RecurringBillItem(
            merchant: 'STC Telecom',
            normalizedMerchant: 'STC',
            categoryCode: 'OPEX-UTILITIES',
            averageAmount: 400.0,
            expectedDayOfMonth: 28,
            status: 'PAID_THIS_CYCLE',
          ),
          RecurringBillItem(
            merchant: 'Saudi Electricity',
            normalizedMerchant: 'SEC',
            categoryCode: 'OPEX-UTILITIES',
            averageAmount: 350.0,
            expectedDayOfMonth: 5,
            status: 'UPCOMING',
          ),
        ],
      );

      final installmentPlans = [
        InstallmentPlan(
          id: 'inst-active-current',
          householdId: 'hh-1',
          merchant: 'Jarir Bookstore',
          provider: 'Tamara',
          totalAmount: 2000.0,
          installmentCount: 4,
          monthlyAmount: 500.0,
          paidInstallments: 1,
          dayOfMonth: 28,
          startDate: '2026-10-01',
          status: 'ACTIVE',
          nextDueAt: DateTime.utc(2026, 10, 28), // Cycle 2026-11 with payday 27
        ),
        InstallmentPlan(
          id: 'inst-active-next',
          householdId: 'hh-1',
          merchant: 'eXtra',
          provider: 'Tabby',
          totalAmount: 1200.0,
          installmentCount: 4,
          monthlyAmount: 300.0,
          paidInstallments: 1,
          dayOfMonth: 28,
          startDate: '2026-10-01',
          status: 'ACTIVE',
          nextDueAt: DateTime.utc(2026, 11, 28), // Cycle 2026-12 with payday 27
        ),
        InstallmentPlan(
          id: 'inst-completed',
          householdId: 'hh-1',
          merchant: 'Amazon',
          provider: 'Tamara',
          totalAmount: 1000.0,
          installmentCount: 4,
          monthlyAmount: 250.0,
          paidInstallments: 4,
          dayOfMonth: 15,
          startDate: '2026-06-01',
          status: 'COMPLETED',
        ),
      ];

      final service = CommitmentsService(
        installments: FakeInstallmentSource(installmentPlans),
        bills: FakeRecurringBillSource(billsSummary),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      // We expect:
      // 1. STC (recurring bill, paid, 400.00 SAR = 40000 halalas)
      // 2. SEC (recurring bill, unpaid, 350.00 SAR = 35000 halalas)
      // 3. Jarir (installment, unpaid, 500.00 SAR = 50000 halalas, cycle 2026-11)
      // 4. eXtra (installment, cycle 2026-12)
      // inst-completed is skipped.

      expect(commitments.length, equals(4));

      final stc = commitments.firstWhere((c) => c.id.contains('STC'));
      expect(stc.kind, equals(CommitmentKind.recurringBill));
      expect(stc.amountHalalas, equals(40000));
      expect(stc.isPaid, isTrue);
      expect(stc.cycleKey, equals('2026-11'));

      final sec = commitments.firstWhere((c) => c.id.contains('SEC'));
      expect(sec.kind, equals(CommitmentKind.recurringBill));
      expect(sec.amountHalalas, equals(35000));
      expect(sec.isPaid, isFalse);
      expect(sec.cycleKey, equals('2026-11'));

      final jarir = commitments.firstWhere((c) => c.id.contains('inst-active-current'));
      expect(jarir.kind, equals(CommitmentKind.installment));
      expect(jarir.amountHalalas, equals(50000));
      expect(jarir.isPaid, isFalse);
      expect(jarir.cycleKey, equals('2026-11'));

      final extra = commitments.firstWhere((c) => c.id.contains('inst-active-next'));
      expect(extra.kind, equals(CommitmentKind.installment));
      expect(extra.amountHalalas, equals(30000));
      expect(extra.isPaid, isFalse);
      expect(extra.cycleKey, equals('2026-12'));
    });

    test('active plan with nextDueAt null filters out earlier paid dates in the cycle', () async {
      final plan = InstallmentPlan(
        id: 'inst-paid-earlier',
        householdId: 'hh-1',
        merchant: 'Noon',
        provider: 'Tabby',
        totalAmount: 1200.0,
        installmentCount: 4,
        monthlyAmount: 300.0,
        paidInstallments: 1,
        dayOfMonth: 1,
        startDate: '2026-10-01',
        status: 'ACTIVE',
        nextDueAt: null, // computes from dayOfMonth
      );

      const emptyBills = RecurringBillsSummary(
        cycleKey: '2026-11',
        cycleLabel: 'November 2026',
        totalRecurringMonthly: 0.0,
        paidThisCycle: 0.0,
        reservedAmount: 0.0,
        bills: [],
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      // Today is 2026-11-06; the 2026-11-01 installment is already in the past
      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
        today: DateTime.utc(2026, 11, 6),
      );

      // Verify no commitment with 2026-11-01 exists
      final hasPastDue = commitments.any((c) => c.id.contains('2026-11-01'));
      expect(hasPastDue, isFalse);
    });
  });
}

