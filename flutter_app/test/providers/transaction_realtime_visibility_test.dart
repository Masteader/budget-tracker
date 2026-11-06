// Owner decision 2026-11-06: a wife's personal purchase is read only by her,
// her husband and an admin who is not a wife (the transactions read policy).
// Realtime follows that policy, so a viewer gets an UPDATE for a row they did
// not read before when it becomes readable to them (a co-wife's purchase
// reclassified as a household expense): the list must take it in, in its
// place, and totals must follow. Rows the viewer never reads are never there.
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent;

Map<String, dynamic> _row(String id, String merchant, double amount, String when, {String? cls, String? wife}) => {
      'id': id,
      'household_id': 'h1',
      'user_id': 'u-$id',
      'amount': amount,
      'currency': 'SAR',
      'merchant': merchant,
      'category_code': 'OPEX-SHOPPING',
      'timestamp': when,
      'created_at': when,
      'is_reallocated': false,
      'nafaqah_class': cls,
      'nafaqah_spouse_id': wife,
    };

void main() {
  late TransactionProvider provider;

  setUp(() {
    provider = TransactionProvider(deleteRow: (_) async => const [], insertRow: (_) async {}, deleteReceipt: (_) async {});
    provider.setTransactionsForTesting([
      Transaction.fromMap(_row('t-new', 'Danube', 50, '2026-11-05T10:00:00Z')),
      Transaction.fromMap(_row('t-old', 'Bakery', 20, '2026-11-01T10:00:00Z')),
    ]);
  });

  test('a row that becomes readable through an update is taken in, in its place', () {
    // The co-wife's purchase, now a household expense: she never had it.
    provider.applyRealtimeChange(
      PostgresChangeEvent.update,
      newRecord: _row('t-mid', 'Salon', 300, '2026-11-03T10:00:00Z'),
    );

    expect(provider.transactions.map((t) => t.id), ['t-new', 't-mid', 't-old']);
    expect(provider.filteredTransactions.map((t) => t.id), ['t-new', 't-mid', 't-old']);
  });

  test('an update of a row the viewer has replaces it, without a second copy', () {
    provider.applyRealtimeChange(
      PostgresChangeEvent.update,
      newRecord: _row('t-old', 'Bakery', 25, '2026-11-01T10:00:00Z'),
    );

    expect(provider.transactions.map((t) => t.id), ['t-new', 't-old']);
    expect(provider.transactions.last.amount, 25);
  });

  test('an insert, an update and a delete keep the list and its total in step', () {
    provider.applyRealtimeChange(PostgresChangeEvent.insert,
        newRecord: _row('t-in', 'Jarir', 70, '2026-11-06T10:00:00Z'));
    provider.applyRealtimeChange(PostgresChangeEvent.delete, oldRecord: {'id': 't-new'});
    // A delete of a row the viewer never read (Realtime sends deletes with the id only): nothing.
    provider.applyRealtimeChange(PostgresChangeEvent.delete, oldRecord: {'id': 't-never-read'});

    expect(provider.transactions.map((t) => t.id), ['t-in', 't-old']);
    final total = provider.transactions.fold<double>(0, (s, t) => s + t.amount);
    expect(total, 90);
  });

  test('an empty update record changes nothing', () {
    provider.applyRealtimeChange(PostgresChangeEvent.update, newRecord: const {});
    expect(provider.transactions.map((t) => t.id), ['t-new', 't-old']);
  });
}
