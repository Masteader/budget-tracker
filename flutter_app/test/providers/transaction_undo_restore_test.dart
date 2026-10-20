// UI-25: undo after delete must restore the full original row (same id,
// payer/beneficiary/account/sub-category attribution, receipt), not a subset.
import 'dart:io';

import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '11111111-1111-1111-1111-111111111111';
const _receipt = 'https://x.supabase.co/storage/v1/object/sign/receipts/h1/r.jpg?token=t';

/// The row exactly as PostgREST returns it from `delete().select()`,
/// including columns the Transaction model does not know about.
final Map<String, dynamic> _dbRow = {
  'id': _id,
  'household_id': 'h1',
  'user_id': 'u-wife',
  'amount': 120.5,
  'currency': 'SAR',
  'merchant': 'Danube',
  'category_code': 'OPEX-GROCERY',
  'sub_category': 'sub-produce',
  'timestamp': '2026-10-19T09:00:00.000Z',
  'created_at': '2026-10-19T09:00:05.000Z',
  'is_reallocated': false,
  'reallocated_from_budget_id': null,
  'source': 'receipt_scan',
  'spent_by': 'partner',
  'paid_by': 'partner',
  'beneficiary': 'both',
  'beneficiary_type': 'household',
  'beneficiary_id': null,
  'account_id': 'acc-wife-wallet',
  'items': [
    {'name': 'Tomatoes', 'quantity': 2, 'price': 10.0},
  ],
  'receipt_url': _receipt,
  'qr_code_raw': 'AQ...',
  'cycle_key': '2026-09',
  'raw_sms': null,
};

Transaction _tx() => Transaction.fromMap(_dbRow);

void main() {
  late List<Map<String, dynamic>> inserted;
  late List<String> deletedReceipts;
  late bool failInsert;

  TransactionProvider build({
    List<Map<String, dynamic>>? deleteResult,
    Duration undoWindow = const Duration(seconds: 10),
  }) {
    final provider = TransactionProvider(
      deleteRow: (id) async => deleteResult ?? [Map<String, dynamic>.from(_dbRow)],
      insertRow: (row) async {
        if (failInsert) throw Exception('insert rejected');
        inserted.add(row);
      },
      deleteReceipt: (url) async => deletedReceipts.add(url),
      undoWindow: undoWindow,
    );
    provider.addTransaction(_tx());
    return provider;
  }

  setUp(() {
    inserted = [];
    deletedReceipts = [];
    failInsert = false;
  });

  test('undo re-inserts every original column with the same id', () async {
    final provider = build();

    expect(await provider.deleteTransaction(_id), isTrue);
    expect(provider.transactions, isEmpty);

    expect(await provider.restoreDeletedTransaction(_id), isTrue);

    expect(inserted, hasLength(1));
    expect(inserted.single, equals(_dbRow));
    for (final key in ['id', 'paid_by', 'beneficiary', 'account_id', 'sub_category', 'user_id', 'beneficiary_type', 'receipt_url']) {
      expect(inserted.single[key], _dbRow[key], reason: key);
    }
    expect(provider.transactions.single.id, _id);
    expect(provider.transactions.single.accountId, 'acc-wife-wallet');
  });

  test('falls back to the full model map when the delete returned no row', () async {
    final provider = build(deleteResult: const []);
    await provider.deleteTransaction(_id);
    await provider.restoreDeletedTransaction(_id);

    final row = inserted.single;
    expect(row['id'], _id);
    expect(row['paid_by'], 'partner');
    expect(row['beneficiary'], 'both');
    expect(row['account_id'], 'acc-wife-wallet');
    expect(row['sub_category'], 'sub-produce');
  });

  test('receipt image survives the undo window and is kept when undone', () async {
    final provider = build(undoWindow: const Duration(milliseconds: 80));
    await provider.deleteTransaction(_id);
    expect(deletedReceipts, isEmpty, reason: 'not deleted up front any more');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await provider.restoreDeletedTransaction(_id);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(deletedReceipts, isEmpty);
    expect(inserted.single['receipt_url'], _receipt);
  });

  test('receipt image is deleted once the undo window passes', () async {
    final provider = build(undoWindow: const Duration(milliseconds: 30));
    await provider.deleteTransaction(_id);
    expect(deletedReceipts, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(deletedReceipts, [_receipt]);
  });

  test('a failed restore reports false and cleans up the receipt', () async {
    final provider = build();
    await provider.deleteTransaction(_id);
    failInsert = true;

    expect(await provider.restoreDeletedTransaction(_id), isFalse);
    expect(deletedReceipts, [_receipt]);
    expect(await provider.restoreDeletedTransaction(_id), isFalse, reason: 'snapshot consumed');
  });

  test('undo snapshots do not survive a sign-out', () async {
    final provider = build();
    await provider.deleteTransaction(_id);

    provider.reset();

    expect(await provider.restoreDeletedTransaction(_id), isFalse);
    expect(inserted, isEmpty);
    expect(deletedReceipts, [_receipt], reason: 'pending cleanup flushed');
  });

  test('the feed undo uses the provider snapshot, not a hand-built subset', () {
    final src = File('lib/screens/home/transaction_feed_screen.dart').readAsStringSync();
    expect(src, contains('restoreDeletedTransaction(tx.id)'));
    expect(src, isNot(contains("from('transactions').insert(")));
  });

  test('a failed delete rolls back and keeps the receipt', () async {
    final provider = TransactionProvider(
      deleteRow: (_) async => throw Exception('rls'),
      insertRow: (row) async => inserted.add(row),
      deleteReceipt: (url) async => deletedReceipts.add(url),
    )..addTransaction(_tx());

    expect(await provider.deleteTransaction(_id), isFalse);
    expect(provider.transactions.single.id, _id);
    expect(deletedReceipts, isEmpty);
  });
}
