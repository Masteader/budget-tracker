import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _husband = 'u-husband';
const _wife = 'u-wife';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

NafaqahSummary _summary({
  String role = 'husband',
  double outstanding = 500.5,
  double allocated = 1500,
  double spent = 1700,
  bool isSet = true,
  String mode = 'family_nafaqah',
  double overpaid = 0,
  bool needsProvider = false,
  bool canSetProvider = false,
}) =>
    NafaqahSummary.fromMap({
      'mode': mode,
      'caller_role': role,
      'caller_user_id': role == 'wife' ? _wife : _husband,
      'cycle_key': '2026-11',
      'husband': {'id': _husband, 'display_name': 'Ahmed'},
      'wives': mode == 'family_nafaqah'
          ? [
              {
                'id': _wife,
                'display_name': 'Sara',
                'reimbursement': {
                  'gross_advanced': outstanding + 100,
                  'reimbursed': 100.0,
                  'outstanding': outstanding,
                  'overpaid': overpaid,
                },
                'allowance': {
                  'cycle_key': '2026-11',
                  'is_set': isSet,
                  'allocated': allocated,
                  'spent': spent,
                  'remaining': allocated - spent,
                  'transaction_count': 2,
                },
              }
            ]
          : [],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': role != 'member',
      'provider_user_id': needsProvider ? null : _husband,
      'needs_provider': needsProvider,
      'can_set_provider': canSetProvider,
    });

