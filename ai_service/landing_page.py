"""
Landing page and auth confirmation HTML generator for Budget Tracker (budget.fmsco.com.sa).
Features:
- World-class obsidian fintech craft design inspired by Nate Herik UI aesthetics.
- Flexible salary cycle budgeting for any day of the month (no fixed 27th payday constraint).
- Comprehensive showcase of all app capabilities:
  * Flexible Payday Engine & Weekend Auto-Shift
  * Conversational Saudi AI Assistant
  * Two-Tier Taxonomy with Hybrid LLM Subcategories
  * ZATCA Phase 2 E-Invoice QR & Camera Scanner
  * Household & Partner Sharing with 2D Fair-Share Split
  * Family Dependents & Children Expense Attribution
  * BNPL & Installment Tracker (Tabby, Tamara, 0% Cards)
  * Recurring Bills & Auto-Cadence Detection
  * Smart Grocery Price Comparison & Basket Optimizer
  * "Can I Afford This?" Instant Purchase Simulator
  * Offline-First SQLite Engine with Idempotent Sync
  * Smart Savings Reserve & Monthly Tax-Ready PDF Reports
- Live Interactive App Stage with 4 interactive simulators.
- 12-pillar Bento Grid with micro-interactions.
- Full bilingual Arabic (RTL default) and English (LTR) instant toggle.
- Sleek store badges: Google Play, Apple App Store, Huawei AppGallery ("Coming Soon").
- Interactive FAQ accordion, Privacy Policy, Terms of Service, and Developer Contact (abedmowafaq@gmail.com).
"""

