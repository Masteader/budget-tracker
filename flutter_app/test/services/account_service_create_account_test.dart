import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';

class _RecordingAccountService extends AccountService {
  int logIncomeCalls = 0;

  @override
  Future<IncomeRecord> logIncome({
    required String householdId,
    required String accountId,
    required String cycleKey,
    required IncomeSourceType sourceType,
    required String title,
    required double baseAmount,
    double overtime = 0.0,
    double bonus = 0.0,
    double deductions = 0.0,
    DateTime? receivedAt,
    String? notes,
  }) async {
    logIncomeCalls++;
    return IncomeRecord(
      id: 'inc-1',
      householdId: householdId,
      userId: 'user-1',
      accountId: accountId,
      cycleKey: cycleKey,
      sourceType: sourceType,
      title: title,
      baseAmount: baseAmount,
      receivedAt: receivedAt ?? DateTime.now(),
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  group('AccountService.createAccount', () {
    test('createAccount with initialBalance: 1000 performs exactly one accounts insert with balance: 1000 and 0 logIncome calls', () async {
      final service = _RecordingAccountService();
      Map<String, dynamic>? insertedRow;

      final acc = await service.createAccount(
        householdId: 'hh-123',
        name: 'Savings Account',
        accountType: AccountType.savings,
        initialBalance: 1000.0,
        insertAccountRow: (row) async {
          insertedRow = row;
          return {
            'id': 'acc-new-1',
            ...row,
            'created_at': DateTime.now().toIso8601String(),
          };
        },
      );

      expect(insertedRow, isNotNull);
      expect(insertedRow!['household_id'], equals('hh-123'));
      expect(insertedRow!['name'], equals('Savings Account'));
      expect(insertedRow!['account_type'], equals('savings'));
      expect(insertedRow!['balance'], equals(1000.0));
      expect(acc.balance, equals(1000.0));

      // Rule 02 & Rule 03: opening balance is NOT logged as cycle income
      expect(service.logIncomeCalls, equals(0));
    });
  });
}
