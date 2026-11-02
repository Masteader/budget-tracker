import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/screens/accounts/accounts_overview_screen.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/services/commitments_service.dart';
import '../support/localized_app.dart';

class _FakeAccountServiceForWidget extends AccountService {
  final List<String> voidedIds = [];
  bool shouldFailVoid = false;

  final List<Account> testAccounts;
  final List<IncomeRecord> testIncomeRecords;

  _FakeAccountServiceForWidget({
    required this.testAccounts,
    required this.testIncomeRecords,
  });

  @override
  Future<List<Account>> getAccounts(String householdId) async => testAccounts;

  @override
  Future<double> getHouseholdConfiguredIncome(String householdId) async => 0.0;

  @override
  Future<List<IncomeRecord>> getCycleIncome(String householdId, String cycleKey) async => testIncomeRecords;

  @override
  Future<Map<String, double>> getCommittedBudgetsByAccount(String householdId, String cycleKey) async => {};

  @override
  Future<void> reconcileUnlinkedTransactions(
    String householdId, {
    required bool callerIsAdmin,
    String? currentUserId,
    Future<List<Account>> Function(String p1)? fetchAccounts,
    Future<List<Map<String, dynamic>>> Function(String p1)? fetchUnlinked,
    Future<void> Function(String p1, String p2)? linkTransaction,
  }) async {}

  @override
  Stream<List<Account>> streamAccounts(String householdId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>> voidIncomeRecord(
    String incomeId, {
    Future<dynamic> Function(String fn, Map<String, dynamic> params)? rpcHandler,
  }) async {
    if (shouldFailVoid) {
      throw Exception('Database permission denied (42501)');
    }
    voidedIds.add(incomeId);
    return {'success': true, 'id': incomeId};
  }
}

class _FakeCommitmentsServiceForWidget extends CommitmentsService {
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
  late Account testAccount;
  late IncomeRecord testIncome;

  setUp(() {
    testAccount = Account(
      id: 'acc-checking-1',
      householdId: 'hh-test-1',
      ownerUserId: 'u-1',
      name: 'Al Rajhi Main',
      accountType: AccountType.bank,
      currency: 'SAR',
      balance: 5000.0,
      isSharedPool: true,
      colorHex: '#10B981',
      iconName: 'account_balance',
      isArchived: false,
      createdAt: DateTime(2026, 1, 1),
    );

    testIncome = IncomeRecord(
      id: 'inc-rec-42',
      householdId: 'hh-test-1',
      userId: 'u-1',
      accountId: 'acc-checking-1',
      cycleKey: '2026-11',
      sourceType: IncomeSourceType.salary,
      title: 'November Salary',
      baseAmount: 1500.0,
      receivedAt: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 11, 1),
    );
  });

  Widget buildTestWidget({
    required AccountProvider provider,
    String lang = 'en',
  }) {
    return ChangeNotifierProvider<AccountProvider>.value(
      value: provider,
      child: localizedApp(
        const AccountsOverviewScreen(householdId: 'hh-test-1'),
        lang: lang,
        scaffold: false,
      ),
    );
  }

  testWidgets('renders income row with delete icon, opens dialog, and cancels cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeService = _FakeAccountServiceForWidget(
      testAccounts: [testAccount],
      testIncomeRecords: [testIncome],
    );
    final originalInstance = AccountService.instance;
    AccountService.instance = fakeService;
    addTearDown(() => AccountService.instance = originalInstance);

    final provider = AccountProvider(
      accounts: fakeService,
      commitments: _FakeCommitmentsServiceForWidget(),
      income: AccountServiceIncomeSource(fakeService),
    );
    provider.bindHousehold('hh-test-1', paydayDay: 27);
    await provider.ensureLoaded();

    await tester.pumpWidget(buildTestWidget(provider: provider, lang: 'en'));
    await tester.pumpAndSettle();

