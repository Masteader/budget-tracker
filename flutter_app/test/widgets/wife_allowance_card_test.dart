import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_allowance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(AllowanceStatus allowance, {bool viewerIsWife = false}) => MaterialApp(
      localizationsDelegates: const [AppLocalizationsDelegate()],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WifeAllowanceCard(
            householdId: 'hh',
            wife: NafaqahWife(id: 'w1', displayName: 'Sara', allowance: allowance),
            cycleKey: '2026-11',
            viewerIsWife: viewerIsWife,
          ),
        ),
      ),
    );

void main() {
  group('working wife without an allowance (§2.3)', () {
    testWidgets('shows her personal spending neutrally, never "overspent"', (tester) async {
      await tester.pumpWidget(_host(const AllowanceStatus(cycleKey: '2026-11', spent: 200, remaining: -200)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('allowance_personal_spending')), findsOneWidget);
      expect(find.textContaining('SAR 200.00'), findsOneWidget);
      expect(find.textContaining('Over the allowance'), findsNothing);
      expect(find.byKey(const ValueKey('allowance_remaining_value')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('the wife herself reads "your" personal spending', (tester) async {
      await tester.pumpWidget(
        _host(const AllowanceStatus(cycleKey: '2026-11', spent: 75, remaining: -75), viewerIsWife: true),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Your personal spending'), findsOneWidget);
    });

    testWidgets('"overspent" appears only when an allowance exists', (tester) async {
      await tester.pumpWidget(
        _host(const AllowanceStatus(cycleKey: '2026-11', isSet: true, allocated: 100, spent: 150, remaining: -50)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Over the allowance'), findsOneWidget);
      expect(find.byKey(const ValueKey('allowance_remaining_value')), findsOneWidget);
      expect(find.byKey(const ValueKey('allowance_personal_spending')), findsNothing);
    });
  });

  test('AllowanceStatus: no allowance means never overspent', () {
    expect(const AllowanceStatus(spent: 200, remaining: -200).isOverspent, isFalse);
    expect(const AllowanceStatus(spent: 200, remaining: -200).hasAllowance, isFalse);
    expect(const AllowanceStatus(allocated: 100, spent: 150, remaining: -50).isOverspent, isTrue);
    expect(const AllowanceStatus(isSet: true, allocated: 100, spent: 50, remaining: 50).isOverspent, isFalse);
  });
}
