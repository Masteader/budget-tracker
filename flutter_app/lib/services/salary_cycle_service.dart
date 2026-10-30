/// Saudi salary-cycle arithmetic, bit-for-bit compatible with the Postgres
/// function `public.get_saudi_cycle_for_timestamp(timestamptz, int)` that
/// stamps `transactions.cycle_key` and drives the budget triggers.
///
/// Rules (mirrored from the SQL):
/// * The instant is converted to the Asia/Riyadh calendar date (UTC+3, no
///   DST) regardless of the device time zone.
/// * The payday is clamped to 1..31 (null → 27) and, per month, to the last
///   day of that month (payday 30 in February starts on Feb 28/29).
/// * A cycle runs from the payday of month M to the day before the payday of
///   month M+1.
/// * Payday 1 is the plain calendar month.
/// * For payday ≤ 15 the cycle is labelled by the month it starts in; for
///   payday ≥ 16 it is labelled by the following month (27 Oct → '2026-11').
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// A salary cycle: inclusive [start] and [end] calendar dates (UTC-midnight
/// `DateTime`s used purely as dates) and its `YYYY-MM` [key].
class SaudiCycle {
  final String key;
  final DateTime start;
  final DateTime end;

  const SaudiCycle({required this.key, required this.start, required this.end});

  String get startIso => _isoDate(start);
  String get endIso => _isoDate(end);

  /// Number of days in the cycle, inclusive of both ends.
  int get lengthInDays => end.difference(start).inDays + 1;

  bool containsDate(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  bool operator ==(Object other) =>
      other is SaudiCycle && other.key == key && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(key, start, end);

  @override
  String toString() => 'SaudiCycle($key, $startIso..$endIso)';
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _key(int year, int month) => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

class SalaryCycleService {
  SalaryCycleService._();

  /// Saudi Arabia observes UTC+3 all year (no daylight saving time).
  static const Duration riyadhOffset = Duration(hours: 3);
  static const int defaultPaydayDay = 27;

  /// SharedPreferences key the settings screen already uses for the payday.
  static const String paydayPrefKey = 'payday_day';

  /// Last known household payday; updated from the server/settings so that
  /// synchronous callers use the household's real payday, not a hardcoded 27.
  static int _paydayDay = defaultPaydayDay;
  static int get paydayDay => _paydayDay;
  static set paydayDay(int value) {
    _paydayDay = normalizePayday(value);
    paydayListenable.value = _paydayDay;
  }

  /// Notifies when the household payday changes (reminders reschedule).
  static final ValueNotifier<int> paydayListenable = ValueNotifier<int>(defaultPaydayDay);

  /// Loads the cached household payday (written by the payday settings card).
  static Future<int> loadCachedPayday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getInt(paydayPrefKey);
      if (cached != null) paydayDay = cached;
    } catch (_) {
      // Preferences unavailable (tests, first launch): keep the current value.
    }
    return _paydayDay;
  }

