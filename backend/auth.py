"""
auth.py — Request authentication for Xissin App API  v2.0

Two protection layers:
  1. App requests  → Session token (X-Session-Token) — validated via Redis
  2. Admin requests → Secret admin key (X-Admin-Key header)

SESSION TOKEN FLOW:
  - App calls POST /api/auth/session on launch with bootstrap HMAC
  - Backend returns a random 256-bit session token stored in Redis (24h TTL)
  - App stores token in FlutterSecureStorage
  - Every API call sends X-Session-Token + X-App-Id headers
  - This middleware looks token up in Redis — found = authorized

WHY THIS IS SAFER THAN HARDCODED HMAC:
  - No secret in the APK grants permanent API access
  - Bootstrap secret only creates sessions (rate-limited + device-fingerprinted)
  - Sessions expire after 24 hours automatically
  - Compromised session only affects that one device

SECURITY NOTES:
  - ADMIN_SECRET_KEY must be set in Railway env vars — no fallback
  - BOOTSTRAP_SALT must be set in Railway env vars (used by session.py)
  - Backend refuses to start if ADMIN_SECRET_KEY is missing
"""

import hmac
import os
import sys
import logging

from fastapi import Header, HTTPException, Request
from typing import Optional

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
_APP_ID = "com.xissin.app"

_SKIP_PATHS = {
    "/",
    "/health",
    "/api/status",
    "/api/settings/version",
    "/api/announcements",
    "/api/payments/webhook",
    "/api/payments/success",
    "/api/payments/failed",
    "/api/crash-report",
    "/api/auth/session",   # session endpoint uses its own bootstrap auth
}


def _admin_key() -> str:
    """
    Read admin key from Railway env var ONLY.
    NO fallback. NO default value.
    If missing → log fatal + exit. Server must not run without it.
    """
    key = os.environ.get("ADMIN_SECRET_KEY", "").strip()
    if not key:
        logger.critical(
            "FATAL: ADMIN_SECRET_KEY environment variable is not set. "
            "Set it in Railway before deploying. Refusing to start."
        )
        sys.exit(1)
    return key


_ADMIN_KEY_VALUE: str = _admin_key()


# ── Session token validation ──────────────────────────────────────────────────

async def _validate_session_token(token: str) -> bool:
    """
    Looks up the session token in Redis.
    Redis TTL handles expiry — if key is gone, session is expired.
    Returns False if Redis is unreachable (fail closed).
    """
    try:
        import database as db
        value = await db.redis_get(f"sess:{token}")
        return value is not None
    except Exception as e:
        logger.warning(f"Redis session lookup failed (rejecting request): {e}")
        return False  # fail closed — never allow on Redis error


# ── App request verification ──────────────────────────────────────────────────

async def verify_app_request(
    request:         Request,
    x_session_token: Optional[str] = Header(None, alias="X-Session-Token"),
    x_app_id:        Optional[str] = Header(None, alias="X-App-Id"),
):
    """
    FastAPI dependency — verifies all app requests via session token.
    Skips public endpoints in _SKIP_PATHS.

    App must:
      1. Call POST /api/auth/session on launch → receive session_token
      2. Store it in FlutterSecureStorage
      3. Send X-Session-Token + X-App-Id on every request
    """
    path = request.url.path
    if path in _SKIP_PATHS:
        return

    if x_app_id != _APP_ID:
        raise HTTPException(status_code=401, detail="Invalid app ID")

    if not x_session_token or len(x_session_token) < 32:
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid session token. Please restart the app.",
        )

    if not await _validate_session_token(x_session_token):
        logger.warning(
            f"Invalid/expired session: token={x_session_token[:8]}... "
            f"path={path}"
        )
        raise HTTPException(
            status_code=401,
            detail="Session expired. Please restart the app to refresh.",
        )


# ── Admin panel verification ──────────────────────────────────────────────────

async def require_admin(
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key"),
):
    """
    FastAPI dependency — protects all admin-only endpoints.
    Key is loaded from ADMIN_SECRET_KEY Railway env var.
    Server refuses to start if that var is missing.
    """
    if not x_admin_key:
        raise HTTPException(status_code=401, detail="Admin key required")

    if not hmac.compare_digest(_ADMIN_KEY_VALUE.encode(), x_admin_key.encode()):
        logger.warning(f"Failed admin auth: key={x_admin_key[:8]}...")
        raise HTTPException(status_code=403, detail="Invalid admin key")
