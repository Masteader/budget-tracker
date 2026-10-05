import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';

void main() {
  group('BudgetApiClient Tests', () {
    test('Can be instantiated with optional BaseApiClient', () {
      final base = BaseApiClient();
      final client = BudgetApiClient(baseClient: base);
      expect(client.baseClient, equals(base));
    });
  });
}
