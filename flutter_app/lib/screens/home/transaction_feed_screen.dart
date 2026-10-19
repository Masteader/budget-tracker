/// Real-time transaction feed — animated list via Supabase stream with editing, sorting, date/category filtering & deletion.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../providers/budget_provider.dart';
import '../../providers/installment_provider.dart';
import '../../providers/recurring_bills_provider.dart';
import '../../providers/transaction_provider.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/csv_export_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/transaction_item_breakdown_card.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import 'edit_transaction_sheet.dart';

class TransactionFeedScreen extends StatefulWidget {
  const TransactionFeedScreen({super.key});

  @override
  State<TransactionFeedScreen> createState() => _TransactionFeedScreenState();
}

class _TransactionFeedScreenState extends State<TransactionFeedScreen> {
  // Filters & Sorting state
  String _selectedCategoryFilter = 'ALL';
  String _selectedSort = 'newest'; // 'newest' | 'oldest' | 'highest' | 'lowest'
  String _selectedDatePeriod = 'ALL'; // 'ALL' | 'TODAY' | 'THIS_WEEK' | 'THIS_MONTH' | 'CUSTOM'
  DateTimeRange? _customDateRange;
  String _selectedSpentByFilter = 'ALL'; // 'ALL' | 'me' | 'partner' | 'both'

  static const List<Map<String, String>> _categoryRawOptions = [
    {'code': 'ALL', 'emoji': ''},
    {'code': 'OPEX-GROCERY', 'emoji': '🛒 '},
    {'code': 'OPEX-DINING', 'emoji': '☕ '},
    {'code': 'OPEX-SHOPPING', 'emoji': '🛍️ '},
    {'code': 'OPEX-UTILITIES', 'emoji': '⚡ '},
    {'code': 'OPEX-FUEL', 'emoji': '⛽ '},
    {'code': 'OPEX-ENTERTAINMENT', 'emoji': '🎮 '},
    {'code': 'OPEX-HEALTH', 'emoji': '💊 '},
    {'code': 'CAPEX-EDUCATION', 'emoji': '🎓 '},
    {'code': 'OPEX-GOV', 'emoji': '🏛️ '},
    {'code': 'OPEX-MISC', 'emoji': '📦 '},
  ];

  List<Map<String, String>> _getCategoryOptions(BuildContext context) {
    return _categoryRawOptions.map((opt) {
      final code = opt['code']!;
      final emoji = opt['emoji']!;
      if (code == 'ALL') {
        return {'code': code, 'label': context.tr('all')};
      }
      return {'code': code, 'label': '$emoji${context.trCat(code)}'};
    }).toList();
  }

