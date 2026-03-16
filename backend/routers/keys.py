"""
routers/keys.py — Key management endpoints

NAMESPACE FIX
-------------
All keys generated/redeemed here are tagged  "source": "app"
and mirrored into  app:registry  in Upstash Redis.

This ensures the xissin-monorepo auto_edit_bot (app:registry reader)
and the Xissin-bot auto_edit_bot (tgbot:registry reader) NEVER
interfere with each other — they live in completely separate namespaces.

Redis keys used by this module:
  app:registry      — dict of all app keys  { key_str: metadata }
  app:sync_now      — trigger flag for auto_edit_bot background loop
"""

from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel
from typing import Optional
import random
import string
import os
import base64
import pickle
import requests as _requests
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import database as db
from auth import require_admin
from limiter import limiter

router = APIRouter()
PH_TZ = ZoneInfo("Asia/Manila")

def ph_now():
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Upstash helpers ───────────────────────────────────────────────────────────

def _upstash_url() -> str:
    return os.environ.get("UPSTASH_REDIS_REST_URL", "").rstrip("/")

def _upstash_token() -> str:
    return os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")

def _redis_get(key: str):
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return None
    try:
        resp   = _requests.get(f"{url}/get/{key}",
                               headers={"Authorization": f"Bearer {token}"}, timeout=10)
        result = resp.json().get("result")
        if result is None:
            return None
        return pickle.loads(base64.b64decode(result.encode("utf-8")))
    except Exception:
        return None

def _redis_set(key: str, data) -> bool:
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return False
    try:
        encoded = base64.b64encode(pickle.dumps(data)).decode("utf-8")
        resp    = _requests.post(
            f"{url}/set/{key}",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain"},
            data=encoded,
            timeout=10,
        )
        return resp.json().get("result") == "OK"
    except Exception:
        return False

# ── App registry mirror ───────────────────────────────────────────────────────

APP_REGISTRY_KEY = "app:registry"   # only app keys — read by auto_edit_bot_APP
APP_SYNC_KEY     = "app:sync_now"   # trigger flag — read by auto_edit_bot_APP

def _mirror_to_app_registry(key_str: str, metadata: dict):
    """
    Keep app:registry in Upstash in sync with every key create/update/delete.
    This is the ONLY registry the app auto_edit_bot reads.
    tgbot keys are stored separately under tgbot:registry — zero overlap.
    """
    try:
        registry = _redis_get(APP_REGISTRY_KEY)
        if not isinstance(registry, dict):
            registry = {}
        registry[key_str] = metadata
        _redis_set(APP_REGISTRY_KEY, registry)
    except Exception:
        pass   # non-critical; bot falls back to 30s loop

def _remove_from_app_registry(key_str: str):
    """Remove a key from app:registry (called on revoke/delete)."""
    try:
        registry = _redis_get(APP_REGISTRY_KEY)
        if isinstance(registry, dict) and key_str in registry:
            del registry[key_str]
            _redis_set(APP_REGISTRY_KEY, registry)
    except Exception:
        pass

def _fire_sync_trigger():
    """
    Write app:sync_now so the APP auto_edit_bot background loop
    wakes up immediately and edits the channel post.
    Note: uses app:sync_now — NOT xissin:sync_now — so it only
    triggers the app bot, never the tgbot bot.
    """
    try:
        payload = base64.b64encode(
            pickle.dumps(datetime.utcnow().isoformat())
        ).decode("utf-8")
        _requests.post(
            f"{_upstash_url()}/set/{APP_SYNC_KEY}",
            headers={
                "Authorization": f"Bearer {_upstash_token()}",
                "Content-Type": "text/plain",
            },
            data=payload,
            timeout=5,
        )
    except Exception:
        pass   # non-critical

# ── Models ────────────────────────────────────────────────────────────────────

class GenerateKeyRequest(BaseModel):
    duration_days: int = 30
    note: Optional[str] = None

class RedeemKeyRequest(BaseModel):
    key: str
    user_id: str
    username: Optional[str] = None

class RevokeKeyRequest(BaseModel):
    key: str

class DeleteKeyRequest(BaseModel):
    key: str

# ── Helpers ───────────────────────────────────────────────────────────────────

def _generate_key_string() -> str:
    def seg(n):
        return "".join(random.choices(string.ascii_uppercase + string.digits, k=n))
    return f"XISSIN-{seg(4)}-{seg(4)}-{seg(4)}-{seg(4)}"

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/generate", dependencies=[Depends(require_admin)])
def generate_key(req: GenerateKeyRequest):
    """Admin: generate a new activation key."""
    key_str = _generate_key_string()
    now     = ph_now()
    metadata = {
        "key":           key_str,
        "source":        "app",          # ← NAMESPACE TAG: identifies this as an app key
        "created_at":    now.isoformat(),
        "expires_at":    (now + timedelta(days=req.duration_days)).isoformat(),
        "duration_days": req.duration_days,
        "note":          req.note or "",
        "redeemed":      False,
        "redeemed_by":   None,
        "redeemed_at":   None,
    }
    db.save_key(key_str, metadata)
    _mirror_to_app_registry(key_str, metadata)   # ← keep app:registry in sync
    db.append_log({"action": "key_generated", "key": key_str, "days": req.duration_days})
    return {"success": True, "key": key_str, "expires_in_days": req.duration_days}


