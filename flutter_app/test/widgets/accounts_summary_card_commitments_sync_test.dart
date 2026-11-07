import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/operating_cash.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/widgets/dashboard/accounts_summary_card.dart';
import 'package:budget_tracker/widgets/dashboard/budget_hero_card.dart';

class _FakeAccountService extends AccountService {
  final StreamController<List<Account>> _controller = StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> streamAccounts(String householdId) => _controller.stream;

  /// When true, fetches never complete, like a slow network for a new household.
  bool holdFetches = false;

  @override
  Future<List<Account>> getAccounts(String householdId) =>
      holdFetches ? Completer<List<Account>>().future : Future.value(<Account>[]);

  void emit(List<Account> accounts) => _controller.add(accounts);
  void close() => _controller.close();
}

class _TestAccountProvider extends ChangeNotifier implements AccountProvider {
  final OperatingCashSnapshot _snapshot;
  final bool _hasLoaded;
  final List<Account> _accounts;

  _TestAccountProvider({
    required OperatingCashSnapshot snapshot,
    bool hasLoaded = true,
    List<Account> accounts = const [],
  })  : _snapshot = snapshot,
        _hasLoaded = hasLoaded,
        _accounts = accounts;

  @override
  OperatingCashSnapshot get snapshot => _snapshot;

  @override
  OperatingCashSnapshot get operatingCashSnapshot => _snapshot;

  @override
  bool get hasLoaded => _hasLoaded;

  @override
  String? get householdId => 'h1';

  @override
  List<Account> get accounts => _accounts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AccountsSummaryCard Commitments SSOT & Hero Sync Tests (Issue 1)', () {
    late _FakeAccountService fakeService;

    setUp(() {
      fakeService = _FakeAccountService();
      AccountService.instance = fakeService;
    });

    tearDown(() {
      fakeService.close();
      AccountService.instance = AccountService();
    });

