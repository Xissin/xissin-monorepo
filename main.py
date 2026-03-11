from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import uvicorn
import os
import logging

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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(keys.router,  prefix="/api/keys",  tags=["Keys"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(sms.router,   prefix="/api/sms",   tags=["SMS Bomber"])

@app.get("/")
def root():
    return {"status": "online", "app": "Xissin Multi-Tool API", "version": "1.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
