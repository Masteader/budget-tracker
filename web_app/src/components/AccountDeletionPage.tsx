import React, { useEffect, useState } from 'react';
import {
  DELETE_ACCOUNT_LANGUAGES,
  deleteAccountTranslations,
  type DeleteAccountDictionary,
  type DeleteAccountLanguage,
  type DeleteAccountSection,
} from '../i18n/translations';
import { useAuth } from '../context/useAuth';
import { CONTACT_EMAIL, submitDeletionRequest, type DeletionRequestResult } from '../lib/inquiries';
import {
  deletionView,
  isAcceptedConfirmation,
  offersCancel,
  type DeletionStatusName,
  type DeletionView,
} from '../lib/accountDeletion';
import { supabase } from '../lib/supabaseClient';
import { Logo } from './Header';

// Public account deletion page, the one the app stores link to. Signed in, it calls the same
// RPCs as the app; identity comes from the session, so nobody can request for someone else, and
// the server re-checks everything (recent login, typed word, household choices). Signed out, it
// offers the request form, which only stores a row and emails the developer.

type Household = {
  household_id: string;
  household_name: string | null;
  position: 'sole_member' | 'primary_admin' | 'co_admin' | 'member';
  needs_choice: boolean;
  candidates: { user_id: string; display_name: string | null; pending_deletion: boolean }[];
};

type DeletionStatus = {
  status: DeletionStatusName;
  scheduled_for?: string;
  can_cancel: boolean;
  marked_households?: { household_id: string; household_name: string | null; scheduled_for: string }[];
};

type Preflight = { deletion: DeletionStatus; households: Household[] };

type HouseholdChoice = { action?: 'transfer' | 'delete'; successor?: string };

function initialLanguage(): DeleteAccountLanguage {
  const asked = new URLSearchParams(window.location.search).get('lang');
  return DELETE_ACCOUNT_LANGUAGES.find((lang) => lang === asked) ?? 'ar';
}

/**
 * The Riyadh date, the same one the reminder emails state, written day month year as the
 * app writes it. Urdu's default long form adds a comma the app does not have.
 */
function formatDate(value: string | undefined, locale: string): string {
  if (!value) return '';
  const parts = new Intl.DateTimeFormat(locale, {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'Asia/Riyadh',
  }).formatToParts(new Date(value));
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? '';
  return `${part('day')} ${part('month')} ${part('year')}`;
}

function errorMessage(hint: string | undefined, t: DeleteAccountDictionary): string {
  const errors = t.account.errors;
  switch (hint) {
    case 'reauthentication_required':
      return errors.reauthenticationRequired;
    case 'confirmation_mismatch':
      return errors.confirmationMismatch;
    case 'household_choice_missing':
      return errors.choiceMissing;
    case 'household_choice_invalid':
      return errors.choiceInvalid;
    case 'successor_invalid':
      return errors.successorInvalid;
    case 'successor_pending_deletion':
      return errors.successorPending;
    case 'deletion_in_progress':
      return errors.inProgress;
    default:
      return errors.generic;
  }
}

const inputClass =
  'w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 disabled:opacity-60';
const primaryButtonClass =
  'rounded-xl bg-teal px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-teal-dark disabled:cursor-wait disabled:opacity-60';
const secondaryButtonClass =
  'rounded-xl border border-line px-4 py-2 text-sm font-semibold text-ink transition-colors hover:border-teal hover:text-teal';

const Alert: React.FC<{ id?: string; children: React.ReactNode }> = ({ id, children }) => (
  <p id={id} role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
    {children}
  </p>
);

const Card: React.FC<{ id?: string; title: string; children: React.ReactNode }> = ({ id, title, children }) => (
  <section id={id} className="scroll-mt-20 rounded-2xl border border-line bg-white p-5 sm:p-6">
    <h2 className="text-xl font-bold text-ink">{title}</h2>
    <div className="mt-3 space-y-4 leading-relaxed text-muted">{children}</div>
  </section>
);