    // Verify income title and delete button exist
    expect(find.text('November Salary'), findsOneWidget);
    final deleteBtn = find.byTooltip('Delete Income Record');
    expect(deleteBtn, findsOneWidget);

    // Tap delete button to open confirmation dialog
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Verify dialog content
    expect(find.text('Delete Income Record'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('November Salary')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Al Rajhi Main')),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete & Revert'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Dialog dismissed and void was NOT invoked
    expect(find.text('Delete & Revert'), findsNothing);
    expect(fakeService.voidedIds, isEmpty);
  });

  testWidgets('tapping confirm deletes income record, calls provider, and shows success snackbar', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeService = _FakeAccountServiceForWidget(
      testAccounts: [testAccount],
      testIncomeRecords: [testIncome],
    );
    final originalInstance = AccountService.instance;
    AccountService.instance = fakeService;
    addTearDown(() => AccountService.instance = originalInstance);

    final provider = AccountProvider(
      accounts: fakeService,
      commitments: _FakeCommitmentsServiceForWidget(),
      income: AccountServiceIncomeSource(fakeService),
    );
    provider.bindHousehold('hh-test-1', paydayDay: 27);
    await provider.ensureLoaded();

    await tester.pumpWidget(buildTestWidget(provider: provider, lang: 'en'));
    await tester.pumpAndSettle();

    // Tap delete button
    final deleteBtn = find.byTooltip('Delete Income Record');
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Tap confirm (Delete & Revert)
    await tester.tap(find.text('Delete & Revert'));
    await tester.pumpAndSettle();

    // Dialog dismissed, provider called with correct ID
    expect(find.text('Delete & Revert'), findsNothing);
    expect(fakeService.voidedIds, contains('inc-rec-42'));

    // Success snackbar shown
    expect(find.text('Income record deleted and balance reverted.'), findsOneWidget);
  });

  testWidgets('renders confirmation dialog in Arabic locale with correct typography', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeService = _FakeAccountServiceForWidget(
      testAccounts: [testAccount],
      testIncomeRecords: [testIncome],
    );
    final originalInstance = AccountService.instance;
    AccountService.instance = fakeService;
    addTearDown(() => AccountService.instance = originalInstance);

    final provider = AccountProvider(
      accounts: fakeService,
      commitments: _FakeCommitmentsServiceForWidget(),
      income: AccountServiceIncomeSource(fakeService),
    );
    provider.bindHousehold('hh-test-1', paydayDay: 27);
    await provider.ensureLoaded();

    await tester.pumpWidget(buildTestWidget(provider: provider, lang: 'ar'));
    await tester.pumpAndSettle();

    // Tooltip in Arabic
    final deleteBtn = find.byTooltip('إلغاء تسجيل الدخل');
    expect(deleteBtn, findsOneWidget);

    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Dialog title and action in Arabic
    expect(find.text('إلغاء تسجيل الدخل'), findsOneWidget);
    expect(find.text('حذف وخصم الرصيد'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);

    // Dismiss
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });

  testWidgets('displays error snackbar when voiding fails', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeService = _FakeAccountServiceForWidget(
      testAccounts: [testAccount],
      testIncomeRecords: [testIncome],
    );
    fakeService.shouldFailVoid = true;
    final originalInstance = AccountService.instance;
    AccountService.instance = fakeService;
    addTearDown(() => AccountService.instance = originalInstance);

    final provider = AccountProvider(
      accounts: fakeService,
      commitments: _FakeCommitmentsServiceForWidget(),
      income: AccountServiceIncomeSource(fakeService),
    );
    provider.bindHousehold('hh-test-1', paydayDay: 27);
    await provider.ensureLoaded();

    await tester.pumpWidget(buildTestWidget(provider: provider, lang: 'en'));
    await tester.pumpAndSettle();

    final deleteBtn = find.byTooltip('Delete Income Record');
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete & Revert'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to delete income record'), findsOneWidget);
  });
}
