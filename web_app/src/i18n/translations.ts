export type Language = 'ar' | 'en';

export interface TranslationDictionary {
  brand: {
    name: string;
    tagline: string;
    subtagline: string;
    sovereignBadge: string;
  };
  nav: {
    simulator: string;
    simulatorSub: string;
    telemetry: string;
    telemetrySub: string;
    pillars: string;
    pillarsSub: string;
    security: string;
    securitySub: string;
    faq: string;
    faqSub: string;
    vipCta: string;
  };
  hero: {
    badge: string;
    title: string;
    subtitle: string;
    ctaPrimary: string;
    ctaSecondary: string;
    spendGaugeTitle: string;
    spendGaugeVal: string;
    spendGaugeUnit: string;
    spendGaugeStatus: string;
    spendGaugeProgress: string;
    roommateTitle: string;
    roommateVal: string;
    roommateStatus: string;
    roommateSub: string;
    roommateSettle: string;
    ingestionTitle: string;
    ingestionVal: string;
    ingestionUnit: string;
    ingestionSub: string;
    ingestionAccuracy: string;
    guarantee1: string;
    guarantee2: string;
    guarantee3: string;
  };
  simulator: {
    badge: string;
    title: string;
    subtitle: string;
    tabSalary: string;
    tabAi: string;
    tabZatca: string;
    tabSplit: string;
    // Tab 1
    salaryPill: string;
    salaryTitle: string;
    salaryDesc: string;
    disbursementLabel: string;
    disbursementDay: string;
    day1Label: string;
    day15Label: string;
    day27Label: string;
    day31Label: string;
    reserveTitle: string;
    reserveVal: string;
    reserveSub: string;
    burnRateTitle: string;
    burnRateSub: string;
    burnRateOptimal: string;
    countdownTitle: string;
    countdownSub: string;
    countdownDays: string;
    poolLabel: string;
    poolVal: string;
    poolDesc: string;
    healthTag: string;
    // Tab 2
    aiPill: string;
    aiTitle: string;
    aiDesc: string;
    aiPromptLabel: string;
    aiPresets: string[];
    aiStatus: string;
    aiPrecision: string;
    aiCatLabel: string;
    aiTotalLabel: string;
    aiLedgerLabel: string;
    aiPayer: string;
    aiDebtor1: string;
    aiDebtor2: string;
    aiImpactLabel: string;
    aiImpactVal: string;
    // Tab 3
    zatcaPill: string;
    zatcaTitle: string;
    zatcaDesc: string;
    zatcaBtn: string;
    zatcaBadge: string;
    zatcaNet: string;
    zatcaTax: string;
    zatcaGrand: string;
    zatcaVerified: string;
    // Tab 4
    splitPill: string;
    splitTitle: string;
    splitDesc: string;
    splitModeFamily: string;
    splitModeRoommates: string;
    splitLedgerTitleFamily: string;
    splitLedgerTitleRoommates: string;
    splitLiveBadge: string;
    splitResolutionTitle: string;
    splitResolutionDesc: string;
    splitSettleBtn: string;
  };
  metrics: {
    metric1Val: string;
    metric1Title: string;
    metric1Desc: string;
    metric2Val: string;
    metric2Title: string;
    metric2Desc: string;
    metric3Val: string;
    metric3Title: string;
    metric3Desc: string;
    metric4Val: string;
    metric4Title: string;
    metric4Desc: string;
  };
  pillars: {
    badge: string;
    title: string;
    subtitle: string;
    items: Array<{
      title: string;
      desc: string;
      icon: string;
    }>;
  };
  security: {
    badge: string;
    title: string;
    subtitle: string;
    cards: Array<{
      title: string;
      desc: string;
    }>;
  };
  faq: {
    badge: string;
    title: string;
    items: Array<{
      q: string;
      sub: string;
      a: string;
    }>;
  };
  earlyAccess: {
    badge: string;
    title: string;
    headline: string;
    desc: string;
    placeholder: string;
    button: string;
    partnerInfo: string;
    successMsg: string;
  };
  footer: {
    rights: string;
    links: string[];
    status: string;
  };
}