def get_landing_page_html() -> str:
    return """<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • ميزانية الأسرة الذكية | الابتكار المالي للأسر في السعودية</title>
  <meta name="description" content="تطبيق إدارة الميزانية ومصاريف الأسرة الذكي في السعودية. دورة راتب مرنة لأي يوم في الشهر، مسح فواتير ZATCA بالذكاء الاصطناعي، تقسيم المصاريف بين الشركاء وتتبع نفقات الأبناء.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=Outfit:wght@400;500;600;700;800;900&family=Plus+Jakarta+Sans:wght@500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-base: #06080D;
      --bg-card: rgba(15, 20, 28, 0.72);
      --bg-card-hover: rgba(22, 29, 41, 0.88);
      --bg-surface: #0E131C;
      --bg-pill: rgba(255, 255, 255, 0.05);
      --border-subtle: rgba(255, 255, 255, 0.08);
      --border-focus: rgba(0, 229, 153, 0.35);
      --border-specular: inset 0 1px 0 rgba(255, 255, 255, 0.12);
      --primary: #00E599;
      --primary-dim: rgba(0, 229, 153, 0.14);
      --primary-glow: rgba(0, 229, 153, 0.35);
      --cyan: #38BDF8;
      --cyan-dim: rgba(56, 189, 248, 0.14);
      --amber: #F59E0B;
      --amber-dim: rgba(245, 158, 11, 0.14);
      --purple: #A855F7;
      --purple-dim: rgba(168, 85, 247, 0.14);
      --rose: #F43F5E;
      --text-pure: #FFFFFF;
      --text-main: #F1F5F9;
      --text-muted: #94A3B8;
      --text-dim: #64748B;
      --font-ar: 'Cairo', -apple-system, sans-serif;
      --font-en: 'Outfit', 'Plus Jakarta Sans', -apple-system, sans-serif;
      --radius-sm: 12px;
      --radius-md: 18px;
      --radius-lg: 26px;
      --radius-xl: 34px;
      --container-max: 1240px;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
    }

    html {
      scroll-behavior: smooth;
    }

    body {
      background-color: var(--bg-base);
      color: var(--text-main);
      font-family: var(--font-ar);
      min-height: 100vh;
      overflow-x: hidden;
      line-height: 1.65;
      position: relative;
    }

    body.lang-en {
      font-family: var(--font-en);
      direction: ltr;
    }

    /* Ambient Matrix & Spotlights */
    .bg-matrix {
      position: fixed;
      inset: 0;
      background-image: radial-gradient(rgba(255, 255, 255, 0.07) 1px, transparent 1px);
      background-size: 28px 28px;
      opacity: 0.55;
      pointer-events: none;
      z-index: 0;
      mask-image: radial-gradient(circle at 50% 30%, black 40%, transparent 85%);
      -webkit-mask-image: radial-gradient(circle at 50% 30%, black 40%, transparent 85%);
    }

    .spotlight-1 {
      position: fixed;
      top: -150px;
      right: 10%;
      width: 650px;
      height: 650px;
      background: radial-gradient(circle, rgba(0, 229, 153, 0.12) 0%, rgba(0, 229, 153, 0.02) 50%, transparent 70%);
      border-radius: 50%;
      pointer-events: none;
      z-index: 0;
      filter: blur(50px);
    }

    .spotlight-2 {
      position: fixed;
      top: 40vh;
      left: -150px;
      width: 700px;
      height: 700px;
      background: radial-gradient(circle, rgba(56, 189, 248, 0.10) 0%, rgba(56, 189, 248, 0.01) 50%, transparent 70%);
      border-radius: 50%;
      pointer-events: none;
      z-index: 0;
      filter: blur(60px);
    }

    .spotlight-3 {
      position: fixed;
      bottom: -100px;
      right: -100px;
      width: 600px;
      height: 600px;
      background: radial-gradient(circle, rgba(168, 85, 247, 0.08) 0%, transparent 70%);
      border-radius: 50%;
      pointer-events: none;
      z-index: 0;
      filter: blur(50px);
    }

    .container {
      max-width: var(--container-max);
      margin: 0 auto;
      padding: 0 28px;
      position: relative;
      z-index: 1;
    }

    /* Navbar */
    header {
      position: sticky;
      top: 0;
      z-index: 100;
      backdrop-filter: blur(20px) saturate(180%);
      -webkit-backdrop-filter: blur(20px) saturate(180%);
      background: rgba(6, 8, 13, 0.78);
      border-bottom: 1px solid var(--border-subtle);
      transition: all 0.3s ease;
    }

    .nav-inner {
      display: flex;
      justify-content: space-between;
      align-items: center;
      height: 80px;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 14px;
      text-decoration: none;
      color: inherit;
    }

    .brand-mark {
      width: 44px;
      height: 44px;
      border-radius: 14px;
      background: linear-gradient(135deg, #00E599 0%, #0284C7 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      box-shadow: 0 0 24px rgba(0, 229, 153, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.3);
      position: relative;
    }

    .brand-mark::after {
      content: '';
      position: absolute;
      inset: -2px;
      border-radius: 16px;
      background: linear-gradient(135deg, rgba(0, 229, 153, 0.6), transparent);
      z-index: -1;
      opacity: 0.5;
    }

    .brand-text h1 {
      font-size: 21px;
      font-weight: 800;
      letter-spacing: -0.02em;
      color: var(--text-pure);
      line-height: 1.2;
    }

    .brand-text span {
      font-size: 11px;
      font-weight: 700;
      color: var(--primary);
      text-transform: uppercase;
      letter-spacing: 0.08em;
      display: block;
    }

    .nav-links {
      display: flex;
      align-items: center;
      gap: 28px;
      list-style: none;
    }

    .nav-link {
      color: var(--text-muted);
      text-decoration: none;
      font-size: 14px;
      font-weight: 600;
      transition: all 0.2s ease;
      position: relative;
    }

    .nav-link:hover {
      color: var(--text-pure);
    }

    .nav-actions {
      display: flex;
      align-items: center;
      gap: 16px;
    }

    .lang-btn {
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--border-subtle);
      color: var(--text-main);
      padding: 9px 18px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      transition: all 0.25s ease;
      box-shadow: var(--border-specular);
    }

    .lang-btn:hover {
      background: rgba(0, 229, 153, 0.1);
      border-color: var(--primary);
      color: var(--primary);
      transform: translateY(-1px);
    }

    /* Hero Section */
    .hero {
      padding: 90px 0 60px;
      text-align: center;
      position: relative;
    }

    .hero-badge-pill {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      padding: 7px 18px;
      background: rgba(0, 229, 153, 0.08);
      border: 1px solid rgba(0, 229, 153, 0.25);
      border-radius: 999px;
      color: var(--primary);
      font-size: 13px;
      font-weight: 700;
      margin-bottom: 28px;
      box-shadow: 0 0 25px rgba(0, 229, 153, 0.15), var(--border-specular);
      backdrop-filter: blur(10px);
    }

    .ping-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--primary);
      position: relative;
    }

    .ping-dot::after {
      content: '';
      position: absolute;
      inset: -4px;
      border-radius: 50%;
      background: var(--primary);
      opacity: 0.6;
      animation: ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;
    }

    @keyframes ping {
      0% { transform: scale(1); opacity: 0.8; }
      100% { transform: scale(2.6); opacity: 0; }
    }

    .hero-heading {
      font-size: clamp(34px, 5.5vw, 68px);
      font-weight: 900;
      line-height: 1.15;
      letter-spacing: -0.03em;
      color: var(--text-pure);
      max-width: 980px;
      margin: 0 auto 24px;
    }

    .hero-heading .gradient-text {
      background: linear-gradient(135deg, #00E599 0%, #38BDF8 60%, #A855F7 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      display: inline-block;
    }

    .hero-desc {
      font-size: clamp(16px, 2.1vw, 20px);
      color: var(--text-muted);
      max-width: 820px;
      margin: 0 auto 40px;
      line-height: 1.8;
      font-weight: 400;
    }

    /* Store Badges */
    .store-cta-group {
      display: flex;
      justify-content: center;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 60px;
    }

    .store-badge-card {
      display: flex;
      align-items: center;
      gap: 14px;
      background: rgba(18, 24, 35, 0.7);
      border: 1px solid var(--border-subtle);
      box-shadow: var(--border-specular), 0 12px 28px rgba(0, 0, 0, 0.4);
      padding: 12px 22px;
      border-radius: var(--radius-md);
      min-width: 215px;
      text-decoration: none;
      color: inherit;
      position: relative;
      overflow: hidden;
      transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      backdrop-filter: blur(14px);
    }

    .store-badge-card::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 1px;
      background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.2), transparent);
    }

    .store-badge-card:hover {
      transform: translateY(-3px);
      border-color: rgba(255, 255, 255, 0.22);
      box-shadow: var(--border-specular), 0 16px 36px rgba(0, 0, 0, 0.6), 0 0 20px rgba(0, 229, 153, 0.15);
    }

    .store-icon {
      font-size: 28px;
      width: 40px;
      height: 40px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(255, 255, 255, 0.05);
      border-radius: 12px;
      flex-shrink: 0;
    }

    .store-texts {
      text-align: start;
    }

    .store-sub {
      font-size: 11px;
      color: var(--text-dim);
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .store-main {
      font-size: 15px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .badge-chip {
      background: rgba(245, 158, 11, 0.15);
      border: 1px solid rgba(245, 158, 11, 0.35);
      color: var(--amber);
      font-size: 10px;
      font-weight: 800;
      padding: 2px 7px;
      border-radius: 6px;
    }

    /* Live Interactive App Stage */
    .interactive-stage {
      max-width: 960px;
      margin: 0 auto 100px;
      background: linear-gradient(180deg, rgba(20, 27, 40, 0.75) 0%, rgba(10, 14, 22, 0.95) 100%);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: var(--radius-xl);
      box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7), 0 0 50px rgba(0, 229, 153, 0.12), var(--border-specular);
      overflow: hidden;
      position: relative;
    }

    .stage-glass-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 18px 28px;
      background: rgba(12, 17, 26, 0.85);
      border-bottom: 1px solid var(--border-subtle);
    }

    .stage-window-controls {
      display: flex;
      gap: 8px;
    }

    .stage-dot {
      width: 11px;
      height: 11px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.12);
    }
    .stage-dot.close { background: #FF5F56; }
    .stage-dot.min { background: #FFBD2E; }
    .stage-dot.max { background: #27C93F; }

    .stage-tabs {
      display: flex;
      gap: 8px;
      background: rgba(255, 255, 255, 0.04);
      padding: 4px;
      border-radius: 12px;
      border: 1px solid var(--border-subtle);
    }

    .stage-tab-btn {
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-family: inherit;
      font-size: 13px;
      font-weight: 700;
      padding: 6px 14px;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s ease;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .stage-tab-btn.active {
      background: rgba(0, 229, 153, 0.16);
      color: var(--primary);
      box-shadow: 0 2px 10px rgba(0, 229, 153, 0.15);
    }

    .stage-tab-btn:hover:not(.active) {
      color: var(--text-pure);
      background: rgba(255, 255, 255, 0.05);
    }

    .stage-viewport {
      padding: 34px 30px;
    }

    /* Tab Content 1: Payday Engine Simulator */
    .tab-panel {
      display: none;
    }
    .tab-panel.active {
      display: block;
      animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    }

    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .simulator-box {
      background: rgba(14, 19, 28, 0.8);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 26px;
      margin-bottom: 24px;
    }

    .sim-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;
      flex-wrap: wrap;
      gap: 12px;
    }

    .sim-title {
      font-size: 16px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .sim-slider-wrap {
      margin-bottom: 24px;
    }

    .slider-labels {
      display: flex;
      justify-content: space-between;
      font-size: 13px;
      color: var(--text-muted);
      margin-bottom: 10px;
    }

    .slider-labels strong {
      color: var(--primary);
      font-size: 15px;
    }

    .custom-range {
      width: 100%;
      height: 8px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.1);
      outline: none;
      -webkit-appearance: none;
      cursor: pointer;
    }

    .custom-range::-webkit-slider-thumb {
      -webkit-appearance: none;
      appearance: none;
      width: 24px;
      height: 24px;
      border-radius: 50%;
      background: var(--primary);
      box-shadow: 0 0 16px var(--primary);
      cursor: grab;
      border: 2px solid #FFFFFF;
      transition: transform 0.1s ease;
    }

    .custom-range::-webkit-slider-thumb:hover {
      transform: scale(1.15);
    }

    .sim-stat-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 16px;
    }

    .stat-pill-card {
      background: rgba(8, 12, 19, 0.9);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      padding: 18px;
      position: relative;
      overflow: hidden;
      box-shadow: var(--border-specular);
    }

    .stat-pill-card::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      width: 4px;
      height: 100%;
    }
    .stat-pill-card.teal::before { background: var(--primary); }
    .stat-pill-card.blue::before { background: var(--cyan); }
    .stat-pill-card.gold::before { background: var(--amber); }

    .stat-lbl {
      font-size: 12px;
      color: var(--text-muted);
      margin-bottom: 6px;
      font-weight: 600;
    }

    .stat-val {
      font-size: 23px;
      font-weight: 800;
      color: var(--text-pure);
      line-height: 1.2;
    }

    .stat-sub {
      font-size: 11px;
      color: var(--text-dim);
      margin-top: 6px;
    }

    /* Tab Content 2: AI Chat Simulator */
    .ai-chat-preview {
      display: flex;
      flex-direction: column;
      gap: 14px;
      background: rgba(14, 19, 28, 0.8);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 24px;
    }

    .chat-bubble-user {
      align-self: flex-start;
      background: rgba(56, 189, 248, 0.12);
      border: 1px solid rgba(56, 189, 248, 0.3);
      padding: 12px 18px;
      border-radius: 18px 18px 4px 18px;
      font-size: 14px;
      color: #E0F2FE;
      max-width: 80%;
    }

    body.lang-en .chat-bubble-user {
      border-radius: 18px 18px 18px 4px;
    }

    .chat-bubble-ai {
      align-self: flex-end;
      background: rgba(0, 229, 153, 0.08);
      border: 1px solid rgba(0, 229, 153, 0.3);
      border-radius: 18px 18px 18px 4px;
      padding: 18px;
      width: 90%;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }

    body.lang-en .chat-bubble-ai {
      border-radius: 18px 18px 4px 18px;
    }

    .ai-card-parsed {
      background: rgba(8, 12, 19, 0.95);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 14px;
      padding: 16px;
      margin-top: 10px;
    }

    .ai-card-title {
      font-size: 15px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      justify-content: space-between;
      margin-bottom: 12px;
    }

    .badge-tag {
      font-size: 11px;
      font-weight: 700;
      padding: 3px 8px;
      border-radius: 6px;
      display: inline-flex;
      align-items: center;
      gap: 4px;
    }

    .badge-tag.cat { background: rgba(168, 85, 247, 0.15); color: #C084FC; border: 1px solid rgba(168, 85, 247, 0.3); }
    .badge-tag.sub { background: rgba(56, 189, 248, 0.15); color: #7DD3FC; border: 1px solid rgba(56, 189, 248, 0.3); }
    .badge-tag.paid { background: rgba(0, 229, 153, 0.15); color: #34D399; border: 1px solid rgba(0, 229, 153, 0.3); }
    .badge-tag.for { background: rgba(245, 158, 11, 0.15); color: #FBBF24; border: 1px solid rgba(245, 158, 11, 0.3); }

    .ai-chips-row {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 8px;
    }

    /* Tab Content 3: ZATCA Scanner Viewfinder */
    .zatca-viewfinder {
      background: radial-gradient(circle at center, rgba(14, 25, 38, 0.8) 0%, rgba(8, 12, 18, 0.95) 100%);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 30px;
      display: flex;
      flex-direction: column;
      align-items: center;
      position: relative;
      overflow: hidden;
    }

    .scan-laser-beam {
      position: absolute;
      top: 0;
      left: 10%;
      right: 10%;
      height: 2px;
      background: linear-gradient(90deg, transparent, #00E599, #38BDF8, transparent);
      box-shadow: 0 0 16px #00E599, 0 0 30px #38BDF8;
      animation: scanLaser 3s ease-in-out infinite alternate;
    }

    @keyframes scanLaser {
      0% { top: 15%; opacity: 0.3; }
      50% { opacity: 1; }
      100% { top: 85%; opacity: 0.3; }
    }

    .zatca-preview-grid {
      display: grid;
      grid-template-columns: 140px 1fr;
      gap: 24px;
      align-items: center;
      width: 100%;
      max-width: 620px;
      background: rgba(10, 14, 22, 0.85);
      border: 1px solid rgba(0, 229, 153, 0.3);
      border-radius: 18px;
      padding: 22px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
    }

    .qr-mock {
      width: 130px;
      height: 130px;
      background: #FFFFFF;
      border-radius: 12px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 8px;
      position: relative;
    }

    .qr-svg {
      width: 100%;
      height: 100%;
    }

    .zatca-details h5 {
      font-size: 16px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 6px;
    }

    .zatca-row {
      display: flex;
      justify-content: space-between;
      font-size: 13px;
      color: var(--text-muted);
      padding: 4px 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    }

    .zatca-row strong {
      color: var(--text-pure);
    }

    /* Tab Content 4: Partner & Dependents Settlement */
    .partner-sim-box {
      background: rgba(14, 19, 28, 0.8);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 26px;
    }

    .split-ratio-bar {
      height: 14px;
      background: rgba(255, 255, 255, 0.08);
      border-radius: 999px;
      display: flex;
      overflow: hidden;
      margin: 16px 0 24px;
    }

    .split-bar-you {
      background: linear-gradient(90deg, #00E599, #059669);
      transition: width 0.3s ease;
    }

    .split-bar-partner {
      background: linear-gradient(90deg, #38BDF8, #0284C7);
      transition: width 0.3s ease;
    }

    .children-chips-bar {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 16px;
    }

    .child-chip {
      background: rgba(168, 85, 247, 0.12);
      border: 1px solid rgba(168, 85, 247, 0.3);
      padding: 6px 14px;
      border-radius: 999px;
      font-size: 13px;
      color: #E9D5FF;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }

    /* Bento Grid Features Section */
    .section-headline {
      text-align: center;
      margin-bottom: 60px;
    }

    .section-eyebrow {
      font-size: 12px;
      font-weight: 800;
      color: var(--primary);
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 12px;
      display: block;
    }

    .section-h2 {
      font-size: clamp(28px, 4vw, 44px);
      font-weight: 900;
      color: var(--text-pure);
      line-height: 1.25;
      letter-spacing: -0.02em;
      margin-bottom: 16px;
    }

    .section-sub {
      font-size: 17px;
      color: var(--text-muted);
      max-width: 680px;
      margin: 0 auto;
    }

    .bento-grid {
      display: grid;
      grid-template-columns: repeat(12, 1fr);
      gap: 24px;
      margin-bottom: 120px;
    }

    .bento-card {
      background: var(--bg-card);
      border: 1px solid var(--border-subtle);
      box-shadow: var(--border-specular), 0 20px 40px rgba(0, 0, 0, 0.35);
      border-radius: var(--radius-lg);
      padding: 34px 28px;
      position: relative;
      overflow: hidden;
      transition: all 0.35s cubic-bezier(0.16, 1, 0.3, 1);
      backdrop-filter: blur(16px);
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }

    .bento-card::before {
      content: '';
      position: absolute;
      inset: 0;
      background: radial-gradient(circle at top right, rgba(255, 255, 255, 0.04), transparent 60%);
      pointer-events: none;
    }

    .bento-card:hover {
      background: var(--bg-card-hover);
      transform: translateY(-5px);
      border-color: rgba(255, 255, 255, 0.18);
      box-shadow: var(--border-specular), 0 25px 60px rgba(0, 0, 0, 0.5), 0 0 30px rgba(0, 229, 153, 0.1);
    }

    .bento-span-8 { grid-column: span 8; }
    .bento-span-4 { grid-column: span 4; }
    .bento-span-6 { grid-column: span 6; }
    .bento-span-12 { grid-column: span 12; }

    .bento-icon {
      width: 52px;
      height: 52px;
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 26px;
      margin-bottom: 22px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--border-subtle);
    }

    .bento-icon.teal { background: var(--primary-dim); border-color: rgba(0, 229, 153, 0.3); color: var(--primary); }
    .bento-icon.blue { background: var(--cyan-dim); border-color: rgba(56, 189, 248, 0.3); color: var(--cyan); }
    .bento-icon.amber { background: var(--amber-dim); border-color: rgba(245, 158, 11, 0.3); color: var(--amber); }
    .bento-icon.purple { background: var(--purple-dim); border-color: rgba(168, 85, 247, 0.3); color: var(--purple); }

    .bento-title {
      font-size: 20px;
      font-weight: 800;
      color: var(--text-pure);
      margin-bottom: 12px;
      line-height: 1.3;
    }

    .bento-desc {
      font-size: 15px;
      color: var(--text-muted);
      line-height: 1.75;
      margin-bottom: 20px;
    }

    .bento-tag-row {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    .pill-micro {
      font-size: 11px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--border-subtle);
      color: var(--text-muted);
    }

    /* Comparison / Highlights Table */
    .matrix-section {
      background: linear-gradient(180deg, rgba(16, 22, 33, 0.6) 0%, rgba(9, 12, 18, 0.9) 100%);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-xl);
      padding: 48px 40px;
      margin-bottom: 120px;
      box-shadow: var(--border-specular);
    }

    .matrix-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 30px;
      margin-top: 36px;
    }

    .matrix-item {
      display: flex;
      gap: 16px;
      align-items: flex-start;
    }

    .matrix-check {
      width: 28px;
      height: 28px;
      border-radius: 8px;
      background: rgba(0, 229, 153, 0.15);
      border: 1px solid var(--primary);
      color: var(--primary);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      font-weight: 900;
      flex-shrink: 0;
      margin-top: 2px;
    }

    .matrix-text h4 {
      font-size: 16px;
      font-weight: 800;
      color: var(--text-pure);
      margin-bottom: 4px;
    }

    .matrix-text p {
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.6;
    }

    /* FAQ Accordion */
    .faq-section {
      max-width: 860px;
      margin: 0 auto 120px;
    }

    .faq-item {
      background: var(--bg-card);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-md);
      margin-bottom: 14px;
      box-shadow: var(--border-specular);
      overflow: hidden;
      transition: all 0.25s ease;
    }

    .faq-item.active {
      border-color: rgba(0, 229, 153, 0.3);
      background: rgba(18, 25, 36, 0.85);
    }

    .faq-btn {
      width: 100%;
      text-align: start;
      background: none;
      border: none;
      color: var(--text-pure);
      font-family: inherit;
      font-size: 16px;
      font-weight: 700;
      padding: 22px 26px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      cursor: pointer;
    }

    .faq-toggle-icon {
      font-size: 18px;
      color: var(--primary);
      transition: transform 0.25s ease;
    }

    .faq-item.active .faq-toggle-icon {
      transform: rotate(45deg);
    }

    .faq-answer {
      display: none;
      padding: 0 26px 22px;
      color: var(--text-muted);
      font-size: 15px;
      line-height: 1.8;
      border-top: 1px solid rgba(255, 255, 255, 0.04);
      padding-top: 16px;
    }

    .faq-item.active .faq-answer {
      display: block;
    }

    /* Legal Section */
    .legal-container {
      background: var(--bg-card);
      border: 1px solid var(--border-subtle);
      border-radius: var(--radius-lg);
      padding: 40px 36px;
      margin-bottom: 100px;
      box-shadow: var(--border-specular);
    }

    .legal-tabs-row {
      display: flex;
      gap: 12px;
      border-bottom: 1px solid var(--border-subtle);
      padding-bottom: 16px;
      margin-bottom: 24px;
    }

    .legal-nav-btn {
      background: none;
      border: none;
      color: var(--text-muted);
      font-family: inherit;
      font-size: 15px;
      font-weight: 700;
      padding: 8px 18px;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .legal-nav-btn.active {
      color: var(--primary);
      background: rgba(0, 229, 153, 0.1);
    }

    .legal-pane {
      max-height: 280px;
      overflow-y: auto;
      padding-right: 14px;
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.8;
    }

    .legal-pane h4 {
      color: var(--text-pure);
      margin: 16px 0 8px;
      font-size: 15px;
    }

    /* Contact Banner */
    .contact-card {
      background: radial-gradient(circle at top right, rgba(0, 229, 153, 0.16) 0%, rgba(56, 189, 248, 0.05) 50%, transparent 80%), #0E1420;
      border: 1px solid rgba(0, 229, 153, 0.35);
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.6), 0 0 50px rgba(0, 229, 153, 0.15), var(--border-specular);
      border-radius: var(--radius-xl);
      padding: 56px 36px;
      text-align: center;
      margin-bottom: 100px;
      position: relative;
      overflow: hidden;
    }

    .contact-title {
      font-size: clamp(24px, 3.5vw, 36px);
      font-weight: 900;
      color: var(--text-pure);
      margin-bottom: 14px;
    }

    .contact-desc {
      color: var(--text-muted);
      font-size: 16px;
      max-width: 640px;
      margin: 0 auto 32px;
      line-height: 1.7;
    }

    .email-capsule {
      display: inline-flex;
      align-items: center;
      gap: 12px;
      background: rgba(6, 9, 14, 0.95);
      border: 1px solid rgba(255, 255, 255, 0.15);
      padding: 14px 30px;
      border-radius: 999px;
      color: var(--text-pure);
      font-size: 16px;
      font-weight: 800;
      text-decoration: none;
      transition: all 0.3s ease;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.5);
    }

    .email-capsule:hover {
      border-color: var(--primary);
      background: rgba(0, 229, 153, 0.1);
      color: var(--primary);
      transform: translateY(-2px);
      box-shadow: 0 15px 35px rgba(0, 229, 153, 0.25);
    }

    /* Footer */
    footer {
      border-top: 1px solid var(--border-subtle);
      padding: 48px 0 60px;
      text-align: center;
      color: var(--text-dim);
      font-size: 14px;
    }

    .footer-links-row {
      display: flex;
      justify-content: center;
      gap: 28px;
      margin-bottom: 18px;
      flex-wrap: wrap;
    }

    .footer-links-row a {
      color: var(--text-muted);
      text-decoration: none;
      font-weight: 600;
      transition: color 0.2s ease;
    }

    .footer-links-row a:hover {
      color: var(--primary);
    }

    /* Responsive */
    @media (max-width: 992px) {
      .bento-span-8, .bento-span-4, .bento-span-6 { grid-column: span 12; }
      .zatca-preview-grid { grid-template-columns: 1fr; justify-items: center; text-align: center; }
      .nav-links { display: none; }
    }

    @media (max-width: 768px) {
      .hero { padding: 50px 0 30px; }
      .stage-glass-bar { flex-direction: column; gap: 14px; }
      .stage-tabs { width: 100%; overflow-x: auto; justify-content: flex-start; }
      .store-badge-card { width: 100%; justify-content: center; }
      .matrix-section { padding: 32px 20px; }
      .contact-card { padding: 36px 20px; }
    }
  </style>
</head>
<body id="page-body">

  <div class="bg-matrix"></div>
  <div class="spotlight-1"></div>
  <div class="spotlight-2"></div>
  <div class="spotlight-3"></div>

  <!-- Header -->
  <header>
    <div class="container nav-inner">
      <a href="/" class="brand">
        <div class="brand-mark">💎</div>
        <div class="brand-text">
          <h1>Budget Tracker</h1>
          <span id="nav-brand-sub">ميزانية الأسرة الذكية</span>
        </div>
      </a>

      <ul class="nav-links">
        <li><a href="#simulator" class="nav-link" id="nav-sim">المحاكي التفاعلي</a></li>
        <li><a href="#features" class="nav-link" id="nav-feat">المميزات</a></li>
        <li><a href="#comparison" class="nav-link" id="nav-comp">المقارنة</a></li>
        <li><a href="#faq" class="nav-link" id="nav-faq">الأسئلة الشائعة</a></li>
        <li><a href="#contact" class="nav-link" id="nav-contact">الدعم الفني</a></li>
      </ul>

      <div class="nav-actions">
        <button id="lang-btn" class="lang-btn" onclick="toggleLanguage()">
          🌐 <span>English</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Hero Section -->
  <main class="container">
    <section class="hero">
      <div class="hero-badge-pill" id="hero-badge">
        <span class="ping-dot"></span>
        <span id="hero-badge-text">الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية</span>
      </div>

      <h2 class="hero-heading">
        <span id="hero-h1">تحكّم مطلق في ميزانية أسرتك</span><br>
        <span class="gradient-text" id="hero-h2">مع أي يوم راتب تختاره وبدقة الذكاء الاصطناعي</span>
      </h2>

      <p class="hero-desc" id="hero-desc">
        صُمم خصيصاً ليواكب واقع الأسر في السعودية. حدد يوم نزول راتبك بكل حرية (اليوم 1، 15، 25، 27 أو أي تاريخ يناسبك)، مع حساب قواعد الصرف المصرفية للعطلات تلقائياً، ومسح فواتير ZATCA، وتوزيع المصاريف بعدالة بين الشركاء والأبناء دون أي عناء.
      </p>

      <!-- Store Badges Coming Soon -->
      <div class="store-cta-group">
        <!-- Google Play -->
        <div class="store-badge-card">
          <div class="store-icon">🤖</div>
          <div class="store-texts">
            <div class="store-sub" id="st-google-sub">متوفر قريباً على</div>
            <div class="store-main">
              Google Play <span class="badge-chip" id="chip-1">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Apple App Store -->
        <div class="store-badge-card">
          <div class="store-icon">🍎</div>
          <div class="store-texts">
            <div class="store-sub" id="st-apple-sub">متوفر قريباً على</div>
            <div class="store-main">
              App Store <span class="badge-chip" id="chip-2">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Huawei AppGallery -->
        <div class="store-badge-card">
          <div class="store-icon">🛍️</div>
          <div class="store-texts">
            <div class="store-sub" id="st-huawei-sub">متوفر قريباً على</div>
            <div class="store-main">
              AppGallery <span class="badge-chip" id="chip-3">قريباً</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Live Interactive App Stage -->
      <div class="interactive-stage" id="simulator">
        <div class="stage-glass-bar">
          <div class="stage-window-controls">
            <div class="stage-dot close"></div>
            <div class="stage-dot min"></div>
            <div class="stage-dot max"></div>
          </div>

          <div class="stage-tabs">
            <button class="stage-tab-btn active" id="tab-sim-btn-1" onclick="switchSimTab('payday')">
              📅 <span id="tab-t1">محاكي دورة الراتب</span>
            </button>
            <button class="stage-tab-btn" id="tab-sim-btn-2" onclick="switchSimTab('ai')">
              ✨ <span id="tab-t2">مساعد الشات الذكي</span>
            </button>
            <button class="stage-tab-btn" id="tab-sim-btn-3" onclick="switchSimTab('zatca')">
              🧾 <span id="tab-t3">ماسح فواتير ZATCA</span>
            </button>
            <button class="stage-tab-btn" id="tab-sim-btn-4" onclick="switchSimTab('partner')">
              👥 <span id="tab-t4">تقسيم الشركاء والأبناء</span>
            </button>
          </div>
        </div>

        <div class="stage-viewport">
          <!-- Tab 1: Payday Engine Simulator -->
          <div id="sim-panel-payday" class="tab-panel active">
            <div class="simulator-box">
              <div class="sim-header">
                <div class="sim-title">
                  <span>⚙️</span>
                  <span id="sim-title-txt">اختر يوم نزول راتبك الشهري (مرن 100% لأي قطاع)</span>
                </div>
                <div id="sim-shift-badge" class="badge-chip" style="font-size: 12px; padding: 4px 10px;">
                  ✓ نظام الصرف التلقائي للعطلات نشط
                </div>
              </div>

              <div class="sim-slider-wrap">
                <div class="slider-labels">
                  <span id="slider-min-lbl">اليوم 1 في الشهر</span>
                  <span><span id="slider-curr-lbl">يوم الراتب المحدد:</span> <strong id="slider-curr-val">27</strong></span>
                  <span id="slider-max-lbl">اليوم 31 في الشهر</span>
                </div>
                <input type="range" min="1" max="31" value="27" class="custom-range" id="payday-range" oninput="updatePaydaySim(this.value)">
              </div>

              <div class="sim-stat-grid">
                <div class="stat-pill-card teal">
                  <div class="stat-lbl" id="sim-lbl-days">الأيام المتبقية في الدورة</div>
                  <div class="stat-val" id="sim-val-days">16 <small style="font-size: 13px;">يوم</small></div>
                  <div class="stat-sub" id="sim-sub-days">دورة نشطة متوازنة</div>
                </div>

                <div class="stat-pill-card blue">
                  <div class="stat-lbl" id="sim-lbl-safe">معدل الصرف اليومي الآمن</div>
                  <div class="stat-val" id="sim-val-safe">345 <small style="font-size: 13px;">ر.س / يوم</small></div>
                  <div class="stat-sub" id="sim-sub-safe">يحميك من نفاد الميزانية قبل الراتب</div>
                </div>

                <div class="stat-pill-card gold">
                  <div class="stat-lbl" id="sim-lbl-reserve">احتياطي الادخار التلقائي</div>
                  <div class="stat-val" id="sim-val-reserve">4,500 <small style="font-size: 13px;">ر.س</small></div>
                  <div class="stat-sub" id="sim-sub-reserve">فائض غير مخصص يُحفظ للطوارئ</div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 2: AI Chat Simulator -->
          <div id="sim-panel-ai" class="tab-panel">
            <div class="ai-chat-preview">
              <div class="chat-bubble-user" id="chat-u-msg">
                "عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة"
              </div>
              <div class="chat-bubble-ai">
                <div style="font-size: 12px; color: var(--primary); font-weight: 700; margin-bottom: 6px;">
                  🤖 <span id="chat-ai-header">تم استخراج المصروف بالذكاء الاصطناعي بدقة</span>
                </div>
                <div class="ai-card-parsed">
                  <div class="ai-card-title">
                    <span>مطعم البيك (وجبة عائلية)</span>
                    <span style="color: var(--primary);">68.00 ر.س</span>
                  </div>
                  <div class="ai-chips-row">
                    <span class="badge-tag cat">🍔 المطاعم والتغذية</span>
                    <span class="badge-tag sub">🍟 وجبات سريعة</span>
                    <span class="badge-tag paid">👤 المدفوع بواسطة: أنا</span>
                    <span class="badge-tag for">👨‍👩‍👧 المستفيد: الأسرة</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 3: ZATCA Scanner Viewfinder -->
          <div id="sim-panel-zatca" class="tab-panel">
            <div class="zatca-viewfinder">
              <div class="scan-laser-beam"></div>
              <div class="zatca-preview-grid">
                <div class="qr-mock">
                  <svg class="qr-svg" viewBox="0 0 100 100">
                    <rect width="100" height="100" fill="#fff"/>
                    <rect x="10" y="10" width="24" height="24" fill="#000"/>
                    <rect x="14" y="14" width="16" height="16" fill="#fff"/>
                    <rect x="18" y="18" width="8" height="8" fill="#000"/>
                    <rect x="66" y="10" width="24" height="24" fill="#000"/>
                    <rect x="70" y="14" width="16" height="16" fill="#fff"/>
                    <rect x="74" y="18" width="8" height="8" fill="#000"/>
                    <rect x="10" y="66" width="24" height="24" fill="#000"/>
                    <rect x="14" y="70" width="16" height="16" fill="#fff"/>
                    <rect x="18" y="74" width="8" height="8" fill="#000"/>
                    <rect x="42" y="18" width="8" height="8" fill="#000"/>
                    <rect x="42" y="42" width="16" height="16" fill="#000"/>
                    <rect x="66" y="66" width="12" height="12" fill="#000"/>
                    <rect x="78" y="42" width="8" height="8" fill="#000"/>
                  </svg>
                </div>
                <div class="zatca-details" style="text-align: start; width: 100%;">
                  <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <span class="badge-chip" style="background: rgba(0, 229, 153, 0.15); border-color: var(--primary); color: var(--primary);">
                      ✓ متوافق مع هيئة الزكاة والضريبة والجمارك (المرحلة 2)
                    </span>
                  </div>
                  <h5>شركة أسواق بندة للتجزئة</h5>
                  <div class="zatca-row">
                    <span id="z-lbl-tax">الرقم الضريبي:</span>
                    <strong>300055489200003</strong>
                  </div>
                  <div class="zatca-row">
                    <span id="z-lbl-vat">ضريبة القيمة المضافة (15%):</span>
                    <strong style="color: var(--amber);">32.40 ر.س</strong>
                  </div>
                  <div class="zatca-row">
                    <span id="z-lbl-tot">الإجمالي شامل الضريبة:</span>
                    <strong style="color: var(--primary);">248.40 ر.س</strong>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 4: Partner & Dependents Settlement -->
          <div id="sim-panel-partner" class="tab-panel">
            <div class="partner-sim-box">
              <div class="sim-header">
                <div class="sim-title">
                  <span>⚖️</span>
                  <span id="part-title-txt">حاسبة التسوية ثنائية الأبعاد وتتبع مصاريف الأبناء</span>
                </div>
                <div class="badge-chip" id="part-badge">نسبة عادلة 50% / 50%</div>
              </div>

              <div class="split-ratio-bar">
                <div class="split-bar-you" id="ratio-bar-you" style="width: 50%;"></div>
                <div class="split-bar-partner" id="ratio-bar-partner" style="width: 50%;"></div>
              </div>

              <div class="sim-stat-grid">
                <div class="stat-pill-card teal">
                  <div class="stat-lbl" id="part-lbl-net">صافي التسوية بين الشركاء</div>
                  <div class="stat-val" style="color: var(--primary);">+380 <small style="font-size: 13px;">ر.س مستحق لك</small></div>
                  <div class="stat-sub" id="part-sub-net">تمت الحسبة التلقائية لجميع فواتير الشهر</div>
                </div>

                <div class="stat-pill-card blue">
                  <div class="stat-lbl" id="part-lbl-kids">مجموع نفقات الأبناء هذا الشهر</div>
                  <div class="stat-val">1,240 <small style="font-size: 13px;">ر.س</small></div>
                  <div class="stat-sub" id="part-sub-kids">مدارس، أنشطة، ورعاية صحية</div>
                </div>
              </div>

              <div class="children-chips-bar">
                <span style="font-size: 13px; color: var(--text-muted); align-self: center;" id="part-lbl-tag">المستفيدون المخصصون:</span>
                <span class="child-chip">👧 سارة (مستلزمات مدرسية: 520 ر.س)</span>
                <span class="child-chip">👦 عمر (أنشطة رياضية: 430 ر.س)</span>
                <span class="child-chip">👶 فهد (تطعيمات وتموين: 290 ر.س)</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Bento Grid Features Section -->
    <section id="features">
      <div class="section-headline">
        <span class="section-eyebrow" id="feat-eyebrow">منظومة مالية شاملة</span>
        <h3 class="section-h2" id="feat-h2">كل ما تحتاجه الأسرة السعودية في تطبيق واحد</h3>
        <p class="section-sub" id="feat-sub">
          تم بناء كل ميزة لحل تحديات مالية حقيقية يواجهها الأفراد والأسر في المملكة مع تجربة مستخدم تتسم بالسهولة والجمال.
        </p>
      </div>

      <div class="bento-grid">
        <!-- 1. Flexible Salary Engine -->
        <div class="bento-card bento-span-8">
          <div>
            <div class="bento-icon teal">📅</div>
            <h4 class="bento-title" id="f1-t">دورة راتب مرنة وقواعد الصرف التلقائية</h4>
            <p class="bento-desc" id="f1-d">
              سواء كنت موظفاً حكومياً، أو في القطاع الخاص، أو تمارس عملاً حراً؛ حدد يوم راتبك الشهري بكل حرية. يطبق التطبيق القواعد المصرفية السعودية التلقائية (الصرف يوم الخميس إذا صادف الجمعة، ويوم الأحد إذا صادف السبت) مع احتساب معدل الصرف اليومي الآمن لتفادي نفاد الراتب مبكراً.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تعديل أي يوم في الشهر</span>
            <span class="pill-micro">موازنة العطلات البنكية</span>
            <span class="pill-micro">معدل الصرف اليومي الآمن</span>
          </div>
        </div>

        <!-- 2. Conversational Saudi AI -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon blue">✨</div>
            <h4 class="bento-title" id="f2-t">مساعد ذكي يفهم اللهجة السعودية</h4>
            <p class="bento-desc" id="f2-d">
              سجّل مشترياتك صوتياً أو كتابياً باللهجة المحلية أو الفصحى أو الإنجليزية. يفهم السياق فورياً ("عبيت بنزين 91 بـ 85 ريال") ويصنّفها بدقة متناهية.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">شات فوري</span>
            <span class="pill-micro">تعرّف باللهجة</span>
          </div>
        </div>

        <!-- 3. Two-Tier Taxonomy & Hybrid LLM Subcategories -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon purple">📂</div>
            <h4 class="bento-title" id="f3-t">تصنيف هجين ثنائي المستويات</h4>
            <p class="bento-desc" id="f3-d">
              تصنيفات رئيسية وفرعية دقيقة (مثل: المطاعم > وجبات سريعة أو كافيهات). يختار الذكاء الاصطناعي التصنيف الفرعي الأنسب مع بطاقة تأكيد تفاعلية تتيح لك التعديل بمرونة.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تصنيف فرعي ذكي</span>
            <span class="pill-micro">بطاقة تأكيد قبل الحفظ</span>
          </div>
        </div>

        <!-- 4. ZATCA Phase 2 QR Scanner -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon teal">🧾</div>
            <h4 class="bento-title" id="f4-t">ماسح فواتير ZATCA المرحلة الثانية</h4>
            <p class="bento-desc" id="f4-d">
              وجّه الكاميرا إلى أي فاتورة إلكترونية لفك شفرة رمز الاستجابة السريعة (Base64 TLV) بدقة 100% واستخراج اسم التاجر، الرقم الضريبي، وضريبة القيمة المضافة فورياً.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تشفير TLV</span>
            <span class="pill-micro">احتساب الضريبة 15%</span>
          </div>
        </div>

        <!-- 5. 2D Partner Fair-Share Split -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon amber">👥</div>
            <h4 class="bento-title" id="f5-t">تقسيم عادل بين الشركاء</h4>
            <p class="bento-desc" id="f5-d">
              نظام توثيق ثنائي الأبعاد يرصد "من دفع" و"من استفاد" مع نسبة مخصصة للتقاسم لحساب التسويات الصافية والديون المتبادلة دون أي إحراج مالي.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">رمز دعوة عائلي</span>
            <span class="pill-micro">تسوية ديون فورية</span>
          </div>
        </div>

        <!-- 6. Children & Dependents Tracking -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon blue">👶</div>
            <h4 class="bento-title" id="f6-t">تتبع نفقات الأبناء والتابعين</h4>
            <p class="bento-desc" id="f6-d">
              أضف أسماء الأبناء في إعدادات الأسرة وخصّص الفواتير لكل ابن (مصاريف المدارس، الأنشطة، المستلزمات الطبية) لمعرفة التكلفة الفعلية لكل فرد بدقة.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تخصيص لكل طفل</span>
            <span class="pill-micro">تقارير نفقات التابعين</span>
          </div>
        </div>

        <!-- 7. BNPL & Installments Tracker -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon purple">💳</div>
            <h4 class="bento-title" id="f7-t">متابعة أقساط تابي وتمارا والبطاقات</h4>
            <p class="bento-desc" id="f7-d">
              تتبّع خطط التقسيط عبر تابي، تمارا، أو البطاقات الائتمانية مع حلقات تقدم دائرية توضح المتبقي والتنبيه التلقائي قبل مواعيد السداد لتفادي الرسوم.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تابي & تمارا</span>
            <span class="pill-micro">تنبيه مواعيد الأقساط</span>
          </div>
        </div>

        <!-- 8. Recurring Bills & Cadence Engine -->
        <div class="bento-card bento-span-4">
          <div>
            <div class="bento-icon amber">⚡</div>
            <h4 class="bento-title" id="f8-t">جدولة الفواتير والاشتراكات الدورية</h4>
            <p class="bento-desc" id="f8-d">
              كشف وجدولة فواتير الكهرباء (SEC)، والمياه (NWC)، والاتصالات (STC/Mobily)، ورسوم الإقامة والتأمين لتجنب الانقطاعات والمفاجآت.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">الكهرباء والمياه</span>
            <span class="pill-micro">تجديدات الاشتراكات</span>
          </div>
        </div>

        <!-- 9. Smart Grocery Comparison -->
        <div class="bento-card bento-span-6">
          <div>
            <div class="bento-icon teal">🛒</div>
            <h4 class="bento-title" id="f9-t">مقارنة أسعار المقاضي وسلة التوفير</h4>
            <p class="bento-desc" id="f9-d">
              سجّل مشتريات السوبرماركت وقارن أسعار السلع الأساسية بين سلاسل المتاجر الكبرى في المملكة (بندة، كارفور، لولو، التميمي، الدانوب) لتوفير ما يصل إلى 20% شهرياً.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">تتبع تاريخ الأسعار</span>
            <span class="pill-micro">سلة المقاضي المثالية</span>
          </div>
        </div>

        <!-- 10. Purchase Affordability Simulator -->
        <div class="bento-card bento-span-6">
          <div>
            <div class="bento-icon blue">🧭</div>
            <h4 class="bento-title" id="f10-t">حاسبة "هل أستطيع تحمل هذه التكلفة؟"</h4>
            <p class="bento-desc" id="f10-d">
              اختبر أي قرار شراء غير مخطط له قبل اتخاذه؛ يحسب التطبيق فورياً أثر الشراء على وتيرة صرف الأيام المتبقية في دورة الراتب وعلى احتياطي الادخار دون إرباك الميزانية.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">محاكاة فورية للقرارات</span>
            <span class="pill-micro">حماية خطة الشهر</span>
          </div>
        </div>

        <!-- 11. Offline-First SQLite Engine -->
        <div class="bento-card bento-span-6">
          <div>
            <div class="bento-icon purple">⚡</div>
            <h4 class="bento-title" id="f11-t">يعمل بالكامل دون اتصال بالإنترنت</h4>
            <p class="bento-desc" id="f11-d">
              قاعدة بيانات SQLite محلية مدمجة تتيح لك تسجيل المصاريف ومسح الفواتير في أي وقت حتى بدون شبكة، مع مزامنة سحابية تلقائية وخوارزمية تشفير تمنع تكرار العمليات.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">مزامنة تلقائية</span>
            <span class="pill-micro">تشفير SHA-256</span>
          </div>
        </div>

        <!-- 12. Smart Savings Reserve & PDF Statements -->
        <div class="bento-card bento-span-6">
          <div>
            <div class="bento-icon amber">📊</div>
            <h4 class="bento-title" id="f12-t">احتياطي الادخار وتقارير PDF الشهرية</h4>
            <p class="bento-desc" id="f12-d">
              يتحول الفائض غير المخصص تلقائياً إلى صندوق احتياطي الادخار الأسري، مع إمكانية تصدير كشوف حساب شهرية رسمية بصيغة PDF باللغتين العربية والإنجليزية.
            </p>
          </div>
          <div class="bento-tag-row">
            <span class="pill-micro">صندوق طوارئ مالي</span>
            <span class="pill-micro">تقارير ضريبية ومالية</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Comparison Section -->
    <section class="matrix-section" id="comparison">
      <div class="section-headline" style="margin-bottom: 30px;">
        <span class="section-eyebrow" id="comp-eyebrow">لماذا نحن الخيار الأفضل؟</span>
        <h3 class="section-h2" id="comp-h2">أمان بنكي وخصوصية تامة بدون تجسس</h3>
      </div>

      <div class="matrix-grid">
        <div class="matrix-item">
          <div class="matrix-check">✓</div>
          <div class="matrix-text">
            <h4 id="cp-1-t">صفر تجسس على الرسائل النصية (SMS)</h4>
            <p id="cp-1-d">لا نطلب أي صلاحية مشبوهة لاعتراض الرسائل البنكية أو قراءة رسائل SMS في الخلفية كما تفعل التطبيقات القديمة.</p>
          </div>
        </div>

        <div class="matrix-item">
          <div class="matrix-check">✓</div>
          <div class="matrix-text">
            <h4 id="cp-2-t">عزل تام لبيانات الأسرة (Row-Level Security)</h4>
            <p id="cp-2-d">بيانات كل أسرة معزولة مشفرة سحابياً ولا يمكن لأي مستخدم آخر الاطلاع على فلس واحد من مصروفاتكم.</p>
          </div>
        </div>

        <div class="matrix-item">
          <div class="matrix-check">✓</div>
          <div class="matrix-text">
            <h4 id="cp-3-t">حفظ السجلات بنسبة 100% وعدم الحذف النهائي</h4>
            <p id="cp-3-d">التصنيفات غير المستخدمة تتحول إلى حالة "غير نشطة" مع حفظ كامل تاريخ المصروفات والرسوم البيانية السابقة.</p>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ Accordion -->
    <section class="faq-section" id="faq">
      <div class="section-headline">
        <span class="section-eyebrow" id="faq-eyebrow">إجابات واضحة</span>
        <h3 class="section-h2" id="faq-h2">الأسئلة الشائعة</h3>
      </div>

      <div class="faq-item active">
        <button class="faq-btn" onclick="toggleFaq(this)">
          <span id="faq-q1">هل التطبيق محصور بيوم راتب معين (مثل يوم 27)؟</span>
          <span class="faq-toggle-icon">+</span>
        </button>
        <div class="faq-answer" id="faq-a1">
          إطلاقاً! يمكنك ضبط يوم نزول الراتب على أي تاريخ في الشهر (1، 15، 25، 27 أو أي تاريخ يحدده جهة عملك). يتولى المحرك إعادة حساب الأيام المتبقية ومعدل الصرف اليومي الآمن بدقة وفق التاريخ الذي تختاره.
        </div>
      </div>

      <div class="faq-item">
        <button class="faq-btn" onclick="toggleFaq(this)">
          <span id="faq-q2">كيف يتعامل التطبيق مع عطلات نهاية الأسبوع ومواعيد صرف الراتب في البنوك السعودية؟</span>
          <span class="faq-toggle-icon">+</span>
        </button>
        <div class="faq-answer" id="faq-a2">
          يطبق التطبيق القواعد المصرفية المعتمدة في المملكة تلقائياً: إذا صادف يوم راتبك يوم الجمعة، يتم تقديم دورة الصرف إلى يوم الخميس. وإذا صادف يوم السبت، يتم ترحيلها إلى يوم الأحد لضمان دقة وتيرة الصرف اليومية.
        </div>
      </div>

      <div class="faq-item">
        <button class="faq-btn" onclick="toggleFaq(this)">
          <span id="faq-q3">هل يمكنني تقسيم المصاريف وتحديد تكلفة كل ابن من أفراد الأسرة؟</span>
          <span class="faq-toggle-icon">+</span>
        </button>
        <div class="faq-answer" id="faq-a3">
          نعم، يدعم التطبيق إدارة أفراد الأسرة وإضافة الأبناء؛ عند تسجيل أي فاتورة يمكنك تحديد من دفع المصروف (أنا أو الشريك) ولمن تم الصرف (أنا، الشريك، أو أحد الأبناء)، ويقوم التطبيق بحساب التسويات الصافية العادلة بدقة.
        </div>
      </div>

      <div class="faq-item">
        <button class="faq-btn" onclick="toggleFaq(this)">
          <span id="faq-q4">هل يمكنني مسح الفواتير الإلكترونية ZATCA دون اتصال بالإنترنت؟</span>
          <span class="faq-toggle-icon">+</span>
        </button>
        <div class="faq-answer" id="faq-a4">
          نعم، فك شفرة Base64 TLV الخاصة بفواتير ZATCA يتم محلياً وبشكل فوري على جهازك وبسرعة فائقة حتى بدون أي اتصال بالإنترنت، ويتم حفظ الفاتورة في قاعدة بيانات SQLite المحلية لحين توفر الشبكة.
        </div>
      </div>
    </section>

    <!-- Legal Section -->
    <section class="legal-container" id="legal">
      <div class="legal-tabs-row">
        <button class="legal-nav-btn active" id="tab-privacy-btn" onclick="switchLegalTab('privacy')">سياسة الخصوصية</button>
        <button class="legal-nav-btn" id="tab-terms-btn" onclick="switchLegalTab('terms')">شروط الاستخدام</button>
      </div>

      <div id="privacy-pane" class="legal-pane">
        <h4 id="lp-1">1. الالتزام الصارم بالخصوصية</h4>
        <p id="lp-1-txt">نحن في Budget Tracker نضع حماية بياناتك المالية فوق كل اعتبار. لا نطلب أي صلاحيات لاعتراض أو قراءة الرسائل النصية، ويتم عزل وتشفير بيانات كل أسرة سحابياً بأحدث معايير الأمان.</p>
        
        <h4 id="lp-2">2. البيانات المُعالجة</h4>
        <p id="lp-2-txt">يقتصر الاستخدام على البيانات التي يقدمها المستخدم طواعية: البريد الإلكتروني للمصادقة، ومصروفات الأسرة المدخلة يدوياً أو عبر الشات ومسح فواتير ZATCA.</p>
        
        <h4 id="lp-3">3. حق حذف الحساب والبيانات</h4>
        <p id="lp-3-txt">يحق للمستخدم طلب الحذف النهائي والشامل لحسابه وكافة سجلاته المالية في أي وقت عبر مراسلة الدعم الفني مباشرة على: abedmowafaq@gmail.com.</p>
      </div>

      <div id="terms-pane" class="legal-pane" style="display: none;">
        <h4 id="lt-1">1. الموافقة والامتثال</h4>
        <p id="lt-1-txt">باستخدامك لتطبيق وموقع Budget Tracker فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.</p>
        
        <h4 id="lt-2">2. الاستخدام للأغراض الشخصية والأسرية</h4>
        <p id="lt-2-txt">التطبيق مصمم لإدارة وتنظيم الميزانية الشخصية والأسرية وتقديم مؤشرات توجيهية ولا يمثل مشورة استثمارية أو مصرفية رسمية.</p>
        
        <h4 id="lt-3">3. الدعم الفني والاستفسارات</h4>
        <p id="lt-3-txt">لأي استفسارات أو مقترحات برمجية، يُرجى مراسلة المطور على: abedmowafaq@gmail.com.</p>
      </div>
    </section>

    <!-- Contact Banner -->
    <section class="contact-card" id="contact">
      <h3 class="contact-title" id="contact-h">هل ترغب بالانضمام للنسخة التجريبية أو تقديم اقتراح؟</h3>
      <p class="contact-desc" id="contact-p">
        يسعدنا دائماً الاستماع لآرائكم وملاحظاتكم لبناء أفضل تجربة مالية رقمية للأسر في المملكة العربية السعودية.
      </p>
      <a href="mailto:abedmowafaq@gmail.com" class="email-capsule">
        <span>✉️</span>
        <span>abedmowafaq@gmail.com</span>
      </a>
    </section>
  </main>

  <!-- Footer -->
  <footer>
    <div class="container">
      <div class="footer-links-row">
        <a href="#simulator" id="ft-sim">المحاكي</a>
        <a href="#features" id="ft-feat">المميزات</a>
        <a href="#comparison" id="ft-comp">الأمان</a>
        <a href="#faq" id="ft-faq">الأسئلة الشائعة</a>
        <a href="#legal" onclick="switchLegalTab('privacy')" id="ft-priv">الخصوصية</a>
        <a href="#legal" onclick="switchLegalTab('terms')" id="ft-term">الشروط</a>
        <a href="mailto:abedmowafaq@gmail.com" id="ft-cont">الدعم</a>
      </div>
      <p id="ft-copy">© 2026 Budget Tracker • جميع الحقوق محفوظة لـ budget.fmsco.com.sa</p>
    </div>
  </footer>

  <script>
    let currentLang = 'ar';

    const translations = {
      en: {
        dir: 'ltr',
        bodyClass: 'lang-en',
        langBtnText: '🇸🇦 <span>العربية</span>',
        navBrandSub: 'Smart Family Budgeting',
        navSim: 'Interactive Simulator',
        navFeat: 'Features',
        navComp: 'Comparison',
        navFaq: 'FAQ',
        navContact: 'Contact',
        heroBadgeText: 'Fintech Innovation • Works with Any Monthly Salary Cycle',
        heroH1: 'Absolute Mastery of Your Family Budget',
        heroH2: 'With Any Salary Date You Choose & AI Precision',
        heroDesc: 'Engineered specifically for households in Saudi Arabia. Freely choose your monthly payday (1st, 15th, 25th, 27th, or custom), with automated banking weekend adjustments, instant ZATCA e-invoice scanning, and fair expense allocation between partners and children.',
        stGoogleSub: 'Coming Soon On',
        stAppleSub: 'Coming Soon On',
        stHuaweiSub: 'Coming Soon On',
        chip1: 'Soon',
        chip2: 'Soon',
        chip3: 'Soon',
        tabT1: 'Payday Engine',
        tabT2: 'AI Chat Assistant',
        tabT3: 'ZATCA Scanner',
        tabT4: 'Partners & Dependents',
        simTitleTxt: 'Choose your monthly salary date (100% flexible for all sectors)',
        simShiftBadge: '✓ Automated Banking Weekend Shift Active',
        sliderMinLbl: 'Day 1 of Month',
        sliderCurrLbl: 'Selected Payday:',
        sliderMaxLbl: 'Day 31 of Month',
        simLblDays: 'Days Remaining in Cycle',
        simSubDays: 'Active balanced cycle',
        simLblSafe: 'Safe Daily Spending Pace',
        simSubSafe: 'Prevents running out before payday',
        simLblReserve: 'Automatic Savings Buffer',
        simSubReserve: 'Unallocated surplus saved for emergencies',
        chatUMsg: '"Family dinner at Al Baik for 68 SAR, paid by me for the family"',
        chatAiHeader: 'Expense Extracted with Precision by AI',
        zLblTax: 'VAT Registration No:',
        zLblVat: 'VAT Amount (15%):',
        zLblTot: 'Grand Total with VAT:',
        partTitleTxt: '2D Fair-Share Settlement & Children Allocation',
        partBadge: 'Fair Ratio 50% / 50%',
        partLblNet: 'Net Settlement Between Partners',
        partSubNet: 'Automatically reconciled across monthly bills',
        partLblKids: 'Total Children Expenses This Month',
        partSubKids: 'Schools, extracurriculars, & healthcare',
        partLblTag: 'Designated Beneficiaries:',
        featEyebrow: 'Comprehensive Financial Platform',
        featH2: 'Everything Your Family Needs in One App',
        featSub: 'Every single feature is built to solve real everyday financial challenges faced by households across Saudi Arabia.',
        f1T: 'Flexible Salary Cycle & Auto Banking Shifts',
        f1D: 'Whether in government, the private sector, or freelancing; configure your salary day freely. The engine applies Saudi banking weekend rules automatically (Thursday if Friday, Sunday if Saturday) with live safe burn-rate pacing.',
        f2T: 'Conversational Saudi AI Assistant',
        f2D: 'Log expenses via text or voice in Saudi dialect, Arabic, English, or Urdu. Instant context parsing ("Filled 91 petrol for 85 SAR") automatically classifies merchant, category, and payment tags.',
        f3T: 'Two-Tier Taxonomy & Hybrid Subcategories',
        f3D: 'Deep multi-tier categories (e.g. Dining > Fast Food or Coffee). AI recommends the optimal subcategory with an interactive confirmation card before recording.',
        f4T: 'ZATCA Phase 2 E-Invoice QR Scanner',
        f4D: 'Point your camera at any e-invoice to decode cryptographic Base64 TLV QR codes with 100% precision, instantly extracting seller info, tax ID, and 15% VAT totals.',
        f5T: 'Fair Partner Attribution & Settlements',
        f5D: 'Two-dimensional tracking records "Who Paid" vs "Who Benefited" with customizable ratios, calculating clean net debts without financial awkwardness.',
        f6T: 'Family Dependents & Children Tracking',
        f6D: 'Add children profiles in household settings to designate costs (school fees, sports, healthcare) and view exact spending per dependent.',
        f7T: 'BNPL & Installment Tracker',
        f7D: 'Track Tabby, Tamara, and bank credit card installment schedules with progress rings and automated notifications before due dates.',
        f8T: 'Recurring Bills & Cadence Engine',
        f8D: 'Auto-detect and track utility bills like electricity (SEC), water (NWC), fiber telecom (STC/Mobily), and annual Iqama renewals.',
        f9T: 'Smart Grocery Price Comparison',
        f9D: 'Log supermarket baskets and track staple price trends across Panda, Carrefour, Lulu, Danube, and Tamimi to save up to 20% every month.',
        f10T: '"Can I Afford This?" Instant Simulator',
        f10D: 'Test discretionary purchases before buying. Real-time simulation checks the impact on remaining cycle budget and emergency savings.',
        f11T: '100% Offline-First SQLite Architecture',
        f11D: 'Integrated local SQLite engine lets you log transactions anywhere without internet, with SHA-256 cloud sync avoiding duplicate entries.',
        f12T: 'Smart Savings Reserve & Monthly PDF Reports',
        f12D: 'Unassigned monthly income automatically sweeps into a family emergency reserve, with official bilingual ZATCA-ready PDF statement exports.',
        compEyebrow: 'Why We Stand Apart',
        compH2: 'Bank-Grade Security with Zero Intrusive Snooping',
        cp1T: 'Zero Background SMS Reading',
        cp1D: 'We never request intrusive SMS intercept permissions to read your private bank text messages, unlike legacy apps.',
        cp2T: 'Household Row-Level Security (RLS)',
        cp2D: 'Every family is strictly isolated with modern database encryption; no other user can ever view a single cent of your transactions.',
        cp3T: '100% Zero Data Deletion',
        cp3D: 'Unused categories are gracefully archived as inactive, fully preserving your historical transaction analytics and trends.',
        faqEyebrow: 'Clear Answers',
        faqH2: 'Frequently Asked Questions',
        faqQ1: 'Is the app locked to a specific payday (like the 27th)?',
        faqA1: 'Not at all! You can set your payday to any day of the month (1st, 15th, 25th, 27th, or custom). The engine dynamically calculates days remaining and safe daily spending according to your chosen date.',
        faqQ2: 'How does the app handle Saudi banking weekend salary shifts?',
        faqA2: 'The engine applies official Saudi banking schedule rules automatically: if your payday falls on a Friday, it shifts to Thursday. If it falls on a Saturday, it moves to Sunday.',
        faqQ3: 'Can I split expenses and track costs for each child?',
        faqA3: 'Yes! The app supports full household dependents management. When logging an expense, you specify who paid and for whom (yourself, your partner, or a child), and net balances reconcile automatically.',
        faqQ4: 'Can I scan ZATCA invoices without an internet connection?',
        faqA4: 'Yes! Cryptographic Base64 TLV decoding is performed locally on your device in milliseconds. Offline receipts queue in your local SQLite database and sync when reconnected.',
        tabPrivacyBtn: 'Privacy Policy',
        tabTermsBtn: 'Terms of Service',
        lp1: '1. Strict Privacy Commitment',
        lp1Txt: 'At Budget Tracker, your financial data privacy is our absolute priority. We do not require SMS reading permissions and protect household data with modern cloud row-level security.',
        lp2: '2. Data Processed',
        lp2Txt: 'Data collection is strictly limited to information voluntarily provided: authentication email, expenses logged via chat or manually, and scanned ZATCA invoice receipts.',
        lp3: '3. Data Deletion Rights',
        lp3Txt: 'You may request permanent deletion of your account and all associated household records at any time by contacting: abedmowafaq@gmail.com.',
        lt1: '1. Agreement to Terms',
        lt1Txt: 'By accessing or using Budget Tracker, you agree to these Terms of Service and related privacy guidelines.',
        lt2: '2. Household Financial Planning',
        lt2Txt: 'The application is intended for personal and household financial organization and does not represent official financial advisory services.',
        lt3: '3. Support & Feedback',
        lt3Txt: 'For developer inquiries, bug reports, or feature requests, contact: abedmowafaq@gmail.com.',
        contactH: 'Interested in joining our Beta or sharing feedback?',
        contactP: 'We are always eager to hear your suggestions to build the finest digital finance experience for families in Saudi Arabia.',
        ftSim: 'Simulator',
        ftFeat: 'Features',
        ftComp: 'Security',
        ftFaq: 'FAQ',
        ftPriv: 'Privacy Policy',
        ftTerm: 'Terms of Service',
        ftCont: 'Support',
        ftCopy: '© 2026 Budget Tracker • All rights reserved for budget.fmsco.com.sa'
      },
      ar: {
        dir: 'rtl',
        bodyClass: '',
        langBtnText: '🌐 <span>English</span>',
        navBrandSub: 'ميزانية الأسرة الذكية',
        navSim: 'المحاكي التفاعلي',
        navFeat: 'المميزات',
        navComp: 'المقارنة',
        navFaq: 'الأسئلة الشائعة',
        navContact: 'الدعم الفني',
        heroBadgeText: 'الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية',
        heroH1: 'تحكّم مطلق في ميزانية أسرتك',
        heroH2: 'مع أي يوم راتب تختاره وبدقة الذكاء الاصطناعي',
        heroDesc: 'صُمم خصيصاً ليواكب واقع الأسر في السعودية. حدد يوم نزول راتبك بكل حرية (اليوم 1، 15، 25، 27 أو أي تاريخ يناسبك)، مع حساب قواعد الصرف المصرفية للعطلات تلقائياً، ومسح فواتير ZATCA، وتوزيع المصاريف بعدالة بين الشركاء والأبناء دون أي عناء.',
        stGoogleSub: 'متوفر قريباً على',
        stAppleSub: 'متوفر قريباً على',
        stHuaweiSub: 'متوفر قريباً على',
        chip1: 'قريباً',
        chip2: 'قريباً',
        chip3: 'قريباً',
        tabT1: 'محاكي دورة الراتب',
        tabT2: 'مساعد الشات الذكي',
        tabT3: 'ماسح فواتير ZATCA',
        tabT4: 'تقسيم الشركاء والأبناء',
        simTitleTxt: 'اختر يوم نزول راتبك الشهري (مرن 100% لأي قطاع)',
        simShiftBadge: '✓ نظام الصرف التلقائي للعطلات نشط',
        sliderMinLbl: 'اليوم 1 في الشهر',
        sliderCurrLbl: 'يوم الراتب المحدد:',
        sliderMaxLbl: 'اليوم 31 في الشهر',
        simLblDays: 'الأيام المتبقية في الدورة',
        simSubDays: 'دورة نشطة متوازنة',
        simLblSafe: 'معدل الصرف اليومي الآمن',
        simSubSafe: 'يحميك من نفاد الميزانية قبل الراتب',
        simLblReserve: 'احتياطي الادخار التلقائي',
        simSubReserve: 'فائض غير مخصص يُحفظ للطوارئ',
        chatUMsg: '"عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة"',
        chatAiHeader: 'تم استخراج المصروف بالذكاء الاصطناعي بدقة',
        zLblTax: 'الرقم الضريبي:',
        zLblVat: 'ضريبة القيمة المضافة (15%):',
        zLblTot: 'الإجمالي شامل الضريبة:',
        partTitleTxt: 'حاسبة التسوية ثنائية الأبعاد وتتبع مصاريف الأبناء',
        partBadge: 'نسبة عادلة 50% / 50%',
        partLblNet: 'صافي التسوية بين الشركاء',
        partSubNet: 'تمت الحسبة التلقائية لجميع فواتير الشهر',
        partLblKids: 'مجموع نفقات الأبناء هذا الشهر',
        partSubKids: 'مدارس، أنشطة، ورعاية صحية',
        partLblTag: 'المستفيدون المخصصون:',
        featEyebrow: 'منظومة مالية شاملة',
        featH2: 'كل ما تحتاجه الأسرة السعودية في تطبيق واحد',
        featSub: 'تم بناء كل ميزة لحل تحديات مالية حقيقية يواجهها الأفراد والأسر في المملكة مع تجربة مستخدم تتسم بالسهولة والجمال.',
        f1T: 'دورة راتب مرنة وقواعد الصرف التلقائية',
        f1D: 'سواء كنت موظفاً حكومياً، أو في القطاع الخاص، أو تمارس عملاً حراً؛ حدد يوم راتبك الشهري بكل حرية. يطبق التطبيق القواعد المصرفية السعودية التلقائية (الصرف يوم الخميس إذا صادف الجمعة، ويوم الأحد إذا صادف السبت) مع احتساب معدل الصرف اليومي الآمن لتفادي نفاد الراتب مبكراً.',
        f2T: 'مساعد ذكي يفهم اللهجة السعودية',
        f2D: 'سجّل مشترياتك صوتياً أو كتابياً باللهجة المحلية أو الفصحى أو الإنجليزية. يفهم السياق فورياً ("عبيت بنزين 91 بـ 85 ريال") ويصنّفها بدقة متناهية.',
        f3T: 'تصنيف هجين ثنائي المستويات',
        f3D: 'تصنيفات رئيسية وفرعية دقيقة (مثل: المطاعم > وجبات سريعة أو كافيهات). يختار الذكاء الاصطناعي التصنيف الفرعي الأنسب مع بطاقة تأكيد تفاعلية تتيح لك التعديل بمرونة.',
        f4T: 'ماسح فواتير ZATCA المرحلة الثانية',
        f4D: 'وجّه الكاميرا إلى أي فاتورة إلكترونية لفك شفرة رمز الاستجابة السريعة (Base64 TLV) بدقة 100% واستخراج اسم التاجر، الرقم الضريبي، وضريبة القيمة المضافة فورياً.',
        f5T: 'تقسيم عادل بين الشركاء',
        f5D: 'نظام توثيق ثنائي الأبعاد يرصد "من دفع" و"من استفاد" مع نسبة مخصصة للتقاسم لحساب التسويات الصافية والديون المتبادلة دون أي إحراج مالي.',
        f6T: 'تتبع نفقات الأبناء والتابعين',
        f6D: 'أضف أسماء الأبناء في إعدادات الأسرة وخصّص الفواتير لكل ابن (مصاريف المدارس، الأنشطة، المستلزمات الطبية) لمعرفة التكلفة الفعلية لكل فرد بدقة.',
        f7T: 'متابعة أقساط تابي وتمارا والبطاقات',
        f7D: 'تتبّع خطط التقسيط عبر تابي، تمارا، أو البطاقات الائتمانية مع حلقات تقدم دائرية توضح المتبقي والتنبيه التلقائي قبل مواعيد السداد لتفادي الرسوم.',
        f8T: 'جدولة الفواتير والاشتراكات الدورية',
        f8D: 'كشف وجدولة فواتير الكهرباء (SEC)، والمياه (NWC)، والاتصالات (STC/Mobily)، ورسوم الإقامة والتأمين لتجنب الانقطاعات والمفاجآت.',
        f9T: 'مقارنة أسعار المقاضي وسلة التوفير',
        f9D: 'سجّل مشتريات السوبرماركت وقارن أسعار السلع الأساسية بين سلاسل المتاجر الكبرى في المملكة (بندة، كارفور، لولو، التميمي، الدانوب) لتوفير ما يصل إلى 20% شهرياً.',
        f10T: 'حاسبة "هل أستطيع تحمل هذه التكلفة؟"',
        f10D: 'اختبر أي قرار شراء غير مخطط له قبل اتخاذه؛ يحسب التطبيق فورياً أثر الشراء على وتيرة صرف الأيام المتبقية في دورة الراتب وعلى احتياطي الادخار دون إرباك الميزانية.',
        f11T: 'يعمل بالكامل دون اتصال بالإنترنت',
        f11D: 'قاعدة بيانات SQLite محلية مدمجة تتيح لك تسجيل المصاريف ومسح الفواتير في أي وقت حتى بدون شبكة، مع مزامنة سحابية تلقائية وخوارزمية تشفير تمنع تكرار العمليات.',
        f12T: 'احتياطي الادخار وتقارير PDF الشهرية',
        f12D: 'يتحول الفائض غير المخصص تلقائياً إلى صندوق احتياطي الادخار الأسري، مع إمكانية تصدير كشوف حساب شهرية رسمية بصيغة PDF باللغتين العربية والإنجليزية.',
        compEyebrow: 'لماذا نحن الخيار الأفضل؟',
        compH2: 'أمان بنكي وخصوصية تامة بدون تجسس',
        cp1T: 'صفر تجسس على الرسائل النصية (SMS)',
        cp1D: 'لا نطلب أي صلاحية مشبوهة لاعتراض الرسائل البنكية أو قراءة رسائل SMS في الخلفية كما تفعل التطبيقات القديمة.',
        cp2T: 'عزل تام لبيانات الأسرة (Row-Level Security)',
        cp2D: 'بيانات كل أسرة معزولة مشفرة سحابياً ولا يمكن لأي مستخدم آخر الاطلاع على فلس واحد من مصروفاتكم.',
        cp3T: 'حفظ السجلات بنسبة 100% وعدم الحذف النهائي',
        cp3D: 'التصنيفات غير المستخدمة تتحول إلى حالة "غير نشطة" مع حفظ كامل تاريخ المصروفات والرسوم البيانية السابقة.',
        faqEyebrow: 'إجابات واضحة',
        faqH2: 'الأسئلة الشائعة',
        faqQ1: 'هل التطبيق محصور بيوم راتب معين (مثل يوم 27)؟',
        faqA1: 'إطلاقاً! يمكنك ضبط يوم نزول الراتب على أي تاريخ في الشهر (1، 15، 25، 27 أو أي تاريخ يحدده جهة عملك). يتولى المحرك إعادة حساب الأيام المتبقية ومعدل الصرف اليومي الآمن بدقة وفق التاريخ الذي تختاره.',
        faqQ2: 'كيف يتعامل التطبيق مع عطلات نهاية الأسبوع ومواعيد صرف الراتب في البنوك السعودية؟',
        faqA2: 'يطبق التطبيق القواعد المصرفية المعتمدة في المملكة تلقائياً: إذا صادف يوم راتبك يوم الجمعة، يتم تقديم دورة الصرف إلى يوم الخميس. وإذا صادف يوم السبت، يتم ترحيلها إلى يوم الأحد لضمان دقة وتيرة الصرف اليومية.',
        faqQ3: 'هل يمكنني تقسيم المصاريف وتحديد تكلفة كل ابن من أفراد الأسرة؟',
        faqA3: 'نعم، يدعم التطبيق إدارة أفراد الأسرة وإضافة الأبناء؛ عند تسجيل أي فاتورة يمكنك تحديد من دفع المصروف (أنا أو الشريك) ولمن تم الصرف (أنا، الشريك، أو أحد الأبناء)، ويقوم التطبيق بحساب التسويات الصافية العادلة بدقة.',
        faqQ4: 'هل يمكنني مسح الفواتير الإلكترونية ZATCA دون اتصال بالإنترنت؟',
        faqA4: 'نعم، فك شفرة Base64 TLV الخاصة بفواتير ZATCA يتم محلياً وبشكل فوري على جهازك وبسرعة فائقة حتى بدون أي اتصال بالإنترنت، ويتم حفظ الفاتورة في قاعدة بيانات SQLite المحلية لحين توفر الشبكة.',
        tabPrivacyBtn: 'سياسة الخصوصية',
        tabTermsBtn: 'شروط الاستخدام',
        lp1: '1. الالتزام الصارم بالخصوصية',
        lp1Txt: 'نحن في Budget Tracker نضع حماية بياناتك المالية فوق كل اعتبار. لا نطلب أي صلاحيات لاعتراض أو قراءة الرسائل النصية، ويتم عزل وتشفير بيانات كل أسرة سحابياً بأحدث معايير الأمان.',
        lp2: '2. البيانات المُعالجة',
        lp2Txt: 'يقتصر الاستخدام على البيانات التي يقدمها المستخدم طواعية: البريد الإلكتروني للمصادقة، ومصروفات الأسرة المدخلة يدوياً أو عبر الشات ومسح فواتير ZATCA.',
        lp3: '3. حق حذف الحساب والبيانات',
        lp3Txt: 'يحق للمستخدم طلب الحذف النهائي والشامل لحسابه وكافة سجلاته المالية في أي وقت عبر مراسلة الدعم الفني مباشرة على: abedmowafaq@gmail.com.',
        lt1: '1. الموافقة والامتثال',
        lt1Txt: 'باستخدامك لتطبيق وموقع Budget Tracker فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.',
        lt2: '2. الاستخدام للأغراض الشخصية والأسرية',
        lt2Txt: 'التطبيق مصمم لإدارة وتنظيم الميزانية الشخصية والأسرية وتقديم مؤشرات توجيهية ولا يمثل مشورة استثمارية أو مصرفية رسمية.',
        lt3: '3. الدعم الفني والاستفسارات',
        lt3Txt: 'لأي استفسارات أو مقترحات برمجية، يُرجى مراسلة المطور على: abedmowafaq@gmail.com.',
        contactH: 'هل ترغب بالانضمام للنسخة التجريبية أو تقديم اقتراح؟',
        contactP: 'يسعدنا دائماً الاستماع لآرائكم وملاحظاتكم لبناء أفضل تجربة مالية رقمية للأسر في المملكة العربية السعودية.',
        ftSim: 'المحاكي',
        ftFeat: 'المميزات',
        ftComp: 'الأمان',
        ftFaq: 'الأسئلة الشائعة',
        ftPriv: 'الخصوصية',
        ftTerm: 'الشروط',
        ftCont: 'الدعم',
        ftCopy: '© 2026 Budget Tracker • جميع الحقوق محفوظة لـ budget.fmsco.com.sa'
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

      for (const [key, val] of Object.entries(data)) {
        const kebab = key.replace(/([A-Z0-9])/g, "-$1").toLowerCase();
        const el = document.getElementById(kebab);
        if (el) {
          if (typeof val === 'string' && val.includes('<')) {
            el.innerHTML = val;
          } else {
            el.innerText = val;
          }
        }
      }
      // Re-trigger simulator numbers in case language switched
      const paydayVal = document.getElementById('payday-range').value;
      updatePaydaySim(paydayVal);
    }

    function switchSimTab(tab) {
      const panels = ['payday', 'ai', 'zatca', 'partner'];
      panels.forEach((p, idx) => {
        const btn = document.getElementById('tab-sim-btn-' + (idx + 1));
        const panel = document.getElementById('sim-panel-' + p);
        if (p === tab) {
          btn.classList.add('active');
          panel.classList.add('active');
        } else {
          btn.classList.remove('active');
          panel.classList.remove('active');
        }
      });
    }

    function updatePaydaySim(day) {
      document.getElementById('slider-curr-val').innerText = day;
      const today = 11;
      let d = parseInt(day);
      let diff = d - today;
      if (diff <= 0) diff += 30;

      const unit = (currentLang === 'ar') ? 'يوم' : 'Days';
      const sar = (currentLang === 'ar') ? 'ر.س / يوم' : 'SAR / day';
      
      document.getElementById('sim-val-days').innerHTML = diff + ' <small style="font-size: 13px;">' + unit + '</small>';
      
      let safeDaily = Math.round(5500 / diff);
      document.getElementById('sim-val-safe').innerHTML = safeDaily + ' <small style="font-size: 13px;">' + sar + '</small>';
    }

    function toggleFaq(btn) {
      const item = btn.parentElement;
      item.classList.toggle('active');
    }

    function switchLegalTab(tab) {
      const pTab = document.getElementById('privacy-pane');
      const tTab = document.getElementById('terms-pane');
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
      background: #06080D;
      color: #C9D1D9;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      position: relative;
    }
    .card {
      background: #0E131C;
      border: 1px solid rgba(0, 229, 153, 0.3);
      border-radius: 24px;
      padding: 48px 36px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6), 0 0 40px rgba(0, 229, 153, 0.15);
      position: relative;
      z-index: 1;
    }
    .icon-circle {
      width: 80px;
      height: 80px;
      border-radius: 50%;
      background: rgba(0, 229, 153, 0.15);
      border: 2px solid #00E599;
      color: #00E599;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 40px;
      margin-bottom: 24px;
      box-shadow: 0 0 25px rgba(0, 229, 153, 0.3);
    }
    h1 {
      color: #FFFFFF;
      font-size: 26px;
      font-weight: 800;
      margin-bottom: 8px;
    }
    .subtitle-en {
      color: #00E599;
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
      background: rgba(56, 189, 248, 0.12);
      border: 1px solid rgba(56, 189, 248, 0.3);
      color: #38BDF8;
      font-size: 13px;
      font-weight: 700;
      padding: 6px 16px;
      border-radius: 20px;
      margin-bottom: 24px;
    }
    .action-btn {
      display: inline-block;
      width: 100%;
      background: linear-gradient(135deg, #00E599, #0284c7);
      color: #FFFFFF;
      font-size: 16px;
      font-weight: 800;
      padding: 14px 20px;
      border-radius: 14px;
      text-decoration: none;
      transition: all 0.25s ease;
      box-shadow: 0 8px 24px rgba(0, 229, 153, 0.3);
    }
    .action-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 12px 30px rgba(0, 229, 153, 0.45);
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
      color: #00E599;
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
