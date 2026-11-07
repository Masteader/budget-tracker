// budgets.remaining_amount is GENERATED ALWAYS AS (allocated_amount - spent_amount).
// Postgres rejects any insert or update that writes it, so the whole write fails:
// linking an account to a category with no budget row, the budget repair clone and
// the rebalance sheet all failed this way.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no app code writes the generated budgets.remaining_amount column', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r"""['"]remaining_amount['"]\s*:""").hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
