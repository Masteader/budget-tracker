import 'dart:async';
import 'package:flutter/foundation.dart';

/// Reconciles unlinked transactions first, then triggers a global provider refresh.
/// Runs refresh in a `finally` block to ensure UI is updated even if reconciliation fails.
Future<void> reconcileThenRefresh({
  required Future<void> Function() reconcile,
  required FutureOr<void> Function() refresh,
  required bool Function() isMounted,
}) async {
  try {
    await reconcile();
  } catch (e, st) {
    debugPrint('reconcile failed: $e');
    debugPrintStack(stackTrace: st);
  } finally {
    if (isMounted()) {
      await refresh();
    }
  }
}
