import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/widgets/dashboard/payday_checkin_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 10, 27)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 10, 31)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 11, 3)), isTrue);
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 11, 4)), isFalse);
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 10, 25)), isFalse);
      expect(PaydayCheckinBanner.isPaydayWindow(DateTime(2026, 11, 26)), isFalse);
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

    testWidgets('stays hidden when a salary was already logged', (tester) async {
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => DateTime(2026, 10, 27),
        salaryLookup: (_, __) async => true,
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });

    testWidgets('stays hidden outside the payday window without querying', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => DateTime(2026, 10, 15),
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
        clock: () => DateTime(2026, 10, 27),
        salaryLookup: (_, __) async => throw Exception('column does not exist'),
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dismiss button hides the banner', (tester) async {
      await tester.pumpWidget(_wrap(PaydayCheckinBanner(
        householdId: 'h1',
        clock: () => DateTime(2026, 10, 28),
        salaryLookup: (_, __) async => false,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });
  });
}
