# -*- coding: utf-8 -*-
"""
Builder script to generate _landing_impl.py and landing_page.py
for FMSCO Enterprise Budget & Cost Governance platform (budget.fmsco.com.sa).
Cinematic NURA Editorial Aesthetic with complete AR/EN translations.
"""
import pathlib

HERE = pathlib.Path(__file__).parent

LANDING_PAGE_PY = '''"""
Landing page and auth confirmation HTML generator for Budget Tracker (budget.fmsco.com.sa).

FMSCO Enterprise Budget and Cost Governance Platform. Cinematic Editorial Redesign.
Visual Reference: NURA editorial minimalism, monolithic concrete, warm light, heavy vignette.
Design System: Deep obsidian base, 1px specular micro-borders, glassmorphism cards.
Features: Bilingual AR/EN, Live Interactive Product Stage, Asymmetric Bento Grid,
          KPI Counters, FAQ, Legal, Developer Contact (abedmowafaq@gmail.com).
"""

import os

try:
    from ai_service._landing_impl import LANDING_HTML, AUTH_CONFIRM_HTML, AUTH_CALLBACK_HTML
except ImportError:
    from _landing_impl import LANDING_HTML, AUTH_CONFIRM_HTML, AUTH_CALLBACK_HTML


def get_landing_page_html() -> str:
    static_index = os.path.join(os.path.dirname(__file__), "static", "index.html")
    if os.path.exists(static_index):
        with open(static_index, "r", encoding="utf-8") as f:
            return f.read()
    return LANDING_HTML


def get_auth_confirm_html() -> str:
    return AUTH_CONFIRM_HTML


def get_auth_confirmed_html() -> str:
    return AUTH_CONFIRM_HTML


def get_auth_callback_html() -> str:
    return AUTH_CALLBACK_HTML
'''