void main() {
  testWidgets('husband sees what he owes his wife and her allowance overspend', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(householdId: 'hh', summary: _summary())));
    await tester.pumpAndSettle();

    expect(find.text('Husband owes Wife:'), findsOneWidget);
    expect(find.text('SAR 500.50'), findsOneWidget);
    expect(find.text('Reimburse Wife'), findsOneWidget);
    // No spousal split anywhere in family mode.
    expect(find.textContaining('50/50'), findsNothing);
    expect(find.textContaining('Half'), findsNothing);

    expect(find.text("Wife's personal allowance"), findsOneWidget);
    expect(find.text('SAR 1,500.00'), findsOneWidget);
    expect(find.text('SAR 1,700.00'), findsOneWidget);
    expect(find.text('SAR -200.00'), findsOneWidget);
    expect(find.text('Over the allowance by SAR 200.00'), findsOneWidget);
    expect(find.text('Change allowance'), findsOneWidget);
  });

  testWidgets('wife sees her claim, records receipt, cannot set her allowance', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(role: 'wife', allocated: 800, spent: 300),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Your husband owes you:'), findsOneWidget);
    expect(find.text('Record amount received'), findsOneWidget);
    expect(find.text('My personal allowance'), findsOneWidget);
    expect(find.text('SAR 500.00'), findsOneWidget); // remaining 800 - 300
    expect(find.text('Set by the husband or a household admin.'), findsOneWidget);
    expect(find.text('Change allowance'), findsNothing);
    expect(find.text('Set allowance'), findsNothing);
  });

  testWidgets('partial reimbursement is recorded for the wife and the card reloads', (tester) async {
    final calls = <Map<String, Object>>[];
    var loads = 0;
    var reimbursed = false;
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(),
      onReimbursed: () => reimbursed = true,
      loadSummary: (_) async {
        loads++;
        return _summary(outstanding: 300.5);
      },
      recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) async {
        calls.add({'amount': amount, 'method': paymentMethod, 'wife': wifeUserId});
        return 300.5;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();
    expect(find.text('Settle Wife Reimbursement'), findsOneWidget);
    expect(find.text('Full (SAR 500.50)'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('reimburse_amount_field')), '200');
    await tester.tap(find.text('Cash'));
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(calls, [
      {'amount': 200.0, 'method': 'cash', 'wife': _wife}
    ]);
    expect(reimbursed, isTrue);
    expect(loads, 1);
    expect(find.text('SAR 300.50'), findsOneWidget);
  });

  testWidgets('a third decimal is rounded half-up from the typed text and shown (FABLE-LOGIC-09)', (tester) async {
    final amounts = <double>[];
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(),
      loadSummary: (_) async => _summary(),
      recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) async {
        amounts.add(amount);
        return 0;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reimburse_amount_field')), '٠٫٢٨٥');
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pump();
    expect(find.text('0.29'), findsOneWidget, reason: 'the field shows the stored, rounded amount');
    await tester.pumpAndSettle();
    expect(amounts, [0.29]);
  });

  testWidgets('overpayment is refused before reaching the server', (tester) async {
    var called = false;
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(),
      recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) async {
        called = true;
        return 0;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reimburse_amount_field')), '500.51');
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('That is more than the outstanding balance (SAR 500.50).'), findsOneWidget);
    expect(find.text('Settle Wife Reimbursement'), findsOneWidget);
  });

  testWidgets('a server-side overpayment rejection is reported, never as success', (tester) async {
    var reimbursed = false;
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(),
      onReimbursed: () => reimbursed = true,
      recordReimbursement: ({required double amount, required String paymentMethod, required String wifeUserId}) async =>
          throw const NafaqahApiException('overpayment', 'exceeds', statusCode: 409),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reimburse Wife'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record Settlement Payment'));
    await tester.pumpAndSettle();

    expect(reimbursed, isFalse);
    expect(find.text('Settlement Failed'), findsOneWidget);
    expect(find.text('That is more than the outstanding balance (SAR 500.50).'), findsOneWidget);
  });

  // FABLE-LOGIC-02: repayments above the advances (an advance cut after it was
  // repaid, before the ledger guard) are shown, never hidden behind "settled".
  testWidgets('an overpaid ledger shows how much was repaid beyond the advances', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(outstanding: 0, overpaid: 100),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Repaid more than advanced by SAR 100.00'), findsOneWidget);
    expect(find.text('An advance was reduced or deleted after it had been repaid.'), findsOneWidget);
    expect(find.text('Reimburse Wife'), findsNothing);
  });

  testWidgets('no overpaid line when the ledger is consistent', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(householdId: 'hh', summary: _summary(outstanding: 0))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Repaid more than advanced'), findsNothing);
    expect(find.byKey(const ValueKey('nafaqah_needs_provider')), findsNothing);
  });

  // FABLE-LOGIC-04: a family without a Nafaqah provider is told who can fix it.
  testWidgets('a family without a provider asks to have one set', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(role: 'wife', needsProvider: true),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nafaqah_needs_provider')), findsOneWidget);
    expect(find.text('This family has no Nafaqah provider (husband). Ask an admin to set one.'), findsOneWidget);

    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh2',
      summary: _summary(role: 'member', needsProvider: true, canSetProvider: true),
    )));
    await tester.pumpAndSettle();
    expect(
      find.text('This family has no Nafaqah provider (husband). Choose one in Settings, under Members & Admins.'),
      findsOneWidget,
    );
  });

  testWidgets('settled balance hides the reimburse action', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(householdId: 'hh', summary: _summary(outstanding: 0))));
    await tester.pumpAndSettle();

    expect(find.text('All Settled'), findsOneWidget);
    expect(find.text('Reimburse Wife'), findsNothing);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('husband sets the allowance for the cycle', (tester) async {
    final saved = <List<Object?>>[];
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(isSet: false, allocated: 0, spent: 99),
      loadSummary: (_) async => _summary(allocated: 1200, spent: 99),
      setAllowance: ({required double amount, required String wifeUserId, String? cycleKey}) async {
        saved.add([amount, wifeUserId, cycleKey]);
        return const AllowanceStatus(cycleKey: '2026-11', isSet: true, allocated: 1200, spent: 99, remaining: 1101);
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('No allowance is set for this cycle; personal purchases are tracked without a limit.'), findsOneWidget);
    expect(find.textContaining('Her personal spending this cycle'), findsOneWidget);
    await tester.tap(find.text('Set allowance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('allowance_amount_field')), '1200');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, [
      [1200.0, _wife, '2026-11']
    ]);
    expect(find.text('SAR 1,101.00'), findsOneWidget);
  });

  testWidgets('history lists advances and repayments', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(
      householdId: 'hh',
      summary: _summary(),
      loadLedger: (_, wifeId) async => NafaqahLedger.fromMap({
        'balance': {'gross_advanced': 600.5, 'reimbursed': 100, 'outstanding': 500.5},
        'history': [
          {'type': 'reimbursement', 'id': 'r1', 'amount': 100, 'payment_method': 'cash', 'timestamp': '2026-11-15T10:00:00Z'},
          {'type': 'advance', 'id': 't1', 'amount': 300, 'merchant': 'Panda', 'timestamp': '2026-11-10T09:00:00Z'},
        ],
      }),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Reimbursement history'), findsOneWidget);
    expect(find.text('Wife paid: Panda'), findsOneWidget);
    expect(find.text('Reimbursed via Cash'), findsOneWidget);
    expect(find.text('+SAR 300.00'), findsOneWidget);
  });

  testWidgets('renders nothing outside family mode (roommates keep their own card)', (tester) async {
    await tester.pumpWidget(_app(FamilyReimbursementCard(householdId: 'hh', summary: _summary(mode: 'not_family'))));
    await tester.pumpAndSettle();

    expect(find.text('Family Expenses & Nafaqah'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('Arabic family card is RTL with riyal amounts', (tester) async {
    await tester.pumpWidget(_app(
      FamilyReimbursementCard(householdId: 'hh', summary: _summary()),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();

    final dir = Directionality.of(tester.element(find.byType(FamilyReimbursementCard)));
    expect(dir, TextDirection.rtl);
    expect(find.text('مصروف الزوجة الشخصي'), findsOneWidget);
    expect(find.text('500.50 ر.س'), findsOneWidget);
    expect(find.textContaining('SAR'), findsNothing);
  });
}
