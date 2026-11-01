import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/scanner/receipt_scanner_sheet.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../support/localized_app.dart';

class _FakeReceiptApiService extends ApiService {
  final Map<String, dynamic>? commitResponse;
  _FakeReceiptApiService({this.commitResponse}) : super();
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
    if (!previewOnly) {
      lastCommitArgs = {
        'nafaqah_class': nafaqahClass,
        'nafaqah_spouse_id': nafaqahSpouseId,
        'account_id': accountId,
      };
      return commitResponse ?? {'status': 'success', 'message': 'Saved successfully'};
    }
    return {'status': 'preview'};
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

class _RecordingAccountProvider extends AccountProvider {
  _RecordingAccountProvider({super.accounts});
  int deductExpenseCalls = 0;

  @override
  Future<void> deductExpense({
    String? accountId,
    required double amount,
    String? nafaqahClass,
    String? spouseId,
  }) async {
    deductExpenseCalls++;
    return super.deductExpense(
      accountId: accountId,
      amount: amount,
      nafaqahClass: nafaqahClass,
      spouseId: spouseId,
    );
  }
}

void main() {
  Widget testSheet({
    Map<String, dynamic>? initialScanResult,
    String lang = 'en',
    ApiService? apiService,
    AccountProvider? accountProvider,
  }) {
    final sheet = Scaffold(
      body: ReceiptScannerSheet(
        householdId: 'hh-test-family',
        apiService: apiService,
        initialScanResult: initialScanResult ??
            {
              'status': 'preview',
              'merchant': 'Tamimi Markets',
              'amount': 250.0,
              'category_code': 'OPEX-GROCERY',
              'household_mode': 'family_nafaqah',
              'is_family': true,
              'recorder_role': 'husband',
              'caller_role': 'husband',
              'items': [
                {'name': 'Groceries', 'quantity': 1.0, 'price': 250.0}
              ],
            },
      ),
    );
    if (accountProvider != null) {
      return ChangeNotifierProvider<AccountProvider>.value(
        value: accountProvider,
        child: localizedApp(sheet, scaffold: false, lang: lang),
      );
    }
    return localizedApp(sheet, scaffold: false, lang: lang);
  }

  testWidgets('ReceiptScannerSheet in Family mode: payer has Me and Partner, never Both (Shared)', (tester) async {
    await tester.pumpWidget(testSheet());
    await tester.pumpAndSettle();

    // Verify "Who Paid?" section
    expect(find.byKey(const ValueKey('spent_by_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('spent_by_partner')), findsOneWidget);
    // Rule 02.3: Both (Shared) is NEVER an option for who paid the cashier in Family mode
    expect(find.byKey(const ValueKey('spent_by_both')), findsNothing);
  });

  testWidgets('ReceiptScannerSheet in Family mode: For Whom selector has all beneficiary chips', (tester) async {
    await tester.pumpWidget(testSheet());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('beneficiary_both')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_me')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_partner')), findsOneWidget);
    expect(find.byKey(const ValueKey('beneficiary_children')), findsOneWidget);
  });

  testWidgets('ReceiptScannerSheet live Nafaqah preview: dynamically updates badge based on payer and beneficiary', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'en'));
    await tester.pumpAndSettle();

    // Default: Paid by Me, For Whom = Household -> Paid by Husband
    expect(find.textContaining('Paid by husband — household expense'), findsOneWidget);

    // Tap Paid by Partner (Wife)
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();

