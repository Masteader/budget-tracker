import React, { useEffect, useState } from 'react';
import { deleteAccountTranslations, translations, type Language } from './i18n/translations';
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
import { AccountDeletionPage } from './components/AccountDeletionPage';

function askedLanguage(): string | null {
  try {
    return new URLSearchParams(window.location.search).get('lang');
  } catch {
    return null;
  }
}

/**
 * Arabic by default; `?lang=en` opens the English page (handy for sharing). This page has no Urdu,
 * and the app's Urdu readers get English, with a notice in Urdu pointing to the page that has it.
 */
function initialLanguage(): Language {
  const asked = askedLanguage();
  return asked === 'en' || asked === 'ur' ? 'en' : 'ar';
}

const PRIVACY_HASH = '#privacy';

/** Says, in Urdu, why this page is in English, and where the deletion and data details are in Urdu. */
const UrduNotice: React.FC = () => {
  const notice = deleteAccountTranslations.ur.landingNotice;
  return (
    <aside id="urdu-notice" lang="ur" dir="rtl" className="bg-ink px-4 py-3 text-center text-sm text-white">
      {notice.body}{' '}
      <a href="/delete-account?lang=ur" className="font-semibold underline">
        {notice.link}
      </a>
    </aside>
  );
};

const Site: React.FC = () => {
  const { session } = useAuth();
  const [lang, setLang] = useState<Language>(initialLanguage);
  const [hash, setHash] = useState(() => window.location.hash);
  const [authModalOpen, setAuthModalOpen] = useState(false);
  const [authInitialTab, setAuthInitialTab] = useState<'signin' | 'signup'>('signin');
  const dict = translations[lang];

  // The privacy section is on the landing page, so a link to it opens that page signed in too.
  const showPortal = Boolean(session) && hash !== PRIVACY_HASH;

  useEffect(() => {
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
    document.documentElement.lang = lang;
    document.title = dict.a11y.pageTitle;
  }, [lang, dict]);

  useEffect(() => {
    const onHashChange = () => setHash(window.location.hash);
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  // The browser looks for the anchor before React has rendered it, so scroll once it exists.
  useEffect(() => {
    if (!showPortal && hash.length > 1) {
      document.getElementById(hash.slice(1))?.scrollIntoView();
    }
  }, [hash, showPortal]);

  const handleOpenAuth = (tab: 'signin' | 'signup') => {
    setAuthInitialTab(tab);
    setAuthModalOpen(true);
  };

  /** Signed in and reading the privacy section: the header's account button goes back to the account. */
  const backToPortal = () => {
    window.history.pushState(null, '', window.location.pathname + window.location.search);
    setHash('');
  };

  // Authenticated state: render account portal
  if (showPortal) {
    return <PortalShell lang={lang} setLanguage={setLang} dict={dict} />;
  }

  // Unauthenticated state, or the privacy section: render landing page
  return (
    <div id="top" className="flex min-h-screen flex-col font-sans">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:start-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-white focus:px-4 focus:py-2 focus:text-ink focus:shadow-lg"
      >
        {dict.a11y.skipToContent}
      </a>
      {askedLanguage() === 'ur' && lang === 'en' && <UrduNotice />}
      <Header
        lang={lang}
        setLanguage={setLang}
        dict={dict}
        onOpenAuth={session ? backToPortal : handleOpenAuth}
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

/** Checked before the session split in Site: signed-in and signed-out visitors both reach the page. */
export const App: React.FC = () =>
  window.location.pathname === '/delete-account' ? <AccountDeletionPage /> : <Site />;

export default App;
