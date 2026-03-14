"""
routers/ngl.py — NGL Anonymous Message Bomber

Sends anonymous messages to any ngl.link/username profile.
Key-gated: user must have an active key.
Rate-limited: 3 requests/minute per IP.
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
import requests
import threading
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

import database as db
from limiter import limiter

router = APIRouter()

# ── Concurrency guard ─────────────────────────────────────────────────────────
_MAX_CONCURRENT = 5
_ngl_semaphore  = threading.Semaphore(_MAX_CONCURRENT)

_NGL_POOL = ThreadPoolExecutor(
    max_workers=20,
    thread_name_prefix="ngl-worker",
)

# ── Models ────────────────────────────────────────────────────────────────────

class NglRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=60)
    message:  str = Field(..., min_length=1, max_length=300)
    quantity: int = Field(default=1, ge=1, le=50)
    user_id:  str = Field(..., min_length=1, max_length=50)

    @field_validator("username")
    @classmethod
    def clean_username(cls, v: str) -> str:
        # strip ngl.link/ prefix if user pastes the full URL
        v = v.strip().lstrip("@")
        v = re.sub(r"https?://(www\.)?ngl\.link/", "", v)
        if not re.match(r"^[A-Za-z0-9._]{1,60}$", v):
            raise ValueError("Invalid NGL username. Use letters, numbers, dots, underscores.")
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
        if not v.strip():
            raise ValueError("user_id cannot be empty")
        return v.strip()


class NglResponse(BaseModel):
    success:   bool
    username:  str
    quantity:  int
    sent:      int
    failed:    int
    message:   str


# ── Core sender ───────────────────────────────────────────────────────────────

def _send_one(username: str, message: str) -> bool:
    """Send a single anonymous NGL message. Returns True on success."""
    url = "https://ngl.link/api/submit"
    payload = (
        f"username={requests.utils.quote(username)}"
        f"&question={requests.utils.quote(message)}"
        f"&deviceId=b8803802-3b9a-4f58-81dd-b0483418aecc"
        f"&gameSlug=&referrer="
    )
    headers = {
        "authority":         "ngl.link",
        "accept":            "*/*",
        "accept-language":   "en-US,en;q=0.9",
        "content-type":      "application/x-www-form-urlencoded; charset=UTF-8",
        "origin":            "https://ngl.link",
        "referer":           f"https://ngl.link/{username}",
        "sec-fetch-dest":    "empty",
        "sec-fetch-mode":    "cors",
        "sec-fetch-site":    "same-origin",
        "x-requested-with":  "XMLHttpRequest",
        "user-agent": (
            "Mozilla/5.0 (Linux; Android 14) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Mobile Safari/537.36"
        ),
    }
    try:
        resp = requests.post(url, headers=headers, data=payload, timeout=10)
        return resp.status_code == 200
    except Exception:
        return False


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/send", response_model=NglResponse)
@limiter.limit("3/minute")
async def send_ngl(req: NglRequest, request: Request):
    # ── 1. Check user is registered ──
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")

    # ── 2. Check ban ──
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="Your account has been banned.")

    # ── 3. Check active key ──
    key_data = db.get_key_for_user(req.user_id)
    if not key_data or key_data.get("status") != "active":
        raise HTTPException(
            status_code=403,
            detail="Active key required to use NGL Bomber.",
        )

    # ── 4. Concurrency guard ──
    acquired = _ngl_semaphore.acquire(blocking=False)
    if not acquired:
        raise HTTPException(
            status_code=429,
            detail="Server is busy. Please try again in a moment.",
        )

    sent   = 0
    failed = 0

    try:
        futures = [
            _NGL_POOL.submit(_send_one, req.username, req.message)
            for _ in range(req.quantity)
        ]
        for fut in as_completed(futures):
            if fut.result():
                sent += 1
            else:
                failed += 1
    finally:
        _ngl_semaphore.release()

    # ── 5. Log usage ──
    db.append_log({
        "action":   "ngl_sent",
        "user_id":  req.user_id,
        "username": req.username,
        "quantity": req.quantity,
        "sent":     sent,
        "failed":   failed,
    })

    success = sent > 0
    return NglResponse(
        success=success,
        username=req.username,
        quantity=req.quantity,
        sent=sent,
        failed=failed,
        message=(
            f"✅ Sent {sent}/{req.quantity} messages to @{req.username}!"
            if success
            else f"❌ All {req.quantity} messages failed. The username may not exist."
        ),
    )
