import React, { useState } from 'react';
import { motion } from 'framer-motion';
import confetti from 'canvas-confetti';
import type { TranslationDictionary } from '../i18n/translations';

interface EarlyAccessProps {
  dict: TranslationDictionary;
}

export const EarlyAccess: React.FC<EarlyAccessProps> = ({ dict }) => {
  const [email, setEmail] = useState('');
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;

    setSubmitted(true);
    confetti({
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

        {submitted ? (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="max-w-md mx-auto p-5 rounded-2xl bg-emerald-50 border border-emerald-300 text-emerald-800 font-bold text-sm mb-6 flex items-center justify-center gap-2"
          >
            <span className="material-symbols-outlined text-[20px]">check_circle</span>
            <span>{dict.earlyAccess.successMsg}</span>
          </motion.div>
        ) : (
          <form onSubmit={handleSubmit} className="max-w-md mx-auto flex flex-col sm:flex-row gap-2 mb-6">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={dict.earlyAccess.placeholder}
              required
              className="flex-1 bg-[#f8fdff] border border-slate-300 rounded-xl px-4 py-3.5 text-sm text-[#0c2530] focus:border-[#00808c] focus:ring-1 focus:ring-[#00808c] outline-none"
            />
            <button
              type="submit"
              className="px-6 py-3.5 rounded-xl bg-[#00808c] hover:bg-[#006575] text-white font-bold text-sm active:scale-95 transition-all whitespace-nowrap shadow-[0_4px_14px_rgba(0,128,140,0.25)]"
            >
              {dict.earlyAccess.button}
            </button>
          </form>
        )}

        <p className="text-xs text-slate-400">
          {dict.earlyAccess.partnerInfo}{' '}
          <a
            href="mailto:abedmowafaq@gmail.com"
            className="text-[#00808c] hover:underline underline-offset-4 font-mono font-medium"
          >
            abedmowafaq@gmail.com
          </a>
        </p>
      </div>
    </section>
  );
};
