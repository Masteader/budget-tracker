import 'dart:io';

import 'package:budget_tracker/widgets/nafaqah/nafaqah_class_selector.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _husband = {'id': 'u-husband', 'display_name': 'Abu Fahad', 'financial_role': 'provider'};
const _wife = {'id': 'u-wife', 'display_name': 'Umm Fahad', 'financial_role': 'spouse'};
const _peerA = {'id': 'u-a', 'display_name': 'Majed', 'financial_role': 'peer'};
const _peerB = {'id': 'u-b', 'display_name': 'Salman', 'financial_role': 'peer'};

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required List<Map<String, dynamic>> members,
    String currentUser = 'u-husband',
    Future<void> Function(Map<String, dynamic> row)? insertRow,
    Future<void> Function(Map<String, dynamic> row, String householdId)? enqueueRow,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ManualExpenseSheet(
                  householdId: 'h1',
                  initialMerchant: 'Panda',
                  initialAmount: 120,
                  loadMembers: (_) async => members,
                  currentUserId: () => currentUser,
                  insertRow: insertRow ?? (_) async {},
                  enqueueRow: enqueueRow ?? (_, __) async {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byIcon(Icons.check_rounded);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  // FR-A-05: a family household (spouse member) never offers the roommate
  // equal split between the spouses.
  testWidgets('family household: Nafaqah choice only, no roommate split toggle', (tester) async {
    await openSheet(tester, members: [_husband, _wife]);

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsNothing);
    expect(find.byType(NafaqahClassSelector), findsOneWidget);
  });

  testWidgets('roommate household keeps the mode toggle and has no Nafaqah choice', (tester) async {
    await openSheet(tester, members: [_peerA, _peerB], currentUser: 'u-a');

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsOneWidget);
    expect(find.byType(NafaqahClassSelector), findsNothing);
  });

  // FR-A-08: a row the database rejects is not reported as "saved offline".
  testWidgets('a database rejection is shown and never queued offline', (tester) async {
    var queued = 0;
    await openSheet(
      tester,
      members: [_husband, _wife],
      insertRow: (_) async => throw const PostgrestException(
        message: 'nafaqah_spouse_id is not a spouse member of household',
        code: '23503',
      ),
      enqueueRow: (_, __) async => queued++,
    );

    await tapSave(tester);

    expect(queued, 0);
    expect(find.byType(ManualExpenseSheet), findsOneWidget, reason: 'the sheet stays open to retry');
    expect(find.textContaining('not a spouse member'), findsOneWidget);
  });

  testWidgets('a network failure is queued offline with the same row', (tester) async {
    Map<String, dynamic>? queuedRow;
    Map<String, dynamic>? triedRow;
    await openSheet(
      tester,
      members: [_husband, _wife],
      insertRow: (row) async {
        triedRow = row;
        throw const SocketException('offline');
      },
      enqueueRow: (row, _) async => queuedRow = row,
    );

    await tapSave(tester);

    expect(queuedRow, isNotNull);
    expect(queuedRow!['id'], triedRow!['id']);
    expect(find.byType(ManualExpenseSheet), findsNothing);
  });
}
