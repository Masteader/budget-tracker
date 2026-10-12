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
      'nav_dashboard': 'Dashboard',
      'nav_transactions': 'Transactions',
      'nav_budgets': 'Budgets',
      'nav_settings': 'Settings',

      // Dashboard
      'salary_cycle': 'Salary Cycle',
      'days_to_payday': 'Days to Payday',
      'burn_rate': 'Burn Rate',
      'allowable_daily': 'Allowable Daily',
      'partner_settlement': 'Partner Settlement',
      'recurring_bills': 'Recurring Bills & Reserves',
      'installments_bnpl': 'Installments & BNPL',
      'price_tracker': 'Price Tracker',
      'multi_shot_scan': 'Multi-Shot Scan',
      'sync_now': 'Sync Now',
      'queued_offline': 'transaction(s) queued offline',
      'all_cleared': 'All cleared',

      // Budgets
      'budget_allocations': 'Budget Allocations',
      'category_library': 'Category Library',
      'add_category': 'Add Category',
      'add_sub_category': 'Add Sub-Category',
      'total_allocated': 'Total Allocated',
      'set': 'Set',
      'not_set': 'Not set',
      'copy_previous': 'Copy Previous Cycle Allocations',
      'deactivate': 'Deactivate',
      'activate': 'Activate',

      // Transactions
      'transactions': 'Transactions',
      'filter_and_sort': 'Filter & Sort',
      'delete_transaction': 'Delete Transaction',
      'delete': 'Delete',
      'save': 'Save',
      'saved': 'Saved Successfully',
      'cancel': 'Cancel',
      'edit': 'Edit',

      // Attribution & Dependents
      'i_paid': 'I Paid',
      'partner_paid': 'Partner Paid',
      'for_whom': 'FOR WHOM?',
      'me_solo': 'Me (Solo)',
      'partner': 'Partner',
      'both_shared': 'Both (Shared)',
      'paid_for_whom': 'Paid for Whom (Children & Dependents)',
      'add_child': 'Add Child',

      // Settings
      'settings_and_permissions': 'Settings & Permissions',
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
      'sign_out': 'Sign Out',
      'overallocated': 'Over-allocated',
      'remaining': 'Remaining',
      'allocated': 'Allocated',
    },
    'ar': {
      'app_title': 'ميزانية الأسرة',
      'nav_dashboard': 'لوحة التحكم',
      'nav_transactions': 'المعاملات',
      'nav_budgets': 'الميزانيات',
      'nav_settings': 'الإعدادات',

      // Dashboard
      'salary_cycle': 'دورة الراتب',
      'days_to_payday': 'أيام حتى الراتب',
      'burn_rate': 'معدل الصرف اليومي',
      'allowable_daily': 'المتاح يومياً',
      'partner_settlement': 'تسوية الشريك',
      'recurring_bills': 'الفواتير الدورية والاحتياطيات',
      'installments_bnpl': 'الأقساط والشراء الآجل',
      'price_tracker': 'مقارنة الأسعار',
      'multi_shot_scan': 'مسح الفواتير',
      'sync_now': 'مزامنة الآن',
      'queued_offline': 'معاملات مسجلة دون اتصال',
      'all_cleared': 'تم سداد الكل',

      // Budgets
      'budget_allocations': 'توزيع الميزانيات',
      'category_library': 'مكتبة التصنيفات',
      'add_category': 'إضافة تصنيف',
      'add_sub_category': 'إضافة تصنيف فرعي',
      'total_allocated': 'إجمالي المخصص',
      'set': 'محدد',
      'not_set': 'غير محدد',
      'copy_previous': 'نسخ مخصصات الدورة السابقة',
      'deactivate': 'تعطيل',
      'activate': 'تفعيل',

      // Transactions
      'transactions': 'المعاملات',
      'filter_and_sort': 'تصفية وترتيب',
      'delete_transaction': 'حذف المعاملة',
      'delete': 'حذف',
      'save': 'حفظ',
      'saved': 'تم الحفظ بنجاح',
      'cancel': 'إلغاء',
      'edit': 'تعديل',

      // Attribution & Dependents
      'i_paid': 'أنا دفعت',
      'partner_paid': 'الشريك دفع',
      'for_whom': 'لمن المصروف؟',
      'me_solo': 'لي شخصياً',
      'partner': 'للشريك',
      'both_shared': 'كلينا (مشترك)',
      'paid_for_whom': 'الدفع لمن (الأبناء والمعالين)',
      'add_child': 'إضافة طفل',

      // Settings
      'settings_and_permissions': 'الإعدادات والصلاحيات',
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
      'sign_out': 'تسجيل الخروج',
      'overallocated': 'تجاوزت سقف الدخل',
      'remaining': 'المتبقي',
      'allocated': 'المخصص',
    },
    'ur': {
      'app_title': 'بجٹ ٹریکر',
      'nav_dashboard': 'ڈیش بورڈ',
      'nav_transactions': 'لین دین',
      'nav_budgets': 'بجٹ',
      'nav_settings': 'ترتیبات',

      // Dashboard
      'salary_cycle': 'تنخواہ کا چکر',
      'days_to_payday': 'تنخواہ تک دن',
      'burn_rate': 'روزانہ خرچ کی رفتار',
      'allowable_daily': 'روزانہ کی اجازت',
      'partner_settlement': 'پارٹنر کا حساب کتاب',
      'recurring_bills': 'ماہانہ بلز اور ریزرو',
      'installments_bnpl': 'اقساط اور بی این پی ایل',
      'price_tracker': 'قیمتوں کا ٹریکر',
      'multi_shot_scan': 'رسید اسکین',
      'sync_now': 'ابھی ہم آہنگ کریں',
      'queued_offline': 'لین دین آف لائن محفوظ ہیں',
      'all_cleared': 'سب ادا ہو چکا',

      // Budgets
      'budget_allocations': 'بجٹ کی تقسیم',
      'category_library': 'کیٹیگری لائبریری',
      'add_category': 'کیٹیگری شامل کریں',
      'add_sub_category': 'ذیلی کیٹیگری شامل کریں',
      'total_allocated': 'کل مختص شدہ',
      'set': 'مقرر',
      'not_set': 'مقرر نہیں',
      'copy_previous': 'پچھلے چکر کی تخصیصات نقل کریں',
      'deactivate': 'غیر فعال کریں',
      'activate': 'فعال کریں',

      // Transactions
      'transactions': 'لین دین',
      'filter_and_sort': 'فلٹر اور ترتیب',
      'delete_transaction': 'لین دین حذف کریں',
      'delete': 'حذف کریں',
      'save': 'محفوظ کریں',
      'saved': 'کامیابی سے محفوظ ہو گیا',
      'cancel': 'منسوخ کریں',
      'edit': 'تبدیل کریں',

      // Attribution & Dependents
      'i_paid': 'میں نے ادا کیا',
      'partner_paid': 'پارٹنر نے ادا کیا',
      'for_whom': 'کس کے لیے؟',
      'me_solo': 'میرے لیے',
      'partner': 'پارٹنر',
      'both_shared': 'مشترکہ',
      'paid_for_whom': 'کس کے لیے ادا کیا (بچے اور زیر کفالت)',
      'add_child': 'بچہ شامل کریں',

      // Settings
      'settings_and_permissions': 'ترتیبات اور اجازتیں',
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
      'sign_out': 'لاگ آؤٹ',
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

extension LocalizationExtension on BuildContext {
  String tr(String key) => AppLocalizations.of(this).get(key);
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
