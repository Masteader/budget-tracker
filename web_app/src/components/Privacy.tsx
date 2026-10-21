import React from 'react';
import type { TranslationDictionary } from '../i18n/translations';
import { Icon } from './Icon';

interface PrivacyProps {
  dict: TranslationDictionary;
}

export const Privacy: React.FC<PrivacyProps> = ({ dict }) => (
  <section id="privacy" aria-labelledby="privacy-title" className="bg-ink text-white">
    <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 md:py-20">
      <div className="mb-10 text-center">
        <h2 id="privacy-title" className="text-3xl font-bold sm:text-4xl">
          {dict.privacy.title}
        </h2>
        <p className="mt-3 text-white/75">{dict.privacy.intro}</p>
      </div>
      <ul className="grid gap-4 sm:grid-cols-2">
        {dict.privacy.items.map((item) => (
          <li key={item.title} className="flex gap-4 rounded-2xl border border-white/15 bg-white/5 p-6 text-start">
            <span className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-white/10 text-teal-mint">
              <Icon name={item.icon} />
            </span>
            <div className="min-w-0">
              <h3 className="text-lg font-bold">{item.title}</h3>
              <p className="mt-1.5 leading-relaxed text-white/80">{item.desc}</p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  </section>
);
