import React, { useState } from 'react';
import { motion } from 'framer-motion';
import confetti from 'canvas-confetti';
import type { Language, TranslationDictionary } from '../i18n/translations';
import { submitInquiry, type InquiryOutcome } from '../lib/inquiries';

interface EarlyAccessProps {
  dict: TranslationDictionary;
  lang: Language;
}

type Status = 'idle' | 'sending' | 'sent' | Exclude<InquiryOutcome, 'sent'>;

export const EarlyAccess: React.FC<EarlyAccessProps> = ({ dict, lang }) => {
  const [email, setEmail] = useState('');
  const [honeypot, setHoneypot] = useState('');
  const [status, setStatus] = useState<Status>('idle');

  const errorMessages: Record<Exclude<InquiryOutcome, 'sent'>, string> = {
    invalid: dict.earlyAccess.errorInvalid,
    rate_limited: dict.earlyAccess.errorRateLimited,
    unavailable: dict.earlyAccess.errorUnavailable,
    network: dict.earlyAccess.errorNetwork,
  };
  const errorMessage = status in errorMessages ? errorMessages[status as keyof typeof errorMessages] : null;
  const sending = status === 'sending';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = email.trim();
    if (!trimmed || sending) return;

    setStatus('sending');
    const outcome = await submitInquiry({
      type: 'vip_early_access',
      email: trimmed,
      locale: lang,
      source: 'web',
      ...(honeypot ? { company_website: honeypot } : {}),
    });
    setStatus(outcome);
    if (outcome !== 'sent') return;

    confetti({
      disableForReducedMotion: true,
      particleCount: 100,
      spread: 70,
      origin: { y: 0.6 },
      colors: ['#00e5bf', '#4de6f7', '#008093', '#d4af37'],
    });
  };

  return (
    <section className="py-20 px-5 lg:px-12 max-w-[1200px] mx-auto text-center" id="early-access">
      <div className="p-8 lg:p-16 rounded-3xl bg-white border border-[#d4ebf0] relative overflow-hidden shadow-[0_10px_30px_rgba(0,100,115,0.06)]">
        <div className="w-full h-1 bg-gradient-to-r from-electric-teal via-[#008093] to-secondary absolute top-0 left-0" />

        <span className="text-secondary text-xs font-mono font-bold uppercase tracking-widest block mb-3">
          {dict.earlyAccess.badge}
        </span>
        <h2 className="text-3xl sm:text-5xl font-bold tracking-tight text-[#0c2530] mb-3">
          {dict.earlyAccess.title}
        </h2>
        <p className="text-base text-[#008093] font-semibold mb-6">
          {dict.earlyAccess.headline}
        </p>
        <p className="text-sm text-slate-600 max-w-xl mx-auto mb-8 leading-relaxed">
          {dict.earlyAccess.desc}
        </p>

        {status === 'sent' ? (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            role="status"
            className="max-w-md mx-auto p-5 rounded-2xl bg-emerald-50 border border-emerald-300 text-emerald-800 font-bold text-sm mb-6 flex items-center justify-center gap-2"
          >
            <span aria-hidden="true" className="material-symbols-outlined text-[20px]">check_circle</span>
            <span>{dict.earlyAccess.successMsg}</span>
          </motion.div>
        ) : (
          <form
            onSubmit={handleSubmit}
            aria-busy={sending}
            className="max-w-md mx-auto mb-6"
          >
            <div className="flex flex-col sm:flex-row gap-2">
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
                placeholder={dict.earlyAccess.placeholder}
                required
                disabled={sending}
                aria-invalid={status === 'invalid'}
                aria-describedby={errorMessage ? 'early-access-error' : undefined}
                className="flex-1 bg-[#f8fdff] border border-slate-300 rounded-xl px-4 py-3.5 text-sm text-[#0c2530] focus:border-[#00808c] focus:ring-1 focus:ring-[#00808c] outline-none disabled:opacity-60"
              />
              {/* Honeypot: invisible to people and assistive tech; bots that fill it are ignored. */}
              <div aria-hidden="true" className="absolute -left-[10000px] w-px h-px overflow-hidden">
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
                className="px-6 py-3.5 rounded-xl bg-[#00808c] hover:bg-[#006575] text-white font-bold text-sm active:scale-95 transition-all whitespace-nowrap shadow-[0_4px_14px_rgba(0,128,140,0.25)] disabled:opacity-70 disabled:cursor-wait"
              >
                {sending ? dict.earlyAccess.sending : dict.earlyAccess.button}
              </button>
            </div>
            {errorMessage && (
              <p
                id="early-access-error"
                role="alert"
                className="mt-3 text-sm font-semibold text-red-700 bg-red-50 border border-red-200 rounded-xl px-4 py-3"
              >
                {errorMessage}
              </p>
            )}
          </form>
        )}

        <p className="text-xs text-slate-400">
          {dict.earlyAccess.partnerInfo}{' '}
          <a
            href="mailto:fmscoinfo@fmsco.com.sa"
            className="text-[#00808c] hover:underline underline-offset-4 font-mono font-medium"
          >
            fmscoinfo@fmsco.com.sa
          </a>
        </p>
      </div>
    </section>
  );
};
