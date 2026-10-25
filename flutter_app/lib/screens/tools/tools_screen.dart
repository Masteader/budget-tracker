/// Tools: the secondary features that used to crowd the dashboard and the
/// speed dial (R3). Each one has exactly one entry point here.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_themes.dart';
import '../../core/widgets/three_d_surface_card.dart';
import '../../core/widgets/three_d_icon_puck.dart';
import '../../core/widgets/velvet_wave_header.dart';
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
        color: context.champagneGold,
        title: context.tr('affordability_simulator'),
        subtitle: context.tr('tool_affordability_desc'),
        onTap: () => AffordabilitySimulatorSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_accounts',
        icon: Icons.account_balance_wallet_outlined,
        color: context.accentText,
        title: context.tr('accounts_balances'),
        subtitle: context.tr('tool_accounts_desc'),
        onTap: () => _push(context, AccountsOverviewScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_record_income',
        icon: Icons.savings_rounded,
        color: context.accentText,
        title: context.tr('record_income'),
        subtitle: context.tr('tool_record_income_desc'),
        onTap: () => RecordIncomeSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_transfer',
        icon: Icons.swap_horiz_rounded,
        color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF9E1B42),
        title: context.tr('transfer_funds'),
        subtitle: context.tr('tool_transfer_desc'),
        onTap: () => AccountTransferSheet.show(context, householdId: householdId),
      ),
      _Tool(
        key: 'tool_batch_scan',
        icon: Icons.dynamic_feed_rounded,
        color: context.isDark ? const Color(0xFFE598B0) : const Color(0xFF4A0E1E),
        title: context.tr('batch_scan_receipts'),
        subtitle: context.tr('tool_batch_scan_desc'),
        onTap: () => _push(context, BatchReceiptScannerScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_price_tracker',
        icon: Icons.trending_up_rounded,
        color: context.champagneGold,
        title: context.tr('price_tracker'),
        subtitle: context.tr('tool_price_tracker_desc'),
        onTap: () => _push(context, GroceryPriceIntelligenceScreen(householdId: householdId)),
      ),
      _Tool(
        key: 'tool_smart_basket',
        icon: Icons.shopping_basket_outlined,
        color: context.isDark ? const Color(0xFFF0A3BC) : const Color(0xFF9E1B42),
        title: context.tr('smart_basket_optimizer'),
        subtitle: context.tr('tool_smart_basket_desc'),
        onTap: () => SmartShoppingBasketSheet.show(context, householdId: householdId),
      ),
    ];

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: VelvetWaveHeader(
              title: context.tr('tools_title'),
              subtitle: context.tr('tools_desc'),
              height: 140,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // The balances summary (on the dashboard only with 2+ accounts).
                AccountsSummaryCard(householdId: householdId),
                const SizedBox(height: 14),
                for (final tool in tools) ...[
                  _ToolTile(tool: tool),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
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
    return ThreeDSurfaceCard(
      borderRadius: 18.0,
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey(tool.key),
        borderRadius: BorderRadius.circular(18),
        onTap: tool.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              ThreeDIconPuck(
                icon: tool.icon,
                size: 42,
                isSquircle: true,
                iconColor: tool.color,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      style: GoogleFonts.outfit(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
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
