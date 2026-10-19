import React, { useState } from 'react';
import { motion } from 'framer-motion';
import confetti from 'canvas-confetti';
import type { TranslationDictionary } from '../i18n/translations';
import { GlacialParticlesCanvas } from './GlacialParticlesCanvas';
import { AliveGlacialRiver } from './AliveGlacialRiver';
import heroGlacierImg from '../assets/hero_glacier.png';

interface HeroProps {
  dict: TranslationDictionary;
}

export const Hero: React.FC<HeroProps> = ({ dict }) => {
  const [settled, setSettled] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  const handleQuickSettle = () => {
    setSettled(true);
    confetti({
      disableForReducedMotion: true,
      particleCount: 70,
      spread: 60,
      origin: { y: 0.7 },
      colors: ['#00e5bf', '#4de6f7', '#73fbc4', '#ffffff'],
    });
    setToastMsg(dict.hero.roommateSub + ' ✓');
    setTimeout(() => {
      setToastMsg(null);
    }, 3500);
  };

  return (
    <section className="relative min-h-[960px] lg:min-h-[1020px] flex items-center justify-center overflow-hidden px-5 lg:px-12 pt-32 pb-20">
      {/* Pristine Sharp Glacial Iceberg Photography (NO BLUR, SHARP & LUMINOUS) */}
      <div className="absolute inset-0 z-0 overflow-hidden">
        <img
          alt={dict.hero.heroImageAlt}
          aria-hidden="true"
          width={1376}
          height={768}
          fetchPriority="high"
          className="w-full h-full object-cover object-center transform scale-[1.01]"
          style={{
            filter: 'contrast(1.06) saturate(1.1) brightness(1.02)',
            imageRendering: '-webkit-optimize-contrast',
          }}
          src={heroGlacierImg}
          loading="eager"
          decoding="sync"
        />

        {/* Dynamic Living Animated River Current in the Glacial Ocean Channel */}
        <AliveGlacialRiver />

        {/* Balanced Vignette: keeps the majestic icebergs and glowing river luminous while ensuring text contrast */}
        <div className="absolute inset-0 bg-gradient-to-t from-[#0b1528] via-[#0b1528]/10 to-[#0b1528]/30 pointer-events-none" />
        <div className="absolute inset-0 bg-radial from-transparent via-transparent to-black/30 pointer-events-none" />
      </div>

      {/* Floating 3D Glacial Particle Field Overlay (Preserved flying dots) */}
      <GlacialParticlesCanvas />

      {/* Hero Content Layer Directly over Glacial Mirror Sea */}
      <div className="relative max-w-[1360px] mx-auto z-20 w-full flex flex-col items-center text-center">
        {/* Crystalline Eyebrow Badge */}
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="inline-flex items-center gap-2.5 px-4 py-1.5 rounded-full bg-deep-navy/70 border border-electric-teal/40 backdrop-blur-md mb-6 text-ice-cyan text-xs font-semibold tracking-wider uppercase shadow-xl"
        >
          <span aria-hidden="true" className="material-symbols-outlined fill-1 text-[16px] text-electric-teal">
            ac_unit
          </span>
          <span className="text-white drop-shadow">{dict.hero.badge}</span>
          <span className="w-2 h-2 rounded-full bg-electric-teal animate-pulse" />
        </motion.div>

        {/* Main Headline with Crisp Deep Navy / White & Electric Teal */}
        <motion.h1
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.1 }}
          className="text-center text-3xl sm:text-5xl lg:text-[62px] lg:leading-[74px] font-bold tracking-tight text-white max-w-5xl mb-8 drop-shadow-lg"
        >
          {dict.hero.title}
        </motion.h1>

        {/* Dual Action Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.2 }}
          className="flex flex-col sm:flex-row items-center justify-center gap-4 w-full mb-12"
        >
          <a
            href="#simulator"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2.5 px-8 py-4 rounded-xl bg-gradient-to-r from-primary-container via-primary to-secondary text-white text-base font-bold shadow-xl shadow-primary-container/40 hover:shadow-electric-teal/40 hover:-translate-y-0.5 active:scale-95 transition-all border border-white/20"
          >
            <span aria-hidden="true" className="material-symbols-outlined text-[20px] text-electric-teal">bolt</span>
            <span>{dict.hero.ctaPrimary}</span>
          </a>
          <a
            href="#pillars"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-8 py-4 rounded-xl bg-deep-navy/70 hover:bg-deep-navy/90 text-white text-base font-semibold border border-white/30 hover:border-ice-cyan backdrop-blur-xl transition-all shadow-lg hover:-translate-y-0.5"
          >
            <span>{dict.hero.ctaSecondary}</span>
            <span aria-hidden="true" className="material-symbols-outlined text-[18px] text-ice-cyan rtl:rotate-180">
              arrow_forward
            </span>
          </a>
        </motion.div>

        {/* Floating Architectural Glass HUD Telemetry Collage */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.4 }}
          className="w-full max-w-5xl grid grid-cols-1 md:grid-cols-3 gap-5 mb-8 text-start"
        >
          {/* HUD Card 1: Safe Burn Rate Live Gauge Widget */}
          <div className="glass-cockpit p-6 rounded-2xl relative overflow-hidden flex flex-col justify-between">
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-mono text-ice-cyan uppercase tracking-wider font-semibold">
                {dict.hero.spendGaugeTitle}
              </span>
              <span className="p-1.5 rounded-lg bg-white/10 text-electric-teal">
                <span aria-hidden="true" className="material-symbols-outlined text-[18px]">speed</span>
              </span>
            </div>
            <div>
              <div className="text-3xl font-bold font-mono text-white mb-1 drop-shadow">
                {dict.hero.spendGaugeVal}{' '}
                <span className="text-xs font-normal text-white/70">{dict.hero.spendGaugeUnit}</span>
              </div>
              <div className="flex items-center justify-between text-xs text-electric-teal font-medium">
                <span>{dict.hero.spendGaugeStatus}</span>
                <span className="font-mono text-white/80">{dict.hero.spendGaugeProgress}</span>
              </div>
            </div>
            <div className="w-full bg-white/15 h-2 rounded-full mt-3 overflow-hidden">
              <div className="telemetry-flow h-full rounded-full" style={{ width: '48%' }} />
            </div>
          </div>

          {/* HUD Card 2: Roommate Balance Preview */}
          <div className="glass-cockpit p-6 rounded-2xl relative overflow-hidden flex flex-col justify-between">
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-mono text-ice-cyan uppercase tracking-wider font-semibold">
                {dict.hero.roommateTitle}
              </span>
              <span className="p-1.5 rounded-lg bg-white/10 text-electric-teal">
                <span aria-hidden="true" className="material-symbols-outlined text-[18px]">balance</span>
              </span>
            </div>
            <div>
              <div className="text-3xl font-bold font-mono text-electric-teal mb-1 drop-shadow">
                {settled ? dict.hero.settledVal : dict.hero.roommateVal}{' '}
                <span className="text-xs font-normal text-white/70">
                  {settled ? dict.hero.settledStatus : dict.hero.roommateStatus}
                </span>
              </div>
              <div className="text-xs text-white/85 flex justify-between items-center">
                <span>{dict.hero.roommateSub}</span>
                <button
                  onClick={handleQuickSettle}
                  className="text-electric-teal font-bold hover:underline cursor-pointer bg-white/10 px-2 py-0.5 rounded text-[11px] transition-all hover:bg-electric-teal hover:text-deep-navy"
                >
                  {settled ? dict.hero.settledBtn : dict.hero.roommateSettle}
                </button>
              </div>
            </div>
            <div className="w-full bg-white/15 h-2 rounded-full mt-3 overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-700 ${
                  settled ? 'bg-secondary' : 'bg-electric-teal'
                }`}
                style={{ width: settled ? '100%' : '72%' }}
              />
            </div>
          </div>

          {/* HUD Card 3: Autonomous Ingestion (ZATCA & Voice NLP) */}
          <div className="glass-cockpit p-6 rounded-2xl relative overflow-hidden flex flex-col justify-between">
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-mono text-ice-cyan uppercase tracking-wider font-semibold">
                {dict.hero.ingestionTitle}
              </span>
              <span className="p-1.5 rounded-lg bg-white/10 text-electric-teal">
                <span aria-hidden="true" className="material-symbols-outlined text-[18px]">psychology</span>
              </span>
            </div>
            <div>
              <div className="text-3xl font-bold font-mono text-white mb-1 drop-shadow">
                {dict.hero.ingestionVal}{' '}
                <span className="text-xs font-normal text-white/70">{dict.hero.ingestionUnit}</span>
              </div>
              <div className="text-xs text-white/85 flex justify-between">
                <span>{dict.hero.ingestionSub}</span>
                <span className="text-ice-cyan font-semibold">{dict.hero.ingestionAccuracy}</span>
              </div>
            </div>
            <div className="w-full bg-white/15 h-2 rounded-full mt-3 overflow-hidden">
              <div
                className="bg-gradient-to-r from-ice-cyan to-electric-teal h-full rounded-full"
                style={{ width: '92%' }}
              />
            </div>
          </div>
        </motion.div>

        {/* Settle Toast Notification */}
        {toastMsg && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="mb-4 px-4 py-2 rounded-full bg-emerald-500 text-deep-navy font-bold text-xs shadow-xl flex items-center gap-2"
          >
            <span aria-hidden="true" className="material-symbols-outlined text-[16px]">check_circle</span>
            <span>{toastMsg}</span>
          </motion.div>
        )}

        {/* Ecosystem Availability & Sovereign Guarantees */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.9, delay: 0.5 }}
          className="w-full max-w-4xl py-3.5 px-6 rounded-2xl bg-deep-navy/80 border border-white/20 backdrop-blur-xl flex flex-wrap items-center justify-around gap-4 text-xs font-medium text-white/90 shadow-2xl"
        >
          <div className="flex items-center gap-2">
            <span aria-hidden="true" className="material-symbols-outlined text-electric-teal text-[18px]">
              verified_user
            </span>
            <span>{dict.hero.guarantee1}</span>
          </div>
          <span className="hidden md:inline text-white/30">•</span>
          <div className="flex items-center gap-2">
            <span aria-hidden="true" className="material-symbols-outlined text-ice-cyan text-[18px]">
              qr_code_scanner
            </span>
            <span>{dict.hero.guarantee2}</span>
          </div>
          <span className="hidden md:inline text-white/30">•</span>
          <div className="flex items-center gap-2">
            <span aria-hidden="true" className="material-symbols-outlined text-electric-teal text-[18px]">
              phone_iphone
            </span>
            <span>{dict.hero.guarantee3}</span>
          </div>
        </motion.div>
      </div>
    </section>
  );
};
