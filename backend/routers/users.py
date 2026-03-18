"""
routers/users.py — User management endpoints

Security:
  - /register now requires valid X-App-Token (same as all other app routes)
  - All admin routes still require X-Admin-Key
  - Public routes (/check, /stats) are read-only and safe
"""

from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel
from typing import Optional

import database as db
from auth import require_admin, verify_app_request

router = APIRouter()


class BanRequest(BaseModel):
    user_id: str
    reason: Optional[str] = None


class RegisterRequest(BaseModel):
    user_id:        str
    username:       Optional[str]  = None
    device_info:    Optional[str]  = None   # legacy plain-text field (kept for compat)
    device_details: Optional[dict] = None   # rich structured device info from app


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/register", dependencies=[Depends(verify_app_request)])
def register_user(req: RegisterRequest):
    """
    Called every time the user opens the app.
    - Creates the user record on first launch.
    - Updates device info + last_seen on every subsequent launch.
    - Requires valid HMAC app token (X-App-Token header).
    """
    from datetime import datetime
    from zoneinfo import ZoneInfo
    now = datetime.now(ZoneInfo("Asia/Manila")).replace(tzinfo=None).isoformat()

    existing = db.get_user(req.user_id)

    if not existing:
        db.save_user(req.user_id, {
            "user_id":        req.user_id,
            "username":       req.username or "",
            "device_info":    req.device_info or "android",
            "device_details": req.device_details or {},
            "joined_at":      now,
            "last_seen":      now,
            "active_key":     None,
            "key_expires":    None,
            "banned":         False,
        })
        db.append_log({
            "action":   "user_registered",
            "user_id":  req.user_id,
            "username": req.username,
        })
    else:
        existing["last_seen"] = now
        if req.device_details:
            existing["device_details"] = req.device_details
        if req.device_info:
            existing["device_info"] = req.device_info
        if req.username:
            existing["username"] = req.username
        db.save_user(req.user_id, existing)

    if req.device_details:
        db.save_device_info(req.user_id, {
            **req.device_details,
            "user_id":   req.user_id,
            "last_seen": now,
        })

    banned = db.is_banned(req.user_id)
    return {
        "registered": True,
        "banned":     banned,
        "user":       db.get_user(req.user_id),
    }


@router.get("/list", dependencies=[Depends(require_admin)])
def list_users():
    """Admin: list all users."""
    users = db.get_all_users()
    return {
        "total": len(users),
        "users": list(users.values()),
    }


@router.get("/logs/recent", dependencies=[Depends(require_admin)])
def get_logs(limit: int = 50):
    """Admin: get recent action logs."""
    return {"logs": db.get_logs(limit=limit)}


@router.get("/devices", dependencies=[Depends(require_admin)])
def get_all_devices():
    """Admin: get device info for all registered users."""
    devices = db.get_all_device_info()
    return {
        "total":   len(devices),
        "devices": list(devices.values()),
    }


@router.get("/devices/{user_id}", dependencies=[Depends(require_admin)])
def get_user_device(user_id: str):
    """Admin: get device info for a specific user."""
    info = db.get_device_info(user_id)
    if not info:
        raise HTTPException(status_code=404, detail="No device info for this user.")
    return info


@router.get("/stats/{user_id}")
def get_user_stats(user_id: str):
    """App: get SMS usage stats for a user."""
    total   = db.get_sms_stat(user_id)
    history = db.get_sms_history(user_id)
    return {
        "user_id":   user_id,
        "total_sms": total,
        "history":   history,
    }


@router.get("/{user_id}", dependencies=[Depends(require_admin)])
def get_user(user_id: str):
    """Admin: get a single user by ID."""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.post("/ban", dependencies=[Depends(require_admin)])
def ban_user(req: BanRequest):
    """Admin: ban a user."""
    db.ban_user(req.user_id)
    user = db.get_user(req.user_id)
    if user:
        user["banned"]     = True
        user["ban_reason"] = req.reason or ""
        db.save_user(req.user_id, user)
    db.append_log({"action": "user_banned", "user_id": req.user_id, "reason": req.reason})
    return {"success": True, "message": f"User {req.user_id} banned"}


@router.post("/unban", dependencies=[Depends(require_admin)])
def unban_user(req: BanRequest):
    """Admin: unban a user."""
    db.unban_user(req.user_id)
    user = db.get_user(req.user_id)
    if user:
        user["banned"] = False
        user.pop("ban_reason", None)
        db.save_user(req.user_id, user)
    db.append_log({"action": "user_unbanned", "user_id": req.user_id})
    return {"success": True, "message": f"User {req.user_id} unbanned"}


@router.get("/check/{user_id}")
def check_user(user_id: str):
    """App: check if user is banned and has active key."""
    banned = db.is_banned(user_id)
    user   = db.get_user(user_id)
    return {
        "banned":     banned,
        "registered": user is not None,
        "has_key":    bool(user and user.get("active_key")) if not banned else False,
    }
