export type Language = 'ar' | 'en';

/**
 * Count label forms, chosen with Intl.PluralRules for the active language.
 * Arabic needs zero/one/two/few (3–10)/many (11–99)/other; English one/other.
 * `{val}` is replaced by the number; a form without `{val}` is shown alone.
 */
export type PluralForms = Partial<Record<Intl.LDMLPluralRule, string>> & { other: string };

export type IconName =
  | 'calendar'
  | 'mic'
  | 'receipt'
  | 'scale'
  | 'users'
  | 'shield'
  | 'lock'
  | 'sparkles'
  | 'noSms'
  | 'chevron'
  | 'mail';

export interface Feature {
  icon: IconName;
  title: string;
  desc: string;
}

export interface NafaqahCase {
  who: string;
  result: string;
  tone: 'neutral' | 'debt' | 'allowance';
}

export interface LedgerRow {
  label: string;
  amount: number;
  /** Shown with a minus sign (a repayment). */
  negative?: boolean;
  total?: boolean;
}

export interface TranslationDictionary {
  brand: {
    name: string;
    shortName: string;
    tagline: string;
  };
  nav: {
    features: string;
    nafaqah: string;
    privacy: string;
    faq: string;
    cta: string;
  };
  hero: {
    badge: string;
    title: string;
    subtitle: string;
    ctaPrimary: string;
    ctaSecondary: string;
    note: string;
  };
  demo: {
    label: string;
    sample: string;
    paydayLabel: string;
    daysLeftLabel: string;
    daysLeft: PluralForms;
    cycleLabel: string;
    budgetLabel: string;
    spentLabel: string;
    leftLabel: string;
    dailyLabel: string;
    perDay: string;
  };
  money: {
    /** Currency unit, placed after the number in Arabic and before it in English. */
    unit: string;
    unitAfter: boolean;
    /** BCP 47 locale for dates (Gregorian calendar, Western digits). */
    dateLocale: string;
  };
  features: {
    title: string;
    subtitle: string;
    items: Feature[];
    nafaqahLink: string;
  };
  nafaqah: {
    badge: string;
    title: string;
    intro: string;
    cases: NafaqahCase[];
    exampleTitle: string;
    exampleRows: LedgerRow[];
    footnote: string;
  };
  privacy: {
    title: string;
    intro: string;
    items: Feature[];
  };
  faq: {
    title: string;
    items: { q: string; a: string }[];
  };
  earlyAccess: {
    badge: string;
    title: string;
    desc: string;
    placeholder: string;
    button: string;
    sending: string;
    successMsg: string;
    errorInvalid: string;
    errorRateLimited: string;
    errorUnavailable: string;
    errorNetwork: string;
    contactInfo: string;
  };
  footer: {
    rights: string;
    contact: string;
    deleteAccount: string;
    deleteAccountHref: string;
  };
  auth: {
    signIn: string;
    signUp: string;
    signOut: string;
    email: string;
    password: string;
    displayName: string;
    signInTitle: string;
    signUpTitle: string;
    submitSignIn: string;
    submitSignUp: string;
    noAccount: string;
    hasAccount: string;
    loading: string;
    errorGeneric: string;
    close: string;
  };
  portal: {
    dashboard: string;
    transactions: string;
    budgets: string;
    householdDefault: string;
    cycleEndsIn: string;
    days: string;
    salaryDay: string;
    totalBalance: string;
    totalIncome: string;
    totalSpent: string;
    installmentsTitle: string;
    recurringBillsTitle: string;
    recentTransactions: string;
    viewAll: string;
    newTransaction: string;
    category: string;
    amount: string;
    description: string;
    date: string;
    save: string;
    cancel: string;
    type: string;
    expense: string;
    income: string;
    searchPlaceholder: string;
    allCategories: string;
    budgetsTitle: string;
    budgetLimit: string;
    spent: string;
    remaining: string;
    wifeAllowanceTitle: string;
    wifeAllowanceSubtitle: string;
    subAllocationsTitle: string;
    noData: string;
    activePlans: string;
    monthlyDue: string;
  };
  a11y: {
    pageTitle: string;
    skipToContent: string;
    switchToEnglish: string;
    switchToArabic: string;
    emailLabel: string;
    mainNav: string;
    footerNav: string;
    home: string;
  };
}

