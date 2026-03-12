from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import uvicorn
import os
import time
import logging

from limiter import limiter
from routers import keys, users, sms
from database import init_db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 Xissin App Backend starting up...")
    init_db()
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
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
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
        # Skip logging health + status spam
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


# ── Routers — v1 (new versioned routes) ───────────────────────────────────────
# Flutter app should use these going forward
app.include_router(keys.router,  prefix="/api/v1/keys",  tags=["v1 - Keys"])
app.include_router(users.router, prefix="/api/v1/users", tags=["v1 - Users"])
app.include_router(sms.router,   prefix="/api/v1/sms",   tags=["v1 - SMS Bomber"])

# ── Routers — legacy (old routes kept so current app version never breaks) ─────
app.include_router(keys.router,  prefix="/api/keys",  tags=["Legacy - Keys"],  include_in_schema=False)
app.include_router(users.router, prefix="/api/users", tags=["Legacy - Users"], include_in_schema=False)
app.include_router(sms.router,   prefix="/api/sms",   tags=["Legacy - SMS"],   include_in_schema=False)


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


# ── R1: /api/status ───────────────────────────────────────────────────────────
# Flutter app calls this on every launch.
# Control everything via Railway environment variables — no code changes needed.
#
# Railway env vars to set:
#   MAINTENANCE_MODE   = "true" or "false"   (default: false)
#   MAINTENANCE_MSG    = "We'll be back soon" (optional custom message)
#   MIN_APP_VERSION    = "1.0.0"             (force update if app is older)
#   LATEST_APP_VERSION = "1.0.0"             (latest version available)
#   FEATURE_SMS        = "true" or "false"   (toggle SMS bomber on/off)
#   FEATURE_KEYS       = "true" or "false"   (toggle Key Manager on/off)
@app.get("/api/status")
def api_status():
    maintenance = os.environ.get("MAINTENANCE_MODE", "false").lower() == "true"
    maintenance_msg = os.environ.get(
        "MAINTENANCE_MSG",
        "Xissin is under maintenance. We'll be back shortly!"
    )

    return {
        # Versioning
        "api_version":        "1.1.0",
        "min_app_version":    os.environ.get("MIN_APP_VERSION",    "1.0.0"),
        "latest_app_version": os.environ.get("LATEST_APP_VERSION", "1.0.0"),

        # Maintenance — Flutter shows a full maintenance screen if True
        "maintenance":         maintenance,
        "maintenance_message": maintenance_msg if maintenance else None,

        # Feature flags — disable tools without shipping a new app build
        "features": {
            "sms_bomber":  os.environ.get("FEATURE_SMS",  "true").lower() == "true",
            "key_manager": os.environ.get("FEATURE_KEYS", "true").lower() == "true",
        },

        # Community links shown in app
        "links": {
            "channel":    "https://t.me/Xissin_0",
            "discussion": "https://t.me/Xissin_1",
        },
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
