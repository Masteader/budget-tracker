import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/screens/scanner/batch_receipt_scanner_screen.dart';
import 'package:budget_tracker/widgets/scanner/batch_item_review_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('BatchReceiptScannerScreen Tests', () {
    testWidgets('renders batch scanner screen with initial empty queue state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          supportedLocales: [Locale('en'), Locale('ar'), Locale('ur')],
          locale: Locale('en'),
          home: BatchReceiptScannerScreen(householdId: 'hh_test_123'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('batch_scanner_app_bar')), findsOneWidget);
      expect(find.byKey(const Key('batch_shutter_button')), findsOneWidget);
      expect(find.byKey(const Key('batch_queue_counter')), findsOneWidget);
      expect(find.textContaining('0'), findsWidgets);
    });

    testWidgets('renders thumbnails in queue tray and deletes item on delete badge tap', (tester) async {
      final dummyFile1 = File('test_assets/receipt1.jpg');
      final dummyFile2 = File('test_assets/receipt2.jpg');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          locale: const Locale('en'),
          home: BatchReceiptScannerScreen(
            householdId: 'hh_test_123',
            initialFiles: [dummyFile1, dummyFile2],
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('queue_item_thumbnail_0')), findsOneWidget);
      expect(find.byKey(const Key('queue_item_thumbnail_1')), findsOneWidget);
      expect(find.byKey(const Key('process_batch_queue_button')), findsOneWidget);

      // Tap delete on the first item
      await tester.tap(find.byKey(const Key('delete_queue_item_0')));
      await tester.pumpAndSettle();

      // Only 1 item remains
      expect(find.byKey(const Key('queue_item_thumbnail_0')), findsOneWidget);
      expect(find.byKey(const Key('queue_item_thumbnail_1')), findsNothing);
    });

    testWidgets('BatchItemReviewSheet steps through receipts sequentially and completes batch', (tester) async {
      final dummyFile1 = File('test_assets/receipt1.jpg');
      final dummyFile2 = File('test_assets/receipt2.jpg');

      bool batchFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          locale: const Locale('en'),
          home: Scaffold(
            body: BatchItemReviewSheet(
              receiptImages: [dummyFile1, dummyFile2],
              householdId: 'hh_test_123',
              mockInitialParse: (file) => {
                'merchant': 'Panda Supermarket',
                'amount': 45.50,
                'vat_amount': 6.82,
                'category_code': 'OPEX-GROCERY',
              },
              onComplete: (savedCount, totalAmount) {
                batchFinished = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 1: Receipt 1 of 2
      expect(find.textContaining('1'), findsWidgets);
      expect(find.text('Panda Supermarket'), findsOneWidget);
      expect(find.byKey(const Key('batch_skip_button')), findsOneWidget);
      expect(find.byKey(const Key('batch_save_next_button')), findsOneWidget);

      // Save & Next -> Advances to Step 2
      await tester.tap(find.byKey(const Key('batch_save_next_button')));
      await tester.pumpAndSettle();

      // Step 2: Receipt 2 of 2
      expect(find.textContaining('2'), findsWidgets);

      // Tap Skip on item 2
      await tester.tap(find.byKey(const Key('batch_skip_button')));
      await tester.pumpAndSettle();

      // Batch finished state
      expect(batchFinished, isTrue);
      expect(find.byKey(const Key('batch_complete_card')), findsOneWidget);
    });
  });
}
