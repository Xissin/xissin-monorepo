from fastapi import FastAPI, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import uvicorn
import os
import time
import logging
from typing import Optional

from limiter import limiter
from routers import users, sms
from database import init_db

try:
    from routers import settings as settings_router
    _HAS_SETTINGS = True
except ImportError:
    _HAS_SETTINGS = False

try:
    from routers import announcements as announcements_router
    _HAS_ANNOUNCEMENTS = True
except ImportError:
    _HAS_ANNOUNCEMENTS = False

try:
    from routers import ngl as ngl_router
    _HAS_NGL = True
except ImportError:
    _HAS_NGL = False

try:
    from routers import location as location_router
    _HAS_LOCATION = True
except ImportError:
    _HAS_LOCATION = False

try:
    from routers import payments as payments_router
    _HAS_PAYMENTS = True
except ImportError:
    _HAS_PAYMENTS = False

try:
    from routers import crash_report as crash_report_router
    _HAS_CRASH_REPORT = True
except ImportError:
    _HAS_CRASH_REPORT = False

try:
    from routers import ip_tracker as ip_tracker_router
    _HAS_IP_TRACKER = True
except ImportError:
    _HAS_IP_TRACKER = False

try:
    from routers import username_tracker as username_tracker_router
    _HAS_USERNAME_TRACKER = True
except ImportError:
    _HAS_USERNAME_TRACKER = False

try:
    from routers import session as session_router
    _HAS_SESSION = True
except ImportError:
    _HAS_SESSION = False

try:
    from routers import tools as tools_router
    _HAS_TOOLS = True
except ImportError:
    _HAS_TOOLS = False

# ── NEW: CODM Checker ─────────────────────────────────────────
try:
    from routers import codm as codm_router
    _HAS_CODM = True
except ImportError:
    _HAS_CODM = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    port = int(os.environ.get("PORT", 8000))
    logger.info("=" * 55)
    logger.info("🚀  XISSIN BACKEND  v2.4.0  —  STARTING UP")
    logger.info("=" * 55)
    logger.info(f"🌐  Listening on  0.0.0.0:{port}")
    logger.info(f"🔧  Environment : {os.environ.get('ENVIRONMENT', 'production')}")

    logger.info("🗄️   Connecting to Redis (Upstash)...")
    try:
        await init_db()
        logger.info("✅  Redis connected successfully")
    except Exception as e:
        logger.error(f"❌  Redis connection FAILED: {e}")

    logger.info("📦  Routers loaded:")
    logger.info("    ✅  /api/users             — Users")
    logger.info("    ✅  /api/sms               — SMS Bomber")
    logger.info(f"    {'✅' if _HAS_NGL                else '❌'}  /api/ngl              — NGL Bomber")
    logger.info(f"    {'✅' if _HAS_ANNOUNCEMENTS       else '❌'}  /api/announcements")
    logger.info(f"    {'✅' if _HAS_SETTINGS            else '❌'}  /api/settings")
    logger.info(f"    {'✅' if _HAS_LOCATION            else '❌'}  /api/location         — User Map")
    logger.info(f"    {'✅' if _HAS_PAYMENTS            else '❌'}  /api/payments         — Premium Keys")
    logger.info(f"    {'✅' if _HAS_CRASH_REPORT        else '❌'}  /api/crash-report     — Crash Reports")
    logger.info(f"    {'✅' if _HAS_IP_TRACKER          else '❌'}  /api/ip-tracker       — IP Tracker")
    logger.info(f"    {'✅' if _HAS_USERNAME_TRACKER    else '❌'}  /api/username-tracker — Username Tracker")
    logger.info(f"    {'✅' if _HAS_SESSION              else '❌'}  /api/auth/session     — Session Tokens")
    logger.info(f"    {'✅' if _HAS_TOOLS               else '❌'}  /api/tools            — Tool Logs")
    logger.info(f"    {'✅' if _HAS_CODM                else '❌'}  /api/codm             — CODM Checker")
    logger.info("=" * 55)

    bot_token = os.getenv("XISSIN_BOT_TOKEN")
    if not bot_token or not bot_token.strip():
        logger.warning("⚠️  WARNING: XISSIN_BOT_TOKEN is missing from environment variables!")
    else:
        logger.info("✅  Telegram Bot Token loaded successfully.")

    codm_cookies = os.getenv("CODM_COOKIES", "")
    cookie_count = len([l for l in codm_cookies.splitlines() if l.strip()])
    if cookie_count == 0:
        logger.warning("⚠️  CODM_COOKIES env var is empty — CODM checker will have no DataDome cookies.")
        logger.warning("⚠️  Add datadome cookies to CODM_COOKIES in Railway env vars.")
    else:
        logger.info(f"✅  CODM_COOKIES loaded: {cookie_count} cookie(s) available.")

    logger.info("=" * 55)
    logger.info("✅  Xissin Backend is ONLINE and ready!")
    logger.info("=" * 55)

    yield

    logger.info("🛑  Xissin Backend shutting down gracefully.")


