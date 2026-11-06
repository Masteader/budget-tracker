// Review R1-13 (owner decisions 2026-11-06): each repayment debit, and each
// reversal credit, shows in the paying account's own history, with a clear
// localized label; a former member's line names nobody.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/providers/account_provider.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/accounts/account_activity_sheet.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _bank = Account(
  id: 'a-bank',
  householdId: 'hh',
  ownerUserId: 'u-husband',
  name: 'Al Rajhi',
  accountType: AccountType.bank,
  currency: 'SAR',
  balance: 800,
);
const _cash = Account(
  id: 'a-cash',
  householdId: 'hh',
  ownerUserId: 'u-husband',
  name: 'Wallet cash',
  accountType: AccountType.cash,
  currency: 'SAR',
  balance: 50,
);

final _movements = [
  AccountMovement.fromMap({'id': 'm1', 'from_account_id': 'a-bank', 'to_account_id': null, 'amount': 100, 'fee': 0,
      'timestamp': '2026-11-06T10:00:00Z', 'purpose': 'wife_repayment'}),
  AccountMovement.fromMap({'id': 'm2', 'from_account_id': null, 'to_account_id': 'a-bank', 'amount': 40, 'fee': 0,
      'timestamp': '2026-11-05T10:00:00Z', 'purpose': 'wife_repayment_reversal'}),
  AccountMovement.fromMap({'id': 'm3', 'from_account_id': 'a-bank', 'to_account_id': null, 'amount': 30, 'fee': 0,
      'timestamp': '2026-11-04T10:00:00Z', 'purpose': 'former_member_payment'}),
  AccountMovement.fromMap({'id': 'm4', 'from_account_id': null, 'to_account_id': 'a-bank', 'amount': 30, 'fee': 0,
      'timestamp': '2026-11-03T10:00:00Z', 'purpose': 'former_member_payment_reversal'}),
  AccountMovement.fromMap({'id': 'm5', 'from_account_id': 'a-bank', 'to_account_id': 'a-cash', 'amount': 20, 'fee': 1.5,
      'timestamp': '2026-11-02T10:00:00Z', 'purpose': null}),
  AccountMovement.fromMap({'id': 'm6', 'from_account_id': 'a-other', 'to_account_id': 'a-bank', 'amount': 10, 'fee': 0,
      'timestamp': '2026-11-01T10:00:00Z', 'purpose': null}),
];

Widget _app(Widget home, {String lang = 'en'}) {
  final accounts = AccountProvider()..setAccountsForTesting(const [_bank, _cash], householdId: 'hh');
  return ChangeNotifierProvider<AccountProvider>.value(
    value: accounts,
    child: MaterialApp(
      locale: Locale(lang),
      theme: AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: home),
    ),
  );
}

String _line(WidgetTester tester, String id) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(ValueKey('acct_movement_$id')), matching: find.byType(Text)))
    .first
    .data!;

void main() {
  for (final (lang, expected) in [
    ('en', ['Repayment to wife', 'Repayment reversed', "Paid on a former member's record", 'Former member payment reversed',
        'Transfer to Wallet cash', 'Transfer in']),
    ('ar', ['سداد للزوجة', 'عُكس السداد', 'دفعة على سجل عضوة سابقة', 'عُكست دفعة سجل العضوة السابقة', 'تحويل إلى Wallet cash',
        'تحويل وارد']),
    ('ur', ['اہلیہ کو ادائیگی', 'ادائیگی واپس ہوئی', 'سابق رکن کے ریکارڈ پر ادائیگی', 'سابق رکن کی ادائیگی واپس ہوئی',
        'Wallet cash کو منتقلی', 'اندر منتقلی']),
  ]) {
    testWidgets('$lang: each repayment and reversal shows in the account, labelled, naming nobody', (tester) async {
      await tester.pumpWidget(_app(AccountActivitySheet(account: _bank, householdId: 'hh', load: (_, __) async => _movements), lang: lang));
      await tester.pumpAndSettle();
      for (var i = 0; i < expected.length; i++) {
        expect(_line(tester, 'm${i + 1}'), expected[i]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('money out shows as minus with its fee, money in as plus', (tester) async {
    await tester.pumpWidget(_app(AccountActivitySheet(account: _bank, householdId: 'hh', load: (_, __) async => _movements)));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('acct_movement_m1')), matching: find.textContaining('100.00')), findsOneWidget);
    expect(_movements[0].changeFor('a-bank'), -100);
    expect(_movements[1].changeFor('a-bank'), 40);
    expect(_movements[4].changeFor('a-bank'), -21.5);
    expect(find.descendant(of: find.byKey(const ValueKey('acct_movement_m5')), matching: find.textContaining('Fee')), findsOneWidget);
  });

  testWidgets('nothing yet says so', (tester) async {
    await tester.pumpWidget(_app(AccountActivitySheet(account: _bank, householdId: 'hh', load: (_, __) async => const [])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_activity_empty')), findsOneWidget);
  });

  testWidgets('a failed load is an error with a retry, never "nothing yet"', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(AccountActivitySheet(
      account: _bank,
      householdId: 'hh',
      load: (_, __) async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return _movements;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('acct_activity_empty')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('acct_activity_retry')));
    await tester.pumpAndSettle();
    expect(_line(tester, 'm1'), 'Repayment to wife');
  });

  testWidgets('the account card opens its activity', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const SingleChildScrollView(
      child: AccountCard(account: _bank, committedBudgets: 0, householdId: 'hh'),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('acct_activity_a-bank')));
    await tester.pumpAndSettle();
    expect(find.text('Account activity'), findsOneWidget);
  });
}
