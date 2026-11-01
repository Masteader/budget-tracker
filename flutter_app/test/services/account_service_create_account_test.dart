import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';

class _FakeAccountServiceWithCycleKeyCapture extends AccountService {
  String? capturedCycleKey;
  Map<String, dynamic>? capturedRecordIncomeParams;

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
    capturedCycleKey = cycleKey;
    capturedRecordIncomeParams = {
      'p_household_id': householdId,
      'p_account_id': accountId,
      'p_cycle_key': cycleKey,
      'p_source_type': sourceType.name,
      'p_title': title,
      'p_base_amount': baseAmount,
    };
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
  group('AccountService.createAccount cycle_key', () {
    test('payday 10 on 12 Oct 2026 yields p_cycle_key == 2026-10', () async {
      final oct12 = DateTime.utc(2026, 10, 12, 10, 0, 0);
      final key = SalaryCycleService.cycleKeyForInstant(oct12, paydayDay: 10);
      expect(key, equals('2026-10'));

      final fakeService = _FakeAccountServiceWithCycleKeyCapture();
      await fakeService.logIncome(
        householdId: 'hh-1',
        accountId: 'acc-1',
        cycleKey: key,
        sourceType: IncomeSourceType.other,
        title: 'Opening Balance - Test',
        baseAmount: 1000.0,
      );

      expect(fakeService.capturedCycleKey, equals('2026-10'));
      expect(fakeService.capturedRecordIncomeParams?['p_cycle_key'], equals('2026-10'));
    });
  });
}
