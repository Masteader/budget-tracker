// UX-21: affordability verdicts come from AppLocalizations in en / ar / ur and
// amounts go through the riyal formatter, never inline "SAR x.x" strings.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/simulator/affordability_simulator_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _advice(String lang, Map<String, dynamic> res) =>
    affordabilityAdvice(AppLocalizations(Locale(lang)), res);

const _comfortable = {
  'verdict': 'comfortable',
  'post_purchase_remaining': 7400.0,
  'days_to_payday': 6,
  'current_daily_allowance': 1300.0,
  'post_purchase_daily_allowance': 1233.333,
  // The server's own en/ar sentences are not shown any more.
  'advice_en': '✅ Yes! You have SAR 400.0 remaining',
  'advice_ar': '✅ نعم، بكل أريحية!',
};

void main() {
  test('comfortable: remaining and days, in all three languages', () {
    expect(_advice('en', _comfortable), "Fits your budget. You'll still have SAR 7,400.00 until payday (6 days).");
    expect(_advice('ar', _comfortable), 'ضمن ميزانيتك. سيبقى لديك 7,400.00 ر.س حتى الراتب (6 أيام).');
    expect(_advice('ur', _comfortable), contains('7,400.00'));
    expect(_advice('ur', _comfortable), isNot(contains('SAR')));
  });

  test('caution: the daily amount before and after, through the formatter', () {
    final res = {..._comfortable, 'verdict': 'caution'};
    expect(
      _advice('en', res),
      'Affordable only by moving money from flexible budgets: your daily amount until payday drops from SAR 1,300.00 to SAR 1,233.33.',
    );
    expect(_advice('ar', res), contains('من 1,300.00 ر.س إلى 1,233.33 ر.س'));
  });

  test('unaffordable: wait for payday or pay in installments', () {
    final res = {..._comfortable, 'verdict': 'unaffordable', 'days_to_payday': 1};
    expect(_advice('en', res), 'More than your flexible budgets can cover. Consider waiting 1 day until payday or paying in installments.');
    expect(_advice('ar', res), 'أكثر مما تغطيه ميزانياتك المرنة. يُفضّل الانتظار يوم واحد حتى الراتب أو التقسيط.');
  });

  test('invalid price', () {
    expect(_advice('en', {'verdict': 'invalid'}), 'Enter a price above zero.');
  });

  testWidgets('the offline estimate shows the localized advice', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: [AppLocalizationsDelegate()],
      supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
      locale: Locale('en'),
      home: Scaffold(body: AffordabilitySimulatorSheet(defaultItem: 'iPad', defaultAmount: 1200, defaultCategory: 'OPEX-SHOPPING')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate Purchase'));
    await tester.pumpAndSettle();
    // No budgets loaded: the offline estimate cannot cover it.
    expect(find.textContaining('More than your flexible budgets can cover'), findsOneWidget);
    expect(find.textContaining('SAR 0.0 '), findsNothing);
  });
}
