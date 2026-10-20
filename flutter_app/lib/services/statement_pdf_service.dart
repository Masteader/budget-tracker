import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api/base_api_client.dart';
import 'api_service.dart';

typedef StatementDownloader = Future<ApiBinaryResponse> Function(String householdId, {String? cycleKey});
typedef StatementDirectoryProvider = Future<Directory> Function();
typedef StatementFileSharer = Future<void> Function(String path, String fileName);

/// Downloads the monthly statement PDF with the user's JWT and hands the file
/// to the system share sheet, from which it can be opened in a PDF viewer,
/// saved to Files/Drive or sent (MOB-26).
///
/// The previous flow showed a bare backend URL to copy into a browser, which
/// carries no `Authorization` header and was rejected by the firewall (403).
///
/// The file is written to an app-private cache folder; earlier statements in
/// that folder are deleted first so financial documents do not pile up.
class StatementPdfService {
  StatementPdfService({
    StatementDownloader? download,
    StatementDirectoryProvider? directory,
    StatementFileSharer? share,
  })  : _download = download ?? ApiService.instance.downloadStatementPdf,
        _directory = directory ?? _defaultDirectory,
        _share = share ?? _shareWithSystemSheet;

  final StatementDownloader _download;
  final StatementDirectoryProvider _directory;
  final StatementFileSharer _share;

  static const String folderName = 'statements';

  static Future<Directory> _defaultDirectory() async {
    final tmp = await getTemporaryDirectory();
    return Directory(p.join(tmp.path, folderName));
  }

  static Future<void> _shareWithSystemSheet(String path, String fileName) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf', name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  }

  /// Returns a file name safe for the file system, always ending in `.pdf`.
  static String safeFileName(String? serverName, {String? cycleKey}) {
    var name = (serverName ?? '').replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '');
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.isEmpty || name == '.pdf') {
      final cycle = (cycleKey ?? 'current').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
      name = 'statement_${cycle.isEmpty ? 'current' : cycle}.pdf';
    }
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    return name;
  }

  /// Downloads, saves and shares the statement. Returns the saved file.
  ///
  /// Throws [ApiDownloadException] when the download fails, and the platform
  /// exception when the file cannot be written or shared.
  Future<File> downloadAndShare(String householdId, {String? cycleKey}) async {
    final res = await _download(householdId, cycleKey: cycleKey);
    final fileName = safeFileName(res.fileName, cycleKey: cycleKey);

    final dir = await _directory();
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // A file still held by a viewer is removed on a later download.
          }
        }
      }
    } else {
      await dir.create(recursive: true);
    }

    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(res.bytes, flush: true);
    await _share(file.path, fileName);
    return file;
  }
}
