// The export dialog: its strings, colours and phone layout. What ends up in the
// CSV itself is data for spreadsheets and stays exactly as it was.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/services/csv_export_service.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/settings_test_app.dart';

const _rows = <Map<String, dynamic>>[
  {'timestamp': '2026-11-01T10:00:00Z', 'merchant': 'بنده', 'category_code': 'OPEX-GROCERIES', 'amount': 1250.5, 'spent_by': 'both', 'source': 'manual'},
  {'timestamp': '2026-11-02T10:00:00Z', 'merchant': 'Tamimi', 'category_code': 'OPEX-GROCERIES', 'amount': 49.5, 'spent_by': 'both', 'source': 'manual'},
];

Future<void> _open(WidgetTester tester, {String lang = 'en', bool dark = false, double scale = 1.0, double width = 390, String? label}) async {
  useViewport(tester, width: width, height: 900);
  await tester.pumpWidget(settingsTestApp(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => CsvExportService.showExportDialog(context, _rows, monthLabel: label),
        child: const Text('open'),
      ),
    ),
    lang: lang,
    dark: dark,
    scale: scale,
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('the CSV content and its header are untouched', () {
    final csv = CsvExportService.generateTransactionsCsv(_rows, headers: CsvExportService.headersFor(AppLocalizations(const Locale('en'))));
    expect(csv.split('\n').first.trim(), 'Date,Merchant,Category,Amount (SAR),VAT (SAR),Spent By,Source,Items Breakdown');
    expect(csv, contains(',1250.50,163.11,both,manual,'));
  });

  for (final lang in ['en', 'ar', 'ur']) {
    final l = AppLocalizations(Locale(lang));

    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$lang ${width.toInt()}px x$scale: fits', (tester) async {
          await _open(tester, lang: lang, width: width, scale: scale, label: l.cycleRange(DateTime.utc(2026, 10, 27), DateTime.utc(2026, 11, 26)));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('$lang: every string is localized, with the locale money format', (tester) async {
      await _open(tester, lang: lang, label: 'LABEL');
      expect(find.text(l.format('csv_export_title', {'label': 'LABEL'})), findsOneWidget);
      expect(
        find.text(l.format('csv_export_summary', {'transactions': l.plural('transactions_count', 2), 'amount': l.sar(1300)})),
        findsOneWidget,
      );
      expect(find.text(l.get('close')), findsOneWidget);
      expect(find.text(l.get('csv_copy')), findsOneWidget);
      if (lang != 'en') {
        for (final english in ['Close', 'Copy CSV']) {
          expect(find.text(english), findsNothing, reason: english);
        }
        // The preview's header row is in this language: no English column title.
        for (final english in ['Date', 'Merchant', 'Category', 'Spent By', 'Items Breakdown']) {
          expect(find.textContaining(english), findsNothing, reason: english);
        }
        expect(find.textContaining(l.get('csv_col_merchant')), findsOneWidget);
        expect(find.textContaining('Export Report'), findsNothing);
        expect(find.textContaining('transactions'), findsNothing);
      }
    });

    testWidgets('$lang: without a label it still reads', (tester) async {
      await _open(tester, lang: lang);
      expect(find.text(l.format('csv_export_title', {'label': l.get('csv_export_current')})), findsOneWidget);
    });

    testWidgets('$lang: copying confirms in the language and copies the same CSV', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _open(tester, lang: lang);
      final expectedCsv = CsvExportService.generateTransactionsCsv(_rows, headers: CsvExportService.headersFor(l));
      await tester.tap(find.text(l.get('csv_copy')));
      await tester.pumpAndSettle();
      expect(copied, expectedCsv);
      expect(copied, isNot(contains('\u2066')), reason: 'bidi marks are for the preview only');
      expect(copied!.split('\n').first, CsvExportService.headersFor(l).join(','));
      expect(find.text(l.get('csv_copied_title')), findsOneWidget);
      expect(find.text(l.get('csv_copied_msg')), findsOneWidget);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}: tokens, not the off-palette green', (tester) async {
      await _open(tester, dark: dark);
      final ctx = tester.element(find.byType(AlertDialog));
      final icon = tester.widget<Icon>(find.byIcon(Icons.table_view_rounded));
      expect(icon.color, ctx.accentText);
      expect(contrast(icon.color!, ctx.cardBg), greaterThanOrEqualTo(3));
      final btn = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('Copy CSV'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)),
      );
      expect(btn.style!.backgroundColor!.resolve({}), ctx.primaryButtonBg);
      expect(btn.style!.foregroundColor!.resolve({}), ctx.primaryButtonFg);
    });
  }

  group('the preview paints its columns in order (S11)', () {
    /// Where each field starts on screen, from the laid-out paragraph: what the
    /// eye sees, whatever bidi properties the widget carries.
    List<double> paintedStarts(WidgetTester tester, List<String> fields) {
      final finder = find.byKey(const ValueKey('csv_preview'));
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final text = tester.widget<Text>(finder).data!;
      var from = 0;
      return [
        for (final field in fields)
          () {
            final start = text.indexOf(field, from);
            expect(start, isNonNegative, reason: field);
            from = start + field.length;
            final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + field.length));
            return boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
          }(),
      ];
    }

    for (final lang in ['ar', 'ur', 'en']) {
      testWidgets('$lang: the header reads Date first, left to right', (tester) async {
        // Wide enough for one line per row, so left-to-right order is all there is.
        await _open(tester, lang: lang, width: 3000);
        final headers = CsvExportService.headersFor(AppLocalizations(Locale(lang)));
        final starts = paintedStarts(tester, headers);
        for (var i = 1; i < starts.length; i++) {
          expect(starts[i], greaterThan(starts[i - 1]), reason: '${headers[i]} must paint after ${headers[i - 1]}');
        }
      });
    }

    testWidgets('a row with an Arabic merchant stays in column order', (tester) async {
      await _open(tester, lang: 'ar', width: 3000);
      final starts = paintedStarts(tester, ['بنده', 'OPEX-GROCERIES', '1250.50', '163.11', 'both', 'manual']);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i], greaterThan(starts[i - 1]));
      }
    });

    testWidgets('the preview is left to right whatever the app direction', (tester) async {
      await _open(tester, lang: 'ar');
      final preview = tester.widget<Text>(find.byKey(const ValueKey('csv_preview')));
      expect(preview.textDirection, TextDirection.ltr);
      expect(preview.textAlign, TextAlign.left);
    });
  });
}
