// UX-29: the budgets list wraps its allocated / spent line instead of
// overflowing, and "deactivate" lives in a menu (with the existing
// confirmation) instead of an unlabelled gold icon next to "edit".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/screens/home/budget_management_screen.dart').readAsStringSync();

  test('no bare archive icon button next to edit', () {
    expect(src.contains('icon: const Icon(Icons.archive_outlined'), isFalse);
    expect(src.contains("key: const ValueKey('budget_row_menu')"), isTrue);
  });

  test('the allocated / spent line wraps', () {
    final i = src.indexOf("context.tr('not_set')");
    expect(i, greaterThan(0));
    final before = src.substring(i - 400, i);
    expect(before.contains('Wrap('), isTrue);
  });
}
