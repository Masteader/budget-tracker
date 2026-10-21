import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../l10n/app_localizations.dart';
import '../models/nafaqah.dart';

/// A transaction write the database (or API) refused for a Nafaqah rule.
enum NafaqahWriteRefusal {
  /// Editing/deleting/declassifying a wife advance would leave her ledger
  /// repaid beyond her advances (guard trigger of migration 20261020800000:
  /// SQLSTATE 22023, hint `ledger_would_be_overpaid`; API 409
  /// `ledger_would_be_overpaid`).
  ledgerWouldBeOverpaid,

  /// A wife-paid (classified) expense in a family that has no Nafaqah provider
  /// (SQLSTATE 23514, hint `no_nafaqah_provider`; API 409 `no_provider`).
  noProvider,

  /// Only the wife, the Nafaqah provider (husband) or an admin may classify a
  /// family expense as wife_reimbursable / wife_personal. Recognised by the
  /// codes `not_classifier` / `nafaqah_classifier_only` (API `detail.code` or
  /// PostgREST hint) and by the API's current message "... can classify a
  /// family expense".
  notClassifier,
}

const String _ledgerHint = 'ledger_would_be_overpaid';
const String _noProviderHint = 'no_nafaqah_provider';
const Set<String> _notClassifierCodes = {'not_classifier', 'nafaqah_classifier_only', 'nafaqah_classifier_forbidden'};

bool _isClassifierMessage(String? message) => (message ?? '').toLowerCase().contains('classify a family expense');

/// Which Nafaqah rule refused [error], or null for any other failure
/// (network, permissions, validation). Understands a [PostgrestException]
/// from a direct table write, a [NafaqahApiException], and the error map the
/// API clients return (`status: 'error'`, `detail: {code: ...}`).
NafaqahWriteRefusal? nafaqahWriteRefusalOf(Object? error) {
  if (error is PostgrestException) {
    final hint = error.hint ?? '';
    final message = error.message.toLowerCase();
    if (hint == _ledgerHint || (error.code == '22023' && message.contains('ledger overpaid'))) {
      return NafaqahWriteRefusal.ledgerWouldBeOverpaid;
    }
    if (hint == _noProviderHint) return NafaqahWriteRefusal.noProvider;
    if (_notClassifierCodes.contains(hint) || _isClassifierMessage(error.message)) {
      return NafaqahWriteRefusal.notClassifier;
    }
    return null;
  }
  if (error is NafaqahApiException) {
    return _fromCode(error.code) ?? (_isClassifierMessage(error.message) ? NafaqahWriteRefusal.notClassifier : null);
  }
  if (error is Map) {
    if (error['status'] != 'error') return null;
    final detail = error['detail'];
    final code = detail is Map ? detail['code']?.toString() : error['code']?.toString();
    final message = detail is Map ? detail['message']?.toString() : (detail ?? error['message'])?.toString();
    return _fromCode(code) ?? (_isClassifierMessage(message) ? NafaqahWriteRefusal.notClassifier : null);
  }
  return null;
}

NafaqahWriteRefusal? _fromCode(String? code) {
  switch (code) {
    case _ledgerHint:
      return NafaqahWriteRefusal.ledgerWouldBeOverpaid;
    case 'no_provider':
    case _noProviderHint:
      return NafaqahWriteRefusal.noProvider;
  }
  if (_notClassifierCodes.contains(code)) return NafaqahWriteRefusal.notClassifier;
  return null;
}

/// The localized explanation of [refusal].
String nafaqahWriteRefusalText(BuildContext context, NafaqahWriteRefusal refusal) {
  switch (refusal) {
    case NafaqahWriteRefusal.ledgerWouldBeOverpaid:
      return context.tr('nafaqah_err_ledger_overpaid');
    case NafaqahWriteRefusal.noProvider:
      return context.tr('nafaqah_err_no_provider');
    case NafaqahWriteRefusal.notClassifier:
      return context.tr('nafaqah_err_not_classifier');
  }
}

/// The localized explanation when [error] is a Nafaqah refusal, else null.
String? nafaqahWriteErrorText(BuildContext context, Object? error) {
  final refusal = nafaqahWriteRefusalOf(error);
  return refusal == null ? null : nafaqahWriteRefusalText(context, refusal);
}
