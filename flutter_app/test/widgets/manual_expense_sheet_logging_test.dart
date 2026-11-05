// The manual expense sheet logs a failure by its type and code only: an error's
// message can carry balances, e-mail addresses or server detail, and
// `debugPrint` is not stripped from release builds.
import 'dart:io';

import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/foundation.dart' show DebugPrintCallback;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// What an error message may carry and the log must not.
const _secret = 'Insufficient funds: balance (1234.56) owner@example.com';

void main() {
  late List<String> log;
  late DebugPrintCallback original;

  setUp(() {
    log = <String>[];
    original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) log.add(message);
    };
  });
  tearDown(() => debugPrint = original);

  Future<void> openAndSave(WidgetTester tester) async {
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
                  loadRoster: (_) async => throw const PostgrestException(message: _secret, code: 'P0001'),
                  loadOwnMemberships: (_) async => [
                    {'user_id': 'u-a', 'role': 'admin', 'financial_role': 'peer'},
                  ],
                  currentUserId: () => 'u-a',
                  insertRow: (_) async {},
                  enqueueRow: (_, __) async {},
                  loadNafaqah: (_) async => throw Exception(_secret),
                  loadAccounts: (_) async => const [],
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
    final save = find.byIcon(Icons.check_rounded);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets('each failure is logged by its site and type, never by its message', (tester) async {
    await openAndSave(tester);
    debugPrint = original;

    expect(log, contains('[ManualExpenseSheet.members] failed: PostgrestException(code: P0001)'));
    expect(log, contains('[ManualExpenseSheet.nafaqahContext] failed: _Exception'));
    expect(log.where((l) => l.contains('1234.56') || l.contains('owner@example.com') || l.contains('Insufficient')), isEmpty);
  });

  // The refresh after a save cannot fail where a test can reach it (it is
  // async and catches its own errors), so its site is held to the rule here.
  test('the sheet never prints an error itself; every site goes through logFailure', () {
    final src = File('lib/widgets/transactions/manual_expense_sheet.dart').readAsStringSync();
    expect(src, isNot(contains('debugPrint(')));
    for (final site in ['members', 'nafaqahContext', 'refreshAfterSave']) {
      expect(src, contains("logFailure('ManualExpenseSheet.$site', e)"));
    }
  });
}
