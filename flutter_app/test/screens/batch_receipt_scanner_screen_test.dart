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
              previewReceipt: (file) async => {
                'merchant': 'Panda Supermarket',
                'amount': 45.50,
                'vat_amount': 6.82,
                'category_code': 'OPEX-GROCERY',
              },
              saveReceipt: (_) async {},
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

    // External review (Gemini) BLOCKER 5: scanned receipts get the family Nafaqah choice.
    Widget familySheet(Map<String, dynamic> parse, {void Function(int, double)? onComplete}) => MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          locale: const Locale('en'),
          home: Scaffold(
            body: BatchItemReviewSheet(
              receiptImages: [File('test_assets/receipt1.jpg')],
              householdId: 'hh_test_123',
              previewReceipt: (_) async => parse,
              saveReceipt: (_) async {},
              onComplete: onComplete,
            ),
          ),
        );

    Map<String, dynamic> familyParse({String role = 'wife', String? cls, List<Map<String, dynamic>>? wives}) => {
          'merchant': 'Panda Supermarket',
          'amount': 45.50,
          'vat_amount': 6.82,
          'category_code': 'OPEX-GROCERY',
          'household_mode': 'family_nafaqah',
          'recorder_role': role,
          'nafaqah_class': cls,
          'wives': wives ?? [
            {'id': 'wife-1', 'display_name': 'Sara'},
          ],
        };

    testWidgets('family: a wife reviews her receipt as a shared advance or her allowance', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(familySheet(familyParse(cls: 'wife_reimbursable')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('batch_nafaqah_review')), findsOneWidget);
      expect(find.text('I paid for the home — he pays me back'), findsOneWidget);
      expect(find.text('For me personally — from my allowance'), findsOneWidget);
      expect(find.textContaining('50/50'), findsNothing);
    });

    testWidgets('roommates: no Nafaqah choice on scanned receipts', (tester) async {
      await tester.pumpWidget(familySheet(familyParse()..['household_mode'] = 'not_family'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch_nafaqah_review')), findsNothing);
    });

    testWidgets('family: a husband with several wives picks the wife before saving', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var saved = -1;

      await tester.pumpWidget(familySheet(
        familyParse(role: 'husband', cls: 'wife_reimbursable', wives: [
          {'id': 'wife-1', 'display_name': 'Sara'},
          {'id': 'wife-2', 'display_name': 'Mona'},
        ]),
        onComplete: (count, _) => saved = count,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('batch_save_next_button')));
      await tester.pumpAndSettle();
      expect(saved, -1);
      expect(find.text('Choose which wife paid before saving.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nafaqah_wife_wife-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch_save_next_button')));
      await tester.pumpAndSettle();
      expect(saved, 1);
    });

    testWidgets('offline: the photo becomes a pending draft with nothing guessed (R8)', (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
          locale: const Locale('en'),
          home: Scaffold(
            body: BatchItemReviewSheet(
              receiptImages: [File('test_assets/receipt1.jpg')],
              householdId: 'hh_test_123',
              previewReceipt: (_) async => {'status': 'error', 'message': 'offline', 'network_error': true},
              saveReceipt: (r) async => saved = r,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('batch_offline_notice')), findsOneWidget);
      expect(find.text('Al Othaim Markets'), findsNothing);
      expect(find.text('85.00'), findsNothing);

      await tester.tap(find.byKey(const Key('batch_save_next_button')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!['is_offline_draft'], isTrue);
      expect(saved!['merchant'], '');
      expect(saved!['amount'], 0.0);
    });
  });
}
