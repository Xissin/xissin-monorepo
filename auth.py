"""
auth.py — Simple admin API key guard for Xissin App API
Set ADMIN_API_KEY env var on Railway. Flutter app sends it in X-Admin-Key header.
"""

import os
from fastapi import Header, HTTPException

# Default fallback — CHANGE THIS in Railway env vars!
_DEFAULT_ADMIN_KEY = "xissin-admin-secret-2025"

def require_admin(x_admin_key: str = Header(default="")):
    expected = os.environ.get("ADMIN_API_KEY", _DEFAULT_ADMIN_KEY)
    if x_admin_key != expected:
        raise HTTPException(status_code=403, detail="Invalid admin key")

def get_admin_key() -> str:
    return os.environ.get("ADMIN_API_KEY", _DEFAULT_ADMIN_KEY)