  /// Persists and applies a household payday fetched from the server.
  static Future<void> cachePayday(int value) async {
    paydayDay = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(paydayPrefKey, _paydayDay);
    } catch (_) {
      // Non-fatal: the in-memory value is still applied.
    }
  }

  /// `GREATEST(1, LEAST(31, COALESCE(p_payday_day, 27)))`.
  static int normalizePayday(int? payday) => (payday ?? defaultPaydayDay).clamp(1, 31);

  static int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// The Asia/Riyadh calendar date of [instant] (any time zone in, date out).
  static DateTime riyadhDate(DateTime instant) {
    final r = instant.toUtc().add(riyadhOffset);
    return DateTime.utc(r.year, r.month, r.day);
  }

  /// Today's date in Riyadh.
  static DateTime riyadhToday({DateTime? now}) => riyadhDate(now ?? DateTime.now());

  /// Cycle containing [instant] (a point in time, e.g. a transaction timestamp).
  static SaudiCycle cycleForInstant(DateTime instant, {int? paydayDay}) {
    final d = riyadhDate(instant);
    return cycleForDate(d.year, d.month, d.day, paydayDay: paydayDay ?? _paydayDay);
  }

  /// Cycle containing the Riyadh calendar date [year]-[month]-[day]
  /// (use for user-picked dates, which have no time-of-day meaning).
  static SaudiCycle cycleForDate(int year, int month, int day, {int? paydayDay}) {
    final payday = normalizePayday(paydayDay ?? _paydayDay);

    if (payday == 1) {
      return SaudiCycle(
        key: _key(year, month),
        start: DateTime.utc(year, month, 1),
        end: DateTime.utc(year, month, daysInMonth(year, month)),
      );
    }

    final clampedToday = payday < daysInMonth(year, month) ? payday : daysInMonth(year, month);

    if (day >= clampedToday) {
      final nextYear = month == 12 ? year + 1 : year;
      final nextMonth = month == 12 ? 1 : month + 1;
      final nextDays = daysInMonth(nextYear, nextMonth);
      final clampedNext = payday < nextDays ? payday : nextDays;
      return SaudiCycle(
        key: payday <= 15 ? _key(year, month) : _key(nextYear, nextMonth),
        start: DateTime.utc(year, month, clampedToday),
        end: DateTime.utc(nextYear, nextMonth, clampedNext).subtract(const Duration(days: 1)),
      );
    }

    final prevYear = month == 1 ? year - 1 : year;
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevDays = daysInMonth(prevYear, prevMonth);
    final clampedPrev = payday < prevDays ? payday : prevDays;
    return SaudiCycle(
      key: payday <= 15 ? _key(prevYear, prevMonth) : _key(year, month),
      start: DateTime.utc(prevYear, prevMonth, clampedPrev),
      end: DateTime.utc(year, month, clampedToday).subtract(const Duration(days: 1)),
    );
  }

  /// The cycle named by a `YYYY-MM` [cycleKey] (a longer `YYYY-MM-DD` value
  /// uses its month), or null when the key is not in that format.
  static SaudiCycle? cycleForKey(String cycleKey, {int? paydayDay}) {
    final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(cycleKey.trim());
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return null;
    final payday = normalizePayday(paydayDay ?? _paydayDay);
    // payday ≤ 15 names the month the cycle starts in (its payday is in it);
    // payday ≥ 16 names the month it ends in (its 1st is inside the cycle).
    final day = payday <= 15 ? (payday < daysInMonth(year, month) ? payday : daysInMonth(year, month)) : 1;
    return cycleForDate(year, month, day, paydayDay: payday);
  }

  /// `cycle_key` for [instant] (defaults to now).
  static String cycleKeyForInstant(DateTime? instant, {int? paydayDay}) =>
      cycleForInstant(instant ?? DateTime.now(), paydayDay: paydayDay).key;

  /// The current cycle in Riyadh.
  static SaudiCycle currentCycle({DateTime? now, int? paydayDay}) =>
      cycleForInstant(now ?? DateTime.now(), paydayDay: paydayDay);

  /// Whole days from today (Riyadh) until the next cycle starts.
  static int daysUntilNextPayday({DateTime? now, int? paydayDay}) {
    final today = riyadhToday(now: now);
    final cycle = cycleForInstant(now ?? DateTime.now(), paydayDay: paydayDay);
    return cycle.end.difference(today).inDays + 1;
  }

  /// Generates available salary cycles deterministically (default past 6 + current + 1 upcoming).
  /// Merges any extra cycles (e.g. from server or loaded transactions).
  static List<SalaryCycleInfo> getAvailableCycles({
    DateTime? anchorDate,
    int? paydayDay,
    int pastCycles = 6,
    int futureCycles = 1,
    List<SalaryCycleInfo>? serverCycles,
    Iterable<String>? extraCycleKeys,
  }) {
    final today = riyadhToday(now: anchorDate);
    final curCycle = cycleForInstant(today, paydayDay: paydayDay);
    final payday = normalizePayday(paydayDay ?? _paydayDay);

    final Map<String, SalaryCycleInfo> map = {};

    SalaryCycleInfo toInfo(SaudiCycle sc, {required bool isCurrent}) {
      return SalaryCycleInfo(
        cycleKey: sc.key,
        cycleStart: sc.startIso,
        cycleEnd: sc.endIso,
        label: sc.key,
        monthName: sc.key,
        isCurrent: isCurrent,
      );
    }

    // 1. Generate future cycles
    SaudiCycle c = curCycle;
    for (int i = 0; i < futureCycles; i++) {
      final nextDate = c.end.add(const Duration(days: 2));
      c = cycleForInstant(nextDate, paydayDay: payday);
      map[c.key] = toInfo(c, isCurrent: false);
    }

    // 2. Add current cycle
    map[curCycle.key] = toInfo(curCycle, isCurrent: true);

    // 3. Generate past cycles
    c = curCycle;
    for (int i = 0; i < pastCycles; i++) {
      final prevDate = c.start.subtract(const Duration(days: 1));
      c = cycleForInstant(prevDate, paydayDay: payday);
      map[c.key] = toInfo(c, isCurrent: false);
    }

    // 4. Incorporate any extra cycle keys
    if (extraCycleKeys != null) {
      for (final k in extraCycleKeys) {
        if (!map.containsKey(k) && k.isNotEmpty) {
          final sc = cycleForKey(k, paydayDay: payday);
          if (sc != null) {
            map[k] = toInfo(sc, isCurrent: sc.containsDate(today));
          }
        }
      }
    }

    // 5. Merge server cycles if available
    if (serverCycles != null) {
      for (final sc in serverCycles) {
        if (sc.cycleKey.isNotEmpty) {
          final isCurr = sc.cycleKey == curCycle.key || sc.isCurrentCycle;
          map[sc.cycleKey] = SalaryCycleInfo(
            cycleKey: sc.cycleKey,
            cycleStart: sc.cycleStart,
            cycleEnd: sc.cycleEnd,
            label: sc.label,
            monthName: sc.monthName,
            isCurrent: isCurr,
          );
        }
      }
    }

    // Sort descending by cycleStart
    final list = map.values.toList()
      ..sort((a, b) => b.cycleStart.compareTo(a.cycleStart));
    return list;
  }
}
