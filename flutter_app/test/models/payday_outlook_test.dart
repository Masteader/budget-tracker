// UX-07: one computation of "left until payday", one daily figure, one verdict.
import 'package:budget_tracker/models/household_dues.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/payday_outlook.dart';
import 'package:flutter_test/flutter_test.dart';

Budget _b(String code, double allocated, double spent) => Budget.fromMap({
      'id': code,
      'household_id': 'hh',
      'month': '2026-11-01',
      'category_code': code,
      'allocated_amount': allocated,
      'spent_amount': spent,
      'remaining_amount': allocated - spent,
      'cycle_key': '2026-11',
    });

// Cycle 27 Oct – 26 Nov 2026 (payday 27).
final _start = DateTime.utc(2026, 10, 27);
final _end = DateTime.utc(2026, 11, 26);

PaydayOutlook _outlook(List<Budget> budgets, DateTime today, {double? income}) => PaydayOutlook.compute(
      budgets: budgets,
      monthlyIncome: income,
      today: today,
      cycleStart: _start,
      cycleEnd: _end,
    );

void main() {
  group('PaydayOutlook', () {
    test('income-based when the income is known: income minus spending', () {
      final o = _outlook([_b('OPEX-DINING', 3000, 2200)], DateTime.utc(2026, 11, 6), income: 12000);
      expect(o.incomeBased, isTrue);
      expect(o.base, 12000);
      expect(o.left, 9800);
      expect(o.daysLeft, 21, reason: '6 Nov to 26 Nov inclusive');
      expect(o.safeDaily, closeTo(9800 / 21, 1e-9));
      expect(o.verdict, PaydayVerdict.onTrack);
    });

    test('budget-based fallback without an income', () {
      final o = _outlook([_b('OPEX-DINING', 3000, 2200)], DateTime.utc(2026, 11, 6));
      expect(o.incomeBased, isFalse);
      expect(o.base, 3000);
      expect(o.left, 800);
    });

    test('a pace that runs out before payday is the one verdict, with the date', () {
      // Day 11; 2,200 spent → 200/day; 800 left lasts 4 days → ~10 Nov.
      final o = _outlook([_b('OPEX-DINING', 3000, 2200)], DateTime.utc(2026, 11, 6));
      expect(o.verdict, PaydayVerdict.runsOut);
      expect(o.runOutDate, DateTime.utc(2026, 11, 10));
    });

    test('spent more than the base: overspent, no daily figure', () {
      final o = _outlook([_b('OPEX-SHOPPING', 1000, 1310)], DateTime.utc(2026, 11, 6));
      expect(o.verdict, PaydayVerdict.overspent);
      expect(o.left, -310);
      expect(o.safeDaily, 0);
    });

    test('unspent rent and bills are kept out of the daily figure', () {
      final o = _outlook(
        [_b('OPEX-UTILITIES', 4000, 0), _b('OPEX-GROCERY', 2000, 500)],
        DateTime.utc(2026, 11, 6),
        income: 10000,
      );
      expect(o.left, 9500);
      // 9,500 left minus the 4,000 still due for bills, over 21 days.
      expect(o.safeDaily, closeTo(5500 / 21, 1e-9));
    });

    test('a closed cycle has no days left and no daily figure', () {
      final o = PaydayOutlook.compute(
        budgets: [_b('OPEX-GROCERY', 2000, 1500)],
        today: DateTime.utc(2026, 12, 5),
        cycleStart: _start,
        cycleEnd: _end,
      );
      expect(o.isClosed, isTrue);
      expect(o.daysLeft, 0);
      expect(o.safeDaily, 0);
      expect(o.verdict, PaydayVerdict.onTrack);
    });

    test('spent share is not clamped', () {
      final o = _outlook([_b('OPEX-SHOPPING', 1000, 1310)], DateTime.utc(2026, 11, 6));
      expect(o.spentShare, closeTo(1.31, 1e-9));
    });

    test('operatingCash grounds live remaining liquidity while income preserves cycle capacity', () {
      final o = PaydayOutlook.compute(
        budgets: [_b('OPEX-GROCERY', 5000, 1000)],
        monthlyIncome: 12000,
        operatingCash: 8500,
        today: DateTime.utc(2026, 11, 6),
        cycleStart: _start,
        cycleEnd: _end,
      );
      expect(o.base, 12000.0);
      expect(o.incomeBased, isTrue);
      expect(o.left, 8500.0);
    });

    test('operatingCash infers cycle capacity when static income is null', () {
      final o = PaydayOutlook.compute(
        budgets: [_b('OPEX-GROCERY', 5000, 1000)],
        operatingCash: 8500,
        today: DateTime.utc(2026, 11, 6),
        cycleStart: _start,
        cycleEnd: _end,
      );
      expect(o.base, 9500.0); // 8500 balance + 1000 spent so far
      expect(o.incomeBased, isTrue);
      expect(o.left, 8500.0);
    });
  });

  group('dues for the hero', () {
    NafaqahSummary family({String role = 'husband', double outstanding = 386.4, String? name = 'Sara'}) =>
        NafaqahSummary.fromMap({
          'mode': 'family_nafaqah',
          'caller_role': role,
          'caller_user_id': role == 'wife' ? 'u-w' : 'u-h',
          'wives': [
            {
              'id': 'u-w',
              'display_name': name,
              'reimbursement': {'outstanding': outstanding},
            }
          ],
        });

    test('the husband sees what he owes his wife, by name', () {
      final lines = nafaqahDueLines(family());
      expect(lines, hasLength(1));
      expect(lines.single.kind, DueKind.owedToWife);
      expect(lines.single.name, 'Sara');
      expect(lines.single.amount, 386.4);
    });

    test('the wife sees what is owed to her', () {
      final lines = nafaqahDueLines(family(role: 'wife'));
      expect(lines.single.kind, DueKind.owedToMe);
    });

    test('nothing owed: no line', () {
      expect(nafaqahDueLines(family(outstanding: 0)), isEmpty);
      expect(nafaqahDueLines(const NafaqahSummary()), isEmpty);
    });
  });
}
