import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/api_service.dart';
import '../support/localized_app.dart';

class _RecordingApiService extends ApiService {
  Map<String, dynamic>? lastCommitArgs;

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
    lastCommitArgs = {
      'accountId': accountId,
      'previewOnly': previewOnly,
      'amount': amount,
    };
    return {
      'status': 'success',
      'account_id': accountId,
      'message': 'Saved',
    };
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
      'ReceiptScannerSheet: non-admin member sees only own accounts, not shared pool in dropdown, and commit uses own account',
      (tester) async {
    final sharedPool = Account(
      id: 'acc-shared-pool',
      householdId: 'hh-1',
      name: 'Shared Family Pool',
      accountType: AccountType.bank,
      balance: 5000.0,
      currency: 'SAR',
      ownerUserId: 'u-admin-husband',
      isSharedPool: true,
      isArchived: false,
      colorHex: '#10B981',
      iconName: 'account_balance',
      createdAt: DateTime(2026, 1, 1),
    );

    final memberOwnAcc = Account(
      id: 'acc-member-own',
      householdId: 'hh-1',
      name: 'Wife Personal Wallet',
      accountType: AccountType.bank,
      balance: 1500.0,
      currency: 'SAR',
      ownerUserId: 'u-member-wife',
      isSharedPool: false,
      isArchived: false,
      colorHex: '#3B82F6',
      iconName: 'wallet',
      createdAt: DateTime(2026, 1, 1),
    );

    final stubAccounts = _StubAccountService([sharedPool, memberOwnAcc]);
    final accountProvider = AccountProvider(accounts: stubAccounts);
    accountProvider.setAccountsForTesting([sharedPool, memberOwnAcc], householdId: 'hh-1');

    final apiService = _RecordingApiService();

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountProvider>.value(
        value: accountProvider,
        child: localizedApp(
          Scaffold(
            body: ReceiptScannerSheet(
              householdId: 'hh-1',
              currentUserId: 'u-member-wife',
              accountService: stubAccounts,
              apiService: apiService,
              initialScanResult: const {
                'status': 'preview',
                'merchant': 'Panda Supermarket',
                'amount': 120.0,
                'category_code': 'OPEX-GROCERY',
                'items': [
                  {'name': 'Bread', 'quantity': 1.0, 'price': 120.0}
                ],
              },
            ),
          ),
          scaffold: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdownFinder = find.byKey(const ValueKey('store_attribution_account_dropdown'));
    await tester.ensureVisible(dropdownFinder);
    await tester.pumpAndSettle();

    // Verify Shared Family Pool is absent from UI
    expect(find.textContaining('Shared Family Pool'), findsNothing);
    // Verify Wife Personal Wallet is visible as selected
    expect(find.textContaining('Wife Personal Wallet'), findsOneWidget);

    final saveButton = find.byKey(const ValueKey('receipt_confirm_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(apiService.lastCommitArgs, isNotNull);
    expect(apiService.lastCommitArgs!['accountId'], equals('acc-member-own'));
  });
}
