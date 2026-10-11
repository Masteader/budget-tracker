# Landing Page Redesign (budget.fmsco.com.sa) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the `budget.fmsco.com.sa` landing page in `ai_service/landing_page.py` into a world-class, Nate Herik-inspired fintech craft experience with obsidian glassmorphism, interactive live widget simulators, flexible salary cycle budgeting (no fixed 27th payday), and comprehensive coverage of all app features.

**Architecture:** 
1. Single self-contained HTML/CSS/JS generator in `ai_service/landing_page.py` (`get_landing_page_html()`) with zero external runtime server dependencies, ensuring ultra-fast load times and seamless FastAPI serving.
2. High-craft UI design system: obsidian palette (`#07090E`, `#0D1117`), mesh grid pattern, luminous radial glow orbs, glassmorphic cards with subtle specular top borders (`inset 0 1px 0 rgba(255,255,255,0.1)`), and micro-animations.
3. Interactive Live App Stage with 4 dynamic interactive tabs (Flexible Payday Simulator, Conversational AI Assistant & Subcategories, ZATCA Phase 2 QR Laser Scanner, and 2D Partner Split & Children Settlement).
4. 12-pillar Bento Grid highlighting all app capabilities.
5. Instant bilingual Arabic (RTL default) / English (LTR) language switcher updating all copy, numbers, and interactive elements.
6. Support contact `abedmowafaq@gmail.com`, "Coming Soon" store badges for Google Play, App Store, and Huawei AppGallery.

**Tech Stack:** Vanilla HTML5, CSS3 (Custom Properties, Glassmorphism, CSS Grid, Flexbox), Vanilla JavaScript (No heavyweight frameworks needed), Google Fonts (Cairo & Outfit), FastAPI backend.

**Spec:** Direct user requirements:
- Remove fixed 27th payday references (flexible/custom salary date for all users).
- Showcase all application features.
- Nate Herik / modern YouTube craft UI design standard (tactile, polished, glowing, interactive).
- Full bilingual Arabic & English support.
- Store badges with Coming Soon tags.
- Support email `abedmowafaq@gmail.com`.

## Global Constraints
- Do NOT mention "27" as a fixed payday anywhere. Mention customizable payday (Day 1, 15, 25, 27, or any day).
- Maintain existing email verification landing page function `get_auth_confirmed_html()`.
- Keep developer email `abedmowafaq@gmail.com`.
- Maintain store badges: Google Play, Apple App Store, Huawei AppGallery ("Coming Soon").
- All pytest tests in `ai_service/tests/` must pass cleanly.

---

### Task 1: Update Test Suite for Flexible Payday & App Features

**Files:**
- Modify: `ai_service/tests/test_landing_page.py`

- [ ] **Step 1: Update assertions in `ai_service/tests/test_landing_page.py`**
  Remove `assert "27" in html`. Replace with assertions for flexible payday (`دورة الراتب`), AI features (`الذكاء الاصطناعي`), savings (`الادخار`), store badges, and developer email.
- [ ] **Step 2: Run pytest to verify test state**
  Run: `pytest tests/test_landing_page.py -v`

---

### Task 2: Implement Nate Herik-Inspired Landing Page in `ai_service/landing_page.py`

**Files:**
- Modify: `ai_service/landing_page.py`

- [ ] **Step 1: Craft the Design System & Atmospheric Obsidian Canvas**
  - Modern typography: `Cairo` for Arabic, `Outfit` for English.
  - Dark fintech theme with subtle dot-matrix/grid background and luminous radial gradient spotlights.
  - Specular card styling with top-edge inset highlights and subtle hover elevation.
- [ ] **Step 2: Build Hero Section with Flexible Salary Cycle Value Proposition**
  - Highlight customizable payday (works for any day of the month: government, private sector, freelance).
  - Prominent "Coming Soon" badges for Google Play, App Store, and AppGallery with clean SVG/Unicode icons.
- [ ] **Step 3: Build Live Interactive App Playground (The Showcase)**
  - Tab 1: **Flexible Payday Simulator** (Slider 1–31, live recalculation of days remaining, daily safe-to-spend allowance, weekend shift indicator).
  - Tab 2: **AI Assistant & Hybrid Subcategories** (Simulated Saudi chat receipt logging -> automatic classification into Main Category & Subcategory + Paid by / For whom tags).
  - Tab 3: **ZATCA Phase 2 Scanner** (Simulated camera frame with animated laser scan beam, QR TLV verification, VAT calculation).
  - Tab 4: **2D Partner Settlement & Children Allocation** (Interactive split ratio slider 50:50 / 60:40 / 70:30, child tags, live debt calculation).
- [ ] **Step 4: Build 12-Pillar Bento Grid of App Capabilities**
  1. Flexible Payday Cycle & Safe Burn-Rate
  2. Saudi Dialect Conversational AI Assistant
  3. Two-Tier Taxonomy & Hybrid LLM Subcategories
  4. ZATCA Phase 2 E-Invoice QR & Camera Scanner
  5. Household & Partner Sharing with 2D Fair-Share Split
  6. Family Dependents & Children Expense Tracking
  7. BNPL & Installment Tracker (Tabby, Tamara, 0% Cards)
  8. Recurring Bills & Auto-Cadence Detection
  9. Smart Grocery Price Comparison & Basket Optimizer
  10. "Can I Afford This?" Instant Purchase Simulator
  11. Offline-First SQLite Engine with Background Sync
  12. Smart Savings Reserve & Monthly PDF Statements
- [ ] **Step 5: Privacy Policy, Terms of Service, FAQ & Developer Contact**
  - Clear tabs for Privacy & Terms with bank-grade security guarantees.
  - Interactive FAQ accordion for top user questions.
  - Contact card for `abedmowafaq@gmail.com`.
- [ ] **Step 6: Complete Dual-Language State Engine (Arabic RTL / English LTR)**
  - Comprehensive translations dictionary for all headings, descriptions, tabs, interactive slider outputs, and badges.

---

### Task 3: Verification & Test Execution

**Files:**
- Test: `ai_service/tests/test_landing_page.py`
- Test: `ai_service/tests/` (all tests)

- [ ] **Step 1: Run pytest on `test_landing_page.py`**
- [ ] **Step 2: Run all backend tests**
- [ ] **Step 3: Verify no fixed "27th" payday text remains in the HTML**
