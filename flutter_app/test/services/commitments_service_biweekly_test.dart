import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/installment_plan.dart';
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
  const emptyBills = RecurringBillsSummary(
    cycleKey: '2026-11',
    cycleLabel: 'November 2026',
    totalRecurringMonthly: 0.0,
    paidThisCycle: 0.0,
    reservedAmount: 0.0,
    bills: [],
  );

  group('CommitmentsService Biweekly Installment Tests (HIGH-05)', () {
    test('1: Biweekly, nextDueAt 2026-10-30, 4 remaining -> 2 commitments (10-30, 11-13)', () async {
      final plan = InstallmentPlan(
        id: 'plan-biweekly-1',
        householdId: 'hh-1',
        merchant: 'Tabby Store',
        provider: 'Tabby',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 0,
        startDate: '2026-10-30',
        status: 'ACTIVE',
        frequency: 'biweekly',
        nextDueAt: DateTime.utc(2026, 10, 30),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(2));
      expect(commitments[0].id, equals('plan-biweekly-1_2026-10-30T00:00:00.000Z'));
      expect(commitments[0].amountHalalas, equals(25000));
      expect(commitments[0].cycleKey, equals('2026-11'));

      expect(commitments[1].id, equals('plan-biweekly-1_2026-11-13T00:00:00.000Z'));
      expect(commitments[1].amountHalalas, equals(25000));
      expect(commitments[1].cycleKey, equals('2026-11'));
    });

    test('2: Biweekly, nextDueAt 2026-10-30, 1 remaining -> 1 commitment (capped by remaining)', () async {
      final plan = InstallmentPlan(
        id: 'plan-biweekly-2',
        householdId: 'hh-1',
        merchant: 'Tamara Store',
        provider: 'Tamara',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 3, // 1 remaining
        startDate: '2026-09-18',
        status: 'ACTIVE',
        frequency: 'biweekly',
        nextDueAt: DateTime.utc(2026, 10, 30),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(1));
      expect(commitments[0].id, equals('plan-biweekly-2_2026-10-30T00:00:00.000Z'));
      expect(commitments[0].amountHalalas, equals(25000));
      expect(commitments[0].cycleKey, equals('2026-11'));
    });

    test('3: Biweekly, nextDueAt 2026-10-20 (overdue), 4 remaining -> 3 commitments (10-20, 11-03, 11-17)', () async {
      final plan = InstallmentPlan(
        id: 'plan-biweekly-3',
        householdId: 'hh-1',
        merchant: 'Tabby Store',
        provider: 'Tabby',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 0,
        startDate: '2026-10-20',
        status: 'ACTIVE',
        frequency: 'biweekly',
        nextDueAt: DateTime.utc(2026, 10, 20),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(3));
      expect(commitments[0].id, equals('plan-biweekly-3_2026-10-20T00:00:00.000Z'));
      expect(commitments[0].amountHalalas, equals(25000));
      expect(commitments[0].cycleKey, equals('2026-11')); // rolled forward because overdue

      expect(commitments[1].id, equals('plan-biweekly-3_2026-11-03T00:00:00.000Z'));
      expect(commitments[1].amountHalalas, equals(25000));
      expect(commitments[1].cycleKey, equals('2026-11'));

      expect(commitments[2].id, equals('plan-biweekly-3_2026-11-17T00:00:00.000Z'));
      expect(commitments[2].amountHalalas, equals(25000));
      expect(commitments[2].cycleKey, equals('2026-11'));
    });

    test('4: Monthly plan -> output identical to current behaviour (regression)', () async {
      final plan = InstallmentPlan(
        id: 'plan-monthly-4',
        householdId: 'hh-1',
        merchant: 'eXtra',
        provider: 'Bank',
        totalAmount: 1200.0,
        installmentCount: 4,
        monthlyAmount: 300.0,
        paidInstallments: 1,
        dayOfMonth: 28,
        startDate: '2026-10-01',
        status: 'ACTIVE',
        frequency: 'monthly',
        nextDueAt: DateTime.utc(2026, 11, 28), // In next cycle 2026-12 for payday 27
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(1));
      expect(commitments[0].id, equals('plan-monthly-4_2026-11-28T00:00:00.000Z'));
      expect(commitments[0].amountHalalas, equals(30000));
      expect(commitments[0].cycleKey, equals('2026-12'));
    });

    test('5: Payday 10, cycle 2026-11 (2026-11-10 -> 2026-12-09) -> bounds derived from paydayDay, not 27', () async {
      // Payday 10: cycle 2026-11 runs 2026-11-10 to 2026-12-09.
      // Next due is 2026-11-12.
      // +14d is 2026-11-26 (inside cycle)
      // +14d is 2026-12-10 (outside cycle: > 2026-12-09)
      final plan = InstallmentPlan(
        id: 'plan-biweekly-5',
        householdId: 'hh-1',
        merchant: 'Tabby Store',
        provider: 'Tabby',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 0,
        startDate: '2026-11-12',
        status: 'ACTIVE',
        frequency: 'biweekly',
        nextDueAt: DateTime.utc(2026, 11, 12),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 10,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(2));
      expect(commitments[0].id, equals('plan-biweekly-5_2026-11-12T00:00:00.000Z'));
      expect(commitments[0].cycleKey, equals('2026-11'));
      expect(commitments[1].id, equals('plan-biweekly-5_2026-11-26T00:00:00.000Z'));
      expect(commitments[1].cycleKey, equals('2026-11'));
    });

    test('6: Fully paid plan (0 remaining) -> 0 commitments', () async {
      final plan = InstallmentPlan(
        id: 'plan-completed-6',
        householdId: 'hh-1',
        merchant: 'Tabby Store',
        provider: 'Tabby',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 4, // 0 remaining
        startDate: '2026-08-01',
        status: 'COMPLETED',
        frequency: 'biweekly',
        nextDueAt: DateTime.utc(2026, 10, 30),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments, isEmpty);
    });

    test('7: Frequency string "BiWeekly" (case-insensitive) -> behaves as biweekly', () async {
      final plan = InstallmentPlan(
        id: 'plan-biweekly-7',
        householdId: 'hh-1',
        merchant: 'Tabby Store',
        provider: 'Tabby',
        totalAmount: 1000.0,
        installmentCount: 4,
        monthlyAmount: 250.0,
        paidInstallments: 0,
        startDate: '2026-10-30',
        status: 'ACTIVE',
        frequency: 'BiWeekly',
        nextDueAt: DateTime.utc(2026, 10, 30),
      );

      final service = CommitmentsService(
        installments: FakeInstallmentSource([plan]),
        bills: FakeRecurringBillSource(emptyBills),
      );

      final commitments = await service.getPendingCommitments(
        householdId: 'hh-1',
        paydayDay: 27,
        cycleKey: '2026-11',
      );

      expect(commitments.length, equals(2));
      expect(commitments[0].id, equals('plan-biweekly-7_2026-10-30T00:00:00.000Z'));
      expect(commitments[1].id, equals('plan-biweekly-7_2026-11-13T00:00:00.000Z'));
    });
  });
}
