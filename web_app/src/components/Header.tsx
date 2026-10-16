import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import type { Language, TranslationDictionary } from '../i18n/translations';

interface HeaderProps {
  lang: Language;
  setLanguage: (lang: Language) => void;
  dict: TranslationDictionary;
}

export const Header: React.FC<HeaderProps> = ({ lang, setLanguage, dict }) => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 20);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <header
      className={`fixed top-0 left-0 right-0 z-50 w-full transition-all duration-300 ${
        isScrolled
          ? 'bg-deep-navy/90 backdrop-blur-2xl border-b border-white/20 shadow-2xl py-2.5'
          : 'bg-deep-navy/40 backdrop-blur-xl border-b border-white/15 py-4'
      }`}
    >
      <div className="flex justify-between items-center w-full px-5 lg:px-12 max-w-[1600px] mx-auto">
        {/* Brand Entity Anchor */}
        <a href="#" className="flex items-center gap-3 group">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-electric-teal via-primary-container to-primary flex items-center justify-center text-white shadow-lg shadow-electric-teal/20 group-hover:scale-105 transition-transform duration-300">
            <span className="material-symbols-outlined fill-1 text-[24px]">account_balance</span>
          </div>
          <div className="flex flex-col text-start">
            <div className="flex items-center gap-2">
              <span className="text-xl font-bold tracking-tight text-white group-hover:text-ice-cyan transition-colors">
                {dict.brand.name}
              </span>
              <span className="text-[10px] font-semibold text-electric-teal bg-white/10 px-2 py-0.5 rounded border border-electric-teal/30 uppercase tracking-wider backdrop-blur-sm">
                {dict.brand.sovereignBadge}
              </span>
            </div>
            <span className="text-[11px] text-white/70 font-medium tracking-wide hidden sm:inline">
              {dict.brand.subtagline}
            </span>
          </div>
        </a>

        {/* Minimal Editorial Nav Links */}
        <nav className="hidden xl:flex items-center gap-7 text-sm font-medium">
          <a
            href="#simulator"
            className="text-white hover:text-ice-cyan transition-colors flex flex-col items-center py-1 group"
          >
            <span className="font-semibold">{dict.nav.simulator}</span>
            <span className="text-[9px] text-white/50 group-hover:text-ice-cyan/70 uppercase font-mono tracking-wider">
              {dict.nav.simulatorSub}
            </span>
          </a>
          <a
            href="#metrics"
            className="text-white/80 hover:text-ice-cyan transition-colors flex flex-col items-center py-1 group"
          >
            <span>{dict.nav.telemetry}</span>
            <span className="text-[9px] text-white/50 group-hover:text-ice-cyan/70 uppercase font-mono tracking-wider">
              {dict.nav.telemetrySub}
            </span>
          </a>
          <a
            href="#pillars"
            className="text-white/80 hover:text-ice-cyan transition-colors flex flex-col items-center py-1 group"
          >
            <span>{dict.nav.pillars}</span>
            <span className="text-[9px] text-white/50 group-hover:text-ice-cyan/70 uppercase font-mono tracking-wider">
              {dict.nav.pillarsSub}
            </span>
          </a>
          <a
            href="#security"
            className="text-white/80 hover:text-ice-cyan transition-colors flex flex-col items-center py-1 group"
          >
            <span>{dict.nav.security}</span>
            <span className="text-[9px] text-white/50 group-hover:text-ice-cyan/70 uppercase font-mono tracking-wider">
              {dict.nav.securitySub}
            </span>
          </a>
          <a
            href="#faq"
            className="text-white/80 hover:text-ice-cyan transition-colors flex flex-col items-center py-1 group"
          >
            <span>{dict.nav.faq}</span>
            <span className="text-[9px] text-white/50 group-hover:text-ice-cyan/70 uppercase font-mono tracking-wider">
              {dict.nav.faqSub}
            </span>
          </a>
        </nav>

        {/* Language Switcher & Action Cluster */}
        <div className="flex items-center gap-3">
          {/* Dual Language Toggle Pill */}
          <div className="inline-flex items-center bg-black/40 p-1 rounded-full border border-white/20 backdrop-blur-md shadow-inner relative">
            <button
              onClick={() => setLanguage('en')}
              className={`px-3 py-1 rounded-full text-xs font-bold transition-all duration-200 ${
                lang === 'en'
                  ? 'bg-primary-container text-white shadow-md'
                  : 'text-white/80 hover:text-ice-cyan'
              }`}
            >
              EN
            </button>
            <button
              onClick={() => setLanguage('ar')}
              className={`px-3 py-1 rounded-full text-xs font-bold transition-all duration-200 ${
                lang === 'ar'
                  ? 'bg-primary-container text-white shadow-md'
                  : 'text-white/80 hover:text-ice-cyan'
              }`}
            >
              العربية
            </button>
          </div>

          {/* VIP CTA Button */}
          <a
            href="#early-access"
            className="hidden sm:inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-gradient-to-r from-primary-container via-primary to-secondary text-white text-xs lg:text-sm font-bold shadow-lg shadow-primary/30 hover:shadow-electric-teal/30 hover:-translate-y-0.5 active:scale-95 transition-all border border-white/20"
          >
            <span className="material-symbols-outlined text-[18px] text-electric-teal">bolt</span>
            <span>{dict.nav.vipCta}</span>
          </a>

          {/* Mobile Menu Button */}
          <button
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="xl:hidden p-2 rounded-lg bg-white/10 text-white hover:bg-white/20 transition-colors"
          >
            <span className="material-symbols-outlined text-[22px]">
              {mobileMenuOpen ? 'close' : 'menu'}
            </span>
          </button>
        </div>
      </div>

      {/* Mobile Menu Drawer */}
      <AnimatePresence>
        {mobileMenuOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="xl:hidden bg-deep-navy/95 border-b border-white/20 px-6 py-5 flex flex-col gap-4 text-sm font-semibold"
          >
            <a
              href="#simulator"
              onClick={() => setMobileMenuOpen(false)}
              className="text-white hover:text-ice-cyan py-2 flex items-center justify-between border-b border-white/10"
            >
              <span>{dict.nav.simulator}</span>
              <span className="text-xs text-electric-teal">{dict.nav.simulatorSub}</span>
            </a>
            <a
              href="#metrics"
              onClick={() => setMobileMenuOpen(false)}
              className="text-white hover:text-ice-cyan py-2 flex items-center justify-between border-b border-white/10"
            >
              <span>{dict.nav.telemetry}</span>
              <span className="text-xs text-electric-teal">{dict.nav.telemetrySub}</span>
            </a>
            <a
              href="#pillars"
              onClick={() => setMobileMenuOpen(false)}
              className="text-white hover:text-ice-cyan py-2 flex items-center justify-between border-b border-white/10"
            >
              <span>{dict.nav.pillars}</span>
              <span className="text-xs text-electric-teal">{dict.nav.pillarsSub}</span>
            </a>
            <a
              href="#security"
              onClick={() => setMobileMenuOpen(false)}
              className="text-white hover:text-ice-cyan py-2 flex items-center justify-between border-b border-white/10"
            >
              <span>{dict.nav.security}</span>
              <span className="text-xs text-electric-teal">{dict.nav.securitySub}</span>
            </a>
            <a
              href="#faq"
              onClick={() => setMobileMenuOpen(false)}
              className="text-white hover:text-ice-cyan py-2 flex items-center justify-between border-b border-white/10"
            >
              <span>{dict.nav.faq}</span>
              <span className="text-xs text-electric-teal">{dict.nav.faqSub}</span>
            </a>
            <a
              href="#early-access"
              onClick={() => setMobileMenuOpen(false)}
              className="w-full inline-flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-primary-container via-primary to-secondary text-white font-bold text-sm shadow-lg"
            >
              <span className="material-symbols-outlined text-[18px]">bolt</span>
              <span>{dict.nav.vipCta}</span>
            </a>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
};
