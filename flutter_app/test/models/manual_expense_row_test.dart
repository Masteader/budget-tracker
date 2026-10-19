import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/models/manual_expense_row.dart';
import 'package:budget_tracker/models/models.dart';

/// Columns of public.transactions as created by supabase/migrations
/// (verified against the migrated local audit database).
const _transactionColumns = {
  'id', 'household_id', 'user_id', 'amount', 'currency', 'merchant', 'category_code',
  'timestamp', 'raw_sms', 'is_reallocated', 'reallocated_from_budget_id', 'created_at',
  'source', 'items', 'receipt_url', 'dedup_fingerprint', 'spent_by', 'sub_category',
  'cycle_key', 'qr_code_raw', 'beneficiary_type', 'beneficiary_id', 'is_settlement',
  'settlement_target_id', 'line_items', 'account_id',
};

void main() {
  Map<String, dynamic> wifeReimbursable() => buildManualExpenseRow(
        id: '6f1c2a3e-0000-4000-8000-000000000001',
        householdId: 'h-1',
        userId: 'u-1',
        amount: 87.5,
        merchant: 'Tamimi',
        categoryCode: 'OPEX-GROCERY',
        spentBy: 'partner',
        paidBy: 'wife',
        beneficiaryType: 'household',
        beneficiaryId: 'household',
        accountId: null,
        // 23:30 in Riyadh on the 26th = 20:30 UTC.
        occurredAt: DateTime.utc(2026, 10, 26, 20, 30),
      );

  test('MOB-03: only real transactions columns are written (no paid_by column)', () {
    final row = wifeReimbursable();
    expect(row.keys.toSet().difference(_transactionColumns), isEmpty);
  });

  test('MOB-03: the wife-paid attribution survives as the PaidBy audit tag', () {
    final row = wifeReimbursable();
    final tx = Transaction.fromMap({
      ...row,
      'created_at': '2026-10-26T20:30:01Z',
    });
    expect(tx.paidBy, 'partner');
    expect(tx.spentBy, 'partner');
  });

  test('MOB-24: the timestamp is an explicit UTC instant', () {
    final row = wifeReimbursable();
    expect(row['timestamp'], '2026-10-26T20:30:00.000Z');
  });

  test('manualPayerAuditTag keeps me/partner and roommate ids', () {
    expect(manualPayerAuditTag('me'), 'me');
    expect(manualPayerAuditTag('wife'), 'partner');
    expect(manualPayerAuditTag('3b0f-roommate'), '3b0f-roommate');
  });
}
