// UX-05: the help centre explains Nafaqah and the wife's allowance, and its
// household answer no longer presents the roommate split to families.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/settings/help_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

void main() {
  testWidgets('a Nafaqah topic with three questions is listed (Arabic)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const HelpSupportScreen(), lang: 'ar', scaffold: false));
    await tester.pumpAndSettle();

    final topic = find.text('النفقة ومصروف الزوجة');
    expect(topic, findsOneWidget);
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(find.text('من يتحمل مصاريف البيت؟'), findsOneWidget);
    expect(find.text('دفعتُ من مالي للبيت، كيف أستردّه؟'), findsOneWidget);
    expect(find.text('ما هو مصروفي الشخصي ومن يحدده؟'), findsOneWidget);
  });

  test('the Nafaqah answers follow the family rules in every language', () {
    for (final lang in ['en', 'ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));
      for (final key in ['faq_nafaqah_a1', 'faq_nafaqah_a2', 'faq_nafaqah_a3']) {
        final v = l.get(key);
        expect(v, isNot(key), reason: '$lang $key missing');
        expect(v.contains('50/50') || v.contains('%'), isFalse, reason: '$lang $key mentions a split');
      }
    }
  });

  test('the household answer speaks about roommates, not splitting between spouses', () {
    final ar = AppLocalizations(const Locale('ar'));
    final en = AppLocalizations(const Locale('en'));
    final ur = AppLocalizations(const Locale('ur'));
    expect(ar.get('faq_household_a1'), isNot(contains('الشريك')));
    expect(ar.get('faq_household_a1'), contains('شركاء السكن'));
    expect(en.get('faq_household_a1').toLowerCase(), contains('roommate'));
    expect(ur.get('faq_household_a1'), contains('روم میٹ'));
    // Families are pointed to the Nafaqah rule: no split between spouses.
    expect(en.get('faq_household_a1'), contains('never split'));
  });
}
