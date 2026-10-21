import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../l10n/app_localizations.dart';

class SmartShoppingBasketSheet extends StatefulWidget {
  final String householdId;

  const SmartShoppingBasketSheet({super.key, required this.householdId});

  static Future<void> show(BuildContext context, {required String householdId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SmartShoppingBasketSheet(householdId: householdId),
    );
  }

  @override
  State<SmartShoppingBasketSheet> createState() => _SmartShoppingBasketSheetState();
}

class _SmartShoppingBasketSheetState extends State<SmartShoppingBasketSheet> {
  final TextEditingController _itemInputCtrl = TextEditingController();
  final List<String> _basketItems = ['Milk', 'Chicken', 'Bread', 'Eggs'];
  final Set<String> _checkedItems = {};

  final List<String> _popularSuggestions = [
    'Milk',
    'Bread',
    'Chicken',
    'Eggs',
    'Cheese',
    'Rice',
    'Oil',
    'Coffee',
    'Tea',
    'Water',
  ];

  bool _isOptimizing = false;
  Map<String, dynamic>? _optimizationResult;

  @override
  void initState() {
    super.initState();
    _fetchOptimization();
  }

  @override
  void dispose() {
    _itemInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOptimization() async {
    if (_basketItems.isEmpty) {
      if (mounted) {
        setState(() {
          _optimizationResult = null;
          _isOptimizing = false;
        });
      }
      return;
    }

    setState(() => _isOptimizing = true);
    try {
      final res = await ApiService.instance.optimizeShoppingBasket(
        widget.householdId,
        _basketItems,
      );
      if (mounted) {
        setState(() {
          _optimizationResult = res;
          _isOptimizing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isOptimizing = false);
    }
  }

  void _addItem(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_basketItems.any((i) => i.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _basketItems.add(trimmed);
      _itemInputCtrl.clear();
    });
    _fetchOptimization();
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final removed = _basketItems.removeAt(index);
      _checkedItems.remove(removed);
    });
    _fetchOptimization();
  }

  void _toggleChecked(String item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_checkedItems.contains(item)) {
        _checkedItems.remove(item);
      } else {
        _checkedItems.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: context.borderColor),
          left: BorderSide(color: context.borderColor),
          right: BorderSide(color: context.borderColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppThemes.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined, color: AppThemes.success, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('smart_basket_optimizer'),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        context.tr('basket_compare_desc'),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('close'),
                  icon: Icon(Icons.close, color: context.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(color: context.borderColor, height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Input Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemInputCtrl,
                        onSubmitted: _addItem,
                        style: TextStyle(color: context.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: context.tr('basket_add_hint'),
                          hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                          filled: true,
                          fillColor: context.inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.borderColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemes.success,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _addItem(_itemInputCtrl.text),
                      child: const Icon(Icons.add, color: Colors.black, size: 20),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Quick suggestions chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _popularSuggestions.map((sug) {
                      final inBasket = _basketItems.any((i) => i.toLowerCase() == sug.toLowerCase());
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: ActionChip(
                          label: Text(sug),
                          labelStyle: TextStyle(
                            color: inBasket ? AppThemes.success : context.textSecondary,
                            fontSize: 12,
                          ),
                          backgroundColor: inBasket
                              ? AppThemes.success.withValues(alpha: 0.12)
                              : context.chipBg,
                          side: BorderSide(
                            color: inBasket ? AppThemes.success : context.borderColor,
                          ),
                          onPressed: () => _addItem(sug),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 20),

                // Optimization Summary Card
                if (_isOptimizing)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.chipBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppThemes.success),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.tr('basket_optimizing'),
                            style: TextStyle(color: context.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_optimizationResult != null && _basketItems.isNotEmpty)
                  _buildOptimizationCard(_optimizationResult!),

                const SizedBox(height: 20),

                // Basket Items Header & Checklist
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.trArgs('basket_checklist', {'done': _checkedItems.length, 'total': _basketItems.length}),
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    if (_basketItems.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _basketItems.clear();
                            _checkedItems.clear();
                            _optimizationResult = null;
                          });
                        },
                        child: Text(context.tr('clear_all'), style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12)),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                if (_basketItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: context.chipBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Center(
                      child: Text(
                        context.tr('basket_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.5),
                      ),
                    ),
                  )
                else
                  ...List.generate(_basketItems.length, (index) {
                    final item = _basketItems[index];
                    final isChecked = _checkedItems.contains(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.chipBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChecked ? AppThemes.success.withValues(alpha: 0.3) : context.borderColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isChecked,
                            activeColor: AppThemes.success,
                            checkColor: Colors.black,
                            onChanged: (_) => _toggleChecked(item),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                color: isChecked ? context.textSecondary : context.textPrimary,
                                fontSize: 14,
                                decoration: isChecked ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('a11y_remove_item'),
                            icon: Icon(Icons.remove_circle_outline, color: context.textSecondary, size: 18),
                            onPressed: () => _removeItem(index),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizationCard(Map<String, dynamic> data) {
    final cheapestStore = data['cheapest_store'] as String? ?? 'N/A';
    final cheapestTotal = (data['cheapest_store_total'] as num?)?.toDouble() ?? 0.0;
    final singleSavings = (data['single_store_savings'] as num?)?.toDouble() ?? 0.0;
    final storeTotals = (data['store_totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final splitOpt = (data['split_optimization'] as Map?)?.cast<String, dynamic>() ?? {};
    final splitTotal = (splitOpt['split_total'] as num?)?.toDouble() ?? 0.0;
    final splitSavings = (splitOpt['extra_savings_vs_single_store'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: context.chipBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemes.success.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Winner Single Store Banner
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppThemes.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppThemes.success),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events, color: AppThemes.success, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('basket_cheapest_store'),
                      style: GoogleFonts.outfit(
                        color: context.successText,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                context.sar(cheapestTotal),
                style: GoogleFonts.outfit(
                  color: context.successText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.trArgs('basket_single_store_saves', {'store': cheapestStore, 'amount': context.sar(singleSavings)}),
            style: TextStyle(color: context.textPrimary, fontSize: 13),
          ),

          const SizedBox(height: 16),
          Divider(color: context.borderColor, height: 1),
          const SizedBox(height: 14),

          // Store Breakdown Grid/Row
          Text(
            context.tr('basket_price_comparison'),
            style: GoogleFonts.outfit(fontSize: 12, color: context.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: storeTotals.entries.map((entry) {
                final isWinner = entry.key == cheapestStore;
                final val = (entry.value as num?)?.toDouble() ?? 0.0;
                return Container(
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isWinner
                        ? AppThemes.success.withValues(alpha: 0.1)
                        : context.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isWinner ? AppThemes.success : context.borderColor,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          color: isWinner ? AppThemes.success : context.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.sar(val),
                        style: TextStyle(
                          color: isWinner ? (context.isDark ? Colors.white : Colors.black) : context.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          if (splitSavings > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF388BFD).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF388BFD).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.splitscreen_rounded, color: Color(0xFF58A6FF), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('basket_split_savings'),
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF58A6FF),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          context.trArgs('basket_split_desc', {'total': context.sar(splitTotal), 'extra': context.sar(splitSavings)}),
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
