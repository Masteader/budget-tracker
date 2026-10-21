import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/supabase_config.dart';


void main() {
  group('BaseApiClient Tests', () {
    test('Builds headers with default Content-Type and ngrok skip header', () {
      final client = BaseApiClient();
      final headers = client.buildHeaders();

      expect(headers['Content-Type'], equals('application/json'));
      // MOB-02: no static shared secret is ever sent from the client.
      expect(headers.containsKey('X-App-Token'), isFalse);
      expect(headers['ngrok-skip-browser-warning'], equals('true'));
      expect(headers.containsKey('X-Signature'), isFalse);
    });

    test('sign returns empty string when webhookSecret is not provided via env', () {
      final client = BaseApiClient();
      const payload = '{"test": "data"}';
      final sig = client.sign(payload);

      if (webhookSecret.isEmpty) {
        expect(sig, isEmpty);
      } else {
        expect(sig.startsWith('sha256='), isTrue);
      }
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
