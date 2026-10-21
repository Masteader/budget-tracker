import React from 'react';
import type { Language, TranslationDictionary } from '../i18n/translations';
import { PaydayDemo } from './PaydayDemo';

interface HeroProps {
  dict: TranslationDictionary;
  lang: Language;
}

export const Hero: React.FC<HeroProps> = ({ dict, lang }) => (
  <section
    aria-labelledby="hero-title"
    className="relative overflow-hidden bg-gradient-to-b from-teal-soft via-bg to-bg"
  >
    {/* One soft background shape; purely decorative. */}
    <div
      aria-hidden="true"
      className="pointer-events-none absolute -top-24 end-[-6rem] h-80 w-80 rounded-full bg-teal-mint/40 blur-3xl"
    />
    <div className="relative mx-auto grid max-w-6xl items-center gap-10 px-4 pb-16 pt-12 sm:px-6 md:grid-cols-2 md:pb-24 md:pt-20">
      <div className="text-start">
        <p className="mb-4 inline-block rounded-full border border-line bg-white px-3 py-1 text-xs font-semibold text-teal-dark">
          {dict.hero.badge}
        </p>
        <h1 id="hero-title" className="text-4xl font-bold leading-tight text-ink sm:text-5xl">
          {dict.hero.title}
        </h1>
        <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">{dict.hero.subtitle}</p>
        <div className="mt-8 flex flex-wrap gap-3">
          <a
            href="#early-access"
            className="rounded-xl bg-teal px-6 py-3 font-bold text-white shadow-sm transition-colors hover:bg-teal-dark"
          >
            {dict.hero.ctaPrimary}
          </a>
          <a
            href="#nafaqah"
            className="rounded-xl border border-line bg-white px-6 py-3 font-bold text-ink transition-colors hover:border-teal hover:text-teal"
          >
            {dict.hero.ctaSecondary}
          </a>
        </div>
        <p className="mt-4 text-sm text-muted">{dict.hero.note}</p>
      </div>
      <div className="flex justify-center md:justify-end">
        <div className="w-full max-w-sm motion-safe:animate-float">
          <PaydayDemo dict={dict} lang={lang} />
        </div>
      </div>
    </div>
  </section>
);
