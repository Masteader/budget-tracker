"""
Landing page and auth confirmation HTML generator for Budget Tracker (budget.fmsco.com.sa).
Architected with modern-landing-designer specifications:
- Deep obsidian palette (#08080A / #111116) with subtle 1px frosted micro-borders.
- Directional light simulation with inset top borders and ambient radial mesh glows.
- Floating frosted sticky navbar with live pulse indicator.
- Hero with tight-tracking typography, primary bloom action, and store badges.
- Live Interactive Product Stage (Payday Simulator, AI Assistant, ZATCA Scanner, 2D Split).
- Metric counters bar (Offline-First, Zero SMS Snooping, ZATCA TLV speed, Any Payday).
- 12-pillar asymmetric Bento Grid with varied spans and rich inner previews.
- Bank-grade security and isolation comparison matrix.
- FAQ accordion with smooth state transitions.
- Instant bilingual Arabic (RTL default) and English (LTR) client-side localization engine.
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
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=Outfit:wght@400;500;600;700;800;900&family=Plus+Jakarta+Sans:wght@500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      /* Modern Landing Designer Obsidian Tokens */
      --canvas-base: #08080A;
      --card-surface: #111116;
      --card-elevated: #16161D;
      --card-border: rgba(255, 255, 255, 0.08);
      --card-border-hover: rgba(255, 255, 255, 0.18);
      --specular-highlight: inset 0 1px 0 rgba(255, 255, 255, 0.12);
      
      /* Accent Glows & Radiance */
      --glow-emerald: rgba(52, 211, 153, 0.9);
      --glow-emerald-dim: rgba(52, 211, 153, 0.12);
      --glow-indigo: rgba(99, 102, 241, 0.15);
      --glow-cyan: rgba(56, 189, 248, 0.12);
      --glow-purple: rgba(168, 85, 247, 0.12);
      --glow-amber: rgba(245, 158, 11, 0.12);
      
      /* Typography */
      --text-pure: #FFFFFF;
      --text-primary: #F1F5F9;
      --text-muted: #94A3B8;
      --text-dim: #64748B;
      --font-ar: 'Cairo', -apple-system, sans-serif;
      --font-en: 'Plus Jakarta Sans', 'Outfit', -apple-system, sans-serif;
      
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

    /* Ambient Mesh Gradients & Dot Texture */
    .ambient-mesh {
      position: fixed;
      inset: 0;
      background-image: radial-gradient(rgba(255, 255, 255, 0.06) 1px, transparent 1px);
      background-size: 28px 28px;
      opacity: 0.6;
      pointer-events: none;
      z-index: 0;
      mask-image: radial-gradient(circle at 50% 25%, black 45%, transparent 85%);
      -webkit-mask-image: radial-gradient(circle at 50% 25%, black 45%, transparent 85%);
    }

    .ambient-glow-top {
      position: fixed;
      top: -180px;
      left: 50%;
      transform: translateX(-50%);
      width: 850px;
      height: 520px;
      background: radial-gradient(circle, rgba(52, 211, 153, 0.16) 0%, rgba(99, 102, 241, 0.10) 45%, transparent 70%);
      pointer-events: none;
      z-index: 0;
      filter: blur(80px);
    }

    .ambient-glow-side {
      position: fixed;
      top: 45vh;
      left: -120px;
      width: 600px;
      height: 600px;
      background: radial-gradient(circle, rgba(56, 189, 248, 0.08) 0%, transparent 65%);
      pointer-events: none;
      z-index: 0;
      filter: blur(90px);
    }

    .ambient-glow-bottom {
      position: fixed;
      bottom: -150px;
      right: -100px;
      width: 650px;
      height: 650px;
      background: radial-gradient(circle, rgba(168, 85, 247, 0.08) 0%, transparent 65%);
      pointer-events: none;
      z-index: 0;
      filter: blur(80px);
    }

    .container {
      max-width: var(--max-w);
      margin: 0 auto;
      padding: 0 28px;
      position: relative;
      z-index: 1;
    }

    /* Floating Frosted Navbar */
    header {
      position: sticky;
      top: 0;
      z-index: 100;
      background: rgba(8, 8, 10, 0.82);
      backdrop-filter: blur(24px) saturate(180%);
      -webkit-backdrop-filter: blur(24px) saturate(180%);
      border-bottom: 1px solid var(--card-border);
      transition: all 0.3s ease;
    }

    .nav-inner {
      display: flex;
      justify-content: space-between;
      align-items: center;
      height: 80px;
    }

    .brand-link {
      display: flex;
      align-items: center;
      gap: 14px;
      text-decoration: none;
      color: inherit;
    }

    .brand-icon-box {
      width: 44px;
      height: 44px;
      border-radius: 14px;
      background: linear-gradient(135deg, #10B981 0%, #0284C7 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      box-shadow: 0 0 24px rgba(16, 185, 129, 0.4), var(--specular-highlight);
      border: 1px solid rgba(255, 255, 255, 0.2);
    }

    .brand-text-wrap h1 {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.02em;
      color: var(--text-pure);
      line-height: 1.2;
    }

    .brand-text-wrap span {
      font-size: 11px;
      font-weight: 700;
      color: #34D399;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      display: block;
    }

    .nav-items {
      display: flex;
      align-items: center;
      gap: 28px;
      list-style: none;
    }

    .nav-item-link {
      color: var(--text-muted);
      text-decoration: none;
      font-size: 14px;
      font-weight: 600;
      transition: color 0.2s ease;
    }

    .nav-item-link:hover {
      color: var(--text-pure);
    }

    .nav-cta-actions {
      display: flex;
      align-items: center;
      gap: 14px;
    }

    .lang-switcher-btn {
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      color: var(--text-primary);
      padding: 9px 18px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      transition: all 0.25s ease;
      box-shadow: var(--specular-highlight);
    }

    .lang-switcher-btn:hover {
      background: rgba(52, 211, 153, 0.1);
      border-color: #34D399;
      color: #34D399;
      transform: translateY(-1px);
    }

    /* Hero Section */
    .hero-section {
      padding: 90px 0 60px;
      text-align: center;
      position: relative;
    }

    .shimmer-status-pill {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      padding: 7px 20px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid var(--card-border);
      border-radius: 999px;
      color: #E2E8F0;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 28px;
      box-shadow: var(--specular-highlight), 0 0 20px rgba(52, 211, 153, 0.12);
      backdrop-filter: blur(14px);
    }

    .live-status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #34D399;
      box-shadow: 0 0 10px #34D399;
      position: relative;
    }

    .live-status-dot::after {
      content: '';
      position: absolute;
      inset: -4px;
      border-radius: 50%;
      background: #34D399;
      opacity: 0.6;
      animation: pulsePing 2s cubic-bezier(0, 0, 0.2, 1) infinite;
    }

    @keyframes pulsePing {
      0% { transform: scale(1); opacity: 0.8; }
      100% { transform: scale(2.8); opacity: 0; }
    }

    .hero-h1 {
      font-size: clamp(34px, 5.4vw, 68px);
      font-weight: 900;
      line-height: 1.15;
      letter-spacing: -0.03em;
      color: var(--text-pure);
      max-width: 980px;
      margin: 0 auto 24px;
    }

    .hero-h1 .gradient-clip {
      background: linear-gradient(135deg, #FFFFFF 0%, #34D399 45%, #38BDF8 85%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      display: inline-block;
    }

    .hero-subtitle {
      font-size: clamp(16px, 2.1vw, 20px);
      color: var(--text-muted);
      max-width: 820px;
      margin: 0 auto 40px;
      line-height: 1.8;
      font-weight: 400;
    }

    /* Dual Action CTA & Store Badges */
    .hero-action-row {
      display: flex;
      justify-content: center;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 60px;
    }

    .primary-bloom-btn {
      background: #FFFFFF;
      color: #08080A;
      font-size: 15px;
      font-weight: 700;
      padding: 13px 28px;
      border-radius: var(--radius-md);
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 10px;
      transition: all 0.25s ease;
      box-shadow: 0 0 25px rgba(255, 255, 255, 0.35);
    }

    .primary-bloom-btn:hover {
      background: #E2E8F0;
      transform: translateY(-2px);
      box-shadow: 0 0 35px rgba(255, 255, 255, 0.5);
    }

    .store-badge-pill {
      display: flex;
      align-items: center;
      gap: 14px;
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      box-shadow: var(--specular-highlight), 0 12px 28px rgba(0, 0, 0, 0.4);
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

    .store-badge-pill:hover {
      transform: translateY(-3px);
      border-color: var(--card-border-hover);
      box-shadow: var(--specular-highlight), 0 16px 36px rgba(0, 0, 0, 0.6), 0 0 20px rgba(52, 211, 153, 0.15);
    }

    .store-icon-cell {
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

    .store-labels-wrap {
      text-align: start;
    }

    .store-sub-lbl {
      font-size: 11px;
      color: var(--text-dim);
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .store-main-lbl {
      font-size: 15px;
      font-weight: 800;
      color: var(--text-pure);
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .coming-tag-chip {
      background: rgba(245, 158, 11, 0.14);
      border: 1px solid rgba(245, 158, 11, 0.35);
      color: #F59E0B;
      font-size: 10px;
      font-weight: 800;
      padding: 2px 7px;
      border-radius: 6px;
    }

    /* Live Interactive Product Stage */
    .interactive-stage-card {
      max-width: 980px;
      margin: 0 auto 90px;
      background: linear-gradient(180deg, rgba(22, 22, 29, 0.85) 0%, rgba(14, 14, 18, 0.98) 100%);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-xl);
      box-shadow: 0 30px 80px rgba(0, 0, 0, 0.75), 0 0 50px rgba(52, 211, 153, 0.12), var(--specular-highlight);
      overflow: hidden;
      position: relative;
    }

    .stage-top-window-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 18px 28px;
      background: rgba(17, 17, 22, 0.9);
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
      color: #34D399;
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
      box-shadow: var(--specular-highlight);
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
      color: #34D399;
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
      background: #34D399;
      box-shadow: 0 0 16px #34D399;
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
      box-shadow: var(--specular-highlight);
    }

    .metric-slab::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      width: 4px;
      height: 100%;
    }
    .metric-slab.emerald::before { background: #34D399; }
    .metric-slab.cyan::before { background: #38BDF8; }
    .metric-slab.amber::before { background: #F59E0B; }

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
      background: #0E0E12;
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
      background: radial-gradient(circle at center, rgba(17, 24, 39, 0.8) 0%, #0A0A0E 100%);
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
      background: linear-gradient(90deg, transparent, #34D399, #38BDF8, transparent);
      box-shadow: 0 0 16px #34D399, 0 0 30px #38BDF8;
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

    /* Metric Counters Bar */
    .metric-counter-strip {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 20px;
      margin-bottom: 100px;
      background: var(--card-surface);
      border: 1px solid var(--card-border);
      box-shadow: var(--specular-highlight);
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
      color: #34D399;
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
      color: #34D399;
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
      box-shadow: var(--specular-highlight), 0 20px 40px rgba(0, 0, 0, 0.35);
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
      box-shadow: var(--specular-highlight), 0 25px 60px rgba(0, 0, 0, 0.5), 0 0 30px rgba(52, 211, 153, 0.12);
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

    .bento-icon-cell.emerald { background: var(--glow-emerald-dim); border-color: rgba(52, 211, 153, 0.3); color: #34D399; }
    .bento-icon-cell.cyan { background: var(--glow-cyan); border-color: rgba(56, 189, 248, 0.3); color: #38BDF8; }
    .bento-icon-cell.amber { background: var(--glow-amber); border-color: rgba(245, 158, 11, 0.3); color: #F59E0B; }
    .bento-icon-cell.purple { background: var(--glow-purple); border-color: rgba(168, 85, 247, 0.3); color: #A855F7; }

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

    /* Security & Comparison Section */
    .security-matrix-card {
      background: linear-gradient(180deg, rgba(17, 17, 22, 0.7) 0%, rgba(10, 10, 14, 0.95) 100%);
      border: 1px solid var(--card-border);
      border-radius: var(--radius-xl);
      padding: 48px 40px;
      margin-bottom: 120px;
      box-shadow: var(--specular-highlight);
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
      border: 1px solid #34D399;
      color: #34D399;
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
      box-shadow: var(--specular-highlight);
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
      color: #34D399;
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
      box-shadow: var(--specular-highlight);
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
      color: #34D399;
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
      background: radial-gradient(circle at top right, rgba(52, 211, 153, 0.16) 0%, rgba(99, 102, 241, 0.08) 50%, transparent 80%), var(--card-surface);
      border: 1px solid rgba(52, 211, 153, 0.35);
      box-shadow: 0 25px 60px rgba(0, 0, 0, 0.6), 0 0 50px rgba(52, 211, 153, 0.15), var(--specular-highlight);
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
      background: #08080A;
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
      border-color: #34D399;
      background: rgba(52, 211, 153, 0.1);
      color: #34D399;
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
      color: #34D399;
    }

    /* Responsive */
    @media (max-width: 992px) {
      .span-col-8, .span-col-4, .span-col-6 { grid-column: span 12; }
      .zatca-preview-layout { grid-template-columns: 1fr; justify-items: center; text-align: center; }
      .nav-items { display: none; }
      .counter-cell:not(:last-child)::after { display: none; }
    }

    @media (max-width: 768px) {
      .hero-section { padding: 50px 0 30px; }
      .stage-top-window-bar { flex-direction: column; gap: 14px; }
      .stage-tab-controls { width: 100%; overflow-x: auto; justify-content: flex-start; }
      .store-badge-pill { width: 100%; justify-content: center; }
      .security-matrix-card { padding: 32px 20px; }
      .contact-cta-hero { padding: 36px 20px; }
      .metric-counter-strip { grid-template-columns: 1fr 1fr; }
    }
  </style>
</head>
<body id="page-body">

  <div class="ambient-mesh"></div>
  <div class="ambient-glow-top"></div>
  <div class="ambient-glow-side"></div>
  <div class="ambient-glow-bottom"></div>

  <!-- Header -->
  <header>
    <div class="container nav-inner">
      <a href="/" class="brand-link">
        <div class="brand-icon-box">💎</div>
        <div class="brand-text-wrap">
          <h1>Budget Tracker</h1>
          <span id="nav-brand-sub">ميزانية الأسرة الذكية</span>
        </div>
      </a>

      <ul class="nav-items">
        <li><a href="#stage" class="nav-item-link" id="nav-sim">المحاكي التفاعلي</a></li>
        <li><a href="#metrics" class="nav-item-link" id="nav-metrics">المؤشرات</a></li>
        <li><a href="#features" class="nav-item-link" id="nav-feat">المميزات</a></li>
        <li><a href="#security" class="nav-item-link" id="nav-sec">الأمان المصرفي</a></li>
        <li><a href="#faq" class="nav-item-link" id="nav-faq">الأسئلة الشائعة</a></li>
        <li><a href="#contact" class="nav-item-link" id="nav-contact">الدعم الفني</a></li>
      </ul>

      <div class="nav-cta-actions">
        <button id="lang-btn" class="lang-switcher-btn" onclick="toggleLanguage()">
          🌐 <span>English</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Hero Section -->
  <main class="container">
    <section class="hero-section">
      <div class="shimmer-status-pill" id="hero-badge">
        <span class="live-status-dot"></span>
        <span id="hero-badge-text">الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية</span>
      </div>

      <h2 class="hero-h1">
        <span id="hero-h1-prefix">تحكّم مطلق في ميزانية أسرتك</span><br>
        <span class="gradient-clip" id="hero-h1-gradient">مع أي يوم راتب تختاره وبدقة الذكاء الاصطناعي</span>
      </h2>

      <p class="hero-subtitle" id="hero-desc">
        صُمم خصيصاً ليواكب واقع الأسر في السعودية. حدد يوم نزول راتبك بكل حرية (اليوم 1، 15، 25، 27 أو أي تاريخ يناسبك)، مع حساب قواعد الصرف المصرفية للعطلات تلقائياً، ومسح فواتير ZATCA، وتوزيع المصاريف بعدالة بين الشركاء والأبناء دون أي عناء.
      </p>

      <!-- Store Badges & Actions -->
      <div class="hero-action-row">
        <!-- Google Play -->
        <div class="store-badge-pill">
          <div class="store-icon-cell">🤖</div>
          <div class="store-labels-wrap">
            <div class="store-sub-lbl" id="st-google-sub">متوفر قريباً على</div>
            <div class="store-main-lbl">
              Google Play <span class="coming-tag-chip" id="chip-1">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Apple App Store -->
        <div class="store-badge-pill">
          <div class="store-icon-cell">🍎</div>
          <div class="store-labels-wrap">
            <div class="store-sub-lbl" id="st-apple-sub">متوفر قريباً على</div>
            <div class="store-main-lbl">
              App Store <span class="coming-tag-chip" id="chip-2">قريباً</span>
            </div>
          </div>
        </div>

        <!-- Huawei AppGallery -->
        <div class="store-badge-pill">
          <div class="store-icon-cell">🛍️</div>
          <div class="store-labels-wrap">
            <div class="store-sub-lbl" id="st-huawei-sub">متوفر قريباً على</div>
            <div class="store-main-lbl">
              AppGallery <span class="coming-tag-chip" id="chip-3">قريباً</span>
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
              📅 <span id="tab-t1">محاكي دورة الراتب</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-2" onclick="switchSimTab('ai')">
              ✨ <span id="tab-t2">مساعد الشات الذكي</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-3" onclick="switchSimTab('zatca')">
              🧾 <span id="tab-t3">ماسح فواتير ZATCA</span>
            </button>
            <button class="stage-tab-trigger" id="tab-sim-btn-4" onclick="switchSimTab('partner')">
              👥 <span id="tab-t4">تقسيم الشركاء والأبناء</span>
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
                  <span id="sim-title-txt">اختر يوم نزول راتبك الشهري (مرن 100% لأي قطاع)</span>
                </div>
                <div id="sim-shift-badge" class="coming-tag-chip" style="font-size: 12px; padding: 4px 10px; background: rgba(52, 211, 153, 0.15); border-color: rgba(52, 211, 153, 0.35); color: #34D399;">
                  ✓ نظام الصرف التلقائي للعطلات نشط
                </div>
              </div>

              <div class="slider-track-wrap">
                <div class="slider-extremes">
                  <span id="slider-min-lbl">اليوم 1 في الشهر</span>
                  <span><span id="slider-curr-lbl">يوم الراتب المحدد:</span> <strong id="slider-curr-val">27</strong></span>
                  <span id="slider-max-lbl">اليوم 31 في الشهر</span>
                </div>
                <input type="range" min="1" max="31" value="27" class="custom-range-slider" id="payday-range" oninput="updatePaydaySim(this.value)">
              </div>

              <div class="sim-metrics-trio">
                <div class="metric-slab emerald">
                  <div class="metric-lbl" id="sim-lbl-days">الأيام المتبقية في الدورة</div>
                  <div class="metric-val" id="sim-val-days">16 <small style="font-size: 13px;">يوم</small></div>
                  <div class="metric-sub" id="sim-sub-days">دورة نشطة متوازنة</div>
                </div>

                <div class="metric-slab cyan">
                  <div class="metric-lbl" id="sim-lbl-safe">معدل الصرف اليومي الآمن</div>
                  <div class="metric-val" id="sim-val-safe">345 <small style="font-size: 13px;">ر.س / يوم</small></div>
                  <div class="metric-sub" id="sim-sub-safe">يحميك من نفاد الميزانية قبل الراتب</div>
                </div>

                <div class="metric-slab amber">
                  <div class="metric-lbl" id="sim-lbl-reserve">احتياطي الادخار التلقائي</div>
                  <div class="metric-val" id="sim-val-reserve">4,500 <small style="font-size: 13px;">ر.س</small></div>
                  <div class="metric-sub" id="sim-sub-reserve">فائض غير مخصص يُحفظ للطوارئ</div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tab 2: AI Chat Simulator -->
          <div id="sim-panel-ai" class="tab-view-pane">
            <div class="ai-chat-preview-box">
              <div class="chat-bubble-sender" id="chat-u-msg">
                "عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة"
              </div>
              <div class="chat-bubble-response">
                <div style="font-size: 12px; color: #34D399; font-weight: 700; margin-bottom: 6px;">
                  🤖 <span id="chat-ai-header">تم استخراج المصروف بالذكاء الاصطناعي بدقة</span>
                </div>
                <div class="ai-parsed-card">
                  <div class="ai-card-title-row">
                    <span>مطعم البيك (وجبة عائلية)</span>
                    <span style="color: #34D399;">68.00 ر.س</span>
                  </div>
                  <div class="tag-cluster">
                    <span class="tag-badge cat">🍔 المطاعم والتغذية</span>
                    <span class="tag-badge sub">🍟 وجبات سريعة</span>
                    <span class="tag-badge paid">👤 المدفوع بواسطة: أنا</span>
                    <span class="tag-badge for">👨‍👩‍👧 المستفيد: الأسرة</span>
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
                    <span class="coming-tag-chip" style="background: rgba(52, 211, 153, 0.15); border-color: rgba(52, 211, 153, 0.35); color: #34D399;">
                      ✓ متوافق مع هيئة الزكاة والضريبة والجمارك (المرحلة 2)
                    </span>
                  </div>
                  <h5>شركة أسواق بندة للتجزئة</h5>
                  <div class="zatca-data-line">
                    <span id="z-lbl-tax">الرقم الضريبي:</span>
                    <strong>300055489200003</strong>
                  </div>
                  <div class="zatca-data-line">
                    <span id="z-lbl-vat">ضريبة القيمة المضافة (15%):</span>
                    <strong style="color: #F59E0B;">32.40 ر.س</strong>
                  </div>
                  <div class="zatca-data-line">
                    <span id="z-lbl-tot">الإجمالي شامل الضريبة:</span>
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
                  <span id="part-title-txt">حاسبة التسوية ثنائية الأبعاد وتتبع مصاريف الأبناء</span>
                </div>
                <div class="coming-tag-chip" id="part-badge">نسبة عادلة 50% / 50%</div>
              </div>

              <div class="split-meter-bar">
                <div class="split-share-you" id="ratio-bar-you" style="width: 50%;"></div>
                <div class="split-share-partner" id="ratio-bar-partner" style="width: 50%;"></div>
              </div>

              <div class="sim-metrics-trio">
                <div class="metric-slab emerald">
                  <div class="metric-lbl" id="part-lbl-net">صافي التسوية بين الشركاء</div>
                  <div class="metric-val" style="color: #34D399;">+380 <small style="font-size: 13px;">ر.س مستحق لك</small></div>
                  <div class="metric-sub" id="part-sub-net">تمت الحسبة التلقائية لجميع فواتير الشهر</div>
                </div>

                <div class="metric-slab cyan">
                  <div class="metric-lbl" id="part-lbl-kids">مجموع نفقات الأبناء هذا الشهر</div>
                  <div class="metric-val">1,240 <small style="font-size: 13px;">ر.س</small></div>
                  <div class="metric-sub" id="part-sub-kids">مدارس، أنشطة، ورعاية صحية</div>
                </div>
              </div>

              <div class="dependents-pill-row">
                <span style="font-size: 13px; color: var(--text-muted); align-self: center;" id="part-lbl-tag">المستفيدون المخصصون:</span>
                <span class="child-dep-chip">👧 سارة (مستلزمات مدرسية: 520 ر.س)</span>
                <span class="child-dep-chip">👦 عمر (أنشطة رياضية: 430 ر.س)</span>
                <span class="child-dep-chip">👶 فهد (تطعيمات وتموين: 290 ر.س)</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Metric Counters Bar -->
      <div class="metric-counter-strip" id="metrics">
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">100</span>%</div>
          <div class="counter-label" id="cnt-lbl-1">يعمل بدون اتصال (Offline-First)</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">0</span>%</div>
          <div class="counter-label" id="cnt-lbl-2">صفر تجسس على رسائل SMS البنكية</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number">&lt;<span class="accent">0.8</span>s</div>
          <div class="counter-label" id="cnt-lbl-3">سرعة فك تشفير فواتير ZATCA TLV</div>
        </div>
        <div class="counter-cell">
          <div class="counter-number"><span class="accent">31</span>/31</div>
          <div class="counter-label" id="cnt-lbl-4">مرونة تامة لأي يوم راتب تختاره</div>
        </div>
      </div>
    </section>

    <!-- 12-Pillar Bento Grid Section -->
    <section id="features">
      <div class="section-header-block">
        <span class="section-eyebrow-text" id="feat-eyebrow">منظومة مالية شاملة</span>
        <h3 class="section-main-heading" id="feat-h2">كل ما تحتاجه الأسرة السعودية في تطبيق واحد</h3>
        <p class="section-lead-copy" id="feat-sub">
          تم بناء كل ميزة لحل تحديات مالية حقيقية يواجهها الأفراد والأسر في المملكة مع تجربة مستخدم تتسم بالسهولة والجمال.
        </p>
      </div>

      <div class="asymmetric-bento-grid">
        <!-- 1. Flexible Salary Engine -->
        <div class="bento-surface-card span-col-8">
          <div>
            <div class="bento-icon-cell emerald">📅</div>
            <h4 class="bento-card-title" id="f1-t">دورة راتب مرنة وقواعد الصرف التلقائية</h4>
            <p class="bento-card-desc" id="f1-d">
              سواء كنت موظفاً حكومياً، أو في القطاع الخاص، أو تمارس عملاً حراً؛ حدد يوم راتبك الشهري بكل حرية. يطبق التطبيق القواعد المصرفية السعودية التلقائية (الصرف يوم الخميس إذا صادف الجمعة، ويوم الأحد إذا صادف السبت) مع احتساب معدل الصرف اليومي الآمن لتفادي نفاد الراتب مبكراً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تعديل أي يوم في الشهر</span>
            <span class="subtle-badge-chip">موازنة العطلات البنكية</span>
            <span class="subtle-badge-chip">معدل الصرف اليومي الآمن</span>
          </div>
        </div>

        <!-- 2. Conversational Saudi AI -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell cyan">✨</div>
            <h4 class="bento-card-title" id="f2-t">مساعد ذكي يفهم اللهجة السعودية</h4>
            <p class="bento-card-desc" id="f2-d">
              سجّل مشترياتك صوتياً أو كتابياً باللهجة المحلية أو الفصحى أو الإنجليزية. يفهم السياق فورياً ("عبيت بنزين 91 بـ 85 ريال") ويصنّفها بدقة متناهية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">شات فوري</span>
            <span class="subtle-badge-chip">تعرّف باللهجة</span>
          </div>
        </div>

        <!-- 3. Two-Tier Taxonomy & Hybrid LLM Subcategories -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell purple">📂</div>
            <h4 class="bento-card-title" id="f3-t">تصنيف هجين ثنائي المستويات</h4>
            <p class="bento-card-desc" id="f3-d">
              تصنيفات رئيسية وفرعية دقيقة (مثل: المطاعم > وجبات سريعة أو كافيهات). يختار الذكاء الاصطناعي التصنيف الفرعي الأنسب مع بطاقة تأكيد تفاعلية تتيح لك التعديل بمرونة.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تصنيف فرعي ذكي</span>
            <span class="subtle-badge-chip">بطاقة تأكيد قبل الحفظ</span>
          </div>
        </div>

        <!-- 4. ZATCA Phase 2 QR Scanner -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell emerald">🧾</div>
            <h4 class="bento-card-title" id="f4-t">ماسح فواتير ZATCA المرحلة الثانية</h4>
            <p class="bento-card-desc" id="f4-d">
              وجّه الكاميرا إلى أي فاتورة إلكترونية لفك شفرة رمز الاستجابة السريعة (Base64 TLV) بدقة 100% واستخراج اسم التاجر، الرقم الضريبي، وضريبة القيمة المضافة فورياً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تشفير TLV</span>
            <span class="subtle-badge-chip">احتساب الضريبة 15%</span>
          </div>
        </div>

        <!-- 5. 2D Partner Fair-Share Split -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell amber">👥</div>
            <h4 class="bento-card-title" id="f5-t">تقسيم عادل بين الشركاء</h4>
            <p class="bento-card-desc" id="f5-d">
              نظام توثيق ثنائي الأبعاد يرصد "من دفع" و"من استفاد" مع نسبة مخصصة للتقاسم لحساب التسويات الصافية والديون المتبادلة دون أي إحراج مالي.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">رمز دعوة عائلي</span>
            <span class="subtle-badge-chip">تسوية ديون فورية</span>
          </div>
        </div>

        <!-- 6. Children & Dependents Tracking -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell cyan">👶</div>
            <h4 class="bento-card-title" id="f6-t">تتبع نفقات الأبناء والتابعين</h4>
            <p class="bento-card-desc" id="f6-d">
              أضف أسماء الأبناء في إعدادات الأسرة وخصّص الفواتير لكل ابن (مصاريف المدارس، الأنشطة، المستلزمات الطبية) لمعرفة التكلفة الفعلية لكل فرد بدقة.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تخصيص لكل طفل</span>
            <span class="subtle-badge-chip">تقارير نفقات التابعين</span>
          </div>
        </div>

        <!-- 7. BNPL & Installments Tracker -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell purple">💳</div>
            <h4 class="bento-card-title" id="f7-t">متابعة أقساط تابي وتمارا والبطاقات</h4>
            <p class="bento-card-desc" id="f7-d">
              تتبّع خطط التقسيط عبر تابي، تمارا، أو البطاقات الائتمانية مع حلقات تقدم دائرية توضح المتبقي والتنبيه التلقائي قبل مواعيد السداد لتفادي الرسوم.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تابي & تمارا</span>
            <span class="subtle-badge-chip">تنبيه مواعيد الأقساط</span>
          </div>
        </div>

        <!-- 8. Recurring Bills & Cadence Engine -->
        <div class="bento-surface-card span-col-4">
          <div>
            <div class="bento-icon-cell amber">⚡</div>
            <h4 class="bento-card-title" id="f8-t">جدولة الفواتير والاشتراكات الدورية</h4>
            <p class="bento-card-desc" id="f8-d">
              كشف وجدولة فواتير الكهرباء (SEC)، والمياه (NWC)، والاتصالات (STC/Mobily)، ورسوم الإقامة والتأمين لتجنب الانقطاعات والمفاجآت.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">الكهرباء والمياه</span>
            <span class="subtle-badge-chip">تجديدات الاشتراكات</span>
          </div>
        </div>

        <!-- 9. Smart Grocery Comparison -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell emerald">🛒</div>
            <h4 class="bento-card-title" id="f9-t">مقارنة أسعار المقاضي وسلة التوفير</h4>
            <p class="bento-card-desc" id="f9-d">
              سجّل مشتريات السوبرماركت وقارن أسعار السلع الأساسية بين سلاسل المتاجر الكبرى في المملكة (بندة، كارفور، لولو، التميمي، الدانوب) لتوفير ما يصل إلى 20% شهرياً.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">تتبع تاريخ الأسعار</span>
            <span class="subtle-badge-chip">سلة المقاضي المثالية</span>
          </div>
        </div>

        <!-- 10. Purchase Affordability Simulator -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell cyan">🧭</div>
            <h4 class="bento-card-title" id="f10-t">حاسبة "هل أستطيع تحمل هذه التكلفة؟"</h4>
            <p class="bento-card-desc" id="f10-d">
              اختبر أي قرار شراء غير مخطط له قبل اتخاذه؛ يحسب التطبيق فورياً أثر الشراء على وتيرة صرف الأيام المتبقية في دورة الراتب وعلى احتياطي الادخار دون إرباك الميزانية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">محاكاة فورية للقرارات</span>
            <span class="subtle-badge-chip">حماية خطة الشهر</span>
          </div>
        </div>

        <!-- 11. Offline-First SQLite Engine -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell purple">⚡</div>
            <h4 class="bento-card-title" id="f11-t">يعمل بالكامل دون اتصال بالإنترنت</h4>
            <p class="bento-card-desc" id="f11-d">
              قاعدة بيانات SQLite محلية مدمجة تتيح لك تسجيل المصاريف ومسح الفواتير في أي وقت حتى بدون شبكة، مع مزامنة سحابية تلقائية وخوارزمية تشفير تمنع تكرار العمليات.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">مزامنة تلقائية</span>
            <span class="subtle-badge-chip">تشفير SHA-256</span>
          </div>
        </div>

        <!-- 12. Smart Savings Reserve & PDF Statements -->
        <div class="bento-surface-card span-col-6">
          <div>
            <div class="bento-icon-cell amber">📊</div>
            <h4 class="bento-card-title" id="f12-t">احتياطي الادخار وتقارير PDF الشهرية</h4>
            <p class="bento-card-desc" id="f12-d">
              يتحول الفائض غير المخصص تلقائياً إلى صندوق احتياطي الادخار الأسري، مع إمكانية تصدير كشوف حساب شهرية رسمية بصيغة PDF باللغتين العربية والإنجليزية.
            </p>
          </div>
          <div class="bento-tag-pills">
            <span class="subtle-badge-chip">صندوق طوارئ مالي</span>
            <span class="subtle-badge-chip">تقارير ضريبية ومالية</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Bank-Grade Security & Comparison Section -->
    <section class="security-matrix-card" id="security">
      <div class="section-header-block" style="margin-bottom: 30px;">
        <span class="section-eyebrow-text" id="comp-eyebrow">معايير أمان بنكية</span>
        <h3 class="section-main-heading" id="comp-h2">أمان بنكي وخصوصية تامة بدون تجسس</h3>
      </div>

      <div class="matrix-item-grid">
        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 id="cp-1-t">صفر تجسس على الرسائل النصية (SMS)</h4>
            <p id="cp-1-d">لا نطلب أي صلاحية مشبوهة لاعتراض الرسائل البنكية أو قراءة رسائل SMS في الخلفية كما تفعل التطبيقات القديمة.</p>
          </div>
        </div>

        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 id="cp-2-t">عزل تام لبيانات الأسرة (Row-Level Security)</h4>
            <p id="cp-2-d">بيانات كل أسرة معزولة مشفرة سحابياً ولا يمكن لأي مستخدم آخر الاطلاع على فلس واحد من مصروفاتكم.</p>
          </div>
        </div>

        <div class="matrix-cell-wrap">
          <div class="verified-check-mark">✓</div>
          <div class="matrix-cell-text">
            <h4 id="cp-3-t">حفظ السجلات بنسبة 100% وعدم الحذف النهائي</h4>
            <p id="cp-3-d">التصنيفات غير المستخدمة تتحول إلى حالة "غير نشطة" مع حفظ كامل تاريخ المصروفات والرسوم البيانية السابقة.</p>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ Accordion -->
    <section class="faq-wrapper-block" id="faq">
      <div class="section-header-block">
        <span class="section-eyebrow-text" id="faq-eyebrow">إجابات واضحة</span>
        <h3 class="section-main-heading" id="faq-h2">الأسئلة الشائعة</h3>
      </div>

      <div class="faq-accordion-item active">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span id="faq-q1">هل التطبيق محصور بيوم راتب معين (مثل يوم 27)؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" id="faq-a1">
          إطلاقاً! يمكنك ضبط يوم نزول الراتب على أي تاريخ في الشهر (1، 15، 25، 27 أو أي تاريخ يحدده جهة عملك). يتولى المحرك إعادة حساب الأيام المتبقية ومعدل الصرف اليومي الآمن بدقة وفق التاريخ الذي تختاره.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span id="faq-q2">كيف يتعامل التطبيق مع عطلات نهاية الأسبوع ومواعيد صرف الراتب في البنوك السعودية؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" id="faq-a2">
          يطبق التطبيق القواعد المصرفية المعتمدة في المملكة تلقائياً: إذا صادف يوم راتبك يوم الجمعة، يتم تقديم دورة الصرف إلى يوم الخميس. وإذا صادف يوم السبت، يتم ترحيلها إلى يوم الأحد لضمان دقة وتيرة الصرف اليومية.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span id="faq-q3">هل يمكنني تقسيم المصاريف وتحديد تكلفة كل ابن من أفراد الأسرة؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" id="faq-a3">
          نعم، يدعم التطبيق إدارة أفراد الأسرة وإضافة الأبناء؛ عند تسجيل أي فاتورة يمكنك تحديد من دفع المصروف (أنا أو الشريك) ولمن تم الصرف (أنا، الشريك، أو أحد الأبناء)، ويقوم التطبيق بحساب التسويات الصافية العادلة بدقة.
        </div>
      </div>

      <div class="faq-accordion-item">
        <button class="faq-header-trigger" onclick="toggleFaq(this)">
          <span id="faq-q4">هل يمكنني مسح الفواتير الإلكترونية ZATCA دون اتصال بالإنترنت؟</span>
          <span class="faq-plus-icon">+</span>
        </button>
        <div class="faq-body-collapse" id="faq-a4">
          نعم، فك شفرة Base64 TLV الخاصة بفواتير ZATCA يتم محلياً وبشكل فوري على جهازك وبسرعة فائقة حتى بدون أي اتصال بالإنترنت، ويتم حفظ الفاتورة في قاعدة بيانات SQLite المحلية لحين توفر الشبكة.
        </div>
      </div>
    </section>

    <!-- Legal Section -->
    <section class="legal-modal-strip" id="legal">
      <div class="legal-selector-tabs">
        <button class="legal-tab-action active" id="tab-privacy-btn" onclick="switchLegalTab('privacy')">سياسة الخصوصية</button>
        <button class="legal-tab-action" id="tab-terms-btn" onclick="switchLegalTab('terms')">شروط الاستخدام</button>
      </div>

      <div id="privacy-pane" class="legal-scroll-pane">
        <h4 id="lp-1">1. الالتزام الصارم بالخصوصية</h4>
        <p id="lp-1-txt">نحن في Budget Tracker نضع حماية بياناتك المالية فوق كل اعتبار. لا نطلب أي صلاحيات لاعتراض أو قراءة الرسائل النصية، ويتم عزل وتشفير بيانات كل أسرة سحابياً بأحدث معايير الأمان.</p>
        
        <h4 id="lp-2">2. البيانات المُعالجة</h4>
        <p id="lp-2-txt">يقتصر الاستخدام على البيانات التي يقدمها المستخدم طواعية: البريد الإلكتروني للمصادقة، ومصروفات الأسرة المدخلة يدوياً أو عبر الشات ومسح فواتير ZATCA.</p>
        
        <h4 id="lp-3">3. حق حذف الحساب والبيانات</h4>
        <p id="lp-3-txt">يحق للمستخدم طلب الحذف النهائي والشامل لحسابه وكافة سجلاته المالية في أي وقت عبر مراسلة الدعم الفني مباشرة على: abedmowafaq@gmail.com.</p>
      </div>

      <div id="terms-pane" class="legal-scroll-pane" style="display: none;">
        <h4 id="lt-1">1. الموافقة والامتثال</h4>
        <p id="lt-1-txt">باستخدامك لتطبيق وموقع Budget Tracker فإنك توافق على الالتزام بكافة الشروط والأحكام الموضحة هنا.</p>
        
        <h4 id="lt-2">2. الاستخدام للأغراض الشخصية والأسرية</h4>
        <p id="lt-2-txt">التطبيق مصمم لإدارة وتنظيم الميزانية الشخصية والأسرية وتقديم مؤشرات توجيهية ولا يمثل مشورة استثمارية أو مصرفية رسمية.</p>
        
        <h4 id="lt-3">3. الدعم الفني والاستفسارات</h4>
        <p id="lt-3-txt">لأي استفسارات أو مقترحات برمجية، يُرجى مراسلة المطور على: abedmowafaq@gmail.com.</p>
      </div>
    </section>

    <!-- Contact Banner -->
    <section class="contact-cta-hero" id="contact">
      <h3 class="contact-heading-text" id="contact-h">هل ترغب بالانضمام للنسخة التجريبية أو تقديم اقتراح؟</h3>
      <p class="contact-copy-text" id="contact-p">
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
        <a href="#stage" id="ft-sim">المحاكي</a>
        <a href="#metrics" id="ft-met">المؤشرات</a>
        <a href="#features" id="ft-feat">المميزات</a>
        <a href="#security" id="ft-comp">الأمان</a>
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
        navSim: 'Interactive Stage',
        navMetrics: 'Metrics',
        navFeat: 'Features',
        navSec: 'Bank Security',
        navFaq: 'FAQ',
        navContact: 'Support',
        heroBadgeText: 'Fintech Innovation • Works with Any Monthly Salary Cycle',
        heroH1Prefix: 'Absolute Mastery of Your Family Budget',
        heroH1Gradient: 'With Any Salary Date You Choose & AI Precision',
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
        cntLbl1: '100% Offline-First Architecture',
        cntLbl2: 'Zero SMS Interception or Snooping',
        cntLbl3: 'Sub-Second ZATCA TLV Verification',
        cntLbl4: 'Full Flexibility for Any Salary Day',
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
        ftMet: 'Metrics',
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
        navMetrics: 'المؤشرات',
        navFeat: 'المميزات',
        navSec: 'الأمان المصرفي',
        navFaq: 'الأسئلة الشائعة',
        navContact: 'الدعم الفني',
        heroBadgeText: 'الابتكار المالي للأسر • متوافق مع أي دورة راتب شهرية',
        heroH1Prefix: 'تحكّم مطلق في ميزانية أسرتك',
        heroH1Gradient: 'مع أي يوم راتب تختاره وبدقة الذكاء الاصطناعي',
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
        cntLbl1: 'يعمل بدون اتصال (Offline-First)',
        cntLbl2: 'صفر تجسس على رسائل SMS البنكية',
        cntLbl3: 'سرعة فك تشفير فواتير ZATCA TLV',
        cntLbl4: 'مرونة تامة لأي يوم راتب تختاره',
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
        ftMet: 'المؤشرات',
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
      background: #08080A;
      color: #C9D1D9;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      position: relative;
    }
    .card {
      background: #111116;
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
