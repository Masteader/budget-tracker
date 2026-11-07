// Which setup tutor steps and buttons each person sees (display only: the
// roles come from the household's member list the app already loads).
import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/tutor_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

HouseholdMember _m(String id, {bool self = false, bool admin = false, String? financialRole, bool provider = false}) =>
    HouseholdMember(
      userId: id,
      role: admin ? 'admin' : 'member',
      financialRole: financialRole,
      isSelf: self,
      isNafaqahProvider: provider,
    );

HouseholdRoster _family({required List<HouseholdMember> members, String? providerId, bool callerAdmin = false}) =>
    HouseholdRoster(
      householdId: 'h1',
      householdType: kHouseholdTypeFamily,
      callerRole: callerAdmin ? 'admin' : 'member',
      nafaqahProviderUserId: providerId,
      members: members,
    );

List<TutorStepId> _ids(TutorViewer v) => v.steps(hasHousehold: true).map((s) => s.id).toList();

TutorStepSpec _step(TutorViewer v, TutorStepId id, {bool hasHousehold = true}) =>
    v.steps(hasHousehold: hasHousehold).singleWhere((s) => s.id == id);

void main() {
  test('the husband (provider, admin) of a family gets the admin steps and his step', () {
    final v = TutorViewer.from(
      roster: _family(
        callerAdmin: true,
        providerId: 'h',
        members: [_m('h', self: true, admin: true, provider: true), _m('w', financialRole: 'spouse')],
      ),
      fallbackIsAdmin: false,
    );
    expect(v.isAdmin, isTrue);
    expect(v.roleStep, TutorRoleStep.husband);
    expect(_ids(v), [
      TutorStepId.payday,
      TutorStepId.accounts,
      TutorStepId.budgets,
      TutorStepId.living,
      TutorStepId.husband,
      TutorStepId.record,
    ]);
    expect(_step(v, TutorStepId.payday).action, TutorAction.payday);
    expect(_step(v, TutorStepId.payday).secondaryAction, TutorAction.income);
    expect(_step(v, TutorStepId.budgets).action, TutorAction.budgets);
    expect(_step(v, TutorStepId.living).action, TutorAction.roles);
    expect(_step(v, TutorStepId.husband).action, TutorAction.accounts);
  });

  test('the husband step shows before any wife has joined (owner decision D2)', () {
    final v = TutorViewer.from(
      roster: _family(callerAdmin: true, providerId: 'h', members: [_m('h', self: true, admin: true, provider: true)]),
      fallbackIsAdmin: false,
    );
    expect(v.roleStep, TutorRoleStep.husband);
  });

  test('a wife who is not an admin gets no admin action, a note instead, and her step', () {
    final v = TutorViewer.from(
      roster: _family(
        providerId: 'h',
        members: [_m('h', admin: true, provider: true), _m('w', self: true, financialRole: 'spouse')],
      ),
      fallbackIsAdmin: true,
    );
    expect(v.isAdmin, isFalse);
    expect(v.roleStep, TutorRoleStep.wife);
    expect(_ids(v), [
      TutorStepId.payday,
      TutorStepId.accounts,
      TutorStepId.budgets,
      TutorStepId.living,
      TutorStepId.wife,
      TutorStepId.record,
    ]);
    final actions = v.steps(hasHousehold: true).expand((s) => [s.action, s.secondaryAction]).whereType<TutorAction>();
    expect(actions, isNot(contains(TutorAction.payday)));
    expect(actions, isNot(contains(TutorAction.budgets)));
    expect(actions, isNot(contains(TutorAction.roles)));
    expect(_step(v, TutorStepId.payday).action, TutorAction.income);
    expect(_step(v, TutorStepId.budgets).adminSetsNote, isTrue);
    expect(_step(v, TutorStepId.living).adminSetsNote, isTrue);
    expect(_step(v, TutorStepId.wife).action, isNull);
  });

  test('a wife who is an admin gets the admin steps and her step', () {
    final v = TutorViewer.from(
      roster: _family(
        callerAdmin: true,
        providerId: 'h',
        members: [_m('h', admin: true, provider: true), _m('w', self: true, admin: true, financialRole: 'spouse')],
      ),
      fallbackIsAdmin: false,
    );
    expect(v.isAdmin, isTrue);
    expect(v.roleStep, TutorRoleStep.wife);
    expect(_step(v, TutorStepId.payday).action, TutorAction.payday);
  });

  test('a husband who is not an admin gets his step and the member steps', () {
    final v = TutorViewer.from(
      roster: _family(
        providerId: 'h',
        members: [_m('a', admin: true), _m('h', self: true, provider: true), _m('w', financialRole: 'spouse')],
      ),
      fallbackIsAdmin: true,
    );
    expect(v.isAdmin, isFalse);
    expect(v.roleStep, TutorRoleStep.husband);
    expect(_step(v, TutorStepId.payday).action, TutorAction.income);
    expect(_step(v, TutorStepId.budgets).action, isNull);
    expect(_step(v, TutorStepId.husband).action, TutorAction.accounts);
  });

  test('a roommate gets the roommate step', () {
    final v = TutorViewer.from(
      roster: HouseholdRoster(
        householdId: 'h1',
        householdType: kHouseholdTypeRoommates,
        callerRole: 'member',
        members: [_m('a', admin: true, financialRole: 'peer'), _m('b', self: true, financialRole: 'peer')],
      ),
      fallbackIsAdmin: false,
    );
    expect(v.roleStep, TutorRoleStep.roommate);
    expect(_ids(v)[4], TutorStepId.roommate);
    expect(_step(v, TutorStepId.roommate).action, isNull);
  });

  test('another family member who is an admin gets five admin steps and no role step', () {
    final v = TutorViewer.from(
      roster: _family(
        callerAdmin: true,
        providerId: 'h',
        members: [_m('h', admin: true, provider: true), _m('s', self: true, admin: true, financialRole: 'family_member')],
      ),
      fallbackIsAdmin: false,
    );
    expect(v.roleStep, TutorRoleStep.none);
    expect(_ids(v), [TutorStepId.payday, TutorStepId.accounts, TutorStepId.budgets, TutorStepId.living, TutorStepId.record]);
  });

  test('without a roster the role provider decides admin, and there is no role step', () {
    final member = TutorViewer.from(roster: null, fallbackIsAdmin: false);
    expect(member.isAdmin, isFalse);
    expect(member.roleStep, TutorRoleStep.none);
    expect(_step(member, TutorStepId.budgets).action, isNull);

    final admin = TutorViewer.from(roster: null, fallbackIsAdmin: true);
    expect(admin.isAdmin, isTrue);
    expect(_step(admin, TutorStepId.budgets).action, TutorAction.budgets);
  });

  test('without a household, only actions that need none are offered', () {
    final v = TutorViewer.from(roster: null, fallbackIsAdmin: true);
    final actions = v.steps(hasHousehold: false).expand((s) => [s.action, s.secondaryAction]).whereType<TutorAction>();
    expect(actions.toSet(), {TutorAction.budgets});
  });
}
