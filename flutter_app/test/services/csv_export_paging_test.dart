// The monthly export against a fake PostgREST that behaves like the real one:
// it caps every response and answers 200 with partial rows.
import 'dart:convert';

import 'package:budget_tracker/services/csv_export_service.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakePostgrest extends http.BaseClient {
  _FakePostgrest(this.rows, {this.cap = 1000, this.payday = 27});

  final List<Map<String, dynamic>> rows;
  final int cap;
  int? payday;
  bool failPayday = false;
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    requests.add(url);
    Object? body;
    var status = 200;
    if (url.path.endsWith('/households')) {
      if (failPayday) {
        status = 500;
        body = {'message': 'boom', 'code': 'XX000'};
      } else {
        body = payday == null
            ? <Object>[]
            : [
                {'payday_day': payday}
              ];
      }
    } else {
      body = page(url);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }

  List<Map<String, dynamic>> page(Uri url) {
    final q = url.queryParameters;
    final hid = q['household_id']!.replaceFirst('eq.', '');
    final key = q['cycle_key']!.replaceFirst('eq.', '');
    final matching = rows.where((r) => r['household_id'] == hid && r['cycle_key'] == key).toList();
    final clauses = (q['order'] ?? '').split(',').where((c) => c.isNotEmpty).map((c) => c.split('.')).toList();
    // Ties the query did not break come back in whatever order Postgres likes:
    // different on each request.
    if (!clauses.any((c) => c.first == 'id')) matching.shuffle();
    mergeSort(matching, (a, b) {
      for (final c in clauses) {
        final cmp = '${a[c[0]]}'.compareTo('${b[c[0]]}');
        if (cmp != 0) return c.length > 1 && c[1] == 'desc' ? -cmp : cmp;
      }
      return 0;
    });
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? cap;
    return matching.skip(offset).take(limit < cap ? limit : cap).toList();
  }
}

/// A stable sort, so a shuffled tie stays shuffled.
void mergeSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      final cmp = compare(a.$2, b.$2);
      return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
    });
  list
    ..clear()
    ..addAll(indexed.map((e) => e.$2));
}

class _IgnoresOffset extends _FakePostgrest {
  _IgnoresOffset(super.rows);

  @override
  List<Map<String, dynamic>> page(Uri url) => rows;
}

class _FailsSecondPage extends _FakePostgrest {
  _FailsSecondPage(super.rows);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if ((int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0) > 0) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'message': 'boom', 'code': 'XX000'}))),
        500,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    return super.send(request);
  }
}

Map<String, dynamic> _row(
  int i, {
  String timestamp = '2026-11-01T10:00:00Z',
  double amount = 1,
  String key = '2026-11',
  String hid = 'hh-1',
  bool? settlement,
  String? nafaqahClass,
}) =>
    {
      'id': 'tx-${i.toString().padLeft(5, '0')}',
      'household_id': hid,
      'cycle_key': key,
      'timestamp': timestamp,
      'amount': amount,
      if (settlement != null) 'is_settlement': settlement,
      'nafaqah_class': nafaqahClass,
    };

SupabaseClient _client(http.Client http) => SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: http,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

Future<List<Map<String, dynamic>>> _fetch(_FakePostgrest server) =>
    CsvExportService.fetchCycleRows(_client(server), householdId: 'hh-1', cycleKey: '2026-11');

