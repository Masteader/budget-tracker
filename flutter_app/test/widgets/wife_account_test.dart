// The wife account (owner decisions 2026-11-06, migration 20261105001300,
// section 12): her husband's account assigned to one wife. She spends from it;
// he funds it; every repayment to her credits one of hers, which the payer
// picks (he may switch her choice to another of hers); her request names the
// one she received it into; with none, wife_account_required and his "create
// her wife account".
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/account.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/nafaqah_account.dart' show accountForNafaqahClass;
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/nafaqah_api_client.dart';
import 'package:budget_tracker/services/household_permissions.dart';
import 'package:budget_tracker/widgets/dashboard/family_reimbursement_card.dart';
import 'package:budget_tracker/widgets/nafaqah/repayment_account_picker.dart';
import 'package:budget_tracker/widgets/nafaqah/unconfirmed_payments.dart';
import 'package:budget_tracker/widgets/nafaqah/wife_account_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/payer_account.dart';

const _husband = 'u-husband';
const _wife = 'u-wife';
const _coWife = 'u-cowife';

Account _wa(String id, String wife, {String owner = _husband, bool archived = false, double balance = 0}) => Account(
      id: id,
      householdId: 'hh',
      ownerUserId: owner,
      name: 'Card $id',
      accountType: AccountType.wife,
      balance: balance,
      isArchived: archived,
      assignedWifeId: wife,
    );

class _FakeBase extends BaseApiClient {
  Map<String, dynamic> response = {'status': 'success', 'outstanding_after': 0, 'id': 'wa-new'};
  String? path;
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool shouldSign = true, Duration timeout = const Duration(seconds: 20), Map<String, String>? extraHeaders}) async {
    this.path = path;
    this.body = body;
    return response;
  }
}

Widget _localized(Widget child, {Locale locale = const Locale('en'), double textScale = 1.0, double width = 800}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), size: Size(width, 900)),
          child: Scaffold(body: Center(child: SizedBox(width: width, child: SingleChildScrollView(child: child)))),
        ),
      ),
    );

NafaqahSummary _summary({String role = 'husband', double outstanding = 300, List<Map<String, dynamic>> requests = const []}) =>
    NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': role,
      'caller_user_id': role == 'wife' ? _wife : _husband,
      'cycle_key': '2026-11',
      'husband': {'id': _husband, 'display_name': 'Ahmed'},
      'wives': [
        {
          'id': _wife,
          'display_name': 'Sara',
          'reimbursement': {'gross_advanced': outstanding, 'reimbursed': 0.0, 'outstanding': outstanding, 'overpaid': 0},
          'allowance': {'cycle_key': '2026-11', 'is_set': false, 'allocated': 0, 'spent': 0, 'remaining': 0, 'transaction_count': 0},
          'requests': requests,
          if (role == 'wife') 'can_request': true,
        }
      ],
      'can_set_allowance': role != 'wife',
      'can_record_reimbursement': role != 'wife',
      'provider_user_id': _husband,
      'needs_provider': false,
    });

Widget _card(NafaqahSummary summary, {required String viewer, required List<Account> wifeAccounts, NafaqahReimbursementRecorder? record,
        NafaqahRequestCreator? ask, NafaqahRequestApprover? approve, PayerAccounts? accounts}) =>
    withPayerAccount(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: FamilyReimbursementCard(
              householdId: 'hh',
              summary: summary,
              recordReimbursement: record,
              createRequest: ask,
              approveRequest: approve,
              loadSummary: (_) async => summary,
            ),
          ),
        ),
      ),
      userId: viewer,
      accounts: accounts,
      wifeAccounts: wifeAccounts,
    );

