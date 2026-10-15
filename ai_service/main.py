"""
FastAPI entry point for the Budget Tracker AI microservice.

Architecture:
- Modular routers under `routes/`
- JWT & HMAC authentication middleware
- Request body size limiter (DoS protection)
- Constant-time firewall token middleware
"""

from __future__ import annotations

import hmac
import logging
import os
import time

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, FileResponse

load_dotenv()  # Load .env before any other imports that read env vars

from utils import verify_signature as _verify_signature
from landing_page import get_landing_page_html, get_auth_confirmed_html
from routes.budgets import router as budgets_router
from routes.households import router as households_router
from routes.analytics import router as analytics_router
from routes.receipts import router as receipts_router
from routes.chat import router as chat_router
from routes.reports import router as reports_router
from routes.support import router as support_router

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Budget Tracker AI Service",
    description="Modular AI service and budget manager for Saudi personal finance.",
    version="1.0.2",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ─── CORS ─────────────────────────────────────────────────────────────────────
DEFAULT_ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "http://localhost:8080",
    "http://localhost:5173",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8080",
    "http://127.0.0.1:5173",
    "https://budget.fmsco.com.sa",
]
env_origins = os.environ.get("ALLOWED_ORIGINS")
if env_origins:
    allow_origins = [o.strip() for o in env_origins.split(",") if o.strip()]
else:
    allow_origins = DEFAULT_ALLOWED_ORIGINS

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# ─── Request Body Size Limit (OWASP A04: DoS Protection) ──────────────────────
MAX_REQUEST_BODY_BYTES = int(os.environ.get("MAX_REQUEST_BODY_BYTES", str(10 * 1024 * 1024)))  # 10MB default


@app.middleware("http")
async def request_size_limit_middleware(request: Request, call_next):
    """Reject request bodies exceeding MAX_REQUEST_BODY_BYTES to prevent DoS."""
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_REQUEST_BODY_BYTES:
        from starlette.responses import JSONResponse
        return JSONResponse(
            status_code=413,
            content={"detail": f"Request body too large. Maximum allowed: {MAX_REQUEST_BODY_BYTES // (1024 * 1024)}MB."},
        )
    return await call_next(request)


# ─── Auth Token & Firewall (OWASP A01 / A02) ───────────────────────────────────
APP_AUTH_TOKEN = os.environ.get("APP_AUTH_TOKEN", "").strip()
IS_PRODUCTION = os.environ.get("ENV", "development").lower() == "production"

if not APP_AUTH_TOKEN:
    logger.warning(
        "APP_AUTH_TOKEN is not configured. "
        "Firewall middleware will reject all proxied/tunnel requests. "
        "Set APP_AUTH_TOKEN in environment variables."
    )


@app.middleware("http")
async def firewall_token_middleware(request: Request, call_next):
    # Allow local inspection, health check and docs
    path = request.url.path
    if path in ["/", "/auth/confirm", "/auth/callback", "/health", "/docs", "/openapi.json", "/redoc", "/hero-bg.webp", "/hero-bg.jpg"] or path.startswith("/auth/") or path.startswith("/static/") or request.method == "OPTIONS":
        return await call_next(request)

    # Check if request arrived via reverse proxy or public tunnel
    forwarded_for = request.headers.get("X-Forwarded-For")
    client_host = request.client.host if request.client else ""
    is_tunnel_or_proxy = bool(forwarded_for) or (client_host not in ["127.0.0.1", "localhost", "::1", "testclient"])

    # Constant-time comparison to prevent side-channel timing attacks (OWASP A02)
    provided_token = request.headers.get("X-App-Token", "")
    token_valid = bool(APP_AUTH_TOKEN and hmac.compare_digest(provided_token, APP_AUTH_TOKEN))
    if is_tunnel_or_proxy and not token_valid:
        logger.warning("Firewall blocked unauthorized public probe from IP=%s (forwarded=%s) to path=%s", client_host, forwarded_for, path)
        from starlette.responses import JSONResponse
        return JSONResponse(
            status_code=403,
            content={"detail": "Forbidden: Untrusted endpoint access."}
        )

    return await call_next(request)


# ─── HMAC Signature Config ───────────────────────────────────────────────────
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "").strip()
if not WEBHOOK_SECRET:
    logger.warning(
        "WEBHOOK_SECRET is not configured. "
        "HMAC signature verification will reject all signed requests. "
        "Set WEBHOOK_SECRET in environment variables."
    )


# ─── Public Landing & Health Routes ──────────────────────────────────────────
@app.get("/", response_class=HTMLResponse, tags=["ops"])
async def root_landing_page():
    """Main public product showcase, feature explanations, and coming soon badges."""
    return HTMLResponse(content=get_landing_page_html())


@app.get("/auth/confirm", response_class=HTMLResponse, tags=["ops"])
@app.get("/auth/callback", response_class=HTMLResponse, tags=["ops"])
async def auth_confirm_landing():
    """Welcome and email confirmation landing page."""
    return HTMLResponse(content=get_auth_confirmed_html())


STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")


@app.get("/hero-bg.webp", tags=["ops"])
async def hero_background_webp():
    """Serve WebP cinematic background image for the landing page."""
    webp_path = os.path.join(STATIC_DIR, "hero_bg.webp")
    if os.path.exists(webp_path):
        return FileResponse(webp_path, media_type="image/webp", headers={"Cache-Control": "public, max-age=604800"})
    raise HTTPException(status_code=404, detail="Background image not found")


@app.get("/hero-bg.jpg", tags=["ops"])
async def hero_background_jpg():
    """Serve JPEG fallback cinematic background image for the landing page."""
    jpg_path = os.path.join(STATIC_DIR, "hero_bg.jpg")
    if os.path.exists(jpg_path):
        return FileResponse(jpg_path, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=604800"})
    raise HTTPException(status_code=404, detail="Background image not found")


@app.get("/health", tags=["ops"])
async def health_check():
    """Liveness probe — returns 200 OK with uptime."""
    return {"status": "ok", "version": "1.0.2", "timestamp": time.time()}


# ─── Include Routers ─────────────────────────────────────────────────────────
app.include_router(budgets_router)
app.include_router(households_router)
app.include_router(analytics_router)
app.include_router(receipts_router)
app.include_router(chat_router)
app.include_router(reports_router)
app.include_router(support_router)


# ─── Entry Point ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000)),
        reload=os.environ.get("RELOAD", "false").lower() == "true",
        log_level="info",
    )
