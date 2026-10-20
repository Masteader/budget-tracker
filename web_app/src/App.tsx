import React, { useState, useEffect } from 'react';
import { MotionConfig } from 'framer-motion';
import { translations, type Language } from './i18n/translations';
import { Header } from './components/Header';
import { Hero } from './components/Hero';
import { Simulator } from './components/Simulator';
import { Metrics } from './components/Metrics';
import { Pillars } from './components/Pillars';
import { SecurityFortress } from './components/SecurityFortress';
import { Faq } from './components/Faq';
import { EarlyAccess } from './components/EarlyAccess';
import { Footer } from './components/Footer';

export const App: React.FC = () => {
  const [lang, setLang] = useState<Language>('ar');

  const dict = translations[lang];

  useEffect(() => {
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.lang = lang;
    document.title = dict.a11y.pageTitle;
  }, [lang, dict]);

  return (
    // reducedMotion="user": framer-motion skips transform/layout animations
    // when the OS "reduce motion" setting is on.
    <MotionConfig reducedMotion="user">
    <div className="min-h-screen bg-[#faf9ff] text-on-surface antialiased flex flex-col selection:bg-primary-container selection:text-white">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:start-3 focus:z-[100] focus:px-4 focus:py-2 focus:rounded-lg focus:bg-white focus:text-[#0c2530] focus:shadow-lg"
      >
        {dict.a11y.skipToContent}
      </a>
      {/* 1. Header with dynamic language switch & nav anchors */}
      <Header lang={lang} setLanguage={setLang} dict={dict} />

      {/* 2. Pristine Glacial Hero with 3D Particles & Telemetry HUD */}
      <Hero dict={dict} />

      {/* 3. Pristine Arctic Content Container */}
      <main id="main-content" tabIndex={-1} className="bg-[#eaf5f7] relative z-20 pt-8 pb-20 border-t border-[#d2ecf0] focus:outline-none">
        {/* Interactive Simulator Cockpit */}
        {/* Keyed by language so the demo inputs (e.g. the AI sample sentence) follow a language switch. */}
        <Simulator key={lang} dict={dict} lang={lang} />

        {/* Live Telemetry Metrics */}
        <Metrics dict={dict} />

        {/* 12 Pillars of Financial Governance */}
        <Pillars dict={dict} />

        {/* Sovereign Privacy Fortress */}
        <SecurityFortress dict={dict} />

        {/* Frequently Asked Questions Accordion */}
        <Faq dict={dict} />

        {/* VIP Early Access Waitlist */}
        <EarlyAccess dict={dict} lang={lang} />
      </main>

      {/* 4. Executive Editorial Footer */}
      <Footer dict={dict} />
    </div>
    </MotionConfig>
  );
};

export default App;
