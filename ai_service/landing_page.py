"""
Landing page and auth confirmation HTML generator for Budget Tracker (budget.fmsco.com.sa).
Architected with modern-landing-designer and cinematic editorial aesthetics:
- Cinematic hero with vertical light ray and atmospheric depth inspired by modern editorial UI.
- Dual-typography: High-contrast bold sans + editorial italic serif accent (like Nate Herik designs).
- Zero SMS and Zero Banking dependencies (100% conversational AI, ZATCA QR OCR, and manual entry).
- Top browser tab SVG logo favicon embedded directly.
- Bug-free segmented language switcher ([العربية] | [English]) with data-i18n mapping.
- Live Interactive Product Stage (Payday Simulator, AI Chat, ZATCA Scanner, 2D Split).
- 12-pillar asymmetric Bento Grid with micro-borders.
- Developer contact (abedmowafaq@gmail.com) and coming soon store badges.
"""

def get_landing_page_html() -> str:
    return """<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • ميزانية الأسرة الذكية | الابتكار المالي للأسر في السعودية</title>
  <meta name="description" content="تطبيق إدارة ميزانية الأسرة ومصاريفها في السعودية. دورة راتب مرنة لأي يوم في الشهر، مسح فواتير ZATCA بالذكاء الاصطناعي، تقسيم المصاريف بين الشركاء وتتبع نفقات الأبناء.">
  
  <!-- Website Logo Favicon for browser tab -->
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0%25' y1='0%25' x2='100%25' y2='100%25'%3E%3Cstop offset='0%25' stop-color='%2334D399'/%3E%3Cstop offset='100%25' stop-color='%230284C7'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='%2308080A'/%3E%3Cpath d='M32 10 L52 24 L52 46 L32 54 L12 46 L12 24 Z' fill='url(%23g)' stroke='%23ffffff' stroke-width='1.5' stroke-opacity='0.4'/%3E%3Ccircle cx='32' cy='32' r='7' fill='%23ffffff'/%3E%3C/svg%3E">
  
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=Newsreader:ital,opsz,wght@1,6..72,400;1,6..72,600;1,6..72,700&family=Playfair+Display:ital,wght@1,500;1,600;1,700&family=Plus+Jakarta+Sans:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  
  <style>
    :root {
      --canvas-base: #060709;
      --card-surface: #0E1015;
      --card-elevated: #14171F;
      --card-border: rgba(255, 255, 255, 0.08);
      --card-border-hover: rgba(255, 255, 255, 0.2);
      --specular-line: inset 0 1px 0 rgba(255, 255, 255, 0.12);
      
      --emerald-glow: #34D399;
      --emerald-dim: rgba(52, 211, 153, 0.12);
      --cyan-glow: #38BDF8;
      --terracotta: #F97316;
      --terracotta-dim: rgba(249, 115, 22, 0.15);
      --amber: #F59E0B;
      --purple: #A855F7;
      
      --text-pure: #FFFFFF;
      --text-primary: #F1F5F9;
      --text-muted: #94A3B8;
      --text-dim: #64748B;
      
      --font-ar: 'Cairo', -apple-system, sans-serif;
      --font-en: 'Plus Jakarta Sans', -apple-system, sans-serif;
      --font-editorial: 'Playfair Display', 'Newsreader', Georgia, serif;
      
      --radius-sm: 10px;
      --radius-md: 16px;
      --radius-lg: 24px;
      --radius-xl: 32px;
      --max-w: 1240px;
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
      background-color: var(--canvas-base);
      color: var(--text-primary);
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

    /* Cinematic Atmospheric Hero Background */
    .cinematic-backdrop {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 880px;
      background: radial-gradient(ellipse 90% 70% at 50% 0%, rgba(14, 28, 22, 0.6) 0%, rgba(6, 7, 9, 0.95) 80%, var(--canvas-base) 100%);
      pointer-events: none;
      z-index: 0;
      overflow: hidden;
    }

    /* Volumetric Godray Light Shaft (Nate Herik Style) */
    .volumetric-light-ray {
      position: absolute;
      top: -60px;
      left: 50%;
      transform: translateX(-50%);
      width: 440px;
      height: 700px;
      background: conic-gradient(from 180deg at 50% 0%, rgba(255, 255, 255, 0.08) 0deg, rgba(52, 211, 153, 0.06) 20deg, transparent 40deg, transparent 320deg, rgba(56, 189, 248, 0.05) 340deg, rgba(255, 255, 255, 0.08) 360deg);
      filter: blur(40px);
      opacity: 0.85;
      pointer-events: none;
    }

    .ambient-dot-grid {
      position: fixed;
      inset: 0;
      background-image: radial-gradient(rgba(255, 255, 255, 0.05) 1px, transparent 1px);
      background-size: 32px 32px;
      opacity: 0.55;
      pointer-events: none;
      z-index: 0;
      mask-image: radial-gradient(circle at 50% 30%, black 45%, transparent 85%);
      -webkit-mask-image: radial-gradient(circle at 50% 30%, black 45%, transparent 85%);
    }

    .container {
      max-width: var(--max-w);
      margin: 0 auto;
      padding: 0 28px;
      position: relative;
      z-index: 1;
    }

    /* Minimalist High-Craft Header */
    header {
      position: sticky;
      top: 0;
      z-index: 100;
      background: rgba(6, 7, 9, 0.75);
      backdrop-filter: blur(24px) saturate(180%);
      -webkit-backdrop-filter: blur(24px) saturate(180%);
      border-bottom: 1px solid var(--card-border);
      transition: all 0.3s ease;
    }

    .nav-inner {
      display: flex;
      justify-content: space-between;
      align-items: center;
      height: 76px;
    }

    .brand-group {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: inherit;
    }

    .brand-logo-pill {
      width: 36px;
      height: 36px;
      border-radius: 10px;
      background: linear-gradient(135deg, #10B981, #0284C7);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      box-shadow: 0 0 20px rgba(16, 185, 129, 0.35), var(--specular-line);
      border: 1px solid rgba(255, 255, 255, 0.2);
    }

    .brand-title-wrap {
      display: flex;
      align-items: baseline;
      gap: 6px;
    }

    .brand-title-wrap h1 {
      font-size: 19px;
      font-weight: 900;
      letter-spacing: -0.03em;
      color: var(--text-pure);
      text-transform: uppercase;
    }

    .brand-dot {
      color: var(--emerald-glow);
      font-size: 22px;
      line-height: 0;
    }

    .nav-links-menu {
      display: flex;
      align-items: center;
      gap: 32px;
      list-style: none;
    }

    .nav-links-menu a {
      color: var(--text-muted);
      text-decoration: none;
      font-size: 13.5px;
      font-weight: 600;
      letter-spacing: 0.02em;
      transition: color 0.2s ease;
    }

    .nav-links-menu a:hover {
      color: var(--text-pure);
    }

    .nav-actions-right {
      display: flex;
      align-items: center;
      gap: 14px;
    }

    /* Bug-free Segmented Language Switcher */
    .segmented-lang-control {
      display: flex;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--card-border);
      border-radius: 999px;
      padding: 3px;
      gap: 2px;
    }

    .lang-segment-btn {
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-family: inherit;
      font-size: 12px;
      font-weight: 700;
      padding: 6px 14px;
      border-radius: 999px;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .lang-segment-btn.active {
      background: #FFFFFF;
      color: #060709;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
    }

    .nav-cta-pill {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.15);
      color: var(--text-pure);
      font-size: 13px;
      font-weight: 700;
      padding: 8px 18px;
      border-radius: 999px;
      text-decoration: none;
      transition: all 0.25s ease;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }

    .nav-cta-pill:hover {
      background: #FFFFFF;
      color: #060709;
      box-shadow: 0 0 20px rgba(255, 255, 255, 0.35);
      transform: translateY(-1px);
    }

    /* Hero Section (Cinematic Editorial) */
    .hero-container {
      padding: 100px 0 60px;
      text-align: center;
      position: relative;
    }

    .hero-kicker-badge {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      padding: 6px 18px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      border-radius: 999px;
      color: #E2E8F0;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      margin-bottom: 28px;
      box-shadow: var(--specular-line);
      backdrop-filter: blur(12px);
    }

    .kicker-ping-point {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: var(--emerald-glow);
      box-shadow: 0 0 10px var(--emerald-glow);
    }

    .hero-headline-main {
      font-size: clamp(38px, 6vw, 76px);
      font-weight: 900;
      line-height: 1.1;
      letter-spacing: -0.04em;
      color: var(--text-pure);
      max-width: 1000px;
      margin: 0 auto 24px;
    }

    /* The Nate Herik Signature Italic Serif Accent */
    .editorial-italic-accent {
      font-family: var(--font-editorial);
      font-weight: 600;
      font-style: italic;
      color: #F97316;
      letter-spacing: normal;
      background: linear-gradient(135deg, #F97316 0%, #FBBF24 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      display: inline-block;
      padding: 0 6px;
    }

    .hero-description-copy {
      font-size: clamp(16px, 2.1vw, 20px);
      color: var(--text-muted);
      max-width: 820px;
      margin: 0 auto 40px;
      line-height: 1.8;
      font-weight: 400;
    }

    /* Store Badges Row */
    .store-badges-grid {
      display: flex;
      justify-content: center;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 70px;
    }

    .store-capsule {
      display: flex;
      align-items: center;
      gap: 14px;
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      box-shadow: var(--specular-line), 0 12px 28px rgba(0, 0, 0, 0.4);
      padding: 12px 22px;
      border-radius: var(--radius-md);
      min-width: 210px;
      text-decoration: none;
      color: inherit;
      position: relative;
      overflow: hidden;
      transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      backdrop-filter: blur(14px);
    }

    .store-capsule:hover {
      transform: translateY(-3px);
      border-color: var(--card-border-hover);
      box-shadow: var(--specular-line), 0 16px 36px rgba(0, 0, 0, 0.6), 0 0 20px rgba(52, 211, 153, 0.15);
    }

    .store-capsule-icon {
      font-size: 26px;
      width: 40px;
      height: 40px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(255, 255, 255, 0.04);
      border-radius: 12px;
      flex-shrink: 0;
    }

    .store-meta-labels {
      text-align: start;
    }

    .store-meta-sub {
      font-size: 11px;
      color: var(--text-dim);
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .store-meta-name {
      font-size: 15px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .badge-soon-pill {
      background: rgba(245, 158, 11, 0.14);
      border: 1px solid rgba(245, 158, 11, 0.35);
      color: var(--amber);
      font-size: 10px;
      font-weight: 800;
      padding: 2px 7px;
      border-radius: 6px;
    }

    /* Live Interactive Product Stage */
    .interactive-stage-card {
      max-width: 980px;
      margin: 0 auto 90px;
      background: linear-gradient(180deg, rgba(20, 23, 31, 0.85) 0%, rgba(11, 13, 18, 0.98) 100%);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-xl);
      box-shadow: 0 30px 80px rgba(0, 0, 0, 0.75), 0 0 50px rgba(52, 211, 153, 0.12), var(--specular-line);
      overflow: hidden;
      position: relative;
    }

    .stage-top-window-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 18px 28px;
      background: rgba(14, 16, 21, 0.9);
      border-bottom: 1px solid var(--card-border);
    }

    .window-traffic-lights {
      display: flex;
      gap: 8px;
    }

    .light-dot {
      width: 11px;
      height: 11px;
      border-radius: 50%;
    }
    .light-dot.red { background: #FF5F56; }
    .light-dot.yellow { background: #FFBD2E; }
    .light-dot.green { background: #27C93F; }

    .stage-tab-controls {
      display: flex;
      gap: 8px;
      background: rgba(255, 255, 255, 0.04);
      padding: 4px;
      border-radius: 12px;
      border: 1px solid var(--card-border);
    }

    .stage-tab-trigger {
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

    .stage-tab-trigger.active {
      background: rgba(52, 211, 153, 0.16);
      color: var(--emerald-glow);
      box-shadow: 0 2px 10px rgba(52, 211, 153, 0.15);
    }

    .stage-tab-trigger:hover:not(.active) {
      color: var(--text-pure);
      background: rgba(255, 255, 255, 0.05);
    }

    .stage-viewport-area {
      padding: 34px 30px;
    }

    .tab-view-pane {
      display: none;
    }
    .tab-view-pane.active {
      display: block;
      animation: fadeInSmooth 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    }

    @keyframes fadeInSmooth {
      from { opacity: 0; transform: translateY(6px); }
      to { opacity: 1; transform: translateY(0); }
    }

    /* Tab 1: Payday Simulator */
    .sim-panel-box {
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 26px;
      box-shadow: var(--specular-line);
    }

    .sim-meta-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 20px;
      flex-wrap: wrap;
      gap: 12px;
    }

    .sim-heading-title {
      font-size: 16px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .slider-track-wrap {
      margin-bottom: 24px;
    }

    .slider-extremes {
      display: flex;
      justify-content: space-between;
      font-size: 13px;
      color: var(--text-muted);
      margin-bottom: 10px;
    }

    .slider-extremes strong {
      color: var(--emerald-glow);
      font-size: 15px;
    }

    .custom-range-slider {
      width: 100%;
      height: 8px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.1);
      outline: none;
      -webkit-appearance: none;
      cursor: pointer;
    }

    .custom-range-slider::-webkit-slider-thumb {
      -webkit-appearance: none;
      appearance: none;
      width: 24px;
      height: 24px;
      border-radius: 50%;
      background: var(--emerald-glow);
      box-shadow: 0 0 16px var(--emerald-glow);
      cursor: grab;
      border: 2px solid #FFFFFF;
      transition: transform 0.1s ease;
    }

    .custom-range-slider::-webkit-slider-thumb:hover {
      transform: scale(1.15);
    }

    .sim-metrics-trio {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 16px;
    }

    .metric-slab {
      background: var(--card-elevated);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-md);
      padding: 18px;
      position: relative;
      overflow: hidden;
      box-shadow: var(--specular-line);
    }

    .metric-slab::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      width: 4px;
      height: 100%;
    }
    .metric-slab.emerald::before { background: var(--emerald-glow); }
    .metric-slab.cyan::before { background: var(--cyan-glow); }
    .metric-slab.amber::before { background: var(--amber); }

    .metric-lbl {
      font-size: 12px;
      color: var(--text-muted);
      margin-bottom: 6px;
      font-weight: 600;
    }

    .metric-val {
      font-size: 23px;
      font-weight: 800;
      color: var(--text-pure);
      line-height: 1.2;
    }

    .metric-sub {
      font-size: 11px;
      color: var(--text-dim);
      margin-top: 6px;
    }

    /* Tab 2: AI Assistant Simulator */
    .ai-chat-preview-box {
      display: flex;
      flex-direction: column;
      gap: 14px;
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 24px;
    }

    .chat-bubble-sender {
      align-self: flex-start;
      background: rgba(56, 189, 248, 0.12);
      border: 1px solid rgba(56, 189, 248, 0.3);
      padding: 12px 18px;
      border-radius: 18px 18px 4px 18px;
      font-size: 14px;
      color: #E0F2FE;
      max-width: 80%;
    }

    body.lang-en .chat-bubble-sender {
      border-radius: 18px 18px 18px 4px;
    }

    .chat-bubble-response {
      align-self: flex-end;
      background: rgba(52, 211, 153, 0.08);
      border: 1px solid rgba(52, 211, 153, 0.3);
      border-radius: 18px 18px 18px 4px;
      padding: 18px;
      width: 90%;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }

    body.lang-en .chat-bubble-response {
      border-radius: 18px 18px 4px 18px;
    }

    .ai-parsed-card {
      background: #090B0E;
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 14px;
      padding: 16px;
      margin-top: 10px;
    }

    .ai-card-title-row {
      font-size: 15px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      justify-content: space-between;
      margin-bottom: 12px;
    }

    .tag-badge {
      font-size: 11px;
      font-weight: 700;
      padding: 3px 8px;
      border-radius: 6px;
      display: inline-flex;
      align-items: center;
      gap: 4px;
    }

    .tag-badge.cat { background: rgba(168, 85, 247, 0.15); color: #C084FC; border: 1px solid rgba(168, 85, 247, 0.3); }
    .tag-badge.sub { background: rgba(56, 189, 248, 0.15); color: #7DD3FC; border: 1px solid rgba(56, 189, 248, 0.3); }
    .tag-badge.paid { background: rgba(52, 211, 153, 0.15); color: #34D399; border: 1px solid rgba(52, 211, 153, 0.3); }
    .tag-badge.for { background: rgba(245, 158, 11, 0.15); color: #FBBF24; border: 1px solid rgba(245, 158, 11, 0.3); }

    .tag-cluster {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 8px;
    }

    /* Tab 3: ZATCA Scanner */
    .zatca-viewfinder-pane {
      background: radial-gradient(circle at center, rgba(14, 20, 28, 0.8) 0%, #080A0D 100%);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 30px;
      display: flex;
      flex-direction: column;
      align-items: center;
      position: relative;
      overflow: hidden;
    }

    .laser-beam-line {
      position: absolute;
      top: 0;
      left: 10%;
      right: 10%;
      height: 2px;
      background: linear-gradient(90deg, transparent, var(--emerald-glow), var(--cyan-glow), transparent);
      box-shadow: 0 0 16px var(--emerald-glow), 0 0 30px var(--cyan-glow);
      animation: laserSweep 3s ease-in-out infinite alternate;
    }

    @keyframes laserSweep {
      0% { top: 15%; opacity: 0.3; }
      50% { opacity: 1; }
      100% { top: 85%; opacity: 0.3; }
    }

    .zatca-preview-layout {
      display: grid;
      grid-template-columns: 140px 1fr;
      gap: 24px;
      align-items: center;
      width: 100%;
      max-width: 620px;
      background: var(--card-elevated);
      border: 1px solid rgba(52, 211, 153, 0.3);
      border-radius: 18px;
      padding: 22px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
    }

    .qr-canvas-box {
      width: 130px;
      height: 130px;
      background: #FFFFFF;
      border-radius: 12px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 8px;
    }

    .qr-canvas-box svg {
      width: 100%;
      height: 100%;
    }

    .zatca-parsed-rows h5 {
      font-size: 16px;
      font-weight: 800;
      color: #FFFFFF;
      margin-bottom: 6px;
    }

    .zatca-data-line {
      display: flex;
      justify-content: space-between;
      font-size: 13px;
      color: var(--text-muted);
      padding: 4px 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.05);
    }

    .zatca-data-line strong {
      color: var(--text-pure);
    }

    /* Tab 4: 2D Partner Split */
    .partner-split-pane {
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 26px;
    }

    .split-meter-bar {
      height: 14px;
      background: rgba(255, 255, 255, 0.08);
      border-radius: 999px;
      display: flex;
      overflow: hidden;
      margin: 16px 0 24px;
    }

    .split-share-you {
      background: linear-gradient(90deg, #34D399, #059669);
      transition: width 0.3s ease;
    }

    .split-share-partner {
      background: linear-gradient(90deg, #38BDF8, #0284C7);
      transition: width 0.3s ease;
    }

    .dependents-pill-row {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 16px;
    }

    .child-dep-chip {
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

    /* Key Metric Counters (Zero SMS / Zero Banking References) */
    .metric-counter-strip {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 20px;
      margin-bottom: 100px;
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      box-shadow: var(--specular-line);
      border-radius: var(--radius-lg);
      padding: 32px 28px;
    }

    .counter-cell {
      text-align: center;
      position: relative;
    }

    .counter-cell:not(:last-child)::after {
      content: '';
      position: absolute;
      top: 15%;
      bottom: 15%;
      right: 0;
      width: 1px;
      background: var(--card-border);
    }

    body.lang-en .counter-cell:not(:last-child)::after {
      right: auto;
      left: 100%;
    }

    .counter-number {
      font-size: 38px;
      font-weight: 900;
      letter-spacing: -0.03em;
      color: var(--text-pure);
      line-height: 1.1;
      margin-bottom: 6px;
    }

    .counter-number .accent {
      color: var(--emerald-glow);
    }

    .counter-label {
      font-size: 13px;
      color: var(--text-muted);
      font-weight: 600;
    }

    /* 12-Pillar Bento Grid */
    .section-header-block {
      text-align: center;
      margin-bottom: 56px;
    }

    .section-eyebrow-text {
      font-size: 12px;
      font-weight: 800;
      color: var(--emerald-glow);
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 12px;
      display: block;
    }

    .section-main-heading {
      font-size: clamp(28px, 4vw, 44px);
      font-weight: 900;
      color: var(--text-pure);
      line-height: 1.25;
      letter-spacing: -0.02em;
      margin-bottom: 16px;
    }

    .section-lead-copy {
      font-size: 17px;
      color: var(--text-muted);
      max-width: 680px;
      margin: 0 auto;
    }

    .asymmetric-bento-grid {
      display: grid;
      grid-template-columns: repeat(12, 1fr);
      gap: 24px;
      margin-bottom: 120px;
    }

    .bento-surface-card {
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      box-shadow: var(--specular-line), 0 20px 40px rgba(0, 0, 0, 0.35);
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

    .bento-surface-card:hover {
      background: var(--card-elevated);
      transform: translateY(-5px);
      border-color: var(--card-border-hover);
      box-shadow: var(--specular-line), 0 25px 60px rgba(0, 0, 0, 0.5), 0 0 30px rgba(52, 211, 153, 0.12);
    }

    .span-col-8 { grid-column: span 8; }
    .span-col-4 { grid-column: span 4; }
    .span-col-6 { grid-column: span 6; }
    .span-col-12 { grid-column: span 12; }

    .bento-icon-cell {
      width: 52px;
      height: 52px;
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 26px;
      margin-bottom: 22px;
      border: 1px solid var(--card-border);
    }

    .bento-icon-cell.emerald { background: var(--emerald-dim); border-color: rgba(52, 211, 153, 0.3); color: var(--emerald-glow); }
    .bento-icon-cell.cyan { background: rgba(56, 189, 248, 0.12); border-color: rgba(56, 189, 248, 0.3); color: var(--cyan-glow); }
    .bento-icon-cell.amber { background: rgba(245, 158, 11, 0.12); border-color: rgba(245, 158, 11, 0.3); color: var(--amber); }
    .bento-icon-cell.purple { background: rgba(168, 85, 247, 0.12); border-color: rgba(168, 85, 247, 0.3); color: var(--purple); }

    .bento-card-title {
      font-size: 20px;
      font-weight: 800;
      color: var(--text-pure);
      margin-bottom: 12px;
      line-height: 1.3;
    }

    .bento-card-desc {
      font-size: 15px;
      color: var(--text-muted);
      line-height: 1.75;
      margin-bottom: 20px;
    }

    .bento-tag-pills {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }

    .subtle-badge-chip {
      font-size: 11px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      color: var(--text-muted);
    }

    /* Privacy & Security Comparison Section */
    .security-matrix-card {
      background: linear-gradient(180deg, rgba(16, 19, 26, 0.7) 0%, rgba(9, 11, 15, 0.95) 100%);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-xl);
      padding: 48px 40px;
      margin-bottom: 120px;
      box-shadow: var(--specular-line);
    }

    .matrix-item-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 30px;
      margin-top: 36px;
    }

    .matrix-cell-wrap {
      display: flex;
      gap: 16px;
      align-items: flex-start;
    }

    .verified-check-mark {
      width: 28px;
      height: 28px;
      border-radius: 8px;
      background: rgba(52, 211, 153, 0.15);
      border: 1px solid var(--emerald-glow);
      color: var(--emerald-glow);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      font-weight: 900;
      flex-shrink: 0;
      margin-top: 2px;
    }

    .matrix-cell-text h4 {
      font-size: 16px;
      font-weight: 800;
      color: var(--text-pure);
      margin-bottom: 4px;
    }

    .matrix-cell-text p {
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.6;
    }

    /* FAQ Accordion */
    .faq-wrapper-block {
      max-width: 860px;
      margin: 0 auto 120px;
    }

    .faq-accordion-item {
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-md);
      margin-bottom: 14px;
      box-shadow: var(--specular-line);
      overflow: hidden;
      transition: all 0.25s ease;
    }

    .faq-accordion-item.active {
      border-color: rgba(52, 211, 153, 0.35);
      background: var(--card-elevated);
    }

    .faq-header-trigger {
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

    .faq-plus-icon {
      font-size: 18px;
      color: var(--emerald-glow);
      transition: transform 0.25s ease;
    }

    .faq-accordion-item.active .faq-plus-icon {
      transform: rotate(45deg);
    }

    .faq-body-collapse {
      display: none;
      padding: 0 26px 22px;
      color: var(--text-muted);
      font-size: 15px;
      line-height: 1.8;
      border-top: 1px solid rgba(255, 255, 255, 0.04);
      padding-top: 16px;
    }

    .faq-accordion-item.active .faq-body-collapse {
      display: block;
    }

    /* Legal Section */
    .legal-modal-strip {
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-lg);
      padding: 40px 36px;
      margin-bottom: 100px;
      box-shadow: var(--specular-line);
    }

    .legal-selector-tabs {
      display: flex;
      gap: 12px;
      border-bottom: 1px solid var(--card-border);
      padding-bottom: 16px;
      margin-bottom: 24px;
    }

    .legal-tab-action {
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

    .legal-tab-action.active {
      color: var(--emerald-glow);
      background: rgba(52, 211, 153, 0.1);
    }

    .legal-scroll-pane {
      max-height: 280px;
      overflow-y: auto;
      padding-right: 14px;
      font-size: 14px;
      color: var(--text-muted);
      line-height: 1.8;
    }

    .legal-scroll-pane h4 {
      color: var(--text-pure);
      margin: 16px 0 8px;
      font-size: 15px;
    }

    /* Contact Banner */
    .contact-cta-hero {
      background: radial-gradient(circle at top right, rgba(52, 211, 153, 0.16) 0%, rgba(249, 115, 22, 0.08) 50%, transparent 80%), var(--card-surface);
      border: 1px solid rgba(52, 211, 153, 0.35);
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.6), 0 0 50px rgba(52, 211, 153, 0.15), var(--specular-line);
      border-radius: var(--radius-xl);
      padding: 56px 36px;
      text-align: center;
      margin-bottom: 100px;
      position: relative;
      overflow: hidden;
    }

    .contact-heading-text {
      font-size: clamp(24px, 3.5vw, 36px);
      font-weight: 900;
      color: var(--text-pure);
      margin-bottom: 14px;
    }

    .contact-copy-text {
      color: var(--text-muted);
      font-size: 16px;
      max-width: 640px;
      margin: 0 auto 32px;
      line-height: 1.7;
    }

    .contact-email-capsule {
      display: inline-flex;
      align-items: center;
      gap: 12px;
      background: #060709;
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

    .contact-email-capsule:hover {
      border-color: var(--emerald-glow);
      background: rgba(52, 211, 153, 0.1);
      color: var(--emerald-glow);
      transform: translateY(-2px);
      box-shadow: 0 15px 35px rgba(52, 211, 153, 0.25);
    }

    /* Minimalist Footer */
    footer {
      border-top: 1px solid var(--card-border);
      padding: 48px 0 60px;
      text-align: center;
      color: var(--text-dim);
      font-size: 14px;
    }

    .footer-link-group {
      display: flex;
      justify-content: center;
      gap: 28px;
      margin-bottom: 18px;
      flex-wrap: wrap;
    }

    .footer-link-group a {
      color: var(--text-muted);
      text-decoration: none;
      font-weight: 600;
      transition: color 0.2s ease;
    }

    .footer-link-group a:hover {
      color: var(--emerald-glow);
    }

    /* Responsive adjustments */
    @media (max-width: 992px) {
      .span-col-8, .span-col-4, .span-col-6 { grid-column: span 12; }
      .zatca-preview-layout { grid-template-columns: 1fr; justify-items: center; text-align: center; }
      .nav-links-menu { display: none; }
      .counter-cell:not(:last-child)::after { display: none; }
    }

    @media (max-width: 768px) {
      .hero-container { padding: 60px 0 30px; }
      .stage-top-window-bar { flex-direction: column; gap: 14px; }
      .stage-tab-controls { width: 100%; overflow-x: auto; justify-content: flex-start; }
      .store-capsule { width: 100%; justify-content: center; }
      .security-matrix-card { padding: 32px 20px; }
      .contact-cta-hero { padding: 36px 20px; }
      .metric-counter-strip { grid-template-columns: 1fr 1fr; }
    }
  </style>
</head>
<body id="page-body">

  <div class="cinematic-backdrop">
    <div class="volumetric-light-ray"></div>
  </div>
  <div class="ambient-dot-grid"></div>

  <!-- Header -->
  <header>
    <div class="container nav-inner">
      <a href="/" class="brand-group">
        <div class="brand-logo-pill">💎</div>
        <div class="brand-title-wrap">
          <h1>Budget Tracker</h1>
          <span class="brand-dot">•</span>
          <span style="font-size: 11px; font-weight: 700; color: #34D399; text-transform: uppercase;" data-i18n="navBrandSub">ميزانية الأسرة</span>
        </div>
      </a>

      <ul class="nav-links-menu">
        <li><a href="#stage" data-i18n="navSim">المحاكي التفاعلي</a></li>
        <li><a href="#metrics" data-i18n="navMetrics">المؤشرات</a></li>
        <li><a href="#features" data-i18n="navFeat">المميزات</a></li>
        <li><a href="#security" data-i18n="navSec">الأمان والخصوصية</a></li>
        <li><a href="#faq" data-i18n="navFaq">الأسئلة الشائعة</a></li>
        <li><a href="#contact" data-i18n="navContact">الدعم الفني</a></li>
      </ul>

      <div class="nav-actions-right">
        <!-- Segmented Language Switcher -->
        <div class="segmented-lang-control">
          <button class="lang-segment-btn active" id="btn-lang-ar" onclick="setLanguage('ar')">العربية</button>
          <button class="lang-segment-btn" id="btn-lang-en" onclick="setLanguage('en')">English</button>
        </div>
        <a href="#stage" class="nav-cta-pill" data-i18n="navCta">جرب المحاكي</a>
      </div>
    </div>
  </header>

  <!-- Hero Section (Cinematic Editorial) -->
  <main class="container">
    <section class="hero-container">
      <div class="hero-kicker-badge">
        <span class="kicker-ping-point"></span>
        <span data-i18n="heroBadgeText">الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية</span>
      </div>

      <h2 class="hero-headline-main">
        <span data-i18n="heroH1Prefix">تحكّم مطلق في ميزانية أسرتك بـ</span>
        <span class="editorial-italic-accent" data-i18n="heroH1Italic">ذكاء فائق.</span>
      </h2>

      <p class="hero-description-copy" data-i18n="heroDesc">
        صُمم خصيصاً ليواكب واقع الأسر في السعودية. حدد يوم نزول راتبك بكل حرية (اليوم 1، 15، 25، 27 أو أي تاريخ يناسبك)، مع مسح فواتير ZATCA بالذكاء الاصطناعي، ومساعد الشات التفاعلي، وتوزيع المصاريف بعدالة بين الشركاء والأبناء دون أي عناء.
      </p>

      <!-- Store Badges & Actions -->
      <div class="store-badges-grid">
        <!-- Google Play -->
        <div class="store-capsule">
          <div class="store-capsule-icon">🤖</div>
          <div class="store-meta-labels">
            <div class="store-meta-sub" data-i18n="stGoogleSub">متوفر قريباً على</div>
            <div class="store-meta-name">
              Google Play <span class="badge-soon-pill" data-i18n="chip1">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Apple App Store -->
        <div class="store-capsule">
          <div class="store-capsule-icon">🍎</div>
          <div class="store-meta-labels">
            <div class="store-meta-sub" data-i18n="stAppleSub">متوفر قريباً على</div>
            <div class="store-meta-name">
              App Store <span class="badge-soon-pill" data-i18n="chip2">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Huawei AppGallery -->
        <div class="store-capsule">
          <div class="store-capsule-icon">🛍️</div>
          <div class="store-meta-labels">
            <div class="store-meta-sub" data-i18n="stHuaweiSub">متوفر قريباً على</div>
            <div class="store-meta-name">
              AppGallery <span class="badge-soon-pill" data-i18n="chip3">قريباً</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Live Interactive Product Stage -->
      <div class="interactive-stage-card" id="stage">
        <div class="stage-top-window-bar">
          <div class="window-traffic-lights">
            <div class="light-dot red"></div>
            <div class="light-dot yellow"></div>
            <div class="light-dot green"></div>
          </div>

          <div class="stage-tab-controls">
            <button class="stage-tab-trigger active" id="tab-sim-btn-1" onclick="switchSimTab('payday')">
              📅 <span data-i18n="tabT1">محاكي دورة الراتب</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-2" onclick="switchSimTab('ai')">
              ✨ <span data-i18n="tabT2">مساعد الشات الذكي</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-3" onclick="switchSimTab('zatca')">
              🧾 <span data-i18n="tabT3">ماسح فواتير ZATCA</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-4" onclick="switchSimTab('partner')">
              👥 <span data-i18n="tabT4">تقسيم الشركاء والأبناء</span>
            </button>
          </div>
        </div>

        <div class="stage-viewport-area">
          <!-- Tab 1: Payday Engine Simulator -->
          <div id="sim-panel-payday" class="tab-view-pane active">
            <div class="sim-panel-box">
              <div class="sim-meta-header">
                <div class="sim-heading-title">
                  <span>⚙️</span>
                  <span data-i18n="simTitleTxt">اختر يوم نزول راتبك الشهري (مرن 100% لأي قطاع)</span>
                </div>
                <div id="sim-shift-badge" class="badge-soon-pill" style="font-size: 12px; padding: 4px 10px; background: rgba(52, 211, 153, 0.15); border-color: rgba(52, 211, 153, 0.35); color: #34D399;" data-i18n="simShiftBadge">
                  ✓ نظام موازنة العطلات التلقائي نشط
                </div>
              </div>

              <div class="slider-track-wrap">
                <div class="slider-extremes">
                  <span data-i18n="sliderMinLbl">اليوم 1 في الشهر</span>
                  <span><span data-i18n="sliderCurrLbl">يوم الراتب المحدد:</span> <strong id="slider-curr-val">27</strong></span>
                  <span data-i18n="sliderMaxLbl">اليوم 31 في الشهر</span>
                </div>
                <input type="range" min="1" max="31" value="27" class="custom-range-slider" id="payday-range" oninput="updatePaydaySim(this.value)">
              </div>

              <div class="sim-metrics-trio">
                <div class="metric-slab emerald">
                  <div class="metric-lbl" data-i18n="simLblDays">الأيام المتبقية في الدورة</div>
                  <div class="metric-val" id="sim-val-days">16 <small style="font-size: 13px;">يوم</small></div>
                  <div class="metric-sub" data-i18n="simSubDays">دورة نشطة متوازنة</div>
                </div>

                <div class="metric-slab cyan">
                  <div class="metric-lbl" data-i18n="simLblSafe">معدل الصرف اليومي الآمن</div>
                  <div class="metric-val" id="sim-val-safe">345 <small style="font-size: 13px;">ر.س / يوم</small></div>
                  <div class="metric-sub" data-i18n="simSubSafe">يحميك من نفاد الميزانية قبل الراتب</div>
                </div>

                <div class="metric-slab amber">
                  <div class="metric-lbl" data-i18n="simLblReserve">احتياطي الادخار التلقائي</div>
                  <div class="metric-val" id="sim-val-reserve">4,500 <small style="font-size: 13px;">ر.س</small></div>
                  <div class="metric-sub" data-i18n="simSubReserve">فائض غير مخصص يُحفظ للطوارئ</div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 2: AI Chat Simulator -->
          <div id="sim-panel-ai" class="tab-view-pane">
            <div class="ai-chat-preview-box">
              <div class="chat-bubble-sender" id="chat-u-msg" data-i18n="chatUMsg">
                "عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة"
              </div>
              <div class="chat-bubble-response">
                <div style="font-size: 12px; color: #34D399; font-weight: 700; margin-bottom: 6px;">
                  🤖 <span data-i18n="chatAiHeader">تم استخراج المصروف بالذكاء الاصطناعي بدقة</span>
                </div>
                <div class="ai-parsed-card">
                  <div class="ai-card-title-row">
                    <span data-i18n="aiCardMerchant">مطعم البيك (وجبة عائلية)</span>
                    <span style="color: #34D399;">68.00 ر.س</span>
                  </div>
                  <div class="tag-cluster">
                    <span class="tag-badge cat" data-i18n="aiTagCat">🍔 المطاعم والتغذية</span>
                    <span class="tag-badge sub" data-i18n="aiTagSub">🍟 وجبات سريعة</span>
                    <span class="tag-badge paid" data-i18n="aiTagPaid">👤 المدفوع بواسطة: أنا</span>
                    <span class="tag-badge for" data-i18n="aiTagFor">👨‍👩‍👧 المستفيد: الأسرة</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 3: ZATCA Scanner Viewfinder -->
          <div id="sim-panel-zatca" class="tab-view-pane">
            <div class="zatca-viewfinder-pane">
              <div class="laser-beam-line"></div>
              <div class="zatca-preview-layout">
                <div class="qr-canvas-box">
                  <svg viewBox="0 0 100 100">
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
                <div class="zatca-parsed-rows" style="text-align: start; width: 100%;">
                  <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <span class="badge-soon-pill" style="background: rgba(52, 211, 153, 0.15); border-color: rgba(52, 211, 153, 0.35); color: #34D399;" data-i18n="zatcaComplianceTag">
                      ✓ متوافق مع هيئة الزكاة والضريبة والجمارك (المرحلة 2)
                    </span>
                  </div>
                  <h5 data-i18n="zatcaMerchantName">شركة أسواق بندة للتجزئة</h5>
                  <div class="zatca-data-line">
                    <span data-i18n="zLblTax">الرقم الضريبي:</span>
                    <strong>300055489200003</strong>
                  </div>
                  <div class="zatca-data-line">
                    <span data-i18n="zLblVat">ضريبة القيمة المضافة (15%):</span>
                    <strong style="color: #F59E0B;">32.40 ر.س</strong>
                  </div>
                  <div class="zatca-data-line">
                    <span data-i18n="zLblTot">الإجمالي شامل الضريبة:</span>
                    <strong style="color: #34D399;">248.40 ر.س</strong>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 4: Partner & Dependents Settlement -->
          <div id="sim-panel-partner" class="tab-view-pane">
            <div class="partner-split-pane">
              <div class="sim-meta-header">
                <div class="sim-heading-title">
                  <span>⚖️</span>
                  <span data-i18n="partTitleTxt">حاسبة التسوية ثنائية الأبعاد وتتبع مصاريف الأبناء</span>
                </div>
                <div class="badge-soon-pill" id="part-badge" data-i18n="partBadge">نسبة عادلة 50% / 50%</div>
              </div>

              <div class="split-meter-bar">
                <div class="split-share-you" id="ratio-bar-you" style="width: 50%;"></div>
                <div class="split-share-partner" id="ratio-bar-partner" style="width: 50%;"></div>
              </div>

              <div class="sim-metrics-trio">
                <div class="metric-slab emerald">
                  <div class="metric-lbl" data-i18n="partLblNet">صافي التسوية بين الشركاء</div>
                  <div class="metric-val" style="color: #34D399;"><span data-i18n="partValNet">+380 ر.س مستحق لك</span></div>
                  <div class="metric-sub" data-i18n="partSubNet">تمت الحسبة التلقائية لجميع فواتير الشهر</div>
                </div>

                <div class="metric-slab cyan">
                  <div class="metric-lbl" data-i18n="partLblKids">مجموع نفقات الأبناء هذا الشهر</div>
                  <div class="metric-val"><span data-i18n="partValKids">1,240 ر.س</span></div>
                  <div class="metric-sub" data-i18n="partSubKids">مدارس، أنشطة، ورعاية صحية</div>
                </div>
              </div>

              <div class="dependents-pill-row">
                <span style="font-size: 13px; color: var(--text-muted); align-self: center;" data-i18n="partLblTag">المستفيدون المخصصون:</span>
                <span class="child-dep-chip" data-i18n="childTag1">👧 سارة (مستلزمات مدرسية: 520 ر.س)</span>
                <span class="child-dep-chip" data-i18n="childTag2">👦 عمر (أنشطة رياضية: 430 ر.س)</span>
                <span class="child-dep-chip" data-i18n="childTag3">👶 فهد (تطعيمات وتموين: 290 ر.س)</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Metric Counters Bar (Zero SMS & Banking) -->
      <div class="metric-counter-strip" id="metrics">
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">100</span>%</div>
          <div class="counter-label" data-i18n="cntLbl1">يعمل بدون اتصال (Offline-First)</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">100</span>%</div>
          <div class="counter-label" data-i18n="cntLbl2">خصوصية تامة وعزل مشفر للأسرة</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number">&lt;<span class="accent">0.8</span>s</div>
          <div class="counter-label" data-i18n="cntLbl3">سرعة فك تشفير فواتير ZATCA TLV</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">31</span>/31</div>
          <div class="counter-label" data-i18n="cntLbl4">مرونة تامة لأي يوم راتب تختاره</div>
        </div>
      </div>
    </section>

    <!-- 12-Pillar Bento Grid Section -->
    <section id="features">
      <div class="section-header-block">
        <span class="section-eyebrow-text" data-i18n="featEyebrow">منظومة مالية شاملة</span>
        <h3 class="section-main-heading" data-i18n="featH2">كل ما تحتاجه الأسرة السعودية في تطبيق واحد</h3>
        <p class="section-lead-copy" data-i18n="featSub">
          تم بناء كل ميزة لحل تحديات مالية حقيقية يواجهها الأفراد والأسر في المملكة مع تجربة مستخدم تتسم بالسهولة والجمال.
        </p>
      </div>

      <div class="asymmetric-bento-grid">
        <!-- 1. Flexible Salary Engine -->
        <div class="bento-surface-card span-col-8">
          <div>
            <div class="bento-icon-cell emerald">📅</div>
            <h4 class="bento-card-title" data-i18n="f1T">دورة راتب مرنة وقواعد الصرف التلقائية</h4>
            <p class="bento-card-desc" data-i18n="f1D">
              سواء كنت موظفاً حكومياً، أو في القطاع الخاص، أو تمارس عملاً حراً؛ حدد يوم راتبك الشهري بكل حرية. يطبق التطبيق نظام موازنة مواعيد الصرف التلقائي للعطلات الأسبوعية مع احتساب معدل الصرف اليومي الآمن لتفادي نفاد الراتب مبكراً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f1Tag1">تعديل أي يوم في الشهر</span>
            <span class="subtle-badge-chip" data-i18n="f1Tag2">موازنة العطلات الأسبوعية</span>
            <span class="subtle-badge-chip" data-i18n="f1Tag3">معدل الصرف اليومي الآمن</span>
          </div>
        </div>

        <!-- 2. Conversational Saudi AI -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell cyan">✨</div>
            <h4 class="bento-card-title" data-i18n="f2T">مساعد ذكي يفهم اللهجة السعودية</h4>
            <p class="bento-card-desc" data-i18n="f2D">
              سجّل مشترياتك صوتياً أو كتابياً باللهجة المحلية أو الفصحى أو الإنجليزية. يفهم السياق فورياً ("عبيت بنزين 91 بـ 85 ريال") ويصنّفها بدقة متناهية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f2Tag1">شات فوري</span>
            <span class="subtle-badge-chip" data-i18n="f2Tag2">تعرّف باللهجة</span>
          </div>
        </div>

        <!-- 3. Two-Tier Taxonomy & Hybrid LLM Subcategories -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell purple">📂</div>
            <h4 class="bento-card-title" data-i18n="f3T">تصنيف هجين ثنائي المستويات</h4>
            <p class="bento-card-desc" data-i18n="f3D">
              تصنيفات رئيسية وفرعية دقيقة (مثل: المطاعم > وجبات سريعة أو كافيهات). يختار الذكاء الاصطناعي التصنيف الفرعي الأنسب مع بطاقة تأكيد تفاعلية تتيح لك التعديل بمرونة.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f3Tag1">تصنيف فرعي ذكي</span>
            <span class="subtle-badge-chip" data-i18n="f3Tag2">بطاقة تأكيد قبل الحفظ</span>
          </div>
        </div>

        <!-- 4. ZATCA Phase 2 QR Scanner -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell emerald">🧾</div>
            <h4 class="bento-card-title" data-i18n="f4T">ماسح فواتير ZATCA المرحلة الثانية</h4>
            <p class="bento-card-desc" data-i18n="f4D">
              وجّه الكاميرا إلى أي فاتورة إلكترونية لفك شفرة رمز الاستجابة السريعة (Base64 TLV) بدقة 100% واستخراج اسم التاجر، الرقم الضريبي، وضريبة القيمة المضافة فورياً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f4Tag1">تشفير TLV</span>
            <span class="subtle-badge-chip" data-i18n="f4Tag2">احتساب الضريبة 15%</span>
          </div>
        </div>

        <!-- 5. 2D Partner Fair-Share Split -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell amber">👥</div>
            <h4 class="bento-card-title" data-i18n="f5T">تقسيم عادل بين الشركاء</h4>
            <p class="bento-card-desc" data-i18n="f5D">
              نظام توثيق ثنائي الأبعاد يرصد "من دفع" و"من استفاد" مع نسبة مخصصة للتقاسم لحساب التسويات الصافية والديون المتبادلة دون أي إحراج مالي.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f5Tag1">رمز دعوة عائلي</span>
            <span class="subtle-badge-chip" data-i18n="f5Tag2">تسوية ديون فورية</span>
          </div>
        </div>

        <!-- 6. Children & Dependents Tracking -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell cyan">👶</div>
            <h4 class="bento-card-title" data-i18n="f6T">تتبع نفقات الأبناء والتابعين</h4>
            <p class="bento-card-desc" data-i18n="f6D">
              أضف أسماء الأبناء في إعدادات الأسرة وخصّص الفواتير لكل ابن (مصاريف المدارس، الأنشطة، المستلزمات الطبية) لمعرفة التكلفة الفعلية لكل فرد بدقة.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f6Tag1">تخصيص لكل طفل</span>
            <span class="subtle-badge-chip" data-i18n="f6Tag2">تقارير نفقات التابعين</span>
          </div>
        </div>

        <!-- 7. BNPL & Installments Tracker -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell purple">💳</div>
            <h4 class="bento-card-title" data-i18n="f7T">متابعة خطط التقسيط (تابي وتمارا)</h4>
            <p class="bento-card-desc" data-i18n="f7D">
              تتبّع خطط التقسيط عبر تابي، تمارا، وبطاقات الدفع مع حلقات تقدم دائرية توضح المتبقي والتنبيه التلقائي قبل مواعيد السداد لتفادي الرسوم.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f7Tag1">تابي & تمارا</span>
            <span class="subtle-badge-chip" data-i18n="f7Tag2">تنبيه مواعيد الأقساط</span>
          </div>
        </div>

        <!-- 8. Recurring Bills & Cadence Engine -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell amber">⚡</div>
            <h4 class="bento-card-title" data-i18n="f8T">جدولة الفواتير والاشتراكات الدورية</h4>
            <p class="bento-card-desc" data-i18n="f8D">
              كشف وجدولة فواتير الكهرباء (SEC)، والمياه (NWC)، والاتصالات (STC/Mobily)، ورسوم الإقامة والتأمين لتجنب الانقطاعات والمفاجآت.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f8Tag1">الكهرباء والمياه</span>
            <span class="subtle-badge-chip" data-i18n="f8Tag2">تجديدات الاشتراكات</span>
          </div>
        </div>

        <!-- 9. Smart Grocery Comparison -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell emerald">🛒</div>
            <h4 class="bento-card-title" data-i18n="f9T">مقارنة أسعار المقاضي وسلة التوفير</h4>
            <p class="bento-card-desc" data-i18n="f9D">
              سجّل مشتريات السوبرماركت وقارن أسعار السلع الأساسية بين سلاسل المتاجر الكبرى في المملكة (بندة، كارفور، لولو، التميمي، الدانوب) لتوفير ما يصل إلى 20% شهرياً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f9Tag1">تتبع تاريخ الأسعار</span>
            <span class="subtle-badge-chip" data-i18n="f9Tag2">سلة المقاضي المثالية</span>
          </div>
        </div>

        <!-- 10. Purchase Affordability Simulator -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell cyan">🧭</div>
            <h4 class="bento-card-title" data-i18n="f10T">حاسبة "هل أستطيع تحمل هذه التكلفة؟"</h4>
            <p class="bento-card-desc" data-i18n="f10D">
              اختبر أي قرار شراء غير مخطط له قبل اتخاذه؛ يحسب التطبيق فورياً أثر الشراء على وتيرة صرف الأيام المتبقية في دورة الراتب وعلى احتياطي الادخار دون إرباك الميزانية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f10Tag1">محاكاة فورية للقرارات</span>
            <span class="subtle-badge-chip" data-i18n="f10Tag2">حماية خطة الشهر</span>
          </div>
        </div>

        <!-- 11. Offline-First SQLite Engine -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell purple">⚡</div>
            <h4 class="bento-card-title" data-i18n="f11T">يعمل بالكامل دون اتصال بالإنترنت</h4>
            <p class="bento-card-desc" data-i18n="f11D">
              قاعدة بيانات SQLite محلية مدمجة تتيح لك تسجيل المصاريف ومسح الفواتير في أي وقت حتى بدون شبكة، مع مزامنة سحابية تلقائية وخوارزمية تشفير تمنع تكرار العمليات.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f11Tag1">مزامنة تلقائية</span>
            <span class="subtle-badge-chip" data-i18n="f11Tag2">تشفير SHA-256</span>
          </div>
        </div>

        <!-- 12. Smart Savings Reserve & PDF Statements -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell amber">📊</div>
            <h4 class="bento-card-title" data-i18n="f12T">احتياطي الادخار وتقارير PDF الشهرية</h4>
            <p class="bento-card-desc" data-i18n="f12D">
              يتحول الفائض غير المخصص تلقائياً إلى صندوق احتياطي الادخار الأسري، مع إمكانية تصدير كشوف حساب شهرية رسمية بصيغة PDF باللغتين العربية والإنجليزية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip" data-i18n="f12Tag1">صندوق طوارئ مالي</span>
            <span class="subtle-badge-chip" data-i18n="f12Tag2">تقارير ضريبية ومالية</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Privacy & Security Comparison Section -->
    <section class="security-matrix-card" id="security">
      <div class="section-header-block" style="margin-bottom: 30px;">
        <span class="section-eyebrow-text" data-i18n="compEyebrow">معايير أمان عالية</span>
        <h3 class="section-main-heading" data-i18n="compH2">خصوصية تامة وعزل مشفر للبيانات</h3>
      </div>

      <div class="matrix-item-grid">
        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 data-i18n="cp1T">عزل تام لبيانات الأسرة (Row-Level Security)</h4>
            <p data-i18n="cp1D">بيانات كل أسرة معزولة ومشفرة سحابياً بقواعد أمان صارمة؛ لا يمكن لأي مستخدم آخر الاطلاع على فلس واحد من مصروفاتكم.</p>
          </div>
        </div>

        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 data-i18n="cp2T">صفر مشاركة مع معلنين أو أطراف ثالثة</h4>
            <p data-i18n="cp2D">لا نبيع بياناتك ولا نشاركها إطلاقاً مع شبكات إعلانية أو وسطاء تجاريين. خصوصيتك المالية مقدسة 100%.</p>
          </div>
        </div>

        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 data-i18n="cp3T">حفظ السجلات بنسبة 100% وعدم الحذف النهائي</h4>
            <p data-i18n="cp3D">التصنيفات غير المستخدمة تتحول إلى حالة "غير نشطة" مع حفظ كامل تاريخ المصروفات والرسوم البيانية السابقة بأمان.</p>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ Accordion -->
    <section class="faq-wrapper-block" id="faq">
      <div class="section-header-block">
        <span class="section-eyebrow-text" data-i18n="faqEyebrow">إجابات واضحة</span>
        <h3 class="section-main-heading" data-i18n="faqH2">الأسئلة الشائعة</h3>
      </div>

      <div class="faq-accordion-item active">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span data-i18n="faqQ1">هل التطبيق محصور بيوم راتب معين (مثل يوم 27)؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" data-i18n="faqA1">
          إطلاقاً! يمكنك ضبط يوم نزول الراتب على أي تاريخ في الشهر (1، 15، 25، 27 أو أي تاريخ يحدده جهة عملك). يتولى المحرك إعادة حساب الأيام المتبقية ومعدل الصرف اليومي الآمن بدقة وفق التاريخ الذي تختاره.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span data-i18n="faqQ2">كيف يتعامل التطبيق مع عطلات نهاية الأسبوع في دورة الراتب؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" data-i18n="faqA2">
          يطبق التطبيق نظام الموازنة التلقائي المعتمد: إذا صادف يوم راتبك يوم الجمعة، يتم تقديم دورة الصرف إلى يوم الخميس. وإذا صادف يوم السبت، يتم ترحيلها إلى يوم الأحد لضمان دقة وتيرة الصرف اليومية.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span data-i18n="faqQ3">هل يمكنني تقسيم المصاريف وتحديد تكلفة كل ابن من أفراد الأسرة؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" data-i18n="faqA3">
          نعم، يدعم التطبيق إدارة أفراد الأسرة وإضافة الأبناء؛ عند تسجيل أي فاتورة يمكنك تحديد من دفع المصروف (أنا أو الشريك) ولمن تم الصرف (أنا، الشريك، أو أحد الأبناء)، ويقوم التطبيق بحساب التسويات الصافية العادلة بدقة.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span data-i18n="faqQ4">هل يمكنني مسح الفواتير الإلكترونية ZATCA دون اتصال بالإنترنت؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" data-i18n="faqA4">
          نعم، فك شفرة Base64 TLV الخاصة بفواتير ZATCA يتم محلياً وبشكل فوري على جهازك وبسرعة فائقة حتى بدون أي اتصال بالإنترنت، ويتم حفظ الفاتورة في قاعدة بيانات SQLite المحلية لحين توفر الشبكة.
        </div>
      </div>
    </section>

    <!-- Legal Section -->
    <section class="legal-modal-strip" id="legal">
      <div class="legal-selector-tabs">
        <button class="legal-tab-action active" id="tab-privacy-btn" onclick="switchLegalTab('privacy')" data-i18n="tabPrivacyBtn">سياسة الخصوصية</button>
        <button class="legal-tab-action" id="tab-terms-btn" onclick="switchLegalTab('terms')" data-i18n="tabTermsBtn">شروط الاستخدام</button>
      </div>

      <div id="privacy-pane" class="legal-scroll-pane">
        <h4 data-i18n="lp1">1. الالتزام الصارم بالخصوصية</h4>
        <p data-i18n="lp1Txt">نحن في Budget Tracker نضع حماية بياناتك المالية فوق كل اعتبار. يتم عزل وتشفير بيانات كل أسرة سحابياً بأحدث معايير الأمان وقواعد Row-Level Security.</p>
        
        <h4 data-i18n="lp2">2. البيانات المُعالجة</h4>
        <p data-i18n="lp2Txt">يقتصر الاستخدام على البيانات التي يقدمها المستخدم طواعية: البريد الإلكتروني للمصادقة، ومصروفات الأسرة المدخلة يدوياً أو عبر الشات ومسح فواتير ZATCA.</p>
        
        <h4 data-i18n="lp3">3. حق حذف الحساب والبيانات</h4>
        <p data-i18n="lp3Txt">يحق للمستخدم طلب الحذف النهائي والشامل لحسابه وكافة سجلاته المالية في أي وقت عبر مراسلة الدعم الفني مباشرة على: abedmowafaq@gmail.com.</p>
      </div>

      <div id="terms-pane" class="legal-scroll-pane" style="display: none;">
        <h4 data-i18n="lt1">1. الموافقة والامتثال</h4>
        <p data-i18n="lt1Txt">باستخدامك لتطبيق وموقع Budget Tracker فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.</p>
        
        <h4 data-i18n="lt2">2. الاستخدام للأغراض الشخصية والأسرية</h4>
        <p data-i18n="lt2Txt">التطبيق مصمم لإدارة وتنظيم الميزانية الشخصية والأسرية وتقديم مؤشرات توجيهية ولا يمثل مشورة استثمارية رسمية.</p>
        
        <h4 data-i18n="lt3">3. الدعم الفني والاستفسارات</h4>
        <p data-i18n="lt3Txt">لأي استفسارات أو مقترحات برمجية، يُرجى مراسلة المطور على: abedmowafaq@gmail.com.</p>
      </div>
    </section>

    <!-- Contact Banner -->
    <section class="contact-cta-hero" id="contact">
      <h3 class="contact-heading-text" data-i18n="contactH">هل ترغب بالانضمام للنسخة التجريبية أو تقديم اقتراح؟</h3>
      <p class="contact-copy-text" data-i18n="contactP">
        يسعدنا دائماً الاستماع لآرائكم وملاحظاتكم لبناء أفضل تجربة مالية رقمية للأسر في المملكة العربية السعودية.
      </p>
      <a href="mailto:abedmowafaq@gmail.com" class="contact-email-capsule">
        <span>✉️</span>
        <span>abedmowafaq@gmail.com</span>
      </a>
    </section>
  </main>

  <!-- Footer -->
  <footer>
    <div class="container">
      <div class="footer-link-group">
        <a href="#stage" data-i18n="ftSim">المحاكي</a>
        <a href="#metrics" data-i18n="ftMet">المؤشرات</a>
        <a href="#features" data-i18n="ftFeat">المميزات</a>
        <a href="#security" data-i18n="ftComp">الأمان والخصوصية</a>
        <a href="#faq" data-i18n="ftFaq">الأسئلة الشائعة</a>
        <a href="#legal" onclick="switchLegalTab('privacy')" data-i18n="ftPriv">الخصوصية</a>
        <a href="#legal" onclick="switchLegalTab('terms')" data-i18n="ftTerm">الشروط</a>
        <a href="mailto:abedmowafaq@gmail.com" data-i18n="ftCont">الدعم</a>
      </div>
      <p data-i18n="ftCopy">© 2026 Budget Tracker • جميع الحقوق محفوظة لـ budget.fmsco.com.sa</p>
    </div>
  </footer>

  <script>
    let currentLang = 'ar';

    const translations = {
      ar: {
        dir: 'rtl',
        bodyClass: '',
        navBrandSub: 'ميزانية الأسرة',
        navSim: 'المحاكي التفاعلي',
        navMetrics: 'المؤشرات',
        navFeat: 'المميزات',
        navSec: 'الأمان والخصوصية',
        navFaq: 'الأسئلة الشائعة',
        navContact: 'الدعم الفني',
        navCta: 'جرب المحاكي',
        heroBadgeText: 'الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية',
        heroH1Prefix: 'تحكّم مطلق في ميزانية أسرتك بـ',
        heroH1Italic: 'ذكاء فائق.',
        heroDesc: 'صُمم خصيصاً ليواكب واقع الأسر في السعودية. حدد يوم نزول راتبك بكل حرية (اليوم 1، 15، 25، 27 أو أي تاريخ يناسبك)، مع مسح فواتير ZATCA بالذكاء الاصطناعي، ومساعد الشات التفاعلي، وتوزيع المصاريف بعدالة بين الشركاء والأبناء دون أي عناء.',
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
        simShiftBadge: '✓ نظام موازنة العطلات التلقائي نشط',
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
        aiCardMerchant: 'مطعم البيك (وجبة عائلية)',
        aiTagCat: '🍔 المطاعم والتغذية',
        aiTagSub: '🍟 وجبات سريعة',
        aiTagPaid: '👤 المدفوع بواسطة: أنا',
        aiTagFor: '👨‍👩‍👧 المستفيد: الأسرة',
        zatcaComplianceTag: '✓ متوافق مع هيئة الزكاة والضريبة والجمارك (المرحلة 2)',
        zatcaMerchantName: 'شركة أسواق بندة للتجزئة',
        zLblTax: 'الرقم الضريبي:',
        zLblVat: 'ضريبة القيمة المضافة (15%):',
        zLblTot: 'الإجمالي شامل الضريبة:',
        partTitleTxt: 'حاسبة التسوية ثنائية الأبعاد وتتبع مصاريف الأبناء',
        partBadge: 'نسبة عادلة 50% / 50%',
        partLblNet: 'صافي التسوية بين الشركاء',
        partValNet: '+380 ر.س مستحق لك',
        partSubNet: 'تمت الحسبة التلقائية لجميع فواتير الشهر',
        partLblKids: 'مجموع نفقات الأبناء هذا الشهر',
        partValKids: '1,240 ر.س',
        partSubKids: 'مدارس، أنشطة، ورعاية صحية',
        partLblTag: 'المستفيدون المخصصون:',
        childTag1: '👧 سارة (مستلزمات مدرسية: 520 ر.س)',
        childTag2: '👦 عمر (أنشطة رياضية: 430 ر.س)',
        childTag3: '👶 فهد (تطعيمات وتموين: 290 ر.س)',
        cntLbl1: 'يعمل بدون اتصال (Offline-First)',
        cntLbl2: 'خصوصية تامة وعزل مشفر للأسرة',
        cntLbl3: 'سرعة فك تشفير فواتير ZATCA TLV',
        cntLbl4: 'مرونة تامة لأي يوم راتب تختاره',
        featEyebrow: 'منظومة مالية شاملة',
        featH2: 'كل ما تحتاجه الأسرة السعودية في تطبيق واحد',
        featSub: 'تم بناء كل ميزة لحل تحديات مالية حقيقية يواجهها الأفراد والأسر في المملكة مع تجربة مستخدم تتسم بالسهولة والجمال.',
        f1T: 'دورة راتب مرنة وقواعد الصرف التلقائية',
        f1D: 'سواء كنت موظفاً حكومياً، أو في القطاع الخاص، أو تمارس عملاً حراً؛ حدد يوم راتبك الشهري بكل حرية. يطبق التطبيق نظام موازنة مواعيد الصرف التلقائي للعطلات الأسبوعية مع احتساب معدل الصرف اليومي الآمن لتفادي نفاد الراتب مبكراً.',
        f1Tag1: 'تعديل أي يوم في الشهر',
        f1Tag2: 'موازنة العطلات الأسبوعية',
        f1Tag3: 'معدل الصرف اليومي الآمن',
        f2T: 'مساعد ذكي يفهم اللهجة السعودية',
        f2D: 'سجّل مشترياتك صوتياً أو كتابياً باللهجة المحلية أو الفصحى أو الإنجليزية. يفهم السياق فورياً ("عبيت بنزين 91 بـ 85 ريال") ويصنّفها بدقة متناهية.',
        f2Tag1: 'شات فوري',
        f2Tag2: 'تعرّف باللهجة',
        f3T: 'تصنيف هجين ثنائي المستويات',
        f3D: 'تصنيفات رئيسية وفرعية دقيقة (مثل: المطاعم > وجبات سريعة أو كافيهات). يختار الذكاء الاصطناعي التصنيف الفرعي الأنسب مع بطاقة تأكيد تفاعلية تتيح لك التعديل بمرونة.',
        f3Tag1: 'تصنيف فرعي ذكي',
        f3Tag2: 'بطاقة تأكيد قبل الحفظ',
        f4T: 'ماسح فواتير ZATCA المرحلة الثانية',
        f4D: 'وجّه الكاميرا إلى أي فاتورة إلكترونية لفك شفرة رمز الاستجابة السريعة (Base64 TLV) بدقة 100% واستخراج اسم التاجر، الرقم الضريبي، وضريبة القيمة المضافة فورياً.',
        f4Tag1: 'تشفير TLV',
        f4Tag2: 'احتساب الضريبة 15%',
        f5T: 'تقسيم عادل بين الشركاء',
        f5D: 'نظام توثيق ثنائي الأبعاد يرصد "من دفع" و"من استفاد" مع نسبة مخصصة للتقاسم لحساب التسويات الصافية والديون المتبادلة دون أي إحراج مالي.',
        f5Tag1: 'رمز دعوة عائلي',
        f5Tag2: 'تسوية ديون فورية',
        f6T: 'تتبع نفقات الأبناء والتابعين',
        f6D: 'أضف أسماء الأبناء في إعدادات الأسرة وخصّص الفواتير لكل ابن (مصاريف المدارس، الأنشطة، المستلزمات الطبية) لمعرفة التكلفة الفعلية لكل فرد بدقة.',
        f6Tag1: 'تخصيص لكل طفل',
        f6Tag2: 'تقارير نفقات التابعين',
        f7T: 'متابعة خطط التقسيط (تابي وتمارا)',
        f7D: 'تتبّع خطط التقسيط عبر تابي، تمارا، وبطاقات الدفع مع حلقات تقدم دائرية توضح المتبقي والتنبيه التلقائي قبل مواعيد السداد لتفادي الرسوم.',
        f7Tag1: 'تابي & تمارا',
        f7Tag2: 'تنبيه مواعيد الأقساط',
        f8T: 'جدولة الفواتير والاشتراكات الدورية',
        f8D: 'كشف وجدولة فواتير الكهرباء (SEC)، والمياه (NWC)، والاتصالات (STC/Mobily)، ورسوم الإقامة والتأمين لتجنب الانقطاعات والمفاجآت.',
        f8Tag1: 'الكهرباء والمياه',
        f8Tag2: 'تجديدات الاشتراكات',
        f9T: 'مقارنة أسعار المقاضي وسلة التوفير',
        f9D: 'سجّل مشتريات السوبرماركت وقارن أسعار السلع الأساسية بين سلاسل المتاجر الكبرى في المملكة (بندة، كارفور، لولو، التميمي، الدانوب) لتوفير ما يصل إلى 20% شهرياً.',
        f9Tag1: 'تتبع تاريخ الأسعار',
        f9Tag2: 'سلة المقاضي المثالية',
        f10T: 'حاسبة "هل أستطيع تحمل هذه التكلفة؟"',
        f10D: 'اختبر أي قرار شراء غير مخطط له قبل اتخاذه؛ يحسب التطبيق فورياً أثر الشراء على وتيرة صرف الأيام المتبقية في دورة الراتب وعلى احتياطي الادخار دون إرباك الميزانية.',
        f10Tag1: 'محاكاة فورية للقرارات',
        f10Tag2: 'حماية خطة الشهر',
        f11T: 'يعمل بالكامل دون اتصال بالإنترنت',
        f11D: 'قاعدة بيانات SQLite محلية مدمجة تتيح لك تسجيل المصاريف ومسح الفواتير في أي وقت حتى بدون شبكة، مع مزامنة سحابية تلقائية وخوارزمية تشفير تمنع تكرار العمليات.',
        f11Tag1: 'مزامنة تلقائية',
        f11Tag2: 'تشفير SHA-256',
        f12T: 'احتياطي الادخار وتقارير PDF الشهرية',
        f12D: 'يتحول الفائض غير المخصص تلقائياً إلى صندوق احتياطي الادخار الأسري، مع إمكانية تصدير كشوف حساب شهرية رسمية بصيغة PDF باللغتين العربية والإنجليزية.',
        f12Tag1: 'صندوق طوارئ مالي',
        f12Tag2: 'تقارير ضريبية ومالية',
        compEyebrow: 'معايير أمان عالية',
        compH2: 'خصوصية تامة وعزل مشفر للبيانات',
        cp1T: 'عزل تام لبيانات الأسرة (Row-Level Security)',
        cp1D: 'بيانات كل أسرة معزولة ومشفرة سحابياً بقواعد أمان صارمة؛ لا يمكن لأي مستخدم آخر الاطلاع على فلس واحد من مصروفاتكم.',
        cp2T: 'صفر مشاركة مع معلنين أو أطراف ثالثة',
        cp2D: 'لا نبيع بياناتك ولا نشاركها إطلاقاً مع شبكات إعلانية أو وسطاء تجاريين. خصوصيتك المالية مقدسة 100%.',
        cp3T: 'حفظ السجلات بنسبة 100% وعدم الحذف النهائي',
        cp3D: 'التصنيفات غير المستخدمة تتحول إلى حالة "غير نشطة" مع حفظ كامل تاريخ المصروفات والرسوم البيانية السابقة بأمان.',
        faqEyebrow: 'إجابات واضحة',
        faqH2: 'الأسئلة الشائعة',
        faqQ1: 'هل التطبيق محصور بيوم راتب معين (مثل يوم 27)؟',
        faqA1: 'إطلاقاً! يمكنك ضبط يوم نزول الراتب على أي تاريخ في الشهر (1، 15، 25، 27 أو أي تاريخ يحدده جهة عملك). يتولى المحرك إعادة حساب الأيام المتبقية ومعدل الصرف اليومي الآمن بدقة وفق التاريخ الذي تختاره.',
        faqQ2: 'كيف يتعامل التطبيق مع عطلات نهاية الأسبوع في دورة الراتب؟',
        faqA2: 'يطبق التطبيق نظام الموازنة التلقائي المعتمد: إذا صادف يوم راتبك يوم الجمعة، يتم تقديم دورة الصرف إلى يوم الخميس. وإذا صادف يوم السبت، يتم ترحيلها إلى يوم الأحد لضمان دقة وتيرة الصرف اليومية.',
        faqQ3: 'هل يمكنني تقسيم المصاريف وتحديد تكلفة كل ابن من أفراد الأسرة؟',
        faqA3: 'نعم، يدعم التطبيق إدارة أفراد الأسرة وإضافة الأبناء؛ عند تسجيل أي فاتورة يمكنك تحديد من دفع المصروف (أنا أو الشريك) ولمن تم الصرف (أنا، الشريك، أو أحد الأبناء)، ويقوم التطبيق بحساب التسويات الصافية العادلة بدقة.',
        faqQ4: 'هل يمكنني مسح الفواتير الإلكترونية ZATCA دون اتصال بالإنترنت؟',
        faqA4: 'نعم، فك شفرة Base64 TLV الخاصة بفواتير ZATCA يتم محلياً وبشكل فوري على جهازك وبسرعة فائقة حتى بدون أي اتصال بالإنترنت، ويتم حفظ الفاتورة في قاعدة بيانات SQLite المحلية لحين توفر الشبكة.',
        tabPrivacyBtn: 'سياسة الخصوصية',
        tabTermsBtn: 'شروط الاستخدام',
        lp1: '1. الالتزام الصارم بالخصوصية',
        lp1Txt: 'نحن في Budget Tracker نضع حماية بياناتك المالية فوق كل اعتبار. يتم عزل وتشفير بيانات كل أسرة سحابياً بأحدث معايير الأمان وقواعد Row-Level Security.',
        lp2: '2. البيانات المُعالجة',
        lp2Txt: 'يقتصر الاستخدام على البيانات التي يقدمها المستخدم طواعية: البريد الإلكتروني للمصادقة، ومصروفات الأسرة المدخلة يدوياً أو عبر الشات ومسح فواتير ZATCA.',
        lp3: '3. حق حذف الحساب والبيانات',
        lp3Txt: 'يحق للمستخدم طلب الحذف النهائي والشامل لحسابه وكافة سجلاته المالية في أي وقت عبر مراسلة الدعم الفني مباشرة على: abedmowafaq@gmail.com.',
        lt1: '1. الموافقة والامتثال',
        lt1Txt: 'باستخدامك لتطبيق وموقع Budget Tracker فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.',
        lt2: '2. الاستخدام للأغراض الشخصية والأسرية',
        lt2Txt: 'التطبيق مصمم لإدارة وتنظيم الميزانية الشخصية والأسرية وتقديم مؤشرات توجيهية ولا يمثل مشورة استثمارية رسمية.',
        lt3: '3. الدعم الفني والاستفسارات',
        lt3Txt: 'لأي استفسارات أو مقترحات برمجية، يُرجى مراسلة المطور على: abedmowafaq@gmail.com.',
        contactH: 'هل ترغب بالانضمام للنسخة التجريبية أو تقديم اقتراح؟',
        contactP: 'يسعدنا دائماً الاستماع لآرائكم وملاحظاتكم لبناء أفضل تجربة مالية رقمية للأسر في المملكة العربية السعودية.',
        ftSim: 'المحاكي',
        ftMet: 'المؤشرات',
        ftFeat: 'المميزات',
        ftComp: 'الأمان والخصوصية',
        ftFaq: 'الأسئلة الشائعة',
        ftPriv: 'الخصوصية',
        ftTerm: 'الشروط',
        ftCont: 'الدعم',
        ftCopy: '© 2026 Budget Tracker • جميع الحقوق محفوظة لـ budget.fmsco.com.sa'
      },
      en: {
        dir: 'ltr',
        bodyClass: 'lang-en',
        navBrandSub: 'Family Budget',
        navSim: 'Interactive Stage',
        navMetrics: 'Metrics',
        navFeat: 'Features',
        navSec: 'Security & Privacy',
        navFaq: 'FAQ',
        navContact: 'Support',
        navCta: 'Try Simulator',
        heroBadgeText: 'Fintech Innovation • Works with Any Monthly Salary Cycle',
        heroH1Prefix: 'Absolute Mastery of Your Family Budget with',
        heroH1Italic: 'Pure Precision.',
        heroDesc: 'Engineered specifically for households in Saudi Arabia. Freely choose your monthly payday (1st, 15th, 25th, 27th, or custom), with instant ZATCA e-invoice scanning, conversational AI chat, and fair expense allocation between partners and children.',
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
        simShiftBadge: '✓ Automated Weekend Adjustment Active',
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
        aiCardMerchant: 'Al Baik Restaurant (Family Meal)',
        aiTagCat: '🍔 Dining & Food',
        aiTagSub: '🍟 Fast Food',
        aiTagPaid: '👤 Paid By: Me',
        aiTagFor: '👨‍👩‍👧 Beneficiary: Family',
        zatcaComplianceTag: '✓ ZATCA Phase 2 E-Invoice Compliant',
        zatcaMerchantName: 'Panda Retail Markets Company',
        zLblTax: 'VAT Registration No:',
        zLblVat: 'VAT Amount (15%):',
        zLblTot: 'Grand Total with VAT:',
        partTitleTxt: '2D Fair-Share Settlement & Children Allocation',
        partBadge: 'Fair Ratio 50% / 50%',
        partLblNet: 'Net Settlement Between Partners',
        partValNet: '+380 SAR Due to You',
        partSubNet: 'Automatically reconciled across monthly bills',
        partLblKids: 'Total Children Expenses This Month',
        partValKids: '1,240 SAR',
        partSubKids: 'Schools, extracurriculars, & healthcare',
        partLblTag: 'Designated Beneficiaries:',
        childTag1: '👧 Sarah (School Supplies: 520 SAR)',
        childTag2: '👦 Omar (Sports Activities: 430 SAR)',
        childTag3: '👶 Fahad (Vaccines & Care: 290 SAR)',
        cntLbl1: '100% Offline-First Architecture',
        cntLbl2: 'Total Privacy with Row-Level Security',
        cntLbl3: 'Sub-Second ZATCA TLV Verification',
        cntLbl4: 'Full Flexibility for Any Salary Day',
        featEyebrow: 'Comprehensive Financial Platform',
        featH2: 'Everything Your Family Needs in One App',
        featSub: 'Every single feature is built to solve real everyday financial challenges faced by households across Saudi Arabia.',
        f1T: 'Flexible Salary Cycle & Auto Shift Pacing',
        f1D: 'Whether in government, the private sector, or freelancing; configure your salary day freely. The engine applies automated weekend schedule adjustments with live safe burn-rate pacing.',
        f1Tag1: 'Any Day of Month',
        f1Tag2: 'Weekend Auto-Pacing',
        f1Tag3: 'Safe Daily Allowance',
        f2T: 'Conversational Saudi AI Assistant',
        f2D: 'Log expenses via text or voice in Saudi dialect, Arabic, English, or Urdu. Instant context parsing ("Filled 91 petrol for 85 SAR") automatically classifies merchant, category, and payment tags.',
        f2Tag1: 'Instant Chat',
        f2Tag2: 'Dialect Recognition',
        f3T: 'Two-Tier Taxonomy & Hybrid Subcategories',
        f3D: 'Deep multi-tier categories (e.g. Dining > Fast Food or Coffee). AI recommends the optimal subcategory with an interactive confirmation card before recording.',
        f3Tag1: 'Smart Subcategories',
        f3Tag2: 'Interactive Confirm Card',
        f4T: 'ZATCA Phase 2 E-Invoice QR Scanner',
        f4D: 'Point your camera at any e-invoice to decode cryptographic Base64 TLV QR codes with 100% precision, instantly extracting seller info, tax ID, and 15% VAT totals.',
        f4Tag1: 'TLV Decoding',
        f4Tag2: '15% VAT Extraction',
        f5T: 'Fair Partner Attribution & Settlements',
        f5D: 'Two-dimensional tracking records "Who Paid" vs "Who Benefited" with customizable ratios, calculating clean net debts without financial awkwardness.',
        f5Tag1: 'Family Invite Code',
        f5Tag2: 'Instant Net Settlements',
        f6T: 'Family Dependents & Children Tracking',
        f6D: 'Add children profiles in household settings to designate costs (school fees, sports, healthcare) and view exact spending per dependent.',
        f6Tag1: 'Per-Child Attribution',
        f6Tag2: 'Dependent Cost Reports',
        f7T: 'BNPL & Installments Tracker (Tabby & Tamara)',
        f7D: 'Track Tabby, Tamara, and payment card installment schedules with progress rings and automated notifications before due dates.',
        f7Tag1: 'Tabby & Tamara',
        f7Tag2: 'Due Date Alerts',
        f8T: 'Recurring Bills & Cadence Engine',
        f8D: 'Auto-detect and track utility bills like electricity (SEC), water (NWC), fiber telecom (STC/Mobily), and annual Iqama renewals.',
        f8Tag1: 'Utilities & Telecom',
        f8Tag2: 'Renewal Schedules',
        f9T: 'Smart Grocery Price Comparison',
        f9D: 'Log supermarket baskets and track staple price trends across Panda, Carrefour, Lulu, Danube, and Tamimi to save up to 20% every month.',
        f9Tag1: 'Price History',
        f9Tag2: 'Optimized Basket',
        f10T: '"Can I Afford This?" Instant Simulator',
        f10D: 'Test discretionary purchases before buying. Real-time simulation checks the impact on remaining cycle budget and emergency savings.',
        f10Tag1: 'Instant Impact Test',
        f10Tag2: 'Budget Protection',
        f11T: '100% Offline-First SQLite Architecture',
        f11D: 'Integrated local SQLite engine lets you log transactions anywhere without internet, with SHA-256 cloud sync avoiding duplicate entries.',
        f11Tag1: 'Local SQLite Engine',
        f11Tag2: 'SHA-256 Sync',
        f12T: 'Smart Savings Reserve & Monthly PDF Reports',
        f12D: 'Unassigned monthly income automatically sweeps into a family emergency reserve, with official bilingual ZATCA-ready PDF statement exports.',
        f12Tag1: 'Emergency Reserve',
        f12Tag2: 'Official PDF Statements',
        compEyebrow: 'High Security Standards',
        compH2: 'Total Privacy with Encrypted Data Isolation',
        cp1T: 'Household Row-Level Security (RLS)',
        cp1D: 'Every family is strictly isolated with modern database encryption; no other user can ever view a single cent of your transactions.',
        cp2T: 'Zero Ads or Third-Party Data Selling',
        cp2D: 'We never sell or monetize your financial data with advertising networks. Your household privacy is 100% sacred.',
        cp3T: '100% Zero Data Deletion',
        cp3D: 'Unused categories are gracefully archived as inactive, fully preserving your historical transaction analytics and trends safely.',
        faqEyebrow: 'Clear Answers',
        faqH2: 'Frequently Asked Questions',
        faqQ1: 'Is the app locked to a specific payday (like the 27th)?',
        faqA1: 'Not at all! You can set your payday to any day of the month (1st, 15th, 25th, 27th, or custom). The engine dynamically calculates days remaining and safe daily spending according to your chosen date.',
        faqQ2: 'How does the app handle weekend schedule adjustments?',
        faqA2: 'The engine applies automated weekend adjustment rules: if your payday falls on a Friday, it shifts to Thursday. If it falls on a Saturday, it moves to Sunday to keep your burn rate accurate.',
        faqQ3: 'Can I split expenses and track costs for each child?',
        faqA3: 'Yes! The app supports full household dependents management. When logging an expense, you specify who paid and for whom (yourself, your partner, or a child), and net balances reconcile automatically.',
        faqQ4: 'Can I scan ZATCA invoices without an internet connection?',
        faqA4: 'Yes! Cryptographic Base64 TLV decoding is performed locally on your device in milliseconds. Offline receipts queue in your local SQLite database and sync when reconnected.',
        tabPrivacyBtn: 'Privacy Policy',
        tabTermsBtn: 'Terms of Service',
        lp1: '1. Strict Privacy Commitment',
        lp1Txt: 'At Budget Tracker, your financial data privacy is our absolute priority. All household data is protected with modern cloud row-level security.',
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
        ftMet: 'Metrics',
        ftFeat: 'Features',
        ftComp: 'Security & Privacy',
        ftFaq: 'FAQ',
        ftPriv: 'Privacy Policy',
        ftTerm: 'Terms of Service',
        ftCont: 'Support',
        ftCopy: '© 2026 Budget Tracker • All rights reserved for budget.fmsco.com.sa'
      }
    };

    function setLanguage(lang) {
      currentLang = lang;
      const data = translations[lang];
      document.documentElement.lang = lang;
      document.documentElement.dir = data.dir;
      document.body.className = data.bodyClass;

      // Update segmented button active states
      const btnAr = document.getElementById('btn-lang-ar');
      const btnEn = document.getElementById('btn-lang-en');
      if (lang === 'ar') {
        btnAr.classList.add('active');
        btnEn.classList.remove('active');
      } else {
        btnEn.classList.add('active');
        btnAr.classList.remove('active');
      }

      // Translate all data-i18n elements
      document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (data[key]) {
          el.innerHTML = data[key];
        }
      });

      // Update simulator numbers with proper language units
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
  
  <!-- Website Logo Favicon for browser tab -->
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0%25' y1='0%25' x2='100%25' y2='100%25'%3E%3Cstop offset='0%25' stop-color='%2334D399'/%3E%3Cstop offset='100%25' stop-color='%230284C7'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='%2308080A'/%3E%3Cpath d='M32 10 L52 24 L52 46 L32 54 L12 46 L12 24 Z' fill='url(%23g)' stroke='%23ffffff' stroke-width='1.5' stroke-opacity='0.4'/%3E%3Ccircle cx='32' cy='32' r='7' fill='%23ffffff'/%3E%3C/svg%3E">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@600;700;800&family=Outfit:wght@600;700;800&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Cairo', -apple-system, sans-serif;
      background: #060709;
      color: #C9D1D9;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      position: relative;
    }
    .card {
      background: #0E1015;
      border: 1px solid rgba(52, 211, 153, 0.3);
      border-radius: 24px;
      padding: 48px 36px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6), 0 0 40px rgba(52, 211, 153, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.12);
      position: relative;
      z-index: 1;
    }
    .icon-circle {
      width: 80px;
      height: 80px;
      border-radius: 50%;
      background: rgba(52, 211, 153, 0.15);
      border: 2px solid #34D399;
      color: #34D399;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 40px;
      margin-bottom: 24px;
      box-shadow: 0 0 25px rgba(52, 211, 153, 0.3);
    }
    h1 {
      color: #FFFFFF;
      font-size: 26px;
      font-weight: 800;
      margin-bottom: 8px;
    }
    .subtitle-en {
      color: #34D399;
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
      background: linear-gradient(135deg, #10B981, #0284C7);
      color: #FFFFFF;
      font-size: 16px;
      font-weight: 800;
      padding: 14px 20px;
      border-radius: 14px;
      text-decoration: none;
      transition: all 0.25s ease;
      box-shadow: 0 8px 24px rgba(16, 185, 129, 0.35);
    }
    .action-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 12px 30px rgba(16, 185, 129, 0.5);
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
      color: #34D399;
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
