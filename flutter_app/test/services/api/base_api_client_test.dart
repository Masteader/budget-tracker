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
    // MOB-02: the per-user JWT is the only credential; no static app token.
    expect(capturedAppToken, isNull);
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
    expect(res['status'], equals('error'));
    expect(res['status_code'], equals(401));
  });

  test('MOB-07: FastAPI JSON error bodies are normalised to status=error with message', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"detail": "Invalid HMAC signature."}', 401);
    });
    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'token',
      sessionRefresher: () async => null,
    );

    final res = await client.post('/agent/scan-receipt', {'household_id': 'h'}, shouldSign: false);

    expect(res['status'], equals('error'));
    expect(res['status_code'], equals(401));
    expect(res['message'], equals('Invalid HMAC signature.'));
    expect(res['detail'], equals('Invalid HMAC signature.'));
  });

  test('MOB-07: 422 validation error keeps status_code so callers can tell it is permanent', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"detail": [{"msg": "field required"}]}', 422);
    });
    final client = BaseApiClient(client: mockClient, authTokenProvider: () => 'token');

    final res = await client.get('/budgets/cycles');

    expect(res['status'], equals('error'));
    expect(res['status_code'], equals(422));
    expect(res['message'], equals('Server response error (422)'));
  });

  test('MOB-08: firewall 403 for an expired bearer token triggers refresh and one replay', () async {
    final tokensUsed = <String?>[];
    final bodies = <String>[];
    final mockClient = MockClient((request) async {
      tokensUsed.add(request.headers['Authorization']);
      bodies.add(request.body);
      if (tokensUsed.length == 1) {
        return http.Response('{"detail": "Forbidden: Untrusted endpoint access."}', 403);
      }
      return http.Response('{"status": "success"}', 200);
    });
    var refreshCalls = 0;
    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'expired_token',
      sessionRefresher: () async {
        refreshCalls++;
        return 'fresh_token';
      },
    );

    final res = await client.post(
      '/agent/chat-transaction',
      {'message': 'Coffee 15'},
      shouldSign: false,
    );

    expect(res['status'], equals('success'));
    expect(refreshCalls, equals(1));
    expect(tokensUsed, equals(['Bearer expired_token', 'Bearer fresh_token']));
    expect(bodies[0], equals(bodies[1]));
  });

  test('MOB-08: a 403 that is a real authorization denial is not retried', () async {
    var requestCount = 0;
    final mockClient = MockClient((request) async {
      requestCount++;
      return http.Response('{"detail": "Forbidden: no access to this household."}', 403);
    });
    var refreshCalls = 0;
    final client = BaseApiClient(
      client: mockClient,
      authTokenProvider: () => 'token',
      sessionRefresher: () async {
        refreshCalls++;
        return 'fresh';
      },
    );

    final res = await client.get('/households/x/payday');

    expect(requestCount, equals(1));
    expect(refreshCalls, equals(0));
    expect(res['status_code'], equals(403));
  });

  test('MOB-06: Idempotency-Key header is forwarded', () async {
    String? key;
    final mockClient = MockClient((request) async {
      key = request.headers['Idempotency-Key'];
      return http.Response('{"status": "success"}', 200);
    });
    final client = BaseApiClient(client: mockClient, authTokenProvider: () => 't');

    await client.post('/agent/chat-transaction', {'m': 1}, shouldSign: false, extraHeaders: {'Idempotency-Key': 'k-1'});

    expect(key, equals('k-1'));
  });

  test('Non-object JSON success bodies do not throw', () async {
    final mockClient = MockClient((request) async => http.Response('[1, 2]', 200));
    final client = BaseApiClient(client: mockClient, authTokenProvider: () => 't');

    final res = await client.get('/list');

    expect(res['status'], equals('success'));
    expect(res['data'], equals([1, 2]));
  });
}