export const translations: Record<Language, TranslationDictionary> = {
  ar: {
    brand: {
      name: 'قوام المال Qawam Money',
      shortName: 'قوام المال',
      tagline: 'ميزانية البيت على دورة الراتب',
    },
    nav: {
      features: 'المزايا',
      nafaqah: 'مصاريف الزوجة',
      privacy: 'الخصوصية',
      faq: 'الأسئلة',
      cta: 'الوصول المبكر',
    },
    hero: {
      badge: 'تطبيق جوال · الوصول المبكر مفتوح',
      title: 'اعرف كم باقي لك لين الراتب',
      subtitle:
        'ميزانية البيت مرتّبة على دورة راتبكم، من يوم الراتب إلى الراتب اللي بعده. سجّل مصروفك بالكلام أو بتصوير الفاتورة، والنفقة بين الزوجين أو قسمة سكن الزملاء تنحسب بوضوح.',
      ctaPrimary: 'سجّل في الوصول المبكر',
      ctaSecondary: 'كيف تنحسب النفقة؟',
      note: 'التطبيق بالعربي والإنجليزي والأردو.',
    },
    demo: {
      label: 'مثال توضيحي',
      sample: 'الأرقام افتراضية، والتواريخ محسوبة من تاريخ اليوم.',
      paydayLabel: 'يوم الراتب في بيتكم',
      daysLeftLabel: 'باقي على الراتب',
      daysLeft: {
        one: 'يوم واحد',
        two: 'يومين',
        few: '{val} أيام',
        many: '{val} يوماً',
        other: '{val} يوم',
      },
      cycleLabel: 'الدورة الحالية',
      budgetLabel: 'ميزانية الدورة',
      spentLabel: 'المصروف',
      leftLabel: 'الباقي',
      dailyLabel: 'المتاح يومياً لين الراتب',
      perDay: 'في اليوم',
    },
    money: {
      unit: 'ر.س',
      unitAfter: true,
      dateLocale: 'ar-SA-u-ca-gregory-nu-latn',
    },
    features: {
      title: 'وش يسوي لك التطبيق',
      subtitle: 'أربعة أشياء، بدون تعقيد.',
      items: [
        {
          icon: 'calendar',
          title: 'اعرف كم باقي لك لين الراتب',
          desc: 'حدّد يوم راتب بيتكم (27 أو أي يوم ثاني)، والتطبيق يحسب على دورة الراتب مو على الشهر: كم صرفتوا، كم باقي، وكم تقدرون تصرفون يومياً لين الراتب الجاي.',
        },
        {
          icon: 'mic',
          title: 'سجّل مصروفك بالكلام أو بتصوير الفاتورة',
          desc: 'اكتب أو قل «دفعت 85 ريال بنزين» ويفهمها التطبيق. أو صوّر الفاتورة: يقرأ رمز QR الضريبي (زاتكا) إذا موجود، ويعبّي المبلغ والمتجر والتصنيف، وأنت تأكّد قبل الحفظ.',
        },
        {
          icon: 'scale',
          title: 'النفقة بين الزوجين واضحة',
          desc: 'النفقة على الزوج. اللي تدفعه الزوجة من فلوسها للبيت ينسجّل دَين لها عليه، ومشترياتها الشخصية تنحسب من مصروفها الشخصي. ما فيه قسمة بالنسبة بين الزوجين.',
        },
        {
          icon: 'users',
          title: 'قسمة سكن الزملاء بالعدل',
          desc: 'في السكن المشترك كل واحد يسجّل اللي دفعه، والتطبيق يقسم المصاريف المشتركة بالتساوي ويبسّط الديون: مين يحوّل لمين وكم، بأقل عدد تحويلات.',
        },
      ],
      nafaqahLink: 'شوف كيف تنحسب مصاريف الزوجة',
    },
    nafaqah: {
      badge: 'وضع الأسرة',
      title: 'كيف تنحسب مصاريف الزوجة؟',
      intro:
        'في وضع الأسرة يمشي التطبيق على أن مصاريف البيت على الزوج: السكن والأكل واحتياجات البيت مسؤوليته. ما يقسم التطبيق أي مصروف بين الزوجين بالنسبة، وكل مصروف ينحسب حسب مين دفع ولمين:',
      cases: [
        {
          who: 'الزوج دفع لشي للبيت أو للعيال',
          result: 'مصروف عادي على البيت. ما فيه دَين على أحد.',
          tone: 'neutral',
        },
        {
          who: 'الزوجة دفعت من فلوسها لشي للبيت أو للعيال',
          result: 'ينسجّل دَين لها على الزوج. التطبيق يعرض المبلغ المستحق لها على الزوج، وهو يسدّده كامل أو على دفعات.',
          tone: 'debt',
        },
        {
          who: 'الزوجة اشترت شي شخصي لها',
          result: 'ينحسب من مصروفها الشخصي للدورة اللي يحدده الزوج. ما هو دَين، ولا يدخل في ميزانية البيت.',
          tone: 'allowance',
        },
      ],
      exampleTitle: 'مثال: دفتر المستحق للزوجة',
      exampleRows: [
        { label: 'دفعت الزوجة مقاضي البيت', amount: 320 },
        { label: 'دفعت الزوجة أغراض مدرسة العيال', amount: 180 },
        { label: 'سدّد الزوج دفعة', amount: 200, negative: true },
        { label: 'الباقي مستحق لها على الزوج', amount: 300, total: true },
      ],
      footnote: 'وضع الأسرة يشتغل لما يكون في المنزل عضو بدور «الزوجة». وتبرّع الزوجة بمبلغ ما يُفترض أبداً؛ ما ينحسب إلا إذا اختير صراحةً.',
    },
    privacy: {
      title: 'خصوصيتك: وش يصير لبياناتك بالضبط',
      intro: 'بدون كلام كبير، هذا اللي يصير فعلاً:',
      items: [
        {
          icon: 'shield',
          title: 'بيانات كل بيت معزولة',
          desc: 'قاعدة البيانات تطبّق أمان مستوى الصفوف (RLS)، والخادم يتحقق من عضويتك في كل طلب، فما يشوف بيانات بيتكم إلا أعضاؤه.',
        },
        {
          icon: 'lock',
          title: 'مشفّرة أثناء النقل والتخزين',
          desc: 'الاتصال مشفّر (HTTPS)، والبيانات مخزّنة مشفّرة عند منصة الاستضافة.',
        },
        {
          icon: 'sparkles',
          title: 'الذكاء الاصطناعي يشوف المحادثة والفاتورة',
          desc: 'نص المحادثة وصور الفواتير تنرسل لمزوّد ذكاء اصطناعي (Google Gemini) عشان يطلّع منها المصروف. لا تكتب فيها شي ما تحتاجه.',
        },
        {
          icon: 'noSms',
          title: 'ما نقرأ رسائلك النصية أبداً',
          desc: 'التطبيق ما يطلب صلاحية الرسائل (SMS) ولا يقرأها. المصروف يدخل بس باللي تسجّله أنت.',
        },
        {
          icon: 'calendar',
          title: 'احذف حسابك، ومعك 30 يوماً للتراجع',
          desc: 'احذفه من إعدادات التطبيق أو من صفحة حذف الحساب. الحذف يتم بعد 30 يوماً من تأكيدك، وتقدر تلغيه قبلها. تسجيل الدخول وحده ما يلغي الحذف.',
        },
        {
          icon: 'users',
          title: 'وش يبقى بعد الحذف',
          desc: 'ينحذف دخولك وحساباتك الشخصية وملاحظاتك وصور فواتيرك. اللي أضفته في منزل باقٍ يبقى باسم «عضو محذوف». النصوص اللي كتبها غيرك وأسماء المنازل ما تتعدل. وما نقدر نحذف نسخ الرسائل في بريد المطوّر ولا سجلات Railway ولا نسخ Supabase الاحتياطية ولا سجلات تدقيق المصادقة فيه. طلبات نموذج الحذف تبقى 90 يوماً.',
        },
      ],
    },
    faq: {
      title: 'أسئلة شائعة',
      items: [
        {
          q: 'هل التطبيق متوفر الحين؟',
          a: 'التطبيق للجوال وهو في مرحلة الوصول المبكر. سجّل بريدك تحت ونتواصل معك لما نفتح دعوات جديدة.',
        },
        {
          q: 'هل يربط على حسابي البنكي أو يقرأ رسائل البنك؟',
          a: 'لا. ما فيه ربط بنكي حالياً، وما نقرأ الرسائل النصية. تسجّل المصروف بالمحادثة أو بالصوت أو بتصوير الفاتورة أو يدوياً.',
        },
        {
          q: 'راتبي ما ينزل يوم 27، يمشي معي؟',
          a: 'إيه. كل بيت يحدّد يوم راتبه (من 1 إلى 31)، والدورة تبدأ من يوم الراتب وتنتهي اليوم اللي قبل الراتب الجاي. يغيّره مشرف المنزل من الإعدادات.',
        },
        {
          q: 'هل يشتغل بدون إنترنت؟',
          a: 'تقدر تسجّل مصروفك بدون إنترنت، وينرفع تلقائياً لما يرجع الاتصال. فهم نص المحادثة وقراءة الفاتورة يصيرون بعد ما يرجع الاتصال.',
        },
        {
          q: 'مين يشوف مصاريفي؟',
          a: 'داخل التطبيق يشوفها أعضاء منزلك فقط. وتعديل أو حذف مصروف سجّله عضو ثاني متاح لمشرفي المنزل فقط.',
        },
        {
          q: 'هل التطبيق يقسم المصاريف بين الزوج والزوجة؟',
          a: 'لا. في وضع الأسرة النفقة على الزوج، واللي تدفعه الزوجة للبيت ينسجّل دَين لها عليه. قسمة المصاريف تكون بس في سكن الزملاء.',
        },
      ],
    },
    earlyAccess: {
      badge: 'الوصول المبكر',
      title: 'جرّب التطبيق قبل الإطلاق',
      desc: 'اترك بريدك ونتواصل معك لما نفتح دعوات جديدة.',
      placeholder: 'بريدك الإلكتروني',
      button: 'سجّلني',
      sending: 'جارٍ الإرسال...',
      successMsg: 'وصلنا طلبك. بنراسلك على بريدك لما يجهز مكانك.',
      errorInvalid: 'يرجى إدخال بريد إلكتروني صحيح.',
      errorRateLimited: 'وصلنا عدد كبير من الطلبات منك. حاول مرة أخرى بعد قليل.',
      errorUnavailable: 'تعذر إرسال طلبك حالياً. حاول لاحقاً أو راسلنا مباشرة على البريد أدناه.',
      errorNetwork: 'تعذر الاتصال بالخادم. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.',
      contactInfo: 'عندك سؤال أو اقتراح؟ راسلنا على',
    },
    footer: {
      rights: 'جميع الحقوق محفوظة.',
      contact: 'تواصل معنا',
      deleteAccount: 'حذف الحساب',
      deleteAccountHref: '/delete-account',
    },
    auth: {
      signIn: 'تسجيل الدخول',
      signUp: 'إنشاء حساب جديد',
      signOut: 'تسجيل الخروج',
      email: 'البريد الإلكتروني',
      password: 'كلمة المرور',
      displayName: 'الاسم أو اللقب',
      signInTitle: 'تسجيل الدخول إلى حسابك',
      signUpTitle: 'إنشاء حساب جديد للأسرة',
      submitSignIn: 'دخول',
      submitSignUp: 'إنشاء الحساب والبدء',
      noAccount: 'ليس لديك حساب بعد؟ سجّل الآن',
      hasAccount: 'لديك حساب بالفعل؟ سجّل دخولك',
      loading: 'جارٍ التحقق...',
      errorGeneric: 'حدث خطأ في المصادقة. يرجى التأكد من البيانات والمحاولة مجدداً.',
      close: 'إغلاق',
    },
    portal: {
      dashboard: 'لوحة التحكم',
      transactions: 'سجل العمليات',
      budgets: 'الميزانيات والبنود',
      householdDefault: 'المنزل',
      cycleEndsIn: 'ينتهي الشهر المالي بعد',
      days: 'أيام',
      salaryDay: 'يوم الراتب',
      totalBalance: 'الرصيد المتبقي',
      totalIncome: 'إجمالي الدخل',
      totalSpent: 'إجمالي المصروفات',
      installmentsTitle: 'الأقساط وخطط الدفع النشطة (تمارا، تابي، بنوك)',
      recurringBillsTitle: 'الفواتير والالتزامات الدورية القادمة',
      recentTransactions: 'آخر العمليات المسجلة',
      viewAll: 'عرض الكل',
      newTransaction: 'إضافة عملية جديدة',
      category: 'التصنيف',
      amount: 'المبلغ',
      description: 'الوصف أو المحل',
      date: 'التاريخ',
      save: 'حفظ',
      cancel: 'إلغاء',
      type: 'نوع العملية',
      expense: 'مصروف',
      income: 'دخل',
      searchPlaceholder: 'بحث في العمليات...',
      allCategories: 'جميع التصنيفات',
      budgetsTitle: 'مخصصات الميزانية الشهرية',
      budgetLimit: 'المخصص المعتمد',
      spent: 'المصروف',
      remaining: 'المتبقي',
      wifeAllowanceTitle: 'مصروف الزوجة الشخصي',
      wifeAllowanceSubtitle: 'مخصص دوري محمي وفق أحكام النفقة الشرعية',
      subAllocationsTitle: 'التخصيصات الفرعية للأبناء والبنود',
      noData: 'لا توجد بيانات مسجلة حتى الآن.',
      activePlans: 'خطة نشطة',
      monthlyDue: 'القسط الشهري',
    },
    a11y: {
      pageTitle: 'قوام المال Qawam Money | اعرف كم باقي لك لين الراتب',
      skipToContent: 'تخطَّ إلى المحتوى الرئيسي',
      switchToEnglish: 'التبديل إلى الإنجليزية',
      switchToArabic: 'التبديل إلى العربية',
      emailLabel: 'البريد الإلكتروني',
      mainNav: 'التنقل الرئيسي',
      footerNav: 'روابط أسفل الصفحة',
      home: 'الصفحة الرئيسية',
    },
  },
  en: {
    brand: {
      name: 'Qawam Money قوام المال',
      shortName: 'Qawam Money',
      tagline: 'Household budget by salary cycle',
    },
    nav: {
      features: 'Features',
      nafaqah: 'Wife Expenses',
      privacy: 'Privacy',
      faq: 'FAQ',
      cta: 'Early access',
    },
    hero: {
      badge: 'Mobile app · Early access open',
      title: 'Know what’s left until payday',
      subtitle:
        'Your household budget follows your salary cycle, from one payday to the next. Log expenses by voice or a receipt photo, and keep wife expenses between spouses or a shared flat’s split clear.',
      ctaPrimary: 'Join early access',
      ctaSecondary: 'How wife expenses work',
      note: 'The app speaks Arabic, English and Urdu.',
    },
    demo: {
      label: 'Example',
      sample: 'Sample amounts; dates are calculated from today.',
      paydayLabel: 'Your household’s payday',
      daysLeftLabel: 'Until payday',
      daysLeft: {
        one: '1 day',
        other: '{val} days',
      },
      cycleLabel: 'Current cycle',
      budgetLabel: 'Cycle budget',
      spentLabel: 'Spent',
      leftLabel: 'Left',
      dailyLabel: 'You can spend per day until payday',
      perDay: 'per day',
    },
    money: {
      unit: 'SAR',
      unitAfter: false,
      dateLocale: 'en-GB',
    },
    features: {
      title: 'What the app does for you',
      subtitle: 'Four things, kept simple.',
      items: [
        {
          icon: 'calendar',
          title: 'Know what’s left until payday',
          desc: 'Set your household’s payday (the 27th or any other day). The app follows your salary cycle, not the calendar month: what you’ve spent, what’s left, and how much you can spend per day until the next salary.',
        },
        {
          icon: 'mic',
          title: 'Log expenses by voice or a receipt photo',
          desc: 'Type or say “paid 85 riyals for fuel” and the app understands it. Or snap the receipt: it reads the ZATCA tax QR code when there is one and fills in the amount, store and category. You confirm before anything is saved.',
        },
        {
          icon: 'scale',
          title: 'Wife expenses between spouses, made clear',
          desc: 'Household maintenance is the husband’s duty. What the wife pays for the home from her own money is recorded as his debt to her, and her personal purchases come out of her personal allowance. Nothing is split between spouses by percentage.',
        },
        {
          icon: 'users',
          title: 'A fair split for shared flats',
          desc: 'In a shared flat everyone logs what they paid. The app splits shared costs equally and simplifies the debts: who pays whom and how much, in the fewest transfers.',
        },
      ],
      nafaqahLink: 'See how wife expenses work',
    },
    nafaqah: {
      badge: 'Family mode',
      title: 'How wife expenses work',
      intro:
        'In family mode the app follows the rule that household maintenance is the husband’s responsibility: housing, food and the home’s needs. It never splits an expense between spouses by percentage. Each expense is handled by who paid and for whom:',
      cases: [
        {
          who: 'The husband pays for the home or the children',
          result: 'An ordinary household expense. Nobody owes anything.',
          tone: 'neutral',
        },
        {
          who: 'The wife pays for the home or the children from her own money',
          result: 'Recorded as a debt the husband owes her. The app shows what he owes her, and he can repay it in full or in parts.',
          tone: 'debt',
        },
        {
          who: 'The wife buys something personal for herself',
          result: 'Counted against her personal allowance for the cycle, which the husband sets. It is not a debt and not part of the household budget.',
          tone: 'allowance',
        },
      ],
      exampleTitle: 'Example: what the husband owes his wife',
      exampleRows: [
        { label: 'Wife paid for groceries', amount: 320 },
        { label: 'Wife paid for school supplies', amount: 180 },
        { label: 'Husband repaid part', amount: 200, negative: true },
        { label: 'Still owed to her by her husband', amount: 300, total: true },
      ],
      footnote: 'Family mode applies when a household member has the “wife” role. A voluntary contribution from the wife is never assumed; it only counts when explicitly chosen.',
    },
    privacy: {
      title: 'Privacy: exactly what happens to your data',
      intro: 'No big words, just what actually happens:',
      items: [
        {
          icon: 'shield',
          title: 'Each household’s data is isolated',
          desc: 'The database enforces row-level security (RLS) and the server checks your membership on every request, so only your household’s members can see its data.',
        },
        {
          icon: 'lock',
          title: 'Encrypted in transit and at rest',
          desc: 'Connections use HTTPS, and the data is stored encrypted by our hosting platform.',
        },
        {
          icon: 'sparkles',
          title: 'An AI reads your chat and receipts',
          desc: 'Chat text and receipt photos are sent to an AI provider (Google Gemini) to extract the expense. Leave out anything it doesn’t need.',
        },
        {
          icon: 'noSms',
          title: 'We never read your SMS',
          desc: 'The app does not ask for SMS permission and does not read your messages. Expenses come only from what you record.',
        },
        {
          icon: 'calendar',
          title: 'Delete your account, with 30 days to change your mind',
          desc: 'Delete it in the app’s Settings or on the account deletion page. It happens 30 days after you confirm, and you can cancel before then. Signing in alone does not cancel it.',
        },
        {
          icon: 'users',
          title: 'What stays after deletion',
          desc: 'Your login, personal accounts, notes and receipt images are deleted. Entries you added to a household that still exists stay as “Deleted member”. Text other people typed and household names are not edited. We cannot remove copies of emails in the developer’s mailbox, Railway logs, Supabase backups or its authentication audit log. Requests sent through the deletion form are kept for 90 days.',
        },
      ],
    },
    faq: {
      title: 'Questions',
      items: [
        {
          q: 'Can I use the app now?',
          a: 'The mobile app is in early access. Leave your email below and we will contact you when we open new invitations.',
        },
        {
          q: 'Does it connect to my bank or read bank SMS?',
          a: 'No. There is no bank connection today, and we do not read text messages. You record expenses by chat, voice, a receipt photo or by hand.',
        },
        {
          q: 'My salary doesn’t arrive on the 27th. Does it still work?',
          a: 'Yes. Each household sets its own payday (1 to 31). A cycle starts on payday and ends the day before the next one. A household admin changes it in Settings.',
        },
        {
          q: 'Does it work offline?',
          a: 'You can record expenses offline; they upload automatically when you are back online. Understanding chat text and reading receipts happens once you are online again.',
        },
        {
          q: 'Who can see my expenses?',
          a: 'In the app, only the members of your household. Editing or deleting an expense another member recorded is limited to household admins.',
        },
        {
          q: 'Does the app split expenses between husband and wife?',
          a: 'No. In family mode household maintenance is on the husband, and what the wife pays for the home is recorded as his debt to her. Splitting costs is only for shared flats.',
        },
      ],
    },
    earlyAccess: {
      badge: 'Early access',
      title: 'Try the app before launch',
      desc: 'Leave your email and we will contact you when we open new invitations.',
      placeholder: 'Your email',
      button: 'Sign me up',
      sending: 'Sending...',
      successMsg: 'Got it. We will email you when your spot is ready.',
      errorInvalid: 'Please enter a valid email address.',
      errorRateLimited: 'We received many requests from you. Please try again shortly.',
      errorUnavailable: 'We could not send your request right now. Please try later or email us at the address below.',
      errorNetwork: 'Could not reach the server. Check your connection and try again.',
      contactInfo: 'Questions or ideas? Email us at',
    },
    footer: {
      rights: 'All rights reserved.',
      contact: 'Contact us',
      deleteAccount: 'Delete account',
      deleteAccountHref: '/delete-account?lang=en',
    },
    auth: {
      signIn: 'Sign In',
      signUp: 'Create Account',
      signOut: 'Sign Out',
      email: 'Email address',
      password: 'Password',
      displayName: 'Name or nickname',
      signInTitle: 'Sign in to your account',
      signUpTitle: 'Create a household account',
      submitSignIn: 'Sign In',
      submitSignUp: 'Create Account & Start',
      noAccount: "Don't have an account? Sign up now",
      hasAccount: 'Already have an account? Sign in',
      loading: 'Authenticating...',
      errorGeneric: 'Authentication error. Please verify your details and try again.',
      close: 'Close',
    },
    portal: {
      dashboard: 'Dashboard',
      transactions: 'Transactions',
      budgets: 'Budgets & Allocations',
      householdDefault: 'Household',
      cycleEndsIn: 'Financial cycle ends in',
      days: 'days',
      salaryDay: 'Payday',
      totalBalance: 'Net Balance',
      totalIncome: 'Total Income',
      totalSpent: 'Total Spent',
      installmentsTitle: 'Active Installment & BNPL Plans (Tamara, Tabby, Banks)',
      recurringBillsTitle: 'Upcoming Recurring Bills & Commitments',
      recentTransactions: 'Recent Transactions',
      viewAll: 'View All',
      newTransaction: 'New Transaction',
      category: 'Category',
      amount: 'Amount',
      description: 'Description or Merchant',
      date: 'Date',
      save: 'Save',
      cancel: 'Cancel',
      type: 'Type',
      expense: 'Expense',
      income: 'Income',
      searchPlaceholder: 'Search transactions...',
      allCategories: 'All Categories',
      budgetsTitle: 'Monthly Budget Allocations',
      budgetLimit: 'Approved Budget',
      spent: 'Spent',
      remaining: 'Remaining',
      wifeAllowanceTitle: "Wife's Personal Allowance",
      wifeAllowanceSubtitle: 'Protected periodic allowance adhering to family expense rules',
      subAllocationsTitle: 'Sub-allocations for Dependents & Categories',
      noData: 'No records found yet.',
      activePlans: 'active plan(s)',
      monthlyDue: 'Monthly due',
    },
    a11y: {
      pageTitle: 'Qawam Money قوام المال | Know what’s left until payday',
      skipToContent: 'Skip to main content',
      switchToEnglish: 'Switch to English',
      switchToArabic: 'Switch to Arabic',
      emailLabel: 'Email address',
      mainNav: 'Main navigation',
      footerNav: 'Footer links',
      home: 'Home',
    },
  },
};

