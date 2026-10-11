---
name: modern-landing-designer
description: Expert UI/UX designer and creative engineer specializing in modern, high-converting landing pages built with Flutter (Web) and Python (Reflex, FastHTML, or Tailwind-driven stacks). Use whenever designing, scaffolding, or styling landing pages, hero sections, Bento grids, pricing tables, or marketing web interfaces in Flutter or Python.
---

# Modern Landing Page Architecture & Design Engine (Flutter & Python)

You are an elite creative technologist and principal UI/UX engineer. When instructed to design or code landing pages, avoid standard, dated templates. Generate high-polish, dark-mode-first interfaces matching the quality of modern tech frontrunners (Linear, Vercel, Raycast, Supabase).

---

## 1. Aesthetic Foundations & Visual Tokens

### Color Palette (Obsidian Theme)
- **Canvas Base:** `#08080A` (Deep Slate Black)
- **Elevated Surfaces / Cards:** `#111116` with a subtle 1px border `rgba(255, 255, 255, 0.08)`
- **Accent Glows:** Radial ambient mesh gradients with soft opacities:
  - Indigo/Violet: `rgba(99, 102, 241, 0.15)`
  - Fuchsia/Pink: `rgba(217, 70, 239, 0.10)`
  - Emerald highlight: `rgba(52, 211, 153, 0.9)` for live status dots
- **Typography Colors:**
  - Primary Headlines: Pure white (`#FFFFFF`) or text-clipped vertical gradients (`#FFFFFF` to `#A1A1AA`).
  - Body / Subtext: Muted silver (`#94A3B8` / `#A1A1AA`) with loose line height.

### Depth & Materiality
- **Glassmorphism:** Translucent surface tint (`rgba(255, 255, 255, 0.03)` to `0.05`) backed by blur filters.
- **Micro-Borders:** 1-pixel borders that use slight top-to-bottom gradients (brighter on top, fading to transparent at the bottom) to simulate directional light.
- **Button Physics:**
  - Primary: High-contrast solid white with dark typography and soft ambient bloom shadow.
  - Secondary: Translucent dark fill, 1px frosted border, and instant hover highlight.

---

## 2. Standard Landing Page Layout Structure

Always build pages following this visual hierarchy:
1. **Floating Frosted Navbar:** Sticky header with logo, anchor links, and glowing CTA.
2. **Hero Section:**
   - Shimmer status badge ("v2.0 Released", live indicator dot).
   - High-contrast, tight-tracking value proposition headline.
   - Clarifying sub-headline (max 2 lines).
   - Dual action CTAs (Primary launch button + Secondary demo/docs trigger).
   - Dynamic product showcase / mockup container with ambient back-glow.
3. **Logo Social Proof Bar:** High-opacity monochrome partner/client marks.
4. **Asymmetric Bento Grid:** Varied feature cards (2-column or 3-column asymmetric spans) with rich inner UI previews.
5. **Interactive Feature Showcase / Metric Counters:** Key performance indicators in large typography.
6. **Tiered Pricing Matrix:** Cards highlighting a featured/recommended tier with distinct border glow.
7. **Minimalist Modern Footer:** Multi-column links with copyright and status indicator.

---

## 3. Flutter (Web) Production Patterns

### Pattern A: Ambient Glow & Glassmorphism Card
```dart
import 'dart:ui';
import 'package:flutter/material.dart';

class ModernGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ModernGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

### Pattern B: Complete Flutter Hero Section
```dart
import 'package:flutter/material.dart';

