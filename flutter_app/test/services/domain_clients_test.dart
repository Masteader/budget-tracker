import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/transaction_api_client.dart';
import 'package:budget_tracker/services/api/receipt_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';

void main() {
  group('Domain API Clients Tests', () {
    test('Clients instantiate cleanly', () {
      final tx = TransactionApiClient();
      final rx = ReceiptApiClient();
      final cx = ChatApiClient();

      expect(tx, isNotNull);
      expect(rx, isNotNull);
      expect(cx, isNotNull);
    });

    test('ChatApiClient fallback direct parsing returns preview structure', () {
      final cx = ChatApiClient();
      final res = cx.fallbackDirectCloudChat('spent 50 sar at Dunkin', 'hh-123');

      expect(res['status'], equals('preview'));
      expect(res['merchant'], equals('Dunkin'));
      expect(res['amount'], equals(50.0));
      expect(res['items'], isNotEmpty);
    });
  });
}