const InfoSection: React.FC<{ section: DeleteAccountSection }> = ({ section }) => (
  <Card title={section.title}>
    {section.intro && <p>{section.intro}</p>}
    <ul className="list-disc space-y-2 ps-5">
      {section.items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  </Card>
);

// ── Signed out: sign in ──────────────────────────────────────────────────────

const SignInCard: React.FC<{ t: DeleteAccountDictionary; onSignedIn: () => void }> = ({ t, onSignedIn }) => {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setFailed(false);
    const { error } = await signIn(email.trim(), password);
    if (error) setFailed(true);
    else onSignedIn();
    setPassword('');
    setBusy(false);
  };

  return (
    <Card title={t.signIn.title}>
      <p>{t.signIn.intro}</p>
      <form onSubmit={handleSubmit} aria-busy={busy} className="space-y-3">
        <div>
          <label htmlFor="deletion-signin-email" className="mb-1.5 block text-xs font-semibold text-ink">
            {t.signIn.email}
          </label>
          <input
            id="deletion-signin-email"
            type="email"
            required
            dir="ltr"
            autoComplete="email"
            maxLength={254}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={busy}
            className={inputClass}
          />
        </div>
        <div>
          <label htmlFor="deletion-signin-password" className="mb-1.5 block text-xs font-semibold text-ink">
            {t.signIn.password}
          </label>
          <input
            id="deletion-signin-password"
            type="password"
            required
            dir="ltr"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={busy}
            className={inputClass}
          />
        </div>
        {failed && <Alert>{t.signIn.error}</Alert>}
        <button type="submit" disabled={busy} className={primaryButtonClass}>
          {busy ? t.signIn.submitting : t.signIn.submit}
        </button>
      </form>
      <p className="text-sm">{t.signIn.forgot}</p>
    </Card>
  );
};

// ── Signed out: request form ─────────────────────────────────────────────────

const RequestCard: React.FC<{ t: DeleteAccountDictionary; lang: DeleteAccountLanguage }> = ({ t, lang }) => {
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');
  const [honeypot, setHoneypot] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<DeletionRequestResult | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = email.trim();
    if (!trimmed || busy) return;
    setBusy(true);
    setResult(
      await submitDeletionRequest({
        email: trimmed,
        locale: lang,
        source: 'web',
        ...(message.trim() ? { message: message.trim() } : {}),
        ...(honeypot ? { company_website: honeypot } : {}),
      }),
    );
    setBusy(false);
  };

  const failure = result && result.outcome !== 'sent' && result.outcome !== 'captured' ? result.outcome : null;
  const failureText = failure && {
    invalid: t.request.errorInvalid,
    rate_limited: t.request.errorRateLimited,
    unavailable: t.request.errorUnavailable,
    network: t.request.errorNetwork,
  }[failure];

  return (
    <Card id="request-form" title={t.request.title}>
      <p>{t.request.intro}</p>
      {result && (result.outcome === 'sent' || result.outcome === 'captured') ? (
        <div role="status" className="space-y-2 rounded-xl bg-teal-soft p-4 text-ink">
          <p className="font-bold">{t.request.receivedTitle}</p>
          <p>{result.outcome === 'captured' ? t.request.capturedBody : t.request.sentBody}</p>
          <p className="font-semibold">{t.request.notDeleted}</p>
          {result.reference && (
            <p className="text-sm">
              {t.request.reference} <bdi dir="ltr">{result.reference}</bdi>
            </p>
          )}
        </div>
      ) : (
        <form onSubmit={handleSubmit} aria-busy={busy} className="space-y-3">
          <div>
            <label htmlFor="deletion-request-email" className="mb-1.5 block text-xs font-semibold text-ink">
              {t.request.email}
            </label>
            <input
              id="deletion-request-email"
              type="email"
              required
              dir="ltr"
              autoComplete="email"
              maxLength={254}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={busy}
              aria-invalid={failure === 'invalid'}
              className={inputClass}
            />
          </div>
          <div>
            <label htmlFor="deletion-request-message" className="mb-1.5 block text-xs font-semibold text-ink">
              {t.request.message}
            </label>
            <textarea
              id="deletion-request-message"
              rows={3}
              maxLength={4000}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              disabled={busy}
              className={inputClass}
            />
          </div>
          {/* Honeypot: invisible to people and assistive tech; bots that fill it are ignored. */}
          <div aria-hidden="true" className="sr-only">
            <input
              type="text"
              name="company_website"
              tabIndex={-1}
              autoComplete="off"
              value={honeypot}
              onChange={(e) => setHoneypot(e.target.value)}
            />
          </div>
          {failureText && <Alert>{failureText}</Alert>}
          <button type="submit" disabled={busy} className={primaryButtonClass}>
            {busy ? t.request.submitting : t.request.submit}
          </button>
        </form>
      )}
    </Card>
  );
};

