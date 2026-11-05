import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/api/base_api_client.dart' show ApiRequestException;
import '../services/api/household_roles_api_client.dart' show HouseholdRolesApiException;
import '../models/nafaqah.dart' show NafaqahApiException;
import '../services/household_join.dart' show HouseholdJoinException;

/// What a failure may say in the log: the error's type and its machine code,
/// nothing else. `debugPrint` is not stripped from release builds, and messages
/// are not safe: the schema raises them with balances ('Insufficient funds:
/// balance (%)', 'Reimbursement of % exceeds...') and server detail can carry
/// names or invite codes.
String describeFailure(Object error) => switch (error) {
      PostgrestException e => 'PostgrestException(code: ${e.code})',
      ApiRequestException e => 'ApiRequestException(status: ${e.statusCode}, code: ${e.code})',
      HouseholdRolesApiException e => 'HouseholdRolesApiException(status: ${e.statusCode}, code: ${e.code})',
      NafaqahApiException e => 'NafaqahApiException(code: ${e.code})',
      HouseholdJoinException e => 'HouseholdJoinException(code: ${e.code})',
      _ => error.runtimeType.toString(),
    };

/// Records a failure the user only sees as a friendly message, so it is still
/// visible to whoever debugs it.
void logFailure(String where, Object error) => debugPrint('[$where] failed: ${describeFailure(error)}');
