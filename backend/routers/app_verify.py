"""
routers/app_verify.py — App request signature verification
─────────────────────────────────────────────────────────────────────────────
Every request from the Flutter app includes:
  X-App-Timestamp  : Unix epoch seconds (int)
  X-App-Token      : HMAC-SHA256(user_id + ":" + timestamp, APP_SECRET)
  X-App-Id         : "com.xissin.app"

We verify:
  1. X-App-Id matches expected package name
  2. X-App-Timestamp is within ±90 seconds of now (anti-replay)
  3. X-App-Token matches our computed HMAC

Set XISSIN_APP_SECRET in your Railway environment variables.
It must match the secret assembled in security_service.dart.

DEFAULT (if env var not set): the same value as in security_service.dart
─────────────────────────────────────────────────────────────────────────────
"""

import os
import hmac
import hashlib
import time
import logging

from fastapi import Request, HTTPException

logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────

# This MUST match the string assembled from character codes in security_service.dart
# Change both sides at the same time if you rotate the key.
_DEFAULT_SECRET = "X1SSIN_SECR3T_2025_ZXYZ"

def _get_secret() -> bytes:
    s = os.environ.get("XISSIN_APP_SECRET", _DEFAULT_SECRET).strip()
    return s.encode("utf-8")

_EXPECTED_APP_ID  = "com.xissin.app"
_MAX_CLOCK_SKEW   = 90    # seconds — reject timestamps older/newer than this
_EXEMPT_PATHS     = {     # endpoints that don't need app signing
    "/",
    "/health",
    "/api/status",
    "/api/announcements",
    "/api/settings/version",
}

# ── Verification function ─────────────────────────────────────────────────────

def verify_app_request(request: Request, user_id: str = "anonymous") -> bool:
    """
    Verify the HMAC app token on a request.
    Returns True if valid, raises HTTPException(401) if invalid.
    Call this at the top of any sensitive endpoint.

    Usage in a router:
        from routers.app_verify import verify_app_request

        @router.post("/bomb")
        def bomb(request: Request, req: BombRequest):
            verify_app_request(request, user_id=req.user_id)
            ...
    """
    # Skip verification for exempt paths
    if request.url.path in _EXEMPT_PATHS:
        return True

    app_id    = request.headers.get("X-App-Id",        "")
    ts_str    = request.headers.get("X-App-Timestamp", "")
    token     = request.headers.get("X-App-Token",     "")

    # ── 1. Package name check ─────────────────────────────────────────────────
    if app_id and app_id != _EXPECTED_APP_ID:
        logger.warning(f"❌ Wrong app ID: {app_id!r} from {_ip(request)}")
        raise HTTPException(status_code=401, detail="Invalid app identity.")

    # ── 2. Timestamp freshness ────────────────────────────────────────────────
    if not ts_str:
        # Missing header — could be a direct API call, log but allow
        # Change this to raise if you want STRICT mode (breaks Postman/curl)
        logger.debug(f"⚠️  Missing X-App-Timestamp from {_ip(request)}")
        return True

    try:
        ts = int(ts_str)
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid timestamp.")

    now = int(time.time())
    if abs(now - ts) > _MAX_CLOCK_SKEW:
        logger.warning(
            f"❌ Stale timestamp: ts={ts} now={now} "
            f"diff={now-ts}s from {_ip(request)}"
        )
        raise HTTPException(
            status_code=401,
            detail="Request expired. Sync your device clock."
        )

    # ── 3. HMAC token verification ────────────────────────────────────────────
    if not token:
        logger.debug(f"⚠️  Missing X-App-Token from {_ip(request)}")
        return True   # lenient — change to raise for STRICT mode

    message  = f"{user_id}:{ts}".encode("utf-8")
    expected = hmac.new(_get_secret(), message, hashlib.sha256).hexdigest()

    if not hmac.compare_digest(expected, token):
        logger.warning(
            f"❌ HMAC mismatch for user={user_id} ts={ts} "
            f"from {_ip(request)}"
        )
        raise HTTPException(status_code=401, detail="Invalid app token.")

    return True


def _ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


# ── FastAPI dependency (for use with Depends) ─────────────────────────────────

async def require_app_token(request: Request) -> bool:
    """
    Use as a FastAPI dependency on routes that need signing:

        @router.post("/bomb", dependencies=[Depends(require_app_token)])
        def bomb(...):
            ...
    """
    # We can't get user_id here without parsing the body, so we just check
    # timestamp freshness and app-id at the dependency level.
    # Full HMAC check happens inside the route after user_id is known.
    app_id = request.headers.get("X-App-Id", "")
    ts_str = request.headers.get("X-App-Timestamp", "")

    if app_id and app_id != _EXPECTED_APP_ID:
        raise HTTPException(status_code=401, detail="Invalid app identity.")

    if ts_str:
        try:
            ts  = int(ts_str)
            now = int(time.time())
            if abs(now - ts) > _MAX_CLOCK_SKEW:
                raise HTTPException(
                    status_code=401,
                    detail="Request expired."
                )
        except (ValueError, HTTPException):
            raise

    return True