export const translations: Record<Language, TranslationDictionary> = {
  ar: {
    brand: {
      name: 'BUDGET Tracker',
      tagline: 'ميزانية وأكثر',
      subtagline: 'الحوكمة المالية الذكية وإدارة المصاريف المشتركة',
      sovereignBadge: 'نظام سيادي مستقل',
    },
    nav: {
      simulator: 'المحاكي التفاعلي',
      simulatorSub: 'تجربة حية',
      telemetry: 'المؤشرات الحية',
      telemetrySub: 'بيانات فورية',
      pillars: 'الركائز الـ 12',
      pillarsSub: 'الهيكل التقني',
      security: 'الخصوصية السيادية',
      securitySub: 'صفر ربط بنكي',
      faq: 'الأسئلة الشائعة',
      faqSub: 'الدليل والدعم',
      vipCta: 'حجز وصول VIP',
    },
    hero: {
      badge: 'الحوكمة المالية السيادية • للأسر الحديثة وشركاء السكن',
      title: 'صفاء وانسيابية مالية تامة لأسرتك وشركاء سكنك.',
      subtitle:
        'متابعة حية للتدفقات النقدية مع خصوصية مطلقة لا تقبل المساومة. اضبط دورة راتبك على أي يوم (من 1 إلى 31)، دوّن مصاريفك صوتياً بالذكاء الاصطناعي، افحص فواتير ZATCA الضريبية المعتمدة بلحظة، ووزع التزامات الشقة المشتركة بعدالة دون أي ربط بنكي أو قراءة للرسائل النصية.',
      ctaPrimary: 'ابدأ المحاكي التفاعلي',
      ctaSecondary: 'استكشف الركائز الـ 12',
      spendGaugeTitle: 'معدل الصرف اليومي الآمن',
      spendGaugeVal: '145.00 ر.س',
      spendGaugeUnit: '/ يومياً',
      spendGaugeStatus: 'وتيرة إنفاق مثالية',
      spendGaugeProgress: 'اليوم 12 من 30',
      roommateTitle: 'معاينة رصيد السكن المشترك',
      roommateVal: '+420.00 ر.س',
      roommateStatus: 'دائن مستحق',
      roommateSub: 'تسوية حساب ماجد وسلمان',
      roommateSettle: 'تسوية بضغطة واحدة',
      ingestionTitle: 'الاستيعاب الذكي الفوري',
      ingestionVal: '0.28 ث',
      ingestionUnit: 'زمن المعالجة',
      ingestionSub: 'تحليل الصوت وفك شفرات ZATCA',
      ingestionAccuracy: 'دقة 99.8%',
      guarantee1: 'خصوصية 100% بدون أي ربط بنكي',
      guarantee2: 'متوافق مع فواتير ZATCA الضريبية TLV',
      guarantee3: 'قريباً على: iOS • Android • AppGallery',
    },
    simulator: {
      badge: 'قمرة القيادة التفاعلية',
      title: 'محاكي الميزانية والحوكمة المالية الحي',
      subtitle:
        'جرّب الركائز الأساسية لنظام BUDGET Tracker مباشرة. اختبر مرونة وتيرة الصرف اليومية، ذكاء فهم الجمل العربية الدارجة، وميزان تسوية السكن العادل.',
      tabSalary: '1. مرونة دورة الراتب (1–31)',
      tabAi: '2. محرك الذكاء الاصطناعي',
      tabZatca: '3. ماسح فواتير ZATCA',
      tabSplit: '4. دفتر المصاريف العادل',
      // Tab 1
      salaryPill: 'معمارية الدورة المتكيفة',
      salaryTitle: 'تحرر تماماً من قيود الشهر الميلادي الثابت',
      salaryDesc:
        'سواء كنت تستلم راتبك يوم 27 (القطاع الحكومي السعودي)، أو في الأول من الشهر، أو أي موعد دوري مخصص، يقوم النظام بإعادة حساب معدل صرفك الآمن واحتياطياتك تلقائياً وبأجزاء من الثانية.',
      disbursementLabel: 'يوم استحقاق الراتب:',
      disbursementDay: 'يوم {val} من كل شهر',
      day1Label: 'يوم 1 (بداية الشهر)',
      day15Label: 'يوم 15 (منتصف الشهر)',
      day27Label: 'يوم 27 (الراتب الحكومي)',
      day31Label: 'يوم 31',
      reserveTitle: 'صندوق الطوارئ التلقائي (حجز 15%)',
      reserveVal: '2,250.00 ر.س',
      reserveSub: 'محمي مسبقاً من الصرف',
      burnRateTitle: 'معدل الصرف اليومي الآمن',
      burnRateSub: 'المخصص المتاح يومياً',
      burnRateOptimal: 'وتيرة إنفاق ممتازة ومتوازنة حتى تاريخ الراتب القادم',
      countdownTitle: 'العد التنازلي للدورة',
      countdownSub: 'الراتب القادم',
      countdownDays: '{val} يوماً متبقية',
      poolLabel: 'مجموع الدخل الشهري المستلم:',
      poolVal: '15,000.00 ر.س',
      poolDesc: '50% ضروريات ثابتة • 35% مصاريف مرنة • 15% احتياطي مدخر',
      healthTag: 'الحالة: استقرار مالي ممتاز',
      // Tab 2
      aiPill: 'معالجة لغوية بدون ملء استمارات',
      aiTitle: 'سجل أصعب الفواتير المشتركة بجملة عامية واحدة',
      aiDesc:
        'وداعاً للقوائم المعقدة والحقول الطويلة. اكتب أو تحدث بلهجتك الدارجة كما تتحدث مع صديقك، وسيتولى النموذج الذكي تصنيف المتجر، المبلغ، وبنود التقاسم بلحظة.',
      aiPromptLabel: 'جرّب كتابة جملة تفاعلية:',
      aiPresets: [
        'فاتورة كهرباء الشقة 420 ريال مقسمة على 4 غرف',
        'عشاء مشاوي مع الزملاء 1800 ريال على 6 أشخاص',
        'اشتراك إنترنت فايبر 280 ريال دفعته كامل وعمر عليه النصف',
      ],
      aiStatus: 'محرك الاستنتاج الذكي الفوري • 0.28 ثانية',
      aiPrecision: 'دقة استخراج 99.8%',
      aiCatLabel: 'التصنيف المالي المكتشف:',
      aiTotalLabel: 'إجمالي المبلغ المستخرج:',
      aiLedgerLabel: 'توزيع الحصص التلقائي:',
      aiPayer: 'أنت (الدافع)',
      aiDebtor1: 'ماجد (مدين)',
      aiDebtor2: 'سلمان (مدين)',
      aiImpactLabel: 'أثر العملية على المصروف المرن:',
      aiImpactVal: '42% متبقي • في النطاق الآمن',
      // Tab 3
      zatcaPill: 'استيعاب مشفر بتقنية Base64 TLV',
      zatcaTitle: 'فك شفرة فواتير ZATCA الضريبية المعتمدة فوراً',
      zatcaDesc:
        'وجّه كاميرا هاتفك إلى رمز الاستجابة السريعة (QR) على أي فاتورة ضريبية سعودية. يستخرج التطبيق اسم المنشأة، الرقم الضريبي، وتفاصيل ضريبة القيمة المضافة 15% دون أي إدخال يدوي أو ربط بنكي.',
      zatcaBtn: 'محاكاة مسح فاتورة ضريبية جديدة',
      zatcaBadge: 'فاتورة ضريبية مبسطة معتمدة من هيئة الزكاة والضريبة والجمارك',
      zatcaNet: 'المبلغ الخاضع للضريبة:',
      zatcaTax: 'ضريبة القيمة المضافة 15%:',
      zatcaGrand: 'الإجمالي الصافي للفاتورة:',
      zatcaVerified: 'توقيع إلكتروني مشفر معتمد (TLV Valid)',
      // Tab 4
      splitPill: 'دفتر محاسبي عادل متعدد الأطراف',
      splitTitle: 'وضعان مخصصان: تضامن الأسرة أو سكن الزملاء',
      splitDesc:
        'تخلص من حرج المطالبات المالية بين الأهل أو الأصدقاء. بدّل بسهولة بين الميزانية الأسرية التضامنية وميزانية سكن الزملاء مع تسويات بنقرة واحدة.',
      splitModeFamily: 'وضع ميزانية الأسرة',
      splitModeRoommates: 'وضع سكن الزملاء والأصدقاء',
      splitLedgerTitleFamily: 'دفتر التسوية [وضع تضامن الأسرة المستقر]',
      splitLedgerTitleRoommates: 'دفتر التسوية [وضع السكن المشترك للزملاء والأصدقاء]',
      splitLiveBadge: 'أرصدة حية',
      splitResolutionTitle: 'تسوية المديونيات بنقرة زر واحدة:',
      splitResolutionDesc: 'يمكن للشركاء سداد المبالغ المعلقة مباشرة دون أي حسابات يدوية معقدة',
      splitSettleBtn: 'إرسال طلب تسوية واتساب',
    },
    metrics: {
      metric1Val: '100%',
      metric1Title: 'خصوصية سيادية تامة',
      metric1Desc: 'صفر قراءة للرسائل النصية، صفر ربط بنكي إجباري. بياناتك تظل ملكك وحدك.',
      metric2Val: '1 - 31',
      metric2Title: 'مرونة دورة الراتب',
      metric2Desc: 'اضبط راتبك على يوم 27 أو أي يوم في الشهر مع إعادة الحساب الفورية للوتيرة اليومية.',
      metric3Val: '99.4%',
      metric3Title: 'دقة المعالجة الذكية',
      metric3Desc: 'فهم متقدم للهجات الدارجة، الصوت، وفك شفرات ZATCA الضريبية المعقدة.',
      metric4Val: '12',
      metric4Title: 'ركيزة حوكمة مالية',
      metric4Desc: 'من الاحتياطيات الوقائية المؤتمتة إلى الحماية الصارمة على مستوى الصف في السجلات.',
    },
    pillars: {
      badge: 'الصلابة الهندسية والمعمارية',
      title: 'الركائز الـ 12 للحوكمة المالية الذكية',
      subtitle:
        'هندسة مالية متكاملة مصممة للقضاء على غموض مصاريف الأسرة والسكن المشترك بحيادية تقنية تامة.',
      items: [
        {
          title: '1. المساعد الصوتي واللغوي الذكي',
          desc: 'يفكك الرسائل النصية والصوتية الدارجة ويقسم المصاريف المتداخلة بلحظة ودون جداول.',
          icon: 'psychology',
        },
        {
          title: '2. دورة الراتب المرنة (1–31)',
          desc: 'تحرر من الأشهر الميلادية الجامدة واربط بدايات ميزانيتك بيوم 27 أو يوم استحقاقك الفعلي.',
          icon: 'calendar_today',
        },
        {
          title: '3. ماسح فواتير ZATCA والباركود',
          desc: 'قراءة فورية لرموز QR الإلكترونية واستخراج بيانات المورد وضريبة 15% بدقة بالغة.',
          icon: 'qr_code_scanner',
        },
        {
          title: '4. تسوية مصاريف الأهل والزملاء',
          desc: 'حساب صافي الالتزامات للإيجار، الفواتير، والمقاضي تلقائياً دون أي إحراج مالي.',
          icon: 'pie_chart',
        },
        {
          title: '5. مؤشرات ومعدلات الصرف الآمن',
          desc: 'مراقبة الوتيرة اليومية الآمنة والأيام المتبقية والمحافظة على رصيد الطوارئ.',
          icon: 'monitoring',
        },
        {
          title: '6. تصنيفات ومظاريف مخصصة',
          desc: 'مظاريف مرنة للضروريات، الالتزامات الشهرية، التعليم، والترفيه بما يناسب نمط حياتك.',
          icon: 'category',
        },
        {
          title: '7. الاحتياطي التلقائي المحمي',
          desc: 'عزل مبالغ الادخار والطوارئ أولاً، واحتساب الصرف اليومي بناءً على السيولة الحقيقية فقط.',
          icon: 'savings',
        },
        {
          title: '8. أمان على مستوى الصف RLS',
          desc: 'سياسات تشفير صارمة تضمن عدم اطلاع أي طرف إلا على السجلات المصرح له بها.',
          icon: 'security',
        },
        {
          title: '9. سجل تدقيق زمني غير قابل للتعديل',
          desc: 'سجل شفاف يوثق تاريخ من أضاف، عدل، أو صادق على كل عملية مالية مشتركة.',
          icon: 'history_edu',
        },
        {
          title: '10. مساحات مالية متعددة',
          desc: 'التنقل بسهولة بين ميزانيتك الخاصة، صندوق نفقات الأسرة، أو مجموعة سكن الأصدقاء.',
          icon: 'hub',
        },
        {
          title: '11. تقارير نهاية الدورة التنفيذية',
          desc: 'ملخصات بيانية بضغطة واحدة توضح تطور الصرف والوفر مع إمكانية التصدير المحمي.',
          icon: 'summarize',
        },
        {
          title: '12. تسجيل صوتي متقدم باللهجات',
          desc: 'سجل مشترياتك أثناء القيادة أو التسوق بالعامية أو الفصحى بصوتك وبدون استخدام اليدين.',
          icon: 'record_voice_over',
        },
      ],
    },
    security: {
      badge: 'ميثاق الخصوصية الصارم بدون مساومة',
      title: 'بياناتك ملكك وحدك. سيادة رقمية بمستويات بنكية.',
      subtitle:
        'الوضوح المالي لا ينبغي أن يكلفك خصوصيتك. تم بناء نظام BUDGET Tracker بشكل مقصود ليعمل بفعالية تامة دون طلب كلمات مرور الحسابات البنكية أو التجسس على الرسائل النصية.',
      cards: [
        {
          title: 'لا نطلب الربط بالحسابات البنكية',
          desc: 'لا نطلب أبداً بيانات دخولك للإنترنت البنكي، أرقام بطاقاتك، أو تفويضات الوصول المفتوح.',
        },
        {
          title: 'صفر قراءة للرسائل النصية والـ OTP',
          desc: 'رسائلك النصية ورموز التحقق الثنائية تظل محمية تماماً داخل هاتفك دون أن يمسها أحد.',
        },
        {
          title: 'تشفير سحابي متقدم AES-256',
          desc: 'تشفير كامل للبيانات أثناء النقل والتخزين مع سياسات عزل صارمة لكل حساب.',
        },
        {
          title: 'حماية خصوصية أسماء الشركاء',
          desc: 'يمكنك استخدام أسماء مستعارة لشركاء السكن مع صلاحيات رؤية مخصصة لكل مشارك.',
        },
        {
          title: 'معالجة محلية لحسابات الصرف',
          desc: 'معادلات وتيرة الصرف ومتبقي الأيام تحسب محلياً على جهازك دون تتبع تجاري.',
        },
        {
          title: 'شاشة مراجعة قبل الحفظ النهائي',
          desc: 'لا يتم ترحيل أي فاتورة ضريبية أو تسجيل صوتي للسجل الرسمي حتى تقوم بتأكيده بنفسك.',
        },
      ],
    },
    faq: {
      badge: 'قاعدة المعرفة والأسئلة الشائعة',
      title: 'الأسئلة الأكثر شيوعاً',
      items: [
        {
          q: 'كيف يضمن BUDGET Tracker الخصوصية الكاملة بدون ربط بنكي؟',
          sub: 'منهجيتنا المعمارية لحماية الخصوصية',
          a: 'نعتمد على وسائل إدخال فائقة الذكاء والسرعة: التسجيل الصوتي، المعالجة اللغوية للنصوص، وقراءة الباركود الضريبي ZATCA مباشرة. بهذا الأسلوب تتفادى تماماً مشاركة كلمات مرور حساباتك أو إعطاء أذونات لقراءة الرسائل النصية والرموز السرية لأي خادم سحابي.',
        },
        {
          q: 'هل يمكنني تغيير موعد دورة الراتب إلى يوم 27 أو أي تاريخ آخر؟',
          sub: 'دعم كامل لمواعيد الرواتب في المملكة والخليج',
          a: 'نعم بالتأكيد. يمكنك تثبيت يوم نزول الراتب على أي يوم من 1 إلى 31. سواء كان راتبك يصرف في 27 (القطاع الحكومي في السعودية)، أو بداية الشهر، أو أي موعد دوري مخصص، يعاد ضبط الوتيرة اليومية الآمنة فورياً.',
        },
        {
          q: 'كيف يعمل ماسح الفواتير الضريبية الرسمي ZATCA؟',
          sub: 'فك تشفير صيغة Base64 TLV المعتمدة',
          a: 'يقوم القارئ المدمج بفك شفرة ترميز TLV المعتمد من هيئة الزكاة والضريبة والجمارك، مستخرجاً اسم المتجر، الرقم الضريبي، التوقيت، المبلغ الخاضع للضريبة، وقيمة الضريبة 15% خلال أجزاء من الثانية.',
        },
        {
          q: 'ما الفرق بين وضع ميزانية الأسرة ووضع سكن الزملاء؟',
          sub: 'التضامن المتكامل مقابل المقاصة الحسابية الدقيقة',
          a: 'وضع الأسرة يركز على تكامل ميزانية الأب والأم، والمصروفات التضامنية والادخار المشترك. أما وضع الزملاء فيتعامل مع كل فرد كشريك مستقل، مع احتساب دقيق للمبالغ المدفوعة وصافي المديونيات وتسويتها بضغطة زر.',
        },
        {
          q: 'هل يفهم المساعد الذكي اللهجات السعودية والخليجية؟',
          sub: 'فهم طبيعي للغة الحوار اليومية',
          a: 'نعم، المحرك الذكي مدرب خصيصاً على المصطلحات اليومية الدارجة مثل "قطة"، "حاسبت"، "سدد لي"، "مقاضي التموينات"، ويفصل بنود الفاتورة المشتركة تلقائياً.',
        },
        {
          q: 'متى سيتوفر التطبيق رسمياً على متاجر الهواتف؟',
          sub: 'جدول إطلاق تطبيقات iOS و Android و AppGallery',
          a: 'النسخة الحالية متاحة كتطبيق ويب فوري PWA، ونعمل حالياً على إتاحة النسخ الرسمية للمسجلين في قائمة الوصول المبكر VIP لأجهزة iPhone و Android و Huawei قريباً.',
        },
      ],
    },
    earlyAccess: {
      badge: 'قائمة الانتظار لأولوية الوصول VIP',
      title: 'احجز مقعدك في الوصول المبكر الحصري',
      headline: 'اختبر الحوكمة المالية السيادية والصفاء المعيشي',
      desc: 'انضم إلى أكثر من 1,500 أسرة ومهني يطالبون بصفاء مالي فائق دون أي تفريط في خصوصيتهم الرقمية.',
      placeholder: 'أدخل بريدك الإلكتروني...',
      button: 'انضم لقائمة VIP',
      partnerInfo: 'للاستفسارات المؤسسية أو شراكات التوزيع:',
      successMsg: 'تم تسجيلك بنجاح في قائمة الوصول المبكر VIP! سنوافيك برابط التفعيل قريباً.',
    },
    footer: {
      rights: '© 2025 BUDGET Tracker | ميزانية وأكثر. الحوكمة المالية السيادية. جميع الحقوق محفوظة.',
      links: [
        'سياسة الخصوصية السيادية',
        'شروط الاستخدام',
        'ميثاق الأمان والتشفير',
        'خدمة كبار العملاء VIP',
        'الدعم والتواصل',
      ],
      status: 'النظام متصل ويعمل بكفاءة • تشفير RLS 256-BIT',
    },
  },
  en: {
    brand: {
      name: 'BUDGET Tracker',
      tagline: 'Sovereign Financial OS',
      subtagline: 'Autonomous Financial Governance & Shared Ledger',
      sovereignBadge: 'Sovereign OS',
    },
    nav: {
      simulator: 'Live Simulator',
      simulatorSub: 'Interactive',
      telemetry: 'Telemetry',
      telemetrySub: 'Live Metrics',
      pillars: '12 Pillars',
      pillarsSub: 'Architecture',
      security: 'Sovereignty',
      securitySub: 'Zero Bank-Link',
      faq: 'FAQ',
      faqSub: 'Help & Guide',
      vipCta: 'Request VIP Access',
    },
    hero: {
      badge: 'Sovereign Financial Governance • For Families & Modern Shared Living',
      title: 'Crystal Financial Clarity for Your Family & Housemates.',
      subtitle:
        'Autonomous expense telemetry and uncompromising privacy. Tailor your cash cycle to any day (1–31), register expenses via voice NLP, scan certified ZATCA e-invoices instantly, and govern shared apartment debts without bank logins or SMS snooping.',
      ctaPrimary: 'Launch Live Simulator',
      ctaSecondary: 'Explore 12 Governance Pillars',
      spendGaugeTitle: 'Live Spend Gauge',
      spendGaugeVal: 'SAR 145.00',
      spendGaugeUnit: '/ day',
      spendGaugeStatus: 'Optimal pacing gauge',
      spendGaugeProgress: 'Day 12 of 30',
      roommateTitle: 'Roommate Balance Preview',
      roommateVal: '+SAR 420.00',
      roommateStatus: 'Net Creditor',
      roommateSub: 'Majed & Salman balanced',
      roommateSettle: '1-Click Settle',
      ingestionTitle: 'Autonomous Ingestion',
      ingestionVal: '0.28s',
      ingestionUnit: 'Inference',
      ingestionSub: 'Voice & ZATCA TLV Base64',
      ingestionAccuracy: '99.8% Acc',
      guarantee1: '100% Zero Bank-Link Privacy',
      guarantee2: 'ZATCA QR Base64 TLV Compliant',
      guarantee3: 'Coming soon: iOS • Android • AppGallery',
    },
    simulator: {
      badge: 'Interactive Command Cockpit',
      title: 'Live Budget & Governance Simulator',
      subtitle:
        'Test the four foundational pillars of BUDGET Tracker in real-time. Feel the precision of dynamic cash burn rates, AI sentence comprehension, and fair roommate ledgers.',
      tabSalary: '1. Flexible Payday (1–31)',
      tabAi: '2. AI Natural Engine',
      tabZatca: '3. ZATCA Invoice Scanner',
      tabSplit: '4. Fair Expense Ledger',
      // Tab 1
      salaryPill: 'Adaptive Cycle Architecture',
      salaryTitle: 'Liberate Yourself from Rigid Calendar Months',
      salaryDesc:
        'Whether you receive compensation on the 27th (Saudi public sector), on the 1st, or on any custom day, the engine dynamically recalculates your daily burn rate and reserve buffers in real time.',
      disbursementLabel: 'Disbursement Day (Payday):',
      disbursementDay: 'Day {val} of Month',
      day1Label: 'Day 1 (Month Start)',
      day15Label: 'Day 15 (Mid-Month)',
      day27Label: 'Day 27 (GCC Public)',
      day31Label: 'Day 31',
      reserveTitle: 'Automatic Emergency Reserve (15% Lock)',
      reserveVal: 'SAR 2,250.00',
      reserveSub: 'Pre-Allocated Buffer',
      burnRateTitle: 'Safe Daily Burn Rate',
      burnRateSub: 'Live Allowance',
      burnRateOptimal: 'Optimal pacing for the current billing cycle',
      countdownTitle: 'Cycle Countdown',
      countdownSub: 'Next Payday',
      countdownDays: '{val} Days Left',
      poolLabel: 'Monthly Deposit Pool:',
      poolVal: 'SAR 15,000.00',
      poolDesc: '50% Fixed Essentials • 35% Discretionary • 15% Auto Reserve',
      healthTag: 'Health: Excellent Pacing',
      // Tab 2
      aiPill: 'Zero Form Friction NLP',
      aiTitle: 'Log Any Complex Multi-Person Bill with a Single Sentence',
      aiDesc:
        'No tedious forms or multi-step dropdowns. Speak or type naturally in English or colloquial Arabic, and the fine-tuned financial model extracts vendor, amount, categories, and roommate split quotas instantaneously.',
      aiPromptLabel: 'Try An Interactive Sentence:',
      aiPresets: [
        'Apartment electricity bill 420 SAR divided across 4 rooms',
        'Dinner barbecue feast 1800 SAR shared between 6 people',
        'Home high-speed internet 280 SAR paid by me Omar owes half',
      ],
      aiStatus: 'Autonomous Inference Engine • 0.28s',
      aiPrecision: '99.8% Precision',
      aiCatLabel: 'Identified Category:',
      aiTotalLabel: 'Extracted Total:',
      aiLedgerLabel: 'Automated Split Ledger:',
      aiPayer: 'You (Payer)',
      aiDebtor1: 'Majed (Debtor)',
      aiDebtor2: 'Salman (Debtor)',
      aiImpactLabel: 'Discretionary Pool Impact:',
      aiImpactVal: '42% Remaining • Healthy',
      // Tab 3
      zatcaPill: 'Base64 TLV Cryptographic Ingestion',
      zatcaTitle: 'Instant ZATCA Certified e-Invoice Decoding',
      zatcaDesc:
        'Point your mobile camera at any Saudi tax invoice QR code. The app decodes seller credentials, VAT registration numbers, and 15% VAT breakdowns with zero manual input and zero bank integration required.',
      zatcaBtn: 'Simulate Next QR Scan',
      zatcaBadge: 'ZATCA Certified Simplified Tax Invoice',
      zatcaNet: 'Taxable Net Amount:',
      zatcaTax: 'VAT 15%:',
      zatcaGrand: 'Grand Invoice Total:',
      zatcaVerified: 'Valid Cryptographic Signature (TLV)',
      // Tab 4
      splitPill: 'Equitable Multi-Party Ledger',
      splitTitle: 'Two Dedicated Modes: Family Solidarity or Roommates',
      splitDesc:
        'Eliminate awkward financial discussions. Switch smoothly between proportional household budgeting (fair salary-weighted contributions) and roommate mode with zero-friction one-click settlements.',
      splitModeFamily: 'Family Mode',
      splitModeRoommates: 'Roommates Mode',
      splitLedgerTitleFamily: 'Settlement Ledger [Family Solidarity Mode]',
      splitLedgerTitleRoommates: 'Settlement Ledger [Roommates Shared Living Mode]',
      splitLiveBadge: 'LIVE BALANCES',
      splitResolutionTitle: 'One-Click Debt Resolution:',
      splitResolutionDesc: 'Majed & Salman can clear SAR 420.00 to your account seamlessly',
      splitSettleBtn: 'Send Settle Request',
    },
    metrics: {
      metric1Val: '100%',
      metric1Title: 'Sovereign Privacy',
      metric1Desc: 'Zero SMS scraping, zero mandatory bank syncing. Your ledgers stay isolated on your terms.',
      metric2Val: '1 - 31',
      metric2Title: 'Flexible Pay Cycle Days',
      metric2Desc: 'Set your salary baseline to the 27th, 1st, or custom bi-weekly cadence with automatic recalculations.',
      metric3Val: '99.4%',
      metric3Title: 'AI Extraction Accuracy',
      metric3Desc: 'Multilingual voice transcripts and tax QR decoders that parse compound shared expenses.',
      metric4Val: '12',
      metric4Title: 'Governance Pillars',
      metric4Desc: 'From automatic emergency reserves to cryptographic row-level audit trails.',
    },
    pillars: {
      badge: 'Architectural Integrity',
      title: 'The 12 Pillars of Financial Governance',
      subtitle:
        'A comprehensive fintech architecture engineered to eliminate household financial ambiguity with absolute technical neutrality.',
      items: [
        {
          title: '1. Conversational AI Assistant',
          desc: 'Instantly parses messy voice and text messages, breaking down complex multi-person purchases without spreadsheets.',
          icon: 'psychology',
        },
        {
          title: '2. Flexible Salary Cycle (Days 1–31)',
          desc: 'Break free from rigid calendar months. Anchor your financial month to the 27th, 1st, or any custom pay schedule.',
          icon: 'calendar_today',
        },
        {
          title: '3. ZATCA & Tax QR Scanner',
          desc: 'Reads e-invoicing QR codes instantly to decode seller details, 15% VAT, and items in milliseconds.',
          icon: 'qr_code_scanner',
        },
        {
          title: '4. Fair Family & Roommate Splits',
          desc: 'Dynamic settlement ledgers calculate net balances for rent, utilities, and groceries without awkward negotiations.',
          icon: 'pie_chart',
        },
        {
          title: '5. Real-Time Cockpit Analytics',
          desc: 'Monitor your daily burn rate, remaining runway, and projected month-end balance with crystalline gauges.',
          icon: 'monitoring',
        },
        {
          title: '6. Custom Expense Buckets',
          desc: 'Adaptable hierarchies for essentials, lifestyle, rent, schooling, and recurring commitments tailored to your habits.',
          icon: 'category',
        },
        {
          title: '7. Automated Smart Reserves',
          desc: 'Quarantine emergency and savings funds first, calculating daily allowance only on truly disposable income.',
          icon: 'savings',
        },
        {
          title: '8. Row-Level Security via Supabase',
          desc: 'Strict cryptographic row-level security policies ensure only authorized participants view each specific record.',
          icon: 'security',
        },
        {
          title: '9. Immutable Audit Trails',
          desc: 'Transparent chronological changelog verifies who added, modified, or approved each shared ledger line item.',
          icon: 'history_edu',
        },
        {
          title: '10. Multi-Household Spaces',
          desc: 'Seamlessly switch between personal private budgets, family household ledgers, and vacation home groups.',
          icon: 'hub',
        },
        {
          title: '11. Cycle-End Executive Reports',
          desc: 'One-click clean summary PDFs and exportable CSVs for household reviews, tax archiving, and savings audits.',
          icon: 'summarize',
        },
        {
          title: '12. Natural Multilingual Voice Notes',
          desc: 'Capture expenses hands-free in English, Arabic dialects, or colloquial phrasing while driving or checking out.',
          icon: 'record_voice_over',
        },
      ],
    },
    security: {
      badge: 'Zero-Compromise Privacy Charter',
      title: 'Your Data Is Yours Alone. Bank-Grade Sovereignty.',
      subtitle:
        'Financial clarity should never come at the expense of your sovereignty. BUDGET Tracker is intentionally architected to function without invasive open-banking credentials or SMS message access.',
      cards: [
        {
          title: 'No Bank Linking Required',
          desc: 'We never ask for online banking logins, credit card numbers, or open banking tokens.',
        },
        {
          title: 'Zero SMS & OTP Access',
          desc: 'Your sensitive text messages, 2FA codes, and OTPs remain completely untouched on your device.',
        },
        {
          title: 'AES-256 Cloud Encryption',
          desc: 'End-to-end encryption in transit and at rest with isolated row-level tenant access controls.',
        },
        {
          title: 'Protected Roommate Aliases',
          desc: 'Use pseudonyms for housemates or family members with granular visibility permissions.',
        },
        {
          title: 'Local Salary Calculations',
          desc: 'Safe spend formulas and runway calculations evaluate locally without marketing telemetry.',
        },
        {
          title: 'Pre-Save Verification Card',
          desc: 'No AI extraction or QR scan is committed to your permanent ledger until you visually verify it.',
        },
      ],
    },
    faq: {
      badge: 'Knowledge & Support Base',
      title: 'Frequently Asked Questions',
      items: [
        {
          q: 'How does BUDGET Tracker ensure 100% privacy without open-banking links?',
          sub: 'Our zero-compromise architectural approach',
          a: 'We leverage ultra-fast AI input modalities: conversational voice parsing, natural text interpretation, and instantaneous ZATCA QR decoding. By avoiding traditional open-banking integrations, you never expose bank account passwords, card pins, or personal SMS text records to any cloud aggregator.',
        },
        {
          q: 'Can I customize the salary cycle to the 27th or any other day?',
          sub: 'Support for Saudi and GCC payment schedules',
          a: 'Yes. You can anchor your disbursement date to any day between 1 and 31. Whether your salary arrives on the 27th (Saudi public sector), at the 1st of the month, or on an alternate corporate schedule, all safe burn rate projections recalculate accordingly.',
        },
        {
          q: 'How does the official ZATCA QR e-invoice decoder function?',
          sub: 'Cryptographic Base64 TLV parsing',
          a: 'Our client-side reader decodes the Base64 TLV structure mandated by the Zakat, Tax and Customs Authority. It extracts the merchant name, tax registration number, timestamp, taxable subtotal, and 15% VAT within milliseconds with zero typing error.',
        },
        {
          q: 'What distinguishes Family Mode from Roommates Mode?',
          sub: 'Harmonious solidarity vs. precise debt clearing',
          a: 'Family Mode focuses on proportional income allocation, household reserve buffers, and collective child allocations. Roommates Mode treats each person as an autonomous counterparty, keeping clean peer-to-peer debit/credit records with instant 1-click settlements.',
        },
        {
          q: 'Does the AI engine support Gulf dialects as well as English?',
          sub: 'Natural conversational comprehension',
          a: 'Yes. The model is specifically fine-tuned for regional vernacular terms like "قطة" (split), "حاسبت" (I paid), and "سدد لي" (settle to me), as well as colloquial conversational English expressions.',
        },
        {
          q: 'When is the official mobile release slated for?',
          sub: 'iOS, Android & Huawei AppGallery schedule',
          a: 'We are currently conducting the private VIP Closed Beta. Waitlist members will receive priority rollout invitations for iOS App Store, Google Play, and Huawei AppGallery.',
        },
      ],
    },
    earlyAccess: {
      badge: 'VIP Priority Waitlist',
      title: 'Reserve Your Sovereign Access Seat',
      headline: 'Experience Sovereign Financial Governance & Balanced Living',
      desc: 'Join over 1,500 pioneer families and professionals who demand absolute financial clarity without compromising digital sovereignty.',
      placeholder: 'Enter your email address...',
      button: 'Join VIP Waitlist',
      partnerInfo: 'For institutional partnerships or household group deployments:',
      successMsg: 'Thank you for requesting VIP Sovereign Access! Confirmation sent to your email.',
    },
    footer: {
      rights: '© 2025 BUDGET Tracker Sovereign Financial Architecture. All rights reserved. Built for clarity and equitable shared living.',
      links: [
        'Privacy Policy',
        'Terms of Service',
        'Sovereign Security',
        'VIP SLA',
        'Support',
      ],
      status: 'SYSTEM ONLINE • 256-BIT RLS',
    },
  },
};
