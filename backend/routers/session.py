"""
backend/routers/session.py

Session token system — replaces the hardcoded HMAC secret in the APK.

Flow:
  1. App launches → sends bootstrap HMAC to POST /api/auth/session
  2. Backend validates bootstrap (rate-limited, device-fingerprinted)
  3. Backend generates a random session token → stores in Redis (24h TTL)
  4. App stores session token in FlutterSecureStorage
  5. ALL subsequent API requests send X-Session-Token header
  6. Backend looks it up in Redis — if found → authorized

Why this is safer than the old approach:
  - The hardcoded secret in the APK only gets you a rate-limited session
  - Real authorization lives server-side in Redis
  - Session tokens are random (unforgeable without calling this endpoint)
  - Tokens expire after 24h and auto-refresh
  - Each session is tied to a device fingerprint

FIXES (v2):
  - BUG 1: redis_set() called with ex= keyword — corrected to ttl_seconds=
  - BUG 2: redis_set/redis_get/redis_incr are SYNC functions — removed await
"""

import hashlib
import hmac
import os
import secrets
import time
import logging

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)

router = APIRouter()

# ── Bootstrap secret ──────────────────────────────────────────────────────────
_BOOTSTRAP_SALT = os.environ.get("BOOTSTRAP_SALT", "xis-boot-2024")
_APP_ID         = "com.xissin.app"
_TOKEN_WINDOW   = 30     # seconds
_SESSION_TTL    = 86400  # 24 hours

_MAX_SESSION_REQUESTS_PER_HOUR = 5


# ── Pydantic models ───────────────────────────────────────────────────────────

class SessionRequest(BaseModel):
    device_fingerprint: str
    timestamp:          int
    bootstrap_token:    str
    app_id:             str


class SessionResponse(BaseModel):
    session_token: str
    expires_in:    int  # seconds


# ── Helpers ───────────────────────────────────────────────────────────────────

def _verify_bootstrap(device_fp: str, timestamp: int, token: str) -> bool:
    """
    Bootstrap HMAC: HMAC-SHA256(device_fp:timestamp:app_id, bootstrap_salt)
    30-second window to prevent replay.
    """
    now = int(time.time())
    if abs(now - timestamp) > _TOKEN_WINDOW:
        logger.warning(f"Bootstrap replay attempt: ts={timestamp} now={now}")
        return False

    message  = f"{device_fp}:{timestamp}:{_APP_ID}"
    expected = hmac.new(
        _BOOTSTRAP_SALT.encode(),
        message.encode(),
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, token)


def _check_rate_limit(device_fp: str) -> bool:
    """
    Allow max 5 session requests per device per hour.
    Uses Redis to track count.
    NOTE: Uses sync db calls — no await needed.
    """
    try:
        import database as db
        rate_key = f"sess_rate:{device_fp}"
        count    = db.redis_get(rate_key)  # ← sync, no await

        if count is None:
            db.redis_set(rate_key, "1", ttl_seconds=3600)  # ← fixed: ttl_seconds not ex
            return True

        if int(count) >= _MAX_SESSION_REQUESTS_PER_HOUR:
            logger.warning(f"Session rate limit hit for device: {device_fp[:16]}...")
            return False

        db.redis_incr(rate_key)  # ← sync, no await
        return True
    except Exception as e:
        logger.warning(f"Rate limit check failed (allowing): {e}")
        return True  # fail open on Redis error


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/session", response_model=SessionResponse)
async def create_session(payload: SessionRequest, request: Request):
    """
    Creates a new session token for the app.
    Protected by bootstrap HMAC — rate limited per device.
    """
    client_ip = request.client.host if request.client else "unknown"

    # 1. Validate app ID
    if payload.app_id != _APP_ID:
        raise HTTPException(status_code=401, detail="Invalid app ID")

    # 2. Validate fingerprint length (should be 32 hex chars)
    if not payload.device_fingerprint or len(payload.device_fingerprint) < 16:
        raise HTTPException(status_code=400, detail="Invalid device fingerprint")

    # 3. Validate bootstrap HMAC
    if not _verify_bootstrap(
        payload.device_fingerprint,
        payload.timestamp,
        payload.bootstrap_token,
    ):
        logger.warning(
            f"Bootstrap HMAC failed: device={payload.device_fingerprint[:16]}... "
            f"ip={client_ip}"
        )
        raise HTTPException(status_code=401, detail="Invalid bootstrap token")

    # 4. Rate limit check — sync function, no await
    if not _check_rate_limit(payload.device_fingerprint):
        raise HTTPException(
            status_code=429,
            detail="Too many session requests. Try again later.",
        )

    # 5. Generate cryptographically random session token
    session_token = secrets.token_hex(32)  # 256-bit random token

    # 6. Store in Redis with TTL — sync call, no await, correct kwarg
    try:
        import database as db
        session_data = {
            "device_fp":  payload.device_fingerprint,
            "created_at": int(time.time()),
            "ip":         client_ip,
        }
        db.redis_set(                        # ← sync, no await
            f"sess:{session_token}",
            str(session_data),
            ttl_seconds=_SESSION_TTL,        # ← fixed: ttl_seconds not ex
        )
        logger.info(
            f"Session created: device={payload.device_fingerprint[:16]}... "
            f"ip={client_ip}"
        )
    except Exception as e:
        logger.error(f"Failed to store session in Redis: {e}")
        raise HTTPException(status_code=500, detail="Session creation failed")

    return SessionResponse(
        session_token=session_token,
        expires_in=_SESSION_TTL,
    )


@router.delete("/session")
async def revoke_session(
    request: Request,
    x_session_token: Optional[str] = None,
):
    """
    Revokes the current session token (logout / re-auth).
    """
    token = request.headers.get("X-Session-Token")
    if not token:
        return {"revoked": False, "reason": "No token provided"}

    try:
        import database as db
        deleted = db.redis_delete(f"sess:{token}")  # ← sync, no await
        return {"revoked": bool(deleted)}
    except Exception:
        return {"revoked": False}