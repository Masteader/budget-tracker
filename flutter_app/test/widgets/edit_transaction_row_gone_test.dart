// Owner decision 2026-11-06: a wife's personal purchase is read only by her,
// her husband and an admin who is not a wife. A row can stop being readable
// while it is on screen (another member reclassified or deleted it); the
// database then changes nothing for an edit or a delete of it (RLS filters it
// out, no error). The sheet must not report a save or a delete that did not
// happen: it says the record is gone and closes with 'gone', so the feed
// reloads, and keeps the receipt photo.
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx() => Transaction(
      id: 'tx-stale',
      householdId: 'h1',
      amount: 120.0,
      currency: 'SAR',
      merchant: 'Salon',
      categoryCode: 'OPEX-SHOPPING',
      timestamp: DateTime(2026, 11, 5),
      isReallocated: false,
      createdAt: DateTime(2026, 11, 5),
      paidBy: 'me',
      beneficiary: 'me',
    );

void main() {
  group('requireRowReached', () {
    test('no row changed: the row is gone for this viewer', () {
      expect(() => requireRowReached(const []), throwsA(isA<TransactionRowGone>()));
    });

    test('a changed row passes', () {
      expect(() => requireRowReached(const [
            {'id': 'tx-stale'}
          ]), returnsNormally);
    });
  });

  /// Opens the sheet as the feed does; [result] holds what it closed with.
  Future<_Closed> openSheet(WidgetTester tester,
      {TransactionRowUpdater? updateRow, TransactionRowRemover? deleteRow}) async {
    final closed = _Closed();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              closed.result = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SingleChildScrollView(
                  child: EditTransactionSheet(
                    transaction: _tx(),
                    householdDependents: const [],
                    updateRow: updateRow,
                    deleteRow: deleteRow,
                  ),
                ),
              );
              closed.done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return closed;
  }

  testWidgets('an edit that reached no row is not reported as saved', (tester) async {
    final closed = await openSheet(tester, updateRow: (id, values) async => throw const TransactionRowGone());

    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('no longer exists'), findsOneWidget);
    expect(find.text('Changes Saved'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(closed.done, isTrue);
    expect(closed.result, 'gone');
  });

  testWidgets('a delete that reached no row is not reported as deleted', (tester) async {
    final closed = await openSheet(tester, deleteRow: (id) async => throw const TransactionRowGone());

    await tester.tap(find.byTooltip('Delete Transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('no longer exists'), findsOneWidget);
    expect(find.text('Transaction Deleted'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(closed.done, isTrue);
    expect(closed.result, 'gone');
  });
}

class _Closed {
  bool done = false;
  String? result;
}
