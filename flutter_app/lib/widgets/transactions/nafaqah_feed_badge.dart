import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../models/nafaqah.dart';
import '../../theme/app_themes.dart';

/// What a transaction is in a family household (UX-04), shown in the feed
/// instead of the roommate "shared / me / partner" badge.
enum NafaqahBadgeKind { household, owedToWife, wifeAllowance, settlement }

/// The badge of [tx]: a settlement anywhere; in a family household its
/// Nafaqah class (no class = the husband's household expense). Null for an
/// ordinary roommate / partner expense.
NafaqahBadgeKind? nafaqahBadgeKind(Transaction tx, {required bool isFamily}) {
  if (tx.isSettlement) return NafaqahBadgeKind.settlement;
  if (!isFamily) return null;
  return nafaqahBadgeKindForClass(tx.nafaqahClass);
}

NafaqahBadgeKind nafaqahBadgeKindForClass(String? nafaqahClass) => switch (nafaqahClass) {
      kWifeReimbursable => NafaqahBadgeKind.owedToWife,
      kWifePersonal => NafaqahBadgeKind.wifeAllowance,
      _ => NafaqahBadgeKind.household,
    };

/// The family context the feed needs to word its badges: whether the
/// household is a family, whether the viewer is the wife, and the wives' names.
class FeedFamilyContext {
  final bool isFamily;
  final bool viewerIsWife;
  final Map<String, String> wifeNames;

  const FeedFamilyContext({this.isFamily = false, this.viewerIsWife = false, this.wifeNames = const {}});

  factory FeedFamilyContext.fromSummary(NafaqahSummary summary) => FeedFamilyContext(
        isFamily: summary.isFamily,
        viewerIsWife: summary.callerIsWife,
        wifeNames: {
          for (final w in summary.wives)
            if ((w.displayName ?? '').trim().isNotEmpty) w.id.toLowerCase(): w.displayName!.trim(),
        },
      );

  /// The wife [tx] names (or the only wife), or null.
  String? wifeNameFor(Transaction tx) {
    final id = tx.nafaqahSpouseId?.toLowerCase();
    if (id != null && wifeNames.containsKey(id)) return wifeNames[id];
    return wifeNames.length == 1 ? wifeNames.values.first : null;
  }
}

class NafaqahFeedBadge extends StatelessWidget {
  final NafaqahBadgeKind kind;
  final String? wifeName;
  final bool viewerIsWife;
  final bool detailed;

  const NafaqahFeedBadge({
    super.key,
    required this.kind,
    this.wifeName,
    this.viewerIsWife = false,
    this.detailed = false,
  });

  static String label(BuildContext context, NafaqahBadgeKind kind, {String? wifeName, bool viewerIsWife = false}) {
    final name = (wifeName ?? '').trim().isEmpty ? context.tr('nafaqah_wife_generic') : wifeName!.trim();
    switch (kind) {
      case NafaqahBadgeKind.owedToWife:
        return viewerIsWife ? context.tr('feed_badge_owed_to_me') : context.trArgs('feed_badge_owed_to_wife', {'wife': name});
      case NafaqahBadgeKind.wifeAllowance:
        return viewerIsWife ? context.tr('feed_badge_my_allowance') : context.trArgs('feed_badge_wife_allowance', {'wife': name});
      case NafaqahBadgeKind.settlement:
        return context.tr('feed_badge_settlement');
      case NafaqahBadgeKind.household:
        return context.tr('feed_badge_household');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color tint, IconData icon) = switch (kind) {
      NafaqahBadgeKind.owedToWife => (
          context.warnText,
          context.warnText,
          Icons.currency_exchange_rounded
        ),
      NafaqahBadgeKind.wifeAllowance => (
          context.accentText,
          context.accentText,
          Icons.shopping_bag_outlined
        ),
      NafaqahBadgeKind.settlement => (
          context.accentText,
          context.accentText,
          Icons.swap_horiz_rounded
        ),
      NafaqahBadgeKind.household => (context.textSecondary, context.textSecondary, Icons.home_outlined),
    };
    return Container(
      key: ValueKey('feed_badge_${kind.name}'),
      padding: EdgeInsets.symmetric(horizontal: detailed ? 10 : 6, vertical: detailed ? 4 : 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tint.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: detailed ? 14 : 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label(context, kind, wifeName: wifeName, viewerIsWife: viewerIsWife),
              style: GoogleFonts.outfit(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transactions of one calendar day (device-local), in feed order.
class TransactionDayGroup {
  final DateTime day;
  final List<Transaction> transactions;
  const TransactionDayGroup(this.day, this.transactions);
}

/// Groups consecutive transactions of the same local day (UX-11). The input
/// order is kept, so it works for newest-first and oldest-first lists.
List<TransactionDayGroup> groupTransactionsByDay(List<Transaction> ordered) {
  final groups = <TransactionDayGroup>[];
  for (final tx in ordered) {
    final local = tx.timestamp.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.transactions.add(tx);
    } else {
      groups.add(TransactionDayGroup(day, [tx]));
    }
  }
  return groups;
}

/// "Today", "Yesterday" or the weekday and date ("الأحد 19 أكتوبر"); the year
/// is added outside the current year.
String feedDayLabel(BuildContext context, DateTime day, {DateTime? now}) {
  final n = (now ?? DateTime.now());
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return context.tr('feed_today');
  if (diff == 1) return context.tr('feed_yesterday');
  return context.fmtDate(d, d.year == today.year ? 'EEEE d MMMM' : 'EEEE d MMMM y');
}
