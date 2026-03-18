from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import uvicorn
import os
import time
import logging

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

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup banner ─────────────────────────────────────────────────────
    port = int(os.environ.get("PORT", 8000))
    logger.info("=" * 55)
    logger.info("🚀  XISSIN BACKEND  v1.7.0  —  STARTING UP")
    logger.info("=" * 55)
    logger.info(f"🌐  Listening on  0.0.0.0:{port}")
    logger.info(f"🔧  Environment : {os.environ.get('ENVIRONMENT', 'production')}")

    # ── DB / Redis init ────────────────────────────────────────────────────
    logger.info("🗄️   Connecting to Redis (Upstash)...")
    try:
        await init_db()
        logger.info("✅  Redis connected successfully")
    except Exception as e:
        logger.error(f"❌  Redis connection FAILED: {e}")

    # ── Loaded routers ─────────────────────────────────────────────────────
    logger.info("📦  Routers loaded:")
    logger.info("    ✅  /api/users   — Users")
    logger.info("    ✅  /api/sms     — SMS Bomber")
    logger.info(f"    {'✅' if _HAS_NGL         else '❌'}  /api/ngl       — NGL Bomber")
    logger.info(f"    {'✅' if _HAS_ANNOUNCEMENTS else '❌'}  /api/announcements")
    logger.info(f"    {'✅' if _HAS_SETTINGS     else '❌'}  /api/settings")
    logger.info(f"    {'✅' if _HAS_LOCATION     else '❌'}  /api/location  — User Map")
    logger.info(f"    {'✅' if _HAS_PAYMENTS     else '❌'}  /api/payments  — Remove Ads")

    logger.info("=" * 55)
    logger.info("✅  Xissin Backend is ONLINE and ready!")
    logger.info("=" * 55)

    yield

    # ── Shutdown ───────────────────────────────────────────────────────────
    logger.info("🛑  Xissin Backend shutting down gracefully.")


app = FastAPI(
    title="Xissin App API",
    description="Backend API for the Xissin Multi-Tool Flutter App",
    version="1.7.0",
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

# ── Request logger ─────────────────────────────────────────────────────────────
# Logs ALL requests including /health and /api/status.
# Health checks use a shorter format so they don't clutter the log.
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start    = time.time()
    response = await call_next(request)
    try:
        duration  = round(time.time() - start, 3)
        client_ip = request.client.host if request.client else "unknown"
        path      = request.url.path

        if path in ("/health", "/api/status"):
            # Short heartbeat line — easy to spot but not noisy
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


# ── Routers ────────────────────────────────────────────────────────────────────
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


# ── Base routes ────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "status":  "online",
        "app":     "Xissin Multi-Tool API",
        "version": "1.7.0",
    }

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/api/status")
def api_status():
    import database as db
    s = db.get_server_settings()

    maintenance = s.get("maintenance", False)
    if not maintenance:
        maintenance = os.environ.get("MAINTENANCE_MODE", "false").lower() == "true"

    maintenance_msg = s.get(
        "maintenance_message",
        os.environ.get("MAINTENANCE_MSG",
                       "Xissin is under maintenance. We'll be back shortly!")
    )
    min_ver = s.get("min_app_version",
                    os.environ.get("MIN_APP_VERSION", "1.0.0"))
    lat_ver = s.get("latest_app_version",
                    os.environ.get("LATEST_APP_VERSION", "1.0.0"))

    return {
        "api_version":        "1.7.0",
        "min_app_version":    min_ver,
        "latest_app_version": lat_ver,
        "maintenance":         maintenance,
        "maintenance_message": maintenance_msg if maintenance else None,
        "features": {
            "sms_bomber":    s.get("feature_sms", True),
            "ngl_bomber":    s.get("feature_ngl", True),
            "announcements": _HAS_ANNOUNCEMENTS,
            "remove_ads":    _HAS_PAYMENTS,
        },
        "links": {
            "channel":    "https://t.me/Xissin_0",
            "discussion": "https://t.me/Xissin_1",
        },
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main_backend:app", host="0.0.0.0", port=port, reload=False)
