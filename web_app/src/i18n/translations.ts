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
      name: 'Budget Tracker',
      tagline: 'ميزانية البيت على دورة الراتب',
    },
    nav: {
      features: 'المزايا',
      nafaqah: 'النفقة',
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
      nafaqahLink: 'شوف كيف تنحسب النفقة',
    },
    nafaqah: {
      badge: 'وضع الأسرة',
      title: 'كيف تنحسب النفقة؟',
      intro:
        'في وضع الأسرة يمشي التطبيق على أن النفقة على الزوج: السكن والأكل واحتياجات البيت مسؤوليته. ما يقسم التطبيق أي مصروف بين الزوجين بالنسبة، وكل مصروف ينحسب حسب مين دفع ولمين:',
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
      pageTitle: 'Budget Tracker | اعرف كم باقي لك لين الراتب',
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
      name: 'Budget Tracker',
      tagline: 'Household budget by salary cycle',
    },
    nav: {
      features: 'Features',
      nafaqah: 'Nafaqah',
      privacy: 'Privacy',
      faq: 'FAQ',
      cta: 'Early access',
    },
    hero: {
      badge: 'Mobile app · Early access open',
      title: 'Know what’s left until payday',
      subtitle:
        'Your household budget follows your salary cycle, from one payday to the next. Log expenses by voice or a receipt photo, and keep Nafaqah between spouses or a shared flat’s split clear.',
      ctaPrimary: 'Join early access',
      ctaSecondary: 'How Nafaqah works',
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
          title: 'Nafaqah between spouses, made clear',
          desc: 'Nafaqah is the husband’s duty. What the wife pays for the home from her own money is recorded as his debt to her, and her personal purchases come out of her personal allowance. Nothing is split between spouses by percentage.',
        },
        {
          icon: 'users',
          title: 'A fair split for shared flats',
          desc: 'In a shared flat everyone logs what they paid. The app splits shared costs equally and simplifies the debts: who pays whom and how much, in the fewest transfers.',
        },
      ],
      nafaqahLink: 'See how Nafaqah works',
    },
    nafaqah: {
      badge: 'Family mode',
      title: 'How Nafaqah works',
      intro:
        'In family mode the app follows the rule that Nafaqah is the husband’s responsibility: housing, food and the home’s needs. It never splits an expense between spouses by percentage. Each expense is handled by who paid and for whom:',
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
          a: 'No. In family mode Nafaqah is on the husband, and what the wife pays for the home is recorded as his debt to her. Splitting costs is only for shared flats.',
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
      wifeAllowanceSubtitle: 'Protected periodic allowance adhering to Nafaqah rules',
      subAllocationsTitle: 'Sub-allocations for Dependents & Categories',
      noData: 'No records found yet.',
      activePlans: 'active plan(s)',
      monthlyDue: 'Monthly due',
    },
    a11y: {
      pageTitle: 'Budget Tracker | Know what’s left until payday',
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
