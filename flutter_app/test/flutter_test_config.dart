import 'dart:async';

import 'package:budget_tracker/widgets/nafaqah/unconfirmed_payments.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. A payment whose answer was lost is kept for
/// the app session (review R2-02); each test starts with none.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(UnconfirmedPayments.reset);
  await testMain();
}
