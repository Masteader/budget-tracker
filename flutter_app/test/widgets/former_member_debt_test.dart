// A wife who deletes her account leaves one anonymised record per household of
// what she was still owed. The husband (provider) or an admin closes it by
// recording payments or her waiver (إبراء); every member sees it, and the
// husband is warned with the amount before her deletion takes effect.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/theme/app_themes.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/payer_account.dart';

const _husband = 'u-husband';
const _wife = 'u-wife';
final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

Widget _app(
  Widget child, {
  String lang = 'en',
  bool dark = false,
  double scale = 1.0,
}) =>
    withPayerAccount(MaterialApp(
      locale: Locale(lang),
      theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: page!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));

Map<String, dynamic> _openDebt({String id = 'd-open', double original = 900, double paid = 500}) => {
      'id': id,
      'original_amount': original,
      'paid_amount': paid,
      'remaining': original - paid,
      'status': 'open',
      'created_at': '2026-11-01T09:00:00Z',
      'closed_at': null,
      'events': [
        {'kind': 'payment', 'amount': paid, 'payment_method': 'cash', 'remaining_after': original - paid, 'created_at': '2026-11-02T09:00:00Z'},
      ],
    };

const _settledDebt = {
  'id': 'd-settled',
  'original_amount': 300,
  'paid_amount': 300,
  'remaining': 0,
  'status': 'settled',
  'created_at': '2026-10-01T09:00:00Z',
  'closed_at': '2026-10-20T10:00:00Z',
  'events': [
    {'kind': 'payment', 'amount': 100, 'payment_method': 'bank_transfer', 'remaining_after': 200, 'created_at': '2026-10-10T09:00:00Z'},
    {'kind': 'payment', 'amount': 200, 'payment_method': 'stc_pay', 'remaining_after': 0, 'created_at': '2026-10-20T10:00:00Z'},
  ],
};

const _waivedDebt = {
  'id': 'd-waived',
  'original_amount': 250,
  'paid_amount': 50,
  'remaining': 0,
  'status': 'waived',
  'created_at': '2026-09-01T09:00:00Z',
  'closed_at': '2026-09-15T10:00:00Z',
  'events': [
    {'kind': 'payment', 'amount': 50, 'payment_method': 'cash', 'remaining_after': 200, 'created_at': '2026-09-05T09:00:00Z'},
    {'kind': 'waiver', 'amount': 200, 'payment_method': null, 'remaining_after': 0, 'created_at': '2026-09-15T10:00:00Z'},
  ],
};

final _deletionDate = DateTime.utc(2026, 12, 5, 10);

NafaqahSummary _summary({
  List<Map<String, dynamic>>? debts,
  bool canManage = true,
  bool withWife = true,
  Map<String, dynamic>? pendingDeletion,
  String role = 'husband',
  String? wifeName = 'Sara',
}) =>
    NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': role,
      'caller_user_id': role == 'wife' ? _wife : _husband,
      'cycle_key': '2026-11',
      'husband': {'id': _husband, 'display_name': 'Ahmed'},
      'wives': withWife
          ? [
              {
                'id': _wife,
                'display_name': wifeName,
                'reimbursement': {'gross_advanced': 486.4, 'reimbursed': 100, 'outstanding': 386.4},
                'allowance': {'cycle_key': '2026-11', 'is_set': true, 'allocated': 1000, 'spent': 645, 'remaining': 355},
                'pending_deletion': pendingDeletion,
              }
            ]
          : [],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': role != 'member',
      'provider_user_id': _husband,
      'needs_provider': false,
      'can_set_provider': false,
      'former_member_debts': debts ?? [_openDebt()],
      'can_manage_former_member_debts': canManage,
    });

typedef _PayCall = ({String debtId, double amount, String paymentMethod, String requestKey});

Finder _k(String key) => find.byKey(ValueKey(key));

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.pumpAndSettle();
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

String _d(String lang, String iso, String pattern) => AppLocalizations(Locale(lang)).date(DateTime.parse(iso).toLocal(), pattern);

