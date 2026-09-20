/// Real-time transaction feed — animated list via Supabase stream.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../main.dart';
import '../../models/models.dart';

class TransactionFeedScreen extends StatefulWidget {
  const TransactionFeedScreen({super.key});

  @override
  State<TransactionFeedScreen> createState() => _TransactionFeedScreenState();
}

class _TransactionFeedScreenState extends State<TransactionFeedScreen> {
  late Future<String> _householdId;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        centerTitle: false,
      ),
      body: FutureBuilder<String>(
        future: _householdId,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hid = snap.data!;
          return StreamBuilder<List<Map<String, dynamic>>>(
            // ── Supabase Realtime stream ─────────────────────────────────
            stream: supabase
                .from('transactions')
                .stream(primaryKey: ['id'])
                .eq('household_id', hid)
                .order('created_at', ascending: false)
                .limit(100),
            builder: (ctx, txSnap) {
              if (!txSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final transactions =
                  txSnap.data!.map(Transaction.fromMap).toList();

              if (transactions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 64, color: Color(0xFF30363D)),
                      const SizedBox(height: 16),
                      Text('No transactions yet',
                          style: GoogleFonts.outfit(
                              color: const Color(0xFF8B949E), fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                          'Transactions appear automatically\nwhen a bank SMS is received.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF8B949E), fontSize: 13)),
                    ],
                  ),
                );
              }

              return AnimatedList(
                initialItemCount: transactions.length,
                itemBuilder: (ctx, i, animation) {
                  final tx = transactions[i];
                  return SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0, -0.3), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOut)),
                    child: FadeTransition(
                      opacity: animation,
                      child: _TransactionTile(tx: tx),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Transaction Tile ─────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final Transaction tx;
  const _TransactionTile({required this.tx});

  IconData get _icon {
    final code = tx.categoryCode ?? '';
    if (code.contains('GROCERY')) return Icons.shopping_basket_outlined;
    if (code.contains('DINING')) return Icons.restaurant_outlined;
    if (code.contains('FUEL')) return Icons.local_gas_station_outlined;
    if (code.contains('UTILITIES')) return Icons.bolt_outlined;
    if (code.contains('ENTERTAINMENT')) return Icons.movie_outlined;
    if (code.contains('HEALTH')) return Icons.local_pharmacy_outlined;
    if (code.contains('EDUCATION')) return Icons.school_outlined;
    if (code.contains('SHOPPING')) return Icons.shopping_bag_outlined;
    return Icons.payments_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tx.isReallocated
              ? Colors.orange.withOpacity(0.4)
              : const Color(0xFF30363D),
        ),
      ),
      child: Row(
        children: [
          // Category icon
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00C896).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: const Color(0xFF00C896), size: 22),
          ),
          const SizedBox(width: 14),

          // Merchant + category
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.merchant ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      tx.categoryCode?.replaceFirst(RegExp(r'^[A-Z]+-'), '') ?? '—',
                      style: const TextStyle(
                          color: Color(0xFF8B949E), fontSize: 12),
                    ),
                    if (tx.isReallocated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Reallocated',
                            style: TextStyle(
                                color: Colors.orange, fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Amount + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${tx.currency} ${tx.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.redAccent),
              ),
              const SizedBox(height: 3),
              Text(
                timeago.format(tx.createdAt),
                style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
