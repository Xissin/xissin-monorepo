"""
routers/keys.py — Key management endpoints
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

# ── Redis sync helpers ────────────────────────────────────────────────────────
# These write to the Telegram bot's xissin:registry (pickle+base64 format)
# so the auto_edit_bot can see app redemptions and edit channel posts.

def _upstash_url():
    return os.environ.get("UPSTASH_REDIS_REST_URL", "").rstrip("/")

def _upstash_token():
    return os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")

def _bot_redis_get(key: str):
    """Read from Upstash in pickle+base64 format (Telegram bot's format)."""
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return None
    try:
        resp = _requests.get(
            f"{url}/get/{key}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=8,
        )
        result = resp.json().get("result")
        if result is None:
            return None
        return pickle.loads(base64.b64decode(result.encode("utf-8")))
    except Exception:
        return None

def _bot_redis_set(key: str, data) -> bool:
    """Write to Upstash in pickle+base64 format (Telegram bot's format)."""
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return False
    try:
        encoded = base64.b64encode(pickle.dumps(data)).decode("utf-8")
        resp = _requests.post(
            f"{url}/set/{key}",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain"},
            data=encoded,
            timeout=8,
        )
        return resp.json().get("result") == "OK"
    except Exception:
        return False

def _sync_redemption_to_bot_registry(key_str: str, key_data: dict):
    """
    After a key is redeemed via the app, mirror the redemption into
    xissin:registry (pickle format) so the auto_edit_bot can see it
    and edit the channel post.
    """
    try:
        registry = _bot_redis_get("xissin:registry") or {}
        entry = registry.get(key_str, {})
        entry.update({
            "redeemed":              True,
            "redeemed_by":           key_data.get("redeemed_by", ""),
            "redeemed_by_username":  key_data.get("redeemed_by_username", ""),
            "redeemed_at":           key_data.get("redeemed_at", ph_now().isoformat()),
            "expires_at":            key_data.get("expires_at", ""),
            "key":                   key_str,
        })
        registry[key_str] = entry
        _bot_redis_set("xissin:registry", registry)
        # Signal the auto_edit_bot to sync immediately
        _fire_sync_trigger()
    except Exception:
        pass   # non-critical — app redemption already saved

def _fire_sync_trigger():
    """Write xissin:sync_now so auto_edit_bot wakes up immediately."""
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return
    try:
        payload = base64.b64encode(
            pickle.dumps(datetime.utcnow().isoformat())
        ).decode("utf-8")
        _requests.post(
            f"{url}/set/xissin:sync_now",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain"},
            data=payload,
            timeout=5,
        )
    except Exception:
        pass

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
    now = ph_now()
    metadata = {
        "key":           key_str,
        "created_at":    now.isoformat(),
        "expires_at":    (now + timedelta(days=req.duration_days)).isoformat(),
        "duration_days": req.duration_days,
        "note":          req.note or "",
        "redeemed":      False,
        "redeemed_by":   None,
        "redeemed_at":   None,
    }
    db.save_key(key_str, metadata)
    db.append_log({"action": "key_generated", "key": key_str, "days": req.duration_days})
    return {"success": True, "key": key_str, "expires_in_days": req.duration_days}


@router.post("/redeem")
@limiter.limit("10/minute")
def redeem_key(request: Request, req: RedeemKeyRequest):
    """User: redeem an activation key."""
    key_data = db.get_key(req.key)

    # ── Check both stores: app store first, then bot registry ────────────────
    if not key_data:
        # Key might have been generated by the Telegram bot — check xissin:registry
        registry = _bot_redis_get("xissin:registry") or {}
        bot_entry = registry.get(req.key)
        if not bot_entry:
            raise HTTPException(status_code=404, detail="Key not found")
        if bot_entry.get("redeemed"):
            raise HTTPException(status_code=400, detail="Key already redeemed")
        # Build a compatible key_data from the bot's entry
        key_data = {
            "key":          req.key,
            "redeemed":     False,
            "redeemed_by":  None,
            "redeemed_at":  None,
            "expires_at":   bot_entry.get("expires_at",
                            (ph_now() + timedelta(days=30)).isoformat()),
            "created_at":   bot_entry.get("created_at", ph_now().isoformat()),
            "duration_days": bot_entry.get("duration_days", 30),
            "note":          bot_entry.get("note", "via-telegram-bot"),
        }
        # Save into app store so future lookups are fast
        db.save_key(req.key, key_data)

    if key_data["redeemed"]:
        raise HTTPException(status_code=400, detail="Key already redeemed")

    expires = datetime.fromisoformat(key_data["expires_at"])
    now = ph_now()
    if now > expires:
        raise HTTPException(status_code=400, detail="Key has expired")

    key_data["redeemed"]             = True
    key_data["redeemed_by"]          = req.user_id
    key_data["redeemed_by_username"] = req.username or ""
    key_data["redeemed_at"]          = now.isoformat()
    db.save_key(req.key, key_data)

    user = db.get_user(req.user_id) or {}
    user.update({
        "user_id":     req.user_id,
        "username":    req.username or user.get("username", ""),
        "active_key":  req.key,
        "key_expires": key_data["expires_at"],
        "joined_at":   user.get("joined_at", now.isoformat()),
        "banned":      False,
    })
    db.save_user(req.user_id, user)
    db.append_log({
        "action":   "key_redeemed",
        "key":      req.key,
        "user_id":  req.user_id,
        "username": req.username,
    })

    # ── Mirror redemption into Telegram bot's registry + trigger auto_edit_bot
    _sync_redemption_to_bot_registry(req.key, key_data)

    return {
        "success":    True,
        "message":    "Key redeemed successfully!",
        "expires_at": key_data["expires_at"],
    }


@router.post("/revoke", dependencies=[Depends(require_admin)])
def revoke_key(req: RevokeKeyRequest):
    key_data = db.get_key(req.key)
    if not key_data:
        raise HTTPException(status_code=404, detail="Key not found")
    db.delete_key(req.key)
    db.append_log({"action": "key_revoked", "key": req.key})
    return {"success": True, "message": "Key revoked"}


@router.post("/delete", dependencies=[Depends(require_admin)])
def delete_unredeemed_key(req: DeleteKeyRequest):
    key_data = db.get_key(req.key)
    if not key_data:
        raise HTTPException(status_code=404, detail="Key not found")
    if key_data.get("redeemed"):
        raise HTTPException(
            status_code=400,
            detail="Cannot delete a redeemed key. Use /revoke if you must remove it."
        )
    db.delete_key(req.key)
    db.append_log({"action": "key_deleted", "key": req.key})
    return {"success": True, "message": f"Key {req.key} deleted successfully"}


@router.get("/list", dependencies=[Depends(require_admin)])
def list_keys():
    keys = db.get_all_keys()
    return {"total": len(keys), "keys": list(keys.values())}


@router.get("/validate/{key_str}")
def validate_key(key_str: str):
    key_data = db.get_key(key_str)

    # Also check bot registry for telegram-bot-generated keys
    if not key_data:
        registry = _bot_redis_get("xissin:registry") or {}
        bot_entry = registry.get(key_str)
        if not bot_entry:
            return {"valid": False, "reason": "Key not found"}
        if bot_entry.get("redeemed"):
            return {"valid": False, "reason": "Key already redeemed"}
        expires_str = bot_entry.get("expires_at", "")
        if expires_str:
            try:
                if ph_now() > datetime.fromisoformat(expires_str):
                    return {"valid": False, "reason": "Key expired"}
            except Exception:
                pass
        return {"valid": True, "expires_at": expires_str}

    if key_data["redeemed"]:
        return {"valid": False, "reason": "Key already redeemed"}
    expires = datetime.fromisoformat(key_data["expires_at"])
    if ph_now() > expires:
        return {"valid": False, "reason": "Key expired"}
    return {"valid": True, "expires_at": key_data["expires_at"]}


@router.get("/status/{user_id}")
def key_status(user_id: str):
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

