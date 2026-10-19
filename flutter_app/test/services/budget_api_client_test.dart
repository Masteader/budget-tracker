import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';

class MockBaseApiClient extends BaseApiClient {
  Map<String, dynamic> mockGetResponse = {};
  Map<String, dynamic> mockPostResponse = {};
  Map<String, dynamic> mockDeleteResponse = {};
  String? lastGetPath;
  String? lastPostPath;
  String? lastDeletePath;
  Map<String, dynamic>? lastPostBody;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async {
    lastGetPath = path;
    return mockGetResponse;
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool shouldSign = true, Duration timeout = const Duration(seconds: 20), Map<String, String>? extraHeaders}) async {
    lastPostPath = path;
    lastPostBody = body;
    return mockPostResponse;
  }

  @override
  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? queryParams, Duration timeout = const Duration(seconds: 15)}) async {
    lastDeletePath = path;
    return mockDeleteResponse;
  }
}

void main() {
  group('BudgetApiClient Tests', () {
    test('Can be instantiated with optional BaseApiClient', () {
      final base = BaseApiClient();
      final client = BudgetApiClient(baseClient: base);
      expect(client.baseClient, equals(base));
    });

    test('fetchHouseholdDependents parses dependent list', () async {
      final mock = MockBaseApiClient();
      mock.mockGetResponse = {
        'status': 'success',
        'dependents': [
          {'id': 'd1', 'household_id': 'hh1', 'name': 'Sarah', 'avatar_icon': 'child'}
        ]
      };
      final client = BudgetApiClient(baseClient: mock);
      final list = await client.fetchHouseholdDependents(householdId: 'hh1');
      expect(mock.lastGetPath, equals('/households/hh1/dependents'));
      expect(list.length, equals(1));
      expect(list.first.name, equals('Sarah'));
    });

    test('createHouseholdDependent posts dependent data', () async {
      final mock = MockBaseApiClient();
      mock.mockPostResponse = {
        'status': 'success',
        'dependent': {'id': 'd2', 'household_id': 'hh1', 'name': 'Adam', 'avatar_icon': 'boy'}
      };
      final client = BudgetApiClient(baseClient: mock);
      final dep = await client.createHouseholdDependent(householdId: 'hh1', name: 'Adam', avatarIcon: 'boy');
      expect(mock.lastPostPath, equals('/households/hh1/dependents'));
      expect(mock.lastPostBody?['name'], equals('Adam'));
      expect(dep?.name, equals('Adam'));
    });

    test('deleteHouseholdDependent calls delete endpoint', () async {
      final mock = MockBaseApiClient();
      mock.mockDeleteResponse = {'status': 'success'};
      final client = BudgetApiClient(baseClient: mock);
      final ok = await client.deleteHouseholdDependent(householdId: 'hh1', dependentId: 'd2');
      expect(mock.lastDeletePath, equals('/households/hh1/dependents/d2'));
      expect(ok, isTrue);
    });
  });
}