    // Now Paid by Partner, For Whom = Household -> Reimbursable Wife Advance
    expect(find.textContaining('Owed to wife:'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('nafaqah_badge_text')), matching: find.textContaining('%')), findsNothing);

    // Tap For Whom = Wife / Partner
    final partnerBeneficiary = find.byKey(const ValueKey('beneficiary_partner'));
    await tester.ensureVisible(partnerBeneficiary);
    await tester.tap(partnerBeneficiary, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Now Paid by Partner, For Whom = Wife -> Wife Personal Allowance
    expect(find.textContaining('From wife\'s personal allowance'), findsOneWidget);
  });

  testWidgets('ReceiptScannerSheet: switching back to Me clears wife nafaqah class without resurrecting stale state', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'en'));
    await tester.pumpAndSettle();

    // Tap Paid by Partner (Wife) + Beneficiary Partner
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();
    final partnerBeneficiary2 = find.byKey(const ValueKey('beneficiary_partner'));
    await tester.ensureVisible(partnerBeneficiary2);
    await tester.tap(partnerBeneficiary2, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('From wife\'s personal allowance'), findsOneWidget);

    // Switch back to Paid by Me
    await tester.ensureVisible(find.byKey(const ValueKey('spent_by_me')));
    await tester.tap(find.byKey(const ValueKey('spent_by_me')));
    await tester.pumpAndSettle();

    // Must show Paid by Husband and NOT resurrect wife_personal!
    expect(find.textContaining('Paid by husband — household expense'), findsOneWidget);
    expect(find.textContaining('From wife\'s personal allowance'), findsNothing);
  });

  testWidgets('ReceiptScannerSheet: Arabic-locale renders dignified Arabic copy', (tester) async {
    await tester.pumpWidget(testSheet(lang: 'ar'));
    await tester.pumpAndSettle();

    // Default: Paid by husband in Arabic
    expect(find.textContaining('دفعه الزوج — مصاريف المنزل'), findsOneWidget);

    // Tap Paid by Partner (Wife)
    await tester.tap(find.byKey(const ValueKey('spent_by_partner')));
    await tester.pumpAndSettle();

    // Reimbursable wife advance in Arabic
    expect(find.textContaining('مستحقات للزوجة:'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('nafaqah_badge_text')), matching: find.textContaining('%')), findsNothing);
  });

  testWidgets('ReceiptScannerSheet: preview without recorder_role/caller_role does not show husband badge and blocks save until class chosen', (tester) async {
    await tester.pumpWidget(testSheet(
      initialScanResult: {
        'status': 'preview',
        'merchant': 'Tamimi Markets',
        'amount': 250.0,
        'category_code': 'OPEX-GROCERY',
        'household_mode': 'family_nafaqah',
        'is_family': true,
        'can_classify': true,
        'wives': [
          {'id': 'w-1', 'display_name': 'Sara'}
        ],
        // No recorder_role or caller_role
        'items': [
          {'name': 'Groceries', 'quantity': 1.0, 'price': 250.0}
        ],
      },
    ));
    await tester.pumpAndSettle();

    // Husband badge must NOT be shown
    expect(find.textContaining('Paid by husband'), findsNothing);

    // Save button should be present
    final saveButton = find.byKey(const ValueKey('receipt_confirm_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Sheet should not have popped (save was blocked) and review section should show
    expect(find.byType(ReceiptScannerSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt_nafaqah_review')), findsOneWidget);
  });

  testWidgets('ReceiptScannerSheet: choosing wife_reimbursable in review section makes commit payload carry nafaqah_class == wife_reimbursable', (tester) async {
    final fakeApi = _FakeReceiptApiService();
    await tester.pumpWidget(testSheet(
      apiService: fakeApi,
      initialScanResult: {
        'status': 'preview',
        'merchant': 'Tamimi Markets',
        'amount': 250.0,
        'category_code': 'OPEX-GROCERY',
        'household_mode': 'family_nafaqah',
        'is_family': true,
        'can_classify': true,
        'wives': [
          {'id': 'w-1', 'display_name': 'Sara'}
        ],
        // No recorder_role or caller_role
        'items': [
          {'name': 'Groceries', 'quantity': 1.0, 'price': 250.0}
        ],
      },
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt_nafaqah_review')), findsOneWidget);

    // Tap the wife reimbursable option
    final reimbOption = find.byKey(const ValueKey('nafaqah_option_wife_reimbursable'));
    await tester.ensureVisible(reimbOption);
    await tester.tap(reimbOption, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Tap confirm save
    final saveButton = find.byKey(const ValueKey('receipt_confirm_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(fakeApi.lastCommitArgs, isNotNull);
    expect(fakeApi.lastCommitArgs!['nafaqah_class'], equals('wife_reimbursable'));
  });

  testWidgets('ReceiptScannerSheet: server returning wife_reimbursable leaves AccountProvider balance unchanged', (tester) async {
    final fakeApi = _FakeReceiptApiService(
      commitResponse: {
        'status': 'success',
        'nafaqah_class': 'wife_reimbursable',
        'account_id': null,
      },
    );
    final householdAcc = Account(
      id: 'acc-main',
      householdId: 'hh-test-family',
      ownerUserId: 'u-h',
      name: 'Household Account',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 1000.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final stubAccounts = _StubAccountService([householdAcc]);
    final accountProvider = _RecordingAccountProvider(accounts: stubAccounts);
    accountProvider.setAccountsForTesting([householdAcc], householdId: 'hh-test-family');

    await tester.pumpWidget(testSheet(
      apiService: fakeApi,
      accountProvider: accountProvider,
      initialScanResult: {
        'status': 'preview',
        'merchant': 'Tamimi Markets',
        'amount': 250.0,
        'category_code': 'OPEX-GROCERY',
        'household_mode': 'family_nafaqah',
        'is_family': true,
        'recorder_role': 'husband',
        'caller_role': 'husband',
        'items': [
          {'name': 'Groceries', 'quantity': 1.0, 'price': 250.0}
        ],
      },
    ));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const ValueKey('receipt_confirm_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(accountProvider.deductExpenseCalls, equals(0));
    expect(accountProvider.accounts.first.balance, equals(1000.0));
  });

  testWidgets('ReceiptScannerSheet: empty item name renders Arabic generic fallback صنف under lang: ar', (tester) async {
    await tester.pumpWidget(testSheet(
      lang: 'ar',
      initialScanResult: {
        'status': 'preview',
        'merchant': 'Tamimi Markets',
        'amount': 50.0,
        'category_code': 'OPEX-GROCERY',
        'household_mode': 'family_nafaqah',
        'is_family': true,
        'recorder_role': 'husband',
        'caller_role': 'husband',
        'items': [
          {'name': '', 'quantity': 1.0, 'price': 50.0}
        ],
      },
    ));
    await tester.pumpAndSettle();

    expect(find.text('صنف'), findsWidgets);
  });
}