void main() {
  group('parsing', () {
    test('records, events, the manager flag and a pending deletion', () {
      final s = _summary(
        debts: [_openDebt(), _settledDebt, _waivedDebt],
        pendingDeletion: {'scheduled_for': _deletionDate.toIso8601String(), 'outstanding': 386.4},
      );
      expect(s.canManageFormerMemberDebts, isTrue);
      expect(s.formerMemberDebts.map((d) => d.id), ['d-open', 'd-settled', 'd-waived']);

      final open = s.formerMemberDebts.first;
      expect(open.originalAmount, 900);
      expect(open.paidAmount, 500);
      expect(open.remaining, 400);
      expect(open.isOpen, isTrue);
      expect(open.closedAt, isNull);
      expect(open.createdAt, DateTime.parse('2026-11-01T09:00:00Z').toLocal());
      expect(open.events.single.isWaiver, isFalse);
      expect(open.events.single.paymentMethod, 'cash');

      final waived = s.formerMemberDebts[2];
      expect(waived.isWaived, isTrue);
      expect(waived.isOpen, isFalse);
      expect(waived.waivedAmount, 200);
      expect(waived.events.last.isWaiver, isTrue);
      expect(waived.events.last.paymentMethod, isNull);
      expect(waived.events.last.remainingAfter, 0);
      expect(waived.closedAt, DateTime.parse('2026-09-15T10:00:00Z').toLocal());
      expect(s.formerMemberDebts[1].isSettled, isTrue);

      final pending = s.wives.single.pendingDeletion!;
      expect(pending.scheduledFor, _deletionDate.toLocal());
      expect(pending.outstanding, 386.4);
    });

    test('missing keys are empty, false and null', () {
      final s = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'wives': [
          {'id': 'w'}
        ],
      });
      expect(s.formerMemberDebts, isEmpty);
      expect(s.canManageFormerMemberDebts, isFalse);
      expect(s.wives.single.pendingDeletion, isNull);
    });

    test('a malformed record or notice is never read as open or due', () {
      final s = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'wives': [
          {'id': 'w', 'pending_deletion': {'outstanding': 10}},
        ],
        'former_member_debts': [
          {'id': 'x', 'original_amount': 100, 'paid_amount': 40, 'status': 'archived', 'events': 'nope'},
          'junk',
          {'original_amount': 5, 'status': 'open'},
        ],
      });
      expect(s.wives.single.pendingDeletion, isNull, reason: 'no date, no notice');
      final d = s.formerMemberDebts.single;
      expect(d.id, 'x');
      expect(d.isOpen, isFalse, reason: 'an unknown status offers no action');
      expect(d.remaining, 60, reason: 'remaining falls back to original - paid');
      expect(d.events, isEmpty);
    });

    test('the API errors of the record are state codes', () {
      NafaqahApiException err(int status, String code, [Map<String, dynamic> extra = const {}]) => NafaqahApiException.fromResponse({
            'status': 'error',
            'status_code': status,
            'detail': {'code': code, 'message': 'x', ...extra},
          });
      expect(err(409, 'debt_closed').code, 'debt_closed');
      expect(err(404, 'debt_not_found').code, 'debt_not_found');
      expect(err(404, 'debt_not_found').outcomeUnknown, isFalse);
      expect(err(409, 'request_key_reused').code, 'request_key_reused');
      final over = err(409, 'overpayment', {'outstanding': 120.5});
      expect(over.code, 'overpayment');
      expect(over.outstanding, 120.5);
    });
  });

  group('panels', () {
    testWidgets('open, settled and waived records, no names', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(debts: [_openDebt(), _settledDebt, _waivedDebt], wifeName: null),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Outstanding owed to a former member'), findsNWidgets(3));
      final open = _k('fmd_panel_d-open');
      expect(find.descendant(of: open, matching: find.text('SAR 400.00')), findsOneWidget);
      expect(find.descendant(of: open, matching: find.text('Owed at deletion: SAR 900.00')), findsOneWidget);
      expect(find.descendant(of: open, matching: find.text('Paid: SAR 500.00')), findsOneWidget);
      expect(find.descendant(of: open, matching: _k('fmd_status_d-open')), findsNothing);

      final settled = _k('fmd_panel_d-settled');
      expect(find.descendant(of: settled, matching: find.text('Settled')), findsOneWidget);
      expect(
        find.descendant(of: settled, matching: find.text('Closed on ${_d('en', '2026-10-20T10:00:00Z', 'd MMM yyyy')}')),
        findsOneWidget,
      );
      expect(find.descendant(of: settled, matching: find.text('Paid: SAR 300.00')), findsOneWidget);

      final waived = _k('fmd_panel_d-waived');
      expect(find.descendant(of: waived, matching: find.text('Waived by her')), findsOneWidget);
      expect(find.descendant(of: waived, matching: find.text('Waived: SAR 200.00')), findsOneWidget);
      expect(
        find.descendant(of: waived, matching: find.text('Closed on ${_d('en', '2026-09-15T10:00:00Z', 'd MMM yyyy')}')),
        findsOneWidget,
      );
      expect(find.textContaining('Sara'), findsNothing);
      expect(find.textContaining('Ahmed'), findsNothing);
    });

    testWidgets('actions only for a manager, only on an open record', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(debts: [_openDebt(), _settledDebt, _waivedDebt]),
      )));
      await tester.pumpAndSettle();
      expect(_k('fmd_pay_d-open'), findsOneWidget);
      expect(_k('fmd_waive_d-open'), findsOneWidget);
      for (final id in ['d-settled', 'd-waived']) {
        expect(_k('fmd_pay_$id'), findsNothing);
        expect(_k('fmd_waive_$id'), findsNothing);
        expect(_k('fmd_history_$id'), findsOneWidget);
      }

      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh2',
        summary: _summary(debts: [_openDebt(), _settledDebt], canManage: false, role: 'member'),
      )));
      await tester.pumpAndSettle();
      expect(_k('fmd_panel_d-open'), findsOneWidget, reason: 'every member sees the record');
      expect(_k('fmd_pay_d-open'), findsNothing);
      expect(_k('fmd_waive_d-open'), findsNothing);
      expect(_k('fmd_history_d-open'), findsOneWidget);
    });

    testWidgets('the records show when no wife remains', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(withWife: false, debts: [_openDebt(), _waivedDebt]),
        emptyPlaceholder: const Text('no wife placeholder'),
      )));
      await tester.pumpAndSettle();
      expect(_k('fmd_panel_d-open'), findsOneWidget);
      expect(_k('fmd_panel_d-waived'), findsOneWidget);
      expect(_k('fmd_pay_d-open'), findsOneWidget);
    });

    testWidgets('no wife and no record: still the placeholder', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(withWife: false, debts: []),
        emptyPlaceholder: const Text('no wife placeholder'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('no wife placeholder'), findsOneWidget);
      expect(find.text('Outstanding owed to a former member'), findsNothing);
    });

    testWidgets('history lists the payments and the waiver', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(debts: [_waivedDebt]),
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_history_d-waived');

      expect(find.text('Record history'), findsOneWidget);
      expect(find.text('Owed when her account was deleted'), findsOneWidget);
      expect(find.text('SAR 250.00'), findsOneWidget);
      expect(find.text('Paid via Cash'), findsOneWidget);
      expect(find.text('−SAR 50.00'), findsOneWidget);
      expect(find.text(_d('en', '2026-09-05T09:00:00Z', 'd MMM yyyy')), findsOneWidget);
      expect(find.text('She waived what remained'), findsOneWidget);
      expect(find.text('−SAR 200.00'), findsOneWidget);
      expect(find.text(_d('en', '2026-09-15T10:00:00Z', 'd MMM yyyy')), findsOneWidget);
    });
  });

  group('record a payment', () {
    late List<_PayCall> calls;
    late int loads;
    late int reimbursed;

    Widget card({Object? Function(int call)? failWith, NafaqahSummary? summary}) => FamilyReimbursementCard(
          householdId: 'hh',
          summary: summary ?? _summary(),
          onReimbursed: () => reimbursed++,
          loadSummary: (_) async {
            loads++;
            return summary ?? _summary();
          },
          recordFormerMemberDebtPayment: ({
            required String debtId,
            required double amount,
            required String paymentMethod,
            required String requestKey,
            required String accountId,
          }) async {
            calls.add((debtId: debtId, amount: amount, paymentMethod: paymentMethod, requestKey: requestKey));
            final failure = failWith?.call(calls.length);
            if (failure != null) throw failure;
            return FormerMemberDebtReceipt.fromMap({
              'status': 'open',
              'replayed': false,
              'debt_id': debtId,
              'event_id': 'e1',
              'amount': amount,
              'payment_method': paymentMethod,
              'remaining': 400 - amount,
            });
          },
        );

    setUp(() {
      calls = [];
      loads = 0;
      reimbursed = 0;
    });

    testWidgets('the sheet is prefilled with what remains', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      expect(find.text('Record a payment'), findsOneWidget);
      expect(find.text('Full (SAR 400.00)'), findsOneWidget);
      final field = tester.widget<TextField>(_k('fmd_amount_field'));
      expect(field.controller!.text, '400.00');
    });

    for (final typed in ['400.01', '0', '-5']) {
      testWidgets('"$typed" is refused before reaching the server', (tester) async {
        await tester.pumpWidget(_app(card()));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'fmd_pay_d-open');
        await tester.enterText(_k('fmd_amount_field'), typed);
        await pickPayerAccount(tester);
        await _tapKey(tester, 'fmd_pay_submit');
        expect(calls, isEmpty);
        expect(_k('fmd_confirm_ok'), findsNothing, reason: 'no confirmation for a refused amount');
        expect(_k('fmd_pay_submit'), findsOneWidget, reason: 'the sheet stays open');
        if (typed == '400.01') {
          expect(find.text('That is more than remains (SAR 400.00).'), findsOneWidget);
        } else {
          expect(find.text('Please enter a valid payment amount'), findsOneWidget);
        }
      });
    }

    testWidgets('exactly what remains is accepted (halala-exact)', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await tester.enterText(_k('fmd_amount_field'), '400.00');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(calls.single.amount, 400.0);
    });

    testWidgets('confirmation states amount and method, then the recorder gets them with a UUID key', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await tester.enterText(_k('fmd_amount_field'), '150.25');
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');

      expect(calls, isEmpty, reason: 'nothing is sent before the confirmation');
      expect(find.text('Record a payment of SAR 150.25 via Cash?'), findsOneWidget);
      await _tapKey(tester, 'fmd_confirm_ok');

      expect(calls, hasLength(1));
      expect(calls.single.debtId, 'd-open');
      expect(calls.single.amount, 150.25);
      expect(calls.single.paymentMethod, 'cash');
      expect(calls.single.requestKey, matches(_uuidV4));
      expect(find.text('Recorded SAR 150.25, paid from Payer bank'), findsOneWidget);
      expect(_k('fmd_pay_submit'), findsNothing, reason: 'the sheet closes');
      expect(loads, 1, reason: 'the summary is refreshed');
      expect(reimbursed, 1);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_cancel');
      expect(calls, isEmpty);
      expect(_k('fmd_pay_submit'), findsOneWidget);
    });

    testWidgets('a retry after an unconfirmed outcome reuses the same key', (tester) async {
      await tester.pumpWidget(_app(card(
        failWith: (n) => n == 1 ? const NafaqahApiException('network', 'timeout', noResponse: true) : null,
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await tester.enterText(_k('fmd_amount_field'), '100');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');

      expect(calls, hasLength(1));
      expect(find.text('Not Confirmed'), findsOneWidget);
      expect(find.textContaining('Recorded SAR'), findsNothing, reason: 'never claimed as recorded');
      expect(loads, 1, reason: 'refreshed to show what the server holds');
      expect(_k('fmd_pay_submit'), findsOneWidget, reason: 'the sheet stays open for a safe retry');

      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(calls, hasLength(2));
      expect(calls[1].requestKey, calls[0].requestKey);
      expect(find.text('Recorded SAR 100.00, paid from Payer bank'), findsOneWidget);
    });

    testWidgets('a replayed retry reports what the server recorded, not what was typed again', (tester) async {
      // The first answer was lost, but the server stored 100 via STC Pay. The user then types
      // 50 and Cash: the same key replays the 100, and the app must say so.
      var n = 0;
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(),
        loadSummary: (_) async => _summary(),
        recordFormerMemberDebtPayment: ({
          required String debtId,
          required double amount,
          required String paymentMethod,
          required String requestKey,
          required String accountId,
        }) async {
          n++;
          if (n == 1) throw const NafaqahApiException('network', 'timeout', noResponse: true);
          return FormerMemberDebtReceipt.fromMap({
            'status': 'open', 'replayed': true, 'debt_id': debtId, 'event_id': 'e1',
            'amount': 100, 'payment_method': 'stc_pay', 'remaining': 300,
          });
        },
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await tester.enterText(_k('fmd_amount_field'), '100');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      await tester.enterText(_k('fmd_amount_field'), '50');
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(n, 2);
      expect(find.text('Recorded SAR 100.00, paid from Payer bank'), findsOneWidget);
      expect(find.textContaining('SAR 50.00 via Cash'), findsNothing);
    });

    testWidgets('a retry after a refusal reuses the same key; a new sheet gets a new key', (tester) async {
      await tester.pumpWidget(_app(card(
        failWith: (n) => n == 1 ? const NafaqahApiException('network', 'x', statusCode: 400) : null,
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_pay_d-open');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(find.text('Settlement Failed'), findsOneWidget);
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(calls, hasLength(2));
      expect(calls[1].requestKey, calls[0].requestKey);

      await _tapKey(tester, 'fmd_pay_d-open');
      await pickPayerAccount(tester);
      await _tapKey(tester, 'fmd_pay_submit');
      await _tapKey(tester, 'fmd_confirm_ok');
      expect(calls, hasLength(3));
      expect(calls[2].requestKey, isNot(calls[0].requestKey));
      expect(calls[2].requestKey, matches(_uuidV4));
    });

    final errors = <String, (NafaqahApiException, String)>{
      'overpayment': (
        const NafaqahApiException('overpayment', 'x', statusCode: 409, outstanding: 120.5),
        'That is more than remains (SAR 120.50).',
      ),
      'debt_closed': (
        const NafaqahApiException('debt_closed', 'x', statusCode: 409),
        'This record is already settled or waived.',
      ),
      'debt_not_found': (
        const NafaqahApiException('debt_not_found', 'x', statusCode: 404),
        'This record no longer exists. Refresh and try again.',
      ),
      'request_key_reused': (
        const NafaqahApiException('request_key_reused', 'x', statusCode: 409),
        'This was already sent with different details. Close this, check the record, then try again.',
      ),
      'forbidden': (
        const NafaqahApiException('forbidden', 'x', statusCode: 403),
        'Only the husband or a household admin can close this record.',
      ),
      'invalid': (
        const NafaqahApiException('invalid', 'x', statusCode: 422),
        'The amount or payment method is not valid.',
      ),
      'other': (
        const NafaqahApiException('network', 'x', statusCode: 400),
        'Settlement was not recorded',
      ),
    };
    errors.forEach((name, c) {
      testWidgets('payment error $name is explained, never shown as success', (tester) async {
        await tester.pumpWidget(_app(card(failWith: (_) => c.$1)));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'fmd_pay_d-open');
        await pickPayerAccount(tester);
        await _tapKey(tester, 'fmd_pay_submit');
        await _tapKey(tester, 'fmd_confirm_ok');
        expect(find.text(c.$2), findsOneWidget);
        expect(find.text('Settlement Failed'), findsOneWidget);
        expect(find.textContaining('Recorded SAR'), findsNothing);
        expect(reimbursed, 0);
      });
    });
  });

  group('her waiver', () {
    late List<({String debtId, String requestKey})> calls;
    late int loads;

    Widget card({Object? Function(int call)? failWith}) => FamilyReimbursementCard(
          householdId: 'hh',
          summary: _summary(),
          loadSummary: (_) async {
            loads++;
            return _summary();
          },
          waiveFormerMemberDebt: ({required String debtId, required String requestKey}) async {
            calls.add((debtId: debtId, requestKey: requestKey));
            final failure = failWith?.call(calls.length);
            if (failure != null) throw failure;
            return FormerMemberDebtReceipt.fromMap({
              'status': 'waived',
              'replayed': false,
              'debt_id': debtId,
              'event_id': 'e2',
              'waived_amount': 400,
              'remaining': 0,
            });
          },
        );

    setUp(() {
      calls = [];
      loads = 0;
    });

    testWidgets('cancel sends nothing; confirm records the waiver with a UUID key', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_waive_d-open');
      expect(
        find.text('This closes the record as waived by her (إبراء): SAR 400.00 is no longer owed. No money moves.'),
        findsOneWidget,
      );
      await _tapKey(tester, 'fmd_waive_cancel');
      expect(calls, isEmpty);
      expect(_k('fmd_waive_ok'), findsNothing);

      await _tapKey(tester, 'fmd_waive_d-open');
      await _tapKey(tester, 'fmd_waive_ok');
      expect(calls.single.debtId, 'd-open');
      expect(calls.single.requestKey, matches(_uuidV4));
      expect(find.text('Recorded as waived by her.'), findsOneWidget);
      expect(_k('fmd_waive_ok'), findsNothing);
      expect(loads, 1);
    });

    testWidgets('a retry in the same dialog reuses the key', (tester) async {
      await tester.pumpWidget(_app(card(
        failWith: (n) => n == 1 ? const NafaqahApiException('network', 'x', statusCode: 503) : null,
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fmd_waive_d-open');
      await _tapKey(tester, 'fmd_waive_ok');
      expect(find.text('We could not confirm this. Trying again is safe: it is recorded only once.'), findsOneWidget);
      expect(find.text('Recorded as waived by her.'), findsNothing);
      expect(loads, 1);
      await _tapKey(tester, 'fmd_waive_ok');
      expect(calls, hasLength(2));
      expect(calls[1].requestKey, calls[0].requestKey);
      expect(find.text('Recorded as waived by her.'), findsOneWidget);
    });

    final errors = <String, (NafaqahApiException, String)>{
      'debt_closed': (const NafaqahApiException('debt_closed', 'x', statusCode: 409), 'This record is already settled or waived.'),
      'debt_not_found': (
        const NafaqahApiException('debt_not_found', 'x', statusCode: 404),
        'This record no longer exists. Refresh and try again.',
      ),
      'request_key_reused': (
        const NafaqahApiException('request_key_reused', 'x', statusCode: 409),
        'This was already sent with different details. Close this, check the record, then try again.',
      ),
      'forbidden': (
        const NafaqahApiException('forbidden', 'x', statusCode: 403),
        'Only the husband or a household admin can close this record.',
      ),
      'other': (const NafaqahApiException('invalid', 'x', statusCode: 422), 'The waiver was not recorded.'),
    };
    errors.forEach((name, c) {
      testWidgets('waiver error $name is explained', (tester) async {
        await tester.pumpWidget(_app(card(failWith: (_) => c.$1)));
        await tester.pumpAndSettle();
        await _tapKey(tester, 'fmd_waive_d-open');
        await _tapKey(tester, 'fmd_waive_ok');
        expect(find.text(c.$2), findsOneWidget);
        expect(find.text('Recorded as waived by her.'), findsNothing);
      });
    });
  });

  group('notice before her deletion', () {
    testWidgets('the husband sees the date and what is still owed', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(
          debts: [],
          pendingDeletion: {'scheduled_for': _deletionDate.toIso8601String(), 'outstanding': 386.4},
        ),
      )));
      await tester.pumpAndSettle();
      final banner = _k('fmd_pending_deletion_$_wife');
      expect(banner, findsOneWidget);
      final date = _d('en', _deletionDate.toIso8601String(), 'd MMMM yyyy');
      expect(
        find.descendant(
          of: banner,
          matching: find.text(
            'Sara has scheduled her account to be deleted on $date. SAR 386.40 is still owed to her. '
            'Settle it before then; after the deletion the household keeps an anonymised record of what remains.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('without her name it says "Your wife"', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(
        householdId: 'hh',
        summary: _summary(
          debts: [],
          wifeName: null,
          pendingDeletion: {'scheduled_for': _deletionDate.toIso8601String(), 'outstanding': 10},
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your wife has scheduled her account to be deleted on'), findsOneWidget);
    });

    testWidgets('no notice without a scheduled deletion', (tester) async {
      await tester.pumpWidget(_app(FamilyReimbursementCard(householdId: 'hh', summary: _summary(debts: []))));
      await tester.pumpAndSettle();
      expect(_k('fmd_pending_deletion_$_wife'), findsNothing);
      expect(find.textContaining('scheduled her account'), findsNothing);
    });

    for (final lang in const ['ar', 'ur']) {
      testWidgets('$lang: the notice is localized with the date and the amount', (tester) async {
        await tester.pumpWidget(_app(
          FamilyReimbursementCard(
            householdId: 'hh',
            summary: _summary(
              debts: [_openDebt()],
              pendingDeletion: {'scheduled_for': _deletionDate.toIso8601String(), 'outstanding': 386.4},
            ),
          ),
          lang: lang,
        ));
        await tester.pumpAndSettle();
        final l = AppLocalizations(Locale(lang));
        final banner = _k('fmd_pending_deletion_$_wife');
        expect(find.descendant(of: banner, matching: find.textContaining(l.date(_deletionDate.toLocal(), 'd MMMM yyyy'))), findsOneWidget);
        expect(find.descendant(of: banner, matching: find.textContaining(l.sar(386.4))), findsOneWidget);
        expect(find.textContaining('SAR'), findsNothing);
        expect(find.text(l.get('fmd_title')), findsOneWidget);
        expect(Directionality.of(tester.element(banner)), TextDirection.rtl);
      });
    }
  });

  group('320 px at x2.0 text', () {
    for (final lang in const ['ar', 'en', 'ur']) {
      for (final dark in const [false, true]) {
        testWidgets('$lang ${dark ? 'dark' : 'light'}: card, sheets and dialogs fit', (tester) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(_app(
            FamilyReimbursementCard(
              householdId: 'hh',
              summary: _summary(
                debts: [_openDebt(), _settledDebt, _waivedDebt],
                pendingDeletion: {'scheduled_for': _deletionDate.toIso8601String(), 'outstanding': 386.4},
              ),
              loadSummary: (_) async => _summary(),
              recordFormerMemberDebtPayment: ({
                required String debtId,
                required double amount,
                required String paymentMethod,
                required String requestKey,
                required String accountId,
              }) async =>
                  const FormerMemberDebtReceipt(),
              waiveFormerMemberDebt: ({required String debtId, required String requestKey}) async => const FormerMemberDebtReceipt(),
            ),
            lang: lang,
            dark: dark,
            scale: 2.0,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'card');
          expect(_k('fmd_pending_deletion_$_wife'), findsOneWidget);

          await _tapKey(tester, 'fmd_pay_d-open');
          expect(tester.takeException(), isNull, reason: 'payment sheet');
          await pickPayerAccount(tester);
          await _tapKey(tester, 'fmd_pay_submit');
          expect(_k('fmd_confirm_ok'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'payment confirmation');
          await _tapKey(tester, 'fmd_confirm_cancel');
          Navigator.of(tester.element(_k('fmd_pay_submit'))).pop();
          await tester.pumpAndSettle();

          await _tapKey(tester, 'fmd_waive_d-open');
          expect(_k('fmd_waive_ok'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'waiver dialog');
          await _tapKey(tester, 'fmd_waive_cancel');

          await _tapKey(tester, 'fmd_history_d-waived');
          expect(tester.takeException(), isNull, reason: 'history sheet');
        });
      }
    }
  });
}
