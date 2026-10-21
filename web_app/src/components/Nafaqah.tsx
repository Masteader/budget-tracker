import React from 'react';
import type { NafaqahCase, TranslationDictionary } from '../i18n/translations';
import { formatMoney } from '../lib/format';

interface NafaqahProps {
  dict: TranslationDictionary;
}

const TONES: Record<NafaqahCase['tone'], string> = {
  neutral: 'border-line bg-white',
  debt: 'border-[#f0d9b0] bg-sand-soft',
  allowance: 'border-[#d6dbff] bg-lilac-soft',
};

const RESULT_TONES: Record<NafaqahCase['tone'], string> = {
  neutral: 'text-muted',
  debt: 'text-sand-ink',
  allowance: 'text-lilac-ink',
};

export const Nafaqah: React.FC<NafaqahProps> = ({ dict }) => {
  const t = dict.nafaqah;
  return (
    <section id="nafaqah" aria-labelledby="nafaqah-title" className="border-y border-line bg-white">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 md:py-20">
        <div className="mx-auto max-w-3xl text-center">
          <p className="text-sm font-bold text-teal">{t.badge}</p>
          <h2 id="nafaqah-title" className="mt-2 text-3xl font-bold text-ink sm:text-4xl">
            {t.title}
          </h2>
          <p className="mt-4 leading-relaxed text-muted">{t.intro}</p>
        </div>

        <ol className="mt-10 grid gap-4 lg:grid-cols-3">
          {t.cases.map((item, idx) => (
            <li key={item.who} className={`rounded-2xl border p-6 text-start ${TONES[item.tone]}`}>
              <span
                aria-hidden="true"
                className="mb-3 inline-flex h-8 w-8 items-center justify-center rounded-full bg-ink text-sm font-bold text-white"
              >
                {idx + 1}
              </span>
              <h3 className="text-lg font-bold text-ink">{item.who}</h3>
              <p className={`mt-2 font-medium leading-relaxed ${RESULT_TONES[item.tone]}`}>{item.result}</p>
            </li>
          ))}
        </ol>

        <div className="mx-auto mt-10 max-w-xl rounded-2xl border border-line bg-bg p-5 sm:p-6">
          <table className="w-full text-start text-sm">
            <caption className="mb-3 text-start text-base font-bold text-ink">{t.exampleTitle}</caption>
            <tbody>
              {t.exampleRows.map((row) => (
                <tr key={row.label} className={row.total ? 'border-t-2 border-ink/20' : 'border-t border-line'}>
                  <th
                    scope="row"
                    className={`py-2.5 pe-3 text-start ${row.total ? 'font-bold text-ink' : 'font-normal text-muted'}`}
                  >
                    {row.label}
                  </th>
                  <td
                    className={`whitespace-nowrap py-2.5 text-end font-bold ${
                      row.total ? 'text-sand-ink' : row.negative ? 'text-teal' : 'text-ink'
                    }`}
                  >
                    <bdi>{(row.negative ? '− ' : '') + formatMoney(row.amount, dict.money)}</bdi>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mx-auto mt-4 max-w-xl text-center text-sm leading-relaxed text-muted">{t.footnote}</p>
      </div>
    </section>
  );
};
