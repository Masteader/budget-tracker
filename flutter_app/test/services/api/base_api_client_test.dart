import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';

void main() {
  test('BaseApiClient attaches Authorization bearer token when provided', () async {
    String? capturedAuthHeader;
    String? capturedAppToken;

    final mockClient = MockClient((request) async {
      capturedAuthHeader = request.headers['Authorization'];
      capturedAppToken = request.headers['X-App-Token'];
      return http.Response('{"status": "ok"}', 200);
    });

    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'fake_supabase_jwt_token',
    );

    await client.post('/budgets/breakdown', {'household_id': '11111111-1111-1111-1111-111111111111'}, shouldSign: false);

    expect(capturedAuthHeader, equals('Bearer fake_supabase_jwt_token'));
    if (BaseApiClient.appAuthToken.isNotEmpty) {
      expect(capturedAppToken, equals(BaseApiClient.appAuthToken));
    } else {
      expect(capturedAppToken, isNull);
    }
  });
}
