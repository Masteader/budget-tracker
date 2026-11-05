// The typed confirmation word, against the one table the server and the web
// page are tested with too: supabase/tests/52_account_deletion_fold_table.sql
// holds it between its $fold_cases$ markers, and checks it there against
// account_deletion_fold_confirmation and the real request_account_deletion.
import 'dart:convert';
import 'dart:io';

import 'package:budget_tracker/models/account_deletion.dart';
import 'package:flutter_test/flutter_test.dart';

const _tablePath = '../supabase/tests/52_account_deletion_fold_table.sql';

/// The JSON array between the two markers.
final _table = RegExp(r'\$fold_cases\$\s*(\[.*?\])\s*\$fold_cases\$', dotAll: true);

List<Map<String, dynamic>> _readTable() {
  final found = _table.firstMatch(File(_tablePath).readAsStringSync());
  if (found == null) throw StateError('no fold_cases table in $_tablePath');
  return (jsonDecode(found[1]!) as List).cast<Map<String, dynamic>>();
}

void main() {
  final table = _readTable();

  test('the shared table is there and covers both outcomes', () {
    expect(table.length, greaterThanOrEqualTo(30));
    expect(table.map((r) => r['id']).toSet().length, table.length);
    expect(table.where((r) => r['match'] == true), isNotEmpty);
    expect(table.where((r) => r['match'] == false), isNotEmpty);
    // The cases the release review named.
    for (final id in [
      'lrm-inside-word',
      'zwnj-between-words',
      'zwnj-inside-arabic-word',
      'ur-arabic-keyboard',
      'nbsp-between-words',
      'en-upper',
      'combining-acute-decomposed',
    ]) {
      expect(table.map((r) => r['id']), contains(id));
    }
  });

  for (final row in table) {
    final id = row['id'] as String;
    final input = row['input'] as String;
    final fold = row['fold'] as String;
    final differs = (row['fold_differs'] as List).contains('dart');

    test('$id: ${row['match'] == true ? 'accepted' : 'refused'}, as the server does', () {
      expect(confirmationWordMatches(input), row['match'], reason: row['note'] as String);
    });

    test('$id: folds to the server\'s text${differs ? ' (differs: no NFC in the app)' : ''}', () {
      if (differs) {
        // Marked in the table because the app has no NFC; a stale mark fails.
        expect(foldConfirmationWord(input), isNot(fold));
      } else {
        expect(foldConfirmationWord(input), fold);
      }
    });
  }
}
