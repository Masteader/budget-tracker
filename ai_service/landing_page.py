"""
Landing page and auth confirmation HTML generator for Budget Tracker (budget.fmsco.com.sa).
Features:
- Premium dark fintech design with glassmorphism and glowing accents.
- Full bilingual Arabic / English instant toggle with RTL support.
- Store badges: Google Play, Apple App Store, Huawei AppGallery ("Coming Soon").
- Comprehensive feature breakdown.
- Privacy Policy & Terms of Service sections.
- Contact email: abedmowafaq@gmail.com.
"""

def get_landing_page_html() -> str:
    return """<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • ميزانية الأسرة الذكية</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-main: #0B0F17;
      --bg-card: rgba(22, 27, 34, 0.85);
      --bg-card-hover: rgba(30, 38, 48, 0.95);
      --border-color: rgba(255, 255, 255, 0.08);
      --border-glow: rgba(0, 200, 150, 0.25);
      --primary: #00C896;
      --primary-glow: #05E2B5;
      --accent-gold: #F59E0B;
      --accent-blue: #38BDF8;
      --accent-purple: #8B5CF6;
      --text-main: #F3F4F6;
      --text-muted: #94A3B8;
      --font-ar: 'Cairo', -apple-system, sans-serif;
      --font-en: 'Outfit', -apple-system, sans-serif;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      scroll-behavior: smooth;
    }

    body {
      background-color: var(--bg-main);
      color: var(--text-main);
      font-family: var(--font-ar);
      min-height: 100vh;
      overflow-x: hidden;
      line-height: 1.6;
      position: relative;
    }

    body.lang-en {
      font-family: var(--font-en);
      direction: ltr;
    }

    /* Ambient background glows */
    .glow-orb-1 {
      position: fixed;
      top: -10vw;
      right: -10vw;
      width: 45vw;
      height: 45vw;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(0, 200, 150, 0.12) 0%, transparent 70%);
      pointer-events: none;
      z-index: 0;
    }

    .glow-orb-2 {
      position: fixed;
      bottom: -15vw;
      left: -10vw;
      width: 50vw;
      height: 50vw;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(56, 189, 248, 0.08) 0%, transparent 70%);
      pointer-events: none;
      z-index: 0;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 24px;
      position: relative;
      z-index: 1;
    }

    /* Header & Navigation */
    header {
      padding: 24px 0;
      border-bottom: 1px solid var(--border-color);
      backdrop-filter: blur(12px);
      position: sticky;
      top: 0;
      z-index: 100;
      background: rgba(11, 15, 23, 0.85);
    }

    .nav-wrapper {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .logo-group {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: inherit;
    }

    .logo-icon {
      width: 42px;
      height: 42px;
      background: linear-gradient(135deg, #00C896, #0284c7);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      box-shadow: 0 4px 20px rgba(0, 200, 150, 0.35);
    }

    .logo-text h1 {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(to right, #FFFFFF, #94A3B8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .logo-text span {
      font-size: 11px;
      color: var(--primary);
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 1px;
      display: block;
    }

    .nav-actions {
      display: flex;
      align-items: center;
      gap: 16px;
    }

    .lang-toggle-btn {
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid var(--border-color);
      color: var(--text-main);
      padding: 8px 16px;
      border-radius: 30px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.25s ease;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .lang-toggle-btn:hover {
      background: rgba(0, 200, 150, 0.15);
      border-color: var(--primary);
      transform: translateY(-1px);
    }

    /* Hero Section */
    .hero {
      padding: 70px 0 50px;
      text-align: center;
    }

    .pill-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 18px;
      background: rgba(0, 200, 150, 0.1);
      border: 1px solid var(--border-glow);
      border-radius: 40px;
      color: var(--primary-glow);
      font-size: 13px;
      font-weight: 700;
      margin-bottom: 24px;
      box-shadow: 0 0 20px rgba(0, 200, 150, 0.15);
    }

    .hero-title {
      font-size: clamp(32px, 5vw, 56px);
      font-weight: 900;
      line-height: 1.25;
      margin-bottom: 20px;
      letter-spacing: -0.5px;
    }

    .hero-title .highlight {
      background: linear-gradient(135deg, #00C896 0%, #38BDF8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .hero-desc {
      font-size: clamp(16px, 2vw, 19px);
      color: var(--text-muted);
      max-width: 780px;
      margin: 0 auto 36px;
      line-height: 1.8;
    }

    /* Store Badges Coming Soon */
    .store-badges-wrapper {
      display: flex;
      justify-content: center;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 50px;
    }

    .store-badge {
      display: flex;
      align-items: center;
      gap: 14px;
      background: #161B22;
      border: 1px solid #30363D;
      padding: 12px 22px;
      border-radius: 16px;
      min-width: 210px;
      position: relative;
      overflow: hidden;
      transition: all 0.3s ease;
      text-decoration: none;
      color: inherit;
    }

    .store-badge:hover {
      border-color: rgba(255, 255, 255, 0.25);
      transform: translateY(-2px);
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }

    .store-icon {
      font-size: 28px;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .store-info {
      text-align: start;
    }

    .store-subtitle {
      font-size: 11px;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .store-title {
      font-size: 15px;
      font-weight: 800;
      color: #FFFFFF;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .coming-soon-tag {
      background: rgba(245, 158, 11, 0.15);
      border: 1px solid rgba(245, 158, 11, 0.4);
      color: var(--accent-gold);
      font-size: 10px;
      padding: 2px 7px;
      border-radius: 8px;
      font-weight: 800;
    }

    /* Live App Interactive Frame Mockup */
    .mockup-container {
      max-width: 820px;
      margin: 0 auto 80px;
      padding: 24px;
      background: linear-gradient(180deg, rgba(22, 27, 34, 0.8) 0%, rgba(13, 17, 23, 0.95) 100%);
      border: 1px solid var(--border-color);
      border-radius: 28px;
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.6), 0 0 40px rgba(0, 200, 150, 0.1);
      position: relative;
    }

    .mockup-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 20px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.06);
      margin-bottom: 24px;
    }

    .mockup-badge {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 13px;
      font-weight: 700;
      color: var(--primary);
    }

    .mockup-pulse {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--primary);
      box-shadow: 0 0 10px var(--primary);
      animation: pulse 2s infinite;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.5; transform: scale(1.3); }
    }

    .mockup-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-bottom: 20px;
    }

    .mockup-card {
      background: rgba(13, 17, 23, 0.9);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 18px;
      padding: 20px;
      text-align: start;
    }

    .mockup-card-label {
      font-size: 12px;
      color: var(--text-muted);
      margin-bottom: 6px;
    }

    .mockup-card-val {
      font-size: 24px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 8px;
    }

    .mockup-progress-bar {
      height: 6px;
      background: rgba(255, 255, 255, 0.08);
      border-radius: 4px;
      overflow: hidden;
      margin-top: 10px;
    }

    .mockup-progress-fill {
      height: 100%;
      background: linear-gradient(90deg, #00C896, #38BDF8);
      border-radius: 4px;
    }

    .mockup-chat-banner {
      background: rgba(0, 200, 150, 0.08);
      border: 1px solid rgba(0, 200, 150, 0.2);
      border-radius: 14px;
      padding: 14px 18px;
      display: flex;
      align-items: center;
      gap: 12px;
      text-align: start;
    }

    .mockup-chat-icon {
      font-size: 22px;
    }

    .mockup-chat-text {
      font-size: 13px;
      color: var(--primary-glow);
      font-weight: 600;
    }

    /* Features Section */
    .section-header {
      text-align: center;
      margin-bottom: 50px;
    }

    .section-title {
      font-size: clamp(26px, 3.5vw, 38px);
      font-weight: 800;
      margin-bottom: 14px;
    }

    .section-subtitle {
      font-size: 16px;
      color: var(--text-muted);
      max-width: 620px;
      margin: 0 auto;
    }

    .features-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 24px;
      margin-bottom: 90px;
    }

    .feature-card {
      background: var(--bg-card);
      border: 1px solid var(--border-color);
      border-radius: 24px;
      padding: 32px 28px;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      position: relative;
      overflow: hidden;
    }

    .feature-card:hover {
      background: var(--bg-card-hover);
      border-color: rgba(0, 200, 150, 0.3);
      transform: translateY(-4px);
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.4);
    }

    .feature-icon-wrapper {
      width: 54px;
      height: 54px;
      border-radius: 16px;
      background: rgba(255, 255, 255, 0.04);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 26px;
      margin-bottom: 22px;
      border: 1px solid rgba(255, 255, 255, 0.06);
    }

    .feature-card:nth-child(1) .feature-icon-wrapper { background: rgba(0, 200, 150, 0.12); color: #00C896; border-color: rgba(0, 200, 150, 0.3); }
    .feature-card:nth-child(2) .feature-icon-wrapper { background: rgba(56, 189, 248, 0.12); color: #38BDF8; border-color: rgba(56, 189, 248, 0.3); }
    .feature-card:nth-child(3) .feature-icon-wrapper { background: rgba(245, 158, 11, 0.12); color: #F59E0B; border-color: rgba(245, 158, 11, 0.3); }
    .feature-card:nth-child(4) .feature-icon-wrapper { background: rgba(139, 92, 246, 0.12); color: #8B5CF6; border-color: rgba(139, 92, 246, 0.3); }
    .feature-card:nth-child(5) .feature-icon-wrapper { background: rgba(236, 72, 153, 0.12); color: #EC4899; border-color: rgba(236, 72, 153, 0.3); }
    .feature-card:nth-child(6) .feature-icon-wrapper { background: rgba(16, 185, 129, 0.12); color: #10B981; border-color: rgba(16, 185, 129, 0.3); }

    .feature-title {
      font-size: 20px;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 12px;
    }

    .feature-desc {
      font-size: 15px;
      color: var(--text-muted);
      line-height: 1.7;
    }

    /* Privacy & Terms Container */
    .legal-section {
      background: #161B22;
      border: 1px solid var(--border-color);
      border-radius: 24px;
      padding: 40px 32px;
      margin-bottom: 80px;
    }

    .legal-tabs {
      display: flex;
      gap: 12px;
      margin-bottom: 24px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      padding-bottom: 12px;
    }

    .legal-tab-btn {
      background: none;
      border: none;
      color: var(--text-muted);
      font-size: 16px;
      font-weight: 700;
      cursor: pointer;
      padding: 8px 16px;
      border-radius: 8px;
      transition: all 0.2s ease;
      font-family: inherit;
    }

    .legal-tab-btn.active {
      color: var(--primary);
      background: rgba(0, 200, 150, 0.1);
    }

    .legal-content {
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.8;
      max-height: 300px;
      overflow-y: auto;
      padding-right: 12px;
    }

    .legal-content h4 {
      color: #FFFFFF;
      margin: 16px 0 8px;
      font-size: 16px;
    }

    /* Contact Banner */
    .contact-banner {
      background: radial-gradient(circle at top right, rgba(0, 200, 150, 0.15), transparent 60%), #161B22;
      border: 1px solid rgba(0, 200, 150, 0.3);
      border-radius: 28px;
      padding: 48px 36px;
      text-align: center;
      margin-bottom: 80px;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
    }

    .contact-title {
      font-size: 26px;
      font-weight: 800;
      margin-bottom: 12px;
    }

    .contact-desc {
      color: var(--text-muted);
      font-size: 15px;
      max-width: 580px;
      margin: 0 auto 28px;
    }

    .email-chip {
      display: inline-flex;
      align-items: center;
      gap: 12px;
      background: #0D1117;
      border: 1px solid rgba(255, 255, 255, 0.15);
      padding: 12px 24px;
      border-radius: 40px;
      color: #FFFFFF;
      font-size: 16px;
      font-weight: 700;
      text-decoration: none;
      transition: all 0.25s ease;
    }

    .email-chip:hover {
      border-color: var(--primary);
      background: rgba(0, 200, 150, 0.1);
      transform: scale(1.02);
      color: var(--primary-glow);
    }

    /* Footer */
    footer {
      border-top: 1px solid var(--border-color);
      padding: 40px 0 60px;
      text-align: center;
      color: var(--text-muted);
      font-size: 14px;
    }

    .footer-links {
      display: flex;
      justify-content: center;
      gap: 24px;
      margin-bottom: 16px;
    }

    .footer-links a {
      color: var(--text-muted);
      text-decoration: none;
      transition: color 0.2s ease;
    }

    .footer-links a:hover {
      color: var(--primary);
    }

    /* Responsive */
    @media (max-width: 768px) {
      .hero { padding: 40px 0 30px; }
      .store-badge { width: 100%; justify-content: center; }
      .mockup-grid { grid-template-columns: 1fr; }
      .features-grid { grid-template-columns: 1fr; }
      .contact-banner { padding: 32px 20px; }
    }
  </style>
</head>
<body id="page-body">

  <div class="glow-orb-1"></div>
  <div class="glow-orb-2"></div>

  <!-- Header -->
  <header>
    <div class="container nav-wrapper">
      <a href="/" class="logo-group">
        <div class="logo-icon">💰</div>
        <div class="logo-text">
          <h1>Budget Tracker</h1>
          <span id="nav-brand-sub">ميزانية الأسرة</span>
        </div>
      </a>
      <div class="nav-actions">
        <button id="lang-btn" class="lang-toggle-btn" onclick="toggleLanguage()">
          🌐 <span>English</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Hero Section -->
  <main class="container">
    <section class="hero">
      <div class="pill-badge" id="hero-pill">
        ✨ ميزانية الأسرة الذكية • متوافقة مع دورة الراتب السعودي
      </div>
      <h2 class="hero-title">
        <span id="hero-title-1">تحكّم في ميزانية أسرتك بدقة</span><br>
        <span class="highlight" id="hero-title-2">ومتوافقة تماماً مع دورة الراتب يوم 27</span>
      </h2>
      <p class="hero-desc" id="hero-desc">
        صُمم خصيصاً للأسر في المملكة العربية السعودية. أتقن دورة الراتب يوم 27 مع الحساب التلقائي للعطلات، امسح الفواتير بالذكاء الاصطناعي، قسّم المصاريف بين الشركاء بعدالة، وابنِ احتياطي ادخار أسري تلقائياً دون أي تعقيد.
      </p>

      <!-- Store Badges Coming Soon -->
      <div class="store-badges-wrapper">
        <!-- Google Play -->
        <div class="store-badge">
          <div class="store-icon">🤖</div>
          <div class="store-info">
            <div class="store-subtitle" id="badge-android-sub">متوفر قريباً على</div>
            <div class="store-title">
              Google Play <span class="coming-soon-tag" id="tag-1">قريباً</span>
            </div>
          </div>
        </div>

        <!-- App Store -->
        <div class="store-badge">
          <div class="store-icon">🍎</div>
          <div class="store-info">
            <div class="store-subtitle" id="badge-apple-sub">متوفر قريباً على</div>
            <div class="store-title">
              App Store <span class="coming-soon-tag" id="tag-2">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Huawei AppGallery -->
        <div class="store-badge">
          <div class="store-icon">🛍️</div>
          <div class="store-info">
            <div class="store-subtitle" id="badge-huawei-sub">متوفر قريباً على</div>
            <div class="store-title">
              AppGallery <span class="coming-soon-tag" id="tag-3">قريباً</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Live App Mockup -->
      <div class="mockup-container">
        <div class="mockup-header">
          <div class="mockup-badge">
            <span class="mockup-pulse"></span>
            <span id="mockup-status">دورة راتب نشطة: أكتوبر 2026</span>
          </div>
          <div style="font-size: 13px; color: var(--text-muted);" id="mockup-days">
            متبقي 16 يوم على الراتب
          </div>
        </div>

        <div class="mockup-grid">
          <div class="mockup-card">
            <div class="mockup-card-label" id="mockup-lbl-1">معدل الصرف اليومي الآمن</div>
            <div class="mockup-card-val" style="color: #00C896;">340 <small style="font-size: 14px;">ر.س / يوم</small></div>
            <div class="mockup-progress-bar">
              <div class="mockup-progress-fill" style="width: 48%;"></div>
            </div>
          </div>

          <div class="mockup-card">
            <div class="mockup-card-label" id="mockup-lbl-2">احتياطي الادخار الأسري</div>
            <div class="mockup-card-val" style="color: #F59E0B;">4,250 <small style="font-size: 14px;">ر.س</small></div>
            <div class="mockup-progress-bar">
              <div class="mockup-progress-fill" style="width: 75%; background: #F59E0B;"></div>
            </div>
          </div>

          <div class="mockup-card">
            <div class="mockup-card-label" id="mockup-lbl-3">المصاريف المشتركة والمستحقات</div>
            <div class="mockup-card-val" style="color: #38BDF8;">+320 <small style="font-size: 14px;">ر.س للشريك</small></div>
            <div class="mockup-progress-bar">
              <div class="mockup-progress-fill" style="width: 60%; background: #38BDF8;"></div>
            </div>
          </div>
        </div>

        <div class="mockup-chat-banner">
          <div class="mockup-chat-icon">✨</div>
          <div class="mockup-chat-text" id="mockup-chat-txt">
            المساعد الذكي داخل التطبيق: التقط صورة لأي فاتورة أو اكتب مشترياتك في الشات وسيتم تسجيلها تلقائياً.
          </div>
        </div>
      </div>
    </section>

    <!-- Detailed Features -->
    <section class="section-header" id="features">
      <h3 class="section-title" id="features-title">مميزات صُممت لراحتك المالية</h3>
      <p class="section-subtitle" id="features-subtitle">حلول رقمية متكاملة تواكب نمط حياة الأسرة السعودية واحتياجاتها الحقيقية</p>
    </section>

    <div class="features-grid">
      <!-- Feature 1 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">🤖</div>
        <h4 class="feature-title" id="f1-title">مساعد ذكي ومسح فوري للفواتير</h4>
        <p class="feature-desc" id="f1-desc">
          التقط صورة لأي فاتورة ورقية أو إلكترونية ليقوم محرك الذكاء الاصطناعي باستخراج اسم المتجر، التاريخ، وضريبة القيمة المضافة فورياً. كما يمكنك تسجيل أي مصروف مباشرة عبر شات التطبيق باللغة العربية، الإنجليزية، أو الأردية.
        </p>
      </div>

      <!-- Feature 2 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">📅</div>
        <h4 class="feature-title" id="f2-title">دورة الراتب السعودي (يوم 27)</h4>
        <p class="feature-desc" id="f2-desc">
          مبني وفق روزنامة صرف الرواتب يوم 27 مع تطبيق قواعد الصرف المصرفية السعودية تلقائياً (الصرف يوم الخميس إذا صادف الجمعة، ويوم الأحد إذا صادف السبت) مع متابعة وتيرة الصرف اليومية لمنع نفاد الميزانية قبل الراتب القادم.
        </p>
      </div>

      <!-- Feature 3 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">🛡️</div>
        <h4 class="feature-title" id="f3-title">احتياطي الادخار الذكي</h4>
        <p class="feature-desc" id="f3-desc">
          الفائض من الراتب الذي لم يُخصص لبنود معينة يتحول تلقائياً إلى صندوق احتياطي الادخار الأسري، ليكون بمثابة صمام أمان يغطي أي تجاوز غير متوقع في البنود الأساسية بكل مرونة وبدون إرباك لخطة الشهر.
        </p>
      </div>

      <!-- Feature 4 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">👥</div>
        <h4 class="feature-title" id="f4-title">تقسيم عادل بين الشركاء والأسرة</h4>
        <p class="feature-desc" id="f4-desc">
          شارك ميزانية المنزل مع شريكك برمز دعوة آمن ومباشر. نظام التوثيق ثنائي الأبعاد يرصد "من دفع المصروف" و"من استفاد منه" لحساب التسويات الصافية والديون المتبادلة بمنتهى الشفافية والراحة.
        </p>
      </div>

      <!-- Feature 5 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">📂</div>
        <h4 class="feature-title" id="f5-title">مكتبة تصنيفات وحماية تامة للبيانات</h4>
        <p class="feature-desc" id="f5-desc">
          تصنيفات متكاملة تشمل التموين، المطاعم، الفواتير، والأقساط بالإضافة لإمكانية إنشاء تصنيفات خاصة بأسرتك. لا يتم حذف أي تصنيف نهائياً بل يتم تحويله لمكتبة التصنيفات (غير نشط) لحفظ تاريخك المالي وسجلاتك بنسبة 100%.
        </p>
      </div>

      <!-- Feature 6 -->
      <div class="feature-card">
        <div class="feature-icon-wrapper">🔒</div>
        <h4 class="feature-title" id="f6-title">خصوصية مصرفية وثقة مطلقة</h4>
        <p class="feature-desc" id="f6-desc">
          لا نطلب أي صلاحيات لقراءة الرسائل النصية في الخلفية ولا نصل لأي بيانات بنكية حساسة. جميع بيانات أسرتك معزولة بأعلى معايير الأمان وقواعد التشفير الحديثة (Row-Level Security).
        </p>
      </div>
    </div>

    <!-- Legal Section (Privacy & Terms) -->
    <section class="legal-section" id="legal">
      <div class="legal-tabs">
        <button class="legal-tab-btn active" id="tab-privacy-btn" onclick="showLegalTab('privacy')">سياسة الخصوصية</button>
        <button class="legal-tab-btn" id="tab-terms-btn" onclick="showLegalTab('terms')">شروط الاستخدام</button>
      </div>

      <div id="privacy-content" class="legal-content">
        <h4 id="lp-1">1. الالتزام بالخصوصية وحماية البيانات</h4>
        <p id="lp-1-txt">نحن في Budget Tracker نولي خصوصية بياناتك المالية الأولوية القصوى. صُمم التطبيق ليعمل بأعلى معايير الأمان وعزل البيانات السحابية بين الأسر المشتركة.</p>
        
        <h4 id="lp-2">2. البيانات التي يتم جمعها</h4>
        <p id="lp-2-txt">يقتصر جمع البيانات على المعلومات التي يُدخلها المستخدم طواعية: عنوان البريد الإلكتروني للمصادقة، النفقات المسجلة يدوياً أو عبر الشات، والصور الملتقطة للفواتير لمعالجتها واستخراج الإجمالي.</p>
        
        <h4 id="lp-3">3. الصلاحيات وشفافية الاستخدام</h4>
        <p id="lp-3-txt">التطبيق لا يطلب أي صلاحيات اعتراض أو قراءة للرسائل النصية التلقائية. مسح الفواتير يتم محلياً وعند طلب المستخدم فقط عبر كاميرا أو معرض الصور.</p>
        
        <h4 id="lp-4">4. عدم مشاركة البيانات وحق الحذف</h4>
        <p id="lp-4-txt">لا نقوم ببيع أو مشاركة بياناتك مع أي طرف ثالث لأغراض تسويقية أو تجارية. يحق للمستخدم حذف حسابه وبياناته في أي وقت من خلال التواصل مع الدعم عبر: abedmowafaq@gmail.com.</p>
      </div>

      <div id="terms-content" class="legal-content" style="display: none;">
        <h4 id="lt-1">1. الموافقة على الشروط</h4>
        <p id="lt-1-txt">باستخدامك لتطبيق وموقع Budget Tracker، فإنك توافق على الالتزام بهذه الشروط والأحكام ومتابعة تحديثاتها الدورية.</p>
        
        <h4 id="lt-2">2. الاستخدام المالي والشخصي</h4>
        <p id="lt-2-txt">التطبيق مخصص لإدارة الميزانيات الشخصية والأسرية ويقدم مؤشرات وتوقعات استرشادية مبنية على البيانات المدخلة من قبل المستخدم دون أن يُعتبر ذلك مشورة استثمارية رسمية.</p>
        
        <h4 id="lt-3">3. أمن الحساب</h4>
        <p id="lt-3-txt">المستخدم مسؤول عن الحفاظ على سرية بيانات تسجيل الدخول ورموز دعوة الأسرة الممنوحة لأفراد عائلته.</p>
        
        <h4 id="lt-4">4. التواصل والدعم الفني</h4>
        <p id="lt-4-txt">لأي استفسارات أو ملاحظات، يُرجى مراسلة المطور مباشرة على البريد الإلكتروني: abedmowafaq@gmail.com.</p>
      </div>
    </section>

    <!-- Contact Banner -->
    <section class="contact-banner" id="contact">
      <h3 class="contact-title" id="contact-title">هل لديك استفسار أو ترغب في الانضمام للنسخة التجريبية؟</h3>
      <p class="contact-desc" id="contact-desc">
        يسعدنا دائماً تواصلكم وتلقي آرائكم ومقترحاتكم لتطوير التطبيق وخدمة الأسر بأفضل صورة ممكنة.
      </p>
      <a href="mailto:abedmowafaq@gmail.com" class="email-chip">
        ✉️ <span>abedmowafaq@gmail.com</span>
      </a>
    </section>
  </main>

  <!-- Footer -->
  <footer>
    <div class="container">
      <div class="footer-links">
        <a href="#features" id="ft-features">المميزات</a>
        <a href="#legal" onclick="showLegalTab('privacy')" id="ft-privacy">سياسة الخصوصية</a>
        <a href="#legal" onclick="showLegalTab('terms')" id="ft-terms">شروط الاستخدام</a>
        <a href="mailto:abedmowafaq@gmail.com" id="ft-contact">اتصل بنا</a>
      </div>
      <p id="ft-copy">© 2026 Budget Tracker • جميع الحقوق محفوظة.</p>
    </div>
  </footer>

  <script>
    let currentLang = 'ar';

    const translations = {
      en: {
        dir: 'ltr',
        bodyClass: 'lang-en',
        langBtnText: '🇸🇦 العربية',
        navBrandSub: 'Family Budget',
        heroPill: '✨ Smart Family Budgeting • Saudi Salary Cycle Engine',
        heroTitle1: 'Master Your Family Budget with AI Precision',
        heroTitle2: 'Engineered for the Saudi 27th Payday Cycle',
        heroDesc: 'Crafted specifically for households in Saudi Arabia. Master the 27th payday cycle with automated weekend shift rules, scan receipts via in-app AI, split expenses fairly with partner attribution, and build your emergency savings reserve effortlessly.',
        badgeAndroidSub: 'Coming Soon On',
        badgeAppleSub: 'Coming Soon On',
        badgeHuaweiSub: 'Coming Soon On',
        tag1: 'Soon',
        tag2: 'Soon',
        tag3: 'Soon',
        mockupStatus: 'Active Salary Cycle: October 2026',
        mockupDays: '16 Days to Payday',
        mockupLbl1: 'Safe Daily Spending',
        mockupLbl2: 'Family Savings Reserve',
        mockupLbl3: 'Shared Expenses & Balance',
        mockupChatTxt: 'In-App AI Assistant: Snap a picture of any receipt or chat naturally to record expenses instantly.',
        featuresTitle: 'Features Designed for Your Financial Peace of Mind',
        featuresSubtitle: 'Integrated digital solutions tailored to the real lifestyle and financial needs of modern Saudi households.',
        f1Title: 'In-App AI Chat & Instant Receipt OCR',
        f1Desc: 'Snap a photo of any printed or digital store receipt: AI extracts merchant name, date, and VAT total in seconds. Or simply chat naturally inside the app in Arabic, English, or Urdu to log any expense effortlessly.',
        f2Title: 'Saudi 27th Payday Cycle',
        f2Desc: 'Engineered around the Saudi government and corporate 27th payday schedule, automatically applying banking weekend shift rules (paid Thursday if 27th is Friday, Sunday if Saturday), with live burn-rate pacing.',
        f3Title: 'Smart Savings Reserve',
        f3Desc: 'Unassigned monthly income automatically sweeps into a dedicated family Savings Reserve, buffering unexpected budget overruns before payday without disrupting your overall financial plan.',
        f4Title: 'Fair Partner & Household Attribution',
        f4Desc: 'Seamlessly share household budgets using secure invite codes. 2D attribution tracks who actually paid vs. who benefited, computing clean net settlements without financial awkwardness.',
        f5Title: 'Category Library & Zero Data Deletion',
        f5Desc: 'Comprehensive taxonomy with pre-configured Saudi cost categories and custom tags. Categories are never deleted; simply toggle them active or inactive while preserving 100% of historical analytics.',
        f6Title: 'Bank-Grade Privacy & Security',
        f6Desc: 'Zero background SMS reading and zero intrusive device permissions. All data is protected with modern Row-Level Security (RLS) guaranteeing total household isolation.',
        tabPrivacyBtn: 'Privacy Policy',
        tabTermsBtn: 'Terms of Service',
        lp1: '1. Privacy Commitment',
        lp1Txt: 'At Budget Tracker, your financial data privacy is our absolute priority. The platform is designed with bank-grade isolation and encryption.',
        lp2: '2. Data Collected',
        lp2Txt: 'Data collection is strictly limited to information entered voluntarily: authentication email, expenses logged manually or via in-app chat, and receipt images uploaded for processing.',
        lp3: '3. Permissions & Transparency',
        lp3Txt: 'The application never requests SMS reading or background message interception permissions. Receipt scanning operates strictly on-demand.',
        lp4: '4. Zero Third-Party Selling & Deletion Rights',
        lp4Txt: 'We never sell or share your data with advertisers or commercial third parties. You may request full account and data deletion at any time by contacting: abedmowafaq@gmail.com.',
        lt1: '1. Agreement to Terms',
        lt1Txt: 'By accessing Budget Tracker, you agree to these Terms of Service and any ongoing updates.',
        lt2: '2. Personal Household Use',
        lt2Txt: 'The application provides guidance and budgeting analytics based on user input and does not represent official financial advisory services.',
        lt3: '3. Account Security',
        lt3Txt: 'Users remain responsible for maintaining the confidentiality of their login credentials and household invite codes.',
        lt4: '4. Developer Contact',
        lt4Txt: 'For technical inquiries, bug reports, or feature feedback, contact the developer directly at: abedmowafaq@gmail.com.',
        contactTitle: 'Have questions or want to join our beta program?',
        contactDesc: 'We are always glad to hear from you. Share your feedback, suggestions, or feature requests directly with the developer.',
        ftFeatures: 'Features',
        ftPrivacy: 'Privacy Policy',
        ftTerms: 'Terms of Service',
        ftContact: 'Contact Us',
        ftCopy: '© 2026 Budget Tracker • All rights reserved.'
      },
      ar: {
        dir: 'rtl',
        bodyClass: '',
        langBtnText: '🌐 English',
        navBrandSub: 'ميزانية الأسرة',
        heroPill: '✨ ميزانية الأسرة الذكية • متوافقة مع دورة الراتب السعودي',
        heroTitle1: 'تحكّم في ميزانية أسرتك بدقة',
        heroTitle2: 'ومتوافقة تماماً مع دورة الراتب يوم 27',
        heroDesc: 'صُمم خصيصاً للأسر في المملكة العربية السعودية. أتقن دورة الراتب يوم 27 مع الحساب التلقائي للعطلات، امسح الفواتير بالذكاء الاصطناعي، قسّم المصاريف بين الشركاء بعدالة، وابنِ احتياطي ادخار أسري تلقائياً دون أي تعقيد.',
        badgeAndroidSub: 'متوفر قريباً على',
        badgeAppleSub: 'متوفر قريباً على',
        badgeHuaweiSub: 'متوفر قريباً على',
        tag1: 'قريباً',
        tag2: 'قريباً',
        tag3: 'قريباً',
        mockupStatus: 'دورة راتب نشطة: أكتوبر 2026',
        mockupDays: 'متبقي 16 يوم على الراتب',
        mockupLbl1: 'معدل الصرف اليومي الآمن',
        mockupLbl2: 'احتياطي الادخار الأسري',
        mockupLbl3: 'المصاريف المشتركة والمستحقات',
        mockupChatTxt: 'المساعد الذكي داخل التطبيق: التقط صورة لأي فاتورة أو اكتب مشترياتك في الشات وسيتم تسجيلها تلقائياً.',
        featuresTitle: 'مميزات صُممت لراحتك المالية',
        featuresSubtitle: 'حلول رقمية متكاملة تواكب نمط حياة الأسرة السعودية واحتياجاتها الحقيقية',
        f1Title: 'مساعد ذكي ومسح فوري للفواتير',
        f1Desc: 'التقط صورة لأي فاتورة ورقية أو إلكترونية ليقوم محرك الذكاء الاصطناعي باستخراج اسم المتجر، التاريخ، وضريبة القيمة المضافة فورياً. كما يمكنك تسجيل أي مصروف مباشرة عبر شات التطبيق باللغة العربية، الإنجليزية، أو الأردية.',
        f2Title: 'دورة الراتب السعودي (يوم 27)',
        f2Desc: 'مبني وفق روزنامة صرف الرواتب يوم 27 مع تطبيق قواعد الصرف المصرفية السعودية تلقائياً (الصرف يوم الخميس إذا صادف الجمعة، ويوم الأحد إذا صادف السبت) مع متابعة وتيرة الصرف اليومية لمنع نفاد الميزانية قبل الراتب القادم.',
        f3Title: 'احتياطي الادخار الذكي',
        f3Desc: 'الفائض من الراتب الذي لم يُخصص لبنود معينة يتحول تلقائياً إلى صندوق احتياطي الادخار الأسري، ليكون بمثابة صمام أمان يغطي أي تجاوز غير متوقع في البنود الأساسية بكل مرونة وبدون إرباك لخطة الشهر.',
        f4Title: 'تقسيم عادل بين الشركاء والأسرة',
        f4Desc: 'شارك ميزانية المنزل مع شريكك برمز دعوة آمن ومباشر. نظام التوثيق ثنائي الأبعاد يرصد "من دفع المصروف" و"من استفاد منه" لحساب التسويات الصافية والديون المتبادلة بمنتهى الشفافية والراحة.',
        f5Title: 'مكتبة تصنيفات وحماية تامة للبيانات',
        f5Desc: 'تصنيفات متكاملة تشمل التموين، المطاعم، الفواتير، والأقساط بالإضافة لإمكانية إنشاء تصنيفات خاصة بأسرتك. لا يتم حذف أي تصنيف نهائياً بل يتم تحويله لمكتبة التصنيفات (غير نشط) لحفظ تاريخك المالي وسجلاتك بنسبة 100%.',
        f6Title: 'خصوصية مصرفية وثقة مطلقة',
        f6Desc: 'لا نطلب أي صلاحيات لقراءة الرسائل النصية في الخلفية ولا نصل لأي بيانات بنكية حساسة. جميع بيانات أسرتك معزولة بأعلى معايير الأمان وقواعد التشفير الحديثة (Row-Level Security).',
        tabPrivacyBtn: 'سياسة الخصوصية',
        tabTermsBtn: 'شروط الاستخدام',
        lp1: '1. الالتزام بالخصوصية وحماية البيانات',
        lp1Txt: 'نحن في Budget Tracker نولي خصوصية بياناتك المالية الأولوية القصوى. صُمم التطبيق ليعمل بأعلى معايير الأمان وعزل البيانات السحابية بين الأسر المشتركة.',
        lp2: '2. البيانات التي يتم جمعها',
        lp2Txt: 'يقتصر جمع البيانات على المعلومات التي يُدخلها المستخدم طواعية: عنوان البريد الإلكتروني للمصادقة، النفقات المسجلة يدوياً أو عبر الشات، والصور الملتقطة للفواتير لمعالجتها واستخراج الإجمالي.',
        lp3: '3. الصلاحيات وشفافية الاستخدام',
        lp3Txt: 'التطبيق لا يطلب أي صلاحيات اعتراض أو قراءة للرسائل النصية التلقائية. مسح الفواتير يتم محلياً وعند طلب المستخدم فقط عبر كاميرا أو معرض الصور.',
        lp4: '4. عدم مشاركة البيانات وحق الحذف',
        lp4Txt: 'لا نقوم ببيع أو مشاركة بياناتك مع أي طرف ثالث لأغراض تسويقية أو تجارية. يحق للمستخدم حذف حسابه وبياناته في أي وقت من خلال التواصل مع الدعم عبر: abedmowafaq@gmail.com.',
        lt1: '1. الموافقة على الشروط',
        lt1Txt: 'باستخدامك لتطبيق وموقع Budget Tracker، فإنك توافق على الالتزام بهذه الشروط والأحكام ومتابعة تحديثاتها الدورية.',
        lt2: '2. الاستخدام المالي والشخصي',
        lt2Txt: 'التطبيق مخصص لإدارة الميزانيات الشخصية والأسرية ويقدم مؤشرات وتوقعات استرشادية مبنية على البيانات المدخلة من قبل المستخدم دون أن يُعتبر ذلك مشورة استثمارية رسمية.',
        lt3: '3. أمن الحساب',
        lt3Txt: 'المستخدم مسؤول عن الحفاظ على سرية بيانات تسجيل الدخول ورموز دعوة الأسرة الممنوحة لأفراد عائلته.',
        lt4: '4. التواصل والدعم الفني',
        lt4Txt: 'لأي استفسارات أو ملاحظات، يُرجى مراسلة المطور مباشرة على البريد الإلكتروني: abedmowafaq@gmail.com.',
        contactTitle: 'هل لديك استفسار أو ترغب في الانضمام للنسخة التجريبية؟',
        contactDesc: 'يسعدنا دائماً تواصلكم وتلقي آرائكم ومقترحاتكم لتطوير التطبيق وخدمة الأسر بأفضل صورة ممكنة.',
        ftFeatures: 'المميزات',
        ftPrivacy: 'سياسة الخصوصية',
        ftTerms: 'شروط الاستخدام',
        ftContact: 'اتصل بنا',
        ftCopy: '© 2026 Budget Tracker • جميع الحقوق محفوظة.'
      }
    };

    function toggleLanguage() {
      currentLang = (currentLang === 'ar') ? 'en' : 'ar';
      applyLanguage(currentLang);
    }

    function applyLanguage(lang) {
      const data = translations[lang];
      document.documentElement.lang = lang;
      document.documentElement.dir = data.dir;
      document.body.className = data.bodyClass;

      document.getElementById('lang-btn').innerHTML = data.langBtnText;
      document.getElementById('nav-brand-sub').innerText = data.navBrandSub;
      document.getElementById('hero-pill').innerText = data.heroPill;
      document.getElementById('hero-title-1').innerText = data.heroTitle1;
      document.getElementById('hero-title-2').innerText = data.heroTitle2;
      document.getElementById('hero-desc').innerText = data.heroDesc;

      document.getElementById('badge-android-sub').innerText = data.badgeAndroidSub;
      document.getElementById('badge-apple-sub').innerText = data.badgeAppleSub;
      document.getElementById('badge-huawei-sub').innerText = data.badgeHuaweiSub;
      document.getElementById('tag-1').innerText = data.tag1;
      document.getElementById('tag-2').innerText = data.tag2;
      document.getElementById('tag-3').innerText = data.tag3;

      document.getElementById('mockup-status').innerText = data.mockupStatus;
      document.getElementById('mockup-days').innerText = data.mockupDays;
      document.getElementById('mockup-lbl-1').innerText = data.mockupLbl1;
      document.getElementById('mockup-lbl-2').innerText = data.mockupLbl2;
      document.getElementById('mockup-lbl-3').innerText = data.mockupLbl3;
      document.getElementById('mockup-chat-txt').innerText = data.mockupChatTxt;

      document.getElementById('features-title').innerText = data.featuresTitle;
      document.getElementById('features-subtitle').innerText = data.featuresSubtitle;

      document.getElementById('f1-title').innerText = data.f1Title;
      document.getElementById('f1-desc').innerText = data.f1Desc;
      document.getElementById('f2-title').innerText = data.f2Title;
      document.getElementById('f2-desc').innerText = data.f2Desc;
      document.getElementById('f3-title').innerText = data.f3Title;
      document.getElementById('f3-desc').innerText = data.f3Desc;
      document.getElementById('f4-title').innerText = data.f4Title;
      document.getElementById('f4-desc').innerText = data.f4Desc;
      document.getElementById('f5-title').innerText = data.f5Title;
      document.getElementById('f5-desc').innerText = data.f5Desc;
      document.getElementById('f6-title').innerText = data.f6Title;
      document.getElementById('f6-desc').innerText = data.f6Desc;

      document.getElementById('tab-privacy-btn').innerText = data.tabPrivacyBtn;
      document.getElementById('tab-terms-btn').innerText = data.tabTermsBtn;
      document.getElementById('lp-1').innerText = data.lp1;
      document.getElementById('lp-1-txt').innerText = data.lp1Txt;
      document.getElementById('lp-2').innerText = data.lp2;
      document.getElementById('lp-2-txt').innerText = data.lp2Txt;
      document.getElementById('lp-3').innerText = data.lp3;
      document.getElementById('lp-3-txt').innerText = data.lp3Txt;
      document.getElementById('lp-4').innerText = data.lp4;
      document.getElementById('lp-4-txt').innerText = data.lp4Txt;

      document.getElementById('lt-1').innerText = data.lt1;
      document.getElementById('lt-1-txt').innerText = data.lt1Txt;
      document.getElementById('lt-2').innerText = data.lt2;
      document.getElementById('lt-2-txt').innerText = data.lt2Txt;
      document.getElementById('lt-3').innerText = data.lt3;
      document.getElementById('lt-3-txt').innerText = data.lt3Txt;
      document.getElementById('lt-4').innerText = data.lt4;
      document.getElementById('lt-4-txt').innerText = data.lt4Txt;

      document.getElementById('contact-title').innerText = data.contactTitle;
      document.getElementById('contact-desc').innerText = data.contactDesc;
      document.getElementById('ft-features').innerText = data.ftFeatures;
      document.getElementById('ft-privacy').innerText = data.ftPrivacy;
      document.getElementById('ft-terms').innerText = data.ftTerms;
      document.getElementById('ft-contact').innerText = data.ftContact;
      document.getElementById('ft-copy').innerText = data.ftCopy;
    }

    function showLegalTab(tab) {
      const pTab = document.getElementById('privacy-content');
      const tTab = document.getElementById('terms-content');
      const pBtn = document.getElementById('tab-privacy-btn');
      const tBtn = document.getElementById('tab-terms-btn');

      if (tab === 'privacy') {
        pTab.style.display = 'block';
        tTab.style.display = 'none';
        pBtn.classList.add('active');
        tBtn.classList.remove('active');
      } else {
        pTab.style.display = 'none';
        tTab.style.display = 'block';
        pBtn.classList.remove('active');
        tBtn.classList.add('active');
      }
    }
  </script>
</body>
</html>
"""

