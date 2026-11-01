import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/post_commit_sync.dart';

void main() {
  group('reconcileThenRefresh (CRITICAL-04)', () {
    test('reconcile completes before refresh starts', () async {
      final log = <String>[];

      await reconcileThenRefresh(
        reconcile: () async {
          log.add('reconcile:start');
          await Future.delayed(const Duration(milliseconds: 10));
          log.add('reconcile:end');
        },
        refresh: () async {
          log.add('refresh');
        },
        isMounted: () => true,
      );

      expect(log, equals(['reconcile:start', 'reconcile:end', 'refresh']));
    });

    test('if reconcile throws, refresh still runs and error is caught', () async {
      final log = <String>[];

      await reconcileThenRefresh(
        reconcile: () async {
          log.add('reconcile:start');
          throw Exception('Network timeout');
        },
        refresh: () async {
          log.add('refresh');
        },
        isMounted: () => true,
      );

      expect(log, equals(['reconcile:start', 'refresh']));
    });

    test('if isMounted returns false, refresh is skipped', () async {
      final log = <String>[];

      await reconcileThenRefresh(
        reconcile: () async {
          log.add('reconcile');
        },
        refresh: () async {
          log.add('refresh');
        },
        isMounted: () => false,
      );

      expect(log, equals(['reconcile']));
    });
  });
}
