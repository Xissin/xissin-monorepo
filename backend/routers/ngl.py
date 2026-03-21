"""
routers/ngl.py — NGL Anonymous Message Bomber

ARCHITECTURE CHANGE:
  Before: App → Railway backend → ngl.link  (Railway IP gets blocked/rate-limited)
  After:  App → ngl.link directly from user's phone  (same as SMS Bomber)
          App → /ngl/log  (backend only logs the result for admin panel)

Endpoints:
  POST /ngl/send  — legacy/admin: still works, fires from Railway
  POST /ngl/log   — NEW: client-side log (called by app after NglService.bombAll)
  GET  /ngl/stats — admin
  GET  /ngl/logs  — admin
"""

from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel, Field, field_validator
import httpx
import asyncio
import random
import re
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

import database as db
from limiter import limiter
from auth import require_admin, verify_app_request

router  = APIRouter()
PH_TZ   = ZoneInfo("Asia/Manila")

_MAX_CONCURRENT = 5
_ngl_semaphore: asyncio.Semaphore | None = None

def _get_semaphore() -> asyncio.Semaphore:
    global _ngl_semaphore
    if _ngl_semaphore is None:
        _ngl_semaphore = asyncio.Semaphore(_MAX_CONCURRENT)
    return _ngl_semaphore

_USER_AGENTS = [
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 13; SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Infinix X6816) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 12; Redmi Note 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 11; TECNO KF6i) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
]

_NGL_ENDPOINTS = [
    "https://ngl.link/api/submit",
]


def _ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)


# ── Shared models ─────────────────────────────────────────────────────────────

class NglRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=60)
    message:  str = Field(..., min_length=1, max_length=300)
    quantity: int = Field(default=1, ge=1, le=50)
    user_id:  str = Field(..., min_length=1, max_length=50)

    @field_validator("username")
    @classmethod
    def clean_username(cls, v: str) -> str:
        v = v.strip().lstrip("@")
        v = re.sub(r"https?://(www\.)?ngl\.link/", "", v)
        v = v.strip("/").strip()
        if not re.match(r"^[A-Za-z0-9._]{1,60}$", v):
            raise ValueError("Invalid NGL username.")
        return v

    @field_validator("message")
    @classmethod
    def clean_message(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Message cannot be empty.")
        return v

    @field_validator("user_id")
    @classmethod
    def clean_user_id(cls, v: str) -> str:
        return v.strip()


class NglResponse(BaseModel):
    success:  bool
    username: str
    quantity: int
    sent:     int
    failed:   int
    message:  str


# ── Core send logic (used by /send endpoint — fires from Railway) ─────────────

async def _send_one(client: httpx.AsyncClient, username: str, message: str, index: int) -> bool:
    if index < 5:
        await asyncio.sleep(index * 0.1)

    device_id  = str(uuid.uuid4())
    user_agent = random.choice(_USER_AGENTS)
    payload    = (
        f"username={username}"
        f"&question={message}"
        f"&deviceId={device_id}&gameSlug=&referrer="
    )
    headers = {
        "authority":        "ngl.link",
        "accept":           "*/*",
        "accept-language":  "en-US,en;q=0.9",
        "content-type":     "application/x-www-form-urlencoded; charset=UTF-8",
        "origin":           "https://ngl.link",
        "referer":          f"https://ngl.link/{username}",
        "sec-ch-ua":        '"Chromium";v="124", "Google Chrome";v="124"',
        "sec-fetch-dest":   "empty",
        "sec-fetch-mode":   "cors",
        "sec-fetch-site":   "same-origin",
        "x-requested-with": "XMLHttpRequest",
        "user-agent":       user_agent,
    }

    for attempt in range(2):
        try:
            resp = await client.post(
                _NGL_ENDPOINTS[0],
                headers=headers,
                content=payload,
                timeout=12,
            )
            if resp.status_code == 200:
                return True
            if resp.status_code == 429 and attempt == 0:
                await asyncio.sleep(1.5)
                continue
            return False
        except Exception:
            if attempt == 0:
                await asyncio.sleep(0.5)
            continue
    return False


# ── /send — legacy/admin: fires from Railway backend ─────────────────────────
# NOTE: The Flutter app no longer calls this. It now uses NglService (client-side).
# Kept for admin testing and backward compatibility.

@router.post("/send", response_model=NglResponse,
             dependencies=[Depends(verify_app_request)])
@limiter.limit("3/minute")
async def send_ngl(req: NglRequest, request: Request):
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="Your account has been banned.")

    settings = db.get_server_settings()
    if not settings.get("feature_ngl", True):
        raise HTTPException(status_code=503,
                            detail="NGL Bomber is currently disabled by the server.")

    async with _get_semaphore():
        sent = failed = 0
        async with httpx.AsyncClient() as client:
            tasks   = [
                _send_one(client, req.username, req.message, i)
                for i in range(req.quantity)
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)

        for result in results:
            if result is True:
                sent += 1
            else:
                failed += 1

    if sent > 0:
        db.increment_ngl_stat(req.user_id, sent)

    db.append_log({
        "action":   "ngl_sent",
        "user_id":  req.user_id,
        "target":   req.username,
        "message":  req.message,
        "quantity": req.quantity,
        "sent":     sent,
        "failed":   failed,
        "source":   "server",
    })

    success = sent > 0
    return NglResponse(
        success=success,
        username=req.username,
        quantity=req.quantity,
        sent=sent,
        failed=failed,
        message=(
            f"Sent {sent}/{req.quantity} messages to @{req.username}!" if success
            else f"All {req.quantity} messages failed."
        ),
    )


