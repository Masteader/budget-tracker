/// CSV Export Service.
/// Generates standard CSV reports for monthly transactions including Date, Merchant, Category, Total Amount, VAT, Spent By, and Line Items.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import '../l10n/app_localizations.dart';
import '../models/models.dart' show Transaction;
import '../models/transaction_attribution.dart' show kDeletedMemberRef, deletedCreatorRef, storedPayerRef;
import '../theme/app_themes.dart';
import '../widgets/app_snackbar.dart';
import 'salary_cycle_service.dart';

/// One household's rows for its current salary cycle, ready to export.
class CycleExport {
  final SaudiCycle cycle;
  final List<Map<String, dynamic>> rows;

  const CycleExport({required this.cycle, required this.rows});
}

class CsvExportService {
  CsvExportService._();

  /// Rows asked for per request. The server may cap a response below this
  /// (Supabase's default is 1000) and still answers 200 with partial rows.
  static const int exportPageSize = 1000;

  /// Stops a server that ignores `offset` from looping forever.
  static const int _maxExportPages = 1000;

  /// The rows the other cycle views count as spending: a settlement moves money
  /// between members and a wife's personal purchase is charged to her allowance.
  /// Decided here rather than in the query: `nafaqah_class=neq.wife_personal`
  /// would also drop every row whose class is NULL, i.e. almost all of them.
  static bool countsAsCycleSpend(Map<String, dynamic> tx) =>
      tx['is_settlement'] != true && tx['nafaqah_class'] != 'wife_personal';

