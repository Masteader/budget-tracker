// linkCategoryAccount against a fake PostgREST `budgets` table that, like the
// real one, is UNIQUE (household_id, month, category_code). A cycle's rows are
// found the way the backend's cycle_budget_rows finds them: rows keyed by the
// cycle, or legacy rows without a cycle_key whose month is the cycle's month.
import 'dart:convert';

import 'package:budget_tracker/services/account_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBudgets extends http.BaseClient {
  _FakeBudgets(List<Map<String, dynamic>> rows) : rows = [for (final r in rows) Map<String, dynamic>.from(r)];

  final List<Map<String, dynamic>> rows;
  final inserts = <Map<String, dynamic>>[];
  final patchedIds = <String>[];

  static bool _matches(Map<String, dynamic> row, Map<String, String> q) {
    for (final e in q.entries) {
      final col = e.key;
      final v = e.value;
      if (v.startsWith('eq.')) {
        if ('${row[col]}' != v.substring(3)) return false;
      } else if (v.startsWith('in.(') && v.endsWith(')')) {
        final ids = v.substring(4, v.length - 1).split(',').map((s) => s.replaceAll('"', ''));
        if (!ids.contains('${row[col]}')) return false;
      } else if (v == 'is.null') {
        if (row[col] != null) return false;
      }
    }
    return true;
  }

  http.StreamedResponse _json(http.BaseRequest request, int status, Object? body) => http.StreamedResponse(
        Stream.value(utf8.encode(body == null ? '' : jsonEncode(body))),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.url.path, endsWith('/budgets'));
    final q = Map<String, String>.from(request.url.queryParameters)
      ..remove('select')
      ..remove('columns');
    final bodyText = request is http.Request ? request.body : '';
    switch (request.method) {
      case 'GET':
        return _json(request, 200, rows.where((r) => _matches(r, q)).toList());
      case 'PATCH':
        final patch = jsonDecode(bodyText) as Map<String, dynamic>;
        for (final r in rows.where((r) => _matches(r, q))) {
          patchedIds.add(r['id'] as String);
          r.addAll(patch);
        }
        return _json(request, 204, null);
      case 'POST':
        final decoded = jsonDecode(bodyText);
        final row = Map<String, dynamic>.from(decoded is List ? decoded.single as Map : decoded as Map);
        final clash = rows.any((r) =>
            r['household_id'] == row['household_id'] &&
            r['category_code'] == row['category_code'] &&
            '${r['month']}'.substring(0, 10) == '${row['month']}'.substring(0, 10));
        if (clash) {
          return _json(request, 409, {
            'code': '23505',
            'message': 'duplicate key value violates unique constraint "budgets_household_id_month_category_code_key"',
            'details': null,
            'hint': null,
          });
        }
        inserts.add(row);
        rows.add({'id': 'new-${inserts.length}', ...row});
        return _json(request, 201, null);
    }
    fail('unexpected ${request.method} ${request.url}');
  }

  Map<String, dynamic> row(String id) => rows.firstWhere((r) => r['id'] == id);
}

SupabaseClient _client(http.Client http) => SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: http,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

Map<String, dynamic> _budget(String id, {String? key, required String month, String cat = 'OPEX-GROCERIES', String hid = 'hh-1', String? account}) => {
      'id': id,
      'household_id': hid,
      'category_code': cat,
      'cycle_key': key,
      'month': month,
      'account_id': account,
    };

Future<void> _link(_FakeBudgets server, {String cycleKey = '2026-11', String? accountId = 'acc-1'}) =>
    AccountService(client: _client(server)).linkCategoryAccount(
      householdId: 'hh-1',
      categoryCode: 'OPEX-GROCERIES',
      cycleKey: cycleKey,
      accountId: accountId,
    );

void main() {
  group('AccountService.linkCategoryAccount finds the cycle row like cycle_budget_rows', () {
    test('a legacy row of the cycle (no cycle_key, month = cycle month) is linked and keyed, nothing inserted', () async {
      final server = _FakeBudgets([_budget('legacy', month: '2026-11-01')]);

      await _link(server);

      expect(server.inserts, isEmpty);
      expect(server.row('legacy')['account_id'], 'acc-1');
      expect(server.row('legacy')['cycle_key'], '2026-11');
    });

    test('a legacy row whose month carries a time part still counts as the cycle row', () async {
      final server = _FakeBudgets([_budget('legacy', month: '2026-11-01T00:00:00')]);

      await _link(server);

      expect(server.inserts, isEmpty);
      expect(server.row('legacy')['account_id'], 'acc-1');
      expect(server.row('legacy')['cycle_key'], '2026-11');
    });

    test('two rows of the cycle do not throw; both are linked', () async {
      final server = _FakeBudgets([
        _budget('keyed-a', key: '2026-11', month: '2026-10-01'),
        _budget('keyed-b', key: '2026-11', month: '2026-11-01'),
      ]);

      await _link(server);

      expect(server.inserts, isEmpty);
      expect(server.row('keyed-a')['account_id'], 'acc-1');
      expect(server.row('keyed-b')['account_id'], 'acc-1');
    });

    test('a keyed row and a legacy row of the same cycle are both linked, and the legacy one is keyed', () async {
      final server = _FakeBudgets([
        _budget('keyed', key: '2026-11', month: '2026-10-01'),
        _budget('legacy', month: '2026-11-01'),
      ]);

      await _link(server);

      expect(server.inserts, isEmpty);
      expect(server.row('keyed')['account_id'], 'acc-1');
      expect(server.row('legacy')['account_id'], 'acc-1');
      expect(server.row('legacy')['cycle_key'], '2026-11');
    });

    test('unlinking (null account) clears the legacy row of the cycle', () async {
      final server = _FakeBudgets([_budget('legacy', month: '2026-11-01', account: 'acc-old')]);

      await _link(server, accountId: null);

      expect(server.inserts, isEmpty);
      expect(server.row('legacy')['account_id'], isNull);
      expect(server.row('legacy')['cycle_key'], '2026-11');
    });

    test('no row of the cycle: exactly one insert, with the cycle month and key', () async {
      final server = _FakeBudgets([]);

      await _link(server);

      expect(server.patchedIds, isEmpty);
      expect(server.inserts, hasLength(1));
      final ins = server.inserts.single;
      expect(ins['household_id'], 'hh-1');
      expect(ins['category_code'], 'OPEX-GROCERIES');
      expect(ins['cycle_key'], '2026-11');
      expect(ins['month'], '2026-11-01');
      expect(ins['account_id'], 'acc-1');
    });

    test("another cycle's rows, legacy rows of other months and other categories are never touched", () async {
      final server = _FakeBudgets([
        _budget('other-cycle', key: '2026-10', month: '2026-10-01', account: 'acc-old'),
        _budget('legacy-other-month', month: '2026-12-01', account: 'acc-old'),
        _budget('other-cat', key: '2026-11', month: '2026-11-01', cat: 'OPEX-TRANSPORT', account: 'acc-old'),
        _budget('other-hh', key: '2026-11', month: '2026-11-01', hid: 'hh-2', account: 'acc-old'),
      ]);

      await _link(server);

      expect(server.patchedIds, isEmpty);
      expect(server.inserts, hasLength(1));
      expect(server.inserts.single['month'], '2026-11-01');
      for (final id in ['other-cycle', 'legacy-other-month', 'other-cat', 'other-hh']) {
        expect(server.row(id)['account_id'], 'acc-old', reason: id);
      }
      expect(server.row('other-cycle')['cycle_key'], '2026-10');
      expect(server.row('legacy-other-month')['cycle_key'], isNull);
    });
  });
}
