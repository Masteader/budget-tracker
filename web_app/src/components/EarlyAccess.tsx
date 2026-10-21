import React, { useState } from 'react';
import type { Language, TranslationDictionary } from '../i18n/translations';
import { CONTACT_EMAIL, submitInquiry, type InquiryOutcome } from '../lib/inquiries';

interface EarlyAccessProps {
  dict: TranslationDictionary;
  lang: Language;
}

type Status = 'idle' | 'sending' | 'sent' | Exclude<InquiryOutcome, 'sent'>;

export const EarlyAccess: React.FC<EarlyAccessProps> = ({ dict, lang }) => {
  const [email, setEmail] = useState('');
  const [honeypot, setHoneypot] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const t = dict.earlyAccess;

  const errorMessages: Record<Exclude<InquiryOutcome, 'sent'>, string> = {
    invalid: t.errorInvalid,
    rate_limited: t.errorRateLimited,
    unavailable: t.errorUnavailable,
    network: t.errorNetwork,
  };
  const errorMessage = status in errorMessages ? errorMessages[status as keyof typeof errorMessages] : null;
  const sending = status === 'sending';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = email.trim();
    if (!trimmed || sending) return;

    setStatus('sending');
    // Success is shown only after the server accepted the request (2xx).
    const outcome = await submitInquiry({
      type: 'vip_early_access',
      email: trimmed,
      locale: lang,
      source: 'web',
      ...(honeypot ? { company_website: honeypot } : {}),
    });
    setStatus(outcome);
  };

  return (
    <section id="early-access" aria-labelledby="early-access-title" className="mx-auto max-w-6xl px-4 pb-20 sm:px-6">
      <div className="rounded-3xl bg-gradient-to-br from-teal to-teal-dark p-8 text-center text-white sm:p-12">
        <p className="text-sm font-bold text-teal-mint">{t.badge}</p>
        <h2 id="early-access-title" className="mt-2 text-3xl font-bold sm:text-4xl">
          {t.title}
        </h2>
        <p className="mx-auto mt-3 max-w-lg text-white/85">{t.desc}</p>

        {status === 'sent' ? (
          <p
            role="status"
            className="mx-auto mt-8 max-w-md rounded-2xl bg-white px-5 py-4 font-bold text-teal-dark"
          >
            {t.successMsg}
          </p>
        ) : (
          <form onSubmit={handleSubmit} aria-busy={sending} className="relative mx-auto mt-8 max-w-md">
            <div className="flex flex-col gap-2 sm:flex-row">
              <label htmlFor="early-access-email" className="sr-only">
                {dict.a11y.emailLabel}
              </label>
              <input
                id="early-access-email"
                type="email"
                name="email"
                autoComplete="email"
                dir="ltr"
                maxLength={254}
                value={email}
                onChange={(e) => {
                  setEmail(e.target.value);
                  if (errorMessage) setStatus('idle');
                }}
                placeholder={t.placeholder}
                required
                disabled={sending}
                aria-invalid={status === 'invalid'}
                aria-describedby={errorMessage ? 'early-access-error' : undefined}
                className="min-w-0 flex-1 rounded-xl border-0 bg-white px-4 py-3.5 text-ink placeholder:text-muted focus:ring-2 focus:ring-teal-mint disabled:opacity-60"
              />
              {/* Honeypot: invisible to people and assistive tech; bots that fill it are ignored.
                  Clipped in place (an off-screen offset would add a horizontal scroll in RTL). */}
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
              <button
                type="submit"
                disabled={sending}
                className="whitespace-nowrap rounded-xl bg-ink px-6 py-3.5 font-bold text-white transition-colors hover:bg-black disabled:cursor-wait disabled:opacity-70"
              >
                {sending ? t.sending : t.button}
              </button>
            </div>
            {errorMessage && (
              <p
                id="early-access-error"
                role="alert"
                className="mt-3 rounded-xl bg-white px-4 py-3 text-sm font-semibold text-red-700"
              >
                {errorMessage}
              </p>
            )}
          </form>
        )}

        <p className="mt-6 text-sm text-white/85">
          {t.contactInfo}{' '}
          <a
            href={`mailto:${CONTACT_EMAIL}`}
            dir="ltr"
            className="inline-block font-semibold text-white underline underline-offset-4"
          >
            {CONTACT_EMAIL}
          </a>
        </p>
      </div>
    </section>
  );
};
