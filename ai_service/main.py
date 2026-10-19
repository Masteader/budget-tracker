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
from fastapi.staticfiles import StaticFiles

load_dotenv()  # Load .env before any other imports that read env vars

from utils import verify_signature as _verify_signature, is_production
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

# ─── Validation errors ───────────────────────────────────────────────────────
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


@app.exception_handler(RequestValidationError)
async def sanitized_validation_handler(request: Request, exc: RequestValidationError):
    """
    Return 422 with location/type/message only. The default handler echoes the offending
    input back (leaking payload contents) and crashes with a 500 when that input is NaN or
    Infinity, which cannot be JSON-encoded.
    """
    errors = [
        {"loc": list(err.get("loc", ())), "type": err.get("type"), "msg": err.get("msg")}
        for err in exc.errors()
    ]
    return JSONResponse(status_code=422, content={"detail": errors})


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
@app.middleware("http")
async def request_size_limit_middleware(request: Request, call_next):
    """
    Reject request bodies exceeding limit (Cost Control & DoS prevention).
    Checks Content-Length header and counts actual streamed bytes for chunked requests.
    """
    path = request.url.path
    max_size = 25 * 1024 * 1024 if path.startswith("/agent/scan-receipt") else 1 * 1024 * 1024

    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > max_size:
                from starlette.responses import JSONResponse
                return JSONResponse(
                    status_code=413,
                    content={"detail": "Payload too large. Maximum allowed request size exceeded."},
                )
        except ValueError:
            pass

    # Stream body byte counting for chunked / unheadered transfers
    orig_receive = request._receive
    bytes_received = 0

    async def limited_receive():
        nonlocal bytes_received
        msg = await orig_receive()
        if msg["type"] == "http.request":
            body = msg.get("body", b"")
            bytes_received += len(body)
            if bytes_received > max_size:
                from fastapi import HTTPException
                raise HTTPException(
                    status_code=413,
                    detail="Payload too large. Maximum allowed request size exceeded."
                )
        return msg

    request._receive = limited_receive
    try:
        return await call_next(request)
    except HTTPException as exc:
        if exc.status_code == 413:
            from starlette.responses import JSONResponse
            return JSONResponse(status_code=413, content={"detail": exc.detail})
        raise


# ─── Auth Token & Firewall (OWASP A01 / A02) ───────────────────────────────────
APP_AUTH_TOKEN = os.environ.get("APP_AUTH_TOKEN", "").strip()
IS_PRODUCTION = os.environ.get("ENV", "development").lower() == "production"

if not APP_AUTH_TOKEN:
    logger.warning(
        "APP_AUTH_TOKEN is not configured. "
        "Firewall middleware will reject all proxied/tunnel requests. "
        "Set APP_AUTH_TOKEN in environment variables."
    )


_API_DOC_PATHS = {"/docs", "/docs/oauth2-redirect", "/openapi.json", "/redoc"}


@app.middleware("http")
async def firewall_token_middleware(request: Request, call_next):
    path = request.url.path

    # Interactive API docs / schema are a development aid only: in production they would hand
    # an attacker the full route map, so they are hidden unless ENV is explicitly non-production.
    if path in _API_DOC_PATHS and is_production():
        from starlette.responses import JSONResponse
        return JSONResponse(status_code=404, content={"detail": "Not Found"})

    if (
        path in [
            "/",
            "/auth/confirm",
            "/auth/callback",
            "/health",
            "/docs",
            "/openapi.json",
            "/redoc",
            "/hero-bg.webp",
            "/hero-bg.jpg",
            "/hero_glacier.png",
            "/hero_glacier.jpg",
            "/favicon.svg",
        ]
        or path.startswith("/assets/")
        or path.startswith("/auth/")
        or path.startswith("/static/")
        or request.method == "OPTIONS"
    ):
        return await call_next(request)

    # Check if request arrived via reverse proxy or public tunnel
    forwarded_for = request.headers.get("X-Forwarded-For")
    client_host = request.client.host if request.client else ""
    is_tunnel_or_proxy = bool(forwarded_for) or (client_host not in ["127.0.0.1", "localhost", "::1", "testclient"])

    # Constant-time comparison to prevent side-channel timing attacks (OWASP A02)
    provided_token = request.headers.get("X-App-Token", "")
    token_valid = bool(APP_AUTH_TOKEN and hmac.compare_digest(provided_token, APP_AUTH_TOKEN))

    # Strict token validation for Bearer headers (reject fake/unverified tokens)
    bearer_valid = False
    auth_header = request.headers.get("Authorization", "").strip()
    if auth_header.startswith("Bearer "):
        token_str = auth_header[7:].strip()
        try:
            from auth import _decode_token
            decoded = _decode_token(token_str)
            if decoded and decoded.get("sub"):
                bearer_valid = True
        except Exception:
            bearer_valid = False

    if is_tunnel_or_proxy and not (token_valid or bearer_valid):
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


def _log_security_configuration() -> None:
    """Surface dangerous configuration at startup (never logs secret values)."""
    from supabase_client import describe_supabase_key

    key_info = describe_supabase_key()
    for env_var, role in key_info["rejected"]:
        logger.critical(
            "%s holds a non-privileged Supabase key (role '%s') and is ignored. "
            "The service needs a service_role JWT or an sb_secret_ key.", env_var, role,
        )
    if not key_info["key"]:
        logger.critical("No privileged Supabase key configured: all database-backed API routes will fail closed.")
    if not os.environ.get("SUPABASE_JWT_SECRET", "").strip():
        logger.warning(
            "SUPABASE_JWT_SECRET is empty: HS256 user tokens are rejected and only ES256 tokens "
            "verifiable via the project's JWKS are accepted."
        )


_log_security_configuration()


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
assets_dir = os.path.join(STATIC_DIR, "assets")
if os.path.exists(assets_dir):
    app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")


@app.get("/hero_glacier.png", tags=["ops"])
@app.get("/hero_glacier.jpg", tags=["ops"])
async def hero_glacier_image():
    """Serve sharp glacial iceberg background image."""
    png_path = os.path.join(STATIC_DIR, "hero_glacier.png")
    if os.path.exists(png_path):
        return FileResponse(png_path, media_type="image/png", headers={"Cache-Control": "public, max-age=604800"})
    raise HTTPException(status_code=404, detail="Glacier image not found")


@app.get("/favicon.svg", tags=["ops"])
async def favicon_svg():
    """Serve application SVG favicon."""
    fav_path = os.path.join(STATIC_DIR, "favicon.svg")
    if os.path.exists(fav_path):
        return FileResponse(fav_path, media_type="image/svg+xml", headers={"Cache-Control": "public, max-age=604800"})
    raise HTTPException(status_code=404, detail="Favicon not found")


@app.get("/hero-bg.webp", tags=["ops"])
async def hero_background_webp():
    """Serve WebP cinematic background image for legacy landing page fallback."""
    webp_path = os.path.join(STATIC_DIR, "hero_bg.webp")
    if os.path.exists(webp_path):
        return FileResponse(webp_path, media_type="image/webp", headers={"Cache-Control": "public, max-age=604800"})
    raise HTTPException(status_code=404, detail="Background image not found")


@app.get("/hero-bg.jpg", tags=["ops"])
async def hero_background_jpg():
    """Serve JPEG fallback cinematic background image."""
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

# Test helper alias
from rate_limiter import reset_rate_limiters as _reset_receipt_scan_rate_limits


# ─── Entry Point ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000)),
        reload=os.environ.get("RELOAD", "false").lower() == "true",
        log_level="info",
    )
