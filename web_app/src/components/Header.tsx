import React from 'react';
import type { Language, TranslationDictionary } from '../i18n/translations';

interface HeaderProps {
  lang: Language;
  setLanguage: (lang: Language) => void;
  dict: TranslationDictionary;
  onOpenAuth?: (tab: 'signin' | 'signup') => void;
}

const LOGO_TICKS =
  'M832.0,530.0L862.0,530.0M830.7,558.9L860.6,561.6M827.0,587.7L856.5,592.9M820.7,615.9L849.7,623.7M812.0,643.6L840.2,653.8M800.9,670.3L828.1,683.0M787.5,696.0L813.5,711.0M772.0,720.4L796.5,737.6M754.3,743.4L777.3,762.7M734.8,764.8L756.0,786.0M713.4,784.3L732.7,807.3M690.4,802.0L707.6,826.5M666.0,817.5L681.0,843.5M640.3,830.9L653.0,858.1M613.6,842.0L623.8,870.2M585.9,850.7L593.7,879.7M557.7,857.0L562.9,886.5M528.9,860.7L531.6,890.6M500.0,862.0L500.0,892.0M471.1,860.7L468.4,890.6M442.3,857.0L437.1,886.5M414.1,850.7L406.3,879.7M386.4,842.0L376.2,870.2M359.7,830.9L347.0,858.1M334.0,817.5L319.0,843.5M309.6,802.0L292.4,826.5M286.6,784.3L267.3,807.3M265.2,764.8L244.0,786.0M245.7,743.4L222.7,762.7M228.0,720.4L203.5,737.6M212.5,696.0L186.5,711.0M199.1,670.3L171.9,683.0M188.0,643.6L159.8,653.8M179.3,615.9L150.3,623.7M173.0,587.7L143.5,592.9M169.3,558.9L139.4,561.6M168.0,530.0L138.0,530.0M169.3,501.1L139.4,498.4M173.0,472.3L143.5,467.1M179.3,444.1L150.3,436.3M188.0,416.4L159.8,406.2M199.1,389.7L171.9,377.0M212.5,364.0L186.5,349.0M228.0,339.6L203.5,322.4M245.7,316.6L222.7,297.3M265.2,295.2L244.0,274.0M286.6,275.7L267.3,252.7M309.6,258.0L292.4,233.5M334.0,242.5L319.0,216.5M359.7,229.1L347.0,201.9M386.4,218.0L376.2,189.8M414.1,209.3L406.3,180.3M442.3,203.0L437.1,173.5M471.1,199.3L468.4,169.4M500.0,198.0L500.0,168.0M528.9,199.3L531.6,169.4M557.7,203.0L562.9,173.5M585.9,209.3L593.7,180.3M613.6,218.0L623.8,189.8M640.3,229.1L653.0,201.9M666.0,242.5L681.0,216.5M690.4,258.0L707.6,233.5M713.4,275.7L732.7,252.7M734.8,295.2L756.0,274.0M754.3,316.6L777.3,297.3M772.0,339.6L796.5,322.4M787.5,364.0L813.5,349.0M800.9,389.7L828.1,377.0M812.0,416.4L840.2,406.2M820.7,444.1L849.7,436.3M827.0,472.3L856.5,467.1M830.7,501.1L860.6,498.4';

export const Logo: React.FC<{ className?: string }> = ({ className = 'w-9 h-9' }) => {
  // The mark appears more than once per page: keep its SVG ids unique.
  const uid = React.useId().replace(/[^a-zA-Z0-9]/g, '');
  const id = (name: string) => `${uid}-${name}`;
  const url = (name: string) => `url(#${id(name)})`;
  return (
    <svg aria-hidden="true" focusable="false" viewBox="126 125 810 810" className={className}>
      <defs>
        <linearGradient id={id('rim')} x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#FFE08A" /><stop offset=".5" stopColor="#F0B132" /><stop offset="1" stopColor="#BE7B14" /></linearGradient>
        <linearGradient id={id('g1')} x1="0" y1="1" x2="1" y2="0"><stop offset="0" stopColor="#F0553F" /><stop offset="1" stopColor="#FF9A6B" /></linearGradient>
        <linearGradient id={id('g2')} x1="1" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#17A7A0" /><stop offset="1" stopColor="#0B6C78" /></linearGradient>
        <linearGradient id={id('g3')} x1="1" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#3D4AA8" /><stop offset="1" stopColor="#232A72" /></linearGradient>
        <linearGradient id={id('g4')} x1="0" y1="1" x2="1" y2="0"><stop offset="0" stopColor="#8E6BE8" /><stop offset="1" stopColor="#B79BFF" /></linearGradient>
        <filter id={id('ws')} x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="16" />
        </filter>
      </defs>
      <circle cx="500" cy="530" r="366" fill={url('rim')} />
      <path d={LOGO_TICKS} stroke="#8F5A0C" strokeOpacity=".6" strokeWidth="7" fill="none" />
      <circle cx="500" cy="530" r="302" fill="#FFF6E0" stroke="#A86C10" strokeWidth="6" />
      <path d="M500.7,538.0L762.4,653.4A286,286 0 0 1 263.0,697.1Z" fill={url('g2')} />
      <path d="M492.2,528.3L245.0,672.2A286,286 0 0 1 324.9,296.4Z" fill={url('g3')} />
      <path d="M499.6,522.0L347.2,280.0A286,286 0 0 1 625.9,265.4Z" fill={url('g4')} />
      <path d="M590.2,497.2L747.3,223.0A316,316 0 0 1 886.8,606.3Z" fill="#3A2003" opacity=".5" filter={url('ws')} transform="translate(-6,16)" />
      <path d="M590.2,497.2L747.3,223.0A316,316 0 0 1 886.8,606.3Z" fill={url('g1')} />
    </svg>
  );
};

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
          <Logo className="h-9 w-9 shrink-0" />
          <span className="flex min-w-0 flex-col leading-tight max-[359px]:hidden">
            <span className="text-sm font-bold text-ink sm:text-base">
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
