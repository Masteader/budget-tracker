import 'package:flutter_test/flutter_test.dart';
import 'package:budget_tracker/services/salary_cycle_service.dart';

/// One parity case. Expected values were produced by running
/// `public.get_saudi_cycle_for_timestamp(ts, payday)` from
/// supabase/migrations/20261019080000_bug02_payday_cycle_parity_and_triggers.sql
/// on a local Postgres 16 built from the repository migrations.
class _Case {
  final String timestamptz;
  final int? payday;
  final String key;
  final String start;
  final String end;
  final String note;
  const _Case(this.timestamptz, this.payday, this.key, this.start, this.end, this.note);
}

const _cases = <_Case>[
  _Case('2026-10-28T12:00:00+03:00', 27, '2026-11', '2026-10-27', '2026-11-26', 'brief: Oct 28 -> 2026-11'),
  _Case('2026-12-27T12:00:00+03:00', 27, '2027-01', '2026-12-27', '2027-01-26', 'brief: Dec 27 -> 2027-01'),
  _Case('2026-10-26T12:00:00+03:00', 27, '2026-10', '2026-09-27', '2026-10-26', 'day before payday stays in Oct cycle'),
  _Case('2026-10-27T00:00:00+03:00', 27, '2026-11', '2026-10-27', '2026-11-26', 'payday midnight Riyadh'),
  _Case('2026-10-26T23:59:59+03:00', 27, '2026-10', '2026-09-27', '2026-10-26', 'last second before payday Riyadh'),
  _Case('2026-10-26T21:00:00Z', 27, '2026-11', '2026-10-27', '2026-11-26', 'UTC 21:00 on 26th is already the 27th in Riyadh'),
  _Case('2026-10-26T20:59:59Z', 27, '2026-10', '2026-09-27', '2026-10-26', 'UTC 20:59 on 26th is still the 26th in Riyadh'),
  _Case('2026-10-27T01:00:00+05:00', 27, '2026-10', '2026-09-27', '2026-10-26', 'Pakistan device: 26th 23:00 Riyadh'),
  _Case('2026-10-26T16:30:00-05:00', 27, '2026-11', '2026-10-27', '2026-11-26', 'US device: 27th 00:30 Riyadh'),
  _Case('2026-12-26T21:00:00Z', 27, '2027-01', '2026-12-27', '2027-01-26', 'year rollover in Riyadh'),
  _Case('2026-12-26T20:00:00Z', 27, '2026-12', '2026-11-27', '2026-12-26', 'still 2026-12 cycle'),
  _Case('2027-01-01T10:00:00+03:00', 27, '2027-01', '2026-12-27', '2027-01-26', 'New Year inside 2027-01 cycle'),
  _Case('2027-01-26T10:00:00+03:00', 27, '2027-01', '2026-12-27', '2027-01-26', 'last day of 2027-01 cycle'),
  _Case('2027-02-26T10:00:00+03:00', 27, '2027-02', '2027-01-27', '2027-02-26', 'Feb 26 non-leap'),
  _Case('2027-02-27T10:00:00+03:00', 27, '2027-03', '2027-02-27', '2027-03-26', 'Feb 27 non-leap payday'),
  _Case('2027-02-28T10:00:00+03:00', 27, '2027-03', '2027-02-27', '2027-03-26', 'Feb 28 non-leap'),
  _Case('2027-03-26T10:00:00+03:00', 27, '2027-03', '2027-02-27', '2027-03-26', 'end of 2027-03 cycle'),
  _Case('2028-02-29T10:00:00+03:00', 27, '2028-03', '2028-02-27', '2028-03-26', 'leap day'),
  _Case('2028-02-28T12:00:00+03:00', 30, '2028-02', '2028-01-30', '2028-02-28', 'leap Feb payday 30 clamps to 29: 28th before payday'),
  _Case('2028-02-29T12:00:00+03:00', 30, '2028-03', '2028-02-29', '2028-03-29', 'leap Feb payday 30 clamps to 29: payday'),
  _Case('2027-02-27T12:00:00+03:00', 30, '2027-02', '2027-01-30', '2027-02-27', 'non-leap Feb payday 30 clamps to 28: 27th'),
  _Case('2027-02-28T12:00:00+03:00', 30, '2027-03', '2027-02-28', '2027-03-29', 'non-leap Feb payday 30 clamps to 28: payday'),
  _Case('2027-03-29T12:00:00+03:00', 30, '2027-03', '2027-02-28', '2027-03-29', 'March 29 before payday 30'),
  _Case('2027-03-30T12:00:00+03:00', 30, '2027-04', '2027-03-30', '2027-04-29', 'March 30 payday'),
  _Case('2027-02-28T12:00:00+03:00', 31, '2027-03', '2027-02-28', '2027-03-30', 'payday 31 in Feb clamps to 28'),
  _Case('2027-01-31T12:00:00+03:00', 31, '2027-02', '2027-01-31', '2027-02-27', 'payday 31 in January'),
  _Case('2027-01-30T12:00:00+03:00', 31, '2027-01', '2026-12-31', '2027-01-30', 'day before payday 31 in January'),
  _Case('2027-04-30T12:00:00+03:00', 31, '2027-05', '2027-04-30', '2027-05-30', 'payday 31 in 30-day April clamps to 30'),
  _Case('2027-04-29T12:00:00+03:00', 31, '2027-04', '2027-03-31', '2027-04-29', 'April 29 before clamped payday'),
  _Case('2027-05-01T12:00:00+03:00', 31, '2027-05', '2027-04-30', '2027-05-30', 'May 1 inside cycle started Apr 30'),
  _Case('2027-12-31T12:00:00+03:00', 31, '2028-01', '2027-12-31', '2028-01-30', 'payday 31 December'),
  _Case('2028-01-15T12:00:00+03:00', 31, '2028-01', '2027-12-31', '2028-01-30', 'mid January payday 31'),
  _Case('2027-02-28T12:00:00+03:00', 29, '2027-03', '2027-02-28', '2027-03-28', 'payday 29 non-leap Feb clamps to 28'),
  _Case('2027-03-28T12:00:00+03:00', 29, '2027-03', '2027-02-28', '2027-03-28', 'payday 29 March 28 before payday'),
  _Case('2028-02-29T12:00:00+03:00', 29, '2028-03', '2028-02-29', '2028-03-28', 'payday 29 leap day'),
  _Case('2026-10-15T12:00:00+03:00', 1, '2026-10', '2026-10-01', '2026-10-31', 'payday 1 calendar month'),
  _Case('2026-12-31T23:59:59+03:00', 1, '2026-12', '2026-12-01', '2026-12-31', 'payday 1 last second of year'),
  _Case('2027-02-28T12:00:00+03:00', 1, '2027-02', '2027-02-01', '2027-02-28', 'payday 1 February'),
  _Case('2026-10-12T12:00:00+03:00', 10, '2026-10', '2026-10-10', '2026-11-09', 'payday 10 labels by start month'),
  _Case('2026-10-05T12:00:00+03:00', 10, '2026-09', '2026-09-10', '2026-10-09', 'payday 10 before payday -> previous month'),
  _Case('2027-01-05T12:00:00+03:00', 10, '2026-12', '2026-12-10', '2027-01-09', 'payday 10 January before payday -> previous year'),
  _Case('2026-10-15T12:00:00+03:00', 15, '2026-10', '2026-10-15', '2026-11-14', 'payday 15 boundary labels by start month'),
  _Case('2026-10-16T12:00:00+03:00', 16, '2026-11', '2026-10-16', '2026-11-15', 'payday 16 boundary labels by next month'),
  _Case('2026-12-20T12:00:00+03:00', 16, '2027-01', '2026-12-16', '2027-01-15', 'payday 16 December -> next year label'),
  _Case('2026-10-28T12:00:00+03:00', 25, '2026-11', '2026-10-25', '2026-11-24', 'payday 25'),
  _Case('2026-10-24T12:00:00+03:00', 25, '2026-10', '2026-09-25', '2026-10-24', 'payday 25 before'),
  _Case('2026-10-28T12:00:00+03:00', 0, '2026-10', '2026-10-01', '2026-10-31', 'payday 0 clamps to 1'),
  _Case('2026-10-28T12:00:00+03:00', 45, '2026-10', '2026-09-30', '2026-10-30', 'payday 45 clamps to 31'),
  _Case('2026-10-28T12:00:00+03:00', null, '2026-11', '2026-10-27', '2026-11-26', 'null payday -> 27'),
  _Case('2028-12-31T03:13:00-05:00', 29, '2029-01', '2028-12-29', '2029-01-28', 'random'),
  _Case('2028-05-23T00:22:00+03:00', 1, '2028-05', '2028-05-01', '2028-05-31', 'random'),
  _Case('2028-08-21T08:35:00+05:00', 5, '2028-08', '2028-08-05', '2028-09-04', 'random'),
  _Case('2026-07-21T08:14:00-05:00', 5, '2026-07', '2026-07-05', '2026-08-04', 'random'),
  _Case('2027-07-30T10:01:00+01:00', 31, '2027-07', '2027-06-30', '2027-07-30', 'random'),
  _Case('2028-05-27T05:36:00Z', 26, '2028-06', '2028-05-26', '2028-06-25', 'random'),
  _Case('2026-10-13T00:49:00+05:00', 26, '2026-10', '2026-09-26', '2026-10-25', 'random'),
  _Case('2029-10-23T08:34:00+05:00', 26, '2029-10', '2029-09-26', '2029-10-25', 'random'),
  _Case('2028-10-04T21:44:00+03:00', 28, '2028-10', '2028-09-28', '2028-10-27', 'random'),
  _Case('2029-02-08T23:13:00-05:00', 1, '2029-02', '2029-02-01', '2029-02-28', 'random'),
  _Case('2028-05-19T07:02:00+01:00', 16, '2028-06', '2028-05-16', '2028-06-15', 'random'),
  _Case('2029-12-23T08:06:00+05:00', 1, '2029-12', '2029-12-01', '2029-12-31', 'random'),
  _Case('2029-11-06T18:36:00+05:00', 29, '2029-11', '2029-10-29', '2029-11-28', 'random'),
  _Case('2026-09-10T06:21:00-05:00', 5, '2026-09', '2026-09-05', '2026-10-04', 'random'),
  _Case('2028-11-06T09:45:00+01:00', 26, '2028-11', '2028-10-26', '2028-11-25', 'random'),
  _Case('2027-05-24T19:24:00+05:00', 1, '2027-05', '2027-05-01', '2027-05-31', 'random'),
  _Case('2028-01-18T20:54:00+05:00', 29, '2028-01', '2027-12-29', '2028-01-28', 'random'),
  _Case('2029-03-23T23:33:00Z', 27, '2029-03', '2029-02-27', '2029-03-26', 'random'),
  _Case('2029-05-15T06:36:00+05:00', 16, '2029-05', '2029-04-16', '2029-05-15', 'random'),
  _Case('2028-04-03T00:22:00+03:00', 5, '2028-03', '2028-03-05', '2028-04-04', 'random'),
  _Case('2028-05-26T08:14:00+03:00', 16, '2028-06', '2028-05-16', '2028-06-15', 'random'),
  _Case('2028-12-18T05:12:00+03:00', 28, '2028-12', '2028-11-28', '2028-12-27', 'random'),
  _Case('2026-08-04T20:51:00+03:00', 30, '2026-08', '2026-07-30', '2026-08-29', 'random'),
  _Case('2028-05-25T01:01:00+05:00', 5, '2028-05', '2028-05-05', '2028-06-04', 'random'),
  _Case('2026-02-28T21:01:00Z', 27, '2026-03', '2026-02-27', '2026-03-26', 'random'),
  _Case('2029-11-23T21:09:00Z', 29, '2029-11', '2029-10-29', '2029-11-28', 'random'),
  _Case('2029-09-14T19:48:00+05:00', 29, '2029-09', '2029-08-29', '2029-09-28', 'random'),
  _Case('2029-05-30T05:28:00+03:00', 26, '2029-06', '2029-05-26', '2029-06-25', 'random'),
  _Case('2027-08-27T05:21:00+01:00', 30, '2027-08', '2027-07-30', '2027-08-29', 'random'),
  _Case('2028-10-30T20:06:00Z', 15, '2028-10', '2028-10-15', '2028-11-14', 'random'),
  _Case('2026-10-17T07:12:00+05:00', 26, '2026-10', '2026-09-26', '2026-10-25', 'random'),
  _Case('2027-03-08T16:59:00+03:00', 30, '2027-03', '2027-02-28', '2027-03-29', 'random'),
  _Case('2026-07-16T18:07:00Z', 25, '2026-07', '2026-06-25', '2026-07-24', 'random'),
  _Case('2026-01-22T03:28:00+01:00', 15, '2026-01', '2026-01-15', '2026-02-14', 'random'),
  _Case('2029-05-30T13:31:00Z', 25, '2029-06', '2029-05-25', '2029-06-24', 'random'),
  _Case('2029-10-23T06:19:00+01:00', 30, '2029-10', '2029-09-30', '2029-10-29', 'random'),
  _Case('2028-03-09T11:30:00+01:00', 25, '2028-03', '2028-02-25', '2028-03-24', 'random'),
  _Case('2028-12-21T09:29:00+01:00', 15, '2028-12', '2028-12-15', '2029-01-14', 'random'),
  _Case('2027-01-22T18:20:00+03:00', 5, '2027-01', '2027-01-05', '2027-02-04', 'random'),
  _Case('2028-01-26T23:22:00-05:00', 26, '2028-02', '2028-01-26', '2028-02-25', 'random'),
  _Case('2029-09-05T06:57:00-05:00', 26, '2029-09', '2029-08-26', '2029-09-25', 'random'),
  _Case('2028-01-07T22:03:00Z', 26, '2028-01', '2027-12-26', '2028-01-25', 'random'),
  _Case('2028-08-26T11:16:00Z', 16, '2028-09', '2028-08-16', '2028-09-15', 'random'),
  _Case('2028-09-19T13:06:00+03:00', 31, '2028-09', '2028-08-31', '2028-09-29', 'random'),
  _Case('2027-12-21T14:01:00-05:00', 25, '2027-12', '2027-11-25', '2027-12-24', 'random'),
  _Case('2026-09-19T08:10:00+01:00', 5, '2026-09', '2026-09-05', '2026-10-04', 'random'),
  _Case('2028-12-24T15:56:00+01:00', 30, '2028-12', '2028-11-30', '2028-12-29', 'random'),
  _Case('2029-10-01T00:42:00+05:00', 25, '2029-10', '2029-09-25', '2029-10-24', 'random'),
  _Case('2028-07-30T03:01:00+03:00', 27, '2028-08', '2028-07-27', '2028-08-26', 'random'),
  _Case('2028-06-22T21:08:00-05:00', 31, '2028-06', '2028-05-31', '2028-06-29', 'random'),
  _Case('2026-11-01T22:17:00+01:00', 1, '2026-11', '2026-11-01', '2026-11-30', 'random'),
  _Case('2027-04-14T13:26:00+01:00', 5, '2027-04', '2027-04-05', '2027-05-04', 'random'),
  _Case('2027-08-11T21:30:00+01:00', 15, '2027-07', '2027-07-15', '2027-08-14', 'random'),
  _Case('2027-10-18T13:20:00+01:00', 16, '2027-11', '2027-10-16', '2027-11-15', 'random'),
  _Case('2029-05-25T08:46:00Z', 16, '2029-06', '2029-05-16', '2029-06-15', 'random'),
  _Case('2026-01-02T02:35:00+03:00', 27, '2026-01', '2025-12-27', '2026-01-26', 'random'),
  _Case('2026-08-26T06:46:00+01:00', 16, '2026-09', '2026-08-16', '2026-09-15', 'random'),
  _Case('2028-11-04T03:45:00+01:00', 27, '2028-11', '2028-10-27', '2028-11-26', 'random'),
  _Case('2029-01-09T06:33:00+03:00', 31, '2029-01', '2028-12-31', '2029-01-30', 'random'),
  _Case('2029-05-08T04:33:00-05:00', 25, '2029-05', '2029-04-25', '2029-05-24', 'random'),
];

