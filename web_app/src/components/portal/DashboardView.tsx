import React, { useEffect, useState } from 'react';
import { useAuth } from '../../context/useAuth';
import type { TranslationDictionary, Language } from '../../i18n/translations';
import { supabase } from '../../lib/supabaseClient';
import {
  riyadhToday,
  cycleFor,
  formatDayMonth,
  formatSAR,
  currentCycleKey,
} from '../../lib/cycleUtils';
import type { PortalTab } from './PortalHeader';

interface DashboardViewProps {
  dict: TranslationDictionary;
  lang: Language;
  onNavigateTab: (tab: PortalTab) => void;
}

interface InstallmentPlanItem {
  id: string;
  merchant: string;
  provider: string;
  monthly_amount: number;
  total_amount: number;
  installment_count: number;
  paid_installments: number;
  day_of_month: number;
  status: string;
}

interface TransactionItem {
  id: string;
  amount: number;
  description?: string;
  category_code?: string;
  timestamp: string;
}

interface RecurringBillItem {
  name: string;
  provider: string;
  amount: number;
  dueDay: number;
  status: 'paid' | 'due';
}

export const DashboardView: React.FC<DashboardViewProps> = ({
  dict,
  lang,
  onNavigateTab,
}) => {
  const { household, householdId } = useAuth();
  const [loading, setLoading] = useState(true);
  const [income, setIncome] = useState(0);
  const [totalSpent, setTotalSpent] = useState(0);
  const [installments, setInstallments] = useState<InstallmentPlanItem[]>([]);
  const [recentTxs, setRecentTxs] = useState<TransactionItem[]>([]);

  const paydayDay = household?.paydayDay || 27;
  const today = riyadhToday();
  const cycleInfo = cycleFor(today, paydayDay);
  const cycleKey = currentCycleKey(paydayDay);

  useEffect(() => {
    let ignore = false;
    const run = async () => {
      if (!householdId) {
        setLoading(false);
        return;
      }
      try {
        const { data: incomeData } = await supabase
          .from('income_records')
          .select('net_amount')
          .eq('household_id', householdId)
          .eq('cycle_key', cycleKey);

        let calcIncome = 0;
        if (incomeData && incomeData.length > 0) {
          calcIncome = incomeData.reduce((acc, row) => acc + Number(row.net_amount || 0), 0);
        } else {
          const { data: houseData } = await supabase
            .from('households')
            .select('monthly_income')
            .eq('id', householdId)
            .maybeSingle();
          calcIncome = Number(houseData?.monthly_income || 15000);
        }
        if (!ignore) setIncome(calcIncome);

        const { data: txsData } = await supabase
          .from('transactions')
          .select('id, amount, description, category_code, timestamp, cycle_key')
          .eq('household_id', householdId)
          .order('timestamp', { ascending: false });

        if (!ignore && txsData) {
          const cycleTxs = txsData.filter(
            (t) => !t.cycle_key || t.cycle_key === cycleKey
          );
          const spent = cycleTxs.reduce((acc, t) => acc + Number(t.amount || 0), 0);
          setTotalSpent(spent);
          setRecentTxs(txsData.slice(0, 5));
        }

        const { data: plansData } = await supabase
          .from('installment_plans')
          .select('*')
          .eq('household_id', householdId)
          .eq('status', 'ACTIVE')
          .order('created_at', { ascending: false });

        if (!ignore && plansData) {
          setInstallments(plansData);
        }
      } catch {
        if (!ignore) {
          setIncome(15000);
          setTotalSpent(4250);
        }
      } finally {
        if (!ignore) setLoading(false);
      }
    };
    run();
    return () => {
      ignore = true;
    };
  }, [householdId, cycleKey]);

  const netBalance = income - totalSpent;
  const cyclePercent = Math.min(100, Math.round((cycleInfo.elapsed / cycleInfo.length) * 100));

  // Essential Saudi household recurring bills
  const recurringBills: RecurringBillItem[] = [
    { name: lang === 'ar' ? 'فاتورة الكهرباء (SEC)' : 'Electricity (SEC)', provider: 'SEC', amount: 380, dueDay: 28, status: 'due' },
    { name: lang === 'ar' ? 'الإنترنت المنزلي فايبر (STC)' : 'Fiber Home Internet (STC)', provider: 'stc', amount: 287.5, dueDay: 1, status: 'paid' },
    { name: lang === 'ar' ? 'المياه الوطنية (NWC)' : 'National Water (NWC)', provider: 'NWC', amount: 95, dueDay: 15, status: 'due' },
    { name: lang === 'ar' ? 'إيجار الشقة السكني' : 'Housing Rent Installment', provider: 'Ejar', amount: 2500, dueDay: 27, status: 'due' },
  ];

  return (
    <div className="space-y-6">
      {/* Payday Countdown HUD Card */}
      <div className="rounded-3xl bg-gradient-to-br from-teal-soft/80 via-white to-teal-soft/40 border border-teal/20 p-6 sm:p-8 shadow-sm">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-teal/10 text-teal-dark font-bold text-xs mb-3">
              <span className="w-2 h-2 rounded-full bg-teal animate-pulse" />
              <span>{dict.portal.cycleEndsIn}</span>
            </div>
            <div className="flex items-baseline gap-3">
              <span className="text-4xl sm:text-5xl font-black text-ink font-mono">
                {cycleInfo.daysLeft}
              </span>
              <span className="text-xl sm:text-2xl font-bold text-muted">
                {dict.portal.days}
              </span>
            </div>
            <p className="text-xs sm:text-sm text-muted mt-2">
              {lang === 'ar'
                ? `دورة الراتب: من ${formatDayMonth(cycleInfo.start, 'ar-SA')} إلى ${formatDayMonth(cycleInfo.nextPayday, 'ar-SA')}`
                : `Salary cycle: from ${formatDayMonth(cycleInfo.start, 'en-US')} to ${formatDayMonth(cycleInfo.nextPayday, 'en-US')}`}
            </p>
          </div>

          <div className="w-full md:w-72 bg-white/80 p-4 rounded-2xl border border-line/80 shadow-sm">
            <div className="flex justify-between text-xs font-bold text-muted mb-2">
              <span>{lang === 'ar' ? 'انقضى من الدورة' : 'Cycle Elapsed'}</span>
              <span className="font-mono text-teal-dark">{cyclePercent}%</span>
            </div>
            <div className="w-full h-3 bg-teal-soft rounded-full overflow-hidden">
              <div
                className="h-full bg-teal rounded-full transition-all duration-700 ease-out"
                style={{ width: `${cyclePercent}%` }}
              />
            </div>
            <div className="flex justify-between text-[11px] text-muted/80 mt-2 font-mono">
              <span>{cycleInfo.elapsed} {lang === 'ar' ? 'يوم' : 'days'}</span>
              <span>{cycleInfo.length} {lang === 'ar' ? 'يوم' : 'days total'}</span>
            </div>
          </div>
        </div>
      </div>

      {/* 3 Core Balances Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 sm:gap-6">
        {/* Net Remaining Balance */}
        <div className="rounded-3xl bg-white border border-line p-6 shadow-sm hover:border-teal/30 transition-all">
          <div className="flex items-center justify-between text-muted text-xs font-bold mb-2">
            <span>{dict.portal.totalBalance}</span>
            <div className="w-8 h-8 rounded-xl bg-teal-soft text-teal flex items-center justify-center">
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
              </svg>
            </div>
          </div>
          <div className="text-2xl sm:text-3xl font-black text-teal font-mono">
            {formatSAR(netBalance)}
          </div>
          <span className="inline-block mt-2 text-[11px] text-muted">
            {lang === 'ar' ? 'المتبقي حتى إيداع الراتب القادم' : 'Available until next salary deposit'}
          </span>
        </div>

        {/* Total Monthly Income */}
        <div className="rounded-3xl bg-white border border-line p-6 shadow-sm hover:border-line/80 transition-all">
          <div className="flex items-center justify-between text-muted text-xs font-bold mb-2">
            <span>{dict.portal.totalIncome}</span>
            <div className="w-8 h-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center">
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M12 19V5M5 12l7-7 7 7" />
              </svg>
            </div>
          </div>
          <div className="text-2xl sm:text-3xl font-black text-ink font-mono">
            {formatSAR(income)}
          </div>
          <span className="inline-block mt-2 text-[11px] text-muted">
            {lang === 'ar' ? 'الرواتب والدخول المعتمدة للدورة' : 'Salaries & verified cycle revenues'}
          </span>
        </div>

        {/* Total Cycle Spent */}
        <div className="rounded-3xl bg-white border border-line p-6 shadow-sm hover:border-line/80 transition-all">
          <div className="flex items-center justify-between text-muted text-xs font-bold mb-2">
            <span>{dict.portal.totalSpent}</span>
            <div className="w-8 h-8 rounded-xl bg-rose-50 text-rose-600 flex items-center justify-center">
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M12 5v14M5 12l7 7 7-7" />
              </svg>
            </div>
          </div>
          <div className="text-2xl sm:text-3xl font-black text-ink font-mono">
            {formatSAR(totalSpent)}
          </div>
          <span className="inline-block mt-2 text-[11px] text-muted">
            {lang === 'ar' ? 'المصروف الفعلي المسجل' : 'Actual logged expenses'}
          </span>
        </div>
      </div>

      {/* Two Column Section: Left = Installments & Bills; Right = Recent Transactions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Left Column: Installments + Recurring Bills */}
        <div className="space-y-6">
          {/* Active Installments Card (BNPL / Banks) */}
          <div className="rounded-3xl bg-white border border-line p-6 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-sand-soft text-sand-ink flex items-center justify-center">
                  <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <rect x="2" y="5" width="20" height="14" rx="2" />
                    <line x1="2" y1="10" x2="22" y2="10" />
                  </svg>
                </div>
                <h3 className="font-bold text-ink text-sm sm:text-base">
                  {dict.portal.installmentsTitle}
                </h3>
              </div>
              <span className="text-xs px-2.5 py-1 rounded-full bg-sand-soft text-sand-ink font-bold">
                {installments.length} {dict.portal.activePlans}
              </span>
            </div>

            {installments.length === 0 ? (
              <div className="py-6 text-center text-xs text-muted">
                {lang === 'ar'
                  ? 'لا توجد خطط أقساط أو تابي/تمارا نشطة حالياً.'
                  : 'No active BNPL or installment plans at this time.'}
              </div>
            ) : (
              <div className="space-y-3">
                {installments.map((plan) => (
                  <div
                    key={plan.id}
                    className="flex items-center justify-between p-3.5 rounded-2xl border border-line/70 bg-bg/50 hover:bg-bg transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <span
                        className={`text-xs font-bold px-2 py-1 rounded-lg ${
                          plan.provider.toLowerCase().includes('tamara')
                            ? 'bg-orange-100 text-orange-800'
                            : plan.provider.toLowerCase().includes('tabby')
                            ? 'bg-emerald-100 text-emerald-800'
                            : 'bg-blue-100 text-blue-800'
                        }`}
                      >
                        {plan.provider}
                      </span>
                      <div>
                        <div className="text-sm font-bold text-ink">{plan.merchant}</div>
                        <div className="text-xs text-muted">
                          {lang === 'ar'
                            ? `القسط ${plan.paid_installments} من ${plan.installment_count} · يستحق في ${plan.day_of_month}`
                            : `Installment ${plan.paid_installments} of ${plan.installment_count} · Due on ${plan.day_of_month}`}
                        </div>
                      </div>
                    </div>
                    <div className="text-right rtl:text-left font-mono text-sm font-bold text-ink">
                      {formatSAR(plan.monthly_amount)}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Upcoming Recurring Bills */}
          <div className="rounded-3xl bg-white border border-line p-6 shadow-sm">
            <div className="flex items-center gap-2 mb-4">
              <div className="w-8 h-8 rounded-xl bg-teal-soft text-teal flex items-center justify-center">
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                  <polyline points="14 2 14 8 20 8" />
                  <line x1="16" y1="13" x2="8" y2="13" />
                  <line x1="16" y1="17" x2="8" y2="17" />
                </svg>
              </div>
              <h3 className="font-bold text-ink text-sm sm:text-base">
                {dict.portal.recurringBillsTitle}
              </h3>
            </div>

            <div className="space-y-3">
              {recurringBills.map((bill, idx) => (
                <div
                  key={idx}
                  className="flex items-center justify-between p-3.5 rounded-2xl border border-line/70 bg-bg/50 hover:bg-bg transition-colors"
                >
                  <div className="flex items-center gap-3">
                    <span
                      className={`text-[11px] font-bold px-2 py-0.5 rounded-md ${
                        bill.status === 'paid'
                          ? 'bg-emerald-100 text-emerald-800'
                          : 'bg-amber-100 text-amber-800'
                      }`}
                    >
                      {bill.status === 'paid'
                        ? (lang === 'ar' ? 'مسددة' : 'Paid')
                        : (lang === 'ar' ? 'مستحقة' : 'Due')}
                    </span>
                    <div>
                      <div className="text-sm font-bold text-ink">{bill.name}</div>
                      <div className="text-xs text-muted">
                        {lang === 'ar'
                          ? `يوم الاستحقاق: ${bill.dueDay} من الشهر`
                          : `Due on day ${bill.dueDay}`}
                      </div>
                    </div>
                  </div>
                  <div className="text-right rtl:text-left font-mono text-sm font-bold text-ink">
                    {formatSAR(bill.amount)}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Right Column: Recent Transactions Preview */}
        <div className="rounded-3xl bg-white border border-line p-6 shadow-sm flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-teal-soft text-teal flex items-center justify-center">
                  <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
                  </svg>
                </div>
                <h3 className="font-bold text-ink text-sm sm:text-base">
                  {dict.portal.recentTransactions}
                </h3>
              </div>
              <button
                type="button"
                onClick={() => onNavigateTab('transactions')}
                className="text-xs font-bold text-teal hover:text-teal-dark transition-colors"
              >
                {dict.portal.viewAll} →
              </button>
            </div>

            {loading ? (
              <div className="py-12 text-center text-xs text-muted">
                {dict.auth.loading}
              </div>
            ) : recentTxs.length === 0 ? (
              <div className="py-12 text-center text-xs text-muted">
                {dict.portal.noData}
              </div>
            ) : (
              <div className="space-y-3">
                {recentTxs.map((tx) => (
                  <div
                    key={tx.id}
                    className="flex items-center justify-between p-3.5 rounded-2xl border border-line/60 hover:border-line transition-all"
                  >
                    <div>
                      <div className="text-sm font-bold text-ink">
                        {tx.description || (lang === 'ar' ? 'مصروف عام' : 'Expense')}
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <span className="px-2 py-0.5 rounded-md bg-teal-soft/60 text-teal-dark text-[10px] font-bold">
                          {tx.category_code || 'OPEX'}
                        </span>
                        <span className="text-[11px] text-muted">
                          {new Date(tx.timestamp).toLocaleDateString(lang === 'ar' ? 'ar-SA' : 'en-US')}
                        </span>
                      </div>
                    </div>
                    <div className="font-mono text-sm font-bold text-rose-600">
                      -{formatSAR(Number(tx.amount))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="mt-6 pt-4 border-t border-line">
            <button
              type="button"
              onClick={() => onNavigateTab('transactions')}
              className="w-full py-3 rounded-2xl border border-dashed border-teal/40 bg-teal/5 text-teal text-xs sm:text-sm font-bold hover:bg-teal hover:text-white transition-all text-center flex items-center justify-center gap-2"
            >
              <span>+</span>
              <span>{dict.portal.newTransaction}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
