// The deletion date is a Riyadh calendar date everywhere: the web page and the emails
// state it that way, so the app must not show another day on a device elsewhere.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _shown(WidgetTester tester, String lang, DateTime instant) async {
  late String text;
  await tester.pumpWidget(MaterialApp(
    locale: Locale(lang),
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: (context) {
      text = context.fmtDate(SalaryCycleService.riyadhDate(instant), 'd MMMM yyyy');
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
  return text;
}

void main() {
  test('deletion dates never go through device time', () {
    for (final path in const [
      'lib/widgets/settings/account_deletion_flow.dart',
      'lib/widgets/dashboard/household_deletion_banner.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('toLocal()'), isFalse, reason: path);
      expect(source.contains('SalaryCycleService.riyadhDate('), isTrue, reason: path);
    }
  });

  // The same three strings web_app's formatDate produces for this instant.
  testWidgets('21:30 UTC on 5 December is 6 December in every language', (tester) async {
    final instant = DateTime.utc(2026, 12, 5, 21, 30);
    expect(await _shown(tester, 'en', instant), '6 December 2026');
    expect(await _shown(tester, 'ar', instant), '6 ديسمبر 2026');
    expect(await _shown(tester, 'ur', instant), '6 دسمبر 2026');
  });
}
