import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/models.dart';

Map<String, dynamic> _row(String? source, String? note) => {
      'id': 'tx-1',
      'household_id': 'hh-1',
      'amount': 10.0,
      'currency': 'SAR',
      'timestamp': '2026-10-20T12:00:00Z',
      'created_at': '2026-10-20T12:00:00Z',
      'source': source,
      'raw_sms': note,
    };

void main() {
  test('only chat, receipt_scan and manual channels exist (zero-SMS policy)', () {
    expect(Transaction.sources, equals({'chat', 'receipt_scan', 'manual'}));
  });

  test('known channels are kept as stored', () {
    expect(Transaction.fromMap(_row('chat', 'x')).source, 'chat');
    expect(Transaction.fromMap(_row('receipt_scan', 'x')).source, 'receipt_scan');
    expect(Transaction.fromMap(_row('manual', 'Manual: x')).source, 'manual');
  });

  test('unknown or legacy labels are shown by audit-note prefix, never as a new channel', () {
    expect(Transaction.fromMap(_row('legacy', 'Chat: panda 10')).source, 'chat');
    expect(Transaction.fromMap(_row('legacy', 'Receipt Scan: Tamimi')).source, 'receipt_scan');
    expect(Transaction.fromMap(_row('legacy', 'note')).source, 'manual');
    expect(Transaction.fromMap(_row(null, null)).source, 'manual');
  });
}
