import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/budget_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../transactions/manual_expense_sheet.dart';
import '../../models/money.dart';
import '../../models/category_catalog.dart';
import '../../services/salary_cycle_service.dart';

/// The advice under an affordability verdict, in the user's language (UX-21),
/// built from the numbers of the API answer or the offline estimate
/// (`verdict`, `post_purchase_remaining`, `current_daily_allowance`,
/// `post_purchase_daily_allowance`, `days_to_payday`), never from the
/// server's own English/Arabic sentences; amounts use the riyal formatter.
String affordabilityAdvice(AppLocalizations l, Map<String, dynamic> res) {
  double n(String key) => (res[key] as num?)?.toDouble() ?? 0.0;
  final days = (res['days_to_payday'] as num?)?.toInt() ?? 0;
  final daysText = l.plural('sim_days_left', days);
  switch (res['verdict']) {
    case 'invalid':
      return l.get('sim_detail_invalid');
    case 'caution':
      return l.format('sim_detail_caution', {
        'from': l.sar(n('current_daily_allowance')),
        'to': l.sar(n('post_purchase_daily_allowance')),
      });
    case 'unaffordable':
      return l.format('sim_detail_unaffordable', {'days': daysText});
    default:
      return l.format('sim_detail_comfortable', {
        'remaining': l.sar(n('post_purchase_remaining')),
        'days': daysText,
      });
  }
}

/// Pre-Purchase Affordability Simulator ("Can I Afford This? / هل أقدر أشتري؟")
/// Evaluates potential purchase impact against salary cycle headroom, category budgets,
/// and days until the household payday. Provides full offline calculation fallback.
class AffordabilitySimulatorSheet extends StatefulWidget {
  final String? householdId;
  final String? defaultItem;
  final double? defaultAmount;
  final String? defaultCategory;

  const AffordabilitySimulatorSheet({
    super.key,
    this.householdId,
    this.defaultItem,
    this.defaultAmount,
    this.defaultCategory,
  });

  static Future<void> show(
    BuildContext context, {
    String? householdId,
    String? defaultItem,
    double? defaultAmount,
    String? defaultCategory,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: AffordabilitySimulatorSheet(
          householdId: householdId,
          defaultItem: defaultItem,
          defaultAmount: defaultAmount,
          defaultCategory: defaultCategory,
        ),
      ),
    );
  }

  @override
  State<AffordabilitySimulatorSheet> createState() => _AffordabilitySimulatorSheetState();
}

class _AffordabilitySimulatorSheetState extends State<AffordabilitySimulatorSheet> {
  late final TextEditingController _itemCtrl;
  late final TextEditingController _amountCtrl;
  late String _selectedCategory;
  bool _isSimulating = false;
  Map<String, dynamic>? _result;

  static final List<Map<String, String>> _categories = [
    for (final code in CategoryCatalog.pickerCodes) {'code': code, 'emoji': CategoryCatalog.emoji(code)},
  ];

