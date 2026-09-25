/// Real-time transaction feed — animated list via Supabase stream with editing, category filtering & deletion.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../widgets/transaction_item_breakdown_card.dart';
import 'edit_transaction_sheet.dart';

class TransactionFeedScreen extends StatefulWidget {
  const TransactionFeedScreen({super.key});

  @override
  State<TransactionFeedScreen> createState() => _TransactionFeedScreenState();
}

class _TransactionFeedScreenState extends State<TransactionFeedScreen> {
  late Future<String> _householdId;
  String _selectedCategoryFilter = 'ALL';

  final List<Map<String, String>> _filterOptions = const [
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
              // Filter Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filterOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final opt = _filterOptions[i];
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

              // Transaction Feed
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('transactions')
                      .stream(primaryKey: ['id'])
                      .eq('household_id', hid)
                      .order('created_at', ascending: false)
                      .limit(100),
                  builder: (ctx, txSnap) {
                    if (!txSnap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)));
                    }
                    var transactions = txSnap.data!.map(Transaction.fromMap).toList();

                    // Apply category filter
                    if (_selectedCategoryFilter != 'ALL') {
                      transactions = transactions
                          .where((t) => t.categoryCode == _selectedCategoryFilter)
                          .toList();
                    }

                    if (transactions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 64, color: Color(0xFF30363D)),
                            const SizedBox(height: 16),
                            Text(
                              'No transactions found',
                              style: GoogleFonts.outfit(color: const Color(0xFF8B949E), fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Log an expense via chat, scan a receipt,\nor receive a bank SMS.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      color: const Color(0xFF00C896),
                      onRefresh: () async => setState(() {}),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