    testWidgets('AccountsSummaryCard consumes snapshot.pendingCommitments as SSOT matching BudgetHeroCard', (tester) async {
      // User scenario:
      // Accounts: Total liquidity = 3,353.75 SAR (e.g. Rajhi 2,508.75 + Cash 845.00)
      // Active cycle commitments = 1,162.00 SAR (116,200 halalas)
      // Card must display SAR 1,162.00 commitments and actual available 2,191.75 SAR (3353.75 - 1162.00)
      const cycleKey = '2026-11';
      const snapshot = OperatingCashSnapshot(
        householdId: 'h1',
        cycleKey: cycleKey,
        liquidHalalas: 335375, // 3,353.75 SAR
        pendingCommitmentsHalalas: 116200, // 1,162.00 SAR
        cycleIncomeHalalas: 894454,
        accountsCount: 2,
      );

      final accountsList = [
        const Account(
          id: 'acc-rajhi',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Al Rajhi',
          accountType: AccountType.bank,
          balance: 2508.75,
        ),
        const Account(
          id: 'acc-cash',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Cash Wallet',
          accountType: AccountType.cash,
          balance: 845.00,
        ),
      ];

      final provider = _TestAccountProvider(
        snapshot: snapshot,
        hasLoaded: true,
        accounts: accountsList,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccountProvider>.value(value: provider),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            locale: const Locale('en'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    BudgetHeroCard(
                      budgets: const [],
                      monthlyIncome: snapshot.cycleIncome,
                      operatingCash: snapshot.liquidBalance,
                      snapshot: snapshot,
                      pendingCommitments: snapshot.pendingCommitments,
                    ),
                    const AccountsSummaryCard(householdId: 'h1'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Emit stream data after listener subscription in initState
      fakeService.emit(accountsList);
      await tester.pumpAndSettle();

      // Total liquidity headline: 3,353.75 SAR
      expect(find.text('3,353.75'), findsWidgets);

      // Verify commitments tip in AccountsSummaryCard:
      // actual available: 3,353.75 - 1,162.00 = 2,191.75
      // commitments: 1,162.00
      expect(find.byKey(const Key('accounts_commitments_tip')), findsOneWidget);
      expect(find.textContaining('1,162.00'), findsWidgets);
      expect(find.textContaining('2,191.75'), findsWidgets);

      // Verify that the unfiltered 3,027.00 does NOT appear anywhere
      expect(find.textContaining('3,027'), findsNothing);

      // Verify BudgetHeroCard and AccountsSummaryCard both reflect 1,162.00 commitments
      expect(find.byKey(const Key('hero_commitments_tip')), findsOneWidget);
    });

    testWidgets('AccountsSummaryCard respects snapshotOverride when passed explicitly', (tester) async {
      const snapshot = OperatingCashSnapshot(
        householdId: 'h1',
        cycleKey: '2026-11',
        liquidHalalas: 500000,
        pendingCommitmentsHalalas: 116200, // 1,162.00 SAR
        cycleIncomeHalalas: 0,
        accountsCount: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: AccountsSummaryCard(
              householdId: 'h1',
              snapshotOverride: snapshot,
            ),
          ),
        ),
      );
      await tester.pump();

      fakeService.emit([
        const Account(
          id: 'acc-1',
          householdId: 'h1',
          ownerUserId: 'u1',
          name: 'Main Bank',
          accountType: AccountType.bank,
          balance: 5000.0,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accounts_commitments_tip')), findsOneWidget);
      // Available = 5000 - 1162 = 3838
      expect(find.textContaining('3,838.00'), findsOneWidget);
      expect(find.textContaining('1,162.00'), findsOneWidget);
    });

    testWidgets(
        'AccountsSummaryCard follows AccountProvider balances after a transaction '
        'even when the realtime stream never emits', (tester) async {
      Account acc(String id, String name, double balance) => Account(
            id: id,
            householdId: 'h1',
            ownerUserId: 'u1',
            name: name,
            accountType: AccountType.bank,
            balance: balance,
          );

      final provider = AccountProvider(accounts: fakeService)
        ..setAccountsForTesting(
          [acc('a1', 'Bank', 1000), acc('a2', 'Cash', 200)],
          householdId: 'h1',
          cycleKey: '2026-11',
          commitments: const [],
          cycleIncomeHalalas: 0,
        );

      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: provider,
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            locale: Locale('en'),
            home: Scaffold(body: AccountsSummaryCard(householdId: 'h1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1,200.00', findRichText: true), findsOneWidget);

      // Expense of 150 from Bank: provider refreshes, realtime stays silent.
      provider.setAccountsForTesting(
        [acc('a1', 'Bank', 850), acc('a2', 'Cash', 200)],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1,050.00', findRichText: true), findsOneWidget);
      expect(find.textContaining('1,200.00', findRichText: true), findsNothing);
    });

    Account acc(String id, String hid, String name, double balance) => Account(
          id: id,
          householdId: hid,
          ownerUserId: 'u1',
          name: name,
          accountType: AccountType.bank,
          balance: balance,
        );

    Widget app(AccountProvider provider, String hid) => ChangeNotifierProvider<AccountProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            locale: const Locale('en'),
            home: Scaffold(body: AccountsSummaryCard(householdId: hid)),
          ),
        );

    testWidgets('AccountsSummaryCard ignores AccountProvider bound to another household '
        'and shows its own household from the fallback stream', (tester) async {
      final provider = AccountProvider(accounts: fakeService)
        ..setAccountsForTesting(
          [acc('x1', 'other', 'Other', 9999)],
          householdId: 'other',
          cycleKey: '2026-11',
          commitments: const [],
          cycleIncomeHalalas: 0,
        );

      await tester.pumpWidget(app(provider, 'h1'));
      await tester.pump();
      fakeService.emit([acc('a1', 'h1', 'Bank', 300)]);
      await tester.pumpAndSettle();

      expect(find.textContaining('300.00', findRichText: true), findsWidgets);
      expect(find.textContaining('9,999.00', findRichText: true), findsNothing);
    });

    testWidgets('AccountsSummaryCard falls back to its stream while AccountProvider has not loaded',
        (tester) async {
      final provider = AccountProvider(accounts: fakeService);
      expect(provider.hasLoaded, isFalse);

      await tester.pumpWidget(app(provider, 'h1'));
      await tester.pump();
      fakeService.emit([acc('a1', 'h1', 'Bank', 500)]);
      await tester.pumpAndSettle();

      expect(find.textContaining('500.00', findRichText: true), findsWidgets);
    });

    testWidgets('AccountsSummaryCard drops the previous household balances on household switch',
        (tester) async {
      final provider = AccountProvider(accounts: fakeService);

      await tester.pumpWidget(app(provider, 'h1'));
      await tester.pump();
      fakeService.emit([acc('a1', 'h1', 'Bank', 700)]);
      await tester.pumpAndSettle();
      expect(find.textContaining('700.00', findRichText: true), findsWidgets);

      fakeService.holdFetches = true; // h2 is still loading
      await tester.pumpWidget(app(provider, 'h2'));
      await tester.pump();

      expect(find.textContaining('700.00', findRichText: true), findsNothing);
    });
  });
}
