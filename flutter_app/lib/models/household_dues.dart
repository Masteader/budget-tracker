/// Who owes whom, from the viewer's point of view, for the dashboard hero
/// (UX-07: "Owed to Sara" in family mode).
library;

import 'nafaqah.dart';

enum DueKind {
  /// Family mode, husband (or admin) viewing: the provider owes this wife.
  owedToWife,

  /// Family mode, the wife viewing: her husband owes her.
  owedToMe,
}

class DueLine {
  final DueKind kind;

  /// The other person's name (the wife), when known.
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
