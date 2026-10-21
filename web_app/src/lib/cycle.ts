// Salary-cycle arithmetic for the landing page example, matching the app's rule
// (.agents/rules/02): a cycle runs from the household payday to the day before the next
// payday on the Asia/Riyadh calendar; a payday past the month's end is clamped to its last day.

export interface CalendarDate {
  year: number;
  /** 1–12 */
  month: number;
  day: number;
}

export interface CycleInfo {
  start: CalendarDate;
  end: CalendarDate;
  nextPayday: CalendarDate;
  /** Whole days from today until the next payday (at least 1). */
  daysLeft: number;
  /** Days in the cycle. */
  length: number;
  /** Days already elapsed in the cycle, today included. */
  elapsed: number;
}

const DAY_MS = 86_400_000;

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function paydayIn(year: number, month: number, payday: number): CalendarDate {
  // Normalise month overflow (0 → December of the previous year, 13 → January of the next).
  const normalised = new Date(Date.UTC(year, month - 1, 1));
  const y = normalised.getUTCFullYear();
  const m = normalised.getUTCMonth() + 1;
  return { year: y, month: m, day: Math.min(payday, daysInMonth(y, m)) };
}

function toUtc(d: CalendarDate): number {
  return Date.UTC(d.year, d.month - 1, d.day);
}

function fromUtc(ms: number): CalendarDate {
  const d = new Date(ms);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/** Today's date in Riyadh, independent of the visitor's time zone. */
export function riyadhToday(now: Date = new Date()): CalendarDate {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Riyadh',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return { year: get('year'), month: get('month'), day: get('day') };
}

export function cycleFor(today: CalendarDate, payday: number): CycleInfo {
  const thisMonth = paydayIn(today.year, today.month, payday);
  const started = today.day >= thisMonth.day;
  const start = started ? thisMonth : paydayIn(today.year, today.month - 1, payday);
  const nextPayday = started ? paydayIn(today.year, today.month + 1, payday) : thisMonth;
  const t = toUtc(today);
  const next = toUtc(nextPayday);
  return {
    start,
    end: fromUtc(next - DAY_MS),
    nextPayday,
    daysLeft: Math.round((next - t) / DAY_MS),
    length: Math.round((next - toUtc(start)) / DAY_MS),
    elapsed: Math.round((t - toUtc(start)) / DAY_MS) + 1,
  };
}

export function formatDayMonth(d: CalendarDate, locale: string): string {
  return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', timeZone: 'UTC' }).format(
    new Date(toUtc(d)),
  );
}
