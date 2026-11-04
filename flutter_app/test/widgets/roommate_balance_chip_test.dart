// The roommate balance chip: name and amount share one paragraph, words break at
// word boundaries, and an amount is one unit that never splits across digits.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/widgets/dashboard/multi_roommate_settlement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_test_app.dart';

const _balances = {
  'Abdulrahman Al-Qahtani': 12500.5,
  'Sara': 1234567.89,
  'Faisal': -1250.5,
};

String _amount(AppLocalizations l, double balance) => '${balance > 0 ? '+' : '-'}${l.sar(balance.abs())}';

Future<void> _pump(WidgetTester tester, {String lang = 'en', bool dark = false, double scale = 1.0, double width = 320}) async {
  useViewport(tester, width: width);
  await tester.pumpWidget(settingsTestApp(
    const MultiRoommateSettlementCard(
      householdId: 'hh',
      currentUserId: 'me',
      summary: SettlementV2Summary(mode: 'multi_roommate', roommateBalances: _balances),
    ),
    lang: lang,
    dark: dark,
    scale: scale,
  ));
  await tester.pump();
}

void main() {
  setUpAll(loadRealFontMetrics);

  for (final lang in ['en', 'ar', 'ur']) {
    final l = AppLocalizations(Locale(lang));
    for (final scale in [1.5, 2.0]) {
      testWidgets('$lang 320px x$scale: amounts stay whole, names break between words', (tester) async {
        await _pump(tester, lang: lang, scale: scale);
        expect(tester.takeException(), isNull);

        _balances.forEach((name, balance) {
          // The exact amount text, sign included, on exactly one painted line.
          final amount = find.text(_amount(l, balance));
          expect(amount, findsOneWidget, reason: name);
          expect(paintedLineCount(tester.renderObject<RenderParagraph>(amount)), 1, reason: name);
        });

        final card = find.byType(MultiRoommateSettlementCard);
        expect(brokenWords(tester, card), isEmpty);

        // Nothing leaves the card.
        final cardRect = tester.getRect(card);
        for (final balance in _balances.values) {
          final rect = tester.getRect(find.text(_amount(l, balance)));
          expect(rect.left, greaterThanOrEqualTo(cardRect.left));
          expect(rect.right, lessThanOrEqualTo(cardRect.right));
        }
      });
    }

    testWidgets('$lang: name and amount read in the right order', (tester) async {
      await _pump(tester, lang: lang, width: 390);
      final name = tester.renderObject<RenderParagraph>(find.textContaining('FAISAL'));
      final nameBox = name.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 6)).first;
      final nameLeft = name.localToGlobal(Offset(nameBox.left, 0)).dx;
      final nameRight = name.localToGlobal(Offset(nameBox.right, 0)).dx;
      final amount = tester.getRect(find.text(_amount(l, -1250.5)));
      if (lang == 'en') {
        expect(nameRight, lessThanOrEqualTo(amount.left));
      } else {
        expect(nameLeft, greaterThanOrEqualTo(amount.right));
      }
    });
  }

  testWidgets('a name and amount that fit share one line (space is not split in half)', (tester) async {
    await _pump(tester, width: 390);
    final chip = find.ancestor(of: find.text('+SAR 1,234,567.89'), matching: find.byType(Container)).first;
    final paragraph = tester.renderObject<RenderParagraph>(find.textContaining('SARA'));
    expect(paintedLineCount(paragraph), 1);
    expect(tester.getRect(find.text('+SAR 1,234,567.89')).center.dy, closeTo(tester.getRect(chip).center.dy, 2));
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}: every amount reaches AA on its chip', (tester) async {
      await _pump(tester, dark: dark, width: 390);
      final ctx = tester.element(find.byType(MultiRoommateSettlementCard));
      final l = AppLocalizations(const Locale('en'));
      for (final balance in _balances.values) {
        final amount = find.text(_amount(l, balance));
        final chip = tester.widget<Container>(find.ancestor(of: amount, matching: find.byType(Container)).first);
        final wash = (chip.decoration! as BoxDecoration).color!;
        final fill = Color.alphaBlend(wash, surfaceCardBg(ctx));
        expect(contrast(tester.widget<Text>(amount).style!.color!, fill), greaterThanOrEqualTo(4.5), reason: '$balance');
      }
    });
  }
}
