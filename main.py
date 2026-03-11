from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from contextlib import asynccontextmanager
import uvicorn
import os
import logging

from limiter import limiter
from routers import keys, users, sms
from database import init_db

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
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
    version="1.0.0",
    lifespan=lifespan,
)

# ── Attach limiter ────────────────────────────────────────────────────────────
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(keys.router,  prefix="/api/keys",  tags=["Keys"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(sms.router,   prefix="/api/sms",   tags=["SMS Bomber"])

# ── Base routes ───────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"status": "online", "app": "Xissin Multi-Tool API", "version": "1.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