// ── Signed in: already scheduled ─────────────────────────────────────────────

// Scheduled, or started or stopped before deleting anything: the server still lets it be cancelled.
const PendingCard: React.FC<{
  t: DeleteAccountDictionary;
  view: Extract<DeletionView, 'pending' | 'starting' | 'stopped'>;
  deletion: DeletionStatus;
  onCancel: () => Promise<void>;
  busy: boolean;
  error: string | null;
}> = ({ t, view, deletion, onCancel, busy, error }) => {
  const marked = deletion.marked_households ?? [];
  const title =
    view === 'starting' ? t.account.startingTitle : view === 'stopped' ? t.account.stoppedTitle : t.account.pendingTitle;
  return (
    <Card title={title}>
      {view === 'pending' ? (
        <>
          <p className="text-lg font-bold text-ink">
            {t.account.pendingDate} <bdi>{formatDate(deletion.scheduled_for, t.dateLocale)}</bdi>
          </p>
          <p>{t.account.pendingUsable}</p>
        </>
      ) : (
        <p>{view === 'starting' ? t.account.startingBody : t.account.stoppedBody}</p>
      )}
      <p className="rounded-xl bg-sand-soft px-4 py-3 font-semibold text-sand-ink">{t.account.pendingSignIn}</p>
      {marked.length > 0 && (
        <div>
          <p className="font-semibold text-ink">{t.account.pendingHouseholds}</p>
          <ul className="mt-1 list-disc space-y-1 ps-5">
            {marked.map((household) => (
              <li key={household.household_id}>
                <bdi>{household.household_name}</bdi>: <bdi>{formatDate(household.scheduled_for, t.dateLocale)}</bdi>
              </li>
            ))}
          </ul>
        </div>
      )}
      {error && <Alert>{error}</Alert>}
      <button type="button" onClick={() => void onCancel()} disabled={busy} className={primaryButtonClass}>
        {busy ? t.account.cancelling : t.account.cancel}
      </button>
    </Card>
  );
};

// ── Signed in: schedule ──────────────────────────────────────────────────────

