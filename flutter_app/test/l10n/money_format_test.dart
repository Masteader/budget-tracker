// UX-10: one formatter for every amount ("1,040.00 ر.س" in Arabic, never
// "SAR 342.75" or "SAR 202.4" next to Arabic text).
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

void main() {
  final ar = AppLocalizations(const Locale('ar'));
  final ur = AppLocalizations(const Locale('ur'));
  final en = AppLocalizations(const Locale('en'));

  test('money(): SAR goes through sar(), other currencies keep their code', () {
    expect(ar.money(6240.5, 'SAR'), '6,240.50 ر.س');
    expect(ur.money(6240.5, 'SAR'), '6,240.50 ریال');
    expect(en.money(6240.5, 'SAR'), 'SAR 6,240.50');
    expect(ar.money(12, 'USD'), '12.00 USD');
    expect(en.money(12, 'USD'), 'USD 12.00');
    expect(ar.money(-859.5, 'SAR'), '-859.50 ر.س');
    // English puts the sign before the code: "-SAR 859.50", not "SAR -859.50".
    expect(en.money(-859.5, 'SAR'), '-SAR 859.50');
    expect(en.sar(-859.5), '-SAR 859.50');
    expect(en.money(-3, 'USD'), '-USD 3.00');
    expect(en.money(859.5, 'SAR', signed: true), '+SAR 859.50');
    expect(ar.money(859.5, 'SAR', signed: true), '+859.50 ر.س');
    expect(ar.money(1000, 'SAR', decimals: 0), '1,000 ر.س');
    // Lower-case / blank currency codes are SAR.
    expect(ar.money(1, ''), '1.00 ر.س');
    expect(ar.money(1, 'sar'), '1.00 ر.س');
  });

  testWidgets('feed card shows Arabic amounts with grouping, no "SAR 342.75"', (tester) async {
    await tester.pumpWidget(localizedApp(const TransactionItemBreakdownCard(
      merchant: 'Danube',
      amount: 1342.75,
      initiallyExpanded: true,
      items: [
        {'name': 'Rice', 'quantity': 1, 'price': 1202.4},
        {'name': 'Milk', 'quantity': 1, 'price': 140.35},
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('SAR'), findsNothing);
    expect(find.text('1,342.75 ر.س'), findsWidgets);
    expect(find.text('1,202.40 ر.س'), findsOneWidget);
  });

  test('screens and widgets never format money as "<currency> <toStringAsFixed>"', () {
    final pattern = RegExp(r"""(currency|'SAR'|"SAR"|tr\(['"]sar['"]\))\}? \$\{[^}]*(toStringAsFixed|fmt\.format)""");
    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
