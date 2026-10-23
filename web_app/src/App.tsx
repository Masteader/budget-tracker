import React, { useEffect, useState } from 'react';
import { translations, type Language } from './i18n/translations';
import { useAuth } from './context/useAuth';
import { Header } from './components/Header';
import { Hero } from './components/Hero';
import { Features } from './components/Features';
import { Nafaqah } from './components/Nafaqah';
import { Privacy } from './components/Privacy';
import { Faq } from './components/Faq';
import { EarlyAccess } from './components/EarlyAccess';
import { Footer } from './components/Footer';
import { AuthModal } from './components/auth/AuthModal';
import { PortalShell } from './components/portal/PortalShell';

/** Arabic by default; `?lang=en` opens the English page (handy for sharing). */
function initialLanguage(): Language {
  try {
    return new URLSearchParams(window.location.search).get('lang') === 'en' ? 'en' : 'ar';
  } catch {
    return 'ar';
  }
}

export const App: React.FC = () => {
  const { session } = useAuth();
  const [lang, setLang] = useState<Language>(initialLanguage);
  const [authModalOpen, setAuthModalOpen] = useState(false);
  const [authInitialTab, setAuthInitialTab] = useState<'signin' | 'signup'>('signin');
  const dict = translations[lang];

  useEffect(() => {
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.lang = lang;
    document.title = dict.a11y.pageTitle;
  }, [lang, dict]);

  const handleOpenAuth = (tab: 'signin' | 'signup') => {
    setAuthInitialTab(tab);
    setAuthModalOpen(true);
  };

  // Authenticated state: render account portal
  if (session) {
    return <PortalShell lang={lang} setLanguage={setLang} dict={dict} />;
  }

  // Unauthenticated state: render landing page
  return (
    <div id="top" className="flex min-h-screen flex-col font-sans">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:start-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-white focus:px-4 focus:py-2 focus:text-ink focus:shadow-lg"
      >
        {dict.a11y.skipToContent}
      </a>
      <Header
        lang={lang}
        setLanguage={setLang}
        dict={dict}
        onOpenAuth={handleOpenAuth}
      />
      <main id="main-content" tabIndex={-1} className="flex-1 focus:outline-none">
        <Hero dict={dict} lang={lang} />
        <Features dict={dict} />
        <Nafaqah dict={dict} />
        <Privacy dict={dict} />
        <Faq dict={dict} />
        <EarlyAccess dict={dict} lang={lang} />
      </main>
      <Footer dict={dict} />

      <AuthModal
        isOpen={authModalOpen}
        onClose={() => setAuthModalOpen(false)}
        initialTab={authInitialTab}
        dict={dict}
      />
    </div>
  );
};

export default App;
