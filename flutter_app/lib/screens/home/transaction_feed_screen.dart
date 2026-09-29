/// Real-time transaction feed — animated list via Supabase stream with editing, sorting, date/category filtering & deletion.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../services/csv_export_service.dart';
import '../../widgets/transaction_item_breakdown_card.dart';
import 'edit_transaction_sheet.dart';

class TransactionFeedScreen extends StatefulWidget {
  const TransactionFeedScreen({super.key});

  @override
  State<TransactionFeedScreen> createState() => _TransactionFeedScreenState();
}

class _TransactionFeedScreenState extends State<TransactionFeedScreen> {
  late Future<String> _householdId;

  // Filters & Sorting state
  String _selectedCategoryFilter = 'ALL';
  String _selectedSort = 'newest'; // 'newest' | 'oldest' | 'highest' | 'lowest'
  String _selectedDatePeriod = 'ALL'; // 'ALL' | 'TODAY' | 'THIS_WEEK' | 'THIS_MONTH' | 'CUSTOM'
  DateTimeRange? _customDateRange;
  String _selectedSpentByFilter = 'ALL'; // 'ALL' | 'me' | 'partner' | 'both'

  final List<Map<String, String>> _categoryOptions = const [
    {'code': 'ALL', 'label': 'All'},
    {'code': 'OPEX-DINING', 'label': '☕ Dining'},
    {'code': 'OPEX-GROCERY', 'label': '🛒 Groceries'},
    {'code': 'OPEX-FUEL', 'label': '⛽ Fuel'},
    {'code': 'OPEX-SHOPPING', 'label': '🛍️ Shopping'},
    {'code': 'OPEX-UTILITIES', 'label': '⚡ Bills'},
    {'code': 'OPEX-HEALTH', 'label': '💊 Health'},
    {'code': 'OPEX-MISC', 'label': '📦 Other'},
  ];

  @override
  void initState() {
    super.initState();
    _householdId = _fetchHouseholdId();
  }

  Future<String> _fetchHouseholdId() async {
    final uid = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('users')
        .select('household_id')
        .eq('id', uid)
        .single();
    return data['household_id'] as String;
  }

