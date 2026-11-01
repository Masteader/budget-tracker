import 'package:flutter/foundation.dart';
import 'account.dart';

enum CommitmentKind { recurringBill, installment }

@immutable
class PendingCommitment {
  final String id;
  final CommitmentKind kind;
  final int amountHalalas;
  final String cycleKey; // YYYY-MM
  final bool isPaid;

  const PendingCommitment({
    required this.id,
    required this.kind,
    required this.amountHalalas,
    required this.cycleKey,
    required this.isPaid,
  });

  double get amount => amountHalalas / 100.0;
}

@immutable
class OperatingCashSnapshot {
  final String householdId;
  final String cycleKey;
  final int liquidHalalas;
  final int pendingCommitmentsHalalas;
  final int cycleIncomeHalalas;
  final int accountsCount;

  const OperatingCashSnapshot({
    required this.householdId,
    required this.cycleKey,
    required this.liquidHalalas,
    required this.pendingCommitmentsHalalas,
    required this.cycleIncomeHalalas,
    required this.accountsCount,
  });

  static const empty = OperatingCashSnapshot(
    householdId: '',
    cycleKey: '',
    liquidHalalas: 0,
    pendingCommitmentsHalalas: 0,
    cycleIncomeHalalas: 0,
    accountsCount: 0,
  );

  /// Liquid operating cash minus pending commitments:
  int get operatingCashHalalas => liquidHalalas - pendingCommitmentsHalalas;

  /// SAR representations:
  double get operatingCash => operatingCashHalalas / 100.0;
  double get liquidBalance => liquidHalalas / 100.0;
  double get pendingCommitments => pendingCommitmentsHalalas / 100.0;
  double get cycleIncome => cycleIncomeHalalas / 100.0;

  bool get isDeficit => operatingCashHalalas < 0;
}

class OperatingCashCalculator {
  /// Converts floating SAR amount into exact integer halalas.
  static int toHalalas(num val) => (val * 100).round();

  static OperatingCashSnapshot compute({
    required String householdId,
    required String cycleKey,
    required List<Account> accounts,
    required List<PendingCommitment> commitments,
    required int cycleIncomeHalalas,
  }) {
    // Rule: non-archived operating accounts only
    final operatingAccounts = accounts.where((a) => !a.isArchived && a.accountType.isOperatingPool).toList();

    int totalLiquidHalalas = 0;
    for (final acc in operatingAccounts) {
      if (acc.balance > 0) {
        totalLiquidHalalas += toHalalas(acc.balance);
      }
    }

    // Rule: unpaid commitments in the active cycle only
    int totalCommitmentsHalalas = 0;
    for (final c in commitments) {
      if (!c.isPaid && c.cycleKey == cycleKey) {
        totalCommitmentsHalalas += c.amountHalalas;
      }
    }

    return OperatingCashSnapshot(
      householdId: householdId,
      cycleKey: cycleKey,
      liquidHalalas: totalLiquidHalalas,
      pendingCommitmentsHalalas: totalCommitmentsHalalas,
      cycleIncomeHalalas: cycleIncomeHalalas,
      accountsCount: operatingAccounts.length,
    );
  }
}

