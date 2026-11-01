import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/api_service.dart';
import '../support/localized_app.dart';

class _Failing500ApiService extends ApiService {
  @override
  Future<Map<String, dynamic>> scanReceipt({
    List<String>? imagesBase64,
    String? imageBase64,
    String? qrCodeRaw,
    required String householdId,
    String? userId,
    bool allowDuplicate = false,
    String? enrichTxId,
    bool previewOnly = false,
    String? merchant,
    String? spentBy,
    String? receiptUrl,
    String? paidBy,
    String? beneficiary,
    String? nafaqahClass,
    String? nafaqahSpouseId,
    String? idempotencyKey,
    DateTime? occurredAt,
    String? previewToken,
    double? amount,
    String? categoryCode,
    String? accountId,
  }) async {
    throw Exception('500 Internal Server Error');
  }
}

class _StubAccountService extends AccountService {
  _StubAccountService(this.accounts);
  final List<Account> accounts;

  @override
  Future<List<Account>> getAccounts(String householdId) async => accounts;

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();
}

void main() {
  testWidgets(
      'when the API returns a 5xx without status_code gating, the user-selected account is inserted over the budget-linked one',
      (tester) async {
    final userAcc = Account(
      id: 'acc-user-selected',
      householdId: 'hh-1',
      name: 'User Selected Account',
      accountType: AccountType.bank,
      balance: 1000.0,
      currency: 'SAR',
      ownerUserId: 'u-test',
      isSharedPool: false,
      isArchived: false,
      colorHex: '#10B981',
      iconName: 'account_balance',
      createdAt: DateTime(2026, 1, 1),
    );

    final stubAccounts = _StubAccountService([userAcc]);
    final accountProvider = AccountProvider(accounts: stubAccounts);
    accountProvider.setAccountsForTesting([userAcc], householdId: 'hh-1');

    Map<String, dynamic>? insertedRow;

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: accountProvider,
        child: localizedApp(
          Scaffold(
            body: ReceiptScannerSheet(
              householdId: 'hh-1',
              currentUserId: 'u-test',
              accountService: stubAccounts,
              apiService: _Failing500ApiService(),
              fallbackInsert: (row) async {
                insertedRow = row;
                return {'id': 'tx-fallback-123'};
              },
              initialScanResult: const {
                'status': 'preview',
                'merchant': 'Hyper Panda',
                'amount': 150.0,
                'category_code': 'OPEX-GROCERY',
                'items': [
                  {'name': 'Milk', 'quantity': 1.0, 'price': 150.0}
                ],
              },
            ),
          ),
          scaffold: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('receipt_confirm_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(insertedRow, isNotNull);
    expect(insertedRow!['account_id'], equals('acc-user-selected'));
  });
}
