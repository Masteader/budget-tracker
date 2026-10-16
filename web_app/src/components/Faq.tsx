import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import type { TranslationDictionary } from '../i18n/translations';

interface FaqProps {
  dict: TranslationDictionary;
}

export const Faq: React.FC<FaqProps> = ({ dict }) => {
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  const toggleFaq = (idx: number) => {
    setOpenIndex(openIndex === idx ? null : idx);
  };

  return (
    <section className="py-20 px-5 lg:px-12 max-w-[1200px] mx-auto text-start" id="faq">
      <div className="text-center mb-16">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-[#dcf2f5] text-[#007a87] text-xs font-mono font-semibold border border-[#bce6ec] mb-3 uppercase tracking-wider">
          <span className="material-symbols-outlined text-[16px]">help</span>
          <span>{dict.faq.badge}</span>
        </div>
        <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-[#0c2530]">
          {dict.faq.title}
        </h2>
      </div>

      <div className="space-y-4">
        {dict.faq.items.map((item, idx) => {
          const isOpen = openIndex === idx;
          return (
            <div
              key={idx}
              className="rounded-2xl card-arctic overflow-hidden border border-[#d4ebf0] bg-white transition-all shadow-sm"
            >
              <button
                onClick={() => toggleFaq(idx)}
                className="w-full p-6 text-start flex justify-between items-center hover:text-[#00808c] transition-colors"
              >
                <div>
                  <span className="text-base font-bold text-[#0c2530] block">{item.q}</span>
                  <span className="text-xs text-slate-400 font-normal mt-0.5 block">{item.sub}</span>
                </div>
                <span
                  className={`material-symbols-outlined text-slate-400 transition-transform duration-300 ${
                    isOpen ? 'rotate-180 text-[#00808c]' : ''
                  }`}
                >
                  expand_more
                </span>
              </button>
              <AnimatePresence>
                {isOpen && (
                  <motion.div
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.3 }}
                    className="overflow-hidden"
                  >
                    <div className="px-6 pb-6 text-sm text-slate-600 border-t border-slate-100 pt-4 leading-relaxed">
                      <p>{item.a}</p>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          );
        })}
      </div>
    </section>
  );
};
