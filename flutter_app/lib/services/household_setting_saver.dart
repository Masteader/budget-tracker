/// Raised when a household setting change was not confirmed by the server.
class HouseholdSettingNotSavedException implements Exception {
  const HouseholdSettingNotSavedException(this.reason);

  final String reason;

  @override
  String toString() => 'HouseholdSettingNotSavedException: $reason';
}

/// Saves a household-wide setting (payday, monthly income, rollover rule)
/// server-first (MOB-27).
///
/// The previous screen code wrote the local cache and in-memory state first
/// and ignored the `false` returned when the API rejected the change, so the
/// user saw "saved" while the device and the database used different values
/// (e.g. different salary-cycle boundaries).
///
/// Here the local side ([applyLocal]) runs only after the server confirmed the
/// change. Otherwise [HouseholdSettingNotSavedException] is thrown and nothing
/// local changes, so the previous value stays in effect everywhere.
Future<void> saveHouseholdSetting<T>({
  required String? householdId,
  required T value,
  required Future<bool> Function(String householdId, T value) saveRemote,
  required Future<void> Function(T value) applyLocal,
}) async {
  if (householdId == null || householdId.isEmpty) {
    throw const HouseholdSettingNotSavedException('no active household');
  }
  final confirmed = await saveRemote(householdId, value);
  if (!confirmed) {
    throw const HouseholdSettingNotSavedException('server did not confirm the change');
  }
  await applyLocal(value);
}
