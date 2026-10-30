import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/installment_provider.dart';
import '../providers/recurring_bills_provider.dart';
import '../providers/transaction_provider.dart';

/// Unified reactive refresh pipeline across financial flows (manual entry,
/// AI chat entry, barcode scanner, receipt OCR, income recording, installment payments).
/// Executes non-blocking parallel refreshes across all active financial providers.
Future<void> refreshGlobalAppData(BuildContext context) async {
  if (!context.mounted) return;

  final futures = <Future>[];

  try {
    futures.add(context.read<AccountProvider>().refresh());
  } catch (_) {}

  try {
    futures.add(context.read<BudgetProvider>().refresh());
  } catch (_) {}

  try {
    futures.add(context.read<TransactionProvider>().fetchTransactions());
  } catch (_) {}

  try {
    futures.add(context.read<InstallmentProvider>().fetchPlans());
  } catch (_) {}

  try {
    futures.add(context.read<RecurringBillsProvider>().fetchBills());
  } catch (_) {}

  if (futures.isNotEmpty) {
    try {
      await Future.wait(futures);
    } catch (e) {
      debugPrint('[refreshGlobalAppData] Error during parallel refresh: $e');
    }
  }
}
