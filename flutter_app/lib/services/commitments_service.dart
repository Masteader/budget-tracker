import '../models/installment_plan.dart';
import '../models/operating_cash.dart';
import '../models/recurring_bill.dart';
import 'api_service.dart';
import 'salary_cycle_service.dart';

abstract interface class InstallmentSource {
  Future<List<InstallmentPlan>> getInstallments(String householdId);
}

abstract interface class RecurringBillSource {
  Future<RecurringBillsSummary> getRecurringBills(String householdId);
}

class ApiInstallmentSource implements InstallmentSource {
  final ApiService _api;
  ApiInstallmentSource([ApiService? api]) : _api = api ?? ApiService.instance;

  @override
  Future<List<InstallmentPlan>> getInstallments(String householdId) =>
      _api.getInstallments(householdId);
}

class ApiRecurringBillSource implements RecurringBillSource {
  final ApiService _api;
  ApiRecurringBillSource([ApiService? api]) : _api = api ?? ApiService.instance;

  @override
  Future<RecurringBillsSummary> getRecurringBills(String householdId) =>
      _api.getRecurringBills(householdId);
}

/// Service that aggregates recurring bills and installment obligations into
/// standardized [PendingCommitment] models stamped with their salary cycle key.
class CommitmentsService {
  final InstallmentSource _installments;
  final RecurringBillSource _bills;

  CommitmentsService({InstallmentSource? installments, RecurringBillSource? bills})
      : _installments = installments ?? ApiInstallmentSource(),
        _bills = bills ?? ApiRecurringBillSource();

  static final instance = CommitmentsService();

  /// Computes the salary cycle key (YYYY-MM) for a given calendar due date and household payday.
  static String cycleKeyForDueDate(DateTime dueDate, int paydayDay) {
    return SalaryCycleService.cycleForDate(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      paydayDay: paydayDay,
    ).key;
  }

  /// Aggregates active installments and recurring bills for [householdId] into
  /// a list of [PendingCommitment] items stamped with their cycle key.
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async {
    final results = await Future.wait([
      _bills.getRecurringBills(householdId),
      _installments.getInstallments(householdId),
    ]);

    final billsSummary = results[0] as RecurringBillsSummary;
    final installmentPlans = results[1] as List<InstallmentPlan>;

    final commitments = <PendingCommitment>[];

    // 1. Process recurring bills
    final billCycleKey = billsSummary.cycleKey.isNotEmpty ? billsSummary.cycleKey : cycleKey;
    for (final bill in billsSummary.bills) {
      commitments.add(PendingCommitment(
        id: 'bill_${bill.normalizedMerchant}_$billCycleKey',
        kind: CommitmentKind.recurringBill,
        amountHalalas: OperatingCashCalculator.toHalalas(bill.averageAmount),
        cycleKey: billCycleKey,
        isPaid: bill.isPaid,
      ));
    }

    // 2. Process active installment plans
    final t = today ?? SalaryCycleService.riyadhToday();

    for (final plan in installmentPlans) {
      if (plan.isCompleted || plan.status != 'ACTIVE') continue;

      if (plan.nextDueAt != null) {
        var dueKey = cycleKeyForDueDate(plan.nextDueAt!, paydayDay);
        // Overdue unpaid installments from an earlier cycle are rolled forward into
        // the current cycle so they are not dropped from pending commitments.
        if (dueKey.compareTo(cycleKey) < 0) {
          dueKey = cycleKey;
        }
        commitments.add(PendingCommitment(
          id: '${plan.id}_${plan.nextDueAt!.toIso8601String()}',
          kind: CommitmentKind.installment,
          amountHalalas: OperatingCashCalculator.toHalalas(plan.monthlyAmount),
          cycleKey: dueKey,
          isPaid: false,
        ));
      } else {
        // Generate upcoming due dates
        final dueDates = plan.dueDates(today: t, max: 6).where((d) => !d.isBefore(t));
        for (final due in dueDates) {
          final dueKey = cycleKeyForDueDate(due, paydayDay);
          commitments.add(PendingCommitment(
            id: '${plan.id}_${due.toIso8601String()}',
            kind: CommitmentKind.installment,
            amountHalalas: OperatingCashCalculator.toHalalas(plan.monthlyAmount),
            cycleKey: dueKey,
            isPaid: false,
          ));
        }
      }
    }

    return commitments;
  }
}

