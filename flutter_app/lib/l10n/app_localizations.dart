import 'package:flutter/widgets.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'app_title': 'Budget Tracker',
      'appearance': 'Appearance',
      'theme_system': 'System Default',
      'theme_light': 'Light Mode',
      'theme_dark': 'Dark Mode',
      'language': 'Language',
      'language_en': 'English',
      'language_ar': 'العربية (Arabic)',
      'language_ur': 'اردو (Urdu)',
      'monthly_income': 'Monthly Salary / Income',
      'income_desc': 'Your household monthly income used for budget planning & auto-savings.',
      'savings_reserve': 'Savings Reserve',
      'payday_title': 'Salary Cycle Payday',
      'help_support': 'Help & Support',
      'ai_chat_entry': 'AI Chat Entry',
      'save': 'Save',
      'saved': 'Saved Successfully',
      'cancel': 'Cancel',
      'overallocated': 'Over-allocated',
      'remaining': 'Remaining',
      'allocated': 'Allocated',
    },
    'ar': {
      'app_title': 'ميزانية الأسرة',
      'appearance': 'مظهر التطبيق',
      'theme_system': 'تلقائي (النظام)',
      'theme_light': 'الوضع الفاتح',
      'theme_dark': 'الوضع الداكن',
      'language': 'لغة التطبيق',
      'language_en': 'الإنجليزية',
      'language_ar': 'العربية',
      'language_ur': 'الأردية (اردو)',
      'monthly_income': 'الراتب أو الدخل الشهري',
      'income_desc': 'دخل الأسرة الشهري لتوزيع الميزانيات واحتساب احتياطي الادخار التلقائي.',
      'savings_reserve': 'احتياطي الادخار',
      'payday_title': 'يوم نزول الراتب',
      'help_support': 'مركز المساعدة والدعم',
      'ai_chat_entry': 'المساعد الذكي لتسجيل المصاريف',
      'save': 'حفظ',
      'saved': 'تم الحفظ بنجاح',
      'cancel': 'إلغاء',
      'overallocated': 'تجاوزت سقف الدخل',
      'remaining': 'المتبقي',
      'allocated': 'المخصص',
    },
    'ur': {
      'app_title': 'بجٹ ٹریکر',
      'appearance': 'ایپ کا منظر',
      'theme_system': 'سسٹم کا پہلے سے طے شدہ',
      'theme_light': 'لائٹ موڈ',
      'theme_dark': 'ڈارک موڈ',
      'language': 'زبان',
      'language_en': 'انگریزی (English)',
      'language_ar': 'عربی (العربية)',
      'language_ur': 'اردو',
      'monthly_income': 'ماہانہ تنخواہ / آمدنی',
      'income_desc': 'بجٹ کی منصوبہ بندی اور خودکار بچت کے لیے گھرانے کی ماہانہ آمدنی۔',
      'savings_reserve': 'بچت کا ذخیرہ',
      'payday_title': 'تنخواہ کا دن',
      'help_support': 'مدد اور سپورٹ',
      'ai_chat_entry': 'اے آئی چیٹ اخراجات اندراج',
      'save': 'محفوظ کریں',
      'saved': 'کامیابی سے محفوظ ہو گیا',
      'cancel': 'منسوخ کریں',
      'overallocated': 'حد سے زیادہ مختص',
      'remaining': 'باقی',
      'allocated': 'مختص شدہ',
    },
  };

  String get(String key) {
    final lang = locale.languageCode;
    return _localizedValues[lang]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar', 'ur'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
