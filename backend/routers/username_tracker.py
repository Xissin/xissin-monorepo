"""
routers/username_tracker.py
Receives username-search logs from the Flutter app.
The actual checking is done client-side (device IP avoids server blocks).
This router only stores results for the admin panel.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, constr
from typing import List
from auth import verify_app_request

import httpx
import os
import time
import logging

logger = logging.getLogger(__name__)

router = APIRouter()

# ── Upstash REST helpers (same pattern as database.py) ────────────────────────

_REDIS_URL   = os.environ.get("UPSTASH_REDIS_REST_URL", "")
_REDIS_TOKEN = os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")


async def _redis(*cmd):
    """Execute a single Redis command via Upstash REST API."""
    if not _REDIS_URL or not _REDIS_TOKEN:
        raise RuntimeError("Upstash env vars not set")
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.post(
            _REDIS_URL,
            headers={"Authorization": f"Bearer {_REDIS_TOKEN}"},
            json=list(cmd),
        )
        resp.raise_for_status()
        return resp.json().get("result")


# ── Request / response models ─────────────────────────────────────────────────

class UsernameLogRequest(BaseModel):
    username:      constr(min_length=1, max_length=64, strip_whitespace=True)
    user_id:       str  = "anonymous"
    found_on:      List[str] = []
    total_checked: int  = 30


class UsernameLogResponse(BaseModel):
    status: str


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/log", response_model=UsernameLogResponse)
async def log_username_search(
    payload: UsernameLogRequest,
    _=Depends(verify_app_request),
):
    """
    Called by the Flutter app after a search completes.
    Stores the result in Redis for the admin panel.
    """
    ts         = int(time.time())
    username_l = payload.username.lower().strip()
    key        = f"username_tracker:log:{ts}:{username_l}"

    try:
        # Store the log entry (expires in 30 days)
        log_entry = {
            "username":    username_l,
            "user_id":     payload.user_id,
            "found_on":    ",".join(payload.found_on),
            "found_count": str(len(payload.found_on)),
            "total":       str(payload.total_checked),
            "ts":          str(ts),
        }
        # HMSET equivalent
        flat = [item for pair in log_entry.items() for item in pair]
        await _redis("HSET", key, *flat)
        await _redis("EXPIRE", key, 60 * 60 * 24 * 30)   # 30 days

        # Maintain a sorted-set of popular usernames
        await _redis("ZINCRBY", "username_tracker:popular", 1, username_l)

        # Keep a list of the 500 most-recent search keys
        await _redis("LPUSH", "username_tracker:recent_keys", key)
        await _redis("LTRIM", "username_tracker:recent_keys", 0, 499)

        logger.info(
            f"[username_tracker] logged '{username_l}' "
            f"found_on={len(payload.found_on)}/{payload.total_checked}"
        )
    except Exception as exc:
        # Logging is best-effort — never return 5xx to the app
        logger.warning(f"[username_tracker] log failed (non-fatal): {exc}")

    return UsernameLogResponse(status="logged")


@router.get("/popular")
async def get_popular_usernames(limit: int = 20):
    """Admin: top usernames searched across all users."""
    try:
        raw = await _redis(
            "ZREVRANGE", "username_tracker:popular", 0, limit - 1, "WITHSCORES"
        )
        # Upstash returns a flat list [name, score, name, score …]
        items = []
        if raw:
            it = iter(raw)
            for username in it:
                score = next(it, 0)
                items.append({"username": username, "count": int(float(score))})
        return {"popular": items}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/recent")
async def get_recent_searches(limit: int = 50):
    """Admin: most-recent username searches."""
    try:
        keys = await _redis("LRANGE", "username_tracker:recent_keys", 0, limit - 1)
        if not keys:
            return {"searches": []}

        searches = []
        for key in keys:
            entry = await _redis("HGETALL", key)
            if entry:
                # Upstash HGETALL returns a flat list [field, val, …]
                d: dict = {}
                if isinstance(entry, list):
                    it = iter(entry)
                    for field in it:
                        val = next(it, "")
                        d[field] = val
                elif isinstance(entry, dict):
                    d = entry
                searches.append(d)

        return {"searches": searches}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
