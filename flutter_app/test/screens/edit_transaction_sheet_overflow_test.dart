// The edit sheet at the smallest supported screen with the largest text: nothing
// overflows and no amount is hidden, in every language and both themes.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'aaaaaaaa-0000-4000-8000-00000000000a';
const _salem = 'bbbbbbbb-0000-4000-8000-00000000000b';

Map<String, dynamic> _row(Map<String, dynamic> fields) => {
      'id': 'tx-1',
      'household_id': 'h1',
      'amount': 12345.67,
      'currency': 'SAR',
      'merchant': 'Al Othaim Markets Riyadh Park Branch',
      'category_code': 'OPEX-GROCERY',
      'timestamp': '2026-10-20T18:00:00Z',
      'created_at': '2026-10-20T18:00:01Z',
      'user_id': _me,
      'source': 'receipt',
      'spent_by': 'me',
      'items': [
        {'name': 'Basmati rice 10 kg family pack', 'price': 11234.50, 'quantity': 3, 'beneficiary': 'household'},
        {'name': 'Milk', 'price': 1111.17, 'quantity': 12, 'beneficiary': _me},
      ],
      ...fields,
    };

const _rows = {
  'own row': <String, dynamic>{},
  'row of a deleted member': <String, dynamic>{'user_id': null},
  'row without items': <String, dynamic>{'items': <Map<String, dynamic>>[]},
};

/// Opens the sheet the way the app does, on a 320 wide phone at x2.0 text.
Future<List<FlutterErrorDetails>> _open(WidgetTester tester, Map<String, dynamic> row, String lang, bool dark) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final overflows = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      overflows.add(details);
    } else {
      previous?.call(details);
    }
  };

  await tester.pumpWidget(MaterialApp(
    locale: Locale(lang),
    theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
      child: page!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => EditTransactionSheet(
              transaction: Transaction.fromMap(_row(row)),
              nafaqah: const NafaqahSummary(mode: 'not_family'),
              loadNafaqahFields: (_) async => {'nafaqah_class': null, 'nafaqah_spouse_id': null},
              currentUserId: () => _me,
              isAdmin: true,
              loadRoster: (_) async => const HouseholdRoster(
                householdId: 'h1',
                members: [
                  HouseholdMember(userId: _me, displayName: 'Abdulrahman Alqahtani', role: 'admin', financialRole: 'peer', isSelf: true),
                  HouseholdMember(userId: _salem, displayName: 'Salem Bin Abdullah Alghamdi', financialRole: 'peer'),
                ],
              ),
              updateRow: (id, values) async {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return overflows;
}

/// Every Text under the sheet that is cut off or fades out instead of wrapping.
List<String> _clippedText(WidgetTester tester) {
  final clipped = <String>[];
  for (final element in find.descendant(of: find.byType(EditTransactionSheet), matching: find.byType(RichText)).evaluate()) {
    final render = element.renderObject! as RenderParagraph;
    if (render.didExceedMaxLines && render.overflow != TextOverflow.visible) {
      clipped.add(render.text.toPlainText());
    }
  }
  return clipped;
}

bool _isAmount(String text) => RegExp(r'\d[\d,.]*\d').hasMatch(text);

void main() {
  for (final lang in const ['en', 'ar', 'ur']) {
    for (final dark in const [false, true]) {
      for (final rowEntry in _rows.entries) {
        testWidgets('$lang, ${dark ? 'dark' : 'light'}, ${rowEntry.key}: no overflow at 320px and x2.0', (tester) async {
          final frameworkHandler = FlutterError.onError;
          final errors = await _open(tester, rowEntry.value, lang, dark);
          expect(find.byType(EditTransactionSheet), findsOneWidget);

          // Scroll through the whole sheet, so every part is laid out.
          final scrollable = find.descendant(of: find.byType(EditTransactionSheet), matching: find.byType(Scrollable));
          if (scrollable.evaluate().isNotEmpty) {
            final position = tester.state<ScrollableState>(scrollable.first).position;
            for (var step = 0; step < 40 && position.pixels < position.maxScrollExtent; step++) {
              position.jumpTo((position.pixels + 300).clamp(0.0, position.maxScrollExtent));
              await tester.pump();
            }
          }

          FlutterError.onError = frameworkHandler;
          expect(
            errors.map((e) => e.exceptionAsString().split('\n').first).toList(),
            isEmpty,
            reason: errors.map((e) => e.toString()).join('\n'),
          );
          expect(_clippedText(tester).where(_isAmount), isEmpty, reason: 'an amount must never be cut off');

          // An amount field must show all its digits, not scroll them out of sight.
          final fields = find.descendant(of: find.byType(EditTransactionSheet), matching: find.byType(EditableText));
          final amounts = fields.evaluate().map((e) => tester.state<EditableTextState>(find.byWidget(e.widget))).where(
                (field) => _isAmount(field.textEditingValue.text) && !field.textEditingValue.text.contains(RegExp(r'[A-Za-z]')),
              );
          // The total, plus each item's price when the row has items.
          expect(amounts.length, greaterThanOrEqualTo(rowEntry.key == 'row without items' ? 1 : 3));
          for (final field in amounts) {
            expect(field.renderEditable.maxScrollExtent, 0, reason: 'hidden digits in ${field.textEditingValue.text}');
          }
        });
      }
    }
  }
}
