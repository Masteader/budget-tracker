// UX-18 / UX-19: chat copy in the app language only, and one 48 dp voice
// language control instead of three 25 dp pills.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/chat/voice_language_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_app.dart';

final _latin = RegExp('[A-Za-z]');

void main() {
  test('the welcome text and examples match the language (no English inside Arabic or Urdu)', () {
    for (final lang in ['ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));
      expect(_latin.hasMatch(l.get('chat_welcome')), isFalse, reason: '$lang welcome');
      for (final key in chatExampleKeys) {
        expect(_latin.hasMatch(l.get(key)), isFalse, reason: '$lang $key: ${l.get(key)}');
      }
    }
    final en = AppLocalizations(const Locale('en'));
    for (final key in chatExampleKeys) {
      expect(RegExp('[؀-ۿ]').hasMatch(en.get(key)), isFalse, reason: 'en $key');
    }
  });

  test('the chat screen has no hard-coded example messages', () {
    final src = File('lib/screens/chat/chat_entry_screen.dart').readAsStringSync();
    expect(src.contains('Can I buy a 1200 SAR iPad?'), isFalse);
    expect(src.contains('Dunkin 19 SAR'), isFalse);
  });

  testWidgets('one voice-language control, 48 dp, offering the three languages', (tester) async {
    var chosen = 'ar_SA';
    await tester.pumpWidget(localizedApp(
      StatefulBuilder(
        builder: (context, setState) => VoiceLanguageButton(
          localeId: chosen,
          onChanged: (v) => setState(() => chosen = v),
        ),
      ),
      lang: 'ar',
    ));
    await tester.pumpAndSettle();
    final button = find.byType(VoiceLanguageButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('اردو'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(chosen, 'en_US');
  });
}
