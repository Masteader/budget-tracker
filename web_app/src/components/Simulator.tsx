import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import confetti from 'canvas-confetti';
import type { TranslationDictionary } from '../i18n/translations';

interface SimulatorProps {
  dict: TranslationDictionary;
}

export const Simulator: React.FC<SimulatorProps> = ({ dict }) => {
  const [activeTab, setActiveTab] = useState<'salary' | 'ai' | 'zatca' | 'split'>('salary');

  // Tab 1: Salary cycle state
  const [payday, setPayday] = useState<number>(27);
  const remainingDays = 31 - payday > 0 ? 31 - payday : 30;
  const safeDaily = (4350 / (remainingDays || 1)).toFixed(2);

  // Tab 2: AI mock state
  const [aiInput, setAiInput] = useState(
    'Supermarket groceries SAR 350 split equally between me, Majed, and Salman'
  );
  const [aiCat, setAiCat] = useState('Groceries & Household Essentials');
  const [aiTotal, setAiTotal] = useState('350.00');
  const [splitA, setSplitA] = useState('116.66');
  const [splitB, setSplitB] = useState('116.66');
  const [splitC, setSplitC] = useState('116.66');

  const handleAiRun = (textToProcess: string) => {
    const text = textToProcess.toLowerCase();
    if (text.includes('electricity') || text.includes('كهرباء')) {
      setAiCat('Residential Utilities (Electricity)');
      setAiTotal('420.00');
      setSplitA('105.00');
      setSplitB('105.00');
      setSplitC('210.00 (2 rooms)');
    } else if (text.includes('barbecue') || text.includes('dinner') || text.includes('مشاوي')) {
      setAiCat('Hospitality & Shared Dining');
      setAiTotal('1,800.00');
      setSplitA('300.00');
      setSplitB('300.00');
      setSplitC('1,200.00 (Others)');
    } else if (text.includes('internet') || text.includes('fiber') || text.includes('إنترنت')) {
      setAiCat('High-Speed Internet (Telecom)');
      setAiTotal('280.00');
      setSplitA('140.00');
      setSplitB('140.00');
      setSplitC('0.00 (Exempt)');
    } else {
      setAiCat('Groceries & Household Essentials');
      setAiTotal('350.00');
      setSplitA('116.66');
      setSplitB('116.66');
      setSplitC('116.66');
    }
  };

  // Tab 3: ZATCA mock state
  const invoiceDatabase = [
    {
      store: 'Tamimi Markets Co. Ltd',
      vat: '300045981200003',
      sub: '304.35',
      tax: '45.65',
      total: '350.00',
    },
    {
      store: 'Hyper Panda - Narjis Branch Riyadh',
      vat: '310129845300003',
      sub: '182.60',
      tax: '27.40',
      total: '210.00',
    },
    {
      store: 'Al-Dawaa Medical Pharmacies',
      vat: '300587419800003',
      sub: '104.35',
      tax: '15.65',
      total: '120.00',
    },
    {
      store: 'Jarir Bookstore - Olaya Branch',
      vat: '300084729100003',
      sub: '426.09',
      tax: '63.91',
      total: '490.00',
    },
  ];
  const [invoiceIndex, setInvoiceIndex] = useState(0);
  const currentInvoice = invoiceDatabase[invoiceIndex];

  const handleNextZatcaScan = () => {
    setInvoiceIndex((prev) => (prev + 1) % invoiceDatabase.length);
  };

  // Tab 4: Split mode state
  const [splitMode, setSplitMode] = useState<'family' | 'roommates'>('family');
  const [settleSuccess, setSettleSuccess] = useState(false);

  const handleSettleRequest = () => {
    setSettleSuccess(true);
    confetti({
      particleCount: 50,
      spread: 50,
      origin: { y: 0.8 },
      colors: ['#00e5bf', '#008093', '#d4af37'],
    });
    setTimeout(() => setSettleSuccess(false), 4000);
  };

  return (
    <section className="py-20 px-5 lg:px-12 max-w-[1600px] mx-auto relative" id="simulator">
      {/* Section Header */}
      <div className="text-center mb-14">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-[#dcf2f5] text-[#007a87] text-xs font-mono font-semibold border border-[#bce6ec] mb-3 uppercase tracking-wider">
          <span className="material-symbols-outlined text-[16px]">tune</span>
          <span>{dict.simulator.badge}</span>
        </div>
        <h2 className="text-3xl sm:text-4xl font-bold tracking-tight text-[#0c2530]">
          {dict.simulator.title}
        </h2>
        <p className="text-sm sm:text-base text-on-surface-variant max-w-2xl mx-auto mt-3">
          {dict.simulator.subtitle}
        </p>
      </div>

      {/* Main Cockpit Console */}
      <div className="card-arctic rounded-3xl border border-surface-container-highest shadow-xl overflow-hidden bg-white">
        {/* Tab Selector Ribbon */}
        <div className="flex flex-wrap p-2.5 gap-2 bg-white rounded-full mx-auto my-4 max-w-5xl shadow-[0_4px_16px_rgba(0,100,115,0.06)] border border-[#d4ebf0]">
          <button
            onClick={() => setActiveTab('salary')}
            className={`sim-tab-btn flex-1 min-w-[200px] py-3 px-4 rounded-full text-xs sm:text-sm font-semibold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'salary'
                ? 'bg-[#00808c] text-white shadow-md'
                : 'text-on-surface-variant hover:text-primary hover:bg-[#eaf5f7]'
            }`}
          >
            <span className="material-symbols-outlined text-[18px]">calendar_month</span>
            <span>{dict.simulator.tabSalary}</span>
          </button>
          <button
            onClick={() => setActiveTab('ai')}
            className={`sim-tab-btn flex-1 min-w-[200px] py-3 px-4 rounded-full text-xs sm:text-sm font-semibold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'ai'
                ? 'bg-[#00808c] text-white shadow-md'
                : 'text-on-surface-variant hover:text-primary hover:bg-[#eaf5f7]'
            }`}
          >
            <span className="material-symbols-outlined text-[18px]">smart_toy</span>
            <span>{dict.simulator.tabAi}</span>
          </button>
          <button
            onClick={() => setActiveTab('zatca')}
            className={`sim-tab-btn flex-1 min-w-[200px] py-3 px-4 rounded-full text-xs sm:text-sm font-semibold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'zatca'
                ? 'bg-[#00808c] text-white shadow-md'
                : 'text-on-surface-variant hover:text-primary hover:bg-[#eaf5f7]'
            }`}
          >
            <span className="material-symbols-outlined text-[18px]">qr_code_scanner</span>
            <span>{dict.simulator.tabZatca}</span>
          </button>
          <button
            onClick={() => setActiveTab('split')}
            className={`sim-tab-btn flex-1 min-w-[200px] py-3 px-4 rounded-full text-xs sm:text-sm font-semibold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'split'
                ? 'bg-[#00808c] text-white shadow-md'
                : 'text-on-surface-variant hover:text-primary hover:bg-[#eaf5f7]'
            }`}
          >
            <span className="material-symbols-outlined text-[18px]">group_work</span>
            <span>{dict.simulator.tabSplit}</span>
          </button>
        </div>

        {/* Simulator Panels Canvas */}
        <div className="p-6 lg:p-12 bg-[#f7fcfe] rounded-3xl m-3 lg:m-4 border border-[#e0f2f5]">
          <AnimatePresence mode="wait">
            {/* TAB 1: Flexible Salary Cycle */}
            {activeTab === 'salary' && (
              <motion.div
                key="salary"
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -15 }}
                transition={{ duration: 0.3 }}
                className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center text-start"
              >
                <div className="lg:col-span-5 space-y-5">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#e3f7fa] text-[#00808c] text-xs font-mono font-medium border border-[#bce6ec] uppercase tracking-wider">
                    <span className="material-symbols-outlined text-[14px]">tune</span>
                    <span>{dict.simulator.salaryPill}</span>
                  </div>
                  <h3 className="text-2xl font-bold text-[#0c2530] tracking-tight">
                    {dict.simulator.salaryTitle}
                  </h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    {dict.simulator.salaryDesc}
                  </p>

                  {/* Interactive Slider */}
                  <div className="p-5 rounded-2xl bg-white border border-[#d4ebf0] space-y-3 shadow-sm">
                    <div className="flex justify-between items-center">
                      <label className="text-xs font-semibold text-slate-700 uppercase font-mono tracking-wider">
                        {dict.simulator.disbursementLabel}
                      </label>
                      <span className="text-base font-mono font-bold text-[#00808c]">
                        {dict.simulator.disbursementDay.replace('{val}', payday.toString())}
                      </span>
                    </div>
                    <input
                      type="range"
                      min="1"
                      max="31"
                      value={payday}
                      onChange={(e) => setPayday(parseInt(e.target.value, 10))}
                      className="w-full accent-[#00808c] cursor-pointer h-2 bg-slate-200 rounded-lg"
                    />
                    <div className="flex justify-between text-[10px] font-mono text-slate-500">
                      <span>{dict.simulator.day1Label}</span>
                      <span>{dict.simulator.day15Label}</span>
                      <span className="text-[#00808c] font-bold">{dict.simulator.day27Label}</span>
                      <span>{dict.simulator.day31Label}</span>
                    </div>
                  </div>

                  {/* Automated 15% Reserve Buffer */}
                  <div className="p-4 rounded-2xl bg-white border border-emerald-400/40 flex items-center justify-between shadow-sm">
                    <div>
                      <div className="text-xs text-slate-500 font-medium">
                        {dict.simulator.reserveTitle}
                      </div>
                      <div className="text-xl font-bold font-mono text-emerald-700 mt-0.5">
                        {dict.simulator.reserveVal}{' '}
                        <span className="text-xs text-slate-400 font-normal">
                          {dict.simulator.reserveSub}
                        </span>
                      </div>
                    </div>
                    <span className="material-symbols-outlined text-emerald-600 text-[28px]">
                      savings
                    </span>
                  </div>
                </div>

                {/* Visual Metrics Panel */}
                <div className="lg:col-span-7 grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {/* Metric 1: Safe Burn Rate */}
                  <div className="p-6 rounded-2xl bg-white border border-[#d4ebf0] relative overflow-hidden shadow-sm">
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <span className="text-xs text-slate-400 uppercase font-mono tracking-wider block">
                          {dict.simulator.burnRateTitle}
                        </span>
                        <span className="text-sm font-semibold text-[#0c2530]">
                          {dict.simulator.burnRateSub}
                        </span>
                      </div>
                      <span className="p-2 rounded-lg bg-[#eaf5f7] text-[#00808c]">
                        <span className="material-symbols-outlined text-[20px]">speed</span>
                      </span>
                    </div>
                    <div className="text-3xl font-bold font-mono text-[#00808c] mb-1">
                      {safeDaily} ر.س{' '}
                      <span className="text-xs font-normal text-slate-400">/ يومياً</span>
                    </div>
                    <p className="text-xs text-emerald-700 flex items-center gap-1.5 mt-2">
                      <span className="material-symbols-outlined text-[14px]">check_circle</span>
                      <span>{dict.simulator.burnRateOptimal}</span>
                    </p>
                    <div className="w-full bg-slate-100 h-2 rounded-full mt-4 overflow-hidden">
                      <div
                        className="bg-gradient-to-r from-[#00808c] to-emerald-500 h-full rounded-full transition-all duration-300"
                        style={{ width: `${Math.min(100, Math.max(20, (145 / parseFloat(safeDaily)) * 50))}%` }}
                      />
                    </div>
                  </div>

                  {/* Metric 2: Days Left */}
                  <div className="p-6 rounded-2xl bg-white border border-[#d4ebf0] relative overflow-hidden shadow-sm">
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <span className="text-xs text-slate-400 uppercase font-mono tracking-wider block">
                          {dict.simulator.countdownTitle}
                        </span>
                        <span className="text-sm font-semibold text-[#0c2530]">
                          {dict.simulator.countdownSub}
                        </span>
                      </div>
                      <span className="p-2 rounded-lg bg-[#eaf5f7] text-emerald-700">
                        <span className="material-symbols-outlined text-[20px]">hourglass_top</span>
                      </span>
                    </div>
                    <div className="text-3xl font-bold font-mono text-[#0c2530] mb-1">
                      {remainingDays}{' '}
                      <span className="text-sm font-normal text-slate-400">
                        {dict.simulator.countdownDays.replace('{val}', '')}
                      </span>
                    </div>
                    <p className="text-xs text-slate-600 mt-2">
                      المتبقي المتاح:{' '}
                      <strong className="text-[#00808c] font-mono font-semibold">
                        4,350.00 ر.س
                      </strong>
                    </p>
                    <div className="w-full bg-slate-100 h-2 rounded-full mt-4 overflow-hidden">
                      <div
                        className="bg-emerald-600 h-full rounded-full transition-all duration-300"
                        style={{ width: `${(remainingDays / 31) * 100}%` }}
                      />
                    </div>
                  </div>

                  {/* Breakdown Pool Row */}
                  <div className="sm:col-span-2 p-5 rounded-2xl bg-white border border-[#d4ebf0] flex flex-col md:flex-row justify-between items-center gap-4 shadow-sm">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-lg bg-[#eaf5f7] flex items-center justify-center text-[#00808c] shadow-sm">
                        <span className="material-symbols-outlined text-[22px]">
                          account_balance_wallet
                        </span>
                      </div>
                      <div>
                        <div className="text-sm font-semibold text-[#0c2530]">
                          {dict.simulator.poolLabel} {dict.simulator.poolVal}
                        </div>
                        <div className="text-xs text-slate-500">{dict.simulator.poolDesc}</div>
                      </div>
                    </div>
                    <span className="px-3 py-1 rounded-full text-xs font-mono font-semibold bg-emerald-50 text-emerald-800 border border-emerald-300">
                      {dict.simulator.healthTag}
                    </span>
                  </div>
                </div>
              </motion.div>
            )}

            {/* TAB 2: AI Natural Language Engine */}
            {activeTab === 'ai' && (
              <motion.div
                key="ai"
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -15 }}
                transition={{ duration: 0.3 }}
                className="grid grid-cols-1 lg:grid-cols-12 gap-8 text-start"
              >
                <div className="lg:col-span-6 space-y-5">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-50 text-emerald-800 text-xs font-mono font-medium border border-emerald-300 uppercase tracking-wider">
                    <span className="material-symbols-outlined text-[14px]">mic</span>
                    <span>{dict.simulator.aiPill}</span>
                  </div>
                  <h3 className="text-2xl font-bold text-[#0c2530] tracking-tight">
                    {dict.simulator.aiTitle}
                  </h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    {dict.simulator.aiDesc}
                  </p>

                  {/* Interactive Prompt Box */}
                  <div className="p-5 rounded-2xl bg-white border border-[#d4ebf0] space-y-3 shadow-sm">
                    <label className="text-xs font-semibold text-[#00808c] uppercase font-mono tracking-wider flex items-center gap-1.5">
                      <span className="material-symbols-outlined text-[16px]">chat</span>
                      <span>{dict.simulator.aiPromptLabel}</span>
                    </label>
                    <div className="flex gap-2">
                      <input
                        type="text"
                        value={aiInput}
                        onChange={(e) => setAiInput(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleAiRun(aiInput)}
                        className="w-full bg-[#f8fdff] border border-slate-300 rounded-xl p-3 text-sm text-[#0c2530] focus:border-[#00808c] focus:ring-1 focus:ring-[#00808c] outline-none"
                      />
                      <button
                        onClick={() => handleAiRun(aiInput)}
                        className="px-5 py-3 bg-gradient-to-r from-[#00808c] to-[#006575] text-white rounded-xl font-bold hover:brightness-110 active:scale-95 transition-all flex items-center justify-center shadow"
                      >
                        <span className="material-symbols-outlined text-[18px]">send</span>
                      </button>
                    </div>
                    {/* Fast Presets */}
                    <div className="flex flex-wrap gap-2 text-xs pt-1">
                      {dict.simulator.aiPresets.map((preset, idx) => (
                        <button
                          key={idx}
                          onClick={() => {
                            setAiInput(preset);
                            handleAiRun(preset);
                          }}
                          className="px-3 py-1.5 rounded-lg bg-[#eaf5f7] hover:bg-[#d8edf1] text-[#006575] font-medium transition-colors text-start"
                        >
                          "{preset}"
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                {/* AI Extraction Preview Card */}
                <div className="lg:col-span-6">
                  <div className="p-6 rounded-2xl bg-white border border-[#d4ebf0] space-y-4 shadow-sm">
                    <div className="flex items-center justify-between border-b border-slate-100 pb-3">
                      <div className="flex items-center gap-2">
                        <div className="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-ping" />
                        <span className="text-sm font-bold text-[#0c2530]">
                          {dict.simulator.aiStatus}
                        </span>
                      </div>
                      <span className="px-2.5 py-0.5 rounded-full text-xs font-mono bg-emerald-50 text-emerald-800 border border-emerald-300">
                        {dict.simulator.aiPrecision}
                      </span>
                    </div>

                    <div className="grid grid-cols-2 gap-3 text-xs">
                      <div className="p-3.5 rounded-xl bg-[#f8fdff] border border-slate-200">
                        <span className="text-slate-400 block uppercase font-mono tracking-wider">
                          {dict.simulator.aiCatLabel}
                        </span>
                        <span className="text-sm font-semibold text-[#0c2530] mt-1 block">
                          {aiCat}
                        </span>
                      </div>
                      <div className="p-3.5 rounded-xl bg-[#f8fdff] border border-slate-200">
                        <span className="text-slate-400 block uppercase font-mono tracking-wider">
                          {dict.simulator.aiTotalLabel}
                        </span>
                        <span className="text-base font-bold font-mono text-[#00808c] mt-1 block">
                          {aiTotal} ر.س
                        </span>
                      </div>
                    </div>

                    {/* Ledger Distribution */}
                    <div className="p-4 rounded-xl bg-[#f8fdff] border border-slate-200 space-y-2">
                      <div className="text-xs font-semibold text-slate-500 uppercase font-mono tracking-wider">
                        {dict.simulator.aiLedgerLabel}
                      </div>
                      <div className="grid grid-cols-3 gap-2 text-center text-xs">
                        <div className="p-2.5 rounded-xl bg-white border border-slate-100">
                          <span className="block text-slate-400 text-[10px] uppercase font-bold">
                            {dict.simulator.aiPayer}
                          </span>
                          <span className="text-[#00808c] font-bold font-mono text-sm block mt-0.5">
                            {splitA} ر.س
                          </span>
                        </div>
                        <div className="p-2.5 rounded-xl bg-white border border-slate-100">
                          <span className="block text-slate-400 text-[10px] uppercase font-bold">
                            {dict.simulator.aiDebtor1}
                          </span>
                          <span className="text-emerald-700 font-bold font-mono text-sm block mt-0.5">
                            {splitB} ر.س
                          </span>
                        </div>
                        <div className="p-2.5 rounded-xl bg-white border border-slate-100">
                          <span className="block text-slate-400 text-[10px] uppercase font-bold">
                            {dict.simulator.aiDebtor2}
                          </span>
                          <span className="text-emerald-700 font-bold font-mono text-sm block mt-0.5">
                            {splitC} ر.س
                          </span>
                        </div>
                      </div>
                    </div>

                    {/* Category Health Impact */}
                    <div className="p-3 rounded-xl bg-[#eaf5f7] border border-[#d4ebf0] flex items-center justify-between text-xs">
                      <div className="flex items-center gap-2 text-slate-600">
                        <span className="material-symbols-outlined text-[#00808c] text-[18px]">
                          info
                        </span>
                        <span>{dict.simulator.aiImpactLabel}</span>
                      </div>
                      <span className="text-emerald-700 font-semibold font-mono">
                        {dict.simulator.aiImpactVal}
                      </span>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}

            {/* TAB 3: ZATCA QR Scanner */}
            {activeTab === 'zatca' && (
              <motion.div
                key="zatca"
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -15 }}
                transition={{ duration: 0.3 }}
                className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center text-start"
              >
                <div className="lg:col-span-5 space-y-5">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#e3f7fa] text-[#00808c] text-xs font-mono font-medium border border-[#bce6ec] uppercase tracking-wider">
                    <span className="material-symbols-outlined text-[14px]">document_scanner</span>
                    <span>{dict.simulator.zatcaPill}</span>
                  </div>
                  <h3 className="text-2xl font-bold text-[#0c2530] tracking-tight">
                    {dict.simulator.zatcaTitle}
                  </h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    {dict.simulator.zatcaDesc}
                  </p>
                  <div>
                    <button
                      onClick={handleNextZatcaScan}
                      className="px-6 py-3.5 rounded-xl bg-gradient-to-r from-[#00808c] via-[#006575] to-emerald-700 text-white font-bold text-sm flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all shadow-md"
                    >
                      <span className="material-symbols-outlined text-[20px]">
                        center_focus_strong
                      </span>
                      <span>{dict.simulator.zatcaBtn}</span>
                    </button>
                  </div>
                </div>

                {/* Scanned Invoice Preview Card */}
                <div className="lg:col-span-7">
                  <div className="p-6 rounded-2xl bg-white border border-[#d4ebf0] space-y-4 shadow-sm">
                    <div className="flex justify-between items-start border-b border-slate-100 pb-4">
                      <div>
                        <span className="text-xs font-mono text-emerald-700 font-semibold block">
                          {dict.simulator.zatcaBadge}
                        </span>
                        <h4 className="text-lg font-bold text-[#0c2530] mt-1">
                          {currentInvoice.store}
                        </h4>
                        <p className="text-xs text-slate-400 font-mono mt-0.5">
                          VAT ID: {currentInvoice.vat}
                        </p>
                      </div>
                      <div className="w-14 h-14 bg-[#eaf5f7] p-1 rounded-xl flex items-center justify-center text-[#00808c] shadow border border-[#d4ebf0]">
                        <span className="material-symbols-outlined text-[42px]">qr_code_2</span>
                      </div>
                    </div>

                    <div className="space-y-2.5 text-xs">
                      <div className="flex justify-between py-1.5 border-b border-slate-100">
                        <span className="text-slate-500">{dict.simulator.zatcaNet}</span>
                        <span className="font-bold font-mono text-[#0c2530]">
                          {currentInvoice.sub} ر.س
                        </span>
                      </div>
                      <div className="flex justify-between py-1.5 border-b border-slate-100">
                        <span className="text-slate-500">{dict.simulator.zatcaTax}</span>
                        <span className="font-bold font-mono text-[#00808c]">
                          {currentInvoice.tax} ر.س
                        </span>
                      </div>
                      <div className="flex justify-between py-2 text-sm bg-[#f8fdff] px-3 rounded-lg">
                        <span className="font-bold text-[#0c2530]">
                          {dict.simulator.zatcaGrand}
                        </span>
                        <span className="font-bold font-mono text-emerald-700">
                          {currentInvoice.total} ر.س
                        </span>
                      </div>
                    </div>

                    <div className="p-3 rounded-xl bg-emerald-50 border border-emerald-200 flex items-center justify-between text-xs">
                      <span className="text-slate-600">حالة التحقق:</span>
                      <span className="inline-flex items-center gap-1.5 text-emerald-800 font-semibold font-mono">
                        <span className="material-symbols-outlined text-[16px]">verified</span>
                        <span>{dict.simulator.zatcaVerified}</span>
                      </span>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}

            {/* TAB 4: Fair Shared Expense Ledger */}
            {activeTab === 'split' && (
              <motion.div
                key="split"
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -15 }}
                transition={{ duration: 0.3 }}
                className="grid grid-cols-1 lg:grid-cols-12 gap-8 text-start"
              >
                <div className="lg:col-span-5 space-y-5">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-50 text-emerald-800 text-xs font-mono font-medium border border-emerald-300 uppercase tracking-wider">
                    <span className="material-symbols-outlined text-[14px]">balance</span>
                    <span>{dict.simulator.splitPill}</span>
                  </div>
                  <h3 className="text-2xl font-bold text-[#0c2530] tracking-tight">
                    {dict.simulator.splitTitle}
                  </h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    {dict.simulator.splitDesc}
                  </p>

                  {/* Mode Toggle Buttons */}
                  <div className="flex rounded-xl bg-white p-1 border border-[#d4ebf0] shadow-sm">
                    <button
                      onClick={() => setSplitMode('family')}
                      className={`flex-1 py-2.5 rounded-lg text-xs font-bold transition-all ${
                        splitMode === 'family'
                          ? 'bg-[#00808c] text-white shadow'
                          : 'text-slate-600 hover:text-[#00808c]'
                      }`}
                    >
                      {dict.simulator.splitModeFamily}
                    </button>
                    <button
                      onClick={() => setSplitMode('roommates')}
                      className={`flex-1 py-2.5 rounded-lg text-xs font-bold transition-all ${
                        splitMode === 'roommates'
                          ? 'bg-emerald-700 text-white shadow'
                          : 'text-slate-600 hover:text-emerald-700'
                      }`}
                    >
                      {dict.simulator.splitModeRoommates}
                    </button>
                  </div>
                </div>

                {/* Dynamic Ledger Simulation Table */}
                <div className="lg:col-span-7">
                  <div className="p-6 rounded-2xl bg-white border border-[#d4ebf0] space-y-4 shadow-sm">
                    <div className="flex justify-between items-center border-b border-slate-100 pb-3">
                      <span className="text-sm font-bold text-[#0c2530]">
                        {splitMode === 'family'
                          ? dict.simulator.splitLedgerTitleFamily
                          : dict.simulator.splitLedgerTitleRoommates}
                      </span>
                      <span className="text-xs text-emerald-700 font-mono font-semibold">
                        {dict.simulator.splitLiveBadge}
                      </span>
                    </div>

                    {splitMode === 'family' ? (
                      <div className="space-y-2.5 text-xs">
                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-[#00808c] shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">
                              أبو فهد (المصروف العام للأسرة)
                            </span>
                            <span className="text-slate-500 text-[11px]">
                              المدفوع: الإيجار السنوي، الفواتير، ومصاريف المدرسة
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-[#00808c] font-bold font-mono text-sm block">
                              4,800.00 ر.س
                            </span>
                            <span className="text-[10px] text-emerald-700 font-semibold">
                              مغطى بالكامل
                            </span>
                          </div>
                        </div>

                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-emerald-500 shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">
                              أم فهد (التموينات ومستلزمات البيت)
                            </span>
                            <span className="text-slate-500 text-[11px]">
                              المدفوع: مقاضي بنده، تموينات الأسبوع
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-emerald-700 font-bold font-mono text-sm block">
                              1,600.00 ر.س
                            </span>
                            <span className="text-[10px] text-emerald-700 font-semibold">
                              تكامل الميزانية 100%
                            </span>
                          </div>
                        </div>

                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-amber-500 shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">
                              صندوق طوارئ واستثمار الأسرة
                            </span>
                            <span className="text-slate-500 text-[11px]">
                              الرصيد التراكمي المحمي للطوارئ الطبية والمدرسية
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-amber-700 font-bold font-mono text-sm block">
                              8,500.00 ر.س
                            </span>
                            <span className="text-[10px] text-amber-700 font-semibold">
                              حساب محمي
                            </span>
                          </div>
                        </div>
                      </div>
                    ) : (
                      <div className="space-y-2.5 text-xs">
                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-[#00808c] shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">أحمد (أنت)</span>
                            <span className="text-slate-500 text-[11px]">
                              دفع: كهرباء الشقة، فايبر الإنترنت، مقاضي الشهر
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-emerald-700 font-bold font-mono text-sm block">
                              +420.00 ر.س
                            </span>
                            <span className="text-[10px] text-emerald-700 uppercase font-mono font-bold">
                              دائن مستحق
                            </span>
                          </div>
                        </div>

                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-rose-400 shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">ماجد العبدالله</span>
                            <span className="text-slate-500 text-[11px]">
                              دفع: صيانة التكييف وفلاتر المياه
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-rose-600 font-bold font-mono text-sm block">
                              -180.00 ر.س
                            </span>
                            <span className="text-[10px] text-rose-600 uppercase font-mono font-bold">
                              مدين
                            </span>
                          </div>
                        </div>

                        <div className="p-3.5 rounded-xl bg-[#f8fdff] flex items-center justify-between border-s-4 border-rose-400 shadow-sm">
                          <div>
                            <span className="font-bold text-[#0c2530] block">سلمان الفهد</span>
                            <span className="text-slate-500 text-[11px]">
                              دفع: تعبئة أسطوانة غاز المطبخ
                            </span>
                          </div>
                          <div className="text-end">
                            <span className="text-rose-600 font-bold font-mono text-sm block">
                              -240.00 ر.س
                            </span>
                            <span className="text-[10px] text-rose-600 uppercase font-mono font-bold">
                              مدين
                            </span>
                          </div>
                        </div>
                      </div>
                    )}

                    <div className="p-4 rounded-xl bg-[#f8fdff] border border-[#d4ebf0] flex flex-col sm:flex-row justify-between items-center gap-3 shadow-sm">
                      <div>
                        <div className="text-xs font-semibold text-[#0c2530]">
                          {dict.simulator.splitResolutionTitle}
                        </div>
                        <div className="text-[11px] text-slate-500">
                          {dict.simulator.splitResolutionDesc}
                        </div>
                      </div>
                      <button
                        onClick={handleSettleRequest}
                        className="px-4 py-2.5 rounded-lg bg-[#00808c] text-white text-xs font-bold hover:brightness-110 active:scale-95 transition-all shadow-sm whitespace-nowrap"
                      >
                        {settleSuccess ? 'تم إرسال الطلب بنجاح ✓' : dict.simulator.splitSettleBtn}
                      </button>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </section>
  );
};
