/// Who paid for an expense and for whom, exactly as the settlement engine
/// reads it (`ai_service/settlement_engine.py`: `transaction_attribution`,
/// `structured_attribution`). `public.transactions` has no `paid_by` or
/// `beneficiary` column:
/// * `spent_by` is the payer relative to the creator (`user_id`): 'me' or
///   'partner' (never 'both' or a name);
/// * `beneficiary_type` / `beneficiary_id` say for whom: 'household'/'household'
///   (everyone), 'individual'/<member id> or 'dependent'/<name>;
/// * a row from the manual sheet (`source` 'manual') carries its payer in the
///   fixed tail of `raw_sms` ("… | PaidBy: <x> | Beneficiary: <y> | SpentBy: <z>"),
///   read right-anchored by the server.
library;

/// Beneficiary ids meaning "the whole household" (server `_SHARED_IDS`).
const Set<String> kSharedBeneficiaryIds = {
  '', 'household', 'all_peers', 'all', 'both', 'shared', 'family', 'everyone',
};

const Set<String> _householdWords = {'us', 'we', 'home', 'house'};
const Set<String> _childrenWords = {'children', 'kids', 'child', 'dependents'};
const Set<String> _relativeTokens = {'me', 'partner', 'wife', 'spouse', 'husband', 'provider'};

/// The manual-row tail the server reads the payer from (server `_MANUAL_TAIL_RE`).
final RegExp manualTailPattern = RegExp(
  r'\|\s*PaidBy:\s*([^|]*?)\s*\|\s*Beneficiary:\s*([^|]*?)\s*\|\s*SpentBy:\s*([^|]*?)\s*$',
  caseSensitive: false,
);

final RegExp _uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

bool isMemberUuid(String value) => _uuidPattern.hasMatch(value.trim());

/// A tail field: no separator or line break can shift the right-anchored match.
String _tailField(String value) => value.replaceAll(RegExp(r'[|\r\n]'), ' ').trim();

/// The `raw_sms` note of a manual row: the human-readable [head] followed by
/// the fixed tail the server reads the payer from.
String manualAuditNote({
  required String head,
  required String payer,
  required String beneficiaryId,
  required String spentBy,
}) =>
    '$head | PaidBy: ${_tailField(payer)} | Beneficiary: ${_tailField(beneficiaryId)} | SpentBy: ${_tailField(spentBy)}';

/// The human-readable part of an existing note: every segment except the
/// attribution tags (`PaidBy`, `Beneficiary`, `SpentBy`, `SubCategory`), so a
/// rebuilt tail is never shadowed by an older one.
String auditNoteHead(String? rawSms, {required String fallback}) {
  final parts = (rawSms ?? '')
      .split('|')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .where((p) => !RegExp(r'^(paidby|beneficiary|spentby|subcategory)\s*:', caseSensitive: false).hasMatch(p))
      .toList();
  return parts.isEmpty ? fallback : parts.join(' | ');
}

/// Structured attribution columns of an expense.
class AttributionColumns {
  final String spentBy;
  final String beneficiaryType;
  final String beneficiaryId;

  const AttributionColumns({required this.spentBy, required this.beneficiaryType, required this.beneficiaryId});

  Map<String, String> toColumns() => {
        'spent_by': spentBy,
        'beneficiary_type': beneficiaryType,
        'beneficiary_id': beneficiaryId,
      };

  @override
  String toString() => 'AttributionColumns($spentBy, $beneficiaryType/$beneficiaryId)';
}

/// `beneficiary_type` / `beneficiary_id` for a beneficiary (server
/// `structured_attribution`): 'both'/'household' and other shared words are
/// the household, 'me' the creator, 'partner' [partnerId] (or the relative
/// token, resolved by the server), 'children' the dependents, a member id an
/// individual, anything else a dependent's name.
({String type, String id}) beneficiaryColumns(String beneficiary, {String? creatorId, String? partnerId}) {
  final raw = beneficiary.trim();
  final ben = raw.toLowerCase();
  if (kSharedBeneficiaryIds.contains(ben) || _householdWords.contains(ben)) {
    return (type: 'household', id: 'household');
  }
  if (ben == 'me') {
    final me = (creatorId ?? '').trim();
    return (type: 'individual', id: me.isEmpty ? 'me' : me.toLowerCase());
  }
  if (_childrenWords.contains(ben)) return (type: 'dependent', id: 'children');
  if (ben == 'partner') {
    final p = (partnerId ?? '').trim();
    return (type: 'individual', id: p.isEmpty ? 'partner' : p.toLowerCase());
  }
  if (_relativeTokens.contains(ben) || isMemberUuid(ben)) return (type: 'individual', id: ben);
  final name = _tailField(raw);
  return (type: 'dependent', id: name.length > 60 ? name.substring(0, 60) : name);
}

