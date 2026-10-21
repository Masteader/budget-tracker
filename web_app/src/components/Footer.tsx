import React from 'react';
import type { TranslationDictionary } from '../i18n/translations';
import { CONTACT_EMAIL } from '../lib/inquiries';
import { Logo } from './Header';
import { Icon } from './Icon';

interface FooterProps {
  dict: TranslationDictionary;
}

export const Footer: React.FC<FooterProps> = ({ dict }) => (
  <footer className="border-t border-line bg-white">
    <div className="mx-auto flex max-w-6xl flex-col items-center gap-4 px-4 py-8 text-center text-sm text-muted sm:flex-row sm:justify-between sm:px-6 sm:text-start">
      <div className="flex items-center gap-2.5">
        <Logo className="h-7 w-7" />
        <span>
          <bdi dir="ltr">© 2026 Budget Tracker</bdi> · {dict.footer.rights}
        </span>
      </div>
      <nav aria-label={dict.a11y.footerNav} className="flex flex-wrap items-center justify-center gap-x-5 gap-y-2">
        <a href="#privacy" className="hover:text-teal">
          {dict.nav.privacy}
        </a>
        <a href="#faq" className="hover:text-teal">
          {dict.nav.faq}
        </a>
        <a href={`mailto:${CONTACT_EMAIL}`} className="inline-flex items-center gap-1.5 hover:text-teal">
          <Icon name="mail" className="h-4 w-4" />
          {dict.footer.contact}
        </a>
      </nav>
    </div>
  </footer>
);