def get_auth_confirmed_html() -> str:
    """HTML for email verification and OAuth callback confirmation."""
    return """<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • تم تأكيد الحساب بنجاح</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@600;700;800&family=Outfit:wght@600;700;800&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Cairo', -apple-system, sans-serif;
      background: #0B0F17;
      color: #C9D1D9;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      position: relative;
    }
    .card {
      background: #161B22;
      border: 1px solid rgba(0, 200, 150, 0.3);
      border-radius: 24px;
      padding: 48px 36px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6), 0 0 40px rgba(0, 200, 150, 0.15);
      position: relative;
      z-index: 1;
    }
    .icon-circle {
      width: 80px;
      height: 80px;
      border-radius: 50%;
      background: rgba(0, 200, 150, 0.15);
      border: 2px solid #00C896;
      color: #00C896;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 40px;
      margin-bottom: 24px;
      box-shadow: 0 0 25px rgba(0, 200, 150, 0.3);
    }
    h1 {
      color: #FFFFFF;
      font-size: 26px;
      font-weight: 800;
      margin-bottom: 8px;
    }
    .subtitle-en {
      color: #00C896;
      font-size: 16px;
      font-weight: 700;
      margin-bottom: 16px;
      font-family: 'Outfit', sans-serif;
      direction: ltr;
    }
    p {
      color: #94A3B8;
      font-size: 15px;
      line-height: 1.7;
      margin-bottom: 28px;
    }
    .badge {
      display: inline-block;
      background: rgba(88, 166, 255, 0.12);
      border: 1px solid rgba(88, 166, 255, 0.3);
      color: #58A6FF;
      font-size: 13px;
      font-weight: 700;
      padding: 6px 16px;
      border-radius: 20px;
      margin-bottom: 24px;
    }
    .action-btn {
      display: inline-block;
      width: 100%;
      background: linear-gradient(135deg, #00C896, #0284c7);
      color: #FFFFFF;
      font-size: 16px;
      font-weight: 800;
      padding: 14px 20px;
      border-radius: 14px;
      text-decoration: none;
      transition: all 0.25s ease;
      box-shadow: 0 8px 24px rgba(0, 200, 150, 0.3);
    }
    .action-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 12px 30px rgba(0, 200, 150, 0.45);
    }
    .contact-hint {
      margin-top: 24px;
      font-size: 13px;
      color: #64748B;
    }
    .contact-hint a {
      color: #94A3B8;
      text-decoration: none;
    }
    .contact-hint a:hover {
      color: #00C896;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon-circle">✓</div>
    <h1>تم تأكيد البريد الإلكتروني بنجاح</h1>
    <div class="subtitle-en">Account Verified Successfully</div>
    <div class="badge">Budget Tracker • ميزانية الأسرة</div>
    <p>تم تفعيل وتأكيد حسابك بنجاح. يمكنك الآن العودة إلى تطبيق الهاتف على جهازك وتسجيل الدخول لمتابعة ميزانيتك.</p>
    <a href="budgettracker://login" class="action-btn">فتح تطبيق الهاتف</a>
    <div class="contact-hint">
      للمساعدة والدعم الفني: <a href="mailto:abedmowafaq@gmail.com">abedmowafaq@gmail.com</a>
    </div>
  </div>
</body>
</html>
"""