const ScheduleCard: React.FC<{
  t: DeleteAccountDictionary;
  lang: DeleteAccountLanguage;
  email: string | undefined;
  households: Household[];
  passwordConfirmed: boolean;
  onScheduled: (deletion: DeletionStatus) => void;
}> = ({ t, lang, email, households, passwordConfirmed, onScheduled }) => {
  const { signIn } = useAuth();
  const [choices, setChoices] = useState<Record<string, HouseholdChoice>>({});
  const [sessionTooOld, setSessionTooOld] = useState(false);
  const needPassword = !passwordConfirmed || sessionTooOld;
  const [password, setPassword] = useState('');
  const [word, setWord] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const setChoice = (householdId: string, change: HouseholdChoice) =>
    setChoices((current) => ({ ...current, [householdId]: { ...current[householdId], ...change } }));

  const choiceComplete = (household: Household) => {
    const choice = choices[household.household_id];
    return choice?.action === 'delete' || (choice?.action === 'transfer' && Boolean(choice.successor));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    const errors = t.account.errors;

    // Checked first, so a slip does not spend a sign-in.
    if (!households.filter((h) => h.needs_choice).every(choiceComplete)) {
      setError(errors.choiceMissing);
      return;
    }
    if (!isAcceptedConfirmation(word)) {
      setError(errors.confirmationMismatch);
      return;
    }

    setBusy(true);
    setError(null);
    try {
      if (needPassword) {
        // A new session is what the server's 15-minute check looks for.
        const outcome = email ? await signIn(email, password) : { error: new Error('no email on session') };
        setPassword('');
        if (outcome.error) {
          setError(errors.password);
          return;
        }
      }

      const { data, error: rpcError } = await supabase.rpc('request_account_deletion', {
        p_confirmation: word,
        p_household_choices: households
          .filter((h) => h.needs_choice)
          .map((h) => {
            const choice = choices[h.household_id];
            return choice.action === 'transfer'
              ? { household_id: h.household_id, action: 'transfer', successor_user_id: choice.successor }
              : { household_id: h.household_id, action: 'delete' };
          }),
        p_locale: lang,
      });
      if (rpcError) {
        if (rpcError.hint === 'reauthentication_required') setSessionTooOld(true);
        setError(errorMessage(rpcError.hint, t));
        return;
      }
      onScheduled(data as DeletionStatus);
    } catch {
      setError(errors.generic);
    } finally {
      setBusy(false);
    }
  };

  // A function, because "$&" in a household name means something in a replacement string.
  const fill = (template: string, name: string | null) => template.replace('{name}', () => name ?? '');

  return (
    <Card title={t.account.flowTitle}>
      <p>{t.account.flowIntro}</p>
      <p className="rounded-xl bg-sand-soft px-4 py-3 text-sm font-semibold text-sand-ink">{t.account.settlementWarning}</p>
      <form onSubmit={handleSubmit} aria-busy={busy} className="space-y-5">
        <div>
          <h3 className="font-bold text-ink">{t.account.householdsTitle}</h3>
          {households.length === 0 && <p className="mt-1">{t.account.noHouseholds}</p>}
          <ul className="mt-2 space-y-3">
            {households.map((household) => {
              const id = household.household_id;
              const choice = choices[id];
              const available = household.candidates.filter((c) => !c.pending_deletion);
              if (!household.needs_choice) {
                const text =
                  household.position === 'sole_member'
                    ? t.account.positionSole
                    : household.position === 'co_admin'
                      ? t.account.positionCoAdmin
                      : t.account.positionMember;
                return (
                  <li key={id} className="rounded-xl border border-line p-3">
                    {fill(text, household.household_name)}
                  </li>
                );
              }
              return (
                <li key={id} className="rounded-xl border border-line p-3">
                  <fieldset className="space-y-2">
                    <legend className="font-semibold text-ink">{fill(t.account.choiceTitle, household.household_name)}</legend>
                    {available.length === 0 && <p className="text-sm">{t.account.noSuccessor}</p>}
                    <label className={`flex items-start gap-2 ${available.length === 0 ? 'opacity-50' : ''}`}>
                      <input
                        type="radio"
                        name={`choice-${id}`}
                        className="mt-1.5"
                        checked={choice?.action === 'transfer'}
                        disabled={busy || available.length === 0}
                        onChange={() => setChoice(id, { action: 'transfer' })}
                      />
                      <span>{t.account.choiceTransfer}</span>
                    </label>
                    {choice?.action === 'transfer' && (
                      <div className="ps-6">
                        <label htmlFor={`successor-${id}`} className="mb-1.5 block text-xs font-semibold text-ink">
                          {t.account.successorLabel}
                        </label>
                        <select
                          id={`successor-${id}`}
                          value={choice.successor ?? ''}
                          disabled={busy}
                          onChange={(e) => setChoice(id, { successor: e.target.value })}
                          className={inputClass}
                        >
                          <option value="">{t.account.successorPlaceholder}</option>
                          {household.candidates.map((candidate) => (
                            <option key={candidate.user_id} value={candidate.user_id} disabled={candidate.pending_deletion}>
                              {candidate.display_name || t.account.successorUnnamed}
                              {candidate.pending_deletion ? ` ${t.account.successorPending}` : ''}
                            </option>
                          ))}
                        </select>
                      </div>
                    )}
                    <label className="flex items-start gap-2">
                      <input
                        type="radio"
                        name={`choice-${id}`}
                        className="mt-1.5"
                        checked={choice?.action === 'delete'}
                        disabled={busy}
                        onChange={() => setChoice(id, { action: 'delete' })}
                      />
                      <span>{t.account.choiceDelete}</span>
                    </label>
                    {choice?.action === 'delete' && (
                      <p className="rounded-xl bg-sand-soft px-4 py-3 text-sm font-semibold text-sand-ink">
                        {t.account.choiceDeleteWarning}
                      </p>
                    )}
                  </fieldset>
                </li>
              );
            })}
          </ul>
        </div>

        {needPassword && (
          <div>
            <label htmlFor="deletion-password" className="mb-1.5 block text-xs font-semibold text-ink">
              {t.account.password}
            </label>
            <input
              id="deletion-password"
              type="password"
              required
              dir="ltr"
              autoComplete="current-password"
              value={password}
              disabled={busy}
              onChange={(e) => setPassword(e.target.value)}
              className={inputClass}
            />
            <p className="mt-1 text-sm">{t.account.passwordHint}</p>
          </div>
        )}

        <div>
          <label htmlFor="deletion-word" className="mb-1.5 block text-xs font-semibold text-ink">
            {t.account.typedWord.replace('{word}', t.confirmationWord)}
          </label>
          <input
            id="deletion-word"
            type="text"
            required
            autoComplete="off"
            value={word}
            disabled={busy}
            onChange={(e) => setWord(e.target.value)}
            className={inputClass}
          />
        </div>

        {error && <Alert>{error}</Alert>}
        <button type="submit" disabled={busy} className={primaryButtonClass}>
          {busy ? t.account.submitting : t.account.submit}
        </button>
      </form>
    </Card>
  );
};

