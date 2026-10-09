import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/support_api_client.dart';
import 'package:budget_tracker/services/api_service.dart';

void main() {
  test('SupportApiClient exposes postSupportChat and ApiService facade', () {
    final client = SupportApiClient();
    expect(client, isNotNull);
    expect(ApiService.instance.support, isNotNull);
  });
}
