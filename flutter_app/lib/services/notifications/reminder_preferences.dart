/// Per-type reminder switches, stored on this device (SharedPreferences).
/// All types are on by default; the settings card turns them off.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_planner.dart';

class ReminderPreferences extends ChangeNotifier {
  ReminderPreferences({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  static final ReminderPreferences instance = ReminderPreferences();

  final Future<SharedPreferences> Function() _prefs;
  final Map<ReminderType, bool> _enabled = {for (final t in ReminderType.values) t: true};
  bool _loaded = false;

  static String prefKey(ReminderType type) => 'reminder_${type.name}_enabled';

  bool get isLoaded => _loaded;

  bool isEnabled(ReminderType type) => _enabled[type] ?? true;

  Set<ReminderType> get enabledTypes => {for (final t in ReminderType.values) if (isEnabled(t)) t};

  Future<void> load() async {
    try {
      final p = await _prefs();
      for (final t in ReminderType.values) {
        _enabled[t] = p.getBool(prefKey(t)) ?? true;
      }
    } catch (_) {
      // Preferences unavailable: keep the defaults.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(ReminderType type, bool value) async {
    if (isEnabled(type) == value) return;
    _enabled[type] = value;
    notifyListeners();
    try {
      final p = await _prefs();
      await p.setBool(prefKey(type), value);
    } catch (_) {
      // The in-memory choice still applies for this session.
    }
  }
}
