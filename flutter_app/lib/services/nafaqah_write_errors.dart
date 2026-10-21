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
}

const String _ledgerHint = 'ledger_would_be_overpaid';
const String _noProviderHint = 'no_nafaqah_provider';

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
    return null;
  }
  if (error is NafaqahApiException) return _fromCode(error.code);
  if (error is Map) {
    if (error['status'] != 'error') return null;
    final detail = error['detail'];
    final code = detail is Map ? detail['code']?.toString() : error['code']?.toString();
    return _fromCode(code);
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
  return null;
}

/// The localized explanation of [refusal].
String nafaqahWriteRefusalText(BuildContext context, NafaqahWriteRefusal refusal) {
  switch (refusal) {
    case NafaqahWriteRefusal.ledgerWouldBeOverpaid:
      return context.tr('nafaqah_err_ledger_overpaid');
    case NafaqahWriteRefusal.noProvider:
      return context.tr('nafaqah_err_no_provider');
  }
}

/// The localized explanation when [error] is a Nafaqah refusal, else null.
String? nafaqahWriteErrorText(BuildContext context, Object? error) {
  final refusal = nafaqahWriteRefusalOf(error);
  return refusal == null ? null : nafaqahWriteRefusalText(context, refusal);
}