/**
 * The account deletion page (/delete-account) only. It offers Urdu with `?lang=ur`, which the
 * rest of the site does not have, so it keeps its own dictionary. Every sentence here is a
 * statement about what the code does: keep it in step with the deletion migrations, the worker
 * and docs/runbooks/account-deletion-purge.md, and promise nothing the code does not do.
 */
export type DeleteAccountLanguage = Language | 'ur';

export const DELETE_ACCOUNT_LANGUAGES: DeleteAccountLanguage[] = ['ar', 'en', 'ur'];

export interface DeleteAccountSection {
  title: string;
  intro?: string;
  items: string[];
}

export interface DeleteAccountDictionary {
  /** The language's own name, for the switcher. */
  languageName: string;
  dir: 'rtl' | 'ltr';
  /** BCP 47 locale for dates (Gregorian calendar, Western digits). */
  dateLocale: string;
  /** The word this language's visitors are asked to type. The server accepts all three. */
  confirmationWord: string;
  pageTitle: string;
  skipToContent: string;
  home: string;
  languageNav: string;
  /** Shown in Urdu on the landing page, which has no Urdu. The other two are its source text. */
  landingNotice: { body: string; link: string };
  appName: string;
  title: string;
  intro: string;
  how: DeleteAccountSection;
  window: DeleteAccountSection;
  deleted: DeleteAccountSection;
  kept: DeleteAccountSection;
  notEdited: DeleteAccountSection;
  outOfReach: DeleteAccountSection;
  admins: DeleteAccountSection;
  contact: string;
  rights: string;
  signIn: {
    title: string;
    intro: string;
    email: string;
    password: string;
    submit: string;
    submitting: string;
    error: string;
    forgot: string;
  };
  request: {
    title: string;
    intro: string;
    email: string;
    message: string;
    submit: string;
    submitting: string;
    receivedTitle: string;
    sentBody: string;
    capturedBody: string;
    notDeleted: string;
    reference: string;
    errorInvalid: string;
    errorRateLimited: string;
    errorUnavailable: string;
    errorNetwork: string;
  };
  account: {
    signedInAs: string;
    signOut: string;
    loading: string;
    loadError: string;
    retry: string;
    flowTitle: string;
    flowIntro: string;
    settlementWarning: string;
    householdsTitle: string;
    noHouseholds: string;
    positionSole: string;
    positionCoAdmin: string;
    positionMember: string;
    choiceTitle: string;
    choiceTransfer: string;
    choiceDelete: string;
    choiceDeleteWarning: string;
    successorLabel: string;
    successorPlaceholder: string;
    successorPending: string;
    successorUnnamed: string;
    noSuccessor: string;
    password: string;
    passwordHint: string;
    typedWord: string;
    submit: string;
    submitting: string;
    pendingTitle: string;
    pendingDate: string;
    pendingUsable: string;
    pendingSignIn: string;
    pendingHouseholds: string;
    cancel: string;
    cancelling: string;
    cancelled: string;
    inProgressTitle: string;
    inProgressBody: string;
    startingTitle: string;
    startingBody: string;
    stoppedTitle: string;
    stoppedBody: string;
    stoppedPartwayTitle: string;
    stoppedPartwayBody: string;
    errors: {
      password: string;
      reauthenticationRequired: string;
      confirmationMismatch: string;
      choiceMissing: string;
      choiceInvalid: string;
      successorInvalid: string;
      successorPending: string;
      inProgress: string;
      generic: string;
    };
  };
}

