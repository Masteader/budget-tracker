import React from 'react';
import { motion } from 'framer-motion';
import type { TranslationDictionary } from '../i18n/translations';

interface PillarsProps {
  dict: TranslationDictionary;
}

export const Pillars: React.FC<PillarsProps> = ({ dict }) => {
  return (
    <section className="py-20 px-5 lg:px-12 max-w-[1600px] mx-auto" id="pillars">
      <div className="text-center mb-16">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-[#dcf2f5] text-[#007a87] text-xs font-mono font-medium border border-[#bce6ec] mb-3 uppercase tracking-wider">
          <span className="material-symbols-outlined text-[16px]">assured_workload</span>
          <span>{dict.pillars.badge}</span>
        </div>
        <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-[#0c2530]">
          {dict.pillars.title}
        </h2>
        <p className="text-sm sm:text-base text-slate-600 max-w-2xl mx-auto mt-3">
          {dict.pillars.subtitle}
        </p>
      </div>

      {/* Bento Grid (12 Architectural Cards) */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 text-start">
        {dict.pillars.items.map((item, idx) => (
          <motion.div
            key={idx}
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.45, delay: (idx % 4) * 0.08 }}
            className="p-6 rounded-2xl bg-white border border-[#d4ebf0] shadow-sm flex flex-col justify-between hover:shadow-lg hover:border-[#00808c] hover:-translate-y-1.5 transition-all group"
          >
            <div>
              <div className="w-10 h-10 rounded-xl bg-[#e3f7fa] flex items-center justify-center text-[#00808c] mb-4 group-hover:scale-110 group-hover:bg-[#00808c] group-hover:text-white transition-all shadow-sm">
                <span className="material-symbols-outlined text-[22px]">{item.icon}</span>
              </div>
              <h3 className="text-base font-bold text-[#0c2530] mb-2 group-hover:text-[#00808c] transition-colors">
                {item.title}
              </h3>
              <p className="text-xs text-slate-500 leading-relaxed">{item.desc}</p>
            </div>
            <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-[11px] text-slate-400 font-mono">
              <span>0{idx + 1} // ARCH</span>
              <span className="material-symbols-outlined text-[14px] text-slate-300 group-hover:text-[#00808c] transition-colors rtl:rotate-180">
                arrow_forward
              </span>
            </div>
          </motion.div>
        ))}
      </div>
    </section>
  );
};
