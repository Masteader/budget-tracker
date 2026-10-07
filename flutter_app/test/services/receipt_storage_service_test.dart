import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/receipt_storage_service.dart';

void main() {
  group('ReceiptStorageService', () {
    test('generateStoragePath creates sanitized path under household partition', () {
      const householdId = 'hh-123-abc';
      final path = ReceiptStorageService.generateStoragePath(householdId, 'test.jpg');
      expect(path.startsWith('hh-123-abc/'), isTrue);
      expect(path.endsWith('.jpg'), isTrue);
    });

    test('generateStoragePath handles png extensions', () {
      const householdId = 'hh-123-abc';
      final path = ReceiptStorageService.generateStoragePath(householdId, 'receipt.PNG');
      expect(path.startsWith('hh-123-abc/'), isTrue);
      expect(path.endsWith('.png'), isTrue);
    });

    test('uploadReceipt returns null if image file does not exist', () async {
      final service = ReceiptStorageService();
      final nonExistent = File('non_existent_receipt.jpg');
      final result = await service.uploadReceipt(
        imageFile: nonExistent,
        householdId: 'hh-123-abc',
      );
      expect(result, isNull);
    });
  });
}
