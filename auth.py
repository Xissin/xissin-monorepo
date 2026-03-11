"""
auth.py — Simple admin API key guard for Xissin App API
Set ADMIN_API_KEY env var on Railway. Flutter app sends it in X-Admin-Key header.
"""

import os
from fastapi import Header, HTTPException


def require_admin(x_admin_key: str = Header(default="")):
    expected = os.environ.get("ADMIN_API_KEY", "")
    if not expected:
        raise HTTPException(status_code=500, detail="ADMIN_API_KEY is not configured on the server.")
    if x_admin_key != expected:
        raise HTTPException(status_code=403, detail="Invalid admin key")


def get_admin_key() -> str:
    key = os.environ.get("ADMIN_API_KEY", "")
    if not key:
        raise RuntimeError("ADMIN_API_KEY environment variable is not set!")
    return key
