import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/useAuth';
import type { TranslationDictionary, Language } from '../../i18n/translations';
import { supabase } from '../../lib/supabaseClient';

interface NewTransactionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  dict: TranslationDictionary;
  lang: Language;
}

export const NewTransactionModal: React.FC<NewTransactionModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  dict,
  lang,
}) => {
  const { user, householdId } = useAuth();
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [categoryCode, setCategoryCode] = useState('OPEX-GROCERY');
  const [date, setDate] = useState(() => new Date().toISOString().split('T')[0]);
  const [spentBy, setSpentBy] = useState<'me' | 'partner' | 'both'>('me');
  const [nafaqahClass, setNafaqahClass] = useState<string>('');
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const categories = [
    { code: 'OPEX-GROCERY', label: lang === 'ar' ? 'البقالة والمؤن' : 'Groceries & Staples' },
    { code: 'OPEX-UTILITIES', label: lang === 'ar' ? 'الفواتير والخدمات' : 'Bills & Utilities' },
    { code: 'OPEX-DINING', label: lang === 'ar' ? 'المطاعم والكافيهات' : 'Dining & Cafes' },
    { code: 'OPEX-FUEL', label: lang === 'ar' ? 'الوقود والنقل' : 'Fuel & Transport' },
    { code: 'OPEX-HEALTH', label: lang === 'ar' ? 'الصحة والصيدلية' : 'Health & Pharmacy' },
    { code: 'OPEX-SHOPPING', label: lang === 'ar' ? 'التسوق والملابس' : 'Shopping & Fashion' },
    { code: 'OPEX-EDUCATION', label: lang === 'ar' ? 'التعليم والمدارس' : 'Education & School' },
    { code: 'OPEX-MISC', label: lang === 'ar' ? 'مصاريف أخرى عامة' : 'Miscellaneous' },
  ];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);
    const parsedAmount = parseFloat(amount);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      setErrorMsg(lang === 'ar' ? 'يرجى إدخال مبلغ صحيح أكبر من الصفر' : 'Please enter a valid amount greater than 0');
      return;
    }

    if (!householdId) {
      setErrorMsg(lang === 'ar' ? 'تعذر تحديد معرف المنزل للحساب' : 'Household ID not found');
      return;
    }

    setSubmitting(true);
    try {
      const { error } = await supabase.from('transactions').insert({
        household_id: householdId,
        user_id: user?.id,
        amount: parsedAmount,
        description: description.trim() || (lang === 'ar' ? 'عملية يدوية' : 'Manual Expense'),
        category_code: categoryCode,
        source: 'manual',
        spent_by: spentBy,
        nafaqah_class: nafaqahClass ? nafaqahClass : null,
        timestamp: new Date(date).toISOString(),
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setAmount('');
        setDescription('');
        onSuccess();
        onClose();
      }
    } catch {
      setErrorMsg(dict.auth.errorGeneric);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-ink/40 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-3xl bg-white p-6 sm:p-8 shadow-2xl border border-line relative"
        onClick={(e) => e.stopPropagation()}
      >
        <button
          type="button"
          onClick={onClose}
          aria-label={dict.auth.close}
          className="absolute top-5 left-5 rtl:left-auto rtl:right-5 p-2 rounded-full text-muted hover:text-ink hover:bg-bg transition-colors"
        >
          <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>

        <h2 className="text-xl font-bold text-ink mb-6 text-center">
          {dict.portal.newTransaction}
        </h2>

        {errorMsg && (
          <div className="mb-4 rounded-xl bg-red-50 border border-red-200 p-3 text-sm text-red-700">
            {errorMsg}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {dict.portal.amount} (ر.س) *
            </label>
            <input
              type="number"
              step="0.01"
              required
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-base font-bold text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all font-mono"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {dict.portal.description}
            </label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={lang === 'ar' ? 'اسم المتجر أو الوصف، مثلاً: بنده أو محطة الدريس' : 'Merchant name or note, e.g. Panda or Shell'}
              className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink placeholder:text-muted/60 focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-ink mb-1.5">
                {dict.portal.category}
              </label>
              <select
                value={categoryCode}
                onChange={(e) => setCategoryCode(e.target.value)}
                className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
              >
                {categories.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-ink mb-1.5">
                {dict.portal.date}
              </label>
              <input
                type="date"
                required
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="w-full rounded-xl border border-line bg-bg px-4 py-2 text-sm text-ink focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all font-mono"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {lang === 'ar' ? 'الدافع / الصارف' : 'Spent By'}
            </label>
            <div className="flex gap-2">
              {[
                { id: 'me' as const, label: lang === 'ar' ? 'أنا' : 'Me' },
                { id: 'partner' as const, label: lang === 'ar' ? 'الشريك' : 'Partner' },
                { id: 'both' as const, label: lang === 'ar' ? 'مشترك' : 'Both' },
              ].map((opt) => (
                <button
                  key={opt.id}
                  type="button"
                  onClick={() => setSpentBy(opt.id)}
                  className={`flex-1 py-1.5 rounded-lg text-xs font-bold border transition-all ${
                    spentBy === opt.id
                      ? 'bg-teal text-white border-teal'
                      : 'bg-bg text-muted border-line hover:text-ink'
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-ink mb-1.5">
              {lang === 'ar' ? 'تصنيف النفقة الشرعية (اختياري)' : 'Nafaqah Category (Optional)'}
            </label>
            <select
              value={nafaqahClass}
              onChange={(e) => setNafaqahClass(e.target.value)}
              className="w-full rounded-xl border border-line bg-bg px-4 py-2.5 text-sm text-ink focus:border-teal focus:outline-none focus:ring-2 focus:ring-teal/20 transition-all"
            >
              <option value="">{lang === 'ar' ? 'مصروف أسري عام (المسؤولية على الزوج)' : 'General Family Expense'}</option>
              <option value="wife_personal">{lang === 'ar' ? 'مصروف الزوجة الشخصي (يخصم من مخصصها)' : "Wife's Personal Allowance"}</option>
              <option value="wife_reimbursable">{lang === 'ar' ? 'سددته الزوجة للأسرة (دين مستحق لها)' : 'Wife-paid Household Debt (Reimbursable)'}</option>
            </select>
          </div>

          <div className="flex gap-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-3 rounded-xl border border-line text-sm font-bold text-muted hover:text-ink hover:bg-bg transition-colors"
            >
              {dict.portal.cancel}
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="flex-1 py-3 rounded-xl bg-teal text-sm font-bold text-white shadow-md hover:bg-teal-dark transition-all disabled:opacity-50"
            >
              {submitting ? dict.auth.loading : dict.portal.save}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