// ── Signed in: which of the above ────────────────────────────────────────────

const AccountCard: React.FC<{
  t: DeleteAccountDictionary;
  lang: DeleteAccountLanguage;
  email: string | undefined;
  passwordConfirmed: boolean;
  onSignOut: () => void;
}> = ({ t, lang, email, passwordConfirmed, onSignOut }) => {
  const [preflight, setPreflight] = useState<Preflight | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const [cancelBusy, setCancelBusy] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [cancelled, setCancelled] = useState(false);

  useEffect(() => {
    let current = true;
    void supabase.rpc('get_account_deletion_preflight').then(({ data, error }) => {
      if (!current) return;
      setLoadFailed(Boolean(error));
      if (!error) setPreflight(data as Preflight);
    });
    return () => {
      current = false;
    };
  }, [loadAttempt]);

  const reload = () => setLoadAttempt((attempt) => attempt + 1);

  const handleCancel = async () => {
    setCancelBusy(true);
    setCancelError(null);
    const { error } = await supabase.rpc('cancel_account_deletion');
    if (error) {
      setCancelError(errorMessage(error.hint, t));
    } else {
      setCancelled(true);
      setPreflight((known) => known && { ...known, deletion: { status: 'none', can_cancel: false } });
    }
    // Also after a refusal: deletion_in_progress means the page is out of date.
    reload();
    setCancelBusy(false);
  };

  const status = preflight?.deletion.status;
  const view = preflight ? deletionView(preflight.deletion) : null;

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-line bg-white px-5 py-3 text-sm text-muted">
        <span>
          {t.account.signedInAs} <bdi dir="ltr" className="font-semibold text-ink">{email}</bdi>
        </span>
        <button type="button" onClick={onSignOut} className={secondaryButtonClass}>
          {t.account.signOut}
        </button>
      </div>

      {cancelled && status === 'none' && (
        <p role="status" className="rounded-xl bg-teal-soft px-4 py-3 font-semibold text-ink">
          {t.account.cancelled}
        </p>
      )}

      {loadFailed ? (
        <>
          <Alert>{t.account.loadError}</Alert>
          <button type="button" onClick={reload} className={secondaryButtonClass}>
            {t.account.retry}
          </button>
          <RequestCard t={t} lang={lang} />
        </>
      ) : !preflight ? (
        <p role="status" className="rounded-2xl border border-line bg-white p-5">
          {t.account.loading}
        </p>
      ) : view && offersCancel(view) ? (
        <PendingCard
          t={t}
          view={view}
          deletion={preflight.deletion}
          onCancel={handleCancel}
          busy={cancelBusy}
          error={cancelError}
        />
      ) : view === 'schedule' ? (
        <ScheduleCard
          t={t}
          lang={lang}
          email={email}
          households={preflight.households}
          passwordConfirmed={passwordConfirmed}
          onScheduled={(deletion) => {
            setCancelled(false);
            setPreflight({ ...preflight, deletion });
          }}
        />
      ) : view === 'stoppedPartway' ? (
        <Card title={t.account.stoppedPartwayTitle}>
          <p>{t.account.stoppedPartwayBody}</p>
        </Card>
      ) : (
        <Card title={t.account.inProgressTitle}>
          <p>{t.account.inProgressBody}</p>
        </Card>
      )}
    </>
  );
};

