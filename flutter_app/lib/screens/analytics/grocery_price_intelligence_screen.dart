import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/analytics/smart_shopping_basket_sheet.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

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
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.cardBg,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: AppThemes.success, size: 22),
            const SizedBox(width: 8),
            Text(
              context.tr('grocery_price_intelligence'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.tr('smart_basket_optimizer'),
            icon: const Icon(Icons.shopping_basket_outlined, color: AppThemes.success),
            onPressed: () {
              HapticFeedback.mediumImpact();
              SmartShoppingBasketSheet.show(context, householdId: widget.householdId);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppThemes.success,
        icon: const Icon(Icons.shopping_basket_rounded, color: Colors.black),
        label: Text(
          context.tr('shopping_list'),
          style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          HapticFeedback.mediumImpact();
          SmartShoppingBasketSheet.show(context, householdId: widget.householdId);
        },
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => _loadPrices(query: v),
              style: TextStyle(color: context.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: context.tr('grocery_search_hint'),
                hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: context.textSecondary, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                      tooltip: context.tr('support_clear_search'),
                        icon: Icon(Icons.clear, color: context.textSecondary, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadPrices();
                        },
                      )
                    : null,
                filled: true,
                fillColor: context.inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppThemes.success),
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
                  label: Text(f == 'All' ? context.tr('all') : f, style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : context.textPrimary)),
                  selected: isSelected,
                  selectedColor: AppThemes.success,
                  backgroundColor: context.cardBg,
                  side: BorderSide(color: isSelected ? AppThemes.success : context.borderColor),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
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
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppShimmer.listItems(count: 4),
                  )
                : _items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: AppEmptyState(
                          icon: Icons.shopping_basket_outlined,
                          title: context.tr('grocery_empty_title'),
                          message: context.tr('grocery_empty_desc'),
                          actionLabel: context.tr('grocery_refresh'),
                          onAction: () => _loadPrices(),
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
    final name = item['item_name'] as String? ?? context.tr('sim_item');
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
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
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
                      : AppThemes.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isInflationHigh ? context.trArgs('grocery_inflation', {'pct': inflationPct}) : context.tr('grocery_stable'),
                  style: TextStyle(
                    color: isInflationHigh ? Colors.redAccent : AppThemes.success,
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
              _buildMetric(context.tr('grocery_latest_price'), context.sar(latestPrice)),
              const SizedBox(width: 20),
              _buildMetric(context.tr('grocery_lowest'), context.sar(minPrice), isHighlight: true),
              const SizedBox(width: 20),
              _buildMetric(context.tr('grocery_purchases'), context.trArgs('grocery_times', {'count': count})),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('grocery_trend'),
                style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                context.tr('grocery_touch'),
                style: GoogleFonts.outfit(color: context.successText, fontSize: 10, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildPriceTrendChart(item['history'] as List? ?? [], minPrice, latestPrice),
          if (storeComparison.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: context.borderColor, height: 1),
            const SizedBox(height: 10),
            Text(
              context.tr('grocery_store_comparison'),
              style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
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
                    color: isCheapest ? AppThemes.success.withValues(alpha: 0.1) : context.subtleCardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCheapest ? AppThemes.success.withValues(alpha: 0.4) : context.borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCheapest) ...[
                        const Icon(Icons.star_rounded, size: 14, color: AppThemes.success),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${entry.key}: ${context.sar(price)}',
                        style: TextStyle(
                          color: isCheapest ? AppThemes.success : context.textPrimary,
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

  Widget _buildPriceTrendChart(List<dynamic> rawHistory, double minPrice, double maxPrice) {
    final history = rawHistory.whereType<Map<String, dynamic>>().toList();

    List<FlSpot> spots = [];
    if (history.length >= 2) {
      for (int i = 0; i < history.length; i++) {
        final price = (history[i]['unit_price'] as num?)?.toDouble() ?? 0.0;
        spots.add(FlSpot(i.toDouble(), price));
      }
    } else if (history.isNotEmpty) {
      final price = (history.first['unit_price'] as num?)?.toDouble() ?? minPrice;
      spots = [
        FlSpot(0, price),
        FlSpot(1, price),
      ];
    } else {
      spots = [
        FlSpot(0, minPrice),
        FlSpot(1, maxPrice > minPrice ? maxPrice : (minPrice + 1)),
      ];
    }

    final double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.9;
    final double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.1;

    return Container(
      height: 90,
      padding: const EdgeInsets.only(top: 8, right: 12, left: 4, bottom: 4),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY > 0 ? minY : 0,
          maxY: maxY > minY ? maxY : (minY + 10),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.cardBg,
              tooltipBorder: BorderSide(color: context.borderColor),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final date = (idx >= 0 && idx < history.length)
                      ? (history[idx]['date'] ?? '')
                      : '';
                  return LineTooltipItem(
                    '${context.sar(spot.y)}${date.isNotEmpty ? '\n$date' : ''}',
                    GoogleFonts.outfit(
                      color: context.successText,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppThemes.success,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: AppThemes.success,
                    strokeWidth: 1.5,
                    strokeColor: context.cardBg,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppThemes.success.withValues(alpha: 0.25),
                    AppThemes.success.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? AppThemes.success : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
