import React from 'react';
import type { TranslationDictionary } from '../i18n/translations';
import { Icon } from './Icon';

interface FaqProps {
  dict: TranslationDictionary;
}

// Native <details>/<summary>: keyboard and screen-reader support without extra script.
export const Faq: React.FC<FaqProps> = ({ dict }) => (
  <section id="faq" aria-labelledby="faq-title" className="mx-auto max-w-3xl px-4 py-16 sm:px-6 md:py-20">
    <h2 id="faq-title" className="mb-8 text-center text-3xl font-bold text-ink sm:text-4xl">
      {dict.faq.title}
    </h2>
    <div className="space-y-3">
      {dict.faq.items.map((item, idx) => (
        <details key={item.q} open={idx === 0} className="group rounded-2xl border border-line bg-white">
          <summary className="flex cursor-pointer items-center justify-between gap-4 rounded-2xl p-5 text-start font-bold text-ink hover:text-teal">
            <span>{item.q}</span>
            <Icon name="chevron" className="h-5 w-5 shrink-0 text-muted transition-transform group-open:rotate-180" />
          </summary>
          <p className="px-5 pb-5 leading-relaxed text-muted">{item.a}</p>
        </details>
      ))}
    </div>
  </section>
);
