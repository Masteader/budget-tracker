import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';

class _MockAccountServiceForVoid extends AccountService {
  final List<String> voidCalls = [];
  bool shouldThrow = false;
  Map<String, dynamic> responseToReturn = {
    'success': true,
    'id': 'inc-test-1',
    'income_id': 'inc-test-1',
    'household_id': 'hh-1',
    'account_id': 'acc-1',
    'user_id': 'u-1',
    'cycle_key': '2026-11',
    'title': 'Test Salary',
    'net_amount': 500.0,
    'reverted_amount': 500.0,
    'new_balance': 1000.0,
    'voided_at': '2026-11-02T08:00:00Z',
  };

  int getAccountsCalls = 0;
  List<Account> accountsToReturn = [
    Account(
      id: 'acc-1',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Bank Checking',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 1500.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  int getCycleIncomeCalls = 0;
  List<IncomeRecord> cycleIncomeToReturn = [
    IncomeRecord(
      id: 'inc-test-1',
      householdId: 'hh-1',
      userId: 'u-1',
      accountId: 'acc-1',
      cycleKey: '2026-11',
      sourceType: IncomeSourceType.salary,
      title: 'Test Salary',
      baseAmount: 500.0,
      receivedAt: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 11, 1),
    ),
  ];

  @override
  Future<Map<String, dynamic>> voidIncomeRecord(
    String incomeId, {
    Future<dynamic> Function(String fn, Map<String, dynamic> params)? rpcHandler,
  }) async {
    if (shouldThrow) {
      throw Exception('Database rejection: Access denied (42501)');
    }
    voidCalls.add(incomeId);
    return responseToReturn;
  }

  @override
  Future<List<Account>> getAccounts(String householdId) async {
    getAccountsCalls++;
    return accountsToReturn;
  }

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async {
    getCycleIncomeCalls++;
    return cycleIncomeToReturn;
  }

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => 0.0;

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

class _MockCommitmentsServiceForVoid extends CommitmentsService {
  @override
  Future<List<PendingCommitment>> getPendingCommitments({
    required String householdId,
    required int paydayDay,
    required String cycleKey,
    DateTime? today,
  }) async =>
      [];
}

void main() {
  group('AccountService.voidIncomeRecord Unit Tests', () {
    test('invokes void_income_record RPC with p_income_id parameter and returns deserialized response', () async {
      final service = AccountService();
      String? invokedFn;
      Map<String, dynamic>? invokedParams;

      final res = await service.voidIncomeRecord(
        'inc-uuid-1234',
        rpcHandler: (fn, params) async {
          invokedFn = fn;
          invokedParams = params;
          return {
            'success': true,
            'id': 'inc-uuid-1234',
            'income_id': 'inc-uuid-1234',
            'net_amount': 750.0,
            'new_balance': 2500.0,
          };
        },
      );

      expect(invokedFn, equals('void_income_record'));
      expect(invokedParams, isNotNull);
      expect(invokedParams!['p_income_id'], equals('inc-uuid-1234'));
      expect(res['success'], isTrue);
      expect(res['net_amount'], equals(750.0));
      expect(res['new_balance'], equals(2500.0));
    });

    test('propagates backend errors and exceptions directly to caller', () async {
      final service = AccountService();

      expect(
        () => service.voidIncomeRecord(
          'inc-invalid-id',
          rpcHandler: (fn, params) async {
            throw Exception('Access denied: caller does not belong to the household of this income record');
          },
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Access denied'),
        )),
      );
    });
  });

  group('AccountProvider.voidIncomeRecord Unit Tests', () {
    late _MockAccountServiceForVoid mockService;
    late _MockCommitmentsServiceForVoid mockCommitments;
    late AccountProvider provider;

    setUp(() {
      mockService = _MockAccountServiceForVoid();
      mockCommitments = _MockCommitmentsServiceForVoid();
      provider = AccountProvider(
        accounts: mockService,
        commitments: mockCommitments,
        income: AccountServiceIncomeSource(mockService),
      );
    });

    test('calls AccountService.voidIncomeRecord and triggers full forced refresh', () async {
      // 1. Initial load
      provider.bindHousehold('hh-1', paydayDay: 27);
      await provider.ensureLoaded();

      expect(provider.accounts.length, equals(1));
      expect(provider.accounts.first.balance, equals(1500.0));
      expect(provider.cycleIncomeRecords.length, equals(1));
      expect(provider.cycleIncomeTotal, equals(500.0));

      final initialGetAccountsCalls = mockService.getAccountsCalls;

      // 2. Prepare mock response simulating DB post-reversal state
      mockService.accountsToReturn = [
        Account(
          id: 'acc-1',
          householdId: 'hh-1',
          ownerUserId: 'u-1',
          name: 'Bank Checking',
          accountType: AccountType.bank,
          currency: 'SAR',
          balance: 1000.0, // Reverted 500 SAR
          isSharedPool: true,
          colorHex: '#10B981',
          iconName: 'account_balance',
          isArchived: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      mockService.cycleIncomeToReturn = []; // Deleted row

      // 3. Void income record
      await provider.voidIncomeRecord('inc-test-1', 'hh-1');

      // 4. Assertions
      expect(mockService.voidCalls, contains('inc-test-1'));
      expect(mockService.getAccountsCalls, greaterThan(initialGetAccountsCalls));
      expect(provider.accounts.first.balance, equals(1000.0));
      expect(provider.cycleIncomeRecords, isEmpty);
      expect(provider.cycleIncomeTotal, equals(0.0));
      expect(provider.operatingCash, equals(1000.0));
    });

    test('bubbles exception and does not mutate state when AccountService fails', () async {
      provider.bindHousehold('hh-1', paydayDay: 27);
      await provider.ensureLoaded();

      mockService.shouldThrow = true;

      await expectLater(
        () => provider.voidIncomeRecord('inc-test-1', 'hh-1'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Database rejection'),
        )),
      );

      // Previous valid state preserved
      expect(provider.accounts.first.balance, equals(1500.0));
      expect(provider.cycleIncomeRecords.length, equals(1));
      expect(provider.cycleIncomeTotal, equals(500.0));
    });
  });
}