  /// Every row of [householdId] in [cycleKey] that the other cycle views count.
  ///
  /// Pages on a stable order (rows sharing a timestamp would otherwise repeat or
  /// vanish across pages) and stops on an empty page, advancing by what actually
  /// arrived: a server cap below [pageSize] makes every page look short.
  static Future<List<Map<String, dynamic>>> fetchCycleRows(
    SupabaseClient client, {
    required String householdId,
    required String cycleKey,
    int pageSize = exportPageSize,
  }) async {
    final rows = <Map<String, dynamic>>[];
    final seenIds = <Object>{};
    var offset = 0;
    for (var page = 0; page < _maxExportPages; page++) {
      final res = await client
          .from('transactions')
          .select()
          .eq('household_id', householdId)
          .eq('cycle_key', cycleKey)
          .order('timestamp', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      final batch = List<Map<String, dynamic>>.from(res);
      if (batch.isEmpty) return rows;
      offset += batch.length;
      for (final tx in batch) {
        // A row written while paging shifts later pages by one.
        final id = tx['id'];
        if (id != null && !seenIds.add(id)) continue;
        if (countsAsCycleSpend(tx)) rows.add(tx);
      }
    }
    throw StateError('Transaction export did not finish within $_maxExportPages pages');
  }

  /// The current cycle's rows for [householdId], using that household's own
  /// payday read from the server. There is no default and no device-wide cache
  /// here: a wrong payday would select a plausible but wrong cycle, so a failed
  /// read fails the export.
  static Future<CycleExport> loadCurrentCycle(
    SupabaseClient client, {
    required String householdId,
    DateTime? now,
  }) async {
    final household = await client.from('households').select('payday_day').eq('id', householdId).maybeSingle();
    if (household == null) throw StateError('Household not readable');
    final payday = SalaryCycleService.normalizePayday((household['payday_day'] as num?)?.toInt());
    final cycle = SalaryCycleService.currentCycle(now: now, paydayDay: payday);
    final rows = await fetchCycleRows(client, householdId: householdId, cycleKey: cycle.key);
    return CycleExport(cycle: cycle, rows: rows);
  }

  /// The column titles in [l]'s language.
  static List<String> headersFor(AppLocalizations l) => [
        l.get('csv_col_date'),
        l.get('csv_col_merchant'),
        l.get('csv_col_category'),
        l.get('csv_col_amount'),
        l.get('csv_col_vat'),
        l.get('csv_col_spent_by'),
        l.get('csv_col_source'),
        l.get('csv_col_items'),
      ];

  /// The row the export reads for [tx], as the feed holds it: the columns of the
  /// file, plus what [storedPayerRef] needs to tell who paid a row whose
  /// creator deleted their account.
  static Map<String, dynamic> exportRowOf(Transaction tx) => {
        'id': tx.id,
        'amount': tx.amount,
        'currency': tx.currency,
        'merchant': tx.merchant,
        'category_code': tx.categoryCode,
        'timestamp': tx.timestamp.toIso8601String(),
        'source': tx.source,
        'spent_by': tx.spentBy,
        if (tx.creatorRemoved) 'user_id': null,
        if (tx.beneficiaryType != null) 'beneficiary_type': tx.beneficiaryType,
        if (tx.beneficiaryId != null) 'beneficiary_id': tx.beneficiaryId,
        'notes': tx.notes,
      };

  /// [deletedMemberLabel] stands for a departed creator; a living member who
  /// paid such a row is named from [memberNames] (member id to display name),
  /// or [memberLabel] when the name is not known. A member id never reaches the
  /// file.
  static String generateTransactionsCsv(
    List<Map<String, dynamic>> transactions, {
    required List<String> headers,
    String deletedMemberLabel = kDeletedMemberRef,
    String memberLabel = 'member',
    Map<String, String> memberNames = const {},
  }) {
    final labels = _PayerLabels(deletedMemberLabel, memberLabel, memberNames);
    final buffer = StringBuffer();
    for (final row in _csvRows(transactions, headers, labels)) {
      buffer.writeln(row.join(','));
    }
    return buffer.toString();
  }

  /// The same cells as [generateTransactionsCsv] for showing on screen: each
  /// field is a left-to-right isolate, so columns stay in order however much
  /// Arabic or Urdu they hold. Without it the bidi algorithm reverses a run of
  /// right-to-left fields together with the commas between them. For display
  /// only; the marks must never reach the clipboard.
  static String previewTransactionsCsv(
    List<Map<String, dynamic>> transactions, {
    required List<String> headers,
    String deletedMemberLabel = kDeletedMemberRef,
    String memberLabel = 'member',
    Map<String, String> memberNames = const {},
  }) {
    final labels = _PayerLabels(deletedMemberLabel, memberLabel, memberNames);
    return _csvRows(transactions, headers, labels).map((row) => row.map((field) => '\u2066$field\u2069').join(',')).join('\n');
  }

  /// `spent_by` is relative to the row's creator. With no creator left, 'me' and
  /// 'partner' name nobody and must not read as whoever exports the file; a
  /// living member who paid (a member id in a manual row's note) stays named,
  /// as [Transaction.attributedSpentBy] does in the feed.
  static String _spentByCell(Map<String, dynamic> tx, _PayerLabels labels) {
    final spentBy = tx['spent_by']?.toString() ?? 'both';
    final creatorRemoved = tx.containsKey('user_id') && (tx['user_id']?.toString() ?? '').trim().isEmpty;
    if (!creatorRemoved || spentBy.toLowerCase() == 'both') return spentBy;
    final payer = deletedCreatorRef(storedPayerRef(tx));
    if (payer == kDeletedMemberRef) return labels.deletedMember;
    final name = labels.names[payer] ?? labels.names.entries.where((e) => e.key.toLowerCase() == payer).firstOrNull?.value;
    return (name == null || name.trim().isEmpty) ? labels.member : name.trim();
  }

  static List<List<String>> _csvRows(List<Map<String, dynamic>> transactions, List<String> headers, _PayerLabels labels) {
    final rows = <List<String>>[headers.map(_escapeCsv).toList()];
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    for (final tx in transactions) {
      final rawDate = tx['timestamp'] as String?;
      String dateStr = '';
      if (rawDate != null) {
        try {
          final dt = DateTime.parse(rawDate).toLocal();
          dateStr = dateFormat.format(dt);
        } catch (_) {
          dateStr = rawDate;
        }
      }

      final merchant = _escapeCsv(tx['merchant']?.toString() ?? 'Unknown');
      final category = _escapeCsv(tx['category_code']?.toString() ?? 'OPEX-MISC');
      final amount = ((tx['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);

      // VAT estimation (15% Saudi VAT if applicable)
      final total = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      final vatStr = (total > 0 ? (total * 0.15 / 1.15) : 0.0).toStringAsFixed(2);

      final spentBy = _escapeCsv(_spentByCell(tx, labels));
      final source = _escapeCsv(tx['source']?.toString() ?? 'manual');

      // Line items
      String itemsStr = '';
      final items = tx['items'];
      if (items is List && items.isNotEmpty) {
        itemsStr = items.map((it) {
          if (it is Map) {
            final name = it['name'] ?? '';
            final qty = it['quantity'] ?? 1;
            final price = it['price'] ?? 0;
            return '$qty x $name ($price SAR)';
          }
          return it.toString();
        }).join('; ');
      }
      final itemsEscaped = _escapeCsv(itemsStr);

      rows.add([dateStr, merchant, category, amount, vatStr, spentBy, source, itemsEscaped]);
    }

    return rows;
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Shows an export dialog with preview and copy options.
  /// [memberNames] (member id to display name) names a living member who paid a
  /// row whose creator deleted their account.
  static void showExportDialog(
    BuildContext context,
    List<Map<String, dynamic>> transactions, {
    String? monthLabel,
    Map<String, String> memberNames = const {},
  }) {
    final l = AppLocalizations.of(context);
    final headers = headersFor(l);
    final deletedMember = l.get('deleted_member');
    final member = l.get('member');
    final csvContent = generateTransactionsCsv(transactions,
        headers: headers, deletedMemberLabel: deletedMember, memberLabel: member, memberNames: memberNames);
    final csvPreview = previewTransactionsCsv(transactions,
        headers: headers, deletedMemberLabel: deletedMember, memberLabel: member, memberNames: memberNames);
    final count = transactions.length;
    final totalSum = transactions.fold<double>(
      0.0,
      (acc, tx) => acc + ((tx['amount'] as num?)?.toDouble() ?? 0.0),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: context.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.table_view_rounded, color: context.accentText, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.trArgs('csv_export_title', {'label': monthLabel ?? context.tr('csv_export_current')}),
                style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.trArgs('csv_export_summary', {
                'transactions': context.trPlural('transactions_count', count),
                'amount': context.sar(totalSum),
              }),
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.subtleCardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.borderColor),
              ),
              child: SingleChildScrollView(
                // Spreadsheet data: its columns read left to right in every language.
                child: Text(
                  csvPreview,
                  key: const ValueKey('csv_preview'),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: TextStyle(color: context.textPrimary, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('close'), style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryButtonBg,
              foregroundColor: context.primaryButtonFg,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(context.tr('csv_copy'), style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final copiedMessage = context.tr('csv_copied_msg');
              final copiedTitle = context.tr('csv_copied_title');
              await Clipboard.setData(ClipboardData(text: csvContent));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                AppSnackBar.showSuccess(
                  context,
                  copiedMessage,
                  title: copiedTitle,
                  icon: Icons.table_chart_outlined,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// How the "spent by" column names who paid a row whose creator is gone.
class _PayerLabels {
  final String deletedMember;
  final String member;
  final Map<String, String> names;

  const _PayerLabels(this.deletedMember, this.member, this.names);
}
