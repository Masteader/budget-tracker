// An expense in a category without an active budget row for its cycle (an
// inactive or unbudgeted category) counts in totals but in no budget (owner
// decision 2026-11-05): the feed marks it "Unbudgeted" and the hero shows the
// cycle's unbudgeted spending, with the budgets' own exclusions.
import 'package:budget_tracker/models/budget_coverage.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(String id, String? code, double amount,
        {String? cycle = '2026-11', String? cls, bool settlement = false, DateTime? at}) =>
    Transaction.fromMap({
      'id': id,
      'household_id': 'h1',
      'amount': amount,
      'currency': 'SAR',
      'merchant': 'M $id',
      'category_code': code,
      'timestamp': (at ?? DateTime.utc(2026, 11, 3, 9)).toIso8601String(),
      'created_at': (at ?? DateTime.utc(2026, 11, 3, 9)).toIso8601String(),
      'cycle_key': cycle,
      'nafaqah_class': cls,
      'is_settlement': settlement,
    });

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this._rows);
  final List<Transaction> _rows;
  @override
  List<Transaction> get transactions => _rows;
  @override
  bool get isLoading => false;
}

void main() {
  final coverage = BudgetCoverage.fromRows([
    {'category_code': 'OPEX-GROCERY', 'cycle_key': '2026-11', 'month': '2026-11-01', 'is_active': true},
    {'category_code': 'OPEX-FUEL', 'cycle_key': '2026-11', 'month': '2026-11-01', 'is_active': null},
    {'category_code': 'OPEX-HOUSING', 'cycle_key': '2026-11', 'month': '2026-11-01', 'is_active': false},
    {'category_code': 'OPEX-DINING', 'cycle_key': '2026-10', 'month': '2026-10-01', 'is_active': true},
    {'category_code': 'OPEX-HEALTH', 'cycle_key': null, 'month': '2026-11-01', 'is_active': true},
  ]);

  group('BudgetCoverage', () {
    test('an active row (NULL is active, as Budget.fromMap reads it) covers its category and cycle', () {
      expect(coverage.covers('OPEX-GROCERY', '2026-11'), isTrue);
      expect(coverage.covers('OPEX-FUEL', '2026-11'), isTrue);
      expect(coverage.covers('OPEX-HEALTH', '2026-11'), isTrue, reason: 'legacy row: cycle from its month');
    });

    test('an inactive row, another cycle or no row covers nothing', () {
      expect(coverage.covers('OPEX-HOUSING', '2026-11'), isFalse);
      expect(coverage.covers('OPEX-DINING', '2026-11'), isFalse);
      expect(coverage.covers('OPEX-CHARITY', '2026-11'), isFalse);
    });

    test('isUnbudgeted: inactive or unbudgeted categories only, never wife_personal or settlements', () {
      expect(coverage.isUnbudgeted(_tx('a', 'OPEX-HOUSING', 2500)), isTrue);
      expect(coverage.isUnbudgeted(_tx('b', 'OPEX-CHARITY', 100)), isTrue);
      expect(coverage.isUnbudgeted(_tx('c', 'OPEX-DINING', 40)), isTrue, reason: 'budgeted last cycle only');
      expect(coverage.isUnbudgeted(_tx('d', 'OPEX-GROCERY', 120)), isFalse);
      expect(coverage.isUnbudgeted(_tx('e', 'OPEX-HOUSING', 90, cls: 'wife_personal')), isFalse,
          reason: 'charged to her allowance, never a category budget');
      expect(coverage.isUnbudgeted(_tx('f', 'OPEX-HOUSING', 90, settlement: true)), isFalse);
      expect(coverage.isUnbudgeted(_tx('g', 'OPEX-HOUSING', 90, cls: 'wife_reimbursable')), isTrue);
      expect(coverage.isUnbudgeted(_tx('h', 'OPEX-HOUSING', 90, cycle: null)), isFalse,
          reason: 'no cycle yet (offline draft): unknown, so not marked');
    });

    test('empty coverage marks nothing until loaded', () {
      expect(BudgetCoverage.unknown.isUnbudgeted(_tx('a', 'OPEX-HOUSING', 2500)), isFalse);
    });
  });

  group('TransactionProvider.unbudgetedCycleSpend', () {
    test('the cycle spending outside the budgeted categories, with the budgets\' exclusions', () {
      final tx = _FakeTransactions([
        _tx('a', 'OPEX-HOUSING', 2500),
        _tx('b', 'OPEX-CHARITY', 100),
        _tx('c', 'OPEX-GROCERY', 120),
        _tx('d', 'OPEX-HOUSING', 90, cls: 'wife_personal'),
        _tx('e', 'OPEX-HOUSING', 70, settlement: true),
        _tx('f', 'OPEX-HOUSING', 60, cls: 'wife_reimbursable'),
        _tx('g', 'OPEX-HOUSING', 1000, cycle: '2026-10'),
        _tx('h', null, 15),
      ]);
      expect(tx.unbudgetedCycleSpend('2026-11', {'OPEX-GROCERY'}, paydayDay: 27), 2675);
      // Everything that is not budgeted plus the budgeted spend is the cycle total.
      expect(
        tx.unbudgetedCycleSpend('2026-11', {'OPEX-GROCERY'}, paydayDay: 27) +
            tx.cycleSpendForCategory('OPEX-GROCERY', '2026-11', paydayDay: 27),
        tx.totalCycleSpend('2026-11', paydayDay: 27),
      );
      expect(tx.unbudgetedCycleSpend('2026-11', {'OPEX-GROCERY', 'OPEX-HOUSING', 'OPEX-CHARITY'}, paydayDay: 27), 15);
    });

    test('a row without a cycle key falls in the cycle of its date', () {
      final tx = _FakeTransactions([_tx('a', 'OPEX-HOUSING', 2500, cycle: null, at: DateTime.utc(2026, 11, 3, 9))]);
      expect(tx.unbudgetedCycleSpend('2026-11', const {}, paydayDay: 27), 2500);
      expect(tx.unbudgetedCycleSpend('2026-10', const {}, paydayDay: 27), 0);
    });
  });
}
