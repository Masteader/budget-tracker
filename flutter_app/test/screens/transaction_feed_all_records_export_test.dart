// The feed's "All Records" export is what the household deletion banner sends
// members to before their history is deleted. It must hold every row, not the
// first page the server is willing to return.
import 'dart:convert';

import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/providers/budget_provider.dart';
import 'package:budget_tracker/providers/recurring_bills_provider.dart';
import 'package:budget_tracker/providers/transaction_provider.dart';
import 'package:budget_tracker/screens/home/transaction_feed_screen.dart';
import 'package:budget_tracker/services/csv_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/localized_app.dart';

/// PostgREST as deployed: never more than [cap] rows per response, answered
/// with 200 whatever the request asked for.
class _CappedPostgrest extends http.BaseClient {
  _CappedPostgrest(this.rows, {this.cap = 1000});

  final List<Map<String, dynamic>> rows;
  final int cap;
  bool fail = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final q = request.url.queryParameters;
    if (fail) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'message': 'boom', 'code': 'XX000'}))),
        500,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    final hid = q['household_id']!.replaceFirst('eq.', '');
    final matching = rows.where((r) => r['household_id'] == hid).toList()
      ..sort((a, b) {
        final t = '${b['timestamp']}'.compareTo('${a['timestamp']}');
        return t != 0 ? t : '${b['id']}'.compareTo('${a['id']}');
      });
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? cap;
    final body = matching.skip(offset).take(limit < cap ? limit : cap).toList();
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _FakeTransactions extends TransactionProvider {
  _FakeTransactions(this._rows);
  final List<Transaction> _rows;
  @override
  List<Transaction> get transactions => _rows;
  @override
  bool get isLoading => false;
}

Map<String, dynamic> _row(int i, {String hid = 'h1'}) => {
      'id': 'tx-${i.toString().padLeft(5, '0')}',
      'household_id': hid,
      'amount': 1.0,
      'currency': 'SAR',
      'merchant': 'Store $i',
      'category_code': 'OPEX-GROCERY',
      'timestamp': DateTime.utc(2026, 1, 1).add(Duration(hours: i)).toIso8601String(),
      'created_at': DateTime.utc(2026, 1, 1).add(Duration(hours: i)).toIso8601String(),
      'spent_by': 'me',
      'user_id': 'u-1',
    };

Future<void> _openExport(WidgetTester tester, _CappedPostgrest server, {required List<Transaction> feedRows}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-key',
    httpClient: server,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TransactionProvider>(create: (_) => _FakeTransactions(feedRows)),
      ChangeNotifierProvider<BudgetProvider>(create: (_) => BudgetProvider()),
      ChangeNotifierProvider<RecurringBillsProvider>(create: (_) => RecurringBillsProvider()),
    ],
    child: localizedApp(
      TransactionFeedScreen(
        householdId: 'h1',
        loadNafaqah: (_) async => const NafaqahSummary(mode: 'standard'),
        loadCycles: (_) async => const {'cycles': <Object>[]},
        loadAllRecords: (hid) => CsvExportService.fetchAllHouseholdRows(client, householdId: hid),
      ),
      lang: 'en',
      scaffold: false,
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('feed_more_menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuItem && w.value == 'csv'));
  await tester.pumpAndSettle();
}

final _l = AppLocalizations(const Locale('en'));

void main() {
  final l = _l;

  // The client decodes a response over 10 kB on a real isolate, which a widget
  // test's fake time never runs, so this server caps at 20 rows a page; the
  // 1000-row cap is proven in services/csv_export_paging_test.dart.
  testWidgets('50 records behind a 20-row cap: the export holds all 50, not the feed\'s first page', (tester) async {
    final all = [for (var i = 0; i < 50; i++) _row(i), _row(9999, hid: 'h2')];
    final server = _CappedPostgrest(all, cap: 20);
    // The feed itself holds only what one capped read returned.
    final feedRows = all.take(20).map(Transaction.fromMap).toList();
    await _openExport(tester, server, feedRows: feedRows);

    expect(find.textContaining(l.plural('transactions_count', 50)), findsOneWidget);
    expect(server.requests, 4, reason: 'three pages of 20, 20 and 10, then the empty page that ends it');
  });

  testWidgets('a failed page shows an error instead of a partial export', (tester) async {
    final server = _CappedPostgrest([for (var i = 0; i < 10; i++) _row(i)])..fail = true;
    await _openExport(tester, server, feedRows: [Transaction.fromMap(_row(0))]);

    expect(find.text(l.format('csv_export_title', {'label': l.get('csv_export_all_records')})), findsNothing);
    expect(find.text(l.get('set_export_failed')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
