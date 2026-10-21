import 'package:budget_tracker/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('ur');
  });

  final now = DateTime.utc(2026, 10, 21);

  group('cycle labels by dates (§2.2.1)', () {
    test('English: day + short month, no year inside the current year', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleRange(DateTime.utc(2026, 10, 27), DateTime.utc(2026, 11, 26), now: now), '27 Oct – 26 Nov');
      expect(en.cycleLabel('2026-11', paydayDay: 27, now: now), '27 Oct – 26 Nov');
    });

    test('a cycle crossing into another year shows both years', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleLabel('2027-01', paydayDay: 27, now: now), '27 Dec 2026 – 26 Jan 2027');
    });

    test('a past year shows its year', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleLabel('2025-11', paydayDay: 27, now: now), '27 Oct 2025 – 26 Nov 2025');
    });

    test('Arabic month names with Western digits (app convention)', () {
      final ar = AppLocalizations(const Locale('ar'));
      final label = ar.cycleLabel('2026-11', paydayDay: 27, now: now);
      expect(label, contains('أكتوبر'));
      expect(label, contains('نوفمبر'));
      expect(label, startsWith('27 '));
      expect(label, contains('26 '));
      expect(RegExp('[٠-٩]').hasMatch(label), isFalse);
    });

    test('never a bare month name or YYYY-MM', () {
      final en = AppLocalizations(const Locale('en'));
      final label = en.cycleLabel('2026-11', paydayDay: 27, now: now);
      expect(label, isNot(contains('November')));
      expect(label, isNot(contains('2026-11')));
    });

    test('unparseable keys fall back to the given text', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleLabel('bad', fallback: 'Current cycle'), 'Current cycle');
      expect(en.cycleLabel('bad'), 'bad');
    });

    test('cycleRangeIso reads server ISO dates', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.cycleRangeIso('2026-10-27', '2026-11-26', now: now), '27 Oct – 26 Nov');
      expect(en.cycleRangeIso('', '2026-11-26', fallback: 'x', now: now), 'x');
    });
  });
}
