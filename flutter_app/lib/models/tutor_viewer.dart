/// Which setup tutor steps and buttons the signed-in person sees.
///
/// Display only: it reads the roles the app already loads (the household's
/// member list, else the cached admin flag) and decides nothing the server
/// checks. An action a person may not take is simply not offered.
library;

import 'household_membership.dart';

/// What a setup tutor step's button opens.
enum TutorAction {
  /// The household's payday editor (admins).
  payday,

  /// **Record Income**.
  income,

  /// **Accounts & Balances**.
  accounts,

  /// The Budgets screen (admins).
  budgets,

  /// **Members & Admins** (admins).
  roles,
}

/// Whether [action] opens a screen that needs the household's id.
bool tutorActionNeedsHousehold(TutorAction action) => action != TutorAction.budgets;

/// The extra step for the person's role in the household.
enum TutorRoleStep { none, wife, husband, roommate }

/// The tutor's steps, in order.
enum TutorStepId { payday, accounts, budgets, living, wife, husband, roommate, record }

class TutorStepSpec {
  final TutorStepId id;

  /// The main button; null for none.
  final TutorAction? action;

  /// A second button under the main one; null for none.
  final TutorAction? secondaryAction;

  /// "Your household's admin sets this up" in place of an admin-only button.
  final bool adminSetsNote;

  const TutorStepSpec(this.id, {this.action, this.secondaryAction, this.adminSetsNote = false});
}

class TutorViewer {
  final bool isAdmin;
  final TutorRoleStep roleStep;

  const TutorViewer({required this.isAdmin, this.roleStep = TutorRoleStep.none});

  /// From the household's member list; without one, [fallbackIsAdmin] (the
  /// cached role) decides and there is no role step.
  factory TutorViewer.from({HouseholdRoster? roster, required bool fallbackIsAdmin}) {
    if (roster == null) return TutorViewer(isAdmin: fallbackIsAdmin);
    return TutorViewer(isAdmin: roster.callerIsAdmin, roleStep: _roleStepOf(roster));
  }

  static TutorRoleStep _roleStepOf(HouseholdRoster roster) {
    if (roster.effectiveHouseholdType == kHouseholdTypeRoommates) return TutorRoleStep.roommate;
    final self = roster.members.where((m) => m.isSelf).firstOrNull;
    if (self == null) return TutorRoleStep.none;
    if (self.isSpouse) return TutorRoleStep.wife;
    if (roster.nafaqahProvider?.isSelf ?? false) return TutorRoleStep.husband;
    return TutorRoleStep.none;
  }

  /// The steps, with only the buttons that can open: those that need the
  /// household are left out when [hasHousehold] is false.
  List<TutorStepSpec> steps({required bool hasHousehold}) {
    TutorAction? offer(TutorAction a) => hasHousehold || !tutorActionNeedsHousehold(a) ? a : null;
    return [
      isAdmin
          ? TutorStepSpec(TutorStepId.payday, action: offer(TutorAction.payday), secondaryAction: offer(TutorAction.income))
          : TutorStepSpec(TutorStepId.payday, action: offer(TutorAction.income)),
      TutorStepSpec(TutorStepId.accounts, action: offer(TutorAction.accounts)),
      isAdmin
          ? TutorStepSpec(TutorStepId.budgets, action: offer(TutorAction.budgets))
          : const TutorStepSpec(TutorStepId.budgets, adminSetsNote: true),
      isAdmin
          ? TutorStepSpec(TutorStepId.living, action: offer(TutorAction.roles))
          : const TutorStepSpec(TutorStepId.living, adminSetsNote: true),
      if (roleStep == TutorRoleStep.wife) const TutorStepSpec(TutorStepId.wife),
      if (roleStep == TutorRoleStep.husband) TutorStepSpec(TutorStepId.husband, action: offer(TutorAction.accounts)),
      if (roleStep == TutorRoleStep.roommate) const TutorStepSpec(TutorStepId.roommate),
      const TutorStepSpec(TutorStepId.record),
    ];
  }
}
