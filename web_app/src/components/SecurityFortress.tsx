import React from 'react';
import { motion } from 'framer-motion';
import type { TranslationDictionary } from '../i18n/translations';

interface SecurityFortressProps {
  dict: TranslationDictionary;
}

export const SecurityFortress: React.FC<SecurityFortressProps> = ({ dict }) => {
  return (
    <section className="py-20 px-5 lg:px-12 max-w-[1600px] mx-auto text-start" id="security">
      <div className="p-8 lg:p-16 rounded-3xl relative overflow-hidden shadow-2xl border border-white/10">
        {/* Photographic Glacial Backdrop */}
        <div
          className="absolute inset-0 z-0 bg-cover bg-center"
          style={{
            backgroundImage: `url("https://lh3.googleusercontent.com/aida-public/AB6AXuBLgYZ7fkw9a8A8yaeZUB_mu7HK77M5kxQLWc73NHCBfJ32Q1ziUxBvJSRCcOJatKT5plWGKNvVynr4EFgpWUH3IE2Z0k2mCsN_7nGJ45ONZ_Ipy6vs-eSledXG3DQpI5RgXU7wxPyiAbbAjIdhah6PTQ_Z4oTpWh8m6dszZD6Wg32gcyTUDgFfUG4th-DU50oHtSsY2qosRrbV7t9FlhFt1QEm6MNgIOx0X7U3Gnr0SD-IS5uUPO8GahiN67-PRJGOzA")`,
          }}
        />
        {/* Sleek dark translucent gradient overlay to keep text ultra crisp */}
        <div className="absolute inset-0 z-0 bg-gradient-to-r from-[#0b1528]/95 via-[#0c1f2e]/85 to-[#0b1528]/80 backdrop-blur-[2px]" />

        <div className="relative z-10 max-w-5xl">
          {/* Top Badge */}
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-white/10 border border-electric-teal/30 text-electric-teal text-xs font-medium backdrop-blur-md mb-6 shadow-sm">
            <span className="material-symbols-outlined text-[16px]">shield</span>
            <span className="text-white font-medium">{dict.security.badge}</span>
          </div>

          {/* Headline */}
          <h2 className="text-3xl sm:text-4xl lg:text-[40px] font-bold tracking-tight text-white leading-tight mb-4 drop-shadow-md">
            {dict.security.title}
          </h2>

          {/* Subtitle */}
          <p className="text-sm sm:text-base text-white/85 max-w-4xl leading-relaxed drop-shadow">
            {dict.security.subtitle}
          </p>
        </div>

        {/* 6 Feature Cards Grid with Frosted Glassmorphism */}
        <div className="relative z-10 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 mt-10">
          {dict.security.cards.map((card, idx) => (
            <motion.div
              key={idx}
              initial={{ opacity: 0, y: 15 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: idx * 0.08 }}
              className="p-6 rounded-2xl bg-[#0c1f2e]/70 border border-white/15 backdrop-blur-md flex flex-col justify-start hover:border-electric-teal/60 hover:-translate-y-1 transition-all shadow-lg"
            >
              <div className="flex items-center gap-3 mb-2">
                <span className="material-symbols-outlined text-electric-teal text-[22px]">
                  check_circle
                </span>
                <h3 className="text-sm font-bold text-white">{card.title}</h3>
              </div>
              <p className="text-xs text-white/70 leading-relaxed ps-8">{card.desc}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};
