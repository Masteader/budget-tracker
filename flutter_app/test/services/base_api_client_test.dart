import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/supabase_config.dart';


void main() {
  group('BaseApiClient Tests', () {
    test('Builds headers with default X-App-Token and ngrok skip header', () {
      final client = BaseApiClient();
      final headers = client.buildHeaders();

      expect(headers['Content-Type'], equals('application/json'));
      expect(headers['X-App-Token'], equals(BaseApiClient.appAuthToken));
      expect(headers['ngrok-skip-browser-warning'], equals('true'));
      expect(headers.containsKey('X-Signature'), isFalse);
    });

    test('Computes HMAC-SHA256 signature prefixed with sha256=', () {
      final client = BaseApiClient();
      final payload = '{"test": "data"}';
      final sig = client.sign(payload);

      expect(sig.startsWith('sha256='), isTrue);
      expect(sig.length, greaterThan(10));
    });

    test('Includes X-Signature when signature is passed to buildHeaders', () {
      final client = BaseApiClient();
      final headers = client.buildHeaders(signature: 'sha256=abcdef123456');

      expect(headers['X-Signature'], equals('sha256=abcdef123456'));
    });

    test('Base URL resolves to live backend without /webhook/sms', () {
      final client = BaseApiClient();
      expect(client.baseUrl, equals(fastapiBaseUrl));
    });

  });
}
