// FABLE2-APP-01 / FABLE2-APP-02: the edit sheet writes who paid and for whom
// in the columns the settlement engine reads (spent_by relative to the
// creator, beneficiary_type / beneficiary_id, and a manual row's note tail),
// never the non-existent paid_by / beneficiary columns, and never rewrites an
// attribution the user did not change. Ported from the reviewer's probe
// (fable2/edit_sheet_attribution_probe_test.dart); each case checks the row
// the server would read after the update.
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = 'aaaaaaaa-0000-4000-8000-00000000000a';
const _b = 'bbbbbbbb-0000-4000-8000-00000000000b';
const _c = 'cccccccc-0000-4000-8000-00000000000c';

Map<String, dynamic> _row(Map<String, dynamic> fields) => {
      'id': 'tx-1',
      'household_id': 'h1',
      'amount': 300.0,
      'currency': 'SAR',
      'merchant': 'Dinner',
      'category_code': 'OPEX-DINING',
      'timestamp': '2026-10-20T18:00:00Z',
      'created_at': '2026-10-20T18:00:01Z',
      'user_id': _a,
      ...fields,
    };

HouseholdRoster _roster(List<String> ids, {String? provider, List<String> wives = const []}) => HouseholdRoster(
      householdId: 'h1',
      nafaqahProviderUserId: provider,
      members: [
        for (final id in ids)
          HouseholdMember(userId: id, financialRole: wives.contains(id) ? 'spouse' : (provider == null ? 'peer' : 'family_member')),
      ],
    );