void main() {
  group('MOB-13 SalaryCycleService parity with get_saudi_cycle_for_timestamp', () {
    for (final c in _cases) {
      test('${c.timestamptz} payday=${c.payday} -> ${c.key} (${c.note})', () {
        final cycle = SalaryCycleService.cycleForInstant(
          DateTime.parse(c.timestamptz),
          paydayDay: SalaryCycleService.normalizePayday(c.payday),
        );
        expect(cycle.key, c.key);
        expect(cycle.startIso, c.start);
        expect(cycle.endIso, c.end);
      });
    }
  });

  group('MOB-13 cycle invariants for every day 2026-2030', () {
    for (final payday in [1, 5, 15, 16, 25, 27, 28, 29, 30, 31]) {
      test('payday $payday: cycles tile the calendar without gaps and keys advance monthly', () {
        var day = DateTime.utc(2026, 1, 1);
        SaudiCycle? previous;
        while (day.isBefore(DateTime.utc(2031, 1, 1))) {
          final cycle = SalaryCycleService.cycleForDate(day.year, day.month, day.day, paydayDay: payday);
          expect(cycle.containsDate(day), isTrue, reason: '$day not inside $cycle');
          expect(cycle.lengthInDays, inInclusiveRange(28, 31), reason: '$cycle');
          if (previous != null && previous != cycle) {
            expect(cycle.start, previous.end.add(const Duration(days: 1)), reason: 'gap after $previous');
            final prevMonth = DateTime.utc(
              int.parse(previous.key.substring(0, 4)),
              int.parse(previous.key.substring(5)) + 1,
            );
            expect(cycle.key, '${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}');
          }
          previous = cycle;
          day = day.add(const Duration(days: 1));
        }
      });
    }
  });

  group('SalaryCycleService helpers', () {
    test('riyadhDate ignores the device zone of the instant', () {
      expect(SalaryCycleService.riyadhDate(DateTime.parse('2026-10-26T21:00:00Z')), DateTime.utc(2026, 10, 27));
      expect(SalaryCycleService.riyadhDate(DateTime.parse('2026-10-27T01:00:00+05:00')), DateTime.utc(2026, 10, 26));
    });

    test('default payday is 27 and payday setter clamps', () {
      final saved = SalaryCycleService.paydayDay;
      SalaryCycleService.paydayDay = 99;
      expect(SalaryCycleService.paydayDay, 31);
      SalaryCycleService.paydayDay = saved;
      expect(SalaryCycleService.normalizePayday(null), 27);
    });

    test('cycleKeyForInstant uses the household payday when set', () {
      final saved = SalaryCycleService.paydayDay;
      SalaryCycleService.paydayDay = 25;
      expect(SalaryCycleService.cycleKeyForInstant(DateTime.parse('2026-10-25T12:00:00+03:00')), '2026-11');
      SalaryCycleService.paydayDay = 27;
      expect(SalaryCycleService.cycleKeyForInstant(DateTime.parse('2026-10-25T12:00:00+03:00')), '2026-10');
      SalaryCycleService.paydayDay = saved;
    });

    test('daysUntilNextPayday counts Riyadh days to the next cycle start', () {
      expect(
        SalaryCycleService.daysUntilNextPayday(now: DateTime.parse('2026-10-26T12:00:00+03:00'), paydayDay: 27),
        1,
      );
      expect(
        SalaryCycleService.daysUntilNextPayday(now: DateTime.parse('2026-10-20T12:00:00+03:00'), paydayDay: 27),
        7,
      );
    });

    test('cycleForKey returns the dates of a cycle key for any payday', () {
      final nov = SalaryCycleService.cycleForKey('2026-11', paydayDay: 27)!;
      expect(nov.startIso, '2026-10-27');
      expect(nov.endIso, '2026-11-26');
      final jan = SalaryCycleService.cycleForKey('2027-01', paydayDay: 27)!;
      expect(jan.startIso, '2026-12-27');
      expect(jan.endIso, '2027-01-26');
      final early = SalaryCycleService.cycleForKey('2026-10', paydayDay: 10)!;
      expect(early.startIso, '2026-10-10');
      expect(early.endIso, '2026-11-09');
      final calendar = SalaryCycleService.cycleForKey('2027-02', paydayDay: 1)!;
      expect(calendar.startIso, '2027-02-01');
      expect(calendar.endIso, '2027-02-28');
      expect(SalaryCycleService.cycleForKey('2026-11-01', paydayDay: 27)!.key, '2026-11');
      expect(SalaryCycleService.cycleForKey('bad'), isNull);
      // Round trip over every payday and month of a year.
      for (var payday = 1; payday <= 31; payday++) {
        for (var month = 1; month <= 12; month++) {
          final key = '2027-${month.toString().padLeft(2, '0')}';
          expect(SalaryCycleService.cycleForKey(key, paydayDay: payday)!.key, key, reason: 'payday $payday $key');
        }
      }
    });
  });
}
