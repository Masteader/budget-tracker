import { riyadhToday, cycleFor, formatDayMonth, type CalendarDate, type CycleInfo } from './cycle';

export { riyadhToday, cycleFor, formatDayMonth, type CalendarDate, type CycleInfo };

export function formatSAR(amount: number): string {
  return (
    new Intl.NumberFormat('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amount) + ' ر.س'
  );
}

export function currentCycleKey(payday: number = 27): string {
  const today = riyadhToday();
  const info = cycleFor(today, payday);
  const m = String(info.start.month).padStart(2, '0');
  return `${info.start.year}-${m}`;
}
