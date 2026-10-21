import type { PluralForms, TranslationDictionary } from '../i18n/translations';

const numberFormat = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });

/** "1,840 ر.س" in Arabic (unit after the number), "SAR 1,840" in English. Western digits. */
export function formatMoney(amount: number, money: TranslationDictionary['money']): string {
  const value = numberFormat.format(amount);
  return money.unitAfter ? `${value} ${money.unit}` : `${money.unit} ${value}`;
}

export function plural(forms: PluralForms, count: number, lang: string): string {
  const form = forms[new Intl.PluralRules(lang).select(count)] ?? forms.other;
  return form.replace('{val}', numberFormat.format(count));
}
