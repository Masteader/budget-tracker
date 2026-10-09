import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';

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
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF30363D)),
          left: BorderSide(color: Color(0xFF30363D)),
          right: BorderSide(color: Color(0xFF30363D)),
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
                color: const Color(0xFF30363D),
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
                    color: const Color(0xFF00C896).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF00C896), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Basket Optimizer',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Compare totals across Panda, Danube, Tamimi & Othaim',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF8B949E),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF8B949E)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF30363D), height: 1),

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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Add item (e.g. Olive Oil, Rice)...',
                          hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF30363D)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF30363D)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C896),
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
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(sug),
                          labelStyle: TextStyle(
                            color: inBasket ? const Color(0xFF00C896) : const Color(0xFF8B949E),
                            fontSize: 12,
                          ),
                          backgroundColor: inBasket
                              ? const Color(0xFF00C896).withValues(alpha: 0.12)
                              : const Color(0xFF0D1117),
                          side: BorderSide(
                            color: inBasket ? const Color(0xFF00C896) : const Color(0xFF30363D),
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
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C896)),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Optimizing basket prices...',
                            style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
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
                      'Shopping Checklist (${_checkedItems.length}/${_basketItems.length})',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
                        child: const Text('Clear All', style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 12)),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                if (_basketItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Center(
                      child: Text(
                        'Your shopping list is empty.\nAdd items or tap suggestions above to compare prices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, height: 1.5),
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
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChecked ? const Color(0xFF00C896).withValues(alpha: 0.3) : const Color(0xFF30363D),
                        ),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isChecked,
                            activeColor: const Color(0xFF00C896),
                            checkColor: Colors.black,
                            onChanged: (_) => _toggleChecked(item),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                color: isChecked ? const Color(0xFF8B949E) : Colors.white,
                                fontSize: 14,
                                decoration: isChecked ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF8B949E), size: 18),
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
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C896).withValues(alpha: 0.3)),
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
                  color: const Color(0xFF00C896).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00C896)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events, color: Color(0xFF00C896), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'CHEAPEST STORE',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF00C896),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${cheapestTotal.toStringAsFixed(2)} SAR',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF00C896),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Complete trip at $cheapestStore saves up to ${singleSavings.toStringAsFixed(2)} SAR vs competitors.',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF30363D), height: 1),
          const SizedBox(height: 14),

          // Store Breakdown Grid/Row
          Text(
            'Supermarket Price Comparison',
            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8B949E), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: storeTotals.entries.map((entry) {
                final isWinner = entry.key == cheapestStore;
                final val = (entry.value as num?)?.toDouble() ?? 0.0;
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isWinner
                        ? const Color(0xFF00C896).withValues(alpha: 0.1)
                        : const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isWinner ? const Color(0xFF00C896) : const Color(0xFF30363D),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          color: isWinner ? const Color(0xFF00C896) : const Color(0xFF8B949E),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${val.toStringAsFixed(2)} SAR',
                        style: TextStyle(
                          color: isWinner ? Colors.white : const Color(0xFFC9D1D9),
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
                          'Multi-Store Split Savings',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF58A6FF),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Splitting items across stores reduces total to ${splitTotal.toStringAsFixed(2)} SAR (saves extra ${splitSavings.toStringAsFixed(2)} SAR).',
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
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
