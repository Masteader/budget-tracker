import React, { useState } from 'react';
import type { Language, TranslationDictionary } from '../../i18n/translations';
import { PortalHeader, type PortalTab } from './PortalHeader';
import { DashboardView } from './DashboardView';
import { TransactionsView } from './TransactionsView';
import { BudgetsView } from './BudgetsView';

interface PortalShellProps {
  lang: Language;
  setLanguage: (lang: Language) => void;
  dict: TranslationDictionary;
}

export const PortalShell: React.FC<PortalShellProps> = ({
  lang,
  setLanguage,
  dict,
}) => {
  const [activeTab, setActiveTab] = useState<PortalTab>('dashboard');

  return (
    <div className="min-h-screen bg-bg text-ink flex flex-col font-sans">
      <PortalHeader
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        lang={lang}
        setLanguage={setLanguage}
        dict={dict}
      />

      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 py-6 sm:py-8">
        {activeTab === 'dashboard' && (
          <DashboardView
            dict={dict}
            lang={lang}
            onNavigateTab={setActiveTab}
          />
        )}
        {activeTab === 'transactions' && (
          <TransactionsView dict={dict} lang={lang} />
        )}
        {activeTab === 'budgets' && (
          <BudgetsView dict={dict} lang={lang} />
        )}
      </main>

      <footer className="border-t border-line/60 bg-white py-6 text-center text-xs text-muted">
        <div className="max-w-6xl mx-auto px-4">
          Budget Tracker · {dict.footer.rights}
        </div>
      </footer>
    </div>
  );
};