/// Pumps the sheet, optionally taps [taps] (in order), saves and returns the
/// values written plus the row as the server reads it afterwards.
Future<({List<Map<String, dynamic>> writes, Map<String, dynamic> after})> _editAndSave(
  WidgetTester tester,
  Map<String, dynamic> row, {
  String viewer = _a,
  HouseholdRoster? roster,
  List<String> deps = const [],
  List<String> taps = const [],
  String? merchant,
  NafaqahSummary nafaqah = const NafaqahSummary(mode: 'not_family'),
}) async {
  final writes = <Map<String, dynamic>>[];
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: EditTransactionSheet(
          transaction: Transaction.fromMap(row),
          householdDependents: deps,
          nafaqah: nafaqah,
          loadNafaqahFields: (_) async => {'nafaqah_class': null, 'nafaqah_spouse_id': null},
          currentUserId: () => viewer,
          loadRoster: roster == null ? null : (_) async => roster,
          updateRow: (id, values) async => writes.add(Map<String, dynamic>.from(values)),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  if (merchant != null) await tester.enterText(find.byType(TextField).first, merchant);
  for (final label in taps) {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
    await tester.pump();
  }
  await tester.ensureVisible(find.text('Save Changes'));
  await tester.tap(find.text('Save Changes'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (writes: writes, after: {...row, if (writes.isNotEmpty) ...writes.last});
}

void main() {
  void expectNoFakeColumns(List<Map<String, dynamic>> writes) {
    for (final w in writes) {
      expect(w.containsKey('paid_by'), isFalse);
      expect(w.containsKey('beneficiary'), isFalse);
    }
  }

  testWidgets('case 1: a merchant-only edit keeps a manual roommate row paid by another member', (tester) async {
    final row = _row({
      'source': 'manual', 'spent_by': 'both', 'beneficiary_type': 'all_peers', 'beneficiary_id': 'all_peers',
      'raw_sms': 'Manual: Dinner | PaidBy: $_b | Beneficiary: all_peers | SpentBy: both',
    });
    final r = await _editAndSave(tester, row, merchant: 'Dinner at Najd');

    expect(r.writes, hasLength(1), reason: 'one update, no note-only retry');
    expectNoFakeColumns(r.writes);
    expect(r.writes.single['merchant'], 'Dinner at Najd');
    expect(r.writes.single.containsKey('spent_by'), isFalse);
    expect(r.writes.single.containsKey('raw_sms'), isFalse);
    expect(storedPayerRef(r.after), _b, reason: 'B still paid');
    expect(r.after['beneficiary_id'], 'all_peers');
  });

  testWidgets('case 2: a manual personal row (B for B) changed to shared keeps B as payer', (tester) async {
    final row = _row({
      'source': 'manual', 'spent_by': 'me', 'beneficiary_type': 'individual', 'beneficiary_id': _b,
      'raw_sms': 'Manual: Coffee | PaidBy: $_b | Beneficiary: $_b | SpentBy: me',
    });
    final r = await _editAndSave(tester, row, taps: ['Both (Shared)'],
        roster: _roster([_a, _b, _c]));

    expectNoFakeColumns(r.writes);
    final w = r.writes.single;
    expect(w['beneficiary_type'], 'household');
    expect(w['beneficiary_id'], 'household');
    expect(w['spent_by'], 'partner');
    expect(storedPayerRef(r.after), _b);
    final tail = manualTailPattern.firstMatch(w['raw_sms'] as String)!;
    expect(tail.group(1), _b);
    expect(tail.group(2), 'household');
    expect((w['raw_sms'] as String).startsWith('Manual: Coffee | PaidBy:'), isTrue);
  });

  testWidgets('case 3: a legacy chat row edited without touching attribution is still read the same way', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'household', 'beneficiary_id': null,
      'category_code': 'OPEX-GROCERY', 'merchant': 'Panda',
      'raw_sms': 'Chat: Panda | PaidBy: me | Beneficiary: me | Items: [1x Panda (50 SAR)]',
    });
    final r = await _editAndSave(tester, row, merchant: 'Panda Hyper');

    expectNoFakeColumns(r.writes);
    expect(r.writes.single.keys, isNot(contains('raw_sms')), reason: 'tags appended after Items were dropped by the server');
    expect(r.writes.single.keys, isNot(contains('beneficiary_id')));
    expect(storedPayerRef(r.after), 'me');
    expect(legacyAuditTags(r.after['raw_sms'] as String)['beneficiary'], 'me');
  });

  testWidgets('case 3b: confirming the same choices on a legacy row writes them structurally', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_id': null, 'category_code': 'OPEX-GROCERY', 'merchant': 'Panda',
      'raw_sms': 'Chat: Panda | PaidBy: me | Beneficiary: me | Items: [1x Panda (50 SAR)]',
    });
    final r = await _editAndSave(tester, row, taps: ['I Paid', 'Me (Solo)']);

    final w = r.writes.single;
    expect(w['spent_by'], 'me');
    expect(w['beneficiary_type'], 'individual');
    expect(w['beneficiary_id'], _a);
    expect(w.containsKey('raw_sms'), isFalse, reason: 'API rows: attribution lives in the columns only');
  });

  testWidgets('case 4: a structured chat row changed to "partner" updates beneficiary_id', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'individual', 'beneficiary_id': _a,
      'raw_sms': 'Chat: X | PaidBy: me | Beneficiary: me',
    });
    final r = await _editAndSave(tester, row, taps: ['Partner'], roster: _roster([_a, _b]));

    final w = r.writes.single;
    expect(w['spent_by'], 'me');
    expect(w['beneficiary_type'], 'individual');
    expect(w['beneficiary_id'], _b, reason: 'the other member of a two-member household');
  });

  testWidgets('FABLE2-APP-02: a dependent beneficiary saves with a valid spent_by', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'merchant': 'Jarir', 'category_code': 'OPEX-SHOPPING', 'amount': 50.0,
      'raw_sms': 'Chat: Jarir | PaidBy: me | Beneficiary: both | Items: [1x Jarir (50 SAR)]',
    });
    final r = await _editAndSave(tester, row, deps: const ['Sarah'], taps: ['Sarah']);

    expect(r.writes, hasLength(1));
    expectNoFakeColumns(r.writes);
    final w = r.writes.single;
    expect(w['spent_by'], 'me', reason: "spent_by is 'me' | 'partner', never a name (CHECK constraint)");
    expect(w['beneficiary_type'], 'dependent');
    expect(w['beneficiary_id'], 'Sarah');
    expect(find.text('Save Changes'), findsNothing, reason: 'saved and closed');
  });

  testWidgets("the partner editing the creator's row: 'I paid' is stored relative to the creator", (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'household', 'beneficiary_id': 'household',
      'raw_sms': 'Chat: Dinner | PaidBy: me | Beneficiary: both',
    });
    final r = await _editAndSave(tester, row, viewer: _b, taps: ['I Paid'], roster: _roster([_a, _b]));

    final w = r.writes.single;
    expect(w['spent_by'], 'partner', reason: 'B paid, and B is the partner of the creator A');
    expect(w['beneficiary_id'], 'household');
  });

  testWidgets('a third member cannot re-attribute a row whose "partner" is unknown', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'household', 'beneficiary_id': 'household',
      'raw_sms': 'Chat: Dinner | PaidBy: me | Beneficiary: both',
    });
    final r = await _editAndSave(tester, row, viewer: _c, taps: ['The other person paid'], roster: _roster([_a, _b, _c]));

    expect(r.writes, isEmpty);
    expect(find.textContaining('another member recorded this expense'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('family: the husband marking the wife as payer stores her as the creator\'s partner', (tester) async {
    final row = _row({
      'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'household', 'beneficiary_id': 'household',
      'category_code': 'OPEX-GROCERY', 'raw_sms': 'Chat: Panda | PaidBy: me | Beneficiary: both',
    });
    const summary = NafaqahSummary(
      mode: 'family_nafaqah', callerRole: 'husband', callerUserId: _a, husbandId: _a,
      wives: [NafaqahWife(id: _b)],
    );
    final r = await _editAndSave(tester, row, nafaqah: summary, taps: ['My wife paid for the home — I pay her back']);

    final w = r.writes.single;
    expect(w['nafaqah_class'], kWifeReimbursable);
    expect(w['nafaqah_spouse_id'], _b);
    expect(w['spent_by'], 'partner');
    expect(w['beneficiary_type'], 'household');
  });
}
