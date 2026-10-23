import React, { useEffect, useState, useMemo } from 'react';
import { useAuth } from '../../context/useAuth';
import type { TranslationDictionary, Language } from '../../i18n/translations';
import { supabase } from '../../lib/supabaseClient';
import { formatSAR, currentCycleKey } from '../../lib/cycleUtils';

interface BudgetsViewProps {
  dict: TranslationDictionary;
  lang: Language;
}

interface BudgetCategory {
  code: string;
  name: string;
  allocated: number;
  spent: number;
}

export const BudgetsView: React.FC<BudgetsViewProps> = ({ dict, lang }) => {
  const { householdId, household } = useAuth();
  const [loading, setLoading] = useState(true);
  const [budgets, setBudgets] = useState<BudgetCategory[]>([]);
  const [wifeAllowance, setWifeAllowance] = useState({ allocated: 2000, spent: 450 });

  const cycleKey = currentCycleKey(household?.paydayDay || 27);

  const defaultCategories: BudgetCategory[] = useMemo(() => [
    { code: 'OPEX-GROCERY', name: lang === 'ar' ? 'البقالة والتموين' : 'Groceries & Staples', allocated: 3500, spent: 0 },
    { code: 'OPEX-UTILITIES', name: lang === 'ar' ? 'الفواتير والخدمات' : 'Bills & Utilities', allocated: 2000, spent: 0 },
    { code: 'OPEX-DINING', name: lang === 'ar' ? 'المطاعم والكافيهات' : 'Dining & Cafes', allocated: 1500, spent: 0 },
    { code: 'OPEX-FUEL', name: lang === 'ar' ? 'الوقود وصيانة السيارة' : 'Fuel & Transport', allocated: 1000, spent: 0 },
    { code: 'OPEX-HEALTH', name: lang === 'ar' ? 'الصحة والصيدلية' : 'Health & Pharmacy', allocated: 800, spent: 0 },
    { code: 'OPEX-SHOPPING', name: lang === 'ar' ? 'التسوق والملابس' : 'Shopping & Fashion', allocated: 1200, spent: 0 },
    { code: 'OPEX-EDUCATION', name: lang === 'ar' ? 'التعليم ومصاريف المدارس' : 'Education & School', allocated: 1500, spent: 0 },
    { code: 'OPEX-MISC', name: lang === 'ar' ? 'المصاريف العامة والطوارئ' : 'Miscellaneous', allocated: 1000, spent: 0 },
  ], [lang]);

  useEffect(() => {
    let ignore = false;
    const run = async () => {
      if (!householdId) {
        setBudgets(defaultCategories);
        setLoading(false);
        return;
      }
      try {
        const { data: budgetData } = await supabase
          .from('budgets')
          .select('category_code, amount, cycle_key')
          .eq('household_id', householdId);

        const { data: txsData } = await supabase
          .from('transactions')
          .select('amount, category_code, nafaqah_class, cycle_key')
          .eq('household_id', householdId);

        const cycleTxs = txsData
          ? txsData.filter((t) => !t.cycle_key || t.cycle_key === cycleKey)
          : [];

        const wifeSpent = cycleTxs
          .filter((t) => t.nafaqah_class === 'wife_personal')
          .reduce((sum, t) => sum + Number(t.amount || 0), 0);

        const { data: allowanceData } = await supabase
          .from('member_allowances')
          .select('amount')
          .eq('household_id', householdId)
          .eq('cycle_key', cycleKey)
          .maybeSingle();

        const allocatedAllowance = allowanceData?.amount ? Number(allowanceData.amount) : 2000;
        if (!ignore) {
          setWifeAllowance({ allocated: allocatedAllowance, spent: wifeSpent });

          const merged = defaultCategories.map((def) => {
            const foundBudget = budgetData?.find((b) => b.category_code === def.code);
            const allocated = foundBudget ? Number(foundBudget.amount) : def.allocated;
            const spent = cycleTxs
              .filter((t) => t.category_code === def.code)
              .reduce((sum, t) => sum + Number(t.amount || 0), 0);
            return {
              ...def,
              allocated,
              spent,
            };
          });

          setBudgets(merged);
        }
      } catch {
        if (!ignore) setBudgets(defaultCategories);
      } finally {
        if (!ignore) setLoading(false);
      }
    };
    run();
    return () => {
      ignore = true;
    };
  }, [householdId, cycleKey, defaultCategories]);

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="bg-white p-6 sm:p-8 rounded-3xl border border-line shadow-sm">
        <h2 className="text-xl sm:text-2xl font-black text-ink">
          {dict.portal.budgetsTitle}
        </h2>
        <p className="text-xs sm:text-sm text-muted mt-1">
          {lang === 'ar'
            ? 'مخصصات الميزانية الشهرية وتوزيع البنود للأسرة وفق دورة الراتب الحالية'
            : 'Monthly budget category limits and sub-allocations for the current salary cycle'}
        </p>
      </div>

      {/* Wife's Personal Allowance Card (مصروف الزوجة) */}
      <div className="rounded-3xl bg-gradient-to-br from-amber-50/70 via-white to-sand-soft/50 border border-amber-200/80 p-6 sm:p-8 shadow-sm">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-amber-100 text-amber-900 font-bold text-xs">
              <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
              </svg>
              <span>{dict.portal.wifeAllowanceTitle}</span>
            </div>
            <h3 className="text-xl font-bold text-ink">
              {dict.portal.wifeAllowanceSubtitle}
            </h3>
            <p className="text-xs text-muted max-w-xl leading-relaxed">
              {lang === 'ar'
                ? 'مخصص شهري خالص للزوجة يخصم منه ما تشتريه لنفسها (أحكام النفقة الشرعية)، ولا يعتبر ديناً ولا تشترك في مصاريف البيت المشتركة.'
                : "A protected monthly personal allowance for the wife. Personal expenses are deducted from this allowance according to Islamic Nafaqah principles."}
            </p>
          </div>

          <div className="bg-white p-5 rounded-2xl border border-line/80 shadow-sm min-w-[260px]">
            <div className="flex justify-between items-baseline mb-2">
              <span className="text-xs text-muted font-bold">{dict.portal.remaining}:</span>
              <span className="text-2xl font-black text-amber-800 font-mono">
                {formatSAR(wifeAllowance.allocated - wifeAllowance.spent)}
              </span>
            </div>
            <div className="w-full h-2.5 bg-amber-100 rounded-full overflow-hidden mb-3">
              <div
                className="h-full bg-amber-500 rounded-full transition-all"
                style={{
                  width: `${Math.min(100, Math.round((wifeAllowance.spent / (wifeAllowance.allocated || 1)) * 100))}%`,
                }}
              />
            </div>
            <div className="flex justify-between text-xs text-muted">
              <span>{dict.portal.spent}: {formatSAR(wifeAllowance.spent)}</span>
              <span>{dict.portal.budgetLimit}: {formatSAR(wifeAllowance.allocated)}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Category Budgets Grid */}
      <div>
        <h3 className="text-lg font-black text-ink mb-4">
          {lang === 'ar' ? 'بنود الميزانية المعتمدة' : 'Approved Budget Categories'}
        </h3>

        {loading ? (
          <div className="py-16 text-center text-sm text-muted">
            {dict.auth.loading}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-6">
            {budgets.map((b) => {
              const remaining = b.allocated - b.spent;
              const percent = Math.min(100, Math.round((b.spent / (b.allocated || 1)) * 100));
              const isExceeded = remaining < 0;
              const isWarning = percent >= 80 && !isExceeded;

              return (
                <div
                  key={b.code}
                  className="rounded-3xl bg-white border border-line p-6 shadow-sm hover:border-teal/30 transition-all flex flex-col justify-between"
                >
                  <div>
                    <div className="flex items-center justify-between mb-3">
                      <div>
                        <span className="text-sm font-bold text-ink">{b.name}</span>
                        <div className="text-[11px] font-mono text-muted">{b.code}</div>
                      </div>
                      <span
                        className={`text-xs font-bold px-2.5 py-1 rounded-full ${
                          isExceeded
                            ? 'bg-rose-100 text-rose-800'
                            : isWarning
                            ? 'bg-amber-100 text-amber-800'
                            : 'bg-teal-soft text-teal-dark'
                        }`}
                      >
                        {percent}%
                      </span>
                    </div>

                    {/* Progress Bar */}
                    <div className="w-full h-2.5 bg-bg rounded-full overflow-hidden mb-4">
                      <div
                        className={`h-full rounded-full transition-all duration-500 ${
                          isExceeded
                            ? 'bg-rose-500'
                            : isWarning
                            ? 'bg-amber-500'
                            : 'bg-teal'
                        }`}
                        style={{ width: `${percent}%` }}
                      />
                    </div>
                  </div>

                  <div className="flex justify-between items-center text-xs pt-3 border-t border-line/60">
                    <span className="text-muted">
                      {dict.portal.spent}: <strong className="font-mono text-ink">{formatSAR(b.spent)}</strong>
                    </span>
                    <span className={isExceeded ? 'text-rose-600 font-bold' : 'text-teal-dark font-bold'}>
                      {dict.portal.remaining}: <strong className="font-mono">{formatSAR(remaining)}</strong>
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Sub-allocations breakdown (Dependents / Children) */}
      <div className="rounded-3xl bg-white border border-line p-6 sm:p-8 shadow-sm">
        <h3 className="text-base font-bold text-ink mb-2">
          {dict.portal.subAllocationsTitle}
        </h3>
        <p className="text-xs text-muted mb-6">
          {lang === 'ar'
            ? 'توزيع المخصصات المحددة للأبناء والمصاريف المستقلة ضمن ميزانية الأسرة'
            : 'Sub-allocations defined for children and independent line-items within the household budget'}
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="p-4 rounded-2xl bg-bg border border-line/70">
            <div className="text-xs font-bold text-ink">{lang === 'ar' ? 'مصاريف الأبناء والمدارس' : 'Children & School'}</div>
            <div className="text-lg font-black text-ink font-mono mt-1">1,200.00 ر.س</div>
            <div className="text-[11px] text-muted mt-1">{lang === 'ar' ? 'مخصص دوري معتمد' : 'Monthly approved'}</div>
          </div>
          <div className="p-4 rounded-2xl bg-bg border border-line/70">
            <div className="text-xs font-bold text-ink">{lang === 'ar' ? 'السائق والوقود المشترك' : 'Driver & Fuel'}</div>
            <div className="text-lg font-black text-ink font-mono mt-1">600.00 ر.س</div>
            <div className="text-[11px] text-muted mt-1">{lang === 'ar' ? 'مخصص دوري معتمد' : 'Monthly approved'}</div>
          </div>
          <div className="p-4 rounded-2xl bg-bg border border-line/70">
            <div className="text-xs font-bold text-ink">{lang === 'ar' ? 'طوارئ وصيانة المنزل' : 'Home Repairs & Emergencies'}</div>
            <div className="text-lg font-black text-ink font-mono mt-1">1,000.00 ر.س</div>
            <div className="text-[11px] text-muted mt-1">{lang === 'ar' ? 'مخصص دوري معتمد' : 'Monthly approved'}</div>
          </div>
        </div>
      </div>
    </div>
  );
};
