// UX-22: the deficit action is an amber outlined "cover the shortfall" button
// (not a full-width solid red, destructive-looking one), and riyal amounts go
// through the riyal formatter ("700.00 ر.س", not "SAR 700.00" in Arabic).
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/widgets/accounts/account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Account account, double committed, Locale locale) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountCard(account: account, committedBudgets: committed, householdId: 'hh-1'),
        ),
      ),
    );

const _stc = Account(
  id: 'acc-2',
  householdId: 'hh-1',
  ownerUserId: 'u-1',
  name: 'STC Pay',
  accountType: AccountType.eWallet,
  balance: 500.0,
);

void main() {
  testWidgets('Arabic deficit: amber outlined cover action, riyal amounts', (tester) async {
    await tester.pumpWidget(_app(_stc, 1200, const Locale('ar')));
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('account_cover_deficit'));
    expect(action, findsOneWidget);
    expect(tester.widget(action), isA<OutlinedButton>());
    expect(find.text('تحويل سريع لتغطية العجز (700.00 ر.س)'), findsOneWidget);
    expect(find.text('500.00 ر.س'), findsOneWidget);
    expect(find.textContaining('SAR'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing, reason: 'no solid red button');
  });

  testWidgets('English deficit keeps the quick-transfer wording', (tester) async {
    await tester.pumpWidget(_app(_stc, 1200, const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Quick transfer to cover the shortfall (SAR 700.00)'), findsOneWidget);
    expect(find.textContaining('Deficit: -SAR 700.00'), findsOneWidget);
  });

  testWidgets('a crypto account keeps its own currency', (tester) async {
    const binance = Account(
      id: 'acc-3',
      householdId: 'hh-1',
      ownerUserId: 'u-1',
      name: 'Binance',
      accountType: AccountType.crypto,
      currency: 'USDT',
      balance: 100.0,
    );
    await tester.pumpWidget(_app(binance, 0, const Locale('ar')));
    await tester.pumpAndSettle();
    expect(find.text('USDT 100.00'), findsOneWidget);
  });
}
