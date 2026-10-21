import React from 'react';
import type { TranslationDictionary } from '../i18n/translations';
import { Icon } from './Icon';

interface FeaturesProps {
  dict: TranslationDictionary;
}

export const Features: React.FC<FeaturesProps> = ({ dict }) => (
  <section id="features" aria-labelledby="features-title" className="mx-auto max-w-6xl px-4 py-16 sm:px-6 md:py-20">
    <div className="mb-10 text-center">
      <h2 id="features-title" className="text-3xl font-bold text-ink sm:text-4xl">
        {dict.features.title}
      </h2>
      <p className="mt-3 text-muted">{dict.features.subtitle}</p>
    </div>
    <ul className="grid gap-4 sm:grid-cols-2">
      {dict.features.items.map((item) => (
        <li key={item.title} className="rounded-2xl border border-line bg-white p-6 text-start">
          <span className="mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl bg-teal-soft text-teal">
            <Icon name={item.icon} />
          </span>
          <h3 className="text-xl font-bold text-ink">{item.title}</h3>
          <p className="mt-2 leading-relaxed text-muted">{item.desc}</p>
          {item.icon === 'scale' && (
            <a href="#nafaqah" className="mt-3 inline-block font-semibold text-teal underline-offset-4 hover:underline">
              {dict.features.nafaqahLink}
            </a>
          )}
        </li>
      ))}
    </ul>
  </section>
);
