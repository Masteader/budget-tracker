// A row whose creator was deleted keeps `user_id` NULL and its `spent_by` as is
// (the column has a CHECK and the settlement engine reads it). It must never read
// as the viewer's: `spent_by = 'me'` means the departed creator there.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/budget_coverage.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
import 'package:budget_tracker/services/csv_export_service.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/localized_app.dart';

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this._rows);
  final List<Transaction> _rows;
  @override
  List<Transaction> get transactions => _rows;
  @override
  bool get isLoading => false;
}

const _viewer = 'aaaaaaaa-0000-4000-8000-00000000000a';
const _wife = 'bbbbbbbb-0000-4000-8000-00000000000b';

Map<String, dynamic> _row(Map<String, dynamic> fields) => {
      'id': 'tx-1',
      'household_id': 'h1',
      'amount': 300.0,
      'currency': 'SAR',
      'merchant': 'Dinner',
      'category_code': 'OPEX-DINING',
      'timestamp': '2026-10-20T18:00:00Z',
      'created_at': '2026-10-20T18:00:01Z',
      'source': 'chat',
      ...fields,
    };

Widget _app(Widget child, {String lang = 'en'}) => MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Transaction.fromMap with no creator', () {
    test("spent_by 'me' is the deleted member, while the stored column is unchanged", () {
      final tx = Transaction.fromMap(_row({'user_id': null, 'spent_by': 'me'}));
      expect(tx.creatorRemoved, isTrue);
      expect(tx.attributedSpentBy, kDeletedMemberRef);
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.spentBy, 'me', reason: 'never write a label into spent_by');
      expect(tx.toMap()['spent_by'], 'me');
    });

    test("spent_by 'partner' cannot be credited to the viewer either", () {
      final tx = Transaction.fromMap(_row({'user_id': null, 'spent_by': 'partner'}));
      expect(tx.attributedSpentBy, kDeletedMemberRef);
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.beneficiary, kDeletedMemberRef);
    });

    test("spent_by 'both' stays shared, not the deleted member's alone", () {
      expect(Transaction.fromMap(_row({'user_id': null, 'spent_by': 'both'})).attributedSpentBy, 'both');
    });

    test('a structured row with a member payer is still the deleted member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': 'me',
      }));
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.beneficiary, kDeletedMemberRef);
    });

    test('a shared beneficiary stays shared', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'me',
        'beneficiary_type': 'household',
        'beneficiary_id': 'household',
      }));
      expect(tx.beneficiary, 'both');
      expect(tx.paidBy, kDeletedMemberRef);
    });

    test('a dependent beneficiary stays that dependent', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'me',
        'beneficiary_type': 'dependent',
        'beneficiary_id': 'Salem',
      }));
      expect(tx.beneficiary, 'Salem');
    });

    test('a note tail naming me is the deleted member too', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'source': 'manual',
        'spent_by': 'me',
        'notes': 'Manual: Dinner | PaidBy: me | Beneficiary: me | SpentBy: me',
      }));
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.beneficiary, kDeletedMemberRef);
    });

    test('an empty creator counts as none', () {
      expect(Transaction.fromMap(_row({'user_id': '  ', 'spent_by': 'me'})).creatorRemoved, isTrue);
    });

    test('copyWith keeps it', () {
      final tx = Transaction.fromMap(_row({'user_id': null, 'spent_by': 'me'}));
      expect(tx.copyWith(merchant: 'Other').creatorRemoved, isTrue);
    });
  });

  // Only references relative to the departed creator ('me', 'partner') or already
  // replaced by the purge are theirs. A member id or a dependent names someone else,
  // who is alive and stays named.
  group('living members on a row with no creator', () {
    test('a living wife\'s id as beneficiary stays her, not the deleted member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': _wife,
      }));
      expect(tx.beneficiary, _wife);
      expect(tx.paidBy, kDeletedMemberRef, reason: "spent_by 'me' is the departed creator");
    });

    test('a living member who paid, named in the note tail, stays that member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'individual',
        'beneficiary_id': _wife,
        'notes': 'Manual: Dinner | PaidBy: $_wife | Beneficiary: $_wife | SpentBy: partner',
      }));
      expect(tx.paidBy, _wife);
      expect(tx.beneficiary, _wife);
      expect(tx.attributedSpentBy, _wife);
      expect(tx.spentBy, 'partner', reason: 'the stored column is unchanged');
    });

    test('a household role word stored without a roster stays that member, to be named by the roster', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': 'Wife',
      }));
      expect(tx.beneficiary, 'wife');
    });

    test('an id in capitals is the same member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'household',
        'beneficiary_id': 'household',
        'notes': 'Manual: Dinner | PaidBy: ${_wife.toUpperCase()} | Beneficiary: household | SpentBy: partner',
      }));
      expect(tx.paidBy, _wife);
      expect(tx.beneficiary, 'both');
    });

    test("'partner' is relative to the departed creator, so it cannot be named", () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'spent_by': 'partner',
        'beneficiary_type': 'individual',
        'beneficiary_id': 'partner',
      }));
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.beneficiary, kDeletedMemberRef);
      expect(tx.attributedSpentBy, kDeletedMemberRef);
    });

    test('an empty payer in the note tail is the deleted member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': null,
        'source': 'manual',
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': _wife,
        'notes': 'Manual: Dinner | PaidBy:  | Beneficiary: $_wife | SpentBy: me',
      }));
      expect(tx.paidBy, kDeletedMemberRef);
      expect(tx.beneficiary, _wife);
    });

    test('nothing on such a row ever reads as "me" or "partner"', () {
      for (final fields in <Map<String, dynamic>>[
        {'spent_by': 'me', 'beneficiary_type': 'individual', 'beneficiary_id': _wife},
        {'spent_by': 'partner', 'beneficiary_type': 'individual', 'beneficiary_id': 'me'},
        {'spent_by': 'me', 'notes': 'Chat: x | PaidBy: me | Beneficiary: partner | SpentBy: me'},
        {
          'source': 'manual',
          'spent_by': 'partner',
          'beneficiary_type': 'individual',
          'beneficiary_id': _viewer,
          'notes': 'Manual: x | PaidBy: $_wife | Beneficiary: $_viewer | SpentBy: partner',
        },
      ]) {
        final tx = Transaction.fromMap(_row({'user_id': null, ...fields}));
        for (final value in [tx.paidBy, tx.beneficiary, tx.attributedSpentBy]) {
          expect(value, isNot(anyOf('me', 'partner')), reason: '$fields');
        }
      }
    });
  });

  group('naming a living member', () {
    const roster = HouseholdRoster(householdId: 'h1', members: [
      HouseholdMember(userId: _viewer, displayName: 'Khalid', financialRole: 'provider', isNafaqahProvider: true),
      HouseholdMember(userId: _wife, displayName: 'Noura', financialRole: 'spouse'),
    ]);

    test('by id, in any case, and by a household role', () {
      expect(roster.nameOf(_wife), 'Noura');
      expect(roster.nameOf(_wife.toUpperCase()), 'Noura');
      expect(roster.nameOf('wife'), 'Noura');
      expect(roster.nameOf('husband'), 'Khalid');
    });

    test('nobody for the creator-relative words, the label or someone not in the roster', () {
      for (final ref in ['me', 'partner', kDeletedMemberRef, '', 'cccccccc-0000-4000-8000-00000000000c']) {
        expect(roster.nameOf(ref), isNull, reason: ref);
      }
    });
  });

  group('rows that do have a creator are unchanged', () {
    test("'me' stays 'me'", () {
      final tx = Transaction.fromMap(_row({'user_id': _viewer, 'spent_by': 'me'}));
      expect(tx.creatorRemoved, isFalse);
      expect(tx.attributedSpentBy, 'me');
      expect(tx.paidBy, 'me');
    });

    test("'partner' stays 'partner'", () {
      final tx = Transaction.fromMap(_row({'user_id': _viewer, 'spent_by': 'partner'}));
      expect(tx.attributedSpentBy, 'partner');
      expect(tx.paidBy, 'partner');
    });

    test('a partial select without user_id says nothing about the creator', () {
      final tx = Transaction.fromMap(_row({'spent_by': 'me'}));
      expect(tx.creatorRemoved, isFalse);
      expect(tx.attributedSpentBy, 'me');
    });

    test('a beneficiary the purge replaced shows the deleted member, not the partner', () {
      final tx = Transaction.fromMap(_row({
        'user_id': _viewer,
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': kDeletedMemberRef,
      }));
      expect(tx.beneficiary, kDeletedMemberRef);
      expect(tx.paidBy, 'me');
    });

    test('a payer the purge replaced in a note shows the deleted member', () {
      final tx = Transaction.fromMap(_row({
        'user_id': _viewer,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'household',
        'beneficiary_id': 'household',
        'notes': 'Manual: Dinner | PaidBy: $kDeletedMemberRef | Beneficiary: household | SpentBy: partner',
      }));
      expect(tx.paidBy, kDeletedMemberRef);
    });
  });

  group('the feed badge', () {
    for (final lang in const ['en', 'ar', 'ur']) {
      testWidgets('$lang: shows the localized label and never "me"', (tester) async {
        final l = AppLocalizations(Locale(lang));
        await tester.pumpWidget(_app(
          const TransactionItemBreakdownCard(merchant: 'Dinner', amount: 10, spentBy: kDeletedMemberRef, initiallyExpanded: true),
          lang: lang,
        ));
        await tester.pump();
        expect(find.textContaining(l.get('deleted_member')), findsWidgets);
        expect(find.text(l.get('me')), findsNothing);
        expect(find.text(l.get('paid_by_me')), findsNothing);
        expect(l.get('deleted_member'), isNot('deleted_member'));
      });
    }
  });

  group('the feed badge for a living member who paid', () {
    for (final lang in const ['en', 'ar', 'ur']) {
      testWidgets('$lang: names them, never "me", "partner", "both" or the deleted member', (tester) async {
        final l = AppLocalizations(Locale(lang));
        await tester.pumpWidget(_app(
          const TransactionItemBreakdownCard(merchant: 'Dinner', amount: 10, spentBy: _wife, payerName: 'Noura', initiallyExpanded: true),
          lang: lang,
        ));
        await tester.pump();
        expect(find.text('Noura'), findsWidgets);
        for (final key in ['me', 'paid_by_me', 'partner', 'paid_by_partner', 'both', 'both_shared', 'deleted_member']) {
          expect(find.text(l.get(key)), findsNothing, reason: key);
        }
      });
    }

    testWidgets('without a roster says a member, not the deleted one', (tester) async {
      final l = AppLocalizations(const Locale('en'));
      await tester.pumpWidget(_app(
        const TransactionItemBreakdownCard(merchant: 'Dinner', amount: 10, spentBy: _wife, initiallyExpanded: true),
      ));
      await tester.pump();
      expect(find.text(l.get('member')), findsWidgets);
      expect(find.text(l.get('deleted_member')), findsNothing);
      expect(find.text(l.get('both')), findsNothing);
    });
  });

  group('the feed', () {
    testWidgets('names a living member who paid a row with no creator, from the roster', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final rosterReads = <String>[];
      final rows = [
        Transaction.fromMap(_row({
          'id': 'wife',
          'timestamp': DateTime.now().toIso8601String(),
          'user_id': null,
          'source': 'manual',
          'spent_by': 'partner',
          'beneficiary_type': 'household',
          'beneficiary_id': 'household',
          'notes': 'Manual: Dinner | PaidBy: $_wife | Beneficiary: household | SpentBy: partner',
        })),
      ];
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions(rows)),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => const NafaqahSummary(mode: 'roommates'),
            loadBudgetCoverage: (_) async => BudgetCoverage.unknown,
            loadCycles: (_) async => const {},
            loadRoster: (hid) async {
              rosterReads.add(hid);
              return const HouseholdRoster(householdId: 'h1', members: [
                HouseholdMember(userId: _viewer, displayName: 'Khalid'),
                HouseholdMember(userId: _wife, displayName: 'Noura'),
              ]);
            },
            initialDatePeriod: 'ALL',
          ),
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
      final l = AppLocalizations(const Locale('en'));
      expect(rosterReads, ['h1']);
      expect(find.text('Noura'), findsWidgets);
      expect(find.text(l.get('deleted_member')), findsNothing);
      expect(find.text(l.get('me')), findsNothing);
    });

    testWidgets('reads no roster when no row needs it', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      var rosterReads = 0;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionProvider>(
              create: (_) => _FakeTransactions([Transaction.fromMap(_row({'user_id': _viewer, 'spent_by': 'me'}))])),
          ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
          ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
        ],
        child: localizedApp(
          TransactionFeedScreen(
            householdId: 'h1',
            loadNafaqah: (_) async => const NafaqahSummary(mode: 'roommates'),
            loadBudgetCoverage: (_) async => BudgetCoverage.unknown,
            loadCycles: (_) async => const {},
            loadRoster: (_) async {
              rosterReads++;
              return const HouseholdRoster(householdId: 'h1');
            },
            initialDatePeriod: 'ALL',
          ),
          scaffold: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(rosterReads, 0);
    });
  });

  group('the feed filter', () {
    test("'paid by me' does not list a deleted member's row", () {
      final provider = TransactionProvider();
      final deleted = Transaction.fromMap(_row({'id': 'gone', 'user_id': null, 'spent_by': 'me'}));
      final mine = Transaction.fromMap(_row({'id': 'mine', 'user_id': _viewer, 'spent_by': 'me'}));
      provider.setTransactionsForTesting([deleted, mine]);
      provider.setSpentByFilter('me');
      expect(provider.filteredTransactions.map((t) => t.id), ['mine']);
    });

    test('a row a living member paid is in no "me", "partner" or "both" filter, as its badge names them', () {
      final provider = TransactionProvider();
      final paidByWife = Transaction.fromMap(_row({
        'id': 'wife',
        'user_id': null,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'household',
        'beneficiary_id': 'household',
        'notes': 'Manual: Dinner | PaidBy: $_wife | Beneficiary: household | SpentBy: partner',
      }));
      provider.setTransactionsForTesting([paidByWife]);
      for (final filter in ['me', 'partner', 'both']) {
        provider.setSpentByFilter(filter);
        expect(provider.filteredTransactions, isEmpty, reason: filter);
      }
    });
  });

  group('the CSV export', () {
    test('writes the localized label for a row with no creator, and the column for the rest', () {
      final l = AppLocalizations(const Locale('ur'));
      final headers = CsvExportService.headersFor(l);
      final csv = CsvExportService.generateTransactionsCsv([
        _row({'id': 'gone', 'user_id': null, 'spent_by': 'me'}),
        _row({'id': 'shared', 'user_id': null, 'spent_by': 'both'}),
        _row({'id': 'mine', 'user_id': _viewer, 'spent_by': 'me'}),
      ], headers: headers, deletedMemberLabel: l.get('deleted_member'));
      final rows = csv.trim().split('\n').map((line) => line.split(',')).toList();
      final spentByColumn = headers.indexOf(l.get('csv_col_spent_by'));
      String cell(int row) => rows[row][spentByColumn].replaceAll('"', '');
      expect(cell(1), l.get('deleted_member'));
      expect(cell(2), 'both');
      expect(cell(3), 'me');
    });

    test('names a living member who paid on a row with no creator', () {
      final l = AppLocalizations(const Locale('en'));
      final headers = CsvExportService.headersFor(l);
      final wifeRow = _row({
        'id': 'wife',
        'user_id': null,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'individual',
        'beneficiary_id': _wife,
        'notes': 'Manual: Dinner | PaidBy: $_wife | Beneficiary: $_wife | SpentBy: partner',
      });
      String cellOf(String csv) {
        final rows = csv.trim().split('\n').map((line) => line.split(',')).toList();
        return rows[1][headers.indexOf(l.get('csv_col_spent_by'))].replaceAll('"', '');
      }

      final named = CsvExportService.generateTransactionsCsv([wifeRow],
          headers: headers, deletedMemberLabel: l.get('deleted_member'), memberLabel: l.get('member'), memberNames: const {_wife: 'Noura'});
      expect(cellOf(named), 'Noura');

      final unnamed = CsvExportService.generateTransactionsCsv([wifeRow],
          headers: headers, deletedMemberLabel: l.get('deleted_member'), memberLabel: l.get('member'));
      expect(cellOf(unnamed), l.get('member'));
      expect(unnamed, isNot(contains(_wife)), reason: 'no member id in a file meant for people');
    });

    test('the feed export carries what the cell needs', () {
      final tx = Transaction.fromMap(_row({
        'id': 'wife',
        'user_id': null,
        'source': 'manual',
        'spent_by': 'partner',
        'beneficiary_type': 'individual',
        'beneficiary_id': _wife,
        'notes': 'Manual: Dinner | PaidBy: $_wife | Beneficiary: $_wife | SpentBy: partner',
      }));
      final l = AppLocalizations(const Locale('en'));
      final headers = CsvExportService.headersFor(l);
      final csv = CsvExportService.generateTransactionsCsv([CsvExportService.exportRowOf(tx)],
          headers: headers, deletedMemberLabel: l.get('deleted_member'), memberLabel: l.get('member'), memberNames: const {_wife: 'Noura'});
      expect(csv, contains('Noura'));
    });
  });
}
