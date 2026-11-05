// The edit sheet with a row whose creator was deleted. Only an admin can open it.
// It must not say the admin paid, and a save must not rewrite who paid.
import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/models/transaction_attribution.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = 'aaaaaaaa-0000-4000-8000-00000000000a';

Map<String, dynamic> _row(Map<String, dynamic> fields) => {
      'id': 'tx-1',
      'household_id': 'h1',
      'amount': 300.0,
      'currency': 'SAR',
      'merchant': 'Dinner',
      'category_code': 'OPEX-DINING',
      'timestamp': '2026-10-20T18:00:00Z',
      'created_at': '2026-10-20T18:00:01Z',
      'user_id': null,
      'source': 'chat',
      'spent_by': 'me',
      ...fields,
    };

Future<List<Map<String, dynamic>>> _pumpSheet(
  WidgetTester tester,
  Map<String, dynamic> row, {
  String lang = 'en',
  double width = 900,
  double scale = 1.0,
}) async {
  final writes = <Map<String, dynamic>>[];
  await tester.binding.setSurfaceSize(Size(width, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    locale: Locale(lang),
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ur')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: page!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: EditTransactionSheet(
          transaction: Transaction.fromMap(row),
          nafaqah: const NafaqahSummary(mode: 'not_family'),
          loadNafaqahFields: (_) async => {'nafaqah_class': null, 'nafaqah_spouse_id': null},
          currentUserId: () => _admin,
          isAdmin: true,
          loadRoster: (_) async => const HouseholdRoster(
            householdId: 'h1',
            members: [
              HouseholdMember(userId: _admin, displayName: 'Admin', role: 'admin', financialRole: 'peer', isSelf: true),
              HouseholdMember(userId: 'bbbbbbbb-0000-4000-8000-00000000000b', displayName: 'Salem', financialRole: 'peer'),
            ],
          ),
          updateRow: (id, values) async => writes.add(Map<String, dynamic>.from(values)),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return writes;
}

Future<void> _save(WidgetTester tester, String lang) async {
  final save = find.text(AppLocalizations(Locale(lang)).get('save_changes'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final lang in const ['en', 'ar', 'ur']) {
    testWidgets('$lang: says who paid is a deleted member, and offers no "I paid"', (tester) async {
      final l = AppLocalizations(Locale(lang));
      await _pumpSheet(tester, _row({}), lang: lang);

      expect(find.byKey(const ValueKey('edit_tx_deleted_member_payer')), findsOneWidget);
      expect(find.textContaining(l.get('deleted_member')), findsWidgets);
      expect(find.text(l.get('i_paid')), findsNothing);
      expect(find.text(l.get('partner_paid')), findsNothing);
      expect(find.text(l.get('settle_personal_me')), findsNothing);
      expect(find.text(l.get('del_member_row_note')), findsOneWidget);
    });
  }

  testWidgets('a row with a creator still asks who paid', (tester) async {
    final l = AppLocalizations(const Locale('en'));
    await _pumpSheet(tester, _row({'user_id': _admin}));
    expect(find.byKey(const ValueKey('edit_tx_deleted_member_payer')), findsNothing);
    expect(find.text(l.get('i_paid')), findsOneWidget);
    expect(find.text(l.get('del_member_row_note')), findsNothing);
  });

  testWidgets('a merchant-only edit does not touch who paid', (tester) async {
    final writes = await _pumpSheet(tester, _row({}));
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await _save(tester, 'en');

    expect(writes, hasLength(1));
    expect(writes.single['merchant'], 'Renamed');
    expect(writes.single.containsKey('spent_by'), isFalse);
    expect(writes.single.containsKey('user_id'), isFalse);
  });

  testWidgets('changing for whom keeps the stored payer and writes no label into spent_by', (tester) async {
    final l = AppLocalizations(const Locale('en'));
    final writes = await _pumpSheet(tester, _row({'spent_by': 'me'}));
    final both = find.text(l.get('both_shared'));
    await tester.ensureVisible(both);
    await tester.tap(both);
    await tester.pump();
    await _save(tester, 'en');

    expect(writes, hasLength(1));
    expect(writes.single['spent_by'], 'me', reason: 'the CHECK allows only me, partner, both');
    expect(writes.single['beneficiary_type'], 'household');
    expect(writes.single['beneficiary_id'], 'household');
  });

  testWidgets('a manual row keeps the payer it has in the note tail', (tester) async {
    final l = AppLocalizations(const Locale('en'));
    final writes = await _pumpSheet(
      tester,
      _row({
        'source': 'manual',
        'spent_by': 'me',
        'beneficiary_type': 'individual',
        'beneficiary_id': kDeletedMemberRef,
        'notes': 'Manual: Dinner | PaidBy: $kDeletedMemberRef | Beneficiary: $kDeletedMemberRef | SpentBy: me',
      }),
    );
    final both = find.text(l.get('both_shared'));
    await tester.ensureVisible(both);
    await tester.tap(both);
    await tester.pump();
    await _save(tester, 'en');

    expect(writes.single['spent_by'], 'me');
    expect(writes.single['notes'], contains('PaidBy: $kDeletedMemberRef'));
    expect(writes.single['notes'], contains('SpentBy: me'));
  });

  testWidgets('the for-whom choice is the viewer\'s own when they pick "me"', (tester) async {
    final l = AppLocalizations(const Locale('en'));
    final writes = await _pumpSheet(tester, _row({}));
    final me = find.text(l.get('me_solo'));
    await tester.ensureVisible(me);
    await tester.tap(me);
    await tester.pump();
    await _save(tester, 'en');

    expect(writes.single['beneficiary_type'], 'individual');
    expect(writes.single['beneficiary_id'], _admin);
    expect(writes.single['spent_by'], 'me');
  });

  testWidgets('the new row fits at 320px and x2.0 text', (tester) async {
    // It stays inside the screen, and its text wraps instead of clipping. The whole
    // sheet at this size is in edit_transaction_sheet_overflow_test.dart.
    await _pumpSheet(tester, _row({}), lang: 'ar', width: 320, scale: 2.0);
    final payer = find.byKey(const ValueKey('edit_tx_deleted_member_payer'));
    expect(payer, findsOneWidget);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(payer);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    final text = find.descendant(of: payer, matching: find.byType(Text));
    expect(tester.getRect(text).right, lessThanOrEqualTo(rect.right));
  });
}
