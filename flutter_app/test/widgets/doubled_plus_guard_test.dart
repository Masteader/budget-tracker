// UX-24: a "+" icon next to a label that starts with "+" shows the plus twice.
import 'dart:io';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no label is built as "+ <translated text>"', () {
    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r"""['"]\+ \$\{context\.tr""").hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('no translated button label starts with "+"', () {
    for (final lang in ['en', 'ar', 'ur']) {
      final l = AppLocalizations(Locale(lang));
      for (final key in ['hmc_add_member', 'add_installment_plan']) {
        expect(l.get(key).trimLeft().startsWith('+'), isFalse, reason: '$lang $key');
      }
    }
  });
}
