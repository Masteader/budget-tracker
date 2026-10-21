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
      expect(find.text('SAR 15,400.00'), findsOneWidget);
      expect(find.text('Al Rajhi Main'), findsOneWidget);

      // Verify clean unmount / cancellation of StreamSubscription without throwing
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
      expect(find.byType(AccountsSummaryCard), findsNothing);
    });
  });
}

