import 'dart:async';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:budget_tracker/widgets/dashboard/payday_checkin_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Midday in Riyadh on [year]-[month]-[day], whatever the test machine's time
/// zone: the window follows the Asia/Riyadh calendar date.
DateTime _on(int year, int month, int day) => DateTime.utc(year, month, day, 9);

/// Expects the window for [payday] to hold on the [open] dates and not on the
/// [closed] ones; dates are (year, month, day).
void _expectWindow(int? payday, {required List<List<int>> open, required List<List<int>> closed}) {
  for (final d in open) {
    expect(PaydayCheckinBanner.isPaydayWindow(_on(d[0], d[1], d[2]), paydayDay: payday), isTrue,
        reason: 'payday $payday: $d should be inside the window');
  }
  for (final d in closed) {
    expect(PaydayCheckinBanner.isPaydayWindow(_on(d[0], d[1], d[2]), paydayDay: payday), isFalse,
        reason: 'payday $payday: $d should be outside the window');
  }
}

void main() {
  group('PaydayCheckinBanner', () {
    test('queries the real income_records column (source_type)', () {
      // Regression: the banner filtered on a non-existent `income_type`
      // column, so the query always threw and the banner never showed.
      final record = IncomeRecord(
        id: 'r1',
        householdId: 'h1',
        userId: 'u1',
        accountId: 'a1',
        cycleKey: '2026-11',
        sourceType: IncomeSourceType.salary,
        title: 'Salary',
        receivedAt: DateTime(2026, 10, 27),
      );
      expect(record.toMap().containsKey(PaydayCheckinBanner.sourceTypeColumn), isTrue);
      expect(record.toMap()[PaydayCheckinBanner.sourceTypeColumn], 'salary');
    });

    test('payday window covers 27th..31st and 1st..3rd only', () {
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 10, 27)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 10, 31)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 11, 3)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 11, 4)), isFalse);
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 10, 25)), isFalse);
      expect(PaydayCheckinBanner.isPaydayWindow(_on(2026, 11, 26)), isFalse);
    });

    group('household payday window', () {
      test('default 27 is the old 27th-to-3rd rule on every date, in every month', () {
        for (var d = DateTime.utc(2024, 1, 1); d.year < 2029; d = d.add(const Duration(days: 1))) {
          final old = d.day >= 27 || d.day <= 3;
          final instant = d.add(const Duration(hours: 9));
          expect(PaydayCheckinBanner.isPaydayWindow(instant, paydayDay: 27), old, reason: '$d');
          expect(PaydayCheckinBanner.isPaydayWindow(instant), old, reason: 'no payday, $d');
          expect(PaydayCheckinBanner.isPaydayWindow(instant, paydayDay: null), old, reason: 'null payday, $d');
        }
      });

      test('payday 1: the 1st to the 8th', () {
        _expectWindow(1, open: [
          [2026, 11, 1],
          [2026, 11, 8],
        ], closed: [
          [2026, 10, 31],
          [2026, 11, 9],
          [2026, 10, 27],
          [2026, 11, 28],
        ]);
      });

      test('payday 15: the 15th to the 22nd, and no longer prompted around the 27th', () {
        _expectWindow(15, open: [
          [2026, 11, 15],
          [2026, 11, 22],
        ], closed: [
          [2026, 11, 14],
          [2026, 11, 23],
          [2026, 10, 27],
          [2026, 11, 3],
        ]);
      });

      test('payday 28: the 28th to the 4th', () {
        _expectWindow(28, open: [
          [2026, 10, 28],
          [2026, 10, 31],
          [2026, 11, 4],
        ], closed: [
          [2026, 10, 27],
          [2026, 11, 5],
        ]);
      });

      test('payday 30: the 30th to the 6th', () {
        _expectWindow(30, open: [
          [2026, 10, 30],
          [2026, 11, 6],
        ], closed: [
          [2026, 10, 29],
          [2026, 11, 7],
        ]);
      });

      test('payday 31: the 31st to the 7th, opening on the last day of a 30-day month', () {
        _expectWindow(31, open: [
          [2026, 10, 31],
          [2026, 11, 7],
          [2026, 11, 30],
          [2026, 12, 7],
        ], closed: [
          [2026, 10, 30],
          [2026, 11, 8],
          [2026, 11, 29],
          [2026, 12, 8],
        ]);
      });

      test('February, non-leap: a later payday opens on the 28th', () {
        _expectWindow(27, open: [
          [2027, 2, 27],
          [2027, 3, 3],
        ], closed: [
          [2027, 2, 26],
          [2027, 3, 4],
        ]);
        _expectWindow(28, open: [
          [2027, 2, 28],
          [2027, 3, 4],
        ], closed: [
          [2027, 2, 27],
          [2027, 3, 5],
        ]);
        _expectWindow(29, open: [
          [2027, 2, 28],
          [2027, 3, 5],
        ], closed: [
          [2027, 2, 27],
          [2027, 3, 6],
        ]);
        _expectWindow(30, open: [
          [2027, 2, 28],
          [2027, 3, 6],
        ], closed: [
          [2027, 2, 27],
          [2027, 3, 7],
        ]);
        _expectWindow(31, open: [
          [2027, 2, 28],
          [2027, 3, 7],
          [2027, 3, 31],
        ], closed: [
          [2027, 2, 27],
          [2027, 3, 8],
          [2027, 3, 30],
        ]);
      });

      test('February, leap: a later payday opens on the 29th', () {
        _expectWindow(28, open: [
          [2028, 2, 28],
          [2028, 2, 29],
          [2028, 3, 4],
        ], closed: [
          [2028, 2, 27],
          [2028, 3, 5],
        ]);
        _expectWindow(29, open: [
          [2028, 2, 29],
          [2028, 3, 5],
        ], closed: [
          [2028, 2, 28],
          [2028, 3, 6],
        ]);
        _expectWindow(30, open: [
          [2028, 2, 29],
          [2028, 3, 6],
        ], closed: [
          [2028, 2, 28],
          [2028, 3, 7],
        ]);
        _expectWindow(31, open: [
          [2028, 2, 29],
          [2028, 3, 7],
        ], closed: [
          [2028, 2, 28],
          [2028, 3, 8],
        ]);
      });

      test('December into January', () {
        _expectWindow(27, open: [
          [2026, 12, 27],
          [2026, 12, 31],
          [2027, 1, 1],
          [2027, 1, 3],
        ], closed: [
          [2026, 12, 26],
          [2027, 1, 4],
        ]);
        _expectWindow(28, open: [
          [2026, 12, 28],
          [2027, 1, 4],
        ], closed: [
          [2026, 12, 27],
          [2027, 1, 5],
        ]);
        _expectWindow(31, open: [
          [2026, 12, 31],
          [2027, 1, 7],
        ], closed: [
          [2026, 12, 30],
          [2027, 1, 8],
        ]);
        _expectWindow(15, open: [
          [2026, 12, 15],
          [2026, 12, 22],
        ], closed: [
          [2026, 12, 31],
          [2027, 1, 1],
        ]);
      });

      test('a payday out of range is normalised like the salary cycle, without crashing', () {
        _expectWindow(0, open: [
          [2026, 11, 1],
          [2026, 11, 8],
        ], closed: [
          [2026, 11, 9],
        ]);
        _expectWindow(99, open: [
          [2026, 10, 31],
          [2026, 11, 7],
        ], closed: [
          [2026, 11, 8],
        ]);
      });

      test('follows the Riyadh calendar date, whatever the device time zone', () {
        // 21:00 UTC is midnight in Riyadh.
        expect(PaydayCheckinBanner.isPaydayWindow(DateTime.utc(2026, 11, 14, 20, 59), paydayDay: 15), isFalse);
        expect(PaydayCheckinBanner.isPaydayWindow(DateTime.utc(2026, 11, 14, 21), paydayDay: 15), isTrue);
        expect(PaydayCheckinBanner.isPaydayWindow(DateTime.utc(2026, 11, 22, 20, 59), paydayDay: 15), isTrue);
        expect(PaydayCheckinBanner.isPaydayWindow(DateTime.utc(2026, 11, 22, 21), paydayDay: 15), isFalse);
      });

      test('for every payday and cycle it is one unbroken run from the cycle start, 5 to 8 days long', () {
        final sweepStart = DateTime.utc(2024, 1, 1);
        final lastWholeRun = DateTime.utc(2028, 12, 1);
        for (var payday = 1; payday <= 31; payday++) {
          final runs = <DateTime, List<DateTime>>{};
          for (var d = sweepStart; d.year < 2029; d = d.add(const Duration(days: 1))) {
            final cycle = SalaryCycleService.cycleForDate(d.year, d.month, d.day, paydayDay: payday);
            final inWindow = PaydayCheckinBanner.isPaydayWindow(d.add(const Duration(hours: 9)), paydayDay: payday);
            // The window always holds on the salary cycle's own first day.
            if (d == cycle.start) expect(inWindow, isTrue, reason: 'payday $payday: cycle start $d');
            if (inWindow) (runs[cycle.start] ??= []).add(d);
          }
          runs.forEach((start, days) {
            if (start.isBefore(sweepStart) || !start.isBefore(lastWholeRun)) return;
            expect(days.first, start, reason: 'payday $payday');
            expect(days.last.difference(days.first).inDays + 1, days.length, reason: 'payday $payday from $start');
            expect(days.length, inInclusiveRange(5, 8), reason: 'payday $payday from $start');
            if (payday <= 21) expect(days.length, 8, reason: 'payday $payday from $start');
          });
        }
      });
    });

    testWidgets('shows in payday window when no salary was logged', (tester) async {
      DateTime? requestedSince;
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => DateTime(2026, 10, 27, 9),
        salaryLookup: (hid, since) async {
          requestedSince = since;
          return false;
        },
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
      expect(requestedSince, DateTime(2026, 10, 7, 9));
    });

    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}: the Log Salary button reads (S12)', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: PaydayCheckinBanner(
              householdId: 'h1',
              clock: () => DateTime(2026, 10, 27, 9),
              salaryLookup: (hid, since) async => false,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final style = tester.widget<ElevatedButton>(find.byType(ElevatedButton)).style!;
        final bg = style.backgroundColor!.resolve({})!;
        final fg = style.foregroundColor!.resolve({})!;
        double contrast(Color a, Color b) {
          final la = a.computeLuminance();
          final lb = b.computeLuminance();
          return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
        }

        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('stays hidden when a salary was already logged', (tester) async {
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => _on(2026, 10, 27),
        salaryLookup: (_, __) async => true,
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });

    testWidgets('stays hidden outside the payday window without querying', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => _on(2026, 10, 15),
        salaryLookup: (_, __) async {
          called = true;
          return false;
        },
      )));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });

    testWidgets('lookup failure hides the banner without crashing', (tester) async {
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => _on(2026, 10, 27),
        salaryLookup: (_, __) async => throw Exception('column does not exist'),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dismiss button hides the banner', (tester) async {
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => _on(2026, 10, 28),
        salaryLookup: (_, __) async => false,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });

    group('household payday', () {
      final banner = find.byIcon(Icons.celebration_rounded);

      testWidgets('payday 15 prompts on the 15th', (tester) async {
        await tester.pumpWidget(_wrap(PaydayCheckinBanner(
          householdId: 'h1',
          paydayDay: 15,
          clock: () => _on(2026, 11, 15),
          salaryLookup: (_, __) async => false,
        )));
        await tester.pumpAndSettle();

        expect(banner, findsOneWidget);
      });

      testWidgets('payday 15 stays quiet around the 27th without querying', (tester) async {
        var called = false;
        await tester.pumpWidget(_wrap(PaydayCheckinBanner(
          householdId: 'h1',
          paydayDay: 15,
          clock: () => _on(2026, 10, 27),
          salaryLookup: (_, __) async {
            called = true;
            return false;
          },
        )));
        await tester.pumpAndSettle();

        expect(called, isFalse);
        expect(banner, findsNothing);
      });

      testWidgets('a null payday falls back to the default 27', (tester) async {
        await tester.pumpWidget(_wrap(PaydayCheckinBanner(
          householdId: 'h1',
          paydayDay: null,
          clock: () => _on(2026, 10, 27),
          salaryLookup: (_, __) async => false,
        )));
        await tester.pumpAndSettle();

        expect(banner, findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a null fallback ignores the last payday cached by the salary cycle service', (tester) async {
        final cached = SalaryCycleService.paydayDay;
        SalaryCycleService.paydayDay = 15;
        addTearDown(() => SalaryCycleService.paydayDay = cached);

        await tester.pumpWidget(_wrap(PaydayCheckinBanner(
          householdId: 'h1',
          clock: () => _on(2026, 10, 27),
          salaryLookup: (_, __) async => false,
        )));
        await tester.pumpAndSettle();

        expect(banner, findsOneWidget);
      });

      testWidgets('a payday loaded after the banner mounts opens the right window', (tester) async {
        Widget build(int? payday) => _wrap(PaydayCheckinBanner(
              householdId: 'h1',
              paydayDay: payday,
              clock: () => _on(2026, 11, 15),
              salaryLookup: (_, __) async => false,
            ));
        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);

        await tester.pumpWidget(build(15));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);
      });

      testWidgets('a payday loaded after the banner mounts closes the default window', (tester) async {
        Widget build(int? payday) => _wrap(PaydayCheckinBanner(
              householdId: 'h1',
              paydayDay: payday,
              clock: () => _on(2026, 10, 28),
              salaryLookup: (_, __) async => false,
            ));
        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);

        await tester.pumpWidget(build(15));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
      });

      testWidgets('a slow lookup from the old payday cannot reopen a closed window', (tester) async {
        final pending = Completer<bool>();
        Widget build(int? payday) => _wrap(PaydayCheckinBanner(
              householdId: 'h1',
              paydayDay: payday,
              clock: () => _on(2026, 10, 28),
              salaryLookup: (_, __) => pending.future,
            ));
        await tester.pumpWidget(build(null));
        await tester.pump();

        await tester.pumpWidget(build(15));
        await tester.pump();
        pending.complete(false);
        await tester.pumpAndSettle();

        expect(banner, findsNothing);
      });

      testWidgets('the default payday arriving as 27 does not query again', (tester) async {
        var calls = 0;
        Widget build(int? payday) => _wrap(PaydayCheckinBanner(
              householdId: 'h1',
              paydayDay: payday,
              clock: () => _on(2026, 10, 28),
              salaryLookup: (_, __) async {
                calls++;
                return false;
              },
            ));
        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();
        await tester.pumpWidget(build(27));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(banner, findsOneWidget);
      });

      testWidgets('a salary logged on payday hides it to the last day of the window', (tester) async {
        final salaryAt = _on(2026, 11, 15);
        await tester.pumpWidget(_wrap(PaydayCheckinBanner(
          householdId: 'h1',
          paydayDay: 15,
          clock: () => _on(2026, 11, 22),
          salaryLookup: (_, since) async => !since.isAfter(salaryAt),
        )));
        await tester.pumpAndSettle();

        expect(banner, findsNothing);
      });

      testWidgets('dismissing on the new window stays dismissed across rebuilds and a payday change', (tester) async {
        var calls = 0;
        Widget build(int? payday) => _wrap(PaydayCheckinBanner(
              householdId: 'h1',
              paydayDay: payday,
              clock: () => _on(2026, 11, 16),
              salaryLookup: (_, __) async {
                calls++;
                return false;
              },
            ));
        await tester.pumpWidget(build(15));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);

        await tester.pumpWidget(build(15));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
        expect(calls, 1);

        // Still inside the window after the admin moves payday by a day.
        await tester.pumpWidget(build(16));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
      });
    });
  });
}
