import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { useAuth } from '../../context/useAuth';
import type { TranslationDictionary, Language } from '../../i18n/translations';
import { supabase } from '../../lib/supabaseClient';
import { formatSAR } from '../../lib/cycleUtils';
import { NewTransactionModal } from './NewTransactionModal';

interface TransactionsViewProps {
  dict: TranslationDictionary;
  lang: Language;
}

interface TransactionRow {
  id: string;
  amount: number;
  description?: string;
  category_code?: string;
  timestamp: string;
  nafaqah_class?: string;
  source?: string;
}

export const TransactionsView: React.FC<TransactionsViewProps> = ({ dict, lang }) => {
  const { householdId } = useAuth();
  const [transactions, setTransactions] = useState<TransactionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('ALL');
  const [isModalOpen, setIsModalOpen] = useState(false);

  const fetchTransactions = useCallback(async () => {
    if (!householdId) return;
    try {
      const { data, error } = await supabase
        .from('transactions')
        .select('*')
        .eq('household_id', householdId)
        .order('timestamp', { ascending: false });

      if (!error && data) {
        setTransactions(data);
      }
    } catch {
      // Ignore
    }
  }, [householdId]);

  useEffect(() => {
    let ignore = false;
    const run = async () => {
      if (!householdId) {
        setLoading(false);
        return;
      }
      try {
        const { data, error } = await supabase
          .from('transactions')
          .select('*')
          .eq('household_id', householdId)
          .order('timestamp', { ascending: false });

        if (!ignore && !error && data) {
          setTransactions(data);
        }
      } catch {
        // Ignore
      } finally {
        if (!ignore) setLoading(false);
      }
    };
    run();
    return () => {
      ignore = true;
    };
  }, [householdId]);

  const categories = useMemo(() => [
    { code: 'ALL', label: dict.portal.allCategories },
    { code: 'OPEX-GROCERY', label: lang === 'ar' ? 'البقالة والمؤن' : 'Groceries & Staples' },
    { code: 'OPEX-UTILITIES', label: lang === 'ar' ? 'الفواتير والخدمات' : 'Bills & Utilities' },
    { code: 'OPEX-DINING', label: lang === 'ar' ? 'المطاعم والكافيهات' : 'Dining & Cafes' },
    { code: 'OPEX-FUEL', label: lang === 'ar' ? 'الوقود والنقل' : 'Fuel & Transport' },
    { code: 'OPEX-HEALTH', label: lang === 'ar' ? 'الصحة والصيدلية' : 'Health & Pharmacy' },
    { code: 'OPEX-SHOPPING', label: lang === 'ar' ? 'التسوق والملابس' : 'Shopping & Fashion' },
    { code: 'OPEX-EDUCATION', label: lang === 'ar' ? 'التعليم والمدارس' : 'Education & School' },
    { code: 'OPEX-MISC', label: lang === 'ar' ? 'مصاريف أخرى عامة' : 'Miscellaneous' },
  ], [dict.portal.allCategories, lang]);

  const filteredTransactions = useMemo(() => {
    return transactions.filter((tx) => {
      const matchesSearch =
        searchQuery.trim() === '' ||
        (tx.description && tx.description.toLowerCase().includes(searchQuery.toLowerCase())) ||
        (tx.category_code && tx.category_code.toLowerCase().includes(searchQuery.toLowerCase()));

      const matchesCat =
        selectedCategory === 'ALL' || tx.category_code === selectedCategory;

      return matchesSearch && matchesCat;
    });
  }, [transactions, searchQuery, selectedCategory]);

  return (
    <div className="space-y-6">
      {/* Header bar: Title, Search, Category filter, and Add button */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-6 rounded-3xl border border-line shadow-sm">
        <div>
          <h2 className="text-xl font-black text-ink">{dict.portal.transactions}</h2>
          <p className="text-xs text-muted mt-1">
            {lang === 'ar'
              ? `إجمالي العمليات المسجلة: ${transactions.length}`
              : `Total recorded transactions: ${transactions.length}`}
          </p>
        </div>

        <button
          type="button"
          onClick={() => setIsModalOpen(true)}
          className="inline-flex items-center justify-center gap-2 rounded-2xl bg-teal px-5 py-3 text-sm font-bold text-white shadow-md hover:bg-teal-dark active:scale-[0.99] transition-all"
        >
          <span className="text-lg leading-none">+</span>
          <span>{dict.portal.newTransaction}</span>
        </button>
      </div>

      {/* Filter and Search controls */}
      <div className="flex flex-col sm:flex-row items-center gap-3">
        {/* Search bar */}
        <div className="relative flex-1 w-full">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={dict.portal.searchPlaceholder}
            className="w-full rounded-2xl border border-line bg-white px-4 py-2.5 text-sm text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
          />
        </div>

        {/* Category selector */}
        <div className="w-full sm:w-64">
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="w-full rounded-2xl border border-line bg-white px-4 py-2.5 text-sm text-ink focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
          >
            {categories.map((c) => (
              <option key={c.code} value={c.code}>
                {c.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Transactions Table Container */}
      <div className="rounded-3xl bg-white border border-line shadow-sm overflow-hidden">
        {loading ? (
          <div className="py-16 text-center text-sm text-muted">
            {dict.auth.loading}
          </div>
        ) : filteredTransactions.length === 0 ? (
          <div className="py-16 text-center text-sm text-muted">
            {dict.portal.noData}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left rtl:text-right text-sm">
              <thead className="border-b border-line bg-bg/80 text-xs font-bold text-muted">
                <tr>
                  <th className="px-6 py-4">{dict.portal.date}</th>
                  <th className="px-6 py-4">{dict.portal.description}</th>
                  <th className="px-6 py-4">{dict.portal.category}</th>
                  <th className="px-6 py-4 text-right rtl:text-left">{dict.portal.amount}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line/60">
                {filteredTransactions.map((tx) => (
                  <tr key={tx.id} className="hover:bg-bg/40 transition-colors">
                    <td className="px-6 py-4 font-mono text-xs text-muted whitespace-nowrap">
                      {new Date(tx.timestamp).toLocaleDateString(lang === 'ar' ? 'ar-SA' : 'en-US')}
                    </td>
                    <td className="px-6 py-4 font-bold text-ink">
                      <div>{tx.description || (lang === 'ar' ? 'مصروف عام' : 'Expense')}</div>
                      {tx.nafaqah_class && (
                        <span className="inline-block mt-1 px-2 py-0.5 rounded-md bg-amber-50 text-amber-800 text-[10px] font-bold border border-amber-200">
                          {tx.nafaqah_class === 'wife_personal'
                            ? (lang === 'ar' ? 'مصروف شخصي للزوجة' : "Wife's Personal")
                            : (lang === 'ar' ? 'مسترد للزوجة (دين)' : 'Wife Reimbursable')}
                        </span>
                      )}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="px-2.5 py-1 rounded-lg bg-teal-soft/80 text-teal-dark font-bold text-xs">
                        {tx.category_code || 'OPEX'}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-right rtl:text-left font-mono font-bold text-rose-600 whitespace-nowrap">
                      -{formatSAR(Number(tx.amount))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <NewTransactionModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onSuccess={fetchTransactions}
        dict={dict}
        lang={lang}
      />
    </div>
  );
};
