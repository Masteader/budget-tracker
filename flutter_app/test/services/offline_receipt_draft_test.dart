import 'dart:io';

import 'package:budget_tracker/services/offline_receipt_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offlineReceiptDraftPayload (R8: no invented offline drafts)', () {
    test('a photo-only draft carries the photos and no merchant, amount or category', () {
      final payload = offlineReceiptDraftPayload(imagesBase64: ['aGVsbG8='], userId: 'u1');
      expect(payload['images_base64'], ['aGVsbG8=']);
      expect(payload['needs_cloud_enrichment'], isTrue);
      expect(payload['user_id'], 'u1');
      expect(payload.containsKey('merchant'), isFalse);
      expect(payload.containsKey('amount'), isFalse);
      expect(payload.containsKey('vat_amount'), isFalse);
      expect(payload.containsKey('category_code'), isFalse);
    });

    test('keeps only what the user typed (trimmed) and the Nafaqah choice', () {
      final payload = offlineReceiptDraftPayload(
        imagesBase64: const [],
        merchant: '  Panda  ',
        amount: 42.5,
        qrCodeRaw: 'QR',
        nafaqahFields: const {'paid_by': 'partner', 'nafaqah_class': 'wife_personal'},
      );
      expect(payload['merchant'], 'Panda');
      expect(payload['amount'], 42.5);
      expect(payload['qr_code_raw'], 'QR');
      expect(payload['paid_by'], 'partner');
      expect(payload['nafaqah_class'], 'wife_personal');
    });

    test('blank merchant and zero amount are omitted, never defaulted', () {
      final payload = offlineReceiptDraftPayload(imagesBase64: const ['x'], merchant: '   ', amount: 0);
      expect(payload.containsKey('merchant'), isFalse);
      expect(payload.containsKey('amount'), isFalse);
    });
  });

  test('lib/ ships no mock OCR recognizer or invented receipt text', () {
    expect(File('lib/services/ocr/local_ocr_service.dart').existsSync(), isFalse);
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'\bMock[A-Z]\w*|\bmock[A-Z]\w*').hasMatch(src) || src.contains('Total: 85.00')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
