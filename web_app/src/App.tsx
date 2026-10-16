import React, { useState, useEffect } from 'react';
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
  }, [lang]);

  return (
    <div className="min-h-screen bg-[#faf9ff] text-on-surface antialiased flex flex-col selection:bg-primary-container selection:text-white">
      {/* 1. Header with dynamic language switch & nav anchors */}
      <Header lang={lang} setLanguage={setLang} dict={dict} />

      {/* 2. Pristine Glacial Hero with 3D Particles & Telemetry HUD */}
      <Hero dict={dict} />

      {/* 3. Pristine Arctic Content Container */}
      <main className="bg-[#eaf5f7] relative z-20 pt-8 pb-20 border-t border-[#d2ecf0]">
        {/* Interactive Simulator Cockpit */}
        <Simulator dict={dict} lang={lang} />

        {/* Live Telemetry Metrics */}
        <Metrics dict={dict} />

        {/* 12 Pillars of Financial Governance */}
        <Pillars dict={dict} />

        {/* Sovereign Privacy Fortress */}
        <SecurityFortress dict={dict} />

        {/* Frequently Asked Questions Accordion */}
        <Faq dict={dict} />

        {/* VIP Early Access Waitlist */}
        <EarlyAccess dict={dict} />
      </main>

      {/* 4. Executive Editorial Footer */}
      <Footer dict={dict} />
    </div>
  );
};

export default App;
