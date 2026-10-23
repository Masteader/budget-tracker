import React from 'react';
import type { Language, TranslationDictionary } from '../../i18n/translations';
import { useAuth } from '../../context/useAuth';
import { Logo } from '../Header';

export type PortalTab = 'dashboard' | 'transactions' | 'budgets';

interface PortalHeaderProps {
  activeTab: PortalTab;
  setActiveTab: (tab: PortalTab) => void;
  lang: Language;
  setLanguage: (lang: Language) => void;
  dict: TranslationDictionary;
}

export const PortalHeader: React.FC<PortalHeaderProps> = ({
  activeTab,
  setActiveTab,
  lang,
  setLanguage,
  dict,
}) => {
  const { user, household, signOut } = useAuth();
  const otherLang: Language = lang === 'ar' ? 'en' : 'ar';

  const navItems: { id: PortalTab; label: string }[] = [
    { id: 'dashboard', label: dict.portal.dashboard },
    { id: 'transactions', label: dict.portal.transactions },
    { id: 'budgets', label: dict.portal.budgets },
  ];

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-white/95 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        {/* Brand & Household info */}
        <div className="flex items-center gap-3 min-w-0">
          <button
            type="button"
            onClick={() => setActiveTab('dashboard')}
            className="flex items-center gap-2 text-left rtl:text-right group focus:outline-none"
          >
            <Logo className="w-8 h-8 shrink-0" />
            <span className="font-bold text-ink text-sm sm:text-base hidden sm:inline">
              Budget Tracker
            </span>
          </button>

          {/* Household Badge */}
          <div className="flex items-center gap-1.5 px-3 py-1 rounded-full bg-teal-soft/80 border border-teal/20 text-teal-dark text-xs font-semibold truncate">
            <span className="w-1.5 h-1.5 rounded-full bg-teal shrink-0 animate-pulse" />
            <span className="truncate">{household?.name || dict.portal.householdDefault}</span>
            <span className="text-muted/60">·</span>
            <span className="shrink-0 font-mono text-[11px]">{dict.portal.salaryDay}: {household?.paydayDay || 27}</span>
          </div>
        </div>

        {/* Central HUD Navigation Tabs */}
        <nav className="flex items-center gap-1 bg-bg p-1 rounded-2xl border border-line">
          {navItems.map((item) => {
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setActiveTab(item.id)}
                className={`px-3 sm:px-4 py-1.5 rounded-xl text-xs sm:text-sm font-bold transition-all ${
                  isActive
                    ? 'bg-teal text-white shadow-sm'
                    : 'text-muted hover:text-ink hover:bg-white/60'
                }`}
              >
                {item.label}
              </button>
            );
          })}
        </nav>

        {/* User profile & actions */}
        <div className="flex items-center gap-2">
          {/* Language Switch */}
          <button
            type="button"
            onClick={() => setLanguage(otherLang)}
            className="rounded-lg border border-line px-2.5 py-1.5 text-xs font-semibold text-ink hover:border-teal hover:text-teal transition-colors"
          >
            {otherLang === 'en' ? 'EN' : 'عربي'}
          </button>

          {/* User Email & Sign Out */}
          <div className="hidden md:flex items-center text-xs text-muted max-w-[140px] truncate" title={user?.email}>
            {user?.email}
          </div>
          <button
            type="button"
            onClick={() => signOut()}
            className="rounded-lg border border-red-200 bg-red-50 px-2.5 sm:px-3 py-1.5 text-xs font-bold text-red-700 hover:bg-red-100 hover:text-red-800 transition-colors"
            title={dict.auth.signOut}
          >
            {dict.auth.signOut}
          </button>
        </div>
      </div>
    </header>
  );
};
