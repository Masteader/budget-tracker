import React, { useId, useState } from 'react';
import type { Language, TranslationDictionary } from '../i18n/translations';
import { cycleFor, formatDayMonth, riyadhToday } from '../lib/cycle';
import { formatMoney, plural } from '../lib/format';

interface PaydayDemoProps {
  dict: TranslationDictionary;
  lang: Language;
}

const SAMPLE_BUDGET = 6000;
const DAYS = Array.from({ length: 31 }, (_, i) => i + 1);

/** Illustrative salary-cycle card: real cycle dates for the chosen payday, sample amounts. */
export const PaydayDemo: React.FC<PaydayDemoProps> = ({ dict, lang }) => {
  const [payday, setPayday] = useState(27);
  const [today] = useState(riyadhToday);
  const selectId = useId();
  const t = dict.demo;

  const cycle = cycleFor(today, payday);
  // Sample spending that tracks how far into the cycle we are.
  const spent = Math.round((SAMPLE_BUDGET * 0.93 * cycle.elapsed) / cycle.length / 10) * 10;
  const left = SAMPLE_BUDGET - spent;
  const daily = Math.floor(left / cycle.daysLeft);
  const percentSpent = Math.round((spent / SAMPLE_BUDGET) * 100);
  const range = `${formatDayMonth(cycle.start, dict.money.dateLocale)} – ${formatDayMonth(cycle.end, dict.money.dateLocale)}`;

  return (
    <div className="w-full max-w-sm rounded-3xl border border-line bg-white p-5 shadow-[0_24px_60px_-20px_rgba(0,75,87,0.35)] sm:p-6">
      <div className="mb-4 flex items-center justify-between gap-3">
        <span className="rounded-full bg-teal-soft px-3 py-1 text-xs font-bold text-teal-dark">{t.label}</span>
        <div className="flex items-center gap-2">
          <label htmlFor={selectId} className="text-xs font-medium text-muted">
            {t.paydayLabel}
          </label>
          <select
            id={selectId}
            value={payday}
            onChange={(e) => setPayday(Number(e.target.value))}
            className="rounded-lg border border-line bg-bg px-2 py-1.5 text-sm font-bold text-ink"
          >
            {DAYS.map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div aria-live="polite">
        <p className="text-sm text-muted">{t.daysLeftLabel}</p>
        <p className="mt-1 text-4xl font-bold text-ink">{plural(t.daysLeft, cycle.daysLeft, lang)}</p>
        <p className="mt-1 text-sm text-muted">
          {t.cycleLabel}: <span className="font-medium text-ink">{range}</span>
        </p>

        <div className="mt-5 h-2.5 overflow-hidden rounded-full bg-teal-soft" aria-hidden="true">
          <div className="h-full rounded-full bg-teal" style={{ width: `${percentSpent}%` }} />
        </div>

        <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
          {[
            { label: t.budgetLabel, value: SAMPLE_BUDGET },
            { label: t.spentLabel, value: spent },
            { label: t.leftLabel, value: left },
          ].map((item) => (
            <div key={item.label} className="rounded-xl bg-bg px-1 py-2">
              <dt className="text-[11px] text-muted">{item.label}</dt>
              <dd className="mt-0.5 text-sm font-bold text-ink">{formatMoney(item.value, dict.money)}</dd>
            </div>
          ))}
        </dl>

        <div className="mt-3 flex items-center justify-between gap-2 rounded-xl bg-teal px-4 py-3 text-white">
          <span className="text-xs font-medium">{t.dailyLabel}</span>
          <span className="whitespace-nowrap text-base font-bold">{formatMoney(daily, dict.money)}</span>
        </div>
      </div>

      <p className="mt-3 text-[11px] leading-relaxed text-muted">{t.sample}</p>
    </div>
  );
};
