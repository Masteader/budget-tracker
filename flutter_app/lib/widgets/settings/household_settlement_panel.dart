import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_themes.dart';
import '../../utils/failure_log.dart';
import '../dashboard/multi_roommate_settlement_card.dart';

/// The body of the Settings "partner settlement" section.
///
/// One state per household: give it a key derived from [householdId], so a
/// switch starts empty and can never show the previous household's debts. It
/// sits inside a folded section, which only builds it when opened, so the
/// summary is fetched on open rather than every time Settings is shown.
class HouseholdSettlementPanel extends StatefulWidget {
  final String householdId;

  /// Bump to fetch again: roles or the Nafaqah provider changed.
  final int refreshToken;

  /// What a family household shows; it loads its own Nafaqah summary.
  final WidgetBuilder familyBuilder;

  const HouseholdSettlementPanel({
    super.key,
    required this.householdId,
    required this.familyBuilder,
    this.refreshToken = 0,
  });

  @override
  State<HouseholdSettlementPanel> createState() => _HouseholdSettlementPanelState();
}

class _HouseholdSettlementPanelState extends State<HouseholdSettlementPanel> {
  SettlementV2Summary? _summary;
  bool _failed = false;

  /// Only the newest request may change the state: an older one that answers
  /// late, or fails late, describes something that has since changed.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant HouseholdSettlementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _failed = false;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final generation = ++_generation;
    try {
      final summary = await ApiService.instance.getSettlementV2(widget.householdId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _summary = summary;
        _failed = false;
      });
    } catch (e) {
      logFailure('Settings.settlementFetch', e);
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  void _refresh() {
    setState(() => _failed = false);
    _fetch();
  }

  void _retry() {
    setState(() {
      _failed = false;
      _summary = null;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    // After a failed refresh the last summary may hold a debt that is already
    // settled, and its Settle button could record it twice: offer Retry instead.
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.tr('load_error_generic'),
                style: TextStyle(color: context.dangerColor, fontSize: 12),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.accentText),
              onPressed: _retry,
              child: Text(context.tr('roles_retry')),
            ),
          ],
        ),
      );
    }

    final summary = _summary;
    if (summary == null) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText),
        ),
      );
    }

    if (summary.isRoommateMode) {
      return MultiRoommateSettlementCard(
        householdId: widget.householdId,
        summary: summary,
        onSettled: _refresh,
      );
    }
    return widget.familyBuilder(context);
  }
}
