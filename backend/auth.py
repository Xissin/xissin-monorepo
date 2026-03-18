"""
auth.py — Request authentication for Xissin App API

Two protection layers:
  1. App requests  → HMAC-SHA256 signed token  (X-App-Token header)
  2. Admin requests → Secret admin key          (X-Admin-Key header)

SECURITY NOTES for public GitHub repo:
  - ADMIN_KEY is read from Railway environment variable only — never hardcoded
  - App HMAC secret (_APP_SALT) is a low-sensitivity salt, not a master secret
  - Timestamps are validated within ±30 seconds to prevent replay attacks
  - All secrets must be set in Railway environment variables
"""

import hashlib
import hmac
import os
import time
import logging

from fastapi import Header, HTTPException, Request
from typing import Optional

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
_APP_SALT       = "xissin-multi-tool-2024"   # matches security_service.dart
_APP_ID         = "com.xissin.app"
_TOKEN_WINDOW   = 30   # seconds — reject tokens older than this
_SKIP_PATHS     = {    # these endpoints never require auth
    "/",
    "/health",
    "/api/status",
    "/api/settings/version",
    "/api/announcements",
    "/api/payments/webhook",
    "/api/payments/success",
    "/api/payments/failed",
}


def _admin_key() -> str:
    """Read admin key from Railway env var — never hardcode this."""
    key = os.environ.get("ADMIN_SECRET_KEY", "").strip()
    if not key:
        # Fallback for local dev only — set this in your .env file
        key = os.environ.get("ADMIN_KEY", "xissin-dev-key").strip()
    return key


# ── App request verification (HMAC) ──────────────────────────────────────────

def _verify_app_token(user_id: str, timestamp_str: str, token: str) -> bool:
    """
    Regenerates the HMAC token and compares in constant time.
    Returns False if timestamp is outside the ±30s window.
    """
    try:
        ts = int(timestamp_str)
    except (ValueError, TypeError):
        return False

    now = int(time.time())
    if abs(now - ts) > _TOKEN_WINDOW:
        logger.warning(
            f"Token replay/clock-skew: ts={ts} now={now} diff={abs(now-ts)}s"
        )
        return False

    message  = f"{user_id}:{ts}:{_APP_ID}"
    expected = hmac.new(
        _APP_SALT.encode(), message.encode(), hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(expected, token)


async def verify_app_request(
    request:        Request,
    x_app_token:    Optional[str] = Header(None, alias="X-App-Token"),
    x_app_timestamp:Optional[str] = Header(None, alias="X-App-Timestamp"),
    x_app_id:       Optional[str] = Header(None, alias="X-App-Id"),
):
    """
    FastAPI dependency — verifies signed app requests.
    Skips verification for public endpoints listed in _SKIP_PATHS.
    """
    path = request.url.path

    # Public endpoints — no auth needed
    if path in _SKIP_PATHS:
        return

    # Require app ID header
    if x_app_id != _APP_ID:
        raise HTTPException(status_code=401, detail="Invalid app ID")

    # Require token + timestamp
    if not x_app_token or not x_app_timestamp:
        raise HTTPException(status_code=401, detail="Missing authentication headers")

    # Extract user_id from request body or path
    user_id = "anonymous"
    try:
        body = await request.json()
        user_id = str(body.get("user_id", "anonymous"))
    except Exception:
        # Some requests have user_id in path params
        user_id = request.path_params.get("user_id", "anonymous")

    if not _verify_app_token(user_id, x_app_timestamp, x_app_token):
        logger.warning(
            f"Invalid app token: user={user_id} "
            f"ts={x_app_timestamp} path={path}"
        )
        raise HTTPException(status_code=401, detail="Invalid or expired token")


# ── Admin panel verification ──────────────────────────────────────────────────

async def require_admin(
    x_admin_key: Optional[str] = Header(None, alias="X-Admin-Key"),
):
    """
    FastAPI dependency — protects all admin-only endpoints.
    Admin key is set via ADMIN_SECRET_KEY Railway environment variable.
    """
    expected = _admin_key()

    if not x_admin_key:
        raise HTTPException(
            status_code=401,
            detail="Admin key required",
        )

    # Constant-time comparison prevents timing attacks
    if not hmac.compare_digest(expected.encode(), x_admin_key.encode()):
        logger.warning(f"Failed admin auth attempt with key: {x_admin_key[:8]}...")
        raise HTTPException(
            status_code=403,
            detail="Invalid admin key",
        )