# ── /log — NEW: client-side log (app calls this AFTER NglService.bombAll) ─────
# Does NOT send any messages. Records only. Same pattern as /sms/log.

class NglLogRequest(BaseModel):
    user_id:  str  = Field(..., min_length=1, max_length=50)
    username: str  = Field(..., min_length=1, max_length=60)
    message:  str  = Field(..., min_length=1, max_length=300)
    quantity: int  = Field(default=1, ge=1, le=50)
    sent:     int  = Field(default=0, ge=0)
    failed:   int  = Field(default=0, ge=0)
    results:  list = Field(default_factory=list)

    @field_validator("username")
    @classmethod
    def clean_username(cls, v: str) -> str:
        v = v.strip().lstrip("@")
        v = re.sub(r"https?://(www\.)?ngl\.link/", "", v)
        return v.strip("/").strip()

    @field_validator("user_id")
    @classmethod
    def clean_user_id(cls, v: str) -> str:
        return v.strip()


@router.post("/log", dependencies=[Depends(verify_app_request)])
@limiter.limit("10/minute")
async def log_ngl_result(req: NglLogRequest, request: Request):
    """
    Log a client-side NGL bomb result to Redis / admin panel.
    Does NOT send any messages — records only.
    Called automatically by the Flutter app after NglService.bombAll() finishes.
    """
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="Your account has been banned.")

    settings = db.get_server_settings()
    if not settings.get("feature_ngl", True):
        raise HTTPException(status_code=503,
                            detail="NGL Bomber is currently disabled by the server.")

    total = req.sent + req.failed

    # Update user's NGL counter in stats
    if req.sent > 0:
        db.increment_ngl_stat(req.user_id, req.sent)

    # Activity log (visible in admin Activity Logs panel)
    db.append_log({
        "action":   "ngl_sent",
        "user_id":  req.user_id,
        "target":   req.username,
        "message":  req.message,
        "quantity": req.quantity,
        "sent":     req.sent,
        "failed":   req.failed,
        "source":   "client",   # marks it was fired from user's phone
    })

    return {"success": True, "logged": True}


# ── Admin endpoints ───────────────────────────────────────────────────────────

@router.get("/stats", dependencies=[Depends(require_admin)])
def get_ngl_stats():
    """Admin: NGL messages sent totals by user."""
    all_stats = db.get_all_ngl_stats()
    total     = sum(all_stats.values())
    users     = db.get_all_users()
    by_user   = [
        {
            "user_id":  uid,
            "username": users.get(uid, {}).get("username", ""),
            "total":    count,
        }
        for uid, count in sorted(all_stats.items(), key=lambda x: x[1], reverse=True)
    ]
    return {"total_ngl_sent": total, "user_count": len(by_user), "by_user": by_user}


@router.get("/logs", dependencies=[Depends(require_admin)])
def get_ngl_logs(limit: int = 100):
    """Admin: recent NGL send logs."""
    all_logs = db.get_logs(limit=500)
    ngl_logs = [l for l in all_logs if l.get("action") == "ngl_sent"][:limit]
    return {"total": len(ngl_logs), "logs": ngl_logs}
