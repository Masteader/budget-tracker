// Every titled toast in the app goes through AppSnackBar. Colours are read from
// what is really painted: the paragraph's resolved style on the bar's Material.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_test_app.dart';

Color _painted(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.descendant(of: find.byType(SnackBar), matching: find.text(text))).text.style!.color!;

Color _bar(WidgetTester tester) => tester
    .widget<Material>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first)
    .color!;

Future<BuildContext> _page(WidgetTester tester, {String lang = 'en', bool dark = false}) async {
  useViewport(tester, height: 800);
  await tester.pumpWidget(settingsTestApp(const Text('page'), lang: lang, dark: dark));
  await tester.pump();
  return tester.element(find.text('page'));
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    final shows = <String, void Function(BuildContext)>{
      'success': (c) => AppSnackBar.showSuccess(c, 'Message', title: 'Title'),
      'error': (c) => AppSnackBar.showError(c, 'Message', title: 'Title'),
      'warning': (c) => AppSnackBar.showWarning(c, 'Message', title: 'Title'),
      'info': (c) => AppSnackBar.showInfo(c, 'Message', title: 'Title'),
      'delete': (c) => AppSnackBar.showDelete(c, 'Message', title: 'Title'),
    };

    shows.forEach((name, show) {
      testWidgets('$mode $name: title and message read on the bar', (tester) async {
        final ctx = await _page(tester, dark: dark);
        show(ctx);
        await tester.pumpAndSettle();
        final bar = _bar(tester);
        expect(bar, ctx.cardBg);
        expect(_painted(tester, 'Title'), ctx.textPrimary);
        expect(contrast(_painted(tester, 'Title'), bar), greaterThanOrEqualTo(4.5));
        expect(contrast(_painted(tester, 'Message'), bar), greaterThanOrEqualTo(4.5));
      });
    });
  }

  for (final lang in ['en', 'ar', 'ur']) {
    testWidgets('$lang: undo is localized and still undoes', (tester) async {
      final ctx = await _page(tester, lang: lang);
      var undone = 0;
      AppSnackBar.showDelete(ctx, 'Message', onUndo: () => undone++);
      await tester.pumpAndSettle();
      final label = AppLocalizations(Locale(lang)).get('undo_action');
      expect(find.text(label), findsOneWidget);
      if (lang != 'en') expect(find.text('UNDO'), findsNothing);
      await tester.tap(find.text(label));
      await tester.pump();
      expect(undone, 1);
    });
  }

  testWidgets('without an undo callback there is no undo button', (tester) async {
    final ctx = await _page(tester);
    AppSnackBar.showDelete(ctx, 'Message');
    await tester.pumpAndSettle();
    expect(find.text('UNDO'), findsNothing);
  });
}