  String get _sortLabel {
    switch (_selectedSort) {
      case 'oldest':
        return 'Oldest First';
      case 'highest':
        return 'Highest (SAR)';
      case 'lowest':
        return 'Lowest (SAR)';
      case 'newest':
      default:
        return 'Newest First';
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
      backgroundColor: const Color(0xFF161B22),
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
                          color: const Color(0xFF30363D),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sort & Filter',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _resetFilters();
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                          child: const Text('Reset All', style: TextStyle(color: Color(0xFF00C896), fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── SORT ORDER ──
                    Text(
                      'SORT BY',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSortOption(
                          key: 'newest',
                          title: 'Newest First',
                          subtitle: 'Date descending',
                          icon: Icons.schedule,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'oldest',
                          title: 'Oldest First',
                          subtitle: 'Date ascending',
                          icon: Icons.history,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'highest',
                          title: 'Highest Amount',
                          subtitle: 'High to Low (SAR)',
                          icon: Icons.trending_up,
                          current: _selectedSort,
                          onSelect: (val) {
                            setModalState(() => _selectedSort = val);
                            setState(() => _selectedSort = val);
                          },
                        ),
                        _buildSortOption(
                          key: 'lowest',
                          title: 'Lowest Amount',
                          subtitle: 'Low to High (SAR)',
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
                      'DATE PERIOD',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All Time',
                          selected: _selectedDatePeriod == 'ALL',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'ALL');
                            setState(() => _selectedDatePeriod = 'ALL');
                          },
                        ),
                        _buildFilterChip(
                          label: 'Today',
                          selected: _selectedDatePeriod == 'TODAY',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'TODAY');
                            setState(() => _selectedDatePeriod = 'TODAY');
                          },
                        ),
                        _buildFilterChip(
                          label: 'This Week',
                          selected: _selectedDatePeriod == 'THIS_WEEK',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'THIS_WEEK');
                            setState(() => _selectedDatePeriod = 'THIS_WEEK');
                          },
                        ),
                        _buildFilterChip(
                          label: 'This Month',
                          selected: _selectedDatePeriod == 'THIS_MONTH',
                          onSelected: (_) {
                            setModalState(() => _selectedDatePeriod = 'THIS_MONTH');
                            setState(() => _selectedDatePeriod = 'THIS_MONTH');
                          },
                        ),
                        _buildFilterChip(
                          label: _customDateRange != null
                              ? '${DateFormat('d MMM').format(_customDateRange!.start)} - ${DateFormat('d MMM').format(_customDateRange!.end)}'
                              : 'Custom Range...',
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
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Color(0xFF00C896),
                                      onPrimary: Colors.black,
                                      surface: Color(0xFF161B22),
                                      onSurface: Colors.white,
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
                      'WHO SPENT THIS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B949E),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All',
                          selected: _selectedSpentByFilter == 'ALL',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'ALL');
                            setState(() => _selectedSpentByFilter = 'ALL');
                          },
                        ),
                        _buildFilterChip(
                          label: '👤 Me',
                          selected: _selectedSpentByFilter == 'me',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'me');
                            setState(() => _selectedSpentByFilter = 'me');
                          },
                        ),
                        _buildFilterChip(
                          label: '💜 Partner',
                          selected: _selectedSpentByFilter == 'partner',
                          onSelected: (_) {
                            setModalState(() => _selectedSpentByFilter = 'partner');
                            setState(() => _selectedSpentByFilter = 'partner');
                          },
                        ),
                        _buildFilterChip(
                          label: '👥 Both (Shared)',
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
                          'Apply Filters',
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
          color: isSelected ? const Color(0xFF00C896).withValues(alpha: 0.12) : const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
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
                  color: isSelected ? const Color(0xFF00C896) : const Color(0xFF8B949E),
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
                color: isSelected ? Colors.white : const Color(0xFFC9D1D9),
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E)),
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
          ? Icon(icon, size: 14, color: selected ? Colors.black : const Color(0xFF8B949E))
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.black : const Color(0xFFC9D1D9),
        ),
      ),
      selected: selected,
      selectedColor: const Color(0xFF00C896),
      backgroundColor: const Color(0xFF0D1117),
      side: BorderSide(
        color: selected ? const Color(0xFF00C896) : const Color(0xFF30363D),
      ),
      onSelected: onSelected,
    );
  }

  Future<void> _deleteTransaction(BuildContext context, Transaction tx) async {
    try {
      await supabase.from('transactions').delete().eq('id', tx.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted SAR ${tx.amount.toStringAsFixed(2)} at ${tx.merchant ?? "merchant"}'),
            backgroundColor: const Color(0xFF21262D),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: const Color(0xFF00C896),
              onPressed: () async {
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
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Text('Transactions', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                tooltip: 'Filter & Sort',
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
      body: FutureBuilder<String>(
        future: _householdId,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)));
          }
          final hid = snap.data!;
          return Column(
            children: [
              // Horizontal Category Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categoryOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final opt = _categoryOptions[i];
                    final isSelected = _selectedCategoryFilter == opt['code'];
                    return ChoiceChip(
                      label: Text(
                        opt['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.black : const Color(0xFFC9D1D9),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF00C896),
                      backgroundColor: const Color(0xFF161B22),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D),
                      ),
                      onSelected: (val) {
                        setState(() => _selectedCategoryFilter = opt['code']!);
                      },
                    );
                  },
                ),
              ),

              // Transaction Stream & Content
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('transactions')
                      .stream(primaryKey: ['id'])
                      .eq('household_id', hid)
                      .order('timestamp', ascending: false)
                      .limit(200),
                  builder: (ctx, txSnap) {
                    if (!txSnap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)));
                    }
                    final rawList = txSnap.data!.map(Transaction.fromMap).toList();
                    final transactions = _filterAndSort(rawList);

                    // Calculate total spent for visible items
                    final visibleTotal = transactions.fold<double>(0.0, (sum, t) => sum + t.amount);

                    return Column(
                      children: [
                        // Quick Sort / Summary sub-bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Text(
                                '${transactions.length} ${transactions.length == 1 ? "expense" : "expenses"} • SAR ${visibleTotal.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF8B949E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _showSortFilterModal,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _selectedSort != 'newest' || _selectedDatePeriod != 'ALL' || _selectedSpentByFilter != 'ALL'
                                          ? const Color(0xFF00C896)
                                          : const Color(0xFF30363D),
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
                                            : const Color(0xFF8B949E),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _sortLabel,
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _selectedSort != 'newest'
                                              ? const Color(0xFF00C896)
                                              : const Color(0xFFC9D1D9),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  if (txSnap.data != null && txSnap.data!.isNotEmpty) {
                                    CsvExportService.showExportDialog(context, txSnap.data!, monthLabel: 'All Records');
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF30363D)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF58A6FF)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Export CSV',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF58A6FF),
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
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.search_off_rounded, size: 56, color: Color(0xFF30363D)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No matching transactions',
                                        style: GoogleFonts.outfit(color: const Color(0xFF8B949E), fontSize: 16),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton(
                                        onPressed: _resetFilters,
                                        child: const Text('Reset filters', style: TextStyle(color: Color(0xFF00C896))),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  color: const Color(0xFF00C896),
                                  onRefresh: () async => setState(() {}),
                                  child: ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.delete_outline, color: Colors.white, size: 24),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                        confirmDismiss: (dir) async {
                                          return await showDialog<bool>(
                                            context: context,
                                            builder: (dCtx) => AlertDialog(
                                              backgroundColor: const Color(0xFF161B22),
                                              title: const Text('Delete Transaction', style: TextStyle(color: Colors.white)),
                                              content: Text(
                                                'Delete SAR ${tx.amount.toStringAsFixed(2)} at ${tx.merchant ?? "Unknown"}?\nYour budget will be updated.',
                                                style: const TextStyle(color: Color(0xFF8B949E)),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dCtx, false),
                                                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.redAccent,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () => Navigator.pop(dCtx, true),
                                                  child: const Text('Delete'),
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
                                          onEdit: () => EditTransactionSheet.show(context, tx),
                                          onDelete: () => _deleteTransaction(context, tx),
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
          );
        },
      ),
    );
  }
}
