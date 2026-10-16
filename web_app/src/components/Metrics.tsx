import React from 'react';
import { motion } from 'framer-motion';
import type { TranslationDictionary } from '../i18n/translations';

interface MetricsProps {
  dict: TranslationDictionary;
}

export const Metrics: React.FC<MetricsProps> = ({ dict }) => {
  const cards = [
    {
      icon: 'verified_user',
      val: dict.metrics.metric1Val,
      title: dict.metrics.metric1Title,
      desc: dict.metrics.metric1Desc,
    },
    {
      icon: 'calendar_month',
      val: dict.metrics.metric2Val,
      title: dict.metrics.metric2Title,
      desc: dict.metrics.metric2Desc,
    },
    {
      icon: 'auto_awesome',
      val: dict.metrics.metric3Val,
      title: dict.metrics.metric3Title,
      desc: dict.metrics.metric3Desc,
    },
    {
      icon: 'account_balance',
      val: dict.metrics.metric4Val,
      title: dict.metrics.metric4Title,
      desc: dict.metrics.metric4Desc,
    },
  ];

  return (
    <section className="py-16 px-5 lg:px-12 max-w-[1600px] mx-auto" id="metrics">
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 text-start">
        {cards.map((card, idx) => (
          <motion.div
            key={idx}
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: idx * 0.1 }}
            className="p-6 rounded-2xl bg-white border border-[#d4ebf0] shadow-sm flex flex-col justify-between hover:shadow-lg hover:border-[#00808c] hover:-translate-y-1 transition-all group"
          >
            <div>
              <div className="w-10 h-10 rounded-xl bg-[#e3f7fa] text-[#00808c] flex items-center justify-center mb-4 group-hover:scale-105 group-hover:bg-[#00808c] group-hover:text-white transition-all">
                <span className="material-symbols-outlined text-[22px]">{card.icon}</span>
              </div>
              <div className="text-3xl lg:text-4xl font-bold font-mono text-[#0c2530] mb-1.5">
                {card.val}
              </div>
              <div className="text-base font-bold text-[#0c2530] mb-2">{card.title}</div>
            </div>
            <p className="text-xs text-slate-500 leading-relaxed mt-2">{card.desc}</p>
          </motion.div>
        ))}
      </div>
    </section>
  );
};