  @override
  void initState() {
    super.initState();
    _itemCtrl = TextEditingController(text: widget.defaultItem ?? '');
    _amountCtrl = TextEditingController(
      text: widget.defaultAmount != null && widget.defaultAmount! > 0
          ? widget.defaultAmount!.toStringAsFixed(0)
          : '',
    );
    _selectedCategory = widget.defaultCategory ?? 'OPEX-SHOPPING';

    if (widget.defaultAmount != null && widget.defaultAmount! > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _simulate());
    }
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _addPresetAmount(double delta) {
    final current = parseMoneyInput(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    final next = current + delta;
    _amountCtrl.text = next.toStringAsFixed(0);
    _simulate();
  }

  Future<void> _simulate() async {
    final amount = parseMoneyInput(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _isSimulating = true);

    final hid = widget.householdId ?? '';
    final item = _itemCtrl.text.trim().isNotEmpty ? _itemCtrl.text.trim() : context.tr('sim_item');

    Map<String, dynamic>? data;

    // 1. Try online simulation API if network available
    try {
      if (hid.isNotEmpty) {
        data = await ApiService.instance.simulateAffordability(
          householdId: hid,
          targetAmount: amount,
          itemName: item,
          categoryCode: _selectedCategory,
        );
      }
    } catch (_) {
      data = null;
    }

    // 2. Offline fallback calculation if network unavailable
    if (data == null || data['verdict'] == null) {
      data = _calculateOfflineSimulation(amount, _selectedCategory, item);
    }

    if (mounted) {
      setState(() {
        _result = data;
        _isSimulating = false;
      });
    }
  }

  Map<String, dynamic> _calculateOfflineSimulation(
    double targetAmount,
    String categoryCode,
    String itemName,
  ) {
    // The household payday (never a hard-coded 27th), on the Riyadh date.
    final daysRemaining = max(1, SalaryCycleService.daysUntilNextPayday());

    // Compute from active in-memory cached budgets
    double totalRemaining = 0.0;
    double catRemaining = 0.0;
    double flexibleHeadroom = 0.0;

    try {
      final categories = context.read<BudgetProvider>().categories;
      for (final c in categories) {
        final rem = max(0.0, c.remainingAmount);
        totalRemaining += rem;
        if (c.categoryCode == categoryCode) {
          catRemaining = rem;
        } else {
          flexibleHeadroom += rem;
        }
      }
    } catch (_) {}

    final newRemaining = totalRemaining - targetAmount;
    final dailyRemaining = totalRemaining / daysRemaining;
    final newDaily = max(0.0, newRemaining / daysRemaining);

    // The advice text is built at display time in the user's language
    // (affordabilityAdvice), from these numbers.
    final String verdict;
    if (targetAmount <= catRemaining) {
      verdict = 'comfortable';
    } else if (targetAmount <= (catRemaining + flexibleHeadroom)) {
      verdict = 'caution';
    } else {
      verdict = 'unaffordable';
    }

    return {
      'verdict': verdict,
      'is_affordable': verdict == 'comfortable' || verdict == 'caution',
      'item_name': itemName,
      'target_amount': targetAmount,
      'current_total_remaining': totalRemaining,
      'post_purchase_remaining': newRemaining,
      'current_daily_allowance': dailyRemaining,
      'post_purchase_daily_allowance': newDaily,
      'days_to_payday': daysRemaining,
      'is_offline': true,
    };
  }

  void _onProceedToLogExpense() {
    Navigator.pop(context);
    final amt = parseMoneyInput(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    ManualExpenseSheet.show(
      context,
      householdId: widget.householdId,
      initialMerchant: _itemCtrl.text.trim(),
      initialAmount: amt > 0 ? amt : null,
      initialCategory: _selectedCategory,
    );
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
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF58A6FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.calculate_outlined,
                    color: Color(0xFF58A6FF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('can_i_afford_this'),
                        style: GoogleFonts.outfit(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        context.tr('affordability_simulator_desc'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('close'),
                  icon: Icon(Icons.close_rounded, color: context.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(color: context.borderColor, height: 1),

          // Body Form & Simulation Output
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Item Name
                  TextField(
                    controller: _itemCtrl,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.tr('item_or_service'),
                      labelStyle: TextStyle(color: context.textSecondary),
                      prefixIcon: Icon(Icons.shopping_bag_outlined, color: context.textSecondary, size: 20),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _simulate(),
                  ),
                  const SizedBox(height: 12),

                  // Amount
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: context.tr('enter_amount'),
                      prefixText: '${context.tr('sar')} ',
                      labelStyle: TextStyle(color: context.textSecondary),
                      prefixIcon: const Icon(Icons.attach_money_rounded, color: AppThemes.success, size: 20),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _simulate(),
                  ),
                  const SizedBox(height: 10),

                  // Quick preset chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPresetChip('+100', 100),
                        const SizedBox(width: 8),
                        _buildPresetChip('+250', 250),
                        const SizedBox(width: 8),
                        _buildPresetChip('+500', 500),
                        const SizedBox(width: 8),
                        _buildPresetChip('+1,000', 1000),
                        const SizedBox(width: 8),
                        _buildPresetChip('+2,500', 2500),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Category Selector
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    dropdownColor: context.cardBg,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.tr('category'),
                      labelStyle: TextStyle(color: context.textSecondary),
                      prefixIcon: Icon(Icons.category_outlined, color: context.textSecondary, size: 20),
                      filled: true,
                      fillColor: context.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _categories.map((c) {
                      final code = c['code']!;
                      final emoji = c['emoji']!;
                      return DropdownMenuItem(
                        value: code,
                        child: Text('$emoji${context.trCat(code)}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCategory = val);
                        if (_amountCtrl.text.isNotEmpty) _simulate();
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Simulate Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemes.success,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSimulating ? null : _simulate,
                    child: _isSimulating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.flash_on_rounded, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('simulate'),
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                  ),

                  // Result Card
                  if (_result != null) ...[
                    const SizedBox(height: 20),
                    _buildResultCard(context),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double amount) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: context.textPrimary)),
      backgroundColor: context.subtleCardBg,
      side: BorderSide(color: context.borderColor),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      onPressed: () => _addPresetAmount(amount),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    final res = _result!;
    final verdict = res['verdict'] as String? ?? 'comfortable';
    final targetAmt = (res['target_amount'] as num?)?.toDouble() ?? 0.0;
    final item = res['item_name'] as String? ?? context.tr('sim_item');
    final daysToPayday = res['days_to_payday'] as int? ?? 0;
    final dailyCurrent = (res['current_daily_allowance'] as num?)?.toDouble() ?? 0.0;
    final dailyPost = (res['post_purchase_daily_allowance'] as num?)?.toDouble() ?? 0.0;
    final isOffline = res['is_offline'] == true;

    Color badgeColor = AppThemes.success;
    IconData badgeIcon = Icons.check_circle_outline_rounded;
    String verdictLabel = context.tr('comfortably_affordable');

    if (verdict == 'caution') {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
      verdictLabel = context.tr('caution_reallocation');
    } else if (verdict == 'unaffordable') {
      badgeColor = Colors.redAccent;
      badgeIcon = Icons.cancel_outlined;
      verdictLabel = context.tr('unaffordable_exceeds');
    }

    // UX-21: the same localized advice for the API answer and the offline
    // estimate, in en / ar / ur.
    final adviceText = affordabilityAdvice(AppLocalizations.of(context), res);

    final monthlyBnpl = targetAmt > 0 ? (targetAmt / 4.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.subtleCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Verdict Header
          Row(
            children: [
              Icon(badgeIcon, color: badgeColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  verdictLabel,
                  style: GoogleFonts.outfit(
                    color: badgeColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isOffline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.tr('offline_estimate'),
                    style: TextStyle(color: context.textSecondary, fontSize: 9.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Item and Amount
          Text(
            '$item • ${context.sar(targetAmt)}',
            style: GoogleFonts.outfit(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$daysToPayday ${context.tr('days_to_payday')}',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Daily Allowance Impact Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('before_purchase'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyCurrent, decimals: 1)}),
                        style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: context.textSecondary, size: 16),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.tr('after_purchase'),
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.trArgs('per_day_suffix', {'amount': context.sar(dailyPost, decimals: 1)}),
                        style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Advice Text
          if (adviceText.isNotEmpty)
            Text(
              adviceText,
              style: TextStyle(color: context.textPrimary, fontSize: 12.5, height: 1.4),
            ),
          const SizedBox(height: 14),

          // Smart BNPL 4-Month Split Option
          if (targetAmt >= 150) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF58A6FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF58A6FF).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_rounded, color: Color(0xFF58A6FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${context.tr('split_with_bnpl')}: 4 × ${context.sar(monthlyBnpl)}/${context.tr('months_short')}',
                      style: const TextStyle(
                        color: Color(0xFF58A6FF),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action CTA: Log Expense
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.cardBg,
              foregroundColor: AppThemes.success,
              side: const BorderSide(color: AppThemes.success),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: Text(context.tr('record_expense')),
            onPressed: _onProceedToLogExpense,
          ),
        ],
      ),
    );
  }
}
