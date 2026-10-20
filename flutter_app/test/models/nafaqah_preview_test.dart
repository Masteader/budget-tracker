// External review (Gemini) BLOCKER 5 / HIGH 4: scanned receipts and chat send
// a Nafaqah choice that never contradicts who paid for whom, and name the wife
// when a husband with several wives records what one of them paid.
import 'package:budget_tracker/models/nafaqah.dart';
import 'package:budget_tracker/services/api/base_api_client.dart';
import 'package:budget_tracker/services/api/chat_api_client.dart';
import 'package:budget_tracker/services/api/receipt_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingBase extends BaseApiClient {
  Map<String, dynamic>? body;
  String? path;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool shouldSign = true, Duration timeout = const Duration(seconds: 20), Map<String, String>? extraHeaders}) async {
    this.path = path;
    this.body = body;
    return {'status': 'success'};
  }
}

Map<String, dynamic> _preview({String role = 'wife', String? cls, List<Map<String, dynamic>>? wives, String? spouse}) => {
      'status': 'preview',
      'household_mode': 'family_nafaqah',
      'recorder_role': role,
      'nafaqah_class': cls,
      'nafaqah_spouse_id': spouse,
      'wives': wives ?? [
        {'id': 'wife-1', 'display_name': 'Sara'},
      ],
    };

void main() {
  test('every choice maps to an attribution that classifies back to it', () {
    for (final role in ['wife', 'husband']) {
      for (final cls in [kWifeReimbursable, kWifePersonal, null]) {
        final a = nafaqahAttribution(role, cls);
        expect(classifyNafaqah(role, a.paidBy, a.beneficiary), cls, reason: '$role / $cls');
      }
    }
  });

  test('preview context: wife, husband, roommates', () {
    final wife = NafaqahPreview.fromPreview(_preview(cls: kWifeReimbursable, spouse: 'wife-1'));
    expect(wife.canClassify, isTrue);
    expect(wife.viewerIsWife, isTrue);
    expect(wife.suggestedClass, kWifeReimbursable);
    expect(wife.needsWifeChoice, isFalse);

    final husband = NafaqahPreview.fromPreview(_preview(role: 'husband'));
    expect(husband.defaultSpouseId, 'wife-1');

    expect(NafaqahPreview.fromPreview({'household_mode': 'not_family'}).canClassify, isFalse);
    expect(NafaqahPreview.fromPreview(_preview(role: 'member')).canClassify, isFalse);
    expect(NafaqahPreview.fromPreview(null).canClassify, isFalse);
  });

  test('wife request fields never name a spouse; columns carry her own id', () {
    final p = NafaqahPreview.fromPreview(_preview());
    expect(p.requestFields(kWifePersonal), {'paid_by': 'me', 'beneficiary': 'me', 'nafaqah_class': kWifePersonal});
    expect(p.requestFields(null), {'paid_by': 'partner', 'beneficiary': 'both', 'nafaqah_class': kNafaqahNone});
    expect(p.transactionColumns(kWifeReimbursable, currentUserId: 'wife-1'),
        {'nafaqah_class': kWifeReimbursable, 'nafaqah_spouse_id': 'wife-1'});
    expect(p.transactionColumns(null, currentUserId: 'wife-1'), isEmpty);
  });

  test('husband with several wives: the chosen wife is sent, nothing without a choice', () {
    final p = NafaqahPreview.fromPreview(_preview(role: 'husband', wives: [
      {'id': 'wife-1', 'display_name': 'Sara'},
      {'id': 'wife-2', 'display_name': 'Mona'},
    ]));
    expect(p.needsWifeChoice, isTrue);
    expect(p.defaultSpouseId, isNull);
    expect(p.requestFields(kWifeReimbursable, chosenWifeId: 'wife-2'), {
      'paid_by': 'partner',
      'beneficiary': 'both',
      'nafaqah_class': kWifeReimbursable,
      'nafaqah_spouse_id': 'wife-2',
    });
    expect(p.transactionColumns(kWifeReimbursable), isEmpty);
    expect(p.transactionColumns(kWifePersonal, chosenWifeId: 'wife-2'),
        {'nafaqah_class': kWifePersonal, 'nafaqah_spouse_id': 'wife-2'});
  });

  test('roommates send no Nafaqah fields', () {
    final p = NafaqahPreview.fromPreview({'household_mode': 'not_family', 'nafaqah_class': kWifeReimbursable});
    expect(p.requestFields(kWifeReimbursable), isEmpty);
    expect(p.transactionColumns(kWifeReimbursable, currentUserId: 'x'), isEmpty);
  });

  test('summary context (multi-page scanner) defaults a wife to her shared advance', () {
    final summary = NafaqahSummary.fromMap({
      'mode': 'family_nafaqah',
      'caller_role': 'wife',
      'caller_user_id': 'wife-1',
      'wives': [
        {'id': 'wife-1', 'display_name': 'Sara'},
      ],
    });
    final p = NafaqahPreview.fromSummary(summary);
    expect(p.canClassify, isTrue);
    expect(p.suggestedClass, kWifeReimbursable);
    expect(NafaqahPreview.fromSummary(const NafaqahSummary()).canClassify, isFalse);
  });

  test('receipt client sends paid_by, beneficiary, class and spouse', () async {
    final base = _RecordingBase();
    await ReceiptApiClient(baseClient: base).scanReceipt(
      imagesBase64: const [],
      qrCodeRaw: 'qr',
      householdId: 'hh',
      paidBy: 'partner',
      beneficiary: 'both',
      nafaqahClass: kWifeReimbursable,
      nafaqahSpouseId: 'wife-2',
    );
    expect(base.path, '/agent/scan-receipt');
    expect(base.body, containsPair('paid_by', 'partner'));
    expect(base.body, containsPair('beneficiary', 'both'));
    expect(base.body, containsPair('nafaqah_class', kWifeReimbursable));
    expect(base.body, containsPair('nafaqah_spouse_id', 'wife-2'));
  });

  test('chat client sends the chosen wife', () async {
    final base = _RecordingBase();
    await ChatApiClient(baseClient: base).postChatTransaction(
      message: 'm',
      householdId: 'hh',
      previewOnly: false,
      nafaqahClass: kWifeReimbursable,
      nafaqahSpouseId: 'wife-2',
    );
    expect(base.body, containsPair('nafaqah_spouse_id', 'wife-2'));
  });
}
