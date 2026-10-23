import React from 'react';
import type { Language, TranslationDictionary } from '../i18n/translations';

interface HeaderProps {
  lang: Language;
  setLanguage: (lang: Language) => void;
  dict: TranslationDictionary;
  onOpenAuth?: (tab: 'signin' | 'signup') => void;
}

export const Logo: React.FC<{ className?: string }> = ({ className = 'w-9 h-9' }) => (
  <svg aria-hidden="true" focusable="false" viewBox="0 0 48 48" className={className}>
    <rect width="48" height="48" rx="12" fill="#006575" />
    <rect x="11" y="14" width="26" height="23" rx="4" fill="none" stroke="#fff" strokeWidth="3" />
    <path d="M11 21h26M18 10v7M30 10v7" stroke="#fff" strokeWidth="3" strokeLinecap="round" />
    <circle cx="24" cy="29" r="3.5" fill="#7fe0d4" />
  </svg>
);

export const Header: React.FC<HeaderProps> = ({ lang, setLanguage, dict, onOpenAuth }) => {
  const other: Language = lang === 'ar' ? 'en' : 'ar';
  const links = [
    { href: '#features', label: dict.nav.features },
    { href: '#nafaqah', label: dict.nav.nafaqah },
    { href: '#privacy', label: dict.nav.privacy },
    { href: '#faq', label: dict.nav.faq },
  ];

  return (
    <header className="sticky top-0 z-50 border-b border-line bg-white/90 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-3 px-4 sm:px-6">
        <a href="#top" className="flex min-w-0 items-center gap-2.5" aria-label={`${dict.brand.name} · ${dict.a11y.home}`}>
          <Logo />
          <span className="flex min-w-0 flex-col leading-tight">
            <span className="font-bold text-ink" lang="en" dir="ltr">
              {dict.brand.name}
            </span>
            <span className="hidden truncate text-xs text-muted sm:block">{dict.brand.tagline}</span>
          </span>
        </a>

        <nav aria-label={dict.a11y.mainNav} className="hidden items-center gap-6 text-sm font-medium md:flex">
          {links.map((link) => (
            <a key={link.href} href={link.href} className="text-muted transition-colors hover:text-teal">
              {link.label}
            </a>
          ))}
        </nav>

        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            lang={other}
            onClick={() => setLanguage(other)}
            aria-label={other === 'en' ? dict.a11y.switchToEnglish : dict.a11y.switchToArabic}
            className="rounded-lg border border-line px-3 py-2 text-sm font-semibold text-ink transition-colors hover:border-teal hover:text-teal"
          >
            {other === 'en' ? 'English' : 'العربية'}
          </button>
          <button
            type="button"
            onClick={() => onOpenAuth?.('signin')}
            className="rounded-lg border border-teal/40 bg-teal/5 px-3.5 py-2 text-sm font-bold text-teal transition-all hover:bg-teal hover:text-white"
          >
            {dict.auth.signIn}
          </button>
          <a
            href="#early-access"
            className="hidden rounded-lg bg-teal px-4 py-2 text-sm font-bold text-white transition-colors hover:bg-teal-dark sm:inline-block"
          >
            {dict.nav.cta}
          </a>
        </div>
      </div>
    </header>
  );
};
