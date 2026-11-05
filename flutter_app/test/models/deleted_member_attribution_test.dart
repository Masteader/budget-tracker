// A row whose creator was deleted keeps `user_id` NULL and its `spent_by` as is
// (the column has a CHECK and the settlement engine reads it). It must never read
// as the viewer's: `spent_by = 'me'` means the departed creator there.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/services/csv_export_service.dart';
import 'package:budget_tracker/widgets/transaction_item_breakdown_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewer = 'aaaaaaaa-0000-4000-8000-00000000000a';

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

  group('the feed filter', () {
    test("'paid by me' does not list a deleted member's row", () {
      final provider = TransactionProvider();
      final deleted = Transaction.fromMap(_row({'id': 'gone', 'user_id': null, 'spent_by': 'me'}));
      final mine = Transaction.fromMap(_row({'id': 'mine', 'user_id': _viewer, 'spent_by': 'me'}));
      provider.setTransactionsForTesting([deleted, mine]);
      provider.setSpentByFilter('me');
      expect(provider.filteredTransactions.map((t) => t.id), ['mine']);
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
  });
}
