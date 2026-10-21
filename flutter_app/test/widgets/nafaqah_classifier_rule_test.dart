// Owner rule: only the wife, the Nafaqah provider (husband) or an admin may
// classify a family expense as wife_reimbursable / wife_personal. The selector
// is hidden for every other member (chat confirmation card, receipt review,
// manual sheet, edit sheet), and an admin who is neither spouse names the wife
// who paid.
import 'package:budget_tracker/models/models.dart';
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/screens/home/edit_transaction_sheet.dart';
import 'package:budget_tracker/widgets/chat/pending_expense_confirmation_card.dart';
import 'package:budget_tracker/widgets/nafaqah/nafaqah_class_selector.dart';
import 'package:budget_tracker/widgets/transactions/manual_expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _preview({String role = 'member', List<Map<String, dynamic>>? wives}) => {
      'status': 'preview',
      'merchant': 'Panda',
      'amount': 180.0,
      'category_code': 'OPEX-GROCERY',
      'paid_by': 'me',
      'beneficiary': 'both',
      'available_sub_categories': [
        {'sub_code': 'pantry_staples', 'name_en': 'Pantry Staples', 'name_ar': 'المؤن'},
      ],
      'dependents': <String>[],
      'household_mode': 'family_nafaqah',
      'recorder_role': role,
      'wives': wives ??
          [
            {'id': 'u-wife', 'display_name': 'Umm Fahad'},
          ],
    };

