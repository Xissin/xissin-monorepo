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
from routers import keys, users, sms, settings
from database import init_db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 Xissin App Backend starting up...")
    await init_db()
    yield
    logger.info("🛑 Xissin App Backend shutting down.")


app = FastAPI(
    title="Xissin App API",
    description="Backend API for the Xissin Multi-Tool Flutter App",
    version="1.1.0",
    lifespan=lifespan,
)

# ── Rate limiter ───────────────────────────────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ───────────────────────────────────────────────────────────────────────
# BUG 4 FIX:
# allow_origins=["*"] + allow_credentials=True is INVALID per the CORS spec.
# Browsers reject this combination. Since the Flutter app sends auth data
# in request bodies (not cookies), allow_credentials must be False.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  # ✅ FIXED — was True, incompatible with wildcard origin
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Request logging middleware ─────────────────────────────────────────────────
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    try:
        duration = round(time.time() - start, 3)
        client_ip = request.client.host if request.client else "unknown"
        if request.url.path not in ("/health", "/api/status"):
            logger.info(
                f"{request.method} {request.url.path} "
                f"→ {response.status_code} "
                f"({duration}s) "
                f"[{client_ip}]"
            )
    except Exception as e:
        logger.warning(f"Log middleware error (non-fatal): {e}")
    return response


# ── Routers ────────────────────────────────────────────────────────────────────
app.include_router(keys.router,     prefix="/api/keys",     tags=["Keys"])
app.include_router(users.router,    prefix="/api/users",    tags=["Users"])
app.include_router(sms.router,      prefix="/api/sms",      tags=["SMS Bomber"])
app.include_router(settings.router, prefix="/api/settings", tags=["Settings"])  # ← NEW


# ── Base routes ────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "status":  "online",
        "app":     "Xissin Multi-Tool API",
        "version": "1.1.0",
    }


@app.get("/health")
def health():
    return {"status": "healthy"}


# ── /api/status ───────────────────────────────────────────────────────────────
# Priority order:
#   1. Redis settings (set via admin dashboard) ← checked FIRST
#   2. Railway env vars                         ← fallback
@app.get("/api/status")
def api_status():
    import database as db
    s = db.get_server_settings()

    # Railway env var can still force maintenance even if Redis says false
    maintenance = s.get("maintenance", False)
    if not maintenance:
        maintenance = os.environ.get("MAINTENANCE_MODE", "false").lower() == "true"

    maintenance_msg = s.get(
        "maintenance_message",
        os.environ.get("MAINTENANCE_MSG", "Xissin is under maintenance. We'll be back shortly!")
    )
    min_ver = s.get("min_app_version",    os.environ.get("MIN_APP_VERSION",    "1.0.0"))
    lat_ver = s.get("latest_app_version", os.environ.get("LATEST_APP_VERSION", "1.0.0"))

    return {
        "api_version":        "1.1.0",
        "min_app_version":    min_ver,
        "latest_app_version": lat_ver,
        "maintenance":         maintenance,
        "maintenance_message": maintenance_msg if maintenance else None,
        "features": {
            "sms_bomber":  s.get("feature_sms",  os.environ.get("FEATURE_SMS",  "true").lower() == "true"),
            "key_manager": s.get("feature_keys", os.environ.get("FEATURE_KEYS", "true").lower() == "true"),
        },
        "links": {
            "channel":    "https://t.me/Xissin_0",
            "discussion": "https://t.me/Xissin_1",
        },
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
