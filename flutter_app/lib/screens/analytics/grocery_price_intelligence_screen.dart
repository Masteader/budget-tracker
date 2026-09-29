import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';

class GroceryPriceIntelligenceScreen extends StatefulWidget {
  final String householdId;

  const GroceryPriceIntelligenceScreen({super.key, required this.householdId});

  @override
  State<GroceryPriceIntelligenceScreen> createState() => _GroceryPriceIntelligenceScreenState();
}

class _GroceryPriceIntelligenceScreenState extends State<GroceryPriceIntelligenceScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String _selectedChip = 'All';

  final List<String> _quickFilters = ['All', 'Milk', 'Chicken', 'Bread', 'Eggs', 'Coffee', 'Rice'];

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrices({String? query}) async {
    setState(() => _isLoading = true);
    final res = await ApiService.instance.getGroceryPriceHistory(
      widget.householdId,
      itemFilter: query?.trim(),
    );
    if (mounted) {
      setState(() {
        _items = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Color(0xFF00C896), size: 22),
            const SizedBox(width: 8),
            Text(
              'Grocery Price Intelligence',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 17),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => _loadPrices(query: v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search items (e.g. Milk, Chicken, Bread, Danube)...',
                hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8B949E), size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF8B949E), size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadPrices();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF161B22),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00C896)),
                ),
              ),
            ),
          ),

          // Quick Filter Chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final f = _quickFilters[i];
                final isSelected = _selectedChip == f;
                return ChoiceChip(
                  label: Text(f, style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : const Color(0xFFC9D1D9))),
                  selected: isSelected,
                  selectedColor: const Color(0xFF00C896),
                  backgroundColor: const Color(0xFF161B22),
                  side: BorderSide(color: isSelected ? const Color(0xFF00C896) : const Color(0xFF30363D)),
                  onSelected: (val) {
                    setState(() => _selectedChip = f);
                    _searchCtrl.text = f == 'All' ? '' : f;
                    _loadPrices(query: f == 'All' ? null : f);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Item Cards List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C896)))
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.shopping_basket_outlined, size: 48, color: Color(0xFF8B949E)),
                            const SizedBox(height: 12),
                            Text(
                              'No price history found.',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Scan receipts or chat line items to build price intelligence.',
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) => _buildPriceCard(_items[idx]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(Map<String, dynamic> item) {
    final name = item['item_name'] as String? ?? 'Item';
    final count = item['purchase_count'] as int? ?? 1;
    final latestPrice = (item['latest_price'] as num?)?.toDouble() ?? 0.0;
    final minPrice = (item['min_price'] as num?)?.toDouble() ?? latestPrice;
    final cheapestStore = item['cheapest_store'] as String?;
    final inflationPct = (item['inflation_pct'] as num?)?.toDouble() ?? 0.0;
    final storeComparison = item['store_comparison'] as Map<String, dynamic>? ?? {};

    final isInflationHigh = inflationPct > 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isInflationHigh
                      ? Colors.redAccent.withValues(alpha: 0.15)
                      : const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isInflationHigh ? '+$inflationPct% Inflation' : 'Stable Price',
                  style: TextStyle(
                    color: isInflationHigh ? Colors.redAccent : const Color(0xFF00C896),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetric('Latest Price', 'SAR ${latestPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 20),
              _buildMetric('Lowest Recorded', 'SAR ${minPrice.toStringAsFixed(2)}', isHighlight: true),
              const SizedBox(width: 20),
              _buildMetric('Purchases', '$count times'),
            ],
          ),
          if (storeComparison.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF30363D), height: 1),
            const SizedBox(height: 10),
            const Text(
              'Store Price Comparison',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: storeComparison.entries.map((entry) {
                final isCheapest = entry.key == cheapestStore;
                final price = (entry.value as num?)?.toDouble() ?? 0.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCheapest ? const Color(0xFF00C896).withValues(alpha: 0.1) : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCheapest ? const Color(0xFF00C896).withValues(alpha: 0.4) : const Color(0xFF30363D),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCheapest) ...[
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFF00C896)),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${entry.key}: SAR ${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isCheapest ? const Color(0xFF00C896) : const Color(0xFFC9D1D9),
                          fontSize: 11,
                          fontWeight: isCheapest ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? const Color(0xFF00C896) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
