import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/useAuth';
import type { TranslationDictionary } from '../../i18n/translations';

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialTab?: 'signin' | 'signup';
  dict: TranslationDictionary;
}

export const AuthModal: React.FC<AuthModalProps> = ({
  isOpen,
  onClose,
  initialTab = 'signin',
  dict,
}) => {
  const { signIn, signUp } = useAuth();
  const [tab, setTab] = useState<'signin' | 'signup'>(initialTab);
  const [prevInitialTab, setPrevInitialTab] = useState(initialTab);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  if (prevInitialTab !== initialTab) {
    setPrevInitialTab(initialTab);
    setTab(initialTab);
    setErrorMsg(null);
  }

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);
    setSubmitting(true);

    try {
      if (tab === 'signin') {
        const { error } = await signIn(email.trim(), password);
        if (error) {
          setErrorMsg(error.message || dict.auth.errorGeneric);
        } else {
          onClose();
        }
      } else {
        const { error } = await signUp(email.trim(), password, displayName.trim());
        if (error) {
          setErrorMsg(error.message || dict.auth.errorGeneric);
        } else {
          onClose();
        }
      }
    } catch {
      setErrorMsg(dict.auth.errorGeneric);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-ink/40 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="auth-modal-title"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-3xl bg-white p-6 sm:p-8 shadow-2xl border border-line relative transition-all"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close Button */}
        <button
          type="button"
          onClick={onClose}
          aria-label={dict.auth.close}
          className="absolute top-5 left-5 rtl:left-auto rtl:right-5 p-2 rounded-full text-muted hover:text-ink hover:bg-bg transition-colors"
        >
          <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>

        {/* Header Tabs */}
        <div className="mt-2 mb-6">
          <div className="inline-flex w-full p-1 bg-teal-soft/60 rounded-2xl border border-line/60">
            <button
              type="button"
              onClick={() => { setTab('signin'); setErrorMsg(null); }}
              className={`flex-1 py-2 text-sm font-bold rounded-xl transition-all ${
                tab === 'signin'
                  ? 'bg-teal text-white shadow-sm'
                  : 'text-muted hover:text-ink'
              }`}
            >
              {dict.auth.signIn}
            </button>
            <button
              type="button"
              onClick={() => { setTab('signup'); setErrorMsg(null); }}
              className={`flex-1 py-2 text-sm font-bold rounded-xl transition-all ${
                tab === 'signup'
                  ? 'bg-teal text-white shadow-sm'
                  : 'text-muted hover:text-ink'
              }`}
            >
              {dict.auth.signUp}
            </button>
          </div>
          <h2 id="auth-modal-title" className="text-xl font-bold text-ink mt-5 text-center">
            {tab === 'signin' ? dict.auth.signInTitle : dict.auth.signUpTitle}
          </h2>
        </div>

        {/* Error Banner */}
        {errorMsg && (
          <div className="mb-4 rounded-xl bg-red-50 border border-red-200 p-3 text-sm text-red-700 flex items-start gap-2">
            <svg className="w-5 h-5 shrink-0 text-red-500 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
            </svg>
            <span>{errorMsg}</span>
          </div>
        )}

        {/* Auth Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          {tab === 'signup' && (
            <div>
              <label className="block text-xs font-semibold text-ink mb-1.5">
                {dict.auth.displayName}
              </label>
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="مثلاً: أبو فهد"
                className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
              />
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {dict.auth.email}
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="user@example.com"
              dir="ltr"
              className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all text-left"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {dict.auth.password}
            </label>
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              dir="ltr"
              className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all text-left"
            />
          </div>

          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-xl bg-teal px-5 py-3 text-sm font-bold text-white shadow-md hover:bg-teal-dark active:scale-[0.99] transition-all disabled:opacity-50 mt-2 flex items-center justify-center gap-2"
          >
            {submitting ? (
              <>
                <svg className="animate-spin h-4 w-4 text-white" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                </svg>
                <span>{dict.auth.loading}</span>
              </>
            ) : tab === 'signin' ? (
              dict.auth.submitSignIn
            ) : (
              dict.auth.submitSignUp
            )}
          </button>
        </form>

        {/* Toggle Footer */}
        <div className="mt-5 text-center">
          <button
            type="button"
            onClick={() => {
              setTab(tab === 'signin' ? 'signup' : 'signin');
              setErrorMsg(null);
            }}
            className="text-xs font-semibold text-teal hover:text-teal-dark transition-colors"
          >
            {tab === 'signin' ? dict.auth.noAccount : dict.auth.hasAccount}
          </button>
        </div>
      </div>
    </div>
  );
};
