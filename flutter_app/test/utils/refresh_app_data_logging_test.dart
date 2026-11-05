// A provider refresh that fails is logged by its type only: its message can
// carry balances, e-mail addresses or server detail, and `debugPrint` is not
// stripped from release builds.
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/utils/refresh_app_data.dart';
import 'package:flutter/foundation.dart' show DebugPrintCallback;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _secret = 'Insufficient funds: balance (1234.56) owner@example.com';

class _FailingTransactions extends TransactionProvider {
  @override
  Future<void> fetchTransactions() async => throw const PostgrestException(message: _secret, code: 'P0001');
}

void main() {
  testWidgets('a failed refresh logs the site and the error type, never the message', (tester) async {
    final log = <String>[];
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) log.add(message);
    };
    addTearDown(() => debugPrint = original);

    late BuildContext captured;
    await tester.pumpWidget(ChangeNotifierProvider<TransactionProvider>(
      create: (_) => _FailingTransactions(),
      child: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    await refreshGlobalAppData(captured);
    debugPrint = original;

    expect(log, contains('[refreshGlobalAppData] failed: PostgrestException(code: P0001)'));
    expect(log.where((l) => l.contains('1234.56') || l.contains('owner@example.com') || l.contains('Insufficient')), isEmpty);
  });
}