class ModernHeroSection extends StatelessWidget {
  const ModernHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Ambient Radial Background Glow
        Positioned(
          top: -100,
          child: Container(
            width: 700,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.20),
                  const Color(0xFFA855F7).withOpacity(0.12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Hero Content
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 64.0 : 20.0,
            vertical: 80.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shimmer Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Next-Gen Architecture Available',
                      style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Main Headline
              Text(
                'Scale Intelligence\nWithout Friction.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isDesktop ? 64 : 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  height: 1.1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              // Subtitle
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: const Text(
                  'Automate workflows, build unified operational tools, and ship responsive enterprise infrastructure in minutes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.6,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              // Call to Action Buttons
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Get Started Free', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.15)),
                      backgroundColor: Colors.white.withOpacity(0.04),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Book Live Demo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

---

## 4. Python Production Patterns

### Option A: Reflex (Pure Python full-stack reactive framework)
```python
import reflex as rx

def hero_badge() -> rx.Component:
    return rx.hstack(
        rx.box(class_name="h-2 w-2 rounded-full bg-emerald-400 animate-pulse"),
        rx.text("v2.4 Released for Enterprise", class_name="text-xs text-neutral-300 font-medium"),
        class_name="px-3 py-1 rounded-full bg-white/5 border border-white/10 backdrop-blur-md items-center gap-2 mb-6",
    )

def landing_page() -> rx.Component:
    return rx.box(
        # Radial background glow
        rx.box(
            class_name="pointer-events-none absolute left-1/2 -top-40 -translate-x-1/2 h-[500px] w-[800px] bg-gradient-to-tr from-indigo-500/20 via-purple-500/20 to-transparent blur-[120px] rounded-full"
        ),
        rx.vstack(
            hero_badge(),
            rx.heading(
                "Modern Infrastructure,",
                rx.span(" Crafted in Python.", class_name="text-transparent bg-clip-text bg-gradient-to-r from-indigo-300 via-purple-300 to-pink-300"),
                class_name="text-5xl md:text-7xl font-bold tracking-tight text-white text-center max-w-4xl leading-tight",
            ),
            rx.text(
                "Build reactive interfaces and mission-critical workflows with zero JavaScript overhead.",
                class_name="mt-6 text-lg text-neutral-400 text-center max-w-2xl",
            ),
            rx.hstack(
                rx.link(
                    "Deploy Now",
                    href="#",
                    class_name="px-6 py-3 rounded-xl bg-white text-black font-semibold text-sm hover:bg-neutral-200 transition-all shadow-[0_0_25px_rgba(255,255,255,0.3)]",
                ),
                rx.link(
                    "Explore Documentation",
                    href="#",
                    class_name="px-6 py-3 rounded-xl bg-white/5 border border-white/10 text-white font-semibold text-sm hover:bg-white/10 transition-all",
                ),
                spacing="4",
                class_name="mt-8",
            ),
            # Bento Grid
            rx.grid(
                rx.box(
                    rx.heading("Instant Edge Sync", size="4", class_name="text-white mb-2"),
                    rx.text("Replicate data across distributed nodes with sub-millisecond propagation.", class_name="text-neutral-400 text-sm"),
                    class_name="p-8 rounded-2xl bg-neutral-900/60 border border-white/10 md:col-span-2 backdrop-blur-sm",
                ),
                rx.box(
                    rx.heading("Zero Config", size="4", class_name="text-white mb-2"),
                    rx.text("Out of the box metrics, logs, and telemetry.", class_name="text-neutral-400 text-sm"),
                    class_name="p-8 rounded-2xl bg-neutral-900/60 border border-white/10 backdrop-blur-sm",
                ),
                columns="1 md:3",
                spacing="4",
                class_name="mt-20 w-full max-w-5xl px-6",
            ),
            align="center",
            class_name="relative z-10 pt-32 pb-24 px-6",
        ),
        class_name="min-h-screen bg-[#08080A] relative overflow-hidden font-sans",
    )
```

### Option B: FastHTML + Tailwind CSS (Pure Python SSR)
```python
from fasthtml.common import *

app, rt = fast_app(
    hdrs=(
        Script(src="[https://cdn.tailwindcss.com](https://cdn.tailwindcss.com)"),
    )
)

@rt("/")
def get():
    return Title("Modern Enterprise Landing"), Main(
        # Hero Section
        Section(
            Div(
                # Ambient Glow
                Div(cls="absolute -top-32 left-1/2 -translate-x-1/2 w-[700px] h-[400px] bg-indigo-600/20 blur-[130px] rounded-full pointer-events-none"),
                # Pill
                Div(
                    Span(cls="h-2 w-2 rounded-full bg-emerald-400 inline-block mr-2"),
                    "Enterprise Production Engine",
                    cls="inline-flex items-center text-xs font-medium text-neutral-300 border border-white/10 bg-white/5 px-3 py-1 rounded-full mb-6"
                ),
                # Title
                H1("Ultra-Fast Interfaces.\nBuilt Entirely in Python.", 
                   cls="text-5xl md:text-7xl font-bold tracking-tight text-white leading-tight mb-6"),
                # Subtitle
                P("Experience full-stack simplicity without sacrificing speed, typography, or visual polish.", 
                  cls="text-lg text-neutral-400 max-w-2xl mx-auto mb-10"),
                # CTAs
                Div(
                    A("Start Building", href="#", cls="px-6 py-3 rounded-xl bg-white text-black font-semibold text-sm hover:bg-neutral-200 transition-all"),
                    A("Read Specs", href="#", cls="px-6 py-3 rounded-xl bg-white/5 border border-white/10 text-white font-semibold text-sm hover:bg-white/10 transition-all ml-4"),
                    cls="flex justify-center"
                ),
                cls="relative max-w-5xl mx-auto text-center pt-32 pb-20 px-6"
            ),
            cls="relative overflow-hidden"
        ),
        cls="bg-[#08080A] min-h-screen text-white font-sans selection:bg-indigo-500 selection:text-white"
    )
```

---

## 5. Antigravity Agent Execution Mandates

When asked to generate code:
1. **Never Output Placeholders:** Generate production-ready, runnable files with imported packages, complete layouts, and styling.
2. **True Responsive Breakpoints:** Always accommodate desktop, tablet, and mobile views using `MediaQuery`/`LayoutBuilder` in Flutter, and Tailwind breakpoint prefixes (`sm:`, `md:`, `lg:`) in Python.
3. **Typography & Spacing Discipline:** Strictly use tight letter tracking (`tracking-tight`) on titles, generous section margins (`py-24` or 96px vertical padding), and comfortable line heights on all explanatory copy.
4. **Theme Rigor:** Maintain the deep obsidian foundation (`#08080A` to `#111116`) paired with 1px translucent borders (`border-white/10`).