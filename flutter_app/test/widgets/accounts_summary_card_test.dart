import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/services/account_service.dart';
import 'package:budget_tracker/widgets/dashboard/accounts_summary_card.dart';

class FakeAccountService extends AccountService {
  final StreamController<List<Account>> _controller = StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> streamAccounts(String householdId) => _controller.stream;

  @override
  Future<List<Account>> getAccounts(String householdId) async => [];

  void emit(List<Account> accounts) {
    _controller.add(accounts);
  }

  void close() {
    _controller.close();
  }
}

void main() {
  group('AccountsSummaryCard Widget Tests', () {
    late FakeAccountService fakeService;

    setUp(() {
      fakeService = FakeAccountService();
      AccountService.instance = fakeService;
    });

    tearDown(() {
      fakeService.close();
      AccountService.instance = AccountService();
    });

    testWidgets('Initializes with subscription, renders data on emit, and disposes cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(
            body: AccountsSummaryCard(householdId: 'test-household-id'),
          ),
        ),
      );
      await tester.pump();

      // Initially empty accounts list returns SizedBox.shrink()
      expect(find.byType(AccountsSummaryCard), findsOneWidget);
      expect(find.text('Accounts & Liquidity'), findsNothing);

      // Emit account data from the stream
      fakeService.emit([
        const Account(
          id: 'acc-1',
          householdId: 'test-household-id',
          ownerUserId: 'u-1',
          name: 'Al Rajhi Main',
          accountType: AccountType.bank,
          balance: 15400.0,
        ),
      ]);
      await tester.pump();

      // Card is now rendered with total liquidity
      expect(find.text('Accounts & Balances'), findsOneWidget);
      // Shown twice: the total-liquidity headline (one Text.rich so the
      // unit can sit on the locale-appropriate side) and the account pill.
      expect(find.text('SAR 15,400.00'), findsNWidgets(2));
      expect(find.text('Al Rajhi Main'), findsOneWidget);

      // Verify clean unmount / cancellation of StreamSubscription without throwing
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
      expect(find.byType(AccountsSummaryCard), findsNothing);
    });

    testWidgets('minAccounts hides the card on the dashboard until there are two accounts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [AppLocalizationsDelegate()],
          home: Scaffold(body: AccountsSummaryCard(householdId: 'h', minAccounts: 2)),
        ),
      );
      await tester.pump();
      const one = Account(id: 'a1', householdId: 'h', ownerUserId: 'u', name: 'Cash', accountType: AccountType.cash, balance: 100);
      const two = Account(id: 'a2', householdId: 'h', ownerUserId: 'u', name: 'STC Pay', accountType: AccountType.eWallet, balance: 50);
      fakeService.emit([one]);
      await tester.pump();
      expect(find.text('Accounts & Balances'), findsNothing);
      fakeService.emit([one, two]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Accounts & Balances'), findsOneWidget);
    });
  });
}