void main() {
  group('NafaqahPreview', () {
    test('a member who is not an admin cannot classify', () {
      final p = NafaqahPreview.fromPreview(_preview());
      expect(p.canClassify, isFalse);
      expect(p.requestFields(kWifeReimbursable), isEmpty);
    });

    test('an admin classifies and names the wife who paid', () {
      final p = NafaqahPreview.fromPreview(_preview()).withAdmin(true);
      expect(p.canClassify, isTrue);
      expect(p.isAdminClassifier, isTrue);
      expect(p.defaultSpouseId, 'u-wife');
      expect(p.requestFields(kWifeReimbursable, chosenWifeId: 'u-wife'), {
        'paid_by': 'partner',
        'beneficiary': 'both',
        'nafaqah_class': kWifeReimbursable,
        'nafaqah_spouse_id': 'u-wife',
      });
      expect(p.requestFields(kWifePersonal, chosenWifeId: 'u-wife')['beneficiary'], 'partner');
      expect(p.requestFields(null), {'nafaqah_class': kNafaqahNone});
      expect(p.transactionColumns(kWifePersonal, chosenWifeId: 'u-wife'),
          {'nafaqah_class': kWifePersonal, 'nafaqah_spouse_id': 'u-wife'});
    });

    test('an admin in a family with several wives must choose one', () {
      final p = NafaqahPreview.fromPreview(_preview(wives: [
        {'id': 'w1'},
        {'id': 'w2'},
      ])).withAdmin(true);
      expect(p.needsWifeChoice, isTrue);
      expect(p.defaultSpouseId, isNull);
    });

    test('the server may say so itself (can_classify), and the summary marks admins', () {
      expect(NafaqahPreview.fromPreview({..._preview(), 'can_classify': true}).canClassify, isTrue);
      final summary = NafaqahSummary.fromMap({
        'mode': 'family_nafaqah',
        'caller_role': 'member',
        'can_set_provider': true,
        'wives': [
          {'id': 'u-wife'},
        ],
      });
      expect(NafaqahPreview.fromSummary(summary).canClassify, isTrue);
    });
  });

  group('chat confirmation card', () {
    Future<List<Object?>> confirm(WidgetTester tester, {required bool isAdmin, String? tap}) async {
      List<Object?> result = const [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PendingExpenseConfirmationCard(
              pendingData: _preview(),
              isAdmin: isAdmin,
              onConfirm: (store, cat, sub, paidBy, beneficiary, cls, spouse) =>
                  result = [paidBy, beneficiary, cls, spouse],
              onCancel: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.ensureVisible(find.text(tap));
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Confirm & Add Expense'));
      await tester.tap(find.text('Confirm & Add Expense'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a family member who is not an admin sees no Nafaqah choice', (tester) async {
      final r = await confirm(tester, isAdmin: false);
      expect(find.byType(NafaqahClassSelector), findsNothing);
      expect(r[2], kNafaqahNone);
    });

    testWidgets('an admin records a wife advance naming her', (tester) async {
      final r = await confirm(tester, isAdmin: true, tap: 'Umm Fahad paid for the home — owed to her');
      expect(r, ['partner', 'both', kWifeReimbursable, 'u-wife']);
    });
  });

  group('manual sheet', () {
    Future<Map<String, dynamic>?> save(WidgetTester tester, {required String role, bool tapShared = false}) async {
      Map<String, dynamic>? saved;
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
                    loadMembers: (_) async => [
                      {'id': 'u-husband', 'financial_role': 'provider', 'role': 'member'},
                      {'id': 'u-wife', 'financial_role': 'spouse', 'role': 'member'},
                      {'id': 'u-son', 'financial_role': 'family_member', 'role': role},
                    ],
                    currentUserId: () => 'u-son',
                    insertRow: (row) async => saved = row,
                    enqueueRow: (_, __) async {},
                    loadNafaqah: (_) async => NafaqahSummary(
                      mode: 'family_nafaqah',
                      callerRole: 'member',
                      callerUserId: 'u-son',
                      husbandId: 'u-husband',
                      canSetProvider: role == 'admin',
                      wives: const [NafaqahWife(id: 'u-wife')],
                    ),
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
      if (tapShared) {
        await tester.ensureVisible(find.byKey(const ValueKey('nafaqah_option_wife_reimbursable')));
        await tester.tap(find.byKey(const ValueKey('nafaqah_option_wife_reimbursable')));
        await tester.pump();
      }
      if (role != 'admin') expect(find.byType(NafaqahClassSelector), findsNothing);
      final saveBtn = find.byIcon(Icons.check_rounded);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('a son who is not an admin records without a class', (tester) async {
      final row = await save(tester, role: 'member');
      expect(row?['nafaqah_class'], isNull);
    });

    testWidgets('an admin son records the wife\'s advance with her member id as payer', (tester) async {
      final row = await save(tester, role: 'admin', tapShared: true);
      expect(row?['nafaqah_class'], kWifeReimbursable);
      expect(row?['nafaqah_spouse_id'], 'u-wife');
      expect(row?['raw_sms'], endsWith('| PaidBy: u-wife | Beneficiary: household | SpentBy: partner'));
    });
  });

  group('edit sheet', () {
    Future<List<Map<String, dynamic>>> edit(WidgetTester tester, {required bool isAdmin, bool tapShared = false}) async {
      final writes = <Map<String, dynamic>>[];
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EditTransactionSheet(
              transaction: Transaction.fromMap({
                'id': 'tx-1', 'household_id': 'h1', 'amount': 90.0, 'merchant': 'Panda', 'category_code': 'OPEX-GROCERY',
                'timestamp': '2026-10-20T10:00:00Z', 'created_at': '2026-10-20T10:00:00Z', 'user_id': 'u-son',
                'source': 'chat', 'spent_by': 'me', 'beneficiary_type': 'household', 'beneficiary_id': 'household',
              }),
              nafaqah: const NafaqahSummary(
                mode: 'family_nafaqah', callerRole: 'member', callerUserId: 'u-son', husbandId: 'u-husband',
                wives: [NafaqahWife(id: 'u-wife')],
              ),
              isAdmin: isAdmin,
              currentUserId: () => 'u-son',
              loadNafaqahFields: (_) async => {'nafaqah_class': null, 'nafaqah_spouse_id': null},
              updateRow: (id, values) async => writes.add(values),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      if (!isAdmin) expect(find.byType(NafaqahClassSelector), findsNothing);
      if (tapShared) {
        await tester.ensureVisible(find.text('The wife paid for the home — owed to her'));
        await tester.tap(find.text('The wife paid for the home — owed to her'));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return writes;
    }

    testWidgets('a member who is not an admin never writes a class', (tester) async {
      final writes = await edit(tester, isAdmin: false);
      expect(writes.single.containsKey('nafaqah_class'), isFalse);
    });

    testWidgets('an admin classifies a wife advance (the son recorded it, the wife paid)', (tester) async {
      final writes = await edit(tester, isAdmin: true, tapShared: true);
      final w = writes.single;
      expect(w['nafaqah_class'], kWifeReimbursable);
      expect(w['nafaqah_spouse_id'], 'u-wife');
      expect(w['beneficiary_type'], 'household');
    });
  });
}
