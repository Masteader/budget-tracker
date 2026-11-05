// Owner decision 2026-11-05: an expense is saved under the category the
// receipt preview chose, never a fallback. The batch review used to replace any
// code its short list does not offer (a household's own category) with
// Groceries, putting the expense in the wrong budget.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/widgets/scanner/batch_item_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final code in ['OPEX-HOUSING', 'CUSTOM-HOME-OFFICE', 'OPEX-GROCERY']) {
    testWidgets('the preview\'s category $code is saved as is', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        locale: const Locale('en'),
        home: Scaffold(
          body: BatchItemReviewSheet(
            receiptImages: [File('test_assets/receipt1.jpg')],
            householdId: 'hh_test_123',
            previewReceipt: (_) async => {
              'merchant': 'Ejar',
              'amount': 2500.0,
              'vat_amount': 0.0,
              'category_code': code,
            },
            saveReceipt: (r) async => saved.add(r),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch_save_next_button')));
      await tester.pumpAndSettle();
      expect(saved.single['category_code'], code);
    });
  }
}
