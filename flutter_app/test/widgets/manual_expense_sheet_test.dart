import 'dart:io';

import 'package:budget_tracker/models/household_membership.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/widgets/nafaqah/nafaqah_class_selector.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _husband = {'id': 'u-husband', 'display_name': 'Abu Fahad', 'financial_role': 'provider'};
const _wife = {'id': 'u-wife', 'display_name': 'Umm Fahad', 'financial_role': 'spouse'};
const _peerA = {'id': 'u-a', 'display_name': 'Majed', 'financial_role': 'peer'};
const _peerB = {'id': 'u-b', 'display_name': 'Salman', 'financial_role': 'peer'};

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    List<Map<String, dynamic>>? members,
    Future<HouseholdRoster> Function(String householdId)? loadRoster,
    Future<List<Map<String, dynamic>>> Function(String householdId)? loadOwnMemberships,
    String currentUser = 'u-husband',
    Future<void> Function(Map<String, dynamic> row)? insertRow,
    Future<void> Function(Map<String, dynamic> row, String householdId)? enqueueRow,
    NafaqahSummary? nafaqah,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ManualExpenseSheet(
                  householdId: 'h1',
                  initialMerchant: 'Panda',
                  initialAmount: 120,
                  loadMembers: members == null ? null : (_) async => members,
                  loadRoster: loadRoster,
                  loadOwnMemberships: loadOwnMemberships,
                  currentUserId: () => currentUser,
                  insertRow: insertRow ?? (_) async {},
                  enqueueRow: enqueueRow ?? (_, __) async {},
                  loadNafaqah: (_) async => nafaqah ?? (throw Exception('offline')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byIcon(Icons.check_rounded);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  // UX-12: amount first (focused, decimal keypad, no "\$" icon) and a date row.
  testWidgets('the amount comes first, is focused and has no dollar icon', (tester) async {
    await openSheet(tester, members: [_peerA, _peerB], currentUser: 'u-a');
    final amount = find.byKey(const ValueKey('manual_amount'));
    final merchant = find.byKey(const ValueKey('manual_merchant'));
    expect(tester.getTopLeft(amount).dy, lessThan(tester.getTopLeft(merchant).dy));
    expect(tester.widget<TextField>(amount).autofocus, isTrue);
    expect(tester.widget<TextField>(amount).keyboardType, const TextInputType.numberWithOptions(decimal: true));
    expect(find.byIcon(Icons.attach_money_rounded), findsNothing);
  });

  testWidgets("yesterday's purchase is booked yesterday", (tester) async {
    Map<String, dynamic>? saved;
    await openSheet(tester, members: [_peerA, _peerB], currentUser: 'u-a', insertRow: (row) async => saved = row);
    await tester.ensureVisible(find.byKey(const ValueKey('expense_date_yesterday')));
    await tester.tap(find.byKey(const ValueKey('expense_date_yesterday')));
    await tester.pump();
    await tapSave(tester);
    final at = DateTime.parse(saved!['timestamp'] as String).toLocal();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect([at.year, at.month, at.day], [yesterday.year, yesterday.month, yesterday.day]);
  });

  testWidgets('without a date choice the expense is booked now', (tester) async {
    Map<String, dynamic>? saved;
    await openSheet(tester, members: [_peerA, _peerB], currentUser: 'u-a', insertRow: (row) async => saved = row);
    await tapSave(tester);
    final at = DateTime.parse(saved!['timestamp'] as String);
    expect(DateTime.now().toUtc().difference(at).inMinutes.abs(), lessThan(2));
  });

  // FR-A-05: a family household (spouse member) never offers the roommate
  // equal split between the spouses.
  testWidgets('family household: Nafaqah choice only, no roommate split toggle', (tester) async {
    await openSheet(tester, members: [_husband, _wife]);

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsNothing);
    expect(find.byType(NafaqahClassSelector), findsOneWidget);
  });

  testWidgets('roommate household keeps the mode toggle and has no Nafaqah choice', (tester) async {
    await openSheet(tester, members: [_peerA, _peerB], currentUser: 'u-a');

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsOneWidget);
    expect(find.byType(NafaqahClassSelector), findsNothing);
  });

  // FR-A-08: a row the database rejects is not reported as "saved offline".
  testWidgets('a database rejection is shown and never queued offline', (tester) async {
    var queued = 0;
    await openSheet(
      tester,
      members: [_husband, _wife],
      insertRow: (_) async => throw const PostgrestException(
        message: 'nafaqah_spouse_id is not a spouse member of household',
        code: '23503',
      ),
      enqueueRow: (_, __) async => queued++,
    );

    await tapSave(tester);

    expect(queued, 0);
    expect(find.byType(ManualExpenseSheet), findsOneWidget, reason: 'the sheet stays open to retry');
    expect(find.textContaining('not a spouse member'), findsOneWidget);
  });

  // FABLE-LOGIC-04: a family without a Nafaqah provider refuses classified
  // expenses; the user is told to ask an admin, nothing is queued.
  testWidgets('a classification refused for a missing provider is explained', (tester) async {
    var queued = 0;
    await openSheet(
      tester,
      members: [_husband, _wife],
      currentUser: 'u-wife',
      insertRow: (_) async => throw const PostgrestException(
        message: 'This family has no Nafaqah provider',
        code: '23514',
        hint: 'no_nafaqah_provider',
      ),
      enqueueRow: (_, __) async => queued++,
    );

    await tapSave(tester);

    expect(queued, 0);
    expect(find.byType(ManualExpenseSheet), findsOneWidget);
    expect(find.textContaining('Ask an admin to choose one'), findsOneWidget);
  });

  testWidgets('a network failure is queued offline with the same row', (tester) async {
    Map<String, dynamic>? queuedRow;
    Map<String, dynamic>? triedRow;
    await openSheet(
      tester,
      members: [_husband, _wife],
      insertRow: (row) async {
        triedRow = row;
        throw const SocketException('offline');
      },
      enqueueRow: (row, _) async => queuedRow = row,
    );

    await tapSave(tester);

    expect(queuedRow, isNotNull);
    expect(queuedRow!['id'], triedRow!['id']);
    expect(find.byType(ManualExpenseSheet), findsNothing);
  });

  // FR-A-07: the family context comes from the household memberships (the
  // Nafaqah summary), not from each member's active household.
  testWidgets("the wife is found even when her active household is another one", (tester) async {
    Map<String, dynamic>? saved;
    await openSheet(
      tester,
      members: [_husband], // users.household_id: the wife is active elsewhere
      nafaqah: const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'husband',
        callerUserId: 'u-husband',
        wives: [NafaqahWife(id: 'u-wife', displayName: 'Umm Fahad')],
      ),
      insertRow: (row) async => saved = row,
    );

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsNothing);
    expect(find.byType(NafaqahClassSelector), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('nafaqah_option_wife_reimbursable')));
    await tester.tap(find.byKey(const ValueKey('nafaqah_option_wife_reimbursable')));
    await tester.pump();
    await tapSave(tester);

    expect(saved?['nafaqah_class'], kWifeReimbursable);
    expect(saved?['nafaqah_spouse_id'], 'u-wife');
  });

  // UX-03: the one Nafaqah question names the spouses.
  testWidgets('the family question names the wife for the husband and the husband for the wife', (tester) async {
    await openSheet(
      tester,
      members: [_husband, _wife],
      nafaqah: const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'husband',
        callerUserId: 'u-husband',
        husbandName: 'Abu Fahad',
        wives: [NafaqahWife(id: 'u-wife', displayName: 'Umm Fahad')],
      ),
    );
    expect(find.text('Umm Fahad paid for the home — I pay her back'), findsOneWidget);
    expect(find.text("Umm Fahad's personal purchase — from her allowance"), findsOneWidget);
  });

  testWidgets('the wife sees her husband by name', (tester) async {
    await openSheet(
      tester,
      members: [_husband, _wife],
      currentUser: 'u-wife',
      nafaqah: const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'wife',
        callerUserId: 'u-wife',
        husbandName: 'Abu Fahad',
        wives: [NafaqahWife(id: 'u-wife', displayName: 'Umm Fahad')],
      ),
    );
    expect(find.text('Abu Fahad paid'), findsOneWidget);
    expect(find.text('For me personally — from my allowance'), findsOneWidget);
  });

  // Roles come from GET /households/{id}/members (the role in THIS household),
  // not users.financial_role filtered by each member's active household.
  group('members and roles per household', () {
    HouseholdMember member(String id, String fin) => HouseholdMember(userId: id, displayName: id, financialRole: fin);

    testWidgets('a wife whose active household is elsewhere is still the wife here', (tester) async {
      await openSheet(
        tester,
        loadRoster: (hid) async => HouseholdRoster(
          householdId: hid,
          members: [member('u-husband', 'provider'), member('u-wife', 'spouse')],
        ),
        loadOwnMemberships: (_) async => fail('the API answered: no fallback'),
      );

      expect(find.byKey(const ValueKey('manual_mode_toggle')), findsNothing);
      expect(find.byType(NafaqahClassSelector), findsOneWidget);
    });

    testWidgets('roommates per household get the split toggle and no Nafaqah choice', (tester) async {
      await openSheet(
        tester,
        currentUser: 'u-a',
        loadRoster: (hid) async => HouseholdRoster(
          householdId: hid,
          members: [member('u-a', 'peer'), member('u-b', 'peer')],
        ),
      );

      expect(find.byKey(const ValueKey('manual_mode_toggle')), findsOneWidget);
      expect(find.byType(NafaqahClassSelector), findsNothing);
      expect(find.text('u-b'), findsOneWidget);
    });

    testWidgets('when the members API fails, only the own membership row is used: no spouse is invented',
        (tester) async {
      var fallbackFor = '';
      await openSheet(
        tester,
        currentUser: 'u-son',
        loadRoster: (_) async => throw Exception('API unavailable'),
        loadOwnMemberships: (hid) async {
          fallbackFor = hid;
          return [
            {'user_id': 'u-son', 'role': 'member', 'financial_role': 'family_member'},
          ];
        },
      );

      expect(fallbackFor, 'h1');
      expect(find.byType(NafaqahClassSelector), findsNothing);
    });

    testWidgets('offline (both loads fail): no spouse, the expense is still recordable', (tester) async {
      Map<String, dynamic>? saved;
      await openSheet(
        tester,
        loadRoster: (_) async => throw Exception('offline'),
        loadOwnMemberships: (_) async => throw Exception('offline'),
        insertRow: (row) async => saved = row,
      );

      expect(find.byType(NafaqahClassSelector), findsNothing);
      await tapSave(tester);
      expect(saved?['nafaqah_class'], isNull);
    });
  });

  testWidgets('another family member (not a spouse) records without a Nafaqah class', (tester) async {
    await openSheet(
      tester,
      members: [_husband, _wife],
      currentUser: 'u-son',
      nafaqah: const NafaqahSummary(
        mode: 'family_nafaqah',
        callerRole: 'member',
        callerUserId: 'u-son',
        wives: [NafaqahWife(id: 'u-wife')],
      ),
    );

    expect(find.byKey(const ValueKey('manual_mode_toggle')), findsNothing);
    expect(find.byType(NafaqahClassSelector), findsNothing);
  });
}
