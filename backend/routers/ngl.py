"""
routers/ngl.py — NGL Anonymous Message Bomber

Sends anonymous messages to any ngl.link/username profile.
Key-gated: user must have an active key.
Rate-limited: 3 requests/minute per IP.
"""

from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel, Field, field_validator
import requests
import threading
import time
import random
import re
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from zoneinfo import ZoneInfo

import database as db
from limiter import limiter
from auth import require_admin

router = APIRouter()
PH_TZ  = ZoneInfo("Asia/Manila")

_MAX_CONCURRENT = 5
_ngl_semaphore  = threading.Semaphore(_MAX_CONCURRENT)

_NGL_POOL = ThreadPoolExecutor(max_workers=20, thread_name_prefix="ngl-worker")

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


def _ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)


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


def _send_one(username: str, message: str, index: int) -> bool:
    delay_s = min(index * 0.1, 2.0)
    if delay_s > 0:
        time.sleep(delay_s)
    device_id  = str(uuid.uuid4())
    user_agent = random.choice(_USER_AGENTS)
    url     = "https://ngl.link/api/submit"
    payload = (
        f"username={requests.utils.quote(username, safe='')}"
        f"&question={requests.utils.quote(message, safe='')}"
        f"&deviceId={device_id}&gameSlug=&referrer="
    )
    headers = {
        "authority": "ngl.link", "accept": "*/*",
        "accept-language": "en-US,en;q=0.9",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "origin": "https://ngl.link", "referer": f"https://ngl.link/{username}",
        "sec-ch-ua": '"Chromium";v="124", "Google Chrome";v="124"',
        "sec-fetch-dest": "empty", "sec-fetch-mode": "cors",
        "sec-fetch-site": "same-origin", "x-requested-with": "XMLHttpRequest",
        "user-agent": user_agent,
    }
    try:
        resp = requests.post(url, headers=headers, data=payload, timeout=12)
        return resp.status_code == 200
    except Exception:
        return False


@router.post("/send", response_model=NglResponse)
@limiter.limit("3/minute")
async def send_ngl(req: NglRequest, request: Request):
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="Your account has been banned.")

    active_key  = user.get("active_key")
    key_expires = user.get("key_expires")
    if not active_key or not key_expires:
        raise HTTPException(status_code=403, detail="Active key required to use NGL Bomber. Go to Key Manager to redeem one.")
    try:
        expires_dt = datetime.fromisoformat(key_expires)
    except (ValueError, TypeError):
        raise HTTPException(status_code=403, detail="Invalid key data. Please re-redeem your key.")
    if _ph_now() > expires_dt:
        raise HTTPException(status_code=403, detail="Your key has expired. Please redeem a new key.")

    settings = db.get_server_settings()
    if not settings.get("feature_ngl", True):
        raise HTTPException(status_code=503, detail="NGL Bomber is currently disabled by the server.")

    acquired = _ngl_semaphore.acquire(blocking=False)
    if not acquired:
        raise HTTPException(status_code=429, detail="Server is busy. Please try again in a moment.")

    sent = failed = 0
    try:
        futures = {_NGL_POOL.submit(_send_one, req.username, req.message, i): i for i in range(req.quantity)}
        for fut in as_completed(futures):
            try:
                if fut.result(): sent += 1
                else: failed += 1
            except Exception:
                failed += 1
    finally:
        _ngl_semaphore.release()

    if sent > 0:
        db.increment_ngl_stat(req.user_id, sent)

    db.append_log({
        "action": "ngl_sent", "user_id": req.user_id,
        "target": req.username, "quantity": req.quantity,
        "sent": sent, "failed": failed,
    })

    success = sent > 0
    return NglResponse(
        success=success, username=req.username, quantity=req.quantity,
        sent=sent, failed=failed,
        message=(
            f"Sent {sent}/{req.quantity} messages to @{req.username}!" if success
            else f"All {req.quantity} messages failed. The username '@{req.username}' may not exist or ngl.link is blocking requests."
        ),
    )


@router.get("/stats", dependencies=[Depends(require_admin)])
def get_ngl_stats():
    """Admin: NGL messages sent totals by user."""
    all_stats = db.get_all_ngl_stats()
    total     = sum(all_stats.values())
    users     = db.get_all_users()
    by_user   = [
        {"user_id": uid, "username": users.get(uid, {}).get("username", ""), "total": count}
        for uid, count in sorted(all_stats.items(), key=lambda x: x[1], reverse=True)
    ]
    return {"total_ngl_sent": total, "user_count": len(by_user), "by_user": by_user}


@router.get("/logs", dependencies=[Depends(require_admin)])
def get_ngl_logs(limit: int = 100):
    """Admin: recent NGL send logs."""
    all_logs = db.get_logs(limit=500)
    ngl_logs = [l for l in all_logs if l.get("action") == "ngl_sent"][:limit]
    return {"total": len(ngl_logs), "logs": ngl_logs}
