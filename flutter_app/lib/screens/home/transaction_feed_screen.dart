/// Real-time transaction feed — animated list via Supabase stream.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main.dart';
import '../../models/models.dart';
import '../../widgets/transaction_item_breakdown_card.dart';

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

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: transactions.length,
                  separatorBuilder: (ctx, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final tx = transactions[i];
                    return _TransactionTile(tx: tx);
                  },
                ),
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

  @override
  Widget build(BuildContext context) {
    return TransactionItemBreakdownCard(
      merchant: tx.merchant ?? 'Unknown',
      amount: tx.amount,
      currency: tx.currency,
      categoryCode: tx.categoryCode,
      source: tx.source,
      items: tx.items,
      isReallocated: tx.isReallocated,
    );
  }
}
