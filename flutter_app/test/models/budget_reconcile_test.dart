import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/budget_reconcile.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this._rows);
  final List<Transaction> _rows;
  @override
  List<Transaction> get transactions => _rows;
  @override
  bool get isLoading => false;
}

void main() {
  group('reconcileCycleBudgets Tests', () {
    const cycleKey = '2026-01-27_2026-02-26';
    final now = DateTime(2026, 2, 1);

    test('a wife_personal 300 tx in OPEX-SHOPPING does not raise shopping spent', () {
      final rawBudgets = <Budget>[
        const Budget(
          id: 'b-1',
          householdId: 'h1',
          categoryCode: 'OPEX-SHOPPING',
          allocatedAmount: 1000.0,
          spentAmount: 0.0,
          remainingAmount: 1000.0,
          month: '2026-02-01',
          cycleKey: cycleKey,
          isActive: true,
        ),
      ];

      final txList = [
        Transaction.fromMap({
          'id': 'tx-1',
          'household_id': 'h1',
          'amount': 100.0,
          'currency': 'SAR',
          'merchant': 'Zara',
          'category_code': 'OPEX-SHOPPING',
          'timestamp': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'spent_by': 'me',
          'cycle_key': cycleKey,
        }),
        Transaction.fromMap({
          'id': 'tx-2',
          'household_id': 'h1',
          'amount': 300.0,
          'currency': 'SAR',
          'merchant': 'Boutique',
          'category_code': 'OPEX-SHOPPING',
          'timestamp': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'spent_by': 'partner',
          'nafaqah_class': 'wife_personal',
          'cycle_key': cycleKey,
        }),
      ];

      final fakeTx = _FakeTransactions(txList);
      final reconciled = reconcileCycleBudgets(rawBudgets, fakeTx, cycleKey, null, null);

      expect(reconciled.length, equals(1));
      expect(reconciled.first.spentAmount, equals(100.0));
      expect(reconciled.first.remainingAmount, equals(900.0));
    });

    test('both screens produce identical spent for the same fixture', () {
      final rawBudgets = <Budget>[
        const Budget(
          id: 'b-1',
          householdId: 'h1',
          categoryCode: 'OPEX-GROCERY',
          allocatedAmount: 2000.0,
          spentAmount: 0.0,
          remainingAmount: 2000.0,
          month: '2026-02-01',
          cycleKey: cycleKey,
          isActive: true,
        ),
        const Budget(
          id: 'b-2',
          householdId: 'h1',
          categoryCode: 'OPEX-SHOPPING',
          allocatedAmount: 1000.0,
          spentAmount: 0.0,
          remainingAmount: 1000.0,
          month: '2026-02-01',
          cycleKey: cycleKey,
          isActive: true,
        ),
      ];

      final txList = [
        Transaction.fromMap({
          'id': 'tx-1',
          'household_id': 'h1',
          'amount': 500.0,
          'currency': 'SAR',
          'merchant': 'Tamimi',
          'category_code': 'OPEX-GROCERY',
          'timestamp': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'spent_by': 'me',
          'cycle_key': cycleKey,
        }),
        Transaction.fromMap({
          'id': 'tx-2',
          'household_id': 'h1',
          'amount': 200.0,
          'currency': 'SAR',
          'merchant': 'Mall',
          'category_code': 'OPEX-SHOPPING',
          'timestamp': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'spent_by': 'me',
          'cycle_key': cycleKey,
        }),
        Transaction.fromMap({
          'id': 'tx-3',
          'household_id': 'h1',
          'amount': 150.0,
          'currency': 'SAR',
          'merchant': 'Salon',
          'category_code': 'OPEX-SHOPPING',
          'timestamp': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'spent_by': 'partner',
          'nafaqah_class': 'wife_personal',
          'cycle_key': cycleKey,
        }),
      ];

      final fakeTx = _FakeTransactions(txList);
      final screen1Result = reconcileCycleBudgets(rawBudgets, fakeTx, cycleKey, null, null);
      final screen2Result = reconcileCycleBudgets(rawBudgets, fakeTx, cycleKey, null, null);

      expect(screen1Result.map((b) => b.spentAmount).toList(), equals([500.0, 200.0]));
      expect(screen2Result.map((b) => b.spentAmount).toList(), equals([500.0, 200.0]));
      expect(screen1Result.map((b) => b.spentAmount).toList(), equals(screen2Result.map((b) => b.spentAmount).toList()));
    });
  });
}