app = FastAPI(
    title="Xissin App API",
    description="Backend API for the Xissin Multi-Tool Flutter App",
    version="2.4.0",
    lifespan=lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start    = time.time()
    response = await call_next(request)
    try:
        duration  = round(time.time() - start, 3)
        client_ip = request.client.host if request.client else "unknown"
        path      = request.url.path

        if path in ("/health", "/api/status"):
            logger.info(f"💓  HEALTH {path} → {response.status_code} [{client_ip}]")
        else:
            logger.info(
                f"{request.method} {path} "
                f"→ {response.status_code} "
                f"({duration}s) [{client_ip}]"
            )
    except Exception as e:
        logger.warning(f"Log middleware error (non-fatal): {e}")
    return response


# ── Routers ───────────────────────────────────────────────────
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(sms.router,   prefix="/api/sms",   tags=["SMS Bomber"])

if _HAS_SETTINGS:
    app.include_router(settings_router.router,
                       prefix="/api/settings", tags=["Settings"])

if _HAS_ANNOUNCEMENTS:
    app.include_router(announcements_router.router,
                       prefix="/api/announcements", tags=["Announcements"])

if _HAS_NGL:
    app.include_router(ngl_router.router,
                       prefix="/api/ngl", tags=["NGL Bomber"])

if _HAS_LOCATION:
    app.include_router(location_router.router,
                       prefix="/api/location", tags=["Location"])

if _HAS_PAYMENTS:
    app.include_router(payments_router.router,
                       prefix="/api/payments", tags=["Payments"])

if _HAS_CRASH_REPORT:
    app.include_router(crash_report_router.router,
                       prefix="/api", tags=["Crash Reports"])

if _HAS_IP_TRACKER:
    app.include_router(ip_tracker_router.router,
                       prefix="/api/ip-tracker", tags=["IP Tracker"])

if _HAS_USERNAME_TRACKER:
    app.include_router(username_tracker_router.router,
                       prefix="/api/username-tracker", tags=["Username Tracker"])

if _HAS_SESSION:
    app.include_router(session_router.router,
                       prefix="/api/auth", tags=["Auth"])

if _HAS_TOOLS:
    app.include_router(tools_router.router,
                       prefix="/api/tools", tags=["Tool Logs"])

# ── NEW: CODM Checker ─────────────────────────────────────────
if _HAS_CODM:
    app.include_router(codm_router.router,
                       prefix="/api/codm", tags=["CODM Checker"])


# ── Base routes ───────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "status":  "online",
        "app":     "Xissin Multi-Tool API",
        "version": "2.4.0",
    }

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/api/status")
def api_status(user_id: Optional[str] = Query(default=None)):
    import database as db
    s = db.get_server_settings()

    maintenance = s.get("maintenance", False)
    if not maintenance:
        maintenance = os.environ.get("MAINTENANCE_MODE", "false").lower() == "true"

    is_owner = False
    if user_id:
        bypass_ids = s.get("owner_bypass_ids") or []
        if user_id.strip() in [i.strip() for i in bypass_ids if i]:
            is_owner = True

    if maintenance and is_owner:
        maintenance = False
        logger.info(f"🔑  Owner bypass: user_id={user_id[:12]}... skipped maintenance")

    maintenance_msg = s.get(
        "maintenance_message",
        os.environ.get("MAINTENANCE_MSG",
                       "Xissin is under maintenance. We'll be back shortly!")
    )
    min_ver    = s.get("min_app_version",
                       os.environ.get("MIN_APP_VERSION", "1.0.0"))
    lat_ver    = s.get("latest_app_version",
                       os.environ.get("LATEST_APP_VERSION", "1.0.0"))
    apk_url    = s.get("apk_download_url",
                       os.environ.get("LATEST_APK_URL", ""))
    apk_sha256 = s.get("apk_sha256",
                       os.environ.get("LATEST_APK_SHA256", ""))
    apk_notes  = s.get("apk_version_notes",
                       os.environ.get("LATEST_APK_NOTES", ""))

    def _feat(key: str, fallback: bool) -> bool:
        if is_owner: return True
        return s.get(key, fallback)

    return {
        "api_version":        "2.4.0",
        "min_app_version":    min_ver,
        "latest_app_version": lat_ver,
        "apk_download_url":   apk_url,
        "apk_sha256":         apk_sha256,
        "apk_version_notes":  apk_notes,
        "maintenance":         maintenance,
        "maintenance_message": maintenance_msg if maintenance else None,
        "is_owner":            is_owner,
        "features": {
            "sms_bomber":       _feat("feature_sms", True),
            "ngl_bomber":       _feat("feature_ngl", True),
            "url_remover":      _feat("feature_url_remover", True),
            "dup_remover":      _feat("feature_dup_remover", True),
            "ip_tracker":       _feat("feature_ip_tracker", True),
            "username_tracker": _feat("feature_username_tracker", True),
            "codm_checker":     _feat("feature_codm_checker", True),

            # Module loaded flags
            "module_ip_tracker":       _HAS_IP_TRACKER,
            "module_username_tracker": _HAS_USERNAME_TRACKER,
            "module_announcements":    _HAS_ANNOUNCEMENTS,
            "module_premium_keys":     _HAS_PAYMENTS,
            "module_tool_logs":        _HAS_TOOLS,
            "module_codm":             _HAS_CODM,
        },
        "links": {
            "channel":    "https://t.me/Xissin_0",
            "discussion": "https://t.me/Xissin_1",
        },
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main_backend:app", host="0.0.0.0", port=port, reload=False)
