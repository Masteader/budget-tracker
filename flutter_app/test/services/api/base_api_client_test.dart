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

  test('BaseApiClient automatically refreshes token on 401 and retries successfully', () async {
    int requestCount = 0;
    final tokensUsed = <String?>[];

    final mockClient = MockClient((request) async {
      requestCount++;
      tokensUsed.add(request.headers['Authorization']);
      if (requestCount == 1) {
        return http.Response('{"detail": "Token expired"}', 401);
      }
      return http.Response('{"status": "success", "data": "retried_ok"}', 200);
    });

    int refreshCalls = 0;
    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'expired_token',
      sessionRefresher: () async {
        refreshCalls++;
        return 'fresh_refreshed_token';
      },
    );

    final res = await client.post('/agent/chat-transaction', {'message': 'Coffee 15'}, shouldSign: false);

    expect(requestCount, equals(2));
    expect(refreshCalls, equals(1));
    expect(tokensUsed[0], equals('Bearer expired_token'));
    expect(tokensUsed[1], equals('Bearer fresh_refreshed_token'));
    expect(res['status'], equals('success'));
    expect(res['data'], equals('retried_ok'));
  });

  test('BaseApiClient returns 401 when token refresh fails', () async {
    int requestCount = 0;

    final mockClient = MockClient((request) async {
      requestCount++;
      return http.Response('{"detail": "Token expired"}', 401);
    });

    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'expired_token',
      sessionRefresher: () async => null,
    );

    final res = await client.post('/agent/chat-transaction', {'message': 'Coffee 15'}, shouldSign: false);

    expect(requestCount, equals(1));
    expect(res['detail'], equals('Token expired'));
  });
}