void main() {
  setUp(UnconfirmedPayments.reset);

  group('the model and who uses it', () {
    test('a wife account reads as one, with whom it is assigned to, and is no budget money', () {
      final a = Account.fromMap({
        'id': 'wa',
        'household_id': 'hh',
        'owner_user_id': _husband,
        'name': 'Sara card',
        'account_type': 'wife',
        'assigned_wife_id': _wife,
        'balance': 120,
      });
      expect(a.isWifeAccount, isTrue);
      expect(a.assignedWifeId, _wife);
      expect(a.accountType.isOperatingPool, isFalse);
      expect(a.toMap()['assigned_wife_id'], _wife);
      expect(AccountType.wife.value, 'wife');
    });

    test('nothing is transferred out of it or paid from it, by its owner either', () {
      final a = _wa('wa', _wife);
      expect(HouseholdPermissions.canWithdrawFrom(a, currentUserId: _husband, isAdmin: true), isFalse);
      expect(HouseholdPermissions.canWithdrawFrom(a, currentUserId: _wife, isAdmin: false), isFalse);
      expect(
          repaymentAccounts([a], householdId: 'hh', currentUserId: _husband, isAdmin: true), isEmpty, reason: 'never a source');
    });

    test('she spends from hers only; she does not top it up; he does', () {
      final mine = _wa('wa1', _wife);
      final hers = _wa('wc', _coWife);
      final gone = _wa('wa2', _wife, archived: true);
      expect(HouseholdPermissions.isHerWifeAccount(mine, currentUserId: _wife), isTrue);
      expect(HouseholdPermissions.isHerWifeAccount(hers, currentUserId: _wife), isFalse);
      expect(HouseholdPermissions.isHerWifeAccount(gone, currentUserId: _wife), isFalse);
      expect(HouseholdPermissions.isHerWifeAccount(mine, currentUserId: _husband), isFalse, reason: 'he does not spend from it');
      expect(HouseholdPermissions.transferDestinations([mine, hers], currentUserId: _wife).map((a) => a.id), ['wc']);
      expect(HouseholdPermissions.transferDestinations([mine, hers], currentUserId: _husband).map((a) => a.id), ['wa1', 'wc']);
      expect(HouseholdPermissions.wifeAccountsOf([mine, hers, gone], householdId: 'hh', wifeId: _wife).map((a) => a.id), ['wa1']);
    });

    test('her personal purchase and her advance may go on her wife account, never on a co-wife\'s', () {
      final accounts = [_wa('wa1', _wife), _wa('wc', _coWife)];
      expect(accountForNafaqahClass(kWifePersonal, 'wa1', accounts: accounts, spouseId: _wife), 'wa1');
      expect(accountForNafaqahClass(kWifeReimbursable, 'wa1', accounts: accounts, spouseId: _wife), 'wa1');
      expect(accountForNafaqahClass(kWifePersonal, 'wc', accounts: accounts, spouseId: _wife), isNull);
    });

    test('every new refusal is a known code', () {
      for (final code in [
        'wife_account_required', 'wife_account_invalid', 'wife_account_insufficient_funds', 'wife_account_forbidden',
        'wife_account_has_history', 'not_a_wife', 'invalid_name', 'account_not_found',
      ]) {
        final e = NafaqahApiException.fromResponse({'status': 'error', 'status_code': 409, 'detail': {'code': code, 'available': 12.5}});
        expect(e.code, code);
      }
      final funds = NafaqahApiException.fromResponse(
          {'status': 'error', 'status_code': 409, 'detail': {'code': 'wife_account_insufficient_funds', 'available': 12.5}});
      expect(funds.outstanding, 12.5);
    });
  });

  group('the API client', () {
    test('a repayment, her request and an approval name the wife account', () async {
      final base = _FakeBase();
      final api = NafaqahApiClient(baseClient: base);
      await api.recordReimbursement(
          householdId: 'hh', amount: 100, paymentMethod: 'cash', wifeUserId: _wife, accountId: 'a-1', requestKey: 'k', wifeAccountId: 'wa1');
      expect(base.body?['wife_account_id'], 'wa1');
      await api.createReimbursementRequest(householdId: 'hh', amount: 50, paymentMethod: 'cash', requestKey: 'k2', wifeAccountId: 'wa2');
      expect(base.body?['wife_account_id'], 'wa2');
      await api.approveReimbursementRequest(householdId: 'hh', requestId: 'q', accountId: 'a-1', requestKey: 'k3', wifeAccountId: 'wa1');
      expect(base.path, '/households/hh/nafaqah/reimbursement-requests/q/approve');
      expect(base.body, {'account_id': 'a-1', 'request_key': 'k3', 'wife_account_id': 'wa1'});
      final id = await api.createWifeAccount(householdId: 'hh', wifeUserId: _wife, name: '  Sara card ');
      expect(base.path, '/households/hh/nafaqah/wife-accounts');
      expect(base.body, {'wife_user_id': _wife, 'name': 'Sara card'});
      expect(id, 'wa-new');
    });
  });

  group('the picker and the prompt', () {
    testWidgets('with none, her husband is offered to create her wife account', (tester) async {
      var created = 0;
      await tester.pumpWidget(_localized(WifeAccountPicker(
        accounts: const [],
        selected: null,
        onChanged: (_) {},
        canCreate: true,
        onCreate: () => created++,
      )));
      await tester.pumpAndSettle();
      expect(find.text('She has no account to receive this yet. Create her wife account first.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wife_acc_create')));
      expect(created, 1);
    });

    testWidgets('anyone else is told only her husband creates it', (tester) async {
      await tester.pumpWidget(_localized(const WifeAccountPicker(accounts: [], selected: null, onChanged: _ignore, receiving: true)));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('There is no wife account to receive this yet. Her husband creates it.'), findsOneWidget);
      expect(find.byKey(const ValueKey('wife_acc_create')), findsNothing);
      expect(find.text('Received into'), findsOneWidget);
    });

    testWidgets('her accounts, with their balances; a tap picks one', (tester) async {
      String? picked;
      await tester.pumpWidget(_localized(WifeAccountPicker(
        accounts: [_wa('wa1', _wife, balance: 120), _wa('wa2', _wife)],
        selected: 'wa1',
        onChanged: (id) => picked = id,
      )));
      await tester.pumpAndSettle();
      expect(find.text('To her account'), findsOneWidget);
      expect(find.text('Card wa1'), findsOneWidget);
      expect(find.text('Balance: SAR 120.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wife_acc_wa2')));
      expect(picked, 'wa2');
    });

    for (final lang in ['ar', 'ur', 'en']) {
      testWidgets('320 px wide at text scale 2.0 in $lang, light and dark: no overflow', (tester) async {
        tester.view.physicalSize = const Size(320, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final dark in [false, true]) {
          await tester.pumpWidget(MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(children: [
                      WifeAccountPicker(accounts: [_wa('wa1', _wife, balance: 123456.78)], selected: 'wa1', onChanged: _ignore),
                      const WifeAccountPicker(accounts: [], selected: null, onChanged: _ignore, canCreate: true, onCreate: _noop),
                    ]),
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (lang != 'en') {
            expect(Directionality.of(tester.element(find.byType(WifeAccountPicker).first)), TextDirection.rtl);
          }
        }
      });
    }
  });

  group('add wife account', () {
    testWidgets('her husband picks the wife and a name; it is made and the dialog closes', (tester) async {
      final made = <String>[];
      await tester.pumpWidget(_localized(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => AddWifeAccountDialog.show(context,
              householdId: 'hh',
              wives: const [WifeChoice(_wife, 'Sara'), WifeChoice(_coWife, 'Huda')],
              create: ({required String wifeUserId, required String name}) async {
                made.add('$wifeUserId|$name');
                return 'wa-new';
              }),
          child: const Text('open'),
        ),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add wife account'), findsOneWidget);
      // No wife chosen yet (two of them): refused.
      await tester.enterText(find.byKey(const ValueKey('wife_acc_name')), 'Sara card');
      await tester.tap(find.byKey(const ValueKey('wife_acc_save')));
      await tester.pump();
      expect(made, isEmpty);
      await tester.tap(find.byKey(const ValueKey('wife_acc_wife_$_coWife')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wife_acc_save')));
      await tester.pumpAndSettle();
      expect(made, ['$_coWife|Sara card']);
      expect(find.byKey(const ValueKey('wife_acc_dialog')), findsNothing);
    });

    testWidgets('a blank name is refused before the server', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_localized(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => AddWifeAccountDialog.show(context, householdId: 'hh', wives: const [WifeChoice(_wife, 'Sara')],
              create: ({required String wifeUserId, required String name}) async {
            calls++;
            return 'x';
          }),
          child: const Text('open'),
        ),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('wife_acc_name')), '   ');
      await tester.tap(find.byKey(const ValueKey('wife_acc_save')));
      await tester.pump();
      expect(calls, 0);
      expect(find.text('Give it a name of 1 to 60 characters.'), findsOneWidget);
    });
  });

  group('the sheets', () {
    testWidgets('a repayment credits her only wife account, chosen for him', (tester) async {
      final calls = <String?>[];
      await tester.pumpWidget(_card(
        _summary(),
        viewer: _husband,
        wifeAccounts: [_wa('wa1', _wife)],
        record: ({required double amount, required String paymentMethod, required String wifeUserId, required String accountId,
            required String requestKey, String? wifeAccountId}) async {
          calls.add(wifeAccountId);
          return 0;
        },
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reimburse Wife'));
      await tester.pumpAndSettle();
      expect(find.text('To her account'), findsOneWidget);
      await pickPayerAccount(tester);
      await _record(tester);
      expect(calls, ['wa1']);
    });

    testWidgets('with two of hers he picks one; with none he is offered to create one and nothing is sent', (tester) async {
      final calls = <String?>[];
      Future<double> record({required double amount, required String paymentMethod, required String wifeUserId, required String accountId,
          required String requestKey, String? wifeAccountId}) async {
        calls.add(wifeAccountId);
        return 0;
      }

      await tester.pumpWidget(_card(_summary(), viewer: _husband, wifeAccounts: [_wa('wa1', _wife), _wa('wa2', _wife)], record: record));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reimburse Wife'));
      await tester.pumpAndSettle();
      await pickPayerAccount(tester);
      await _record(tester);
      expect(calls, isEmpty, reason: 'two of hers: he must pick');
      expect(find.text('Choose her account'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('wife_acc_wa2')));
      await tester.tap(find.byKey(const ValueKey('wife_acc_wa2')));
      await tester.pumpAndSettle();
      await _record(tester);
      expect(calls, ['wa2']);

      await tester.pumpWidget(_card(_summary(), viewer: _husband, wifeAccounts: const [], record: record));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reimburse Wife'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wife_acc_create')), findsOneWidget);
      await pickPayerAccount(tester);
      await _record(tester);
      expect(calls, ['wa2'], reason: 'nothing sent without her account');
      expect(find.text('She has no wife account to receive this. Her husband creates one first.'), findsOneWidget);
    });

    testWidgets('her request names the wife account she received it into', (tester) async {
      final asks = <String?>[];
      await tester.pumpWidget(_card(
        _summary(role: 'wife'),
        viewer: _wife,
        wifeAccounts: [_wa('wa1', _wife)],
        ask: ({required double amount, required String paymentMethod, required String requestKey, String? wifeAccountId}) async {
          asks.add(wifeAccountId);
        },
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as received'));
      await tester.pumpAndSettle();
      expect(find.text('Received into'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('req_send')));
      await tester.tap(find.byKey(const ValueKey('req_send')));
      await tester.pumpAndSettle();
      expect(asks, ['wa1']);
    });

    testWidgets('he approves into her choice, or switches to another of hers', (tester) async {
      final approvals = <String?>[];
      final requests = [
        {'id': 'q1', 'amount': 30.0, 'payment_method': 'cash', 'status': 'pending', 'wife_account_id': 'wa2'},
      ];
      await tester.pumpWidget(_card(
        _summary(requests: requests),
        viewer: _husband,
        wifeAccounts: [_wa('wa1', _wife), _wa('wa2', _wife)],
        approve: ({required String requestId, required String accountId, required String requestKey, String? wifeAccountId}) async {
          approvals.add(wifeAccountId);
          return 0;
        },
      ));
      await tester.pumpAndSettle();
      final approve = find.byKey(const ValueKey('req_approve_q1'));
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('req_approve_wife_account')), findsOneWidget);
      await pickPayerAccount(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('wife_acc_wa1')));
      await tester.tap(find.byKey(const ValueKey('wife_acc_wa1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('req_approve_submit')));
      await tester.tap(find.byKey(const ValueKey('req_approve_submit')));
      await tester.pumpAndSettle();
      expect(approvals, ['wa1']);
    });
  });

  group('every new refusal is worded', () {
    for (final lang in ['en', 'ar', 'ur']) {
      testWidgets('in $lang', (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(_localized(Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }), locale: Locale(lang)));
        await tester.pumpAndSettle();
        final generic = repaymentErrorText(ctx, const NafaqahApiException('network', ''));
        for (final code in [
          'wife_account_required', 'wife_account_invalid', 'wife_account_insufficient_funds', 'wife_account_forbidden',
          'wife_account_has_history', 'not_a_wife', 'invalid_name', 'account_not_found',
        ]) {
          final text = repaymentErrorText(ctx, NafaqahApiException(code, '', outstanding: 12.5));
          expect(text, isNot(generic), reason: code);
          expect(text, isNot(contains('wife_acc_')), reason: '$code is translated');
        }
      });
    }
  });
}

Future<void> _record(WidgetTester tester) async {
  final button = find.text('Record Settlement Payment');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _ignore(String _) {}
void _noop() {}
