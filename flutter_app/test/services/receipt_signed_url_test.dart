import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budget_tracker/services/receipt_storage_service.dart';

void main() {
  late List<http.Request> requests;
  late int signStatus;

  SupabaseClient fakeClient() => SupabaseClient(
        'https://unit-test.invalid',
        'sb_publishable_unit_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (signStatus != 200) {
            return http.Response(jsonEncode({'statusCode': '$signStatus', 'error': 'x', 'message': 'denied'}), signStatus);
          }
          final path = request.url.path.split('/object/sign/').last;
          return http.Response(jsonEncode({'signedURL': '/object/sign/$path?token=fresh-${requests.length}'}), 200);
        }),
      );

  setUp(() {
    requests = [];
    signStatus = 200;
    ReceiptStorageService.clearSignedUrlCache();
  });

  test('MOB-22: a stored (expiring) signed URL is re-signed from its storage path', () async {
    final service = ReceiptStorageService(client: fakeClient());
    const stored =
        'https://unit-test.invalid/storage/v1/object/sign/receipts/hh-1/old.jpg?token=expired-token';

    final url = await service.getSignedReceiptUrl(stored);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, contains('/object/sign/receipts/hh-1/old.jpg'));
    expect(url, contains('token=fresh-1'));
    expect(url, isNot(contains('expired-token')));
  });

  test('MOB-22: signed URLs are cached until near expiry, then cleared on sign-out', () async {
    final service = ReceiptStorageService(client: fakeClient());
    final a = await service.getSignedReceiptUrl('hh-1/a.jpg');
    final b = await service.getSignedReceiptUrl('hh-1/a.jpg');
    expect(a, b);
    expect(requests, hasLength(1));
    expect(ReceiptStorageService.cachedSignedUrlCount, 1);

    ReceiptStorageService.clearSignedUrlCache();
    expect(ReceiptStorageService.cachedSignedUrlCount, 0);
  });

  test('MOB-22: when signing is denied no unusable URL is returned', () async {
    signStatus = 403;
    final service = ReceiptStorageService(client: fakeClient());

    expect(await service.getSignedReceiptUrl('hh-other/a.jpg'), isNull);
    expect(
      await service.getSignedReceiptUrl('https://unit-test.invalid/storage/v1/object/public/receipts/hh-1/a.jpg'),
      isNull,
    );
  });
}
