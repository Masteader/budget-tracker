/// Tools: the secondary features that used to crowd the dashboard and the
/// speed dial (R3). Each one has exactly one entry point here.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../../widgets/accounts/account_transfer_sheet.dart';
import '../../widgets/accounts/record_income_sheet.dart';
import '../../widgets/analytics/smart_shopping_basket_sheet.dart';
import '../../widgets/dashboard/accounts_summary_card.dart';
import '../../widgets/simulator/affordability_simulator_sheet.dart';
import '../accounts/accounts_overview_screen.dart';
import '../analytics/grocery_price_intelligence_screen.dart';
import '../scanner/batch_receipt_scanner_screen.dart';

class ToolsScreen extends StatelessWidget {
  final String householdId;

  const ToolsScreen({super.key, required this.householdId});

  static Future<void> open(BuildContext context, {required String householdId}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ToolsScreen(householdId: householdId)),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool(
        key: 'tool_affordability',
        icon: Icons.calculate_outlined,
        color: AppThemes.champagneGold,
        title: context.tr('affordability_simulator'),
        subtitle: context.tr('tool_affordability_desc'),
        onTap: () => AffordabilitySimulatorSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_accounts',
        icon: Icons.account_balance_wallet_outlined,
        color: AppThemes.iceCyan,
        title: context.tr('accounts_balances'),
        subtitle: context.tr('tool_accounts_desc'),
        onTap: () => _push(context, AccountsOverviewScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_record_income',
        icon: Icons.savings_rounded,
        color: AppThemes.success,
        title: context.tr('record_income'),
        subtitle: context.tr('tool_record_income_desc'),
        onTap: () => RecordIncomeSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_transfer',
        icon: Icons.swap_horiz_rounded,
        color: AppThemes.iceCyan,
        title: context.tr('transfer_funds'),
        subtitle: context.tr('tool_transfer_desc'),
        onTap: () => AccountTransferSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_batch_scan',
        icon: Icons.dynamic_feed_rounded,
        color: AppThemes.electricTeal,
        title: context.tr('batch_scan_receipts'),
        subtitle: context.tr('tool_batch_scan_desc'),
        onTap: () => _push(context, BatchReceiptScannerScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_price_tracker',
        icon: Icons.trending_up_rounded,
        color: AppThemes.mintNeon,
        title: context.tr('price_tracker'),
        subtitle: context.tr('tool_price_tracker_desc'),
        onTap: () => _push(context, GroceryPriceIntelligenceScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_smart_basket',
        icon: Icons.shopping_basket_outlined,
        color: AppThemes.mintNeon,
        title: context.tr('smart_basket_optimizer'),
        subtitle: context.tr('tool_smart_basket_desc'),
        onTap: () => SmartShoppingBasketSheet.show(context, householdId: householdId),
      ),
    ];

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        title: Text(
          context.tr('tools_title'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: context.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: [
          Text(
            context.tr('tools_desc'),
            style: GoogleFonts.outfit(fontSize: 12.5, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          // The balances summary (on the dashboard only with 2+ accounts).
          AccountsSummaryCard(householdId: householdId),
          const SizedBox(height: 12),
          for (final tool in tools) ...[
            _ToolTile(tool: tool),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Tool {
  final String key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tool({
    required this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _ToolTile extends StatelessWidget {
  final _Tool tool;

  const _ToolTile({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey(tool.key),
        borderRadius: BorderRadius.circular(16),
        onTap: tool.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: tool.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(tool.icon, color: tool.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.subtitle,
                      style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: context.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
