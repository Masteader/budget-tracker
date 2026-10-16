"""
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