LANDING_HTML_CONTENT = r'''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Budget Tracker • ميزانية الأسرة الذكية</title>
  <meta name="description" content="منصة Budget لإدارة ميزانية الأسرة والحوكمة المالية في السعودية. دورة راتب مرنة، مسح فواتير ZATCA بالذكاء الاصطناعي، تقسيم المصاريف بين الشركاء والأبناء.">

  <!-- Favicon: stylized Budget brandmark in obsidian with glowing terracotta accent -->
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Cdefs%3E%3ClinearGradient id='g' x1='0%25' y1='0%25' x2='100%25' y2='100%25'%3E%3Cstop offset='0%25' stop-color='%23C2783C'/%3E%3Cstop offset='100%25' stop-color='%23F5C06E'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='%23080709' stroke='%23C2783C' stroke-width='2' stroke-opacity='0.4'/%3E%3Ctext x='48%25' y='55%25' dominant-baseline='middle' text-anchor='middle' font-family='Georgia,serif' font-style='italic' font-weight='bold' font-size='38' fill='url(%23g)'%3EB%3C/text%3E%3Ccircle cx='48' cy='46' r='4' fill='%23F0A05A'/%3E%3C/svg%3E">

  <!-- Typography: Cairo, Plus Jakarta Sans, Playfair Display, Space Mono -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=Playfair+Display:ital,wght@1,500;1,600;1,700;1,800&family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800;900&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">

  <style>
    :root {
      --canvas:       #080709;
      --canvas-2:     #0D0C10;
      --surface:      #121117;
      --surface-2:    #17161F;
      --surface-3:    #1F1D2B;
      --border:       rgba(255,255,255,0.08);
      --border-h:     rgba(255,255,255,0.22);
      --spec:         inset 0 1px 0 rgba(255,255,255,0.12);
      --terra:        #C2783C;
      --terra-b:      #F0A05A;
      --terra-d:      rgba(194,120,60,0.14);
      --terra-g:      rgba(240,160,90,0.24);
      --amber:        #F5C06E;
      --emerald:      #34D399;
      --emerald-d:    rgba(52,211,153,0.12);
      --cyan:         #38BDF8;
      --cyan-d:       rgba(56,189,248,0.12);
      --purple:       #A855F7;
      --purple-d:     rgba(168,85,247,0.12);
      --t0: #FFFFFF;
      --t1: #F0EDE8;
      --t2: #9E9790;
      --t3: #5C5650;
      --fa: 'Cairo', sans-serif;
      --fe: 'Plus Jakarta Sans', sans-serif;
      --fi: 'Playfair Display', Georgia, serif;
      --fm: 'Space Mono', monospace;
      --r-sm: 10px; --r-md: 16px; --r-lg: 24px; --r-xl: 32px;
      --mw: 1280px;
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    html { scroll-behavior: smooth; }
    body {
      background: var(--canvas); color: var(--t1);
      font-family: var(--fa); min-height: 100vh;
      overflow-x: hidden; -webkit-font-smoothing: antialiased; line-height: 1.65;
    }
    body.en { font-family: var(--fe); direction: ltr; }

    /* Atmosphere & Lighting */
    .atmo {
      position: absolute; inset: 0; height: 100vh;
      pointer-events: none; z-index: 0; overflow: hidden;
    }
    .atmo::before {
      content: ''; position: absolute; inset: 0;
      background:
        radial-gradient(ellipse 85% 60% at 50% -10%, rgba(70,48,22,0.60) 0%, transparent 68%),
        radial-gradient(ellipse 55% 45% at 20% 30%, rgba(35,24,12,0.45) 0%, transparent 60%),
        radial-gradient(ellipse 65% 50% at 80% 25%, rgba(28,20,10,0.40) 0%, transparent 60%),
        linear-gradient(180deg, rgba(12,10,8,0.25) 0%, rgba(8,7,9,0.85) 60%, var(--canvas) 100%);
    }
    .godray {
      position: absolute; top: -100px; left: 50%; transform: translateX(-50%);
      width: 580px; height: 960px;
      background: conic-gradient(from 178deg at 50% 0%,
        rgba(255,205,130,0.12) 0deg, rgba(194,120,60,0.08) 10deg,
        transparent 25deg, transparent 335deg,
        rgba(194,120,60,0.06) 350deg, rgba(255,205,130,0.12) 360deg);
      filter: blur(55px); opacity: 0.95; mix-blend-mode: screen;
    }
    .noise {
      position: fixed; inset: 0;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='300'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.75' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='300' height='300' filter='url(%23n)' opacity='0.038'/%3E%3C/svg%3E");
      pointer-events: none; z-index: 1; opacity: 0.6;
    }
    .dots {
      position: fixed; inset: 0;
      background-image: radial-gradient(rgba(255,255,255,0.04) 1px, transparent 1px);
      background-size: 38px 38px; pointer-events: none; z-index: 0;
      mask-image: radial-gradient(ellipse 80% 60% at 50% 25%, black 30%, transparent 80%);
      -webkit-mask-image: radial-gradient(ellipse 80% 60% at 50% 25%, black 30%, transparent 80%);
    }

    .wrap { max-width: var(--mw); margin: 0 auto; padding: 0 32px; position: relative; z-index: 2; }

    /* Sticky Minimalist Header */
    header { position: fixed; top: 0; left: 0; right: 0; z-index: 200; transition: background .4s, border-color .4s; }
    header.on { background: rgba(8,7,9,0.85); backdrop-filter: blur(28px) saturate(160%); -webkit-backdrop-filter: blur(28px) saturate(160%); border-bottom: 1px solid var(--border); }
    .nav { display: flex; align-items: center; justify-content: space-between; height: 74px; }
    .brand { display: flex; align-items: center; gap: 10px; text-decoration: none; color: inherit; }
    .bwm { font-family: var(--fe); font-size: 21px; font-weight: 800; letter-spacing: -0.02em; color: var(--t0); }
    .bdot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: var(--terra-b); box-shadow: 0 0 10px var(--terra-b); margin-inline-start: 2px; vertical-align: middle; }
    .bsub { font-size: 11px; font-weight: 700; color: var(--t2); letter-spacing: .08em; text-transform: uppercase; border-inline-start: 1px solid var(--border); padding-inline-start: 10px; }
    .navlinks { display: flex; align-items: center; gap: 28px; list-style: none; }
    .navlinks a { color: var(--t2); text-decoration: none; font-size: 13px; font-weight: 600; letter-spacing: .03em; transition: color .2s; }
    .navlinks a:hover { color: var(--t0); }
    .navr { display: flex; align-items: center; gap: 14px; }
    .lsw { display: flex; background: rgba(255,255,255,.05); border: 1px solid var(--border); border-radius: 999px; padding: 3px; gap: 2px; }
    .lbtn { background: transparent; border: none; color: var(--t2); font-family: inherit; font-size: 11.5px; font-weight: 700; padding: 5px 13px; border-radius: 999px; cursor: pointer; transition: all .2s; letter-spacing: .03em; }
    .lbtn.on { background: var(--t0); color: var(--canvas); box-shadow: 0 2px 8px rgba(0,0,0,.5); }
    .ctap { background: #FFFFFF; color: #080709; font-size: 12.5px; font-weight: 700; padding: 9px 22px; border-radius: 999px; text-decoration: none; letter-spacing: .03em; transition: all .25s; box-shadow: 0 0 20px rgba(255,255,255,.2); }
    .ctap:hover { background: #F0EDE8; box-shadow: 0 0 28px rgba(255,255,255,.4); transform: translateY(-1px); }

    /* Full 100vh Hero with Floating Cinematic Background */
    .hero { position: relative; min-height: 100vh; display: flex; flex-direction: column; justify-content: flex-end; padding-bottom: 84px; overflow: hidden; }
    .hero-bg {
      position: absolute; inset: 0;
      background-color: #080709;
      background-image:
        linear-gradient(180deg, rgba(8,7,9,0.30) 0%, rgba(8,7,9,0.10) 25%, rgba(8,7,9,0.75) 65%, var(--canvas) 100%),
        linear-gradient(90deg, rgba(8,7,9,0.92) 0%, rgba(8,7,9,0.60) 45%, rgba(8,7,9,0.20) 100%),
        url('/hero-bg.webp'), url('/hero-bg.jpg');
      background-size: cover;
      background-position: center 30%;
      background-repeat: no-repeat;
      z-index: 0;
      transform: scale(1.02);
      animation: heroFloat 28s ease-in-out infinite alternate;
    }
    body.en .hero-bg {
      background-image:
        linear-gradient(180deg, rgba(8,7,9,0.30) 0%, rgba(8,7,9,0.10) 25%, rgba(8,7,9,0.75) 65%, var(--canvas) 100%),
        linear-gradient(270deg, rgba(8,7,9,0.92) 0%, rgba(8,7,9,0.60) 45%, rgba(8,7,9,0.20) 100%),
        url('/hero-bg.webp'), url('/hero-bg.jpg');
    }
    @keyframes heroFloat {
      0% { transform: scale(1.02) translateY(0); }
      100% { transform: scale(1.07) translateY(-10px); }
    }
    .hero-light {
      position: absolute; top: 0; right: 0; width: 50%; height: 75%;
      background: radial-gradient(ellipse 65% 85% at 100% 0%, rgba(194,120,60,.22) 0%, rgba(120,80,30,.09) 45%, transparent 70%);
      pointer-events: none; z-index: 0;
    }
    .hero-c { position: relative; z-index: 2; max-width: var(--mw); margin: 0 auto; padding: 0 32px; width: 100%; }
    .eyebrow { font-family: var(--fm); font-size: 11px; font-weight: 700; color: var(--terra-b); letter-spacing: .24em; text-transform: uppercase; margin-bottom: 24px; display: flex; align-items: center; gap: 12px; }
    .eyebrow::before { content: ''; display: inline-block; width: 34px; height: 1px; background: var(--terra); }
    .h1 { font-size: clamp(48px,7.5vw,96px); font-weight: 900; line-height: 1.02; letter-spacing: -.035em; color: var(--t0); max-width: 860px; margin-bottom: 22px; }
    .h1i { font-family: var(--fi); font-style: italic; font-weight: 600; font-size: .95em; background: linear-gradient(120deg,var(--terra),var(--amber)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; display: block; letter-spacing: -.02em; }
    .hsub { font-size: clamp(15.5px,1.8vw,19px); color: var(--t2); max-width: 600px; line-height: 1.75; margin-bottom: 44px; font-weight: 400; }
    .hact { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; margin-bottom: 64px; }
    .bp { background: var(--terra); color: #fff; font-family: inherit; font-size: 14px; font-weight: 700; padding: 14px 32px; border-radius: 12px; border: none; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; transition: all .3s; box-shadow: 0 0 28px rgba(194,120,60,.5),var(--spec); letter-spacing: .02em; }
    .bp:hover { background: var(--terra-b); box-shadow: 0 0 44px rgba(240,160,90,.7); transform: translateY(-2px); }
    .bg { background: rgba(255,255,255,.05); color: var(--t1); font-family: inherit; font-size: 14px; font-weight: 600; padding: 14px 30px; border-radius: 12px; border: 1px solid var(--border); cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; transition: all .25s; backdrop-filter: blur(12px); }
    .bg:hover { border-color: var(--border-h); background: rgba(255,255,255,.08); transform: translateY(-1px); }
    .scroll-ind { display: flex; align-items: center; gap: 10px; color: var(--t3); font-size: 11px; font-weight: 600; letter-spacing: .12em; text-transform: uppercase; animation: flt 3s ease-in-out infinite; }
    .scroll-ind svg { animation: by 1.8s ease-in-out infinite; }
    @keyframes flt { 0%,100%{opacity:.5} 50%{opacity:1} }
    @keyframes by { 0%,100%{transform:translateY(0)} 50%{transform:translateY(5px)} }

    /* Section Typography */
    section { position: relative; z-index: 2; }
    .seye { font-family: var(--fm); font-size: 11px; font-weight: 700; color: var(--terra-b); letter-spacing: .2em; text-transform: uppercase; display: block; margin-bottom: 14px; }
    .stit { font-size: clamp(28px,3.6vw,48px); font-weight: 900; color: var(--t0); line-height: 1.15; letter-spacing: -.025em; margin-bottom: 16px; }
    .sbod { font-size: 17px; color: var(--t2); max-width: 680px; line-height: 1.8; }
    .sh { margin-bottom: 60px; }
    .sh.c { text-align: center; }
    .sh.c .sbod { margin: 0 auto; }

    /* Store Badges */
    .stores { display: flex; justify-content: center; flex-wrap: wrap; gap: 16px; margin-bottom: 84px; }
    .sc { display: flex; align-items: center; gap: 14px; background: var(--surface); border: 1px solid var(--border); box-shadow: var(--spec),0 12px 32px rgba(0,0,0,.45); padding: 14px 24px; border-radius: var(--r-md); min-width: 210px; text-decoration: none; color: inherit; transition: all .3s cubic-bezier(.16,1,.3,1); }
    .sc:hover { transform: translateY(-3px); border-color: var(--border-h); box-shadow: var(--spec),0 20px 44px rgba(0,0,0,.6),0 0 24px var(--terra-g); }
    .si { width: 42px; height: 42px; background: rgba(255,255,255,.04); border-radius: 12px; border: 1px solid var(--border); display: flex; align-items: center; justify-content: center; font-size: 22px; flex-shrink: 0; }
    .sm { text-align: start; }
    .ss { font-size: 10.5px; color: var(--t3); font-weight: 600; letter-spacing: .04em; text-transform: uppercase; }
    .sn { font-size: 14.5px; font-weight: 800; color: var(--t0); display: flex; align-items: center; gap: 8px; }
    .chip { background: rgba(194,120,60,.16); border: 1px solid rgba(194,120,60,.4); color: var(--terra-b); font-size: 10.5px; font-weight: 800; padding: 2px 8px; border-radius: 6px; }

    /* Interactive Product Stage */
    .stgw { max-width: 1040px; margin: 0 auto 110px; background: linear-gradient(180deg,rgba(22,20,28,.92) 0%,rgba(10,9,14,.98) 100%); border: 1px solid var(--border); border-radius: var(--r-xl); box-shadow: 0 40px 90px rgba(0,0,0,.8),0 0 60px var(--terra-d),var(--spec); overflow: hidden; }
    .stgb { display: flex; align-items: center; justify-content: space-between; padding: 18px 28px; background: rgba(14,12,18,.95); border-bottom: 1px solid var(--border); }
    .tl { display: flex; gap: 8px; }
    .dl { width: 11px; height: 11px; border-radius: 50%; }
    .dl.r{background:#FF5F56} .dl.y{background:#FFBD2E} .dl.g{background:#27C93F}
    .stabs { display: flex; gap: 6px; background: rgba(255,255,255,.04); padding: 4px; border-radius: 12px; border: 1px solid var(--border); }
    .stab { background: transparent; border: none; color: var(--t2); font-family: inherit; font-size: 12.5px; font-weight: 700; padding: 8px 16px; border-radius: 8px; cursor: pointer; transition: all .2s; display: flex; align-items: center; gap: 6px; }
    .stab.on { background: var(--terra-d); color: var(--terra-b); box-shadow: 0 2px 12px var(--terra-d); }
    .stab:hover:not(.on) { color: var(--t0); background: rgba(255,255,255,.05); }
    .stgbody { padding: 34px 30px; }
    .tp { display: none; }
    .tp.on { display: block; animation: fu .3s cubic-bezier(.16,1,.3,1); }
    @keyframes fu { from{opacity:0;transform:translateY(8px)} to{opacity:1;transform:translateY(0)} }

    .simbox { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 30px; box-shadow: var(--spec); }
    .simh { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; flex-wrap: wrap; gap: 10px; }
    .simt { font-size: 15.5px; font-weight: 800; color: var(--t0); display: flex; align-items: center; gap: 8px; }
    .rlbl { display: flex; justify-content: space-between; font-size: 12.5px; color: var(--t2); margin-bottom: 12px; }
    .rlbl strong { color: var(--terra-b); font-size: 16px; }
    input[type=range] { width: 100%; height: 8px; border-radius: 999px; background: rgba(255,255,255,.09); outline: none; -webkit-appearance: none; cursor: pointer; }
    input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 22px; height: 22px; border-radius: 50%; background: var(--terra-b); box-shadow: 0 0 14px var(--terra); border: 2px solid #fff; cursor: grab; transition: transform .15s; }
    input[type=range]::-webkit-slider-thumb:hover { transform: scale(1.15); }
    .mtrio { display: grid; grid-template-columns: repeat(auto-fit,minmax(210px,1fr)); gap: 16px; margin-top: 24px; }
    .ms { background: var(--surface-2); border: 1px solid var(--border); border-radius: var(--r-md); padding: 18px; position: relative; overflow: hidden; box-shadow: var(--spec); }
    .ms::before { content: ''; position: absolute; top: 0; left: 0; width: 3px; height: 100%; }
    .ms.t::before{background:var(--terra-b)} .ms.c::before{background:var(--cyan)} .ms.a::before{background:var(--amber)}
    .ml { font-size: 12px; color: var(--t2); margin-bottom: 6px; font-weight: 600; }
    .mv { font-size: 23px; font-weight: 900; color: var(--t0); line-height: 1.2; }
    .msb { font-size: 11px; color: var(--t3); margin-top: 6px; }

    .chatbox { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 26px; display: flex; flex-direction: column; gap: 14px; }
    .bu { align-self: flex-start; background: rgba(56,189,248,.10); border: 1px solid rgba(56,189,248,.25); padding: 12px 20px; border-radius: 18px 18px 4px 18px; font-size: 14.5px; color: #E0F2FE; max-width: 80%; }
    body.en .bu { border-radius: 18px 18px 18px 4px; }
    .bai { align-self: flex-end; background: rgba(194,120,60,.08); border: 1px solid rgba(194,120,60,.24); border-radius: 18px 18px 18px 4px; padding: 20px; width: 94%; }
    body.en .bai { border-radius: 18px 18px 4px 18px; }
    .apc { background: #08070A; border: 1px solid var(--border); border-radius: 14px; padding: 18px; margin-top: 10px; }
    .acr { font-size: 15.5px; font-weight: 800; color: var(--t0); display: flex; justify-content: space-between; margin-bottom: 12px; }
    .tg { font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 6px; display: inline-flex; align-items: center; gap: 4px; }
    .tg.cat{background:rgba(168,85,247,.14);color:#C084FC;border:1px solid rgba(168,85,247,.3)}
    .tg.sub{background:rgba(56,189,248,.14);color:#7DD3FC;border:1px solid rgba(56,189,248,.3)}
    .tg.paid{background:rgba(52,211,153,.14);color:#34D399;border:1px solid rgba(52,211,153,.3)}
    .tg.for{background:var(--terra-d);color:var(--terra-b);border:1px solid rgba(194,120,60,.35)}
    .trow { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }

    .zatp { background: radial-gradient(circle at center,rgba(16,22,30,.8) 0%,#07060A 100%); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 32px; display: flex; flex-direction: column; align-items: center; position: relative; overflow: hidden; }
    .laser { position: absolute; top: 0; left: 10%; right: 10%; height: 2px; background: linear-gradient(90deg,transparent,var(--emerald),var(--cyan),transparent); box-shadow: 0 0 14px var(--emerald),0 0 28px var(--cyan); animation: sw 3s ease-in-out infinite alternate; }
    @keyframes sw { 0%{top:12%;opacity:.3} 50%{opacity:1} 100%{top:88%;opacity:.3} }
    .zatc { display: grid; grid-template-columns: 130px 1fr; gap: 24px; align-items: center; width: 100%; max-width: 620px; background: var(--surface-2); border: 1px solid rgba(52,211,153,.25); border-radius: 18px; padding: 22px; box-shadow: 0 10px 28px rgba(0,0,0,.5); }
    .qrb { width: 120px; height: 120px; background: #fff; border-radius: 10px; display: flex; align-items: center; justify-content: center; padding: 6px; }
    .zatd h5 { font-size: 16px; font-weight: 800; color: #fff; margin-bottom: 6px; }
    .dl2 { display: flex; justify-content: space-between; font-size: 13px; color: var(--t2); padding: 4px 0; border-bottom: 1px solid rgba(255,255,255,.05); }
    .dl2 strong { color: var(--t0); }

    .splitp { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 28px; }
    .splitbar { height: 12px; background: rgba(255,255,255,.07); border-radius: 999px; display: flex; overflow: hidden; margin: 16px 0 22px; }
    .sy { background: linear-gradient(90deg,var(--terra),#E87B40); transition: width .3s; }
    .sp { background: linear-gradient(90deg,var(--cyan),#0284C7); transition: width .3s; }
    .dchips { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; }
    .dc { background: rgba(168,85,247,.10); border: 1px solid rgba(168,85,247,.28); padding: 6px 14px; border-radius: 999px; font-size: 13px; color: #E9D5FF; display: inline-flex; align-items: center; gap: 6px; }

    /* Animated KPI Counters */
    .kpis { display: grid; grid-template-columns: repeat(auto-fit,minmax(210px,1fr)); gap: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); box-shadow: var(--spec),0 20px 50px rgba(0,0,0,.45); margin-bottom: 110px; overflow: hidden; }
    .kc { padding: 34px 28px; text-align: center; border-inline-end: 1px solid var(--border); transition: background .3s; }
    .kc:last-child { border-inline-end: none; }
    .kc:hover { background: var(--surface-2); }
    .kn { font-size: 42px; font-weight: 900; letter-spacing: -.03em; color: var(--t0); line-height: 1.1; margin-bottom: 6px; }
    .kn .acc { color: var(--terra-b); }
    .kl { font-size: 13.5px; color: var(--t2); font-weight: 600; }

    /* 12-Pillar Bento Grid */
    .bento { display: grid; grid-template-columns: repeat(12,1fr); gap: 20px; margin-bottom: 120px; }
    .bc { background: var(--surface); border: 1px solid var(--border); box-shadow: var(--spec),0 18px 40px rgba(0,0,0,.35); border-radius: var(--r-lg); padding: 32px 26px; position: relative; overflow: hidden; transition: all .35s cubic-bezier(.16,1,.3,1); display: flex; flex-direction: column; justify-content: space-between; min-height: 200px; }
    .bc:hover { background: var(--surface-2); transform: translateY(-4px); border-color: var(--border-h); box-shadow: var(--spec),0 28px 64px rgba(0,0,0,.55),0 0 32px var(--terra-d); }
    .bc::after { content: ''; position: absolute; top: 0; left: 15%; right: 15%; height: 1px; background: linear-gradient(90deg,transparent,var(--terra),transparent); opacity: 0; transition: opacity .35s; }
    .bc:hover::after { opacity: 1; }
    .s8{grid-column:span 8} .s4{grid-column:span 4} .s6{grid-column:span 6} .s12{grid-column:span 12}
    .bi { width: 50px; height: 50px; border-radius: 14px; display: flex; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 20px; border: 1px solid var(--border); flex-shrink: 0; }
    .bi.t{background:var(--terra-d);border-color:rgba(194,120,60,.3)}
    .bi.e{background:var(--emerald-d);border-color:rgba(52,211,153,.3)}
    .bi.c{background:rgba(56,189,248,.10);border-color:rgba(56,189,248,.3)}
    .bi.p{background:rgba(168,85,247,.10);border-color:rgba(168,85,247,.3)}
    .bi.a{background:rgba(245,192,110,.10);border-color:rgba(245,192,110,.3)}
    .bt { font-size: 19px; font-weight: 800; color: var(--t0); margin-bottom: 10px; line-height: 1.3; }
    .bd { font-size: 14.5px; color: var(--t2); line-height: 1.75; margin-bottom: 18px; }
    .bch { display: flex; gap: 8px; flex-wrap: wrap; }
    .bchip { font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 999px; background: rgba(255,255,255,.04); border: 1px solid var(--border); color: var(--t2); }
    .bst { font-size: 44px; font-weight: 900; letter-spacing: -.03em; color: var(--t0); line-height: 1.05; margin: 12px 0 6px; }
    .bst .acc { color: var(--terra-b); }
    .bsl { font-size: 13px; color: var(--t2); font-weight: 600; }

    /* Privacy Architecture (No SMS / No Bank) */
    .priv { background: linear-gradient(180deg,rgba(18,16,24,.8) 0%,rgba(10,9,13,.98) 100%); border: 1px solid var(--border); border-radius: var(--r-xl); padding: 54px 46px; margin-bottom: 120px; box-shadow: var(--spec); }
    .pgrid { display: grid; grid-template-columns: repeat(auto-fit,minmax(280px,1fr)); gap: 28px; margin-top: 40px; }
    .pi { display: flex; gap: 16px; align-items: flex-start; }
    .ckb { width: 28px; height: 28px; border-radius: 8px; background: var(--emerald-d); border: 1px solid var(--emerald); color: var(--emerald); display: flex; align-items: center; justify-content: center; font-size: 14px; font-weight: 900; flex-shrink: 0; margin-top: 2px; }
    .pt h4 { font-size: 15.5px; font-weight: 800; color: var(--t0); margin-bottom: 4px; }
    .pt p { font-size: 14px; color: var(--t2); line-height: 1.6; }

    /* FAQ */
    .faqw { max-width: 880px; margin: 0 auto 120px; }
    .faqit { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-md); margin-bottom: 12px; overflow: hidden; transition: all .25s; }
    .faqit.op { border-color: rgba(194,120,60,.35); background: var(--surface-2); }
    .faqtr { width: 100%; text-align: start; background: none; border: none; color: var(--t0); font-family: inherit; font-size: 15.5px; font-weight: 700; padding: 22px 26px; display: flex; justify-content: space-between; align-items: center; cursor: pointer; }
    .faqic { font-size: 18px; color: var(--terra-b); transition: transform .25s; }
    .faqit.op .faqic { transform: rotate(45deg); }
    .faqbd { display: none; padding: 0 26px 22px; color: var(--t2); font-size: 15px; line-height: 1.8; border-top: 1px solid rgba(255,255,255,.04); padding-top: 16px; }
    .faqit.op .faqbd { display: block; }

    /* Contact & Legal */
    .contact { background: radial-gradient(ellipse 70% 60% at 60% 0%,var(--terra-g) 0%,transparent 65%),var(--surface); border: 1px solid rgba(194,120,60,.3); border-radius: var(--r-xl); padding: 60px 40px; text-align: center; margin-bottom: 100px; position: relative; overflow: hidden; box-shadow: 0 28px 70px rgba(0,0,0,.65),0 0 60px var(--terra-d),var(--spec); }
    .ch { font-size: clamp(24px,3.5vw,38px); font-weight: 900; color: var(--t0); margin-bottom: 14px; }
    .cp { color: var(--t2); font-size: 16px; max-width: 640px; margin: 0 auto 34px; line-height: 1.75; }
    .ep { display: inline-flex; align-items: center; gap: 12px; background: var(--canvas); border: 1px solid rgba(255,255,255,.14); padding: 14px 34px; border-radius: 999px; color: var(--t0); font-size: 15.5px; font-weight: 800; text-decoration: none; transition: all .3s; }
    .ep:hover { border-color: var(--terra-b); background: rgba(194,120,60,.12); color: var(--terra-b); transform: translateY(-2px); box-shadow: 0 16px 40px rgba(194,120,60,.25); }
    .vipf { display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; max-width: 540px; margin: 0 auto 14px; }
    .vipf input[type=email] { flex: 1 1 240px; min-width: 0; background: var(--canvas); border: 1px solid rgba(255,255,255,.14); border-radius: 999px; padding: 14px 24px; color: var(--t0); font-family: inherit; font-size: 15px; direction: ltr; }
    .vipf input[type=email]::placeholder { color: var(--t3); }
    .vipf input[type=email]:focus-visible, .vipf button:focus-visible { outline: 2px solid var(--terra-b); outline-offset: 2px; }
    .vipf .bp { border-radius: 999px; }
    .vipf .bp[disabled] { opacity: .65; cursor: wait; transform: none; }
    .vipmsg { max-width: 540px; margin: 0 auto 26px; font-size: 14px; font-weight: 700; line-height: 1.7; }
    .vipmsg:empty { display: none; }
    .vipmsg.ok { color: var(--emerald); }
    .vipmsg.err { color: #FCA5A5; }
    .vsr { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border: 0; }
    .hpf { position: absolute; left: -10000px; width: 1px; height: 1px; overflow: hidden; }

    .legc { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 40px 36px; margin-bottom: 100px; }
    .ltabs { display: flex; gap: 10px; border-bottom: 1px solid var(--border); padding-bottom: 16px; margin-bottom: 22px; }
    .ltab { background: none; border: none; color: var(--t2); font-family: inherit; font-size: 14.5px; font-weight: 700; padding: 8px 18px; border-radius: 8px; cursor: pointer; transition: all .2s; }
    .ltab.on { color: var(--terra-b); background: var(--terra-d); }
    .lscr { max-height: 270px; overflow-y: auto; padding-right: 12px; font-size: 14px; color: var(--t2); line-height: 1.8; }
    .lscr h4 { color: var(--t0); margin: 14px 0 7px; font-size: 14.5px; }

    /* Footer */
    footer { border-top: 1px solid var(--border); padding: 48px 0 56px; text-align: center; color: var(--t3); font-size: 13.5px; }
    .flinks { display: flex; justify-content: center; gap: 28px; flex-wrap: wrap; margin-bottom: 18px; }
    .flinks a { color: var(--t2); text-decoration: none; font-weight: 600; transition: color .2s; }
    .flinks a:hover { color: var(--terra-b); }
    .fstat { display: inline-flex; align-items: center; gap: 7px; margin-bottom: 14px; font-size: 12px; color: var(--t3); }
    .ldot { width: 7px; height: 7px; border-radius: 50%; background: var(--emerald); box-shadow: 0 0 8px var(--emerald); animation: pls 2s ease-in-out infinite; }
    @keyframes pls { 0%,100%{opacity:1} 50%{opacity:.4} }

    @media(max-width:992px){
      .s8,.s4,.s6{grid-column:span 12}
      .zatc{grid-template-columns:1fr;justify-items:center;text-align:center}
      .navlinks{display:none}
      .kpis{grid-template-columns:1fr 1fr}
      .kc:nth-child(2){border-inline-end:none}
      .kc:nth-child(odd){border-inline-end:1px solid var(--border)}
    }
    @media(max-width:720px){
      .stgb{flex-direction:column;gap:14px}
      .stabs{width:100%;overflow-x:auto}
      .sc{width:100%;justify-content:center}
      .priv{padding:32px 20px}
      .contact{padding:36px 20px}
      .kpis{grid-template-columns:1fr}
      .kc{border-inline-end:none!important;border-bottom:1px solid var(--border)}
      .kc:last-child{border-bottom:none}
    }
  </style>
</head>
<body id="pb">

<div class="atmo"><div class="godray"></div></div>
<div class="noise"></div>
<div class="dots"></div>

<!-- STICKY MINIMALIST HEADER -->
<header id="hdr">
  <div class="wrap nav">
    <a href="/" class="brand">
      <span class="bwm">BUDGET<span class="bdot"></span></span>
      <span class="bsub" data-i18n="brandSub">Tracker • ميزانية الأسرة</span>
    </a>
    <ul class="navlinks">
      <li><a href="#stage"    data-i18n="n1">المحاكي</a></li>
      <li><a href="#metrics"  data-i18n="n2">المؤشرات</a></li>
      <li><a href="#features" data-i18n="n3">المميزات</a></li>
      <li><a href="#security" data-i18n="n4">الخصوصية</a></li>
      <li><a href="#faq"      data-i18n="n5">الأسئلة</a></li>
      <li><a href="#contact"  data-i18n="n6">التواصل</a></li>
    </ul>
    <div class="navr">
      <div class="lsw">
        <button class="lbtn on" id="btn-ar" onclick="setL('ar')">العربية</button>
        <button class="lbtn"    id="btn-en" onclick="setL('en')">English</button>
      </div>
      <a href="#stage" class="ctap" data-i18n="nc">جرّب المحاكي</a>
    </div>
  </div>
</header>

<!-- 100VH HERO VIEWPORT (NURA EDITORIAL MINIMALISM) -->
<section class="hero" id="hero">
  <div class="hero-bg"></div>
  <div class="hero-light"></div>
  <div class="hero-c">
    <div class="eyebrow" data-i18n="ey">نظام حوكمة الميزانية العائلية • المملكة العربية السعودية</div>
    <h1 class="h1">
      <span data-i18n="h1a">تحكّم مطلق في</span>
      <span class="h1i" data-i18n="h1b">ميزانية الأسرة.</span>
    </h1>
    <p class="hsub" data-i18n="hs">منصة Budget لإدارة المصاريف والحوكمة المالية للأسرة السعودية — دورة راتب مرنة لأي يوم، ومساعد ذكاء اصطناعي، ومسح فواتير ZATCA، وتوزيع عادل بين الشركاء والأبناء.</p>
    <div class="hact">
      <a href="#stage"    class="bp" data-i18n="c1">⚡ ابدأ التجربة الحية</a>
      <a href="#features" class="bg" data-i18n="c2">← استكشف المميزات الـ 12</a>
    </div>
    <div class="scroll-ind" data-i18n="si">
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M8 3v10M8 13l-4-4M8 13l4-4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
      مرر للأسفل لاكتشاف المنصة
    </div>
  </div>
</section>

<main class="wrap">

  <!-- STORE BADGES -->
  <div class="stores" style="margin-top:80px">
    <div class="sc"><div class="si">🤖</div><div class="sm"><div class="ss" data-i18n="ss">متوفر قريباً على</div><div class="sn">Google Play <span class="chip" data-i18n="ch1">قريباً</span></div></div></div>
    <div class="sc"><div class="si">🍎</div><div class="sm"><div class="ss" data-i18n="ss">متوفر قريباً على</div><div class="sn">App Store <span class="chip" data-i18n="ch2">قريباً</span></div></div></div>
    <div class="sc"><div class="si">🛍️</div><div class="sm"><div class="ss" data-i18n="ss">متوفر قريباً على</div><div class="sn">AppGallery <span class="chip" data-i18n="ch3">قريباً</span></div></div></div>
  </div>

  <!-- INTERACTIVE PRODUCT STAGE -->
  <div id="stage" style="scroll-margin-top:90px">
    <div class="sh c">
      <span class="seye" data-i18n="ste">LIVE INTERACTIVE DEMO</span>
      <h2 class="stit" data-i18n="stt">جرّب المنصة الآن — مباشرةً في المتصفح</h2>
      <p class="sbod" data-i18n="stb">أربعة سيناريوهات تفاعلية تحاكي تجربة التطبيق الكاملة بدقة. لا تسجيل، لا تحميل.</p>
    </div>
  </div>

  <div class="stgw">
    <div class="stgb">
      <div class="tl"><div class="dl r"></div><div class="dl y"></div><div class="dl g"></div></div>
      <div class="stabs">
        <button class="stab on" id="s1" onclick="swTab('sim')">📅 <span data-i18n="t1">دورة الراتب</span></button>
        <button class="stab"    id="s2" onclick="swTab('ai')">✨ <span data-i18n="t2">مساعد الذكاء</span></button>
        <button class="stab"    id="s3" onclick="swTab('zatca')">🧾 <span data-i18n="t3">فواتير ZATCA</span></button>
        <button class="stab"    id="s4" onclick="swTab('split')">👥 <span data-i18n="t4">توزيع الأسرة</span></button>
      </div>
      <div class="ldot" style="margin:0 6px"></div>
    </div>
    <div class="stgbody">

      <!-- Tab 1: Simulator -->
      <div id="p-sim" class="tp on">
        <div class="simbox">
          <div class="simh">
            <div class="simt">⚙️ <span data-i18n="simT">حدد يوم نزول راتبك الشهري (1 - 31)</span></div>
            <div class="chip" style="font-size:12px;padding:4px 10px;background:rgba(52,211,153,.13);border-color:rgba(52,211,153,.35);color:#34D399;" data-i18n="simB">✓ موازنة العطلات تلقائياً</div>
          </div>
          <div style="margin-bottom:22px">
            <div class="rlbl">
              <span data-i18n="sm1">اليوم 1</span>
              <span><span data-i18n="smc">يوم الراتب:</span> <strong id="sv">25</strong></span>
              <span data-i18n="sm2">اليوم 31</span>
            </div>
            <input type="range" min="1" max="31" value="25" id="pslider" oninput="updSim(this.value)">
          </div>
          <div class="mtrio">
            <div class="ms t"><div class="ml" data-i18n="ml1">الأيام المتبقية في الدورة</div><div class="mv" id="sd">14 <small style="font-size:13px" data-i18n="dy">يوم</small></div><div class="msb" data-i18n="ms1">دورة نشطة متوازنة</div></div>
            <div class="ms c"><div class="ml" data-i18n="ml2">معدل الصرف اليومي الآمن</div><div class="mv" id="sr">345 <small style="font-size:13px" id="srunit">ر.س/يوم</small></div><div class="msb" data-i18n="ms2">يحميك من نفاد الميزانية مبكراً</div></div>
            <div class="ms a"><div class="ml" data-i18n="ml3">احتياطي الادخار التلقائي</div><div class="mv" id="sres">4,500 <small style="font-size:13px" id="sresunit">ر.س</small></div><div class="msb" data-i18n="ms3">فائض محفوظ للطوارئ</div></div>
          </div>
        </div>
      </div>

      <!-- Tab 2: AI Chat -->
      <div id="p-ai" class="tp">
        <div class="chatbox">
          <div class="bu" data-i18n="cu">"عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة"</div>
          <div class="bai">
            <div style="font-size:12.5px;color:var(--terra-b);font-weight:700;margin-bottom:8px">🤖 <span data-i18n="cai">تم استخراج المعاملة بالذكاء الاصطناعي بدقة عالية</span></div>
            <div class="apc">
              <div class="acr"><span data-i18n="cm">مطعم البيك (وجبة عائلية)</span><span style="color:var(--terra-b)">68.00 <span class="cur-unit">ر.س</span></span></div>
              <div class="trow">
                <span class="tg cat" data-i18n="tc">🍔 المطاعم والتغذية</span>
                <span class="tg sub" data-i18n="ts">🍟 وجبات سريعة</span>
                <span class="tg paid" data-i18n="tp2">👤 دفع: أنا</span>
                <span class="tg for" data-i18n="tf">👨‍👩‍👧 لصالح: الأسرة</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab 3: ZATCA -->
      <div id="p-zatca" class="tp">
        <div class="zatp">
          <div class="laser"></div>
          <div class="zatc">
            <div class="qrb">
              <svg viewBox="0 0 21 21" style="width:100%;height:100%">
                <rect width="21" height="21" fill="#fff"/>
                <rect x="1" y="1" width="7" height="7" fill="#000"/><rect x="2" y="2" width="5" height="5" fill="#fff"/><rect x="3" y="3" width="3" height="3" fill="#000"/>
                <rect x="13" y="1" width="7" height="7" fill="#000"/><rect x="14" y="2" width="5" height="5" fill="#fff"/><rect x="15" y="3" width="3" height="3" fill="#000"/>
                <rect x="1" y="13" width="7" height="7" fill="#000"/><rect x="2" y="14" width="5" height="5" fill="#fff"/><rect x="3" y="15" width="3" height="3" fill="#000"/>
                <rect x="9" y="1" width="1" height="1" fill="#000"/><rect x="11" y="1" width="1" height="1" fill="#000"/>
                <rect x="9" y="3" width="1" height="1" fill="#000"/><rect x="11" y="5" width="1" height="1" fill="#000"/>
                <rect x="9" y="7" width="3" height="1" fill="#000"/><rect x="9" y="9" width="1" height="1" fill="#000"/>
                <rect x="13" y="9" width="1" height="3" fill="#000"/><rect x="17" y="9" width="1" height="3" fill="#000"/>
                <rect x="1" y="9" width="3" height="1" fill="#000"/><rect x="5" y="9" width="1" height="3" fill="#000"/>
                <rect x="7" y="11" width="5" height="1" fill="#000"/><rect x="11" y="13" width="1" height="5" fill="#000"/>
                <rect x="13" y="13" width="3" height="1" fill="#000"/><rect x="17" y="13" width="1" height="1" fill="#000"/>
              </svg>
            </div>
            <div class="zatd" style="width:100%">
              <h5 data-i18n="zt">مسح فوري للفاتورة الضريبية</h5>
              <div style="font-size:11.5px;color:var(--emerald);margin-bottom:8px" data-i18n="zs">مطابق لهيئة الزكاة والضريبة والجمارك ZATCA</div>
              <div class="dl2"><span data-i18n="zmv">اسم المنشأة:</span><strong data-i18n="zm">متجر الدانوب (فرع النخيل)</strong></div>
              <div class="dl2"><span data-i18n="ztt">المجموع الكلي:</span><strong style="color:var(--terra-b)">245.50 <span class="cur-unit">ر.س</span></strong></div>
              <div class="dl2"><span data-i18n="zvt">ضريبة القيمة المضافة (15%):</span><strong>32.02 <span class="cur-unit">ر.س</span></strong></div>
              <div class="dl2"><span data-i18n="zdt">التاريخ والوقت:</span><span>2026-10-11 14:32</span></div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tab 4: Split -->
      <div id="p-split" class="tp">
        <div class="splitp">
          <div style="display:flex;justify-content:space-between;align-items:center">
            <span style="font-size:15px;font-weight:800;color:var(--t0)" data-i18n="spt">محاكاة توزيع المصاريف بين الشركاء والأبناء</span>
            <span class="chip" style="background:rgba(56,189,248,.12);border-color:rgba(56,189,248,.35);color:#7DD3FC">توزيع عادل</span>
          </div>
          <div class="splitbar">
            <div class="sy" id="spty" style="width:60%"></div>
            <div class="sp" id="sptp" style="width:40%"></div>
          </div>
          <div style="display:flex;justify-content:space-between;font-size:13px;color:var(--t2)">
            <div><span style="display:inline-block;width:10px;height:10px;background:var(--terra);border-radius:2px;margin-inline-end:6px"></span><span data-i18n="spy">حصة الشريك الأول (أنت)</span>: <strong style="color:var(--t0)" id="pcy">60%</strong></div>
            <div><span style="display:inline-block;width:10px;height:10px;background:var(--cyan);border-radius:2px;margin-inline-end:6px"></span><span data-i18n="spp">حصة الشريك الثاني</span>: <strong style="color:var(--t0)" id="pcp">40%</strong></div>
          </div>
          <div class="dchips">
            <div class="dc">👶 سارة (ابنة) — 340 <span class="cur-unit">ر.س</span></div>
            <div class="dc">👦 عمر (ابن) — 280 <span class="cur-unit">ر.س</span></div>
            <div class="dc">🏠 مصاريف مشتركة للمنزل — 1,200 <span class="cur-unit">ر.س</span></div>
          </div>
        </div>
      </div>

    </div>
  </div>

  <!-- KPI METRICS -->
  <div id="metrics" style="scroll-margin-top:90px">
    <div class="kpis">
      <div class="kc"><div class="kn"><span class="acc" id="k1">0</span>+</div><div class="kl" data-i18n="kl1">تصنيف ذكي للمصاريف</div></div>
      <div class="kc"><div class="kn"><span class="acc" id="k2">0</span>%</div><div class="kl" data-i18n="kl2">دقة استخراج البيانات بالذكاء الاصطناعي</div></div>
      <div class="kc"><div class="kn"><span class="acc" id="k3">0</span></div><div class="kl" data-i18n="kl3">يوم مرن لدورة الراتب</div></div>
      <div class="kc"><div class="kn"><span class="acc" id="k4">0</span>%</div><div class="kl" data-i18n="kl4">خصوصية — لا بنك ولا SMS</div></div>
    </div>
  </div>

  <!-- 12-PILLAR BENTO GRID -->
  <div id="features" style="scroll-margin-top:90px">
    <div class="sh">
      <span class="seye" data-i18n="be">CAPABILITIES</span>
      <h2 class="stit" data-i18n="bt">اثنا عشر ركيزة لحوكمة مالية متكاملة</h2>
      <p class="sbod" data-i18n="bb">نظام متكامل يغطي كل جوانب إدارة مصاريف الأسرة السعودية بدون تعقيد.</p>
    </div>
  </div>

  <div class="bento">
    <!-- 1 -->
    <div class="bc s8">
      <div>
        <div class="bi t">✨</div>
        <div class="bt" data-i18n="b1t">مساعد الذكاء الاصطناعي التفاعلي</div>
        <div class="bd" data-i18n="b1d">سجّل أي مصروف بجملة عربية أو إنجليزية طبيعية. يستخرج الذكاء الاصطناعي المبلغ والمتجر والفئة والدافع والمستفيد — مع بطاقة تأكيد تفاعلية قبل الحفظ.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b1c1">معالجة لغوية NLP</span>
        <span class="bchip" data-i18n="b1c2">تصنيف تلقائي</span>
        <span class="bchip" data-i18n="b1c3">بطاقة تأكيد قبل الحفظ</span>
      </div>
    </div>
    <!-- 2 -->
    <div class="bc s4">
      <div>
        <div class="bi e">📅</div>
        <div class="bt" data-i18n="b2t">دورة الراتب المرنة</div>
        <div class="bd" data-i18n="b2d">حدد يوم راتبك بحرية تامة من 1 إلى 31. يحسب التطبيق الأيام المتبقية والمعدل الآمن يومياً مع موازنة تلقائية للعطلات.</div>
      </div>
      <div class="bst"><span class="acc">1-31</span></div>
      <div class="bsl" data-i18n="b2sl">مرونة كاملة في اختيار يوم الراتب</div>
    </div>
    <!-- 3 -->
    <div class="bc s6">
      <div>
        <div class="bi c">🧾</div>
        <div class="bt" data-i18n="b3t">ماسح فواتير ZATCA بالذكاء الاصطناعي</div>
        <div class="bd" data-i18n="b3d">امسح رمز QR لأي فاتورة إلكترونية سعودية واستخرج المبلغ، الضريبة (15%)، اسم المنشأة، والتاريخ فورياً بدقة متناهية.</div>
      </div>
      <div class="bch">
        <span class="bchip">OCR ذكي</span>
        <span class="bchip" data-i18n="b3c2">مطابق لـ ZATCA</span>
        <span class="bchip" data-i18n="b3c3">استخراج فوري</span>
      </div>
    </div>
    <!-- 4 -->
    <div class="bc s6">
      <div>
        <div class="bi p">👨‍👩‍👧‍👦</div>
        <div class="bt" data-i18n="b4t">توزيع الشركاء والأبناء</div>
        <div class="bd" data-i18n="b4d">حدد من دفع ولمن — الشريك أو الأبناء المسجلون. توزيع عادل وشفاف يمنحك وضوحاً كاملاً حول حصة كل فرد في ميزانية الأسرة.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b4c1">دفع بواسطة</span>
        <span class="bchip" data-i18n="b4c2">لصالح الأبناء</span>
        <span class="bchip" data-i18n="b4c3">توزيع نسبي</span>
      </div>
    </div>
    <!-- 5 -->
    <div class="bc s4">
      <div>
        <div class="bi a">📊</div>
        <div class="bt" data-i18n="b5t">لوحة التحكم اللحظية</div>
        <div class="bd" data-i18n="b5d">رسوم بيانية ومؤشرات فورية للمصاريف، الميزانية المتبقية، معدل الصرف اليومي، والمدى الزمني حتى الراتب القادم.</div>
      </div>
      <div class="bch">
        <span class="bchip">معدل الصرف اليومي</span>
        <span class="bchip">مدرج الميزانية</span>
      </div>
    </div>
    <!-- 6 -->
    <div class="bc s8">
      <div>
        <div class="bi t">🏷️</div>
        <div class="bt" data-i18n="b6t">تصنيفات وفئات فرعية مخصصة</div>
        <div class="bd" data-i18n="b6d">أنشئ فئاتك الرئيسية وفئاتك الفرعية الخاصة على مستوى منزلك. يقترح الذكاء الاصطناعي التصنيف تلقائياً ويمكنك تعديل أي معاملة في أي وقت بعد الحفظ.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b6c1">فئات مخصصة</span>
        <span class="bchip" data-i18n="b6c2">فئات فرعية دقيقة</span>
        <span class="bchip" data-i18n="b6c3">اقتراح ذكاء اصطناعي</span>
        <span class="bchip" data-i18n="b6c4">تعديل بعد الحفظ</span>
      </div>
    </div>
    <!-- 7 -->
    <div class="bc s6">
      <div>
        <div class="bi e">💰</div>
        <div class="bt" data-i18n="b7t">الادخار والاحتياطي التلقائي</div>
        <div class="bd" data-i18n="b7d">يحسب النظام الفائض المتبقي عند نهاية كل دورة مالية ويقترح ترحيله تلقائياً لصندوق الطوارئ أو أهداف الادخار المحددة مسبقاً.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b7c1">احتياطي طوارئ</span>
        <span class="bchip" data-i18n="b7c2">أهداف ادخار</span>
      </div>
    </div>
    <!-- 8 -->
    <div class="bc s6">
      <div>
        <div class="bi c">🔒</div>
        <div class="bt" data-i18n="b8t">خصوصية مطلقة — لا SMS ولا بنك</div>
        <div class="bd" data-i18n="b8d">لا يطلب التطبيق أذونات قراءة الرسائل القصيرة ولا يطلب ربطاً بنكياً. بياناتك مشفّرة بالكامل داخل سحابة Supabase الآمنة.</div>
      </div>
      <div class="bst"><span class="acc">100</span><span style="font-size:22px">%</span></div>
      <div class="bsl" data-i18n="b8sl">بيانات مشفّرة وخصوصية محفوظة بالكامل</div>
    </div>
    <!-- 9 -->
    <div class="bc s4">
      <div>
        <div class="bi p">🗂️</div>
        <div class="bt" data-i18n="b9t">سجل المعاملات والتدقيق</div>
        <div class="bd" data-i18n="b9d">سجل زمني متكامل مع فلاتر ذكية حسب التاريخ أو الفئة أو عضو الأسرة، مع إمكانية التعديل وإعادة التصنيف أو الحذف متى شئت.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b9c1">تعديل لاحق</span>
        <span class="bchip" data-i18n="b9c2">فلاتر متقدمة</span>
      </div>
    </div>
    <!-- 10 -->
    <div class="bc s8">
      <div>
        <div class="bi t">🏠</div>
        <div class="bt" data-i18n="b10t">إعدادات المنزل والأسرة</div>
        <div class="bd" data-i18n="b10d">سجّل أسماء الشريك والأبناء لتخصيص تجربة التوزيع. اختر المستفيد من قائمة أفراد أسرتك بدقة لضمان إدارة مالية عادلة ومفصّلة.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b10c1">الشريك</span>
        <span class="bchip" data-i18n="b10c2">الأبناء والتابعون</span>
        <span class="bchip" data-i18n="b10c3">هوية المنزل</span>
      </div>
    </div>
    <!-- 11 -->
    <div class="bc s6">
      <div>
        <div class="bi a">📈</div>
        <div class="bt" data-i18n="b11t">تقارير وتحليلات شهرية</div>
        <div class="bd" data-i18n="b11d">مقارنات شهرية تفصيلية للمصاريف حسب الفئة والدافع والمستفيد، مع كشف مؤشرات الهدر وتحليل السلوك المالي عبر الزمن.</div>
      </div>
      <div class="bch">
        <span class="bchip">مقارنة شهرية</span>
        <span class="bchip">تحليل سلوك الصرف</span>
      </div>
    </div>
    <!-- 12 -->
    <div class="bc s6">
      <div>
        <div class="bi e">🎤</div>
        <div class="bt" data-i18n="b12t">إدخال صوتي باللهجة السعودية</div>
        <div class="bd" data-i18n="b12d">سجّل مصروفك بصوتك وبلهجتك الطبيعية. يتعرف الذكاء الاصطناعي على الكلمات السعودية المحلية ويحوّلها إلى معاملات منظمة وفورية.</div>
      </div>
      <div class="bch">
        <span class="bchip" data-i18n="b12c1">لهجة سعودية محلية</span>
        <span class="bchip" data-i18n="b12c2">تحويل صوت لنص</span>
      </div>
    </div>
  </div>

  <!-- PRIVACY ARCHITECTURE -->
  <div id="security" style="scroll-margin-top:90px">
    <div class="priv">
      <div class="sh">
        <span class="seye" data-i18n="pe">PRIVACY & SECURITY</span>
        <h2 class="stit" data-i18n="pt2">بياناتك ملكك — خصوصية مطلقة</h2>
        <p class="sbod" data-i18n="pb">صُمم التطبيق لحماية خصوصيتك بالكامل. لا قراءة لرسائل SMS، لا ربط بالحسابات البنكية، لا مشاركة مع أي طرف ثالث.</p>
      </div>
      <div class="pgrid">
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p1h">لا SMS — لا قراءة لرسائلك الشخصية</h4><p data-i18n="p1p">التطبيق لا يطلب إذن قراءة الرسائل القصيرة إطلاقاً. إدخال يدوي أو صوتي أو مسح QR فقط.</p></div></div>
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p2h">لا ربط بنكي — خصوصية مالية تامة</h4><p data-i18n="p2p">لا اتصال بأنظمة البنوك ولا حاجة لبيانات الدخول المصرفية. أنت من يتحكم بما يتم تسجيله.</p></div></div>
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p3h">تشفير متطور للبيانات</h4><p data-i18n="p3p">بيانات Supabase مشفّرة بأحدث معايير الأمان المعتمدة مع عزل صارم بين الحسابات.</p></div></div>
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p4h">هوية أفراد الأسرة محمية</h4><p data-i18n="p4p">بيانات منزلك والأبناء مسجلة فقط في نطاق حسابك الخاص ولا يتم مشاركتها خارجياً.</p></div></div>
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p5h">دورة راتب مرنة ومحلية</h4><p data-i18n="p5p">تحديد يوم راتبك يُستخدم حصراً لحساب فترتك المالية داخل التطبيق لتنظيم ميزانيتك.</p></div></div>
        <div class="pi"><div class="ckb">✓</div><div class="pt"><h4 data-i18n="p6h">مراجعة وتأكيد إلزامي قبل الحفظ</h4><p data-i18n="p6p">كل إدخال — نصي أو صوتي أو مسح فاتورة — يمر ببطاقة مراجعة لتؤكده قبل الحفظ.</p></div></div>
      </div>
    </div>
  </div>

  <!-- FAQ -->
  <div id="faq" style="scroll-margin-top:90px">
    <div class="sh c"><span class="seye">FAQ</span><h2 class="stit" data-i18n="ft">أسئلة شائعة</h2></div>
  </div>
  <div class="faqw">
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq1">هل يقرأ التطبيق رسائل SMS البنكية؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa1">لا تماماً. التطبيق لا يطلب إذن قراءة الرسائل نهائياً. الإدخال يدوي أو صوتي أو عبر مسح QR الفاتورة فقط — خصوصيتك وأمان هاتفك خط أحمر.</div></div>
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq2">كيف يعمل مسح فاتورة ZATCA بالذكاء الاصطناعي؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa2">تفتح كاميرا التطبيق وتمسح رمز QR لأي فاتورة إلكترونية سعودية متوافقة مع ZATCA. يستخرج التطبيق اسم المنشأة، الإجمالي، وضريبة القيمة المضافة 15% والتاريخ فورياً.</div></div>
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq3">كيف أُضيف أسماء أبنائي وشريكي لتوزيع المصاريف؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa3">من إعدادات التطبيق تحت "هوية المنزل"، أضف أسماء الشريك والأبناء. عند تسجيل أي مصروف تختار بضغطة زر "لصالح من" لتقسيم النفقات بدقة وشفافية.</div></div>
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq4">هل يمكنني تعديل معاملة أو تصنيفها بعد حفظها؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa4">نعم بكل تأكيد. يمكنك تعديل المبلغ، الفئة، الفئة الفرعية، أو الدافع والمستفيد لأي معاملة في أي وقت من سجل المعاملات.</div></div>
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq5">ما الفرق بين الفئة الرئيسية والفئة الفرعية؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa5">الفئة الرئيسية مثل (مطاعم وتغذية)، والفئة الفرعية أدق مثل (وجبات سريعة — البيك، كنتاكي). يمكنك تخصيص فئاتك الفرعية لتناسب نمط إنفاق أسرتك بدقة.</div></div>
    <div class="faqit" onclick="tgFaq(this)"><button class="faqtr"><span data-i18n="fq6">هل التطبيق متوفر للتحميل الآن؟</span><span class="faqic">+</span></button><div class="faqbd" data-i18n="fa6">التطبيق قيد المرحلة التجريبية المتقدمة وسيُطرح قريباً على Google Play وApp Store وAppGallery. يمكنك التواصل مع المطور للحصول على وصول تجريبي مبكر.</div></div>
  </div>

  <!-- LEGAL & COMPLIANCE -->
  <div class="legc">
    <div class="sh"><span class="seye">LEGAL</span><h2 class="stit" style="font-size:clamp(22px,3vw,32px)" data-i18n="lt">الشروط والخصوصية</h2></div>
    <div class="ltabs">
      <button class="ltab on" onclick="swLeg('p',this)" data-i18n="ll1">سياسة الخصوصية</button>
      <button class="ltab"    onclick="swLeg('t',this)" data-i18n="ll2">شروط الاستخدام</button>
    </div>
    <div id="lp" class="lscr">
      <h4 data-i18n="lp1h">جمع البيانات والخصوصية</h4><p data-i18n="lp1p">لا نقوم بجمع أو طلب بيانات بنكية أو صلاحيات SMS. تُخزّن كافة بيانات الميزانية مشفرة داخل قاعدة بيانات Supabase المؤمنة ولا يتم بيعها أو مشاركتها.</p>
      <h4 data-i18n="lp2h">معالجة الذكاء الاصطناعي</h4><p data-i18n="lp2p">تُعالج الرسائل النصية والصوتية بواسطة نماذج الذكاء الاصطناعي لاستخراج بيانات المصروف فقط ولا تُستخدم لتدريب نماذج عامة دون موافقة.</p>
      <h4 data-i18n="lp3h">حذف الحساب والبيانات</h4><p data-i18n="lp3p">يحق للمستخدم طلب الحذف الكامل لحسابه وسجلاته في أي وقت عبر إعدادات التطبيق أو عبر مراسلة الدعم الفني.</p>
    </div>
    <div id="lt2" class="lscr" style="display:none">
      <h4 data-i18n="lt1h">نطاق الاستخدام</h4><p data-i18n="lt1p">المنصة مخصصة لإدارة وحوكمة ميزانيات الأسر والأفراد في المملكة العربية السعودية للاستخدام الشخصي غير التجاري.</p>
      <h4 data-i18n="lt2h">المسؤولية المالية</h4><p data-i18n="lt2p">التطبيق يقدم أدوات تنظيمية واقتراحات استرشادية مبنية على الذكاء الاصطناعي ولا يُعد بديلاً عن المشورة المالية الرسمية.</p>
      <h4 data-i18n="lt3h">التحديثات والتطوير</h4><p data-i18n="lt3p">تحتفظ إدارة منصة FMSCO بحق تحديث المزايا والشروط دورياً لتحسين جودة وأمان الخدمة مع إشعار المستخدمين.</p>
    </div>
  </div>

  <!-- CONTACT -->
  <div id="contact" class="contact" style="scroll-margin-top:90px">
    <h2 class="ch" data-i18n="cth">هل لديك استفسار أو ترغب بنسخة تجريبية مبكرة؟</h2>
    <p class="cp" data-i18n="ctp">فريق FMSCO الهندسي مرحّب بملاحظاتك واستفساراتك للمساهمة في تقديم أفضل تجربة مالية للأسرة.</p>
    <form id="vip-form" class="vipf" novalidate onsubmit="vipSubmit(event)">
      <label for="vip-email" class="vsr" data-i18n="vipl">البريد الإلكتروني للانضمام إلى قائمة الوصول المبكر VIP</label>
      <input id="vip-email" name="email" type="email" required maxlength="254" autocomplete="email" placeholder="بريدك الإلكتروني" aria-describedby="vip-msg">
      <div class="hpf" aria-hidden="true"><input id="vip-hp" name="company_website" type="text" tabindex="-1" autocomplete="off"></div>
      <button id="vip-btn" type="submit" class="bp" data-i18n="vipb">انضم لقائمة VIP</button>
    </form>
    <p id="vip-msg" class="vipmsg" role="status" aria-live="polite"></p>
    <a href="mailto:abedmowafaq@gmail.com" class="ep">✉ abedmowafaq@gmail.com</a>
  </div>

</main>

<!-- FOOTER -->
<footer>
  <div class="wrap">
    <div class="fstat"><div class="ldot"></div><span data-i18n="fs">جميع الأنظمة تعمل بكفاءة</span></div>
    <div class="flinks">
      <a href="#features" data-i18n="fl1">المميزات</a>
      <a href="#security" data-i18n="fl2">الخصوصية</a>
      <a href="#faq"      data-i18n="fl3">الأسئلة</a>
      <a href="mailto:abedmowafaq@gmail.com">abedmowafaq@gmail.com</a>
    </div>
    <p>© 2026 Budget Tracker • <span data-i18n="fm">صُنع بـ ❤️ للأسر السعودية</span></p>
  </div>
</footer>

<!-- BILINGUAL TRANSLATION & INTERACTIVITY SCRIPT -->
<script>
const T = {
  ar: {
    brandSub: "Tracker • ميزانية الأسرة",
    n1: "المحاكي", n2: "المؤشرات", n3: "المميزات", n4: "الخصوصية", n5: "الأسئلة", n6: "التواصل", nc: "جرّب المحاكي",
    ey: "نظام حوكمة الميزانية العائلية • المملكة العربية السعودية",
    h1a: "تحكّم مطلق في",
    h1b: "ميزانية الأسرة.",
    hs: "منصة Budget لإدارة المصاريف والحوكمة المالية للأسرة السعودية — دورة راتب مرنة لأي يوم، ومساعد ذكاء اصطناعي، ومسح فواتير ZATCA، وتوزيع عادل بين الشركاء والأبناء.",
    c1: "⚡ ابدأ التجربة الحية",
    c2: "← استكشف المميزات الـ 12",
    si: "مرر للأسفل لاكتشاف المنصة",
    ss: "متوفر قريباً على",
    ch1: "قريباً", ch2: "قريباً", ch3: "قريباً",
    ste: "LIVE INTERACTIVE DEMO",
    stt: "جرّب المنصة الآن — مباشرةً في المتصفح",
    stb: "أربعة سيناريوهات تفاعلية تحاكي تجربة التطبيق الكاملة بدقة. لا تسجيل، لا تحميل.",
    t1: "دورة الراتب", t2: "مساعد الذكاء", t3: "فواتير ZATCA", t4: "توزيع الأسرة",
    simT: "حدد يوم نزول راتبك الشهري (1 - 31)",
    simB: "✓ موازنة العطلات تلقائياً",
    sm1: "اليوم 1", smc: "يوم الراتب:", sm2: "اليوم 31",
    ml1: "الأيام المتبقية في الدورة", dy: "يوم", ms1: "دورة نشطة متوازنة",
    ml2: "معدل الصرف اليومي الآمن", ms2: "يحميك من نفاد الميزانية مبكراً",
    ml3: "احتياطي الادخار التلقائي", ms3: "فائض محفوظ للطوارئ",
    cu: "\"عشاء عائلي في البيك بـ 68 ريال، دفعتها أنا للأسرة\"",
    cai: "تم استخراج المعاملة بالذكاء الاصطناعي بدقة عالية",
    cm: "مطعم البيك (وجبة عائلية)",
    tc: "🍔 المطاعم والتغذية", ts: "🍟 وجبات سريعة", tp2: "👤 دفع: أنا", tf: "👨‍👩‍👧 لصالح: الأسرة",
    zt: "مسح فوري للفاتورة الضريبية",
    zs: "مطابق لهيئة الزكاة والضريبة والجمارك ZATCA",
    zm: "متجر الدانوب (فرع النخيل)",
    zmv: "اسم المنشأة:", ztt: "المجموع الكلي:", zvt: "ضريبة القيمة المضافة (15%):", zdt: "التاريخ والوقت:",
    spt: "محاكاة توزيع المصاريف بين الشركاء والأبناء",
    spy: "حصة الشريك الأول (أنت)", spp: "حصة الشريك الثاني",
    kl1: "تصنيف ذكي للمصاريف",
    kl2: "دقة استخراج البيانات بالذكاء الاصطناعي",
    kl3: "يوم مرن لدورة الراتب",
    kl4: "خصوصية — لا بنك ولا SMS",
    be: "CAPABILITIES",
    bt: "اثنا عشر ركيزة لحوكمة مالية متكاملة",
    bb: "نظام متكامل يغطي كل جوانب إدارة مصاريف الأسرة السعودية بدون تعقيد.",
    b1t: "مساعد الذكاء الاصطناعي التفاعلي",
    b1d: "سجّل أي مصروف بجملة عربية أو إنجليزية طبيعية. يستخرج الذكاء الاصطناعي المبلغ والمتجر والفئة والدافع والمستفيد — مع بطاقة تأكيد تفاعلية قبل الحفظ.",
    b1c1: "معالجة لغوية NLP", b1c2: "تصنيف تلقائي", b1c3: "بطاقة تأكيد قبل الحفظ",
    b2t: "دورة الراتب المرنة",
    b2d: "حدد يوم راتبك بحرية تامة من 1 إلى 31. يحسب التطبيق الأيام المتبقية والمعدل الآمن يومياً مع موازنة تلقائية للعطلات.",
    b2sl: "مرونة كاملة في اختيار يوم الراتب",
    b3t: "ماسح فواتير ZATCA بالذكاء الاصطناعي",
    b3d: "امسح رمز QR لأي فاتورة إلكترونية سعودية واستخرج المبلغ، الضريبة (15%)، اسم المنشأة، والتاريخ فورياً بدقة متناهية.",
    b3c2: "مطابق لـ ZATCA", b3c3: "استخراج فوري",
    b4t: "توزيع الشركاء والأبناء",
    b4d: "حدد من دفع ولمن — الشريك أو الأبناء المسجلون. توزيع عادل وشفاف يمنحك ووضوحاً كاملاً حول حصة كل فرد في ميزانية الأسرة.",
    b4c1: "دفع بواسطة", b4c2: "لصالح الأبناء", b4c3: "توزيع نسبي",
    b5t: "لوحة التحكم اللحظية",
    b5d: "رسوم بيانية ومؤشرات فورية للمصاريف، الميزانية المتبقية، معدل الصرف اليومي، والمدى الزمني حتى الراتب القادم.",
    b6t: "تصنيفات وفئات فرعية مخصصة",
    b6d: "أنشئ فئاتك الرئيسية وفئاتك الفرعية الخاصة على مستوى منزلك. يقترح الذكاء الاصطناعي التصنيف تلقائياً ويمكنك تعديل أي معاملة في أي وقت بعد الحفظ.",
    b6c1: "فئات مخصصة", b6c2: "فئات فرعية دقيقة", b6c3: "اقتراح ذكاء اصطناعي", b6c4: "تعديل بعد الحفظ",
    b7t: "الادخار والاحتياطي التلقائي",
    b7d: "يحسب النظام الفائض المتبقي عند نهاية كل دورة مالية ويقترح ترحيله تلقائياً لصندوق الطوارئ أو أهداف الادخار المحددة مسبقاً.",
    b7c1: "احتياطي طوارئ", b7c2: "أهداف ادخار",
    b8t: "خصوصية مطلقة — لا SMS ولا بنك",
    b8d: "لا يطلب التطبيق أذونات قراءة الرسائل القصيرة ولا يطلب ربطاً بنكياً. بياناتك مشفّرة بالكامل داخل سحابة Supabase الآمنة.",
    b8sl: "بيانات مشفّرة وخصوصية محفوظة بالكامل",
    b9t: "سجل المعاملات والتدقيق",
    b9d: "سجل زمني متكامل مع فلاتر ذكية حسب التاريخ أو الفئة أو عضو الأسرة، مع إمكانية التعديل وإعادة التصنيف أو الحذف متى شئت.",
    b9c1: "تعديل لاحق", b9c2: "فلاتر متقدمة",
    b10t: "إعدادات المنزل والأسرة",
    b10d: "سجّل أسماء الشريك والأبناء لتخصيص تجربة التوزيع. اختر المستفيد من قائمة أفراد أسرتك بدقة لضمان إدارة مالية عادلة ومفصّلة.",
    b10c1: "الشريك", b10c2: "الأبناء والتابعون", b10c3: "هوية المنزل",
    b11t: "تقارير وتحليلات شهرية",
    b11d: "مقارنات شهرية تفصيلية للمصاريف حسب الفئة والدافع والمستفيد، مع كشف مؤشرات الهدر وتحليل السلوك المالي عبر الزمن.",
    b12t: "إدخال صوتي باللهجة السعودية",
    b12d: "سجّل مصروفك بصوتك وبلهجتك الطبيعية. يتعرف الذكاء الاصطناعي على الكلمات السعودية المحلية ويحوّلها إلى معاملات منظمة وفورية.",
    b12c1: "لهجة سعودية محلية", b12c2: "تحويل صوت لنص",
    pe: "PRIVACY & SECURITY",
    pt2: "بياناتك ملكك — خصوصية مطلقة",
    pb: "صُمم التطبيق لحماية خصوصيتك بالكامل. لا قراءة لرسائل SMS، لا ربط بالحسابات البنكية، لا مشاركة مع أي طرف ثالث.",
    p1h: "لا SMS — لا قراءة لرسائلك الشخصية", p1p: "التطبيق لا يطلب إذن قراءة الرسائل القصيرة إطلاقاً. إدخال يدوي أو صوتي أو مسح QR فقط.",
    p2h: "لا ربط بنكي — خصوصية مالية تامة", p2p: "لا اتصال بأنظمة البنوك ولا حاجة لبيانات الدخول المصرفية. أنت من يتحكم بما يتم تسجيله.",
    p3h: "تشفير متطور للبيانات", p3p: "بيانات Supabase مشفّرة بأحدث معايير الأمان المعتمدة مع عزل صارم بين الحسابات.",
    p4h: "هوية أفراد الأسرة محمية", p4p: "بيانات منزلك والأبناء مسجلة فقط في نطاق حسابك الخاص ولا يتم مشاركتها خارجياً.",
    p5h: "دورة راتب مرنة ومحلية", p5p: "تحديد يوم راتبك يُستخدم حصراً لحساب فترتك المالية داخل التطبيق لتنظيم ميزانيتك.",
    p6h: "مراجعة وتأكيد إلزامي قبل الحفظ", p6p: "كل إدخال — نصي أو صوتي أو مسح فاتورة — يمر ببطاقة مراجعة لتؤكده قبل الحفظ.",
    ft: "أسئلة شائعة",
    fq1: "هل يقرأ التطبيق رسائل SMS البنكية؟", fa1: "لا تماماً. التطبيق لا يطلب إذن قراءة الرسائل نهائياً. الإدخال يدوي أو صوتي أو عبر مسح QR الفاتورة فقط — خصوصيتك وأمان هاتفك خط أحمر.",
    fq2: "كيف يعمل مسح فاتورة ZATCA بالذكاء الاصطناعي؟", fa2: "تفتح كاميرا التطبيق وتمسح رمز QR لأي فاتورة إلكترونية سعودية متوافقة مع ZATCA. يستخرج التطبيق اسم المنشأة، الإجمالي، وضريبة القيمة المضافة 15% والتاريخ فورياً.",
    fq3: "كيف أُضيف أسماء أبنائي وشريكي لتوزيع المصاريف؟", fa3: "من إعدادات التطبيق تحت \"هوية المنزل\"، أضف أسماء الشريك والأبناء. عند تسجيل أي مصروف تختار بضغطة زر \"لصالح من\" لتقسيم النفقات بدقة وشفافية.",
    fq4: "هل يمكنني تعديل معاملة أو تصنيفها بعد حفظها؟", fa4: "نعم بكل تأكيد. يمكنك تعديل المبلغ، الفئة، الفئة الفرعية، أو الدافع والمستفيد لأي معاملة في أي وقت من سجل المعاملات.",
    fq5: "ما الفرق بين الفئة الرئيسية والفئة الفرعية؟", fa5: "الفئة الرئيسية مثل (مطاعم وتغذية)، والفئة الفرعية أدق مثل (وجبات سريعة — البيك، كنتاكي). يمكنك تخصيص فئاتك الفرعية لتناسب نمط إنفاق أسرتك بدقة.",
    fq6: "هل التطبيق متوفر للتحميل الآن؟", fa6: "التطبيق قيد المرحلة التجريبية المتقدمة وسيُطرح قريباً على Google Play وApp Store وAppGallery. يمكنك التواصل مع المطور للحصول على وصول تجريبي مبكر.",
    lt: "الشروط والخصوصية",
    ll1: "سياسة الخصوصية", ll2: "شروط الاستخدام",
    lp1h: "جمع البيانات والخصوصية", lp1p: "لا نقوم بجمع أو طلب بيانات بنكية أو صلاحيات SMS. تُخزّن كافة بيانات الميزانية مشفرة داخل قاعدة بيانات Supabase المؤمنة ولا يتم بيعها أو مشاركتها.",
    lp2h: "معالجة الذكاء الاصطناعي", lp2p: "تُعالج الرسائل النصية والصوتية بواسطة نماذج الذكاء الاصطناعي لاستخراج بيانات المصروف فقط ولا تُستخدم لتدريب نماذج عامة دون موافقة.",
    lp3h: "حذف الحساب والبيانات", lp3p: "يحق للمستخدم طلب الحذف الكامل لحسابه وسجلاته في أي وقت عبر إعدادات التطبيق أو عبر مراسلة الدعم الفني.",
    lt1h: "نطاق الاستخدام", lt1p: "المنصة مخصصة لإدارة وحوكمة ميزانيات الأسر والأفراد في المملكة العربية السعودية للاستخدام الشخصي غير التجاري.",
    lt2h: "المسؤولية المالية", lt2p: "التطبيق يقدم أدوات تنظيمية واقتراحات استرشادية مبنية على الذكاء الاصطناعي ولا يُعد بديلاً عن المشورة المالية الرسمية.",
    lt3h: "التحديثات والتطوير", lt3p: "تحتفظ إدارة منصة Budget بحق تحديث المزايا والشروط دورياً لتحسين جودة وأمان الخدمة مع إشعار المستخدمين.",
    cth: "هل لديك استفسار أو ترغب بنسخة تجريبية مبكرة؟",
    ctp: "فريق التطوير الهندسي مرحّب بملاحظاتك واستفساراتك للمساهمة في تقديم أفضل تجربة مالية للأسرة.",
    vipl: "البريد الإلكتروني للانضمام إلى قائمة الوصول المبكر VIP", vipph: "بريدك الإلكتروني",
    vipb: "انضم لقائمة VIP", vipsend: "جارٍ الإرسال...",
    vipok: "تم استلام طلبك! سنراسلك على بريدك عند فتح الوصول المبكر.",
    viperr: "تعذر إرسال طلبك حالياً. حاول لاحقاً أو راسلنا مباشرة على البريد أدناه.",
    viperr422: "يرجى إدخال بريد إلكتروني صحيح.",
    viperr429: "وصلنا عدد كبير من الطلبات منك. حاول مرة أخرى بعد قليل.",
    vipnet: "تعذر الاتصال بالخادم. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.",
    fs: "جميع الأنظمة تعمل بكفاءة",
    fl1: "المميزات", fl2: "الخصوصية", fl3: "الأسئلة",
    fm: "صُنع بـ ❤️ للأسر السعودية"
  },
  en: {
    brandSub: "Tracker • Family Finance",
    n1: "Simulator", n2: "Metrics", n3: "Features", n4: "Privacy", n5: "FAQ", n6: "Contact", nc: "Try Demo",
    ey: "ENTERPRISE HOUSEHOLD GOVERNANCE • SAUDI ARABIA",
    h1a: "Capital in the",
    h1b: "Algorithm.",
    hs: "An advanced household financial governance platform for Saudi families — flexible payday cycles, conversational AI ledger, ZATCA e-invoice scanning, and equitable partner-children allocation.",
    c1: "⚡ Launch Interactive Demo",
    c2: "→ Explore All 12 Capabilities",
    si: "Scroll down to explore",
    ss: "Coming soon on",
    ch1: "Soon", ch2: "Soon", ch3: "Soon",
    ste: "LIVE INTERACTIVE DEMO",
    stt: "Experience the Platform — Live in Browser",
    stb: "Four real-time interactive workflows demonstrating our core architecture. Zero setup required.",
    t1: "Payday Cycle", t2: "AI Assistant", t3: "ZATCA Invoices", t4: "Household Split",
    simT: "Set Your Monthly Payday (1 - 31)",
    simB: "✓ Auto Holiday Adjustment",
    sm1: "Day 1", smc: "Selected Payday:", sm2: "Day 31",
    ml1: "Days Remaining in Cycle", dy: "days", ms1: "Active balanced cycle",
    ml2: "Safe Daily Spending Rate", ms2: "Prevents early budget depletion",
    ml3: "Automated Savings Reserve", ms3: "Protected emergency buffer",
    cu: "\"Family dinner at AlBaik for 68 SAR, paid by me for the family\"",
    cai: "AI extracted transaction parameters with high precision",
    cm: "AlBaik Restaurant (Family Meal)",
    tc: "🍔 Dining & Food", ts: "🍟 Fast Food", tp2: "👤 Paid by: Me", tf: "👨‍👩‍👧 For: Family",
    zt: "Instant Tax Invoice Extraction",
    zs: "ZATCA Phase 2 E-Invoicing Compliant",
    zm: "Danube Hypermarket (Al-Nakheel)",
    zmv: "Merchant:", ztt: "Total Amount:", zvt: "VAT Amount (15%):", zdt: "Timestamp:",
    spt: "Simulated Expense Allocation Across Household",
    spy: "Partner 1 Share (You)", spp: "Partner 2 Share",
    kl1: "Smart Expense Categories",
    kl2: "AI OCR & NLP Data Extraction",
    kl3: "Flexible Payday Range (1-31)",
    kl4: "Privacy Guarantee — Zero Bank/SMS",
    be: "SYSTEM CAPABILITIES",
    bt: "Twelve Pillars of Household Financial Governance",
    bb: "A comprehensive operating system engineered for modern Saudi family economics.",
    b1t: "Conversational AI Assistant",
    b1d: "Log any expense in natural Arabic or English. The AI extracts amount, merchant, category, payer, and beneficiary with a live confirmation card before saving.",
    b1c1: "NLP Processing", b1c2: "Auto Categorization", b1c3: "Pre-Save Confirmation",
    b2t: "Flexible Payday Cycle",
    b2d: "Set your payday freely anywhere from Day 1 to Day 31. The engine calculates remaining runway and safe daily spend with automatic holiday shift handling.",
    b2sl: "Full flexibility across all calendar days",
    b3t: "ZATCA AI E-Invoice Scanner",
    b3d: "Scan any Saudi e-invoice QR code and extract total amount, 15% VAT, merchant name, and timestamp instantaneously with certified precision.",
    b3c2: "ZATCA Compliant", b3c3: "Instant Extraction",
    b4t: "Partner & Dependent Attribution",
    b4d: "Designate who paid and who benefited — spouse or registered children. Equitable distribution gives full transparency over household capital.",
    b4c1: "Paid By", b4c2: "For Dependents", b4c3: "Equitable Split",
    b5t: "Real-Time Financial Dashboard",
    b5d: "Visual telemetry for current expenditure, remaining runway, safe daily burn rate, and projected end-of-month surplus.",
    b5c1: "Daily Safe Spend", b5c2: "Budget Runway",
    b6t: "Hierarchical Custom Categories",
    b6d: "Define customized categories and granular subcategories for your home. AI suggests taxonomy and you can edit or re-categorize anytime after saving.",
    b6c1: "Custom Taxonomies", b6c2: "Granular Subcategories", b6c3: "AI Suggestion", b6c4: "Post-Save Edit",
    b7t: "Automated Savings Reserve",
    b7d: "Automatically computes surplus at each cycle cutoff and routes capital directly to emergency cushions or defined savings milestones.",
    b7c1: "Emergency Cushion", b7c2: "Milestone Reserves",
    b8t: "Zero-Compromise Privacy — No Bank / No SMS",
    b8d: "No SMS reading permissions requested and no bank scraping required. All data is end-to-end encrypted in your dedicated Supabase instance.",
    b8sl: "100% Encrypted & Sovereign Data",
    b9t: "Transaction Ledger & Audit Trail",
    b9d: "Full transactional history with chronological filtering, member breakdown, fast search, and the ability to edit or delete any entry.",
    b9c1: "Post-Edit Capable", b9c2: "Advanced Filters",
    b10t: "Household Profile & Members",
    b10d: "Register spouse and children under your household profile. Attribute expenses directly to individual family members with complete precision.",
    b10c1: "Spouse", b10c2: "Dependents", b10c3: "Household ID",
    b11t: "Monthly Analytics & Telemetry",
    b11d: "Comprehensive monthly variance reports by category and member, identifying expenditure leaks and historical spending trends.",
    b12t: "Saudi Dialect Voice Input",
    b12d: "Speak your expense in local Saudi Arabic dialect. On-device speech recognition converts natural audio into structured, validated data.",
    b12c1: "Local Dialect NLP", b12c2: "Speech to Structured Data",
    pe: "PRIVACY & SECURITY ARCHITECTURE",
    pt2: "Your Data Remains Yours — Absolute Privacy",
    pb: "Architected from first principles with zero intrusion. No SMS scraping, no banking credentials, no third-party data sharing.",
    p1h: "No SMS Scraping — Zero Message Access", p1p: "We never request or require SMS permissions. Inputs are entered manually, via voice, or through ZATCA QR scans only.",
    p2h: "No Bank Linking Required — Full Control", p2p: "Zero integration with banking APIs or open banking scrapers. You retain sovereign control over what is entered.",
    p3h: "End-to-End Encrypted Storage", p3p: "Supabase cloud storage utilizes enterprise AES-256 encryption with strict Row Level Security (RLS) isolation.",
    p4h: "Household Privacy Isolation", p4p: "Your family members and children data remain strictly scoped to your private authenticated tenant.",
    p5h: "Flexible & Sovereign Payday Cycle", p5p: "Your designated payday is private metadata used exclusively for calculating cycle mathematics inside your app.",
    p6h: "Mandatory Confirmation Card", p6p: "Every capture — voice, text, or receipt scan — presents an explicit review card before committing to the ledger.",
    ft: "Frequently Asked Questions",
    fq1: "Does the app read my private SMS or bank notifications?", fa1: "Never. The app does not request SMS permissions. Expenses are logged through conversational input, voice recording, or ZATCA QR scanning.",
    fq2: "How does the ZATCA QR scanner operate?", fa2: "Using on-device computer vision, the app decodes TLV-encoded Base64 QR tags from Saudi tax receipts, extracting VAT, merchant, date, and totals in milliseconds.",
    fq3: "How do I register spouse and dependents?", fa3: "Under Account Settings > Household Profile, you can add your partner and children. When capturing expenses, simply select the beneficiary member.",
    fq4: "Can transactions be modified after saving?", fa4: "Yes. Every transaction remains fully mutable. You can update amounts, change categories, or delete entries at any time.",
    fq5: "What is the difference between categories and subcategories?", fa5: "Categories are broad operational divisions (e.g., Dining & Groceries) while subcategories represent specific merchants or types (e.g., Fast Food, Bakeries).",
    fq6: "When will the application be available for public download?", fa6: "Budget Tracker is currently in private enterprise testing. It will soon be accessible on Google Play, the App Store, and Huawei AppGallery.",
    lt: "Legal & Governance Terms",
    ll1: "Privacy Policy", ll2: "Terms of Service",
    lp1h: "Data Collection & Governance", lp1p: "We do not scrape SMS messages or connect to bank portals. User data is stored encrypted within Supabase with strict isolation.",
    lp2h: "AI Processing Protocols", lp2p: "Conversational inputs are routed to specialized language models solely for entity extraction and are not retained for general model training.",
    lp3h: "Account & Data Erasure", lp3p: "Users may request instantaneous permanent deletion of their account and all associated ledgers directly from settings.",
    lt1h: "Permitted Use", lt1p: "Budget Tracker is licensed for personal and family budget governance within the Kingdom of Saudi Arabia.",
    lt2h: "Financial Disclaimer", lt2p: "The platform delivers operational budgeting telemetry and AI suggestions; it does not offer statutory financial advisory services.",
    lt3h: "Platform Modifications", lt3p: "The platform reserves the right to enhance system capabilities and policies periodically with prior notice to users.",
    cth: "Inquiries or Early Beta Access?",
    ctp: "The engineering team welcomes your inquiries, institutional feedback, and feature requests.",
    vipl: "Email address for the VIP early-access list", vipph: "Your email address",
    vipb: "Join the VIP list", vipsend: "Sending...",
    vipok: "Request received! We will email you when early access opens.",
    viperr: "We could not send your request right now. Please try again later or email us directly below.",
    viperr422: "Please enter a valid email address.",
    viperr429: "Too many requests from you. Please try again in a little while.",
    vipnet: "Could not reach the server. Check your connection and try again.",
    fs: "All Systems Operational",
    fl1: "Capabilities", fl2: "Privacy", fl3: "FAQ",
    fm: "Crafted with care for Saudi Families"
  }
};

let L = 'ar';

function setL(l) {
  L = l;
  const b = document.getElementById('pb');
  const h = document.documentElement;
  if (l === 'en') {
    b.classList.add('en');
    h.setAttribute('lang', 'en');
    h.setAttribute('dir', 'ltr');
    document.getElementById('btn-en').classList.add('on');
    document.getElementById('btn-ar').classList.remove('on');
    document.querySelectorAll('.cur-unit').forEach(el => el.textContent = 'SAR');
    document.getElementById('srunit').textContent = 'SAR/day';
    document.getElementById('sresunit').textContent = 'SAR';
  } else {
    b.classList.remove('en');
    h.setAttribute('lang', 'ar');
    h.setAttribute('dir', 'rtl');
    document.getElementById('btn-ar').classList.add('on');
    document.getElementById('btn-en').classList.remove('on');
    document.querySelectorAll('.cur-unit').forEach(el => el.textContent = 'ر.س');
    document.getElementById('srunit').textContent = 'ر.س/يوم';
    document.getElementById('sresunit').textContent = 'ر.س';
  }
  if (T[l]) {
    Object.entries(T[l]).forEach(([k, v]) => {
      document.querySelectorAll('[data-i18n="' + k + '"]').forEach(el => {
        el.innerHTML = v;
      });
    });
  }
  const vipEmail = document.getElementById('vip-email');
  if (vipEmail && T[l]) vipEmail.placeholder = T[l].vipph;
  vipShow('', '');
  // Re-run slider calculation to update labels
  updSim(document.getElementById('pslider').value);
}

// VIP early access: emailed to the developer by POST /public/inquiries (same origin).
// Success is shown only when the server answers 2xx; anything else shows an error.
function vipShow(kind, text) {
  const m = document.getElementById('vip-msg');
  if (!m) return;
  m.className = 'vipmsg' + (kind ? ' ' + kind : '');
  m.setAttribute('role', kind === 'err' ? 'alert' : 'status');
  m.textContent = text;
}

async function vipSubmit(e) {
  e.preventDefault();
  const input = document.getElementById('vip-email');
  const btn = document.getElementById('vip-btn');
  const hp = document.getElementById('vip-hp');
  const email = input.value.trim();
  if (btn.disabled) return;
  if (!email || !input.checkValidity()) {
    input.setAttribute('aria-invalid', 'true');
    vipShow('err', T[L].viperr422);
    input.focus();
    return;
  }
  btn.disabled = true;
  input.disabled = true;
  btn.textContent = T[L].vipsend;
  vipShow('', '');
  let err = null;
  try {
    const body = { type: 'vip_early_access', email: email, locale: L, source: 'landing' };
    if (hp && hp.value) body.company_website = hp.value;
    const res = await fetch('/public/inquiries', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(body),
      credentials: 'same-origin'
    });
    if (!res.ok) err = res.status === 422 ? T[L].viperr422 : res.status === 429 ? T[L].viperr429 : T[L].viperr;
  } catch (x) {
    err = T[L].vipnet;
  }
  btn.disabled = false;
  input.disabled = false;
  btn.textContent = T[L].vipb;
  if (err) {
    input.setAttribute('aria-invalid', 'true');
    vipShow('err', err);
    input.focus();
    return;
  }
  input.removeAttribute('aria-invalid');
  input.value = '';
  vipShow('ok', T[L].vipok);
}

window.addEventListener('scroll', () => {
  document.getElementById('hdr').classList.toggle('on', window.scrollY > 20);
});

function swTab(n) {
  ['sim', 'ai', 'zatca', 'split'].forEach(x => {
    const el = document.getElementById('p-' + x);
    if (el) el.classList.remove('on');
  });
  ['s1', 's2', 's3', 's4'].forEach(x => {
    const el = document.getElementById(x);
    if (el) el.classList.remove('on');
  });
  const target = document.getElementById('p-' + n);
  if (target) target.classList.add('on');
  const m = { sim: 's1', ai: 's2', zatca: 's3', split: 's4' };
  const btn = document.getElementById(m[n]);
  if (btn) btn.classList.add('on');
}

function updSim(v) {
  document.getElementById('sv').textContent = v;
  const t = new Date().getDate();
  let d = parseInt(v) - t;
  if (d <= 0) d += 30;
  const r = Math.round(12000 / Math.max(d, 1));
  const res = Math.max(0, 12000 - r * d);
  document.getElementById('sd').innerHTML = d + ' <small style="font-size:13px">' + (L === 'ar' ? 'يوم' : 'days') + '</small>';
  document.getElementById('sr').innerHTML = r.toLocaleString() + ' <small style="font-size:13px">' + (L === 'ar' ? 'ر.س/يوم' : 'SAR/day') + '</small>';
  document.getElementById('sres').innerHTML = res.toLocaleString() + ' <small style="font-size:13px">' + (L === 'ar' ? 'ر.س' : 'SAR') + '</small>';
}

document.getElementById('pslider').addEventListener('input', function() {
  updSim(this.value);
});

const KT = { k1: 50, k2: 97, k3: 31, k4: 100 };
function aniK(id, tg, dur) {
  const el = document.getElementById(id);
  if (!el) return;
  let s = 0;
  const st = tg / (dur / 16);
  (function u() {
    s = Math.min(s + st, tg);
    el.textContent = Math.round(s);
    if (s < tg) requestAnimationFrame(u);
  })();
}

new IntersectionObserver((en) => {
  en.forEach(e => {
    if (e.isIntersecting && !e.target.dataset.observed) {
      Object.entries(KT).forEach(([id, v]) => aniK(id, v, 1800));
      e.target.dataset.observed = '1';
    }
  });
}, { threshold: 0.3 }).observe(document.querySelector('.kpis'));

function tgFaq(el) {
  const op = el.classList.contains('op');
  document.querySelectorAll('.faqit').forEach(i => i.classList.remove('op'));
  if (!op) el.classList.add('op');
}

function swLeg(tab, btn) {
  document.getElementById('lp').style.display = tab === 'p' ? 'block' : 'none';
  document.getElementById('lt2').style.display = tab === 't' ? 'block' : 'none';
  document.querySelectorAll('.ltab').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
}

let pct = 60;
setInterval(() => {
  pct = pct === 60 ? 45 : (pct === 45 ? 70 : 60);
  const y = document.getElementById('spty'), p = document.getElementById('sptp'), py = document.getElementById('pcy'), pp = document.getElementById('pcp');
  if (y) y.style.width = pct + '%';
  if (p) p.style.width = (100 - pct) + '%';
  if (py) py.textContent = pct + '%';
  if (pp) pp.textContent = (100 - pct) + '%';
}, 2800);

window.addEventListener('load', () => {
  updSim(25);
  document.getElementById('hdr').classList.add('on');
});
</script>
</body>
</html>'''

AUTH_CONFIRM_HTML_CONTENT = r'''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>تأكيد البريد الإلكتروني | Budget Tracker</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;900&display=swap" rel="stylesheet">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#080709;color:#F0EDE8;font-family:'Cairo',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}
    .card{background:#121117;border:1px solid rgba(255,255,255,0.08);border-radius:24px;padding:56px 48px;max-width:480px;width:100%;text-align:center;box-shadow:0 40px 80px rgba(0,0,0,0.7),inset 0 1px 0 rgba(255,255,255,0.09)}
    .ring{width:72px;height:72px;border-radius:50%;background:rgba(52,211,153,0.12);border:2px solid #34D399;display:flex;align-items:center;justify-content:center;font-size:32px;margin:0 auto 28px;box-shadow:0 0 30px rgba(52,211,153,0.3)}
    h1{font-size:24px;font-weight:900;margin-bottom:12px;color:#fff}
    p{font-size:15px;color:#9E9790;line-height:1.75;margin-bottom:32px}
    .btn{display:inline-flex;align-items:center;gap:8px;background:#C2783C;color:#fff;font-family:'Cairo',sans-serif;font-size:15px;font-weight:700;padding:14px 32px;border-radius:12px;text-decoration:none;transition:all .3s;box-shadow:0 0 24px rgba(194,120,60,0.45)}
    .btn:hover{background:#F0A05A;transform:translateY(-1px)}
    .sub{margin-top:24px;font-size:13px;color:#5C5650}
    .sub a{color:#C2783C;text-decoration:none}
  </style>
</head>
<body>
  <div class="card">
    <div class="ring">✓</div>
    <h1>تم تأكيد البريد الإلكتروني بنجاح</h1>
    <p>رائع! حسابك مفعّل وجاهز للاستخدام. انقر على الزر أدناه للعودة إلى التطبيق وبدء إدارة ميزانيتك الذكية.</p>
    <a href="budgettracker://login" class="btn">&#x1F680; فتح التطبيق</a>
    <div class="sub">مشكلة؟ تواصل معنا على <a href="mailto:abedmowafaq@gmail.com">abedmowafaq@gmail.com</a></div>
  </div>
</body>
</html>'''

AUTH_CALLBACK_HTML_CONTENT = r'''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>تسجيل الدخول | Budget Tracker</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;900&display=swap" rel="stylesheet">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#080709;color:#F0EDE8;font-family:'Cairo',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}
    .card{background:#121117;border:1px solid rgba(255,255,255,0.08);border-radius:24px;padding:56px 48px;max-width:480px;width:100%;text-align:center;box-shadow:0 40px 80px rgba(0,0,0,0.7),inset 0 1px 0 rgba(255,255,255,0.09)}
    .spinner{width:52px;height:52px;border:3px solid rgba(255,255,255,0.08);border-top-color:#C2783C;border-radius:50%;animation:spin .9s linear infinite;margin:0 auto 28px}
    @keyframes spin{to{transform:rotate(360deg)}}
    h1{font-size:22px;font-weight:800;margin-bottom:10px;color:#fff}
    p{font-size:15px;color:#9E9790}
  </style>
  <script>setTimeout(()=>{window.location.href='budgettracker://login';},1500);</script>
</head>
<body>
  <div class="card">
    <div class="spinner"></div>
    <h1>جاري تسجيل الدخول...</h1>
    <p>يتم إعادة توجيهك للتطبيق تلقائياً.</p>
  </div>
</body>
</html>'''

if __name__ == '__main__':
    # Write landing_page.py
    (HERE / 'landing_page.py').write_text(LANDING_PAGE_PY, encoding='utf-8')
    print("Wrote landing_page.py")

    # Write _landing_impl.py
    impl_content = (
        '# -*- coding: utf-8 -*-\n'
        '"""Complete HTML payloads for FMSCO Enterprise Landing & Auth."""\n\n'
        'LANDING_HTML = ' + repr(LANDING_HTML_CONTENT) + '\n\n'
        'AUTH_CONFIRM_HTML = ' + repr(AUTH_CONFIRM_HTML_CONTENT) + '\n\n'
        'AUTH_CALLBACK_HTML = ' + repr(AUTH_CALLBACK_HTML_CONTENT) + '\n'
    )
    (HERE / '_landing_impl.py').write_text(impl_content, encoding='utf-8')
    print("Wrote _landing_impl.py")
