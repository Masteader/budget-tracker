/// CSV Export Service.
/// Generates standard CSV reports for monthly transactions including Date, Merchant, Category, Total Amount, VAT, Spent By, and Line Items.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CsvExportService {
  CsvExportService._();

  static String generateTransactionsCsv(List<Map<String, dynamic>> transactions) {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln('Date,Merchant,Category,Amount (SAR),VAT (SAR),Spent By,Source,Items Breakdown');

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

      final spentBy = _escapeCsv(tx['spent_by']?.toString() ?? 'both');
      final source = _escapeCsv(tx['source']?.toString() ?? 'sms');

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

      buffer.writeln('$dateStr,$merchant,$category,$amount,$vatStr,$spentBy,$source,$itemsEscaped');
    }

    return buffer.toString();
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Shows an export dialog with preview and copy options.
  static void showExportDialog(BuildContext context, List<Map<String, dynamic>> transactions, {String? monthLabel}) {
    final csvContent = generateTransactionsCsv(transactions);
    final count = transactions.length;
    final totalSum = transactions.fold<double>(
      0.0,
      (acc, tx) => acc + ((tx['amount'] as num?)?.toDouble() ?? 0.0),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.table_view_rounded, color: Color(0xFF00C896), size: 22),
            const SizedBox(width: 10),
            Text(
              'Export Report (${monthLabel ?? 'Current'})',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count transactions • Total SAR ${totalSum.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              height: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  csvContent,
                  style: const TextStyle(color: Color(0xFFC9D1D9), fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy CSV', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csvContent));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('CSV report copied to clipboard! Ready to paste in Excel / Google Sheets.'),
                    backgroundColor: Color(0xFF00C896),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
