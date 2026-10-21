// MOB-26: the statement PDF must be fetched with the user's JWT (the firewall
// rejects a bare URL) and handed to the OS as a file, not shown as a link.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/budget_api_client.dart';
import 'package:budget_tracker/services/statement_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4\n%fake statement\n%%EOF'));

void main() {
  group('BaseApiClient.getBinary', () {
    test('sends the bearer token and returns the raw bytes and file name', () async {
      http.Request? captured;
      final client = BaseApiClient(
        client: MockClient((request) async {
          captured = request;
          return http.Response.bytes(_pdfBytes, 200, headers: {
            'content-type': 'application/pdf',
            'content-disposition': 'attachment; filename="statement_2026-10_abcd1234.pdf"',
          });
        }),
        authTokenProvider: () => 'user-jwt',
      );

      final res = await client.getBinary('/reports/statement-pdf', queryParams: {'household_id': 'h1'}, accept: 'application/pdf');

      expect(captured!.headers['Authorization'], 'Bearer user-jwt');
      expect(captured!.headers['Accept'], 'application/pdf');
      expect(captured!.url.queryParameters['household_id'], 'h1');
      expect(res.bytes, _pdfBytes);
      expect(res.fileName, 'statement_2026-10_abcd1234.pdf');
    });

    test('refreshes an expired token once and replays the download', () async {
      final tokens = <String?>[];
      final client = BaseApiClient(
        client: MockClient((request) async {
          tokens.add(request.headers['Authorization']);
          if (tokens.length == 1) return http.Response('{"detail":"expired"}', 401);
          return http.Response.bytes(_pdfBytes, 200);
        }),
        authTokenProvider: () => 'old',
        sessionRefresher: () async => 'new',
      );

      final res = await client.getBinary('/reports/statement-pdf');

      expect(tokens, ['Bearer old', 'Bearer new']);
      expect(res.bytes, _pdfBytes);
    });

    test('throws with the status code instead of returning the error body as a file', () async {
      final client = BaseApiClient(
        client: MockClient((_) async => http.Response('{"detail":"Untrusted endpoint access"}', 403)),
        authTokenProvider: () => 'jwt',
        sessionRefresher: () async => null,
      );

      expect(
        () => client.getBinary('/reports/statement-pdf'),
        throwsA(isA<ApiDownloadException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('wraps network failures', () async {
      final client = BaseApiClient(
        client: MockClient((_) async => throw const SocketException('offline')),
        authTokenProvider: () => 'jwt',
      );

      expect(
        () => client.getBinary('/reports/statement-pdf'),
        throwsA(isA<ApiDownloadException>().having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });
  });

  group('BudgetApiClient.downloadStatementPdf', () {
    test('requests the household and cycle through the authenticated client', () async {
      Uri? url;
      final api = BudgetApiClient(
        baseClient: BaseApiClient(
          client: MockClient((request) async {
            url = request.url;
            return http.Response.bytes(_pdfBytes, 200);
          }),
          authTokenProvider: () => 'jwt',
        ),
      );

      final res = await api.downloadStatementPdf('h1', cycleKey: '2026-10');

      expect(url!.path, endsWith('/reports/statement-pdf'));
      expect(url!.queryParameters, {'household_id': 'h1', 'cycle_key': '2026-10'});
      expect(res.bytes, _pdfBytes);
    });

    test('rejects a 200 response that is not a PDF (e.g. an HTML proxy page)', () async {
      final api = BudgetApiClient(
        baseClient: BaseApiClient(
          client: MockClient((_) async => http.Response('<html>login</html>', 200)),
          authTokenProvider: () => 'jwt',
        ),
      );

      expect(() => api.downloadStatementPdf('h1'), throwsA(isA<ApiDownloadException>()));
    });
  });

  group('StatementPdfService', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('statement_pdf_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('saves the downloaded PDF, removes older statements and shares the file', () async {
      final dir = Directory('${tmp.path}/statements');
      await dir.create();
      final stale = File('${dir.path}/statement_2026-09_old.pdf');
      await stale.writeAsString('old');

      String? sharedPath;
      String? sharedName;
      final service = StatementPdfService(
        download: (hid, {cycleKey}) async => ApiBinaryResponse(
          bytes: _pdfBytes,
          contentDisposition: 'attachment; filename="statement_current_h1.pdf"',
        ),
        directory: () async => dir,
        share: (path, name) async {
          sharedPath = path;
          sharedName = name;
        },
      );

      final file = await service.downloadAndShare('h1');

      expect(await file.readAsBytes(), _pdfBytes);
      expect(sharedPath, file.path);
      expect(sharedName, 'statement_current_h1.pdf');
      expect(await stale.exists(), isFalse);
    });

    test('does not share anything when the download fails', () async {
      var shared = false;
      final service = StatementPdfService(
        download: (hid, {cycleKey}) async => throw const ApiDownloadException('Forbidden', statusCode: 403),
        directory: () async => tmp,
        share: (path, name) async => shared = true,
      );

      await expectLater(service.downloadAndShare('h1'), throwsA(isA<ApiDownloadException>()));
      expect(shared, isFalse);
    });

    test('sanitises the server file name', () {
      expect(StatementPdfService.safeFileName('../../etc/passwd'), 'etcpasswd.pdf');
      expect(StatementPdfService.safeFileName(null, cycleKey: '2026-10'), 'statement_2026-10.pdf');
      expect(StatementPdfService.safeFileName('statement.PDF'), 'statement.PDF');
    });
  });

  test('the transactions screen no longer exposes a bare statement URL', () {
    final src = File('lib/screens/home/transaction_feed_screen.dart').readAsStringSync();
    expect(src.contains('getStatementPdfUrl'), isFalse);
    expect(src.contains('StatementPdfService'), isTrue);
  });
}