void main() {
  group('paging (B1)', () {
    for (final total in [0, 1, 999, 1000, 1001, 1200, 2000, 2500]) {
      test('$total rows behind a 1000-row cap all arrive, once each', () async {
        final server = _FakePostgrest([
          for (var i = 0; i < total; i++) _row(i, timestamp: '2026-11-01T10:${(i % 60).toString().padLeft(2, '0')}:00Z'),
        ]);
        final rows = await _fetch(server);
        expect(rows.length, total);
        expect(rows.map((r) => r['id']).toSet().length, total);
      });
    }

    test('a cap below the requested page size does not end the export early', () async {
      final server = _FakePostgrest([for (var i = 0; i < 1200; i++) _row(i)], cap: 500);
      expect((await _fetch(server)).length, 1200);
    });

    test('rows sharing one timestamp neither repeat nor vanish across pages', () async {
      final server = _FakePostgrest([for (var i = 0; i < 2500; i++) _row(i)]);
      final rows = await _fetch(server);
      expect(rows.map((r) => r['id']).toSet().length, 2500);
    });

    test('asks for a stable order, newest first', () async {
      final server = _FakePostgrest([_row(1, timestamp: '2026-11-01T10:00:00Z'), _row(2, timestamp: '2026-11-02T10:00:00Z')]);
      final rows = await _fetch(server);
      final order = server.requests.first.queryParameters['order']!;
      expect(order, startsWith('timestamp.desc'));
      expect(order, contains('id.desc'));
      expect(rows.first['id'], 'tx-00002');
    });

    test('a server that ignores the offset cannot hang the export or truncate it silently', () async {
      final server = _IgnoresOffset([for (var i = 0; i < 10; i++) _row(i)]);
      await expectLater(_fetch(server), throwsStateError);
    });

    test('a failed page fails the export instead of returning what arrived so far', () async {
      final server = _FailsSecondPage([for (var i = 0; i < 1500; i++) _row(i)]);
      await expectLater(_fetch(server), throwsA(isA<PostgrestException>()));
    });

    test('only this household and cycle are asked for', () async {
      final server = _FakePostgrest([_row(1), _row(2, hid: 'hh-2'), _row(3, key: '2026-10')]);
      final rows = await _fetch(server);
      expect(rows.map((r) => r['id']), ['tx-00001']);
    });
  });

  group('the same rows as the other cycle views (B2)', () {
    test('settlements and wife personal purchases are left out, NULL classes stay', () async {
      final server = _FakePostgrest([
        _row(1, amount: 5000),
        _row(2, amount: 700, settlement: true),
        _row(3, amount: 300, nafaqahClass: 'wife_personal'),
        _row(4, amount: 100, nafaqahClass: 'wife_reimbursable'),
        _row(5, amount: 50, settlement: false),
      ]);
      final rows = await _fetch(server);
      expect(rows.map((r) => r['id']).toSet(), {'tx-00001', 'tx-00004', 'tx-00005'});
      expect(rows.fold<double>(0, (s, r) => s + (r['amount'] as num)), 5150);
    });

    test('exclusions do not make a full page look like the end', () async {
      final server = _FakePostgrest([
        for (var i = 0; i < 1000; i++) _row(i, settlement: true, timestamp: '2026-11-02T10:00:00Z'),
        for (var i = 1000; i < 1100; i++) _row(i, timestamp: '2026-11-01T10:00:00Z'),
      ]);
      expect((await _fetch(server)).length, 100);
    });
  });

  group('the cycle comes from this household\'s payday (B3)', () {
    final nov5 = DateTime.utc(2026, 11, 5, 9);

    Future<CycleExport> load(_FakePostgrest s) =>
        CsvExportService.loadCurrentCycle(_client(s), householdId: 'hh-1', now: nov5);

    test('payday 10 on 5 Nov selects 2026-10, not the default payday\'s 2026-11', () async {
      final server = _FakePostgrest([_row(1, key: '2026-10'), _row(2, key: '2026-11')], payday: 10);
      final export = await load(server);
      expect(export.cycle.key, '2026-10');
      expect(export.cycle.start, DateTime.utc(2026, 10, 10));
      expect(export.cycle.end, DateTime.utc(2026, 11, 9));
      expect(export.rows.map((r) => r['id']), ['tx-00001']);
    });

    test('payday 27 and payday 1 name their own cycles', () async {
      expect((await load(_FakePostgrest(const [], payday: 27))).cycle, SalaryCycleService.currentCycle(now: nov5, paydayDay: 27));
      final first = (await load(_FakePostgrest(const [], payday: 1))).cycle;
      expect(first.key, '2026-11');
      expect(first.start, DateTime.utc(2026, 11, 1));
    });

    test('the device-wide payday is not used', () async {
      SalaryCycleService.paydayDay = 27;
      addTearDown(() => SalaryCycleService.paydayDay = 27);
      expect((await load(_FakePostgrest(const [], payday: 10))).cycle.key, '2026-10');
    });

    test('a household that cannot be read fails the export; no cycle is guessed', () async {
      final server = _FakePostgrest([_row(1)], payday: null);
      await expectLater(load(server), throwsStateError);
      expect(server.requests.where((u) => u.path.endsWith('/transactions')), isEmpty);
    });

    test('a failed payday read fails the export', () async {
      final server = _FakePostgrest([_row(1)])..failPayday = true;
      await expectLater(load(server), throwsA(isA<PostgrestException>()));
      expect(server.requests.where((u) => u.path.endsWith('/transactions')), isEmpty);
    });
  });
}
