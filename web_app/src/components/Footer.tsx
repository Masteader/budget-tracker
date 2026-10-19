import React from 'react';
import type { TranslationDictionary } from '../i18n/translations';

interface FooterProps {
  dict: TranslationDictionary;
}

export const Footer: React.FC<FooterProps> = ({ dict }) => {
  return (
    <footer className="border-t border-slate-200 bg-[#f1f3ff] text-start">
      <div className="flex flex-col md:flex-row justify-between items-center w-full px-5 lg:px-12 py-12 max-w-[1600px] mx-auto gap-8">
        {/* Brand & Copy */}
        <div className="flex flex-col md:flex-row items-center gap-4 text-center md:text-start">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-primary-container text-white flex items-center justify-center shadow">
              <span aria-hidden="true" className="material-symbols-outlined fill-1 text-[20px]">account_balance</span>
            </div>
            <div>
              <span className="text-base font-bold text-[#0c2530] block">{dict.brand.name}</span>
              <span className="text-[10px] text-slate-400 font-mono uppercase tracking-wider">
                {dict.brand.tagline}
              </span>
            </div>
          </div>
          <p className="text-xs text-slate-500 max-w-md">{dict.footer.rights}</p>
        </div>

        {/* Legal Links */}
        <div className="flex flex-wrap justify-center items-center gap-x-6 gap-y-2 text-xs font-medium text-slate-600">
          {dict.footer.links.map((link, idx) => (
            <a key={idx} href="#" className="hover:text-primary transition-colors">
              {link}
            </a>
          ))}
        </div>

        {/* System Telemetry Status */}
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-white border border-secondary/30 text-xs text-secondary font-mono shadow-sm">
          <span className="w-2 h-2 rounded-full bg-secondary animate-pulse" />
          <span>{dict.footer.status}</span>
        </div>
      </div>
    </footer>
  );
};
