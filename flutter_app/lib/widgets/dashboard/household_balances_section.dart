import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../card_error_state.dart';
import 'family_reimbursement_card.dart';
import 'multi_roommate_settlement_card.dart';

/// Loads the household's settlement summary (`GET /households/{id}/settlement-v2`).
typedef SettlementLoader = Future<SettlementV2Summary> Function(String householdId);

/// Who owes whom in the household: the roommate settlement card for a
/// roommates household, otherwise the family Nafaqah card. A failed load is
/// an error card with a retry (UX-01): it used to fall through to the family
/// card, so a roommates household silently lost its balances.
class HouseholdBalancesSection extends StatefulWidget {
  final String householdId;
  final SettlementLoader? loadSettlement;
  final NafaqahSummaryLoader? loadNafaqah;

  /// The settlement summary after each successful load.
  final ValueChanged<SettlementV2Summary>? onSettlementLoaded;

  /// The Nafaqah summary after each load of the family card.
  final ValueChanged<NafaqahSummary>? onNafaqahLoaded;

  const HouseholdBalancesSection({
    super.key,
    required this.householdId,
    this.loadSettlement,
    this.loadNafaqah,
    this.onSettlementLoaded,
    this.onNafaqahLoaded,
  });

  @override
  State<HouseholdBalancesSection> createState() => _HouseholdBalancesSectionState();
}

class _HouseholdBalancesSectionState extends State<HouseholdBalancesSection> {
  late Future<SettlementV2Summary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant HouseholdBalancesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.householdId != widget.householdId) _future = _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<SettlementV2Summary> _load() async {
    final loader = widget.loadSettlement ?? ApiService.instance.getSettlementV2;
    final summary = await loader(widget.householdId);
    if (mounted) widget.onSettlementLoaded?.call(summary);
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SettlementV2Summary>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return CardErrorState(
            title: context.tr('household_balances_title'),
            message: context.tr('load_error_balances'),
            icon: Icons.account_balance_wallet_outlined,
            onRetry: _reload,
          );
        }
        // A reload keeps showing the previous summary (FutureBuilder keeps its data).
        if (!snap.hasData) {
          return Container(
            key: const Key('household_balances_loading'),
            height: 110,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.borderColor),
            ),
            child: const Center(
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final summary = snap.data!;
        if (summary.isRoommateMode) {
          return MultiRoommateSettlementCard(
            householdId: widget.householdId,
            summary: summary,
            onSettled: _reload,
          );
        }
        return FamilyReimbursementCard(
          householdId: widget.householdId,
          loadSummary: widget.loadNafaqah,
          onSummaryLoaded: widget.onNafaqahLoaded,
        );
      },
    );
  }
}