// ── The page ─────────────────────────────────────────────────────────────────

export const AccountDeletionPage: React.FC = () => {
  const { session, user, loading, signOut } = useAuth();
  const [lang, setLang] = useState<DeleteAccountLanguage>(initialLanguage);
  // A sign-in on this page is already the fresh login the server asks for.
  const [signedInHere, setSignedInHere] = useState(false);
  const t = deleteAccountTranslations[lang];

  useEffect(() => {
    document.documentElement.dir = t.dir;
    document.documentElement.lang = lang;
    document.title = t.pageTitle;
  }, [lang, t]);

  const chooseLanguage = (next: DeleteAccountLanguage) => {
    setLang(next);
    window.history.replaceState(null, '', `${window.location.pathname}?lang=${next}`);
  };

  return (
    <div className="flex min-h-screen flex-col font-sans">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:start-3 focus:top-3 focus:z-[100] focus:rounded-lg focus:bg-white focus:px-4 focus:py-2 focus:text-ink focus:shadow-lg"
      >
        {t.skipToContent}
      </a>
      <header className="border-b border-line bg-white">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6">
          <a href={lang === 'en' ? '/?lang=en' : '/'} aria-label={t.home} className="flex min-w-0 items-center gap-2.5">
            <Logo className="h-9 w-9 shrink-0" />
            <span className="text-sm font-bold text-ink sm:text-base">{t.appName}</span>
          </a>
          <nav aria-label={t.languageNav} className="flex items-center gap-1.5">
            {DELETE_ACCOUNT_LANGUAGES.map((code) => (
              <button
                key={code}
                type="button"
                lang={code}
                aria-pressed={code === lang}
                onClick={() => chooseLanguage(code)}
                className={`rounded-lg border px-3 py-1.5 text-sm font-semibold transition-colors ${
                  code === lang ? 'border-teal bg-teal text-white' : 'border-line text-ink hover:border-teal hover:text-teal'
                }`}
              >
                {deleteAccountTranslations[code].languageName}
              </button>
            ))}
          </nav>
        </div>
      </header>

      <main id="main-content" tabIndex={-1} className="mx-auto w-full max-w-3xl flex-1 space-y-5 px-4 py-8 focus:outline-none sm:px-6">
        <div>
          <h1 className="text-3xl font-bold text-ink sm:text-4xl">{t.title}</h1>
          <p className="mt-3 leading-relaxed text-muted">{t.intro}</p>
        </div>

        <InfoSection section={t.how} />

        {loading ? (
          <p role="status" className="rounded-2xl border border-line bg-white p-5 text-muted">
            {t.account.loading}
          </p>
        ) : session ? (
          <AccountCard
            key={user?.id}
            t={t}
            lang={lang}
            email={user?.email}
            passwordConfirmed={signedInHere}
            onSignOut={() => {
              setSignedInHere(false);
              void signOut();
            }}
          />
        ) : (
          <>
            <SignInCard t={t} onSignedIn={() => setSignedInHere(true)} />
            <RequestCard t={t} lang={lang} />
          </>
        )}

        <InfoSection section={t.window} />
        <InfoSection section={t.deleted} />
        <InfoSection section={t.kept} />
        <InfoSection section={t.notEdited} />
        <InfoSection section={t.outOfReach} />
        <InfoSection section={t.admins} />

        <p className="text-sm text-muted">
          {t.contact}{' '}
          <a href={`mailto:${CONTACT_EMAIL}`} dir="ltr" className="inline-block font-semibold text-teal underline underline-offset-4">
            {CONTACT_EMAIL}
          </a>
        </p>
      </main>

      <footer className="border-t border-line bg-white py-6 text-center text-xs text-muted">
        <bdi dir="ltr">© 2026</bdi> {t.appName} · {t.rights}
      </footer>
    </div>
  );
};
