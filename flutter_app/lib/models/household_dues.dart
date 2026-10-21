/// Who owes whom, from the viewer's point of view, for the dashboard hero
/// (UX-07: "Owed to Sara" in family mode; UX-16: "You owe Faisal" for
/// roommates).
library;

import 'models.dart';
import 'nafaqah.dart';

enum DueKind {
  /// Family mode, husband (or admin) viewing: the provider owes this wife.
  owedToWife,

  /// Family mode, the wife viewing: her husband owes her.
  owedToMe,

  /// Roommates: the viewer owes this roommate.
  iOwe,

  /// Roommates: this roommate owes the viewer.
  owedByRoommate,
}

class DueLine {
  final DueKind kind;

  /// The other person's name (the wife, the roommate), when known.
  final String? name;
  final double amount;

  const DueLine({required this.kind, required this.amount, this.name});
}

/// What the provider owes each wife for shared things she paid from her own
/// money (Nafaqah rule 2), as the viewer should see it. A wife sees only her
/// own balance; nothing outside family mode or when nothing is owed.
List<DueLine> nafaqahDueLines(NafaqahSummary summary) {
  if (!summary.isFamily) return const [];
  final lines = <DueLine>[];
  for (final wife in summary.wives) {
    final owed = wife.reimbursement.outstanding;
    if (owed < 0.005) continue;
    if (summary.callerIsWife) {
      if (wife.id == summary.callerUserId) lines.add(DueLine(kind: DueKind.owedToMe, amount: owed));
    } else {
      final name = (wife.displayName ?? '').trim();
      lines.add(DueLine(kind: DueKind.owedToWife, amount: owed, name: name.isEmpty ? null : name));
    }
  }
  return lines;
}

/// The viewer's net with each roommate from the simplified debts: what I owe
/// first, then what I am owed, each largest first. Empty without a viewer.
List<DueLine> roommateDueLines(SettlementV2Summary summary, String? meId) {
  if (meId == null || meId.isEmpty) return const [];
  final net = <String, double>{}; // > 0: they owe me; < 0: I owe them
  final names = <String, String>{};
  for (final d in summary.simplifiedDebts) {
    if (d.fromId == meId) {
      net[d.toId] = (net[d.toId] ?? 0) - d.amount;
      names[d.toId] = d.toName;
    } else if (d.toId == meId) {
      net[d.fromId] = (net[d.fromId] ?? 0) + d.amount;
      names[d.fromId] = d.fromName;
    }
  }
  final lines = <DueLine>[
    for (final e in net.entries)
      if (e.value <= -0.005)
        DueLine(kind: DueKind.iOwe, amount: -e.value, name: names[e.key])
      else if (e.value >= 0.005)
        DueLine(kind: DueKind.owedByRoommate, amount: e.value, name: names[e.key]),
  ];
  return stableSorted(lines, (a, b) {
    if (a.kind != b.kind) return a.kind == DueKind.iOwe ? -1 : 1;
    return b.amount.compareTo(a.amount);
  });
}

/// [items] sorted by [compare], equal items keeping their order.
List<T> stableSorted<T>(List<T> items, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