  String _getSortLabel(BuildContext context) {
    switch (_selectedSort) {
      case 'oldest':
        return context.tr('sort_oldest');
      case 'highest':
        return context.tr('sort_highest');
      case 'lowest':
        return context.tr('sort_lowest');
      case 'newest':
      default:
        return context.tr('sort_newest');
    }
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedSort != 'newest') count++;
    if (_selectedCategoryFilter != 'ALL') count++;
    if (_selectedDatePeriod != 'ALL') count++;
    if (_selectedSpentByFilter != 'ALL') count++;
    return count;
  }

  List<Transaction> _filterAndSort(List<Transaction> list) {
    var result = List<Transaction>.from(list);

    // 1. Category Filter
    if (_selectedCategoryFilter != 'ALL') {
      result = result.where((t) => t.categoryCode == _selectedCategoryFilter).toList();
    }

    // 2. Spent By Filter
    if (_selectedSpentByFilter != 'ALL') {
      result = result
          .where((t) => t.spentBy.toLowerCase() == _selectedSpentByFilter.toLowerCase())
          .toList();
    }

    // 3. Date Range Filter
    final now = DateTime.now();
    if (_selectedDatePeriod == 'TODAY') {
      result = result.where((t) {
        final d = t.timestamp.toLocal();
        return d.year == now.year && d.month == now.month && d.day == now.day;
      }).toList();
    } else if (_selectedDatePeriod == 'THIS_WEEK') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final cleanStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      result = result.where((t) => t.timestamp.isAfter(cleanStart)).toList();
    } else if (_selectedDatePeriod == 'THIS_MONTH') {
      result = result.where((t) {
        final d = t.timestamp.toLocal();
        return d.year == now.year && d.month == now.month;
      }).toList();
    } else if (_selectedDatePeriod == 'CUSTOM' && _customDateRange != null) {
      final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
      final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
      result = result.where((t) => t.timestamp.isAfter(start) && t.timestamp.isBefore(end)).toList();
    }

    // 4. Sort
    switch (_selectedSort) {
      case 'oldest':
        result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case 'highest':
        result.sort((a, b) => b.amount.compareTo(a.amount));
        break;
      case 'lowest':
        result.sort((a, b) => a.amount.compareTo(b.amount));
        break;
      case 'newest':
      default:
        result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
    }

    return result;
  }

  void _resetFilters() {
    setState(() {
      _selectedCategoryFilter = 'ALL';
      _selectedSort = 'newest';
      _selectedDatePeriod = 'ALL';
      _customDateRange = null;
      _selectedSpentByFilter = 'ALL';
    });
  }

  void _showSortFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.borderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('filter_and_sort'),
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _resetFilters();
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                          child: Text(context.tr('reset_all'), style: const TextStyle(color: Color(0xFF00C896), fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── SORT ORDER ──
                    Text(
                      context.tr('sort_by'),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSortOption(
                          key: 'newest',
                          title: context.tr('sort_newest'),
                          subtitle: context.tr('date_descending'),
                          icon: Icons.schedule,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'oldest',
                          title: context.tr('sort_oldest'),
                          subtitle: context.tr('date_ascending'),
                          icon: Icons.history,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'highest',
                          title: context.tr('sort_highest'),
                          subtitle: context.tr('high_to_low'),
                          icon: Icons.trending_up,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'lowest',
                          title: context.tr('sort_lowest'),
                          subtitle: context.tr('low_to_high'),
                          icon: Icons.trending_down,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── DATE PERIOD ──
                    Text(
                      context.tr('date_period'),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: context.tr('all_time'),
                          selected: _selectedDatePeriod == 'ALL',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'ALL');
                            setState(() => _selectedDatePeriod = 'ALL');
                          },
                        ),
                        _buildFilterChip(
                          label: context.tr('today'),
                          selected: _selectedDatePeriod == 'TODAY',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'TODAY');
                            setState(() => _selectedDatePeriod = 'TODAY');
                          },
                        ),
                        _buildFilterChip(
                          label: context.tr('this_week'),
                          selected: _selectedDatePeriod == 'THIS_WEEK',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'THIS_WEEK');
                            setState(() => _selectedDatePeriod = 'THIS_WEEK');
                          },
                        ),
                        _buildFilterChip(
                          label: context.tr('this_month'),
                          selected: _selectedDatePeriod == 'THIS_MONTH',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'THIS_MONTH');
                            setState(() => _selectedDatePeriod = 'THIS_MONTH');
                          },
                        ),
                        _buildFilterChip(
                          label: _customDateRange != null
                              ? '${DateFormat('d MMM').format(_customDateRange!.start)} - ${DateFormat('d MMM').format(_customDateRange!.end)}'
                              : context.tr('custom_range'),
                          selected: _selectedDatePeriod == 'CUSTOM',
                          icon: Icons.calendar_today,
                          onSelected: (_) async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                              initialDateRange: _customDateRange ??
                                  DateTimeRange(
                                    start: DateTime.now().subtract(const Duration(days: 7)),
                                    end: DateTime.now(),
                                  ),
                              builder: (pickerCtx, child) {
                                return Theme(
                                  data: (context.isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
                                    colorScheme: ColorScheme.fromSeed(
                                      seedColor: const Color(0xFF00C896),
                                      brightness: context.isDark ? Brightness.dark : Brightness.light,
                                      primary: const Color(0xFF00C896),
                                      onPrimary: Colors.black,
                                      surface: context.cardBg,
                                      onSurface: context.textPrimary,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setModalState(() {
                                _customDateRange = picked;
                                _selectedDatePeriod = 'CUSTOM';
                              });
                              setState(() {
                                _customDateRange = picked;
                                _selectedDatePeriod = 'CUSTOM';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── WHO SPENT THIS ──
                    Text(
                      context.tr('who_spent_this'),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: context.tr('all'),
                          selected: _selectedSpentByFilter == 'ALL',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'ALL');
                            setState(() => _selectedSpentByFilter = 'ALL');
                          },
                        ),
                        _buildFilterChip(
                          label: '👤 ${context.tr("me")}',
                          selected: _selectedSpentByFilter == 'me',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'me');
                            setState(() => _selectedSpentByFilter = 'me');
                          },
                        ),
                        _buildFilterChip(
                          label: '💜 ${context.tr("partner")}',
                          selected: _selectedSpentByFilter == 'partner',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'partner');
                            setState(() => _selectedSpentByFilter = 'partner');
                          },
                        ),
                        _buildFilterChip(
                          label: '👥 ${context.tr("both_shared")}',
                          selected: _selectedSpentByFilter == 'both',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'both');
                            setState(() => _selectedSpentByFilter = 'both');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          context.tr('apply_filters'),
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortOption({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    final isSelected = current == key;
    return GestureDetector(
      onTap: () => onSelect(key),
      child: Container(
        width: (MediaQuery.of(context).size.width - 48) / 2,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.12) : context.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C896) : context.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? const Color(0xFF00C896) : context.textSecondary,
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF00C896)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF00C896) : context.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    IconData? icon,
  }) {
    return ChoiceChip(
      avatar: icon != null
          ? Icon(icon, size: 14, color: selected ? Colors.black : context.textSecondary)
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.black : context.textPrimary,
        ),
      ),
      selected: selected,
      selectedColor: const Color(0xFF00C896),
      backgroundColor: context.cardBg,
      side: BorderSide(
        color: selected ? const Color(0xFF00C896) : context.borderColor,
      ),
      onSelected: onSelected,
    );
  }

  Future<void> _deleteTransaction(BuildContext context, Transaction tx, {bool requireConfirm = false}) async {
    final txProvider = context.read<TransactionProvider>();
    final budgetProvider = context.read<BudgetProvider>();

    if (requireConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: context.cardBg,
          title: Text(context.tr('delete_transaction'), style: TextStyle(color: context.textPrimary)),
          content: Text(
            '${context.tr('delete_confirm_prefix')} ${context.tr('sar')} ${tx.amount.toStringAsFixed(2)} ${context.tr('at_merchant')} ${context.trMerchant(tx.merchant)}?\n${context.tr('budget_will_be_updated')}',
            style: TextStyle(color: context.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(context.tr('delete')),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    HapticFeedback.mediumImpact();
    final success = await txProvider.deleteTransaction(tx.id);
    if (!success) {
      if (context.mounted) {
        AppSnackBar.showError(
          context,
          context.tr('delete_failed'),
          title: context.tr('delete_transaction'),
        );
      }
      return;
    }

    // Instantly refresh budget calculations across the app
    budgetProvider.refresh();
    if (context.mounted) {
      context.read<RecurringBillsProvider>().fetchBills();
      try {
        context.read<InstallmentProvider>().fetchPlans(silent: true);
      } catch (_) {}
    }

    if (context.mounted) {
      AppSnackBar.showDelete(
        context,
        '${context.tr('sar')} ${tx.amount.toStringAsFixed(2)} ${context.tr('at_merchant')} ${context.trMerchant(tx.merchant)}',
        title: context.tr('transaction_removed'),
        onUndo: () async {
          await supabase.from('transactions').insert({
            'household_id': tx.householdId,
            'amount': tx.amount,
            'currency': tx.currency,
            'merchant': tx.merchant,
            'category_code': tx.categoryCode,
            'timestamp': tx.timestamp.toIso8601String(),
            'source': tx.source,
            'items': tx.items,
            'receipt_url': tx.receiptUrl,
            'spent_by': tx.spentBy,
          });
          await txProvider.fetchTransactions();
          budgetProvider.refresh();
          if (context.mounted) {
            context.read<RecurringBillsProvider>().fetchBills();
          }
          if (context.mounted) {
            AppSnackBar.showSuccess(
              context,
              '${context.tr('sar')} ${tx.amount.toStringAsFixed(2)} ${context.tr('at_merchant')} ${context.trMerchant(tx.merchant)}',
              title: context.tr('transaction_restored'),
            );
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(context.tr('nav_transactions'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary)),
        backgroundColor: context.scaffoldBg,
        elevation: 0,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.tune_rounded, color: context.textPrimary),
                tooltip: context.tr('filter_and_sort'),
                onPressed: _showSortFilterModal,
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C896),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_activeFilterCount',
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
              // Horizontal Category Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _getCategoryOptions(context).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final opt = _getCategoryOptions(context)[i];
                    final isSelected = _selectedCategoryFilter == opt['code'];
                    return ChoiceChip(
                      label: Text(
                        opt['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.black : context.textPrimary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF00C896),
                      backgroundColor: context.cardBg,
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF00C896) : context.borderColor,
                      ),
                      onSelected: (val) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategoryFilter = opt['code']!);
                      },
                    );
                  },
                ),
              ),

              // Centralized Provider State Feed
              Expanded(
                child: Consumer<TransactionProvider>(
                  builder: (ctx, txProvider, _) {
                    if (txProvider.isLoading && txProvider.transactions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: AppShimmer.listItems(count: 6),
                      );
                    }

                    final transactions = _filterAndSort(txProvider.transactions);
                    final visibleTotal = transactions.fold<double>(0.0, (sum, t) => sum + t.amount);

                    return Column(
                      children: [
                        // Quick Sort / Summary sub-bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${transactions.length} ${transactions.length == 1 ? context.tr("expenses_count_singular") : context.tr("expenses_count_plural")} • ${context.tr("sar")} ${visibleTotal.toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(
                                    color: context.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _showSortFilterModal,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.chipBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedSort != 'newest' || _selectedDatePeriod != 'ALL' || _selectedSpentByFilter != 'ALL'
                                          ? const Color(0xFF00C896)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.swap_vert_rounded,
                                        size: 14,
                                        color: _selectedSort != 'newest'
                                            ? const Color(0xFF00C896)
                                            : context.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getSortLabel(context),
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _selectedSort != 'newest'
                                              ? const Color(0xFF00C896)
                                              : context.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  if (txProvider.transactions.isNotEmpty) {
                                    final exportList = txProvider.transactions.map((t) => {
                                      'id': t.id,
                                      'amount': t.amount,
                                      'currency': t.currency,
                                      'merchant': t.merchant,
                                      'category_code': t.categoryCode,
                                      'timestamp': t.timestamp.toIso8601String(),
                                      'source': t.source,
                                      'spent_by': t.spentBy,
                                      'raw_sms': t.rawSms,
                                    }).toList();
                                    CsvExportService.showExportDialog(context, exportList, monthLabel: 'All Records');
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.chipBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: context.borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.file_download_outlined, size: 14, color: context.isDark ? const Color(0xFF58A6FF) : const Color(0xFF0284C7)),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.tr('export_csv'),
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: context.isDark ? const Color(0xFF58A6FF) : const Color(0xFF0284C7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () async {
                                  final user = supabase.auth.currentUser;
                                  if (user == null) return;
                                  final prof = await supabase.from('users').select('household_id').eq('id', user.id).single();
                                  final hid = prof['household_id'] as String?;
                                  if (hid != null && context.mounted) {
                                    final pdfUrl = ApiService.instance.getStatementPdfUrl(hid);
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: context.cardBg,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        title: Row(
                                          children: [
                                            const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE24A4A), size: 22),
                                            const SizedBox(width: 10),
                                            Text(
                                              context.tr('monthly_statement_pdf'),
                                              style: GoogleFonts.outfit(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.tr('pdf_desc'),
                                              style: TextStyle(color: context.textSecondary, fontSize: 13),
                                            ),
                                            const SizedBox(height: 14),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: context.subtleCardBg,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: context.borderColor),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.link_rounded, color: Color(0xFF00C896), size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      pdfUrl,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: context.textPrimary, fontSize: 11, fontFamily: 'monospace'),
                                                    ),
                                                  ),
                                                ],
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
                                              backgroundColor: const Color(0xFF00C896),
                                              foregroundColor: Colors.black,
                                            ),
                                            icon: const Icon(Icons.copy_rounded, size: 16),
                                            label: Text(context.tr('copy_pdf_link'), style: const TextStyle(fontWeight: FontWeight.bold)),
                                            onPressed: () async {
                                              await Clipboard.setData(ClipboardData(text: pdfUrl));
                                              if (ctx.mounted) {
                                                Navigator.pop(ctx);
                                                AppSnackBar.showSuccess(
                                                  context,
                                                  context.tr('pdf_copied_desc'),
                                                  title: context.tr('link_copied'),
                                                  icon: Icons.picture_as_pdf_rounded,
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: context.chipBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: context.borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.picture_as_pdf_outlined, size: 14, color: context.dangerColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        context.tr('export_pdf'),
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: context.dangerColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // List view
                        Expanded(
                          child: transactions.isEmpty
                              ? SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: AppEmptyState(
                                      icon: Icons.search_off_rounded,
                                      title: context.tr('no_matching_transactions'),
                                      message: 'Try adjusting your filters, date range, or category selection to find what you need.',
                                      actionLabel: context.tr('reset_filters'),
                                      onAction: () {
                                        HapticFeedback.lightImpact();
                                        _resetFilters();
                                      },
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  color: const Color(0xFF00C896),
                                  onRefresh: () async {
                                    await Future.wait([
                                      context.read<TransactionProvider>().fetchTransactions(),
                                      context.read<BudgetProvider>().refresh(),
                                      context.read<RecurringBillsProvider>().fetchBills(),
                                    ]);
                                  },
                                  child: ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
                                    itemCount: transactions.length,
                                    separatorBuilder: (ctx, _) => const SizedBox(height: 6),
                                    itemBuilder: (ctx, i) {
                                      final tx = transactions[i];
                                      return Dismissible(
                                        key: Key(tx.id),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.only(right: 20),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                                              const SizedBox(width: 8),
                                              Text(context.tr('delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                        confirmDismiss: (dir) async {
                                          return await showDialog<bool>(
                                            context: context,
                                            builder: (dCtx) => AlertDialog(
                                              backgroundColor: context.cardBg,
                                              title: Text(context.tr('delete_transaction'), style: TextStyle(color: context.textPrimary)),
                                              content: Text(
                                                '${context.tr('delete_confirm_prefix')} ${context.tr('sar')} ${tx.amount.toStringAsFixed(2)} ${context.tr('at_merchant')} ${context.trMerchant(tx.merchant)}?\n${context.tr('budget_will_be_updated')}',
                                                style: TextStyle(color: context.textSecondary),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx, false),
                                                  child: Text(context.tr('cancel'), style: TextStyle(color: context.textSecondary)),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.redAccent,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () => Navigator.pop(dCtx, true),
                                                  child: Text(context.tr('delete')),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        onDismissed: (_) => _deleteTransaction(context, tx),
                                        child: TransactionItemBreakdownCard(
                                          merchant: tx.merchant ?? 'Unknown',
                                          amount: tx.amount,
                                          currency: tx.currency,
                                          categoryCode: tx.categoryCode,
                                          source: tx.source,
                                          spentBy: tx.spentBy,
                                          items: tx.items,
                                          isReallocated: tx.isReallocated,
                                          receiptUrl: tx.receiptUrl,
                                          qrCodeRaw: tx.qrCodeRaw,
                                          isInstallment: tx.isInstallment,
                                          installmentBadgeText: tx.installmentBadgeText,
                                          installmentProvider: tx.installmentProvider,
                                          onEdit: () async {
                                            final res = await EditTransactionSheet.show(context, tx);
                                            if (res == 'deleted') {
                                              if (context.mounted) {
                                                context.read<TransactionProvider>().deleteTransaction(tx.id);
                                                context.read<BudgetProvider>().refresh();
                                                context.read<RecurringBillsProvider>().fetchBills();
                                                try {
                                                  context.read<InstallmentProvider>().fetchPlans(silent: true);
                                                } catch (_) {}
                                              }
                                            } else if (res == 'updated') {
                                              if (context.mounted) {
                                                context.read<TransactionProvider>().fetchTransactions();
                                                context.read<BudgetProvider>().refresh();
                                                context.read<RecurringBillsProvider>().fetchBills();
                                                try {
                                                  context.read<InstallmentProvider>().fetchPlans(silent: true);
                                                } catch (_) {}
                                              }
                                            }
                                          },
                                          onDelete: () => _deleteTransaction(context, tx, requireConfirm: true),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }
}