@router.post("/redeem")
@limiter.limit("10/minute")
def redeem_key(request: Request, req: RedeemKeyRequest):
    """User: redeem an activation key. Rate limited to 10 attempts per minute per IP."""
    key_data = db.get_key(req.key)
    if not key_data:
        raise HTTPException(status_code=404, detail="Key not found")
    if key_data["redeemed"]:
        raise HTTPException(status_code=400, detail="Key already redeemed")

    expires = datetime.fromisoformat(key_data["expires_at"])
    now     = ph_now()
    if now > expires:
        raise HTTPException(status_code=400, detail="Key has expired")

    key_data["redeemed"]             = True
    key_data["redeemed_by"]          = req.user_id
    key_data["redeemed_by_username"] = req.username or ""
    key_data["redeemed_at"]          = now.isoformat()
    key_data["source"]               = key_data.get("source", "app")  # ← ensure tag present
    db.save_key(req.key, key_data)
    _mirror_to_app_registry(req.key, key_data)   # ← update app:registry with redeemed state

    user = db.get_user(req.user_id) or {}
    user.update({
        "user_id":    req.user_id,
        "username":   req.username or user.get("username", ""),
        "active_key": req.key,
        "key_expires": key_data["expires_at"],
        "joined_at":  user.get("joined_at", now.isoformat()),
        "banned":     False,
    })
    db.save_user(req.user_id, user)
    db.append_log({
        "action":   "key_redeemed",
        "key":      req.key,
        "user_id":  req.user_id,
        "username": req.username,
    })

    # ── Instantly trigger APP auto_edit_bot to update the channel post ───────
    # Uses app:sync_now — will NOT trigger the tgbot bot at all.
    _fire_sync_trigger()

    return {
        "success":    True,
        "message":    "Key redeemed successfully!",
        "expires_at": key_data["expires_at"],
    }


@router.post("/revoke", dependencies=[Depends(require_admin)])
def revoke_key(req: RevokeKeyRequest):
    """Admin: revoke / delete a key."""
    key_data = db.get_key(req.key)
    if not key_data:
        raise HTTPException(status_code=404, detail="Key not found")
    db.delete_key(req.key)
    _remove_from_app_registry(req.key)   # ← keep app:registry clean
    db.append_log({"action": "key_revoked", "key": req.key})
    return {"success": True, "message": "Key revoked"}


@router.post("/delete", dependencies=[Depends(require_admin)])
def delete_unredeemed_key(req: DeleteKeyRequest):
    """Admin: delete an unredeemed key only. Redeemed keys are protected."""
    key_data = db.get_key(req.key)
    if not key_data:
        raise HTTPException(status_code=404, detail="Key not found")
    if key_data.get("redeemed"):
        raise HTTPException(
            status_code=400,
            detail="Cannot delete a redeemed key. Use /revoke if you must remove it."
        )
    db.delete_key(req.key)
    _remove_from_app_registry(req.key)   # ← keep app:registry clean
    db.append_log({"action": "key_deleted", "key": req.key})
    return {"success": True, "message": f"Key {req.key} deleted successfully"}


@router.get("/list", dependencies=[Depends(require_admin)])
def list_keys():
    """Admin: list all keys."""
    keys = db.get_all_keys()
    return {
        "total": len(keys),
        "keys":  list(keys.values()),
    }


@router.get("/validate/{key_str}")
def validate_key(key_str: str):
    """Check if a key is valid and not yet expired."""
    key_data = db.get_key(key_str)
    if not key_data:
        return {"valid": False, "reason": "Key not found"}
    if key_data["redeemed"]:
        return {"valid": False, "reason": "Key already redeemed"}
    expires = datetime.fromisoformat(key_data["expires_at"])
    if ph_now() > expires:
        return {"valid": False, "reason": "Key expired"}
    return {"valid": True, "expires_at": key_data["expires_at"]}


@router.get("/status/{user_id}")
def key_status(user_id: str):
    """Check if a user has an active (non-expired) key."""
    user = db.get_user(user_id)
    if not user or not user.get("active_key"):
        return {"active": False}
    expires = datetime.fromisoformat(user["key_expires"])
    if ph_now() > expires:
        return {"active": False, "reason": "Key expired"}
    return {
        "active":     True,
        "key":        user["active_key"],
        "expires_at": user["key_expires"],
    }