/// Structured columns for an expense whose [payer] ('me' | 'partner') and
/// [beneficiary] are relative to the creator.
AttributionColumns attributionColumns({
  required String payer,
  required String beneficiary,
  String? creatorId,
  String? partnerId,
}) {
  final p = payer.trim().toLowerCase();
  if (p != 'me' && p != 'partner') {
    throw ArgumentError.value(payer, 'payer', "must be 'me' or 'partner'");
  }
  final ben = beneficiaryColumns(beneficiary, creatorId: creatorId, partnerId: partnerId);
  return AttributionColumns(spentBy: p, beneficiaryType: ben.type, beneficiaryId: ben.id);
}

/// Tags of a note written before the structured columns: the server-authored
/// segment (last occurrence, before the trailing item summary).
Map<String, String> legacyAuditTags(String? rawSms) {
  var text = rawSms ?? '';
  final cut = text.lastIndexOf(' | Items: [');
  if (cut != -1) text = text.substring(0, cut);
  final tags = <String, String>{};
  for (final part in text.split('|')) {
    final trimmed = part.trim();
    final low = trimmed.toLowerCase();
    for (final tag in const ['paidby', 'beneficiary', 'spentby']) {
      if (low.startsWith('$tag:')) tags[tag] = trimmed.substring(tag.length + 1).trim();
    }
  }
  return tags;
}

/// The stored payer of a non-settlement row as the server reads it: 'me',
/// 'partner' (relative to the creator) or, for a manual roommate row, a
/// member id.
String storedPayerRef(Map<String, dynamic> row) {
  final source = (row['source'] as String? ?? '').trim().toLowerCase();
  final raw = row['raw_sms'] as String? ?? '';
  final spentBy = (row['spent_by'] as String? ?? '').trim().toLowerCase();
  if ((row['beneficiary_id']?.toString() ?? '').trim().isNotEmpty) {
    if (source == 'manual') {
      final tail = manualTailPattern.firstMatch(raw);
      final payer = tail?.group(1)?.trim().toLowerCase() ?? '';
      return payer.isEmpty ? 'me' : payer;
    }
    return spentBy == 'partner' ? 'partner' : 'me';
  }
  var payer = (legacyAuditTags(raw)['paidby'] ?? '').toLowerCase();
  final apiRow = source == 'chat' ||
      source == 'receipt_scan' ||
      raw.trimLeft().startsWith('Chat:') ||
      raw.trimLeft().startsWith('Receipt Scan:');
  if (apiRow && payer.isNotEmpty && payer != 'me' && payer != 'partner') payer = 'me';
  if (payer.isEmpty) payer = (spentBy == 'me' || spentBy == 'partner') ? spentBy : 'me';
  return payer;
}

/// Who 'partner' is for a member, from what the app knows of the household:
/// the other member of a two-member household, or in a family the spouse
/// (the husband and his only wife). Mirrors the server's `counterpart_id`.
class HouseholdRelations {
  final List<String> memberIds;
  final String? husbandId;
  final List<String> wifeIds;

  /// Whether [memberIds] is the complete roster (the two-member rule applies).
  final bool rosterComplete;

  HouseholdRelations({
    List<String> memberIds = const [],
    this.husbandId,
    List<String> wifeIds = const [],
    this.rosterComplete = false,
  })  : memberIds = memberIds.map((m) => m.toLowerCase()).toList(),
        wifeIds = wifeIds.map((w) => w.toLowerCase()).toList();

  bool get isFamily => wifeIds.isNotEmpty;

  /// The member 'partner' names for [member], or null when it names nobody.
  String? counterpartOf(String? member) {
    final me = (member ?? '').toLowerCase();
    if (me.isEmpty) return null;
    if (rosterComplete && memberIds.length == 2 && memberIds.contains(me)) {
      return memberIds.firstWhere((m) => m != me);
    }
    final husband = (husbandId ?? '').toLowerCase();
    if (isFamily && husband.isNotEmpty) {
      if (me == husband && wifeIds.length == 1) return wifeIds.single;
      if (wifeIds.contains(me)) return husband;
    }
    return null;
  }
}