export const deleteAccountTranslations: Record<DeleteAccountLanguage, DeleteAccountDictionary> = {
  ar: {
    languageName: 'العربية',
    dir: 'rtl',
    dateLocale: 'ar-SA-u-ca-gregory-nu-latn',
    confirmationWord: 'حذف',
    pageTitle: 'حذف الحساب | قوام المال Qawam Money',
    skipToContent: 'تخطَّ إلى المحتوى الرئيسي',
    home: 'الصفحة الرئيسية',
    languageNav: 'اللغة',
    landingNotice: {
      body: 'هذه الصفحة غير متوفرة بالأردية، لذلك تظهر بالإنجليزية.',
      link: 'اقرأ عن حذف الحساب وبياناتك بالأردية',
    },
    appName: 'قوام المال · Qawam Money',
    title: 'حذف حسابك في قوام المال',
    intro:
      'توضح هذه الصفحة كيف تحذف حسابك في تطبيق قوام المال (Qawam Money)، وما الذي يُحذف، وما الذي يبقى، وكيف تتراجع. لا يتم الحذف فوراً: يُحذف حسابك بعد 30 يوماً من تأكيدك.',
    how: {
      title: 'كيف تحذف حسابك',
      items: [
        'من التطبيق: افتح الإعدادات واختر حذف الحساب.',
        'من هذه الصفحة: سجّل الدخول أدناه، وأكّد كلمة المرور، واكتب كلمة التأكيد.',
        'إذا لم تستطع تسجيل الدخول: أرسل نموذج الطلب أدناه. يتولاه شخص، ولا يحذف النموذج شيئاً بنفسه.',
      ],
    },
    window: {
      title: 'مهلة الثلاثين يوماً وكيف تلغي الحذف',
      items: [
        'بعد تأكيدك يُجدول حسابك للحذف بعد 30 يوماً، ويظهر لك التاريخ في التطبيق وفي هذه الصفحة.',
        'خلال هذه المدة يبقى حسابك عاملاً، بما في ذلك التصدير، لكن لا يمكنك الانضمام إلى منزل أو إنشاء منزل أو أن تصبح مشرفاً.',
        'تسجيل الدخول وحده لا يلغي الحذف. لإلغائه اختر الإلغاء من إعدادات التطبيق، أو سجّل الدخول في هذه الصفحة واختر الإلغاء.',
        'عندما يحين التاريخ يبدأ الحذف، ولا يمكن إلغاؤه بعد ذلك. وقد ينتهي بعد التاريخ إذا احتاجت إحدى خطواته إلى إعادة المحاولة.',
        'إذا أصبحت خلال المهلة المشرف الأساسي أو الوحيد لمنزل فيه أعضاء آخرون، يُبلَّغ ذلك المنزل بحذفه قبل 7 أيام، ويتأخر موعد حذف حسابك إلى نهايتها.',
        'قد نراسلك بالبريد قبل التاريخ بنحو 7 أيام وبيوم واحد وعند اكتمال الحذف، وقد نراسل أعضاء المنزل عند حذف منزلهم. يتوقف ذلك على توفر خدمة البريد لدينا، فلا تعتمد عليه: العبرة بالتاريخ الظاهر في التطبيق وفي هذه الصفحة.',
      ],
    },
    deleted: {
      title: 'ما الذي يُحذف',
      items: [
        'بيانات دخولك وبريدك الإلكتروني واسمك الظاهر.',
        'حساباتك الشخصية، والدخل المسجل فيها، والتحويلات بينها.',
        'الملاحظات التي كتبتها على مصروفاتك ودخلك وتحويلاتك.',
        'صور الفواتير المرفقة بمصروفاتك.',
        'عضويتك في كل المنازل، وأي تابع مرتبط بك.',
        'إذا كنتِ الزوجة في منزل أسرة: مصروفاتك الشخصية ومصروفك الشخصي المحدد ودفتر المستحق لك. وإن كان زوجك ما زال مديناً لكِ بمبلغ، يعرض التطبيق عليه المبلغ عند جدولة الحذف (وقد نرسله إليه بالبريد)، أو يعرضه على مديري المنزل إن لم يُحدَّد الزوج؛ وبعد الحذف لا يبقى في المنزل إلا المبلغ المستحق دون اسم، حتى يسجّله هو أو أحد المديرين مدفوعاً أو أنكِ أبرأتِه منه.',
        'الرسائل التي أرسلتها إلينا من هذا البريد عبر نماذج التواصل والدعم.',
        'أي منزل أنت عضوه الوحيد، بكل ما فيه.',
      ],
    },
    kept: {
      title: 'ما الذي يبقى دون اسمك',
      items: [
        'ما أضفته في منزل ما زال قائماً يبقى فيه بمبلغه وتاريخه وتصنيفه ومتجره وبنوده، ويظهر باسم «عضو محذوف». ويُزال اسمك وبريدك الإلكتروني من اسم المتجر وأسماء البنود.',
        'الدخل الذي سجلته في حساب مشترك والتحويلات من الحساب المشترك وإليه تبقى دون اسمك أو ملاحظاتك، فلا يتغير رصيد الحساب المشترك.',
        'الحسابات المشتركة التي تملكها تنتقل إلى مشرف آخر، ويبقى رصيدها كما هو، ويُزال اسمك من أسمائها.',
        'قد تتغير التسويات في ذلك المنزل: لا تُحتسب المصروفات التي دفعتها أنت، وتُعاد قسمة المصروفات المتساوية في الدورة الحالية، فقد تتغير ديون الأعضاء الآخرين. أرصدة الحسابات ومصروف الميزانيات لا تتغير.',
        'سجل لا يحوي اسماً ولا بريداً ولا معرّف مستخدم، يبيّن أن عملية حذف قد اكتملت.',
      ],
    },
    notEdited: {
      title: 'ما الذي لا يُعدَّل',
      items: [
        'النصوص التي كتبها الأعضاء الآخرون، مثل ملاحظة تذكرك بالاسم، تبقى كما كتبوها. ونزيل أيضاً بريدك الإلكتروني من سجلات المنزل.',
        'أسماء المنازل تبقى كما هي، حتى لو تضمن أحدها اسمك، إلا أن بريدك الإلكتروني يُستبدل فيها أيضاً.',
      ],
    },
    outOfReach: {
      title: 'ما لا نستطيع حذفه',
      intro: 'لا يصل الحذف إلى ما يلي، ولا نستطيع إزالة سجلات بعينها منه:',
      items: [
        'نسخ الرسائل الموجودة في بريد المطوّر، مثل طلبات الدعم والحذف.',
        'سجلات خوادم Railway.',
        'النسخ الاحتياطية لقاعدة بيانات Supabase.',
        'سجلات تدقيق المصادقة في Supabase.',
      ],
    },
    admins: {
      title: 'إذا كنت تدير منزلاً',
      items: [
        'إذا كنت المشرف الأساسي أو الوحيد لمنزل فيه أعضاء آخرون، فعليك الاختيار قبل جدولة الحذف: تعيين عضو آخر مشرفاً أساسياً أو حذف المنزل.',
        'التعيين يتم فوراً. تبقى مشرفاً مساعداً حتى الحذف النهائي، ولا يعيد الإلغاء إليك صفة المشرف الأساسي.',
        'حذف المنزل يزيل كل ما فيه عند حلول التاريخ، ومنها حسابات الأعضاء الآخرين ومصروفاتهم في هذا المنزل ودفتر الزوجة. يحتفظ الأعضاء بحساباتهم للدخول، لكنهم لا يعودون أعضاء فيه.',
        'حتى ذلك الحين يبقى المنزل نشطاً ويرى أعضاؤه تنبيهاً ليصدّروا ما يريدون الاحتفاظ به، ولا يقبل أعضاء جدداً. وإلغاء حذف حسابك يلغي ذلك.',
        'المشرف المساعد والعضو العادي يغادران فقط، ويستمر المنزل.',
      ],
    },
    contact: 'عندك سؤال؟ راسلنا على',
    rights: 'جميع الحقوق محفوظة.',
    signIn: {
      title: 'احذف حسابك بنفسك',
      intro: 'سجّل الدخول لجدولة الحذف أو إلغائه. تسجيل الدخول وحده لا يبدأ شيئاً ولا يلغي شيئاً.',
      email: 'البريد الإلكتروني',
      password: 'كلمة المرور',
      submit: 'تسجيل الدخول',
      submitting: 'جارٍ التحقق...',
      error: 'تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور وحاول مرة أخرى.',
      forgot: 'نسيت كلمة المرور؟ استعدها من التطبيق، أو أرسل نموذج الطلب أدناه.',
    },
    request: {
      title: 'لا تستطيع تسجيل الدخول؟ أرسل طلب حذف',
      intro:
        'هذا النموذج لا يحذف شيئاً: يخزّن طلبك ويرسله بالبريد إلى المطوّر، الذي يتولاه يدوياً وقد يرد على هذا العنوان، فاكتب بريد حسابك. إرساله لا يبحث عن أي حساب ولا يجدول حذفه، ولن تصلك رسالة تلقائية. نحتفظ بالطلب المخزّن 90 يوماً ثم نزيله.',
      email: 'بريد حسابك',
      message: 'رسالة (اختياري)',
      submit: 'إرسال الطلب',
      submitting: 'جارٍ الإرسال...',
      receivedTitle: 'وصلنا طلبك',
      sentBody: 'خُزّن طلبك وأُرسل إلى المطوّر، الذي يتولاه يدوياً.',
      capturedBody: 'خُزّن طلبك، لكن الرسالة التي تنبّه المطوّر تعذّر إرسالها حالياً، فقد يتأخر الاطلاع عليه.',
      notDeleted: 'لم يُحذف حسابك ولم يُجدول حذفه بهذا الطلب.',
      reference: 'رقم المرجع:',
      errorInvalid: 'يرجى إدخال بريد إلكتروني صحيح.',
      errorRateLimited: 'وصلنا عدد كبير من الطلبات. حاول مرة أخرى بعد قليل.',
      errorUnavailable: 'لم يصلنا طلبك. حاول لاحقاً أو راسلنا مباشرة على البريد أدناه.',
      errorNetwork: 'تعذر الاتصال بالخادم، ولم يصلنا طلبك. تحقق من اتصالك وحاول مرة أخرى.',
    },
    account: {
      signedInAs: 'مسجّل الدخول باسم',
      signOut: 'تسجيل الخروج',
      loading: 'جارٍ التحميل...',
      loadError: 'تعذر تحميل حالة حسابك. حاول مرة أخرى أو استخدم نموذج الطلب أدناه.',
      retry: 'إعادة المحاولة',
      flowTitle: 'جدولة حذف حسابك',
      flowIntro: 'سيُحذف حسابك بعد 30 يوماً من التأكيد. اقرأ هذه الصفحة أولاً، وصدّر من التطبيق ما تريد الاحتفاظ به.',
      settlementWarning: 'قد تتغير التسويات وديون الأعضاء الآخرين في المنازل التي تبقى بعدك. أرصدة الحسابات ومصروف الميزانيات لا تتغير.',
      householdsTitle: 'منازلك',
      noHouseholds: 'لست عضواً في أي منزل.',
      positionSole: '{name}: أنت عضوه الوحيد، فسيُحذف بكل ما فيه.',
      positionCoAdmin: '{name}: أنت مشرف مساعد، فستغادره ويستمر المنزل.',
      positionMember: '{name}: ستغادره ويستمر المنزل.',
      choiceTitle: '{name}: أنت مشرفه الأساسي. اختر ما يحدث له:',
      choiceTransfer: 'تعيين عضو آخر مشرفاً أساسياً (يتم فوراً)',
      choiceDelete: 'حذف هذا المنزل بكل ما فيه',
      choiceDeleteWarning: 'سيُزال كل ما فيه عند حلول التاريخ، ومنها حسابات الأعضاء الآخرين ومصروفاتهم في هذا المنزل ودفتر الزوجة. يحتفظ الأعضاء بحساباتهم للدخول.',
      successorLabel: 'المشرف الأساسي الجديد',
      successorPlaceholder: 'اختر عضواً',
      successorPending: '(مجدول للحذف)',
      successorUnnamed: 'عضو بلا اسم',
      noSuccessor: 'لا يوجد عضو يمكنه تولي الإدارة، فالخيار المتاح هو حذف المنزل.',
      password: 'كلمة المرور',
      passwordHint: 'نطلبها مرة أخرى للتأكد من أنك صاحب الحساب.',
      typedWord: 'اكتب «{word}» للتأكيد',
      submit: 'جدولة الحذف بعد 30 يوماً',
      submitting: 'جارٍ الجدولة...',
      pendingTitle: 'حسابك مجدول للحذف',
      pendingDate: 'موعد الحذف:',
      pendingUsable: 'حتى ذلك الحين يبقى حسابك عاملاً.',
      pendingSignIn: 'تسجيل الدخول وحده لا يلغي الحذف. للاحتفاظ بحسابك اختر إلغاء الحذف.',
      pendingHouseholds: 'منازل ستُحذف أيضاً:',
      cancel: 'إلغاء الحذف',
      cancelling: 'جارٍ الإلغاء...',
      cancelled: 'أُلغي الحذف ويبقى حسابك. ما تم من تعيين مشرف أساسي يبقى كما هو.',
      inProgressTitle: 'بدأ حذف حسابك',
      inProgressBody: 'حُذف بعض بياناتك بالفعل، لذلك لم يعد بالإمكان إلغاء الحذف. إذا كان عندك سؤال فراسلنا على البريد أدناه.',
      startingTitle: 'حذف حسابك يبدأ الآن',
      startingBody: 'لم يُحذف شيء بعد، لذلك ما زال بإمكانك إلغاء الحذف.',
      stoppedTitle: 'توقف حذف حسابك قبل أن يُحذف أي شيء',
      stoppedBody: 'تعثرت إحدى خطوات الحذف. لم يُحذف شيء بعد، لذلك ما زال بإمكانك إلغاء الحذف، وإلا فسنتابع الأمر.',
      stoppedPartwayTitle: 'توقف حذف حسابك في منتصفه',
      stoppedPartwayBody: 'حُذف بعض بياناتك بالفعل، لذلك لم يعد بالإمكان إلغاء الحذف. سنتابع الأمر. إذا كان عندك سؤال فراسلنا على البريد أدناه.',
      errors: {
        password: 'تعذر تأكيد كلمة المرور. تحقق منها وحاول مرة أخرى.',
        reauthenticationRequired: 'لتأكيد الطلب أدخل كلمة المرور مرة أخرى.',
        confirmationMismatch: 'كلمة التأكيد غير مطابقة.',
        choiceMissing: 'اختر ما يحدث لكل منزل تديره.',
        choiceInvalid: 'تغيّرت منازلك. حدّث الصفحة واختر مرة أخرى.',
        successorInvalid: 'اختر عضواً آخر من هذا المنزل.',
        successorPending: 'هذا العضو مجدول للحذف. اختر عضواً آخر.',
        inProgress: 'حُذف بعض بياناتك بالفعل، لذلك لا يمكن إلغاء الحذف.',
        generic: 'تعذر إتمام الطلب، ولم يتغير شيء في حسابك. حاول مرة أخرى.',
      },
    },
  },
  en: {
    languageName: 'English',
    dir: 'ltr',
    dateLocale: 'en-GB',
    confirmationWord: 'DELETE',
    pageTitle: 'Delete your account | Qawam Money قوام المال',
    skipToContent: 'Skip to main content',
    home: 'Home',
    languageNav: 'Language',
    landingNotice: {
      body: 'This page is not available in Urdu, so it is shown in English.',
      link: 'Read about account deletion and your data in Urdu',
    },
    appName: 'Qawam Money · قوام المال',
    title: 'Delete your Qawam Money account',
    intro:
      'This page explains how to delete your account in the Qawam Money (قوام المال) app, what is removed, what stays, and how to change your mind. It does not happen at once: your account is deleted 30 days after you confirm.',
    how: {
      title: 'How to delete your account',
      items: [
        'In the app: open Settings and choose to delete your account.',
        'On this page: sign in below, confirm your password and type the confirmation word.',
        'If you can’t sign in: send the request form below. A person handles it, and the form deletes nothing by itself.',
      ],
    },
    window: {
      title: 'The 30-day window and how to cancel',
      items: [
        'After you confirm, your account is scheduled for deletion 30 days later, and you can see the date in the app and on this page.',
        'During those 30 days your account keeps working, including exports, but you cannot join or create a household or be made an admin.',
        'Signing in alone does not cancel the deletion. To cancel, choose Cancel in the app’s Settings, or sign in on this page and choose Cancel.',
        'When the date comes, deletion starts and can no longer be cancelled. It can finish after the date if a step has to be retried.',
        'If during the window you become the primary or only admin of a household with other members, that household gets 7 days’ notice of its deletion, and your own deletion moves to the end of that notice.',
        'We may email you about 7 days and 1 day before the date and when deletion is done, and may email a household’s members when it is being deleted. This depends on our email service being available, so don’t rely on it: the date in the app and on this page is what counts.',
      ],
    },
    deleted: {
      title: 'What is deleted',
      items: [
        'Your login, email address and display name.',
        'Your personal accounts, the income recorded into them, and transfers between them.',
        'The notes you wrote on your entries, income and transfers.',
        'Receipt images attached to your entries.',
        'Your membership of every household, and any dependent entry linked to you.',
        'If you are the wife in a family household: your personal expense entries, your set allowance and the ledger of what you are owed. If your husband still owes you money, the app shows him the amount when you schedule the deletion (and we may email him), or shows the household’s admins if no husband is set; after the deletion the household keeps only the amount still owed, with no name, until he or an admin records it as paid or as waived by you.',
        'Messages you sent us from this email address through the contact and support forms.',
        'Any household where you are the only member, with everything in it.',
      ],
    },
    kept: {
      title: 'What stays, without your name',
      items: [
        'What you added to a household that still exists stays there, with its amount, date, category, store and item lines, and the entries show as “Deleted member”. Your name and email address are removed from their store and item names.',
        'Income you recorded into a shared pool, and transfers to or from a shared pool, stay without your name or notes, so the pool’s balance does not change.',
        'Shared pools you own pass to another admin, with their balance unchanged, and your name is removed from their names.',
        'Settlements in that household can change: entries you paid are no longer counted and equal splits in the current cycle are divided again, so other members’ debts can change. Account balances and budget spending do not change.',
        'A record with no name, email or user ID, showing that a deletion was completed.',
      ],
    },
    notEdited: {
      title: 'What is not edited',
      items: [
        'Free text other members typed, such as a note mentioning you by name, stays as they wrote it. We also remove your email address from household records.',
        'Household names stay as they are, even if one includes your name, except that your email address is replaced there too.',
      ],
    },
    outOfReach: {
      title: 'What we cannot remove',
      intro: 'Deletion does not reach these, and we cannot remove individual records from them:',
      items: [
        'Copies of emails in the developer’s mailbox, such as support and deletion requests.',
        'Railway server logs.',
        'Supabase database backups.',
        'Supabase authentication audit log entries.',
      ],
    },
    admins: {
      title: 'If you manage a household',
      items: [
        'If you are the primary or only admin of a household with other members, you must choose before scheduling: assign another member as primary admin, or delete the household.',
        'Assigning happens immediately. You stay a co-admin until final deletion, and cancelling does not give the primary admin title back.',
        'Deleting a household removes everything in it when the date comes, including other members’ accounts and entries in that household and the wife’s ledger. Members keep their logins but no longer belong to it.',
        'Until then the household stays active, its members see a banner so they can export what they want to keep, and it takes no new members. Cancelling your deletion clears this.',
        'A co-admin or a regular member simply leaves, and the household continues.',
      ],
    },
    contact: 'Questions? Email us at',
    rights: 'All rights reserved.',
    signIn: {
      title: 'Delete your account yourself',
      intro: 'Sign in to schedule or cancel the deletion. Signing in alone starts nothing and cancels nothing.',
      email: 'Email address',
      password: 'Password',
      submit: 'Sign in',
      submitting: 'Checking...',
      error: 'Could not sign in. Check your email and password and try again.',
      forgot: 'Forgot your password? Reset it in the app, or send the request form below.',
    },
    request: {
      title: 'Can’t sign in? Send a deletion request',
      intro:
        'This form does not delete anything. It stores your request and emails it to the developer, who handles it by hand and may reply to this address, so use the email on your account. Sending it does not look up any account or schedule a deletion, and no automatic email is sent to you. We keep the stored request for 90 days, then remove it.',
      email: 'The email on your account',
      message: 'Message (optional)',
      submit: 'Send request',
      submitting: 'Sending...',
      receivedTitle: 'We received your request',
      sentBody: 'It has been stored and sent to the developer, who handles it by hand.',
      capturedBody: 'It has been stored, but the email that tells the developer about it could not be sent right now, so it may take longer to be seen.',
      notDeleted: 'Your account has not been deleted or scheduled for deletion by this request.',
      reference: 'Reference:',
      errorInvalid: 'Please enter a valid email address.',
      errorRateLimited: 'We received many requests. Please try again shortly.',
      errorUnavailable: 'We did not receive your request. Please try later or email us at the address below.',
      errorNetwork: 'Could not reach the server, so we did not receive your request. Check your connection and try again.',
    },
    account: {
      signedInAs: 'Signed in as',
      signOut: 'Sign out',
      loading: 'Loading...',
      loadError: 'We could not load your account’s status. Try again, or use the request form below.',
      retry: 'Try again',
      flowTitle: 'Schedule your account’s deletion',
      flowIntro: 'Your account will be deleted 30 days after you confirm. Read this page first, and export from the app anything you want to keep.',
      settlementWarning: 'Settlements and other members’ debts can change in the households that continue without you. Account balances and budget spending do not change.',
      householdsTitle: 'Your households',
      noHouseholds: 'You are not a member of any household.',
      positionSole: '{name}: you are the only member, so it is deleted with everything in it.',
      positionCoAdmin: '{name}: you are a co-admin, so you leave and the household continues.',
      positionMember: '{name}: you leave and the household continues.',
      choiceTitle: '{name}: you are its primary admin. Choose what happens to it:',
      choiceTransfer: 'Assign another member as primary admin (happens immediately)',
      choiceDelete: 'Delete this household with everything in it',
      choiceDeleteWarning: 'Everything in it is removed when the date comes, including other members’ accounts and entries in that household and the wife’s ledger. Members keep their logins.',
      successorLabel: 'New primary admin',
      successorPlaceholder: 'Choose a member',
      successorPending: '(scheduled for deletion)',
      successorUnnamed: 'Unnamed member',
      noSuccessor: 'No member can take over, so the choice available is to delete the household.',
      password: 'Password',
      passwordHint: 'We ask again to make sure it is you.',
      typedWord: 'Type “{word}” to confirm',
      submit: 'Schedule deletion in 30 days',
      submitting: 'Scheduling...',
      pendingTitle: 'Your account is scheduled for deletion',
      pendingDate: 'Deletion date:',
      pendingUsable: 'Until then your account keeps working.',
      pendingSignIn: 'Signing in alone does not cancel this. To keep your account, cancel the deletion.',
      pendingHouseholds: 'Households also being deleted:',
      cancel: 'Cancel the deletion',
      cancelling: 'Cancelling...',
      cancelled: 'The deletion is cancelled and your account stays. A primary admin assignment already made stays as it is.',
      inProgressTitle: 'Your account’s deletion has started',
      inProgressBody: 'Some of your data has already been deleted, so it can no longer be cancelled. If you have a question, email us at the address below.',
      startingTitle: 'Your account’s deletion is starting',
      startingBody: 'Nothing has been deleted yet, so you can still cancel it.',
      stoppedTitle: 'Your account’s deletion stopped before deleting anything',
      stoppedBody: 'One of its steps failed. Nothing has been deleted yet, so you can still cancel it; otherwise we will look into it.',
      stoppedPartwayTitle: 'Your account’s deletion stopped partway',
      stoppedPartwayBody: 'Some of your data has already been deleted, so it can no longer be cancelled. We will look into it. If you have a question, email us at the address below.',
      errors: {
        password: 'Could not confirm your password. Check it and try again.',
        reauthenticationRequired: 'To confirm this request, enter your password again.',
        confirmationMismatch: 'The confirmation word does not match.',
        choiceMissing: 'Choose what happens to each household you manage.',
        choiceInvalid: 'Your households have changed. Reload the page and choose again.',
        successorInvalid: 'Choose another member of this household.',
        successorPending: 'This member is scheduled for deletion. Choose another member.',
        inProgress: 'Some of your data has already been deleted, so the deletion cannot be cancelled.',
        generic: 'That did not go through, and nothing changed on your account. Please try again.',
      },
    },
  },
  ur: {
    languageName: 'اردو',
    dir: 'rtl',
    dateLocale: 'ur-PK-u-ca-gregory-nu-latn',
    confirmationWord: 'حذف کریں',
    pageTitle: 'اکاؤنٹ حذف کریں | قوام المال Qawam Money',
    skipToContent: 'مرکزی مواد پر جائیں',
    home: 'ہوم پیج',
    languageNav: 'زبان',
    landingNotice: {
      body: 'یہ صفحہ اردو میں دستیاب نہیں، اس لیے انگریزی میں دکھایا گیا ہے۔',
      link: 'اکاؤنٹ حذف کرنے اور اپنے ڈیٹا کے بارے میں اردو میں پڑھیں',
    },
    appName: 'قوام المال · Qawam Money',
    title: 'قوام المال میں اپنا اکاؤنٹ حذف کریں',
    intro:
      'یہ صفحہ بتاتا ہے کہ قوام المال (Qawam Money) ایپ میں اپنا اکاؤنٹ کیسے حذف کریں، کیا ہٹایا جاتا ہے، کیا باقی رہتا ہے اور ارادہ کیسے بدلیں۔ حذف فوراً نہیں ہوتا: آپ کا اکاؤنٹ تصدیق کے 30 دن بعد حذف ہوتا ہے۔',
    how: {
      title: 'اپنا اکاؤنٹ کیسے حذف کریں',
      items: [
        'ایپ سے: سیٹنگز کھولیں اور اکاؤنٹ حذف کرنے کا انتخاب کریں۔',
        'اس صفحے سے: نیچے سائن ان کریں، پاس ورڈ کی تصدیق کریں اور تصدیقی لفظ لکھیں۔',
        'اگر سائن ان نہیں کر سکتے: نیچے درخواست فارم بھیجیں۔ اسے ایک شخص دیکھتا ہے، اور فارم خود کچھ حذف نہیں کرتا۔',
      ],
    },
    window: {
      title: '30 دن کی مہلت اور منسوخی کا طریقہ',
      items: [
        'تصدیق کے بعد آپ کا اکاؤنٹ 30 دن بعد حذف ہونے کے لیے طے ہو جاتا ہے، اور تاریخ آپ کو ایپ اور اس صفحے پر نظر آتی ہے۔',
        'ان 30 دنوں میں آپ کا اکاؤنٹ چلتا رہتا ہے، ایکسپورٹ سمیت، لیکن آپ کسی گھرانے میں شامل نہیں ہو سکتے، نیا گھرانہ نہیں بنا سکتے اور منتظم نہیں بن سکتے۔',
        'صرف سائن ان کرنے سے حذف منسوخ نہیں ہوتا۔ منسوخ کرنے کے لیے ایپ کی سیٹنگز میں منسوخی کا انتخاب کریں، یا اس صفحے پر سائن ان کر کے منسوخ کریں۔',
        'تاریخ آنے پر حذف شروع ہو جاتا ہے اور پھر منسوخ نہیں ہو سکتا۔ اگر کوئی مرحلہ دوبارہ چلانا پڑے تو یہ تاریخ کے بعد مکمل ہو سکتا ہے۔',
        'اگر مہلت کے دوران آپ کسی ایسے گھرانے کے بنیادی یا واحد منتظم بن جائیں جس میں دوسرے ارکان ہوں تو اس گھرانے کو حذف سے 7 دن پہلے اطلاع دی جاتی ہے، اور آپ کا اپنا حذف اس مدت کے اختتام تک مؤخر ہو جاتا ہے۔',
        'ہم آپ کو ای میل کر سکتے ہیں: تاریخ سے تقریباً 7 دن اور 1 دن پہلے اور حذف مکمل ہونے پر، اور گھرانہ حذف ہونے پر اس کے ارکان کو بھی۔ یہ ہماری ای میل سروس کی دستیابی پر منحصر ہے، اس لیے اس پر انحصار نہ کریں: اصل وہی تاریخ ہے جو ایپ اور اس صفحے پر نظر آتی ہے۔',
      ],
    },
    deleted: {
      title: 'کیا حذف ہوتا ہے',
      items: [
        'آپ کا لاگ اِن، ای میل پتہ اور ظاہری نام۔',
        'آپ کے ذاتی اکاؤنٹس، ان میں درج آمدنی اور ان کے درمیان منتقلیاں۔',
        'آپ کے اندراجات، آمدنی اور منتقلیوں پر آپ کے لکھے ہوئے نوٹس۔',
        'آپ کے اندراجات سے منسلک رسیدوں کی تصاویر۔',
        'ہر گھرانے میں آپ کی رکنیت، اور آپ سے منسلک کوئی زیرِ کفالت اندراج۔',
        'اگر آپ کسی خاندانی گھرانے میں بیوی ہیں: آپ کے ذاتی اخراجات کے اندراجات، آپ کا مقررہ جیب خرچ اور آپ کے واجبات کا کھاتہ۔ اگر آپ کے شوہر پر ابھی آپ کی کوئی رقم واجب ہے تو حذف طے کرتے وقت ایپ انہیں یہ رقم دکھاتی ہے (اور ہم انہیں ای میل بھی کر سکتے ہیں)، یا شوہر مقرر نہ ہو تو گھرانے کے منتظمین کو دکھاتی ہے؛ حذف کے بعد گھرانے میں صرف واجب الادا رقم بغیر نام کے رہتی ہے، جب تک وہ یا کوئی منتظم اسے ادا شدہ یا آپ کی طرف سے معاف شدہ درج نہ کر دے۔',
        'اس ای میل پتے سے رابطہ اور سپورٹ فارمز کے ذریعے ہمیں بھیجے گئے پیغامات۔',
        'کوئی بھی گھرانہ جس کے آپ واحد رکن ہیں، اس کی ہر چیز سمیت۔',
      ],
    },
    kept: {
      title: 'کیا آپ کے نام کے بغیر باقی رہتا ہے',
      items: [
        'موجود گھرانوں میں آپ کے اندراجات رقم، تاریخ، زمرے، دکان اور تفصیلی سطروں سمیت باقی رہتے ہیں، اور «حذف شدہ رکن» کے نام سے دکھائی دیتے ہیں۔ دکان اور سطروں کے ناموں سے آپ کا نام اور ای میل پتہ ہٹا دیا جاتا ہے۔',
        'مشترکہ پول میں آپ کی درج کردہ آمدنی اور مشترکہ پول سے آنے جانے والی منتقلیاں آپ کے نام یا نوٹس کے بغیر باقی رہتی ہیں، اس لیے پول کا بیلنس نہیں بدلتا۔',
        'آپ کی ملکیت والے مشترکہ پول کسی دوسرے منتظم کو منتقل ہو جاتے ہیں، ان کا بیلنس نہیں بدلتا، اور ان کے ناموں سے آپ کا نام ہٹا دیا جاتا ہے۔',
        'اس گھرانے میں تصفیے بدل سکتے ہیں: آپ کے ادا کردہ اندراجات شمار نہیں ہوتے اور موجودہ سائیکل کی برابر تقسیم دوبارہ ہوتی ہے، اس لیے دوسرے ارکان کے قرض بدل سکتے ہیں۔ اکاؤنٹس کے بیلنس اور بجٹ کے اخراجات نہیں بدلتے۔',
        'ایک ریکارڈ جس میں نہ نام ہے، نہ ای میل، نہ یوزر آئی ڈی، اور جو صرف یہ بتاتا ہے کہ ایک حذف مکمل ہوا۔',
      ],
    },
    notEdited: {
      title: 'کس چیز میں ترمیم نہیں ہوتی',
      items: [
        'دوسرے ارکان کی لکھی ہوئی عبارت، جیسے آپ کا نام لینے والا نوٹ، ویسی ہی رہتی ہے۔ ہم گھرانے کے ریکارڈ سے آپ کا ای میل پتہ بھی ہٹا دیتے ہیں۔',
        'گھرانوں کے نام جوں کے توں رہتے ہیں، چاہے کسی میں آپ کا نام شامل ہو، البتہ ان میں بھی آپ کا ای میل پتہ بدل دیا جاتا ہے۔',
      ],
    },
    outOfReach: {
      title: 'جو ہم نہیں ہٹا سکتے',
      intro: 'حذف ان تک نہیں پہنچتا، اور ہم ان میں سے الگ الگ ریکارڈ نہیں ہٹا سکتے:',
      items: [
        'ڈویلپر کے میل باکس میں ای میلز کی نقول، جیسے سپورٹ اور حذف کی درخواستیں۔',
        'Railway کے سرور لاگز۔',
        'Supabase ڈیٹا بیس کے بیک اپس۔',
        'Supabase کے تصدیقی آڈٹ لاگ کے اندراجات۔',
      ],
    },
    admins: {
      title: 'اگر آپ کسی گھرانے کا انتظام کرتے ہیں',
      items: [
        'اگر آپ کسی ایسے گھرانے کے بنیادی یا واحد منتظم ہیں جس میں دوسرے ارکان ہیں تو طے کرنے سے پہلے انتخاب کرنا ہوگا: کسی دوسرے رکن کو بنیادی منتظم بنائیں یا گھرانہ حذف کریں۔',
        'منتظم بنانا فوراً ہو جاتا ہے۔ آپ آخری حذف تک شریک منتظم رہتے ہیں، اور منسوخی سے بنیادی منتظم کا منصب واپس نہیں ملتا۔',
        'گھرانہ حذف کرنے سے تاریخ آنے پر اس کی ہر چیز ہٹ جاتی ہے، جس میں اس گھرانے میں دوسرے ارکان کے اکاؤنٹس اور اندراجات اور بیوی کا کھاتہ بھی شامل ہے۔ ارکان کے لاگ اِن برقرار رہتے ہیں، لیکن وہ اس گھرانے کے رکن نہیں رہتے۔',
        'تب تک گھرانہ فعال رہتا ہے، اس کے ارکان کو ایک بینر نظر آتا ہے تاکہ وہ جو چاہیں ایکسپورٹ کر لیں، اور نئے ارکان شامل نہیں ہو سکتے۔ آپ کے حذف کی منسوخی سے یہ ختم ہو جاتا ہے۔',
        'شریک منتظم یا عام رکن صرف چھوڑ دیتا ہے، اور گھرانہ جاری رہتا ہے۔',
      ],
    },
    contact: 'کوئی سوال ہے؟ ہمیں ای میل کریں:',
    rights: 'جملہ حقوق محفوظ ہیں۔',
    signIn: {
      title: 'اپنا اکاؤنٹ خود حذف کریں',
      intro: 'حذف طے یا منسوخ کرنے کے لیے سائن ان کریں۔ صرف سائن ان کرنے سے نہ کچھ شروع ہوتا ہے نہ کچھ منسوخ ہوتا ہے۔',
      email: 'ای میل پتہ',
      password: 'پاس ورڈ',
      submit: 'سائن ان کریں',
      submitting: 'جانچ ہو رہی ہے...',
      error: 'سائن ان نہیں ہو سکا۔ ای میل اور پاس ورڈ جانچ کر دوبارہ کوشش کریں۔',
      forgot: 'پاس ورڈ بھول گئے؟ ایپ سے ری سیٹ کریں، یا نیچے درخواست فارم بھیجیں۔',
    },
    request: {
      title: 'سائن ان نہیں کر سکتے؟ حذف کی درخواست بھیجیں',
      intro:
        'یہ فارم کچھ حذف نہیں کرتا۔ یہ آپ کی درخواست محفوظ کر کے ڈویلپر کو ای میل کرتا ہے، جو اسے خود دیکھتا ہے اور اس پتے پر جواب دے سکتا ہے، اس لیے اپنے اکاؤنٹ کا ای میل لکھیں۔ اسے بھیجنے سے نہ کوئی اکاؤنٹ تلاش ہوتا ہے نہ حذف طے ہوتا ہے، اور آپ کو خودکار ای میل نہیں آتی۔ محفوظ درخواست ہم 90 دن تک رکھتے ہیں، پھر ہٹا دیتے ہیں۔',
      email: 'آپ کے اکاؤنٹ کا ای میل',
      message: 'پیغام (اختیاری)',
      submit: 'درخواست بھیجیں',
      submitting: 'بھیجی جا رہی ہے...',
      receivedTitle: 'آپ کی درخواست ہمیں مل گئی',
      sentBody: 'یہ محفوظ ہو گئی ہے اور ڈویلپر کو بھیج دی گئی ہے، جو اسے خود دیکھتا ہے۔',
      capturedBody: 'یہ محفوظ ہو گئی ہے، لیکن ڈویلپر کو مطلع کرنے والی ای میل ابھی نہیں بھیجی جا سکی، اس لیے اسے دیکھنے میں دیر ہو سکتی ہے۔',
      notDeleted: 'آپ کا اکاؤنٹ حذف نہیں ہوا اور اس درخواست سے اس کا حذف طے نہیں ہوا۔',
      reference: 'حوالہ نمبر:',
      errorInvalid: 'براہ کرم درست ای میل پتہ درج کریں۔',
      errorRateLimited: 'ہمیں بہت سی درخواستیں ملی ہیں۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔',
      errorUnavailable: 'آپ کی درخواست ہمیں نہیں ملی۔ بعد میں کوشش کریں یا نیچے دیے گئے پتے پر ای میل کریں۔',
      errorNetwork: 'سرور سے رابطہ نہیں ہو سکا، اس لیے آپ کی درخواست ہمیں نہیں ملی۔ اپنا کنکشن جانچ کر دوبارہ کوشش کریں۔',
    },
    account: {
      signedInAs: 'سائن ان بطور',
      signOut: 'سائن آؤٹ',
      loading: 'لوڈ ہو رہا ہے...',
      loadError: 'آپ کے اکاؤنٹ کی حالت لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں یا نیچے درخواست فارم استعمال کریں۔',
      retry: 'دوبارہ کوشش کریں',
      flowTitle: 'اپنے اکاؤنٹ کا حذف طے کریں',
      flowIntro: 'آپ کا اکاؤنٹ تصدیق کے 30 دن بعد حذف ہوگا۔ پہلے یہ صفحہ پڑھیں، اور جو رکھنا چاہتے ہیں اسے ایپ سے ایکسپورٹ کر لیں۔',
      settlementWarning: 'جو گھرانے آپ کے بعد جاری رہیں گے ان میں تصفیے اور دوسرے ارکان کے قرض بدل سکتے ہیں۔ اکاؤنٹس کے بیلنس اور بجٹ کے اخراجات نہیں بدلتے۔',
      householdsTitle: 'آپ کے گھرانے',
      noHouseholds: 'آپ کسی گھرانے کے رکن نہیں ہیں۔',
      positionSole: '{name}: آپ واحد رکن ہیں، اس لیے یہ اپنی ہر چیز سمیت حذف ہو جائے گا۔',
      positionCoAdmin: '{name}: آپ شریک منتظم ہیں، اس لیے آپ چھوڑ دیں گے اور گھرانہ جاری رہے گا۔',
      positionMember: '{name}: آپ چھوڑ دیں گے اور گھرانہ جاری رہے گا۔',
      choiceTitle: '{name}: آپ اس کے بنیادی منتظم ہیں۔ انتخاب کریں کہ اس کا کیا ہو:',
      choiceTransfer: 'کسی دوسرے رکن کو بنیادی منتظم بنائیں (فوراً ہو جاتا ہے)',
      choiceDelete: 'یہ گھرانہ اس کی ہر چیز سمیت حذف کریں',
      choiceDeleteWarning: 'تاریخ آنے پر اس کی ہر چیز ہٹ جائے گی، جس میں اس گھرانے میں دوسرے ارکان کے اکاؤنٹس اور اندراجات اور بیوی کا کھاتہ بھی شامل ہے۔ ارکان کے لاگ اِن برقرار رہیں گے۔',
      successorLabel: 'نیا بنیادی منتظم',
      successorPlaceholder: 'رکن منتخب کریں',
      successorPending: '(حذف کے لیے طے شدہ)',
      successorUnnamed: 'بے نام رکن',
      noSuccessor: 'کوئی رکن انتظام نہیں سنبھال سکتا، اس لیے دستیاب انتخاب گھرانہ حذف کرنا ہے۔',
      password: 'پاس ورڈ',
      passwordHint: 'ہم دوبارہ پوچھتے ہیں تاکہ یقین ہو جائے کہ یہ آپ ہی ہیں۔',
      typedWord: 'تصدیق کے لیے «{word}» لکھیں',
      submit: '30 دن بعد حذف طے کریں',
      submitting: 'طے ہو رہا ہے...',
      pendingTitle: 'آپ کا اکاؤنٹ حذف کے لیے طے ہے',
      pendingDate: 'حذف کی تاریخ:',
      pendingUsable: 'تب تک آپ کا اکاؤنٹ چلتا رہے گا۔',
      pendingSignIn: 'صرف سائن ان کرنے سے یہ منسوخ نہیں ہوتا۔ اکاؤنٹ رکھنا ہو تو حذف منسوخ کریں۔',
      pendingHouseholds: 'یہ گھرانے بھی حذف ہوں گے:',
      cancel: 'حذف منسوخ کریں',
      cancelling: 'منسوخ ہو رہا ہے...',
      cancelled: 'حذف منسوخ ہو گیا اور آپ کا اکاؤنٹ برقرار ہے۔ بنیادی منتظم کی جو تقرری ہو چکی ہے وہ ویسی ہی رہے گی۔',
      inProgressTitle: 'آپ کے اکاؤنٹ کا حذف شروع ہو چکا ہے',
      inProgressBody: 'آپ کا کچھ ڈیٹا حذف ہو چکا ہے، اس لیے اب یہ منسوخ نہیں ہو سکتا۔ کوئی سوال ہو تو نیچے دیے گئے پتے پر ای میل کریں۔',
      startingTitle: 'آپ کے اکاؤنٹ کا حذف شروع ہو رہا ہے',
      startingBody: 'ابھی کچھ حذف نہیں ہوا، اس لیے آپ اب بھی حذف منسوخ کر سکتے ہیں۔',
      stoppedTitle: 'کچھ حذف ہونے سے پہلے ہی آپ کے اکاؤنٹ کا حذف رک گیا',
      stoppedBody: 'حذف کا ایک مرحلہ ناکام ہو گیا۔ ابھی کچھ حذف نہیں ہوا، اس لیے آپ اب بھی حذف منسوخ کر سکتے ہیں، ورنہ ہم اسے دیکھیں گے۔',
      stoppedPartwayTitle: 'آپ کے اکاؤنٹ کا حذف ادھورا رک گیا',
      stoppedPartwayBody: 'آپ کا کچھ ڈیٹا حذف ہو چکا ہے، اس لیے اب یہ منسوخ نہیں ہو سکتا۔ ہم اسے دیکھیں گے۔ کوئی سوال ہو تو نیچے دیے گئے پتے پر ای میل کریں۔',
      errors: {
        password: 'پاس ورڈ کی تصدیق نہیں ہو سکی۔ جانچ کر دوبارہ کوشش کریں۔',
        reauthenticationRequired: 'اس درخواست کی تصدیق کے لیے اپنا پاس ورڈ دوبارہ درج کریں۔',
        confirmationMismatch: 'تصدیقی لفظ مطابقت نہیں رکھتا۔',
        choiceMissing: 'ہر اس گھرانے کے لیے انتخاب کریں جس کا آپ انتظام کرتے ہیں۔',
        choiceInvalid: 'آپ کے گھرانے بدل گئے ہیں۔ صفحہ دوبارہ لوڈ کر کے پھر انتخاب کریں۔',
        successorInvalid: 'اس گھرانے کا کوئی دوسرا رکن منتخب کریں۔',
        successorPending: 'یہ رکن حذف کے لیے طے ہے۔ کوئی دوسرا رکن منتخب کریں۔',
        inProgress: 'آپ کا کچھ ڈیٹا حذف ہو چکا ہے، اس لیے حذف منسوخ نہیں ہو سکتا۔',
        generic: 'یہ مکمل نہیں ہو سکا، اور آپ کے اکاؤنٹ میں کچھ نہیں بدلا۔ دوبارہ کوشش کریں۔',
      },
    },
  },
};
