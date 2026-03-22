"""
routers/payments.py — Premium Key System
Replaces PayMongo with a manual key-based system.

Flow:
  1. Admin generates keys in Streamlit admin panel
  2. User contacts @QuitNat on Telegram
  3. User pays via GCash
  4. Developer sends the user a key (e.g. XISSIN-A3B2-C9D1)
  5. User enters key in app → premium granted instantly

Key format: XISSIN-XXXX-XXXX  (16 chars total)
"""

import json
import logging
import random
import re
import string

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator
from typing import Optional

import database as db
from auth import require_admin, verify_app_request

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Config ────────────────────────────────────────────────────────────────────
_USER_ID_RE = re.compile(r'^[a-zA-Z0-9_\-\.]{1,64}$')
_KEY_RE     = re.compile(r'^XISSIN-[A-Z0-9]{4}-[A-Z0-9]{4}$')
_TELEGRAM   = "@QuitNat"


# ── Redis helpers ─────────────────────────────────────────────────────────────

def _rk(key_str: str) -> str:
    """Redis key for a specific premium key."""
    return f"xissin:key:{key_str.upper()}"

def _get_key_data(key_str: str) -> Optional[dict]:
    try:
        raw = db.redis_get(_rk(key_str))
        return json.loads(raw) if raw else None
    except Exception:
        return None

def _save_key_data(key_str: str, data: dict):
    try:
        db.redis_set(_rk(key_str), json.dumps(data))
    except Exception as e:
        logger.error(f"Failed to save key data: {e}")

def _get_key_index() -> list:
    try:
        raw = db.redis_get("xissin:keys:index")
        return json.loads(raw) if raw else []
    except Exception:
        return []

def _save_key_index(keys: list):
    try:
        db.redis_set("xissin:keys:index", json.dumps(keys))
    except Exception as e:
        logger.error(f"Failed to save key index: {e}")


# ── Key generation ────────────────────────────────────────────────────────────

def _generate_key() -> str:
    chars  = string.ascii_uppercase + string.digits
    part1  = ''.join(random.choices(chars, k=4))
    part2  = ''.join(random.choices(chars, k=4))
    return f"XISSIN-{part1}-{part2}"

def _validate_user_id(user_id: str) -> str:
    uid = str(user_id).strip()
    if not _USER_ID_RE.match(uid):
        raise HTTPException(status_code=400, detail="Invalid user_id format.")
    return uid


# ── Request models ────────────────────────────────────────────────────────────

class KeyRedeemRequest(BaseModel):
    user_id: str
    key: str

    @field_validator("user_id")
    @classmethod
    def validate_uid(cls, v):
        v = str(v).strip()
        if not _USER_ID_RE.match(v):
            raise ValueError("Invalid user_id")
        return v

    @field_validator("key")
    @classmethod
    def validate_key(cls, v):
        v = str(v).strip().upper()
        if not _KEY_RE.match(v):
            raise ValueError("Invalid key format. Expected: XISSIN-XXXX-XXXX")
        return v


class GenerateKeysRequest(BaseModel):
    count: int = 1
    note: Optional[str] = None

    @field_validator("count")
    @classmethod
    def validate_count(cls, v):
        if not 1 <= v <= 50:
            raise ValueError("Count must be between 1 and 50")
        return v


# ── 0. Product info (app dialog) ──────────────────────────────────────────────

@router.get("/remove-ads-info")
def get_remove_ads_info():
    """Returns info shown in the premium dialog in the Flutter app."""
    return {
        "telegram":    _TELEGRAM,
        "telegram_url": "https://t.me/QuitNat",
        "label":       "Get Premium — Contact @QuitNat on Telegram",
        "description": "Chat with the developer, pay via GCash, and get your key.",
        "benefits": [
            "No ads forever — banner & interstitial gone",
            "SMS Bomber — 50 batches, no cooldown",
            "NGL Bomber — up to 100 attacks, no cooldown",
            "URL & Dup Remover — unlimited file size",
            "IP Tracker & Username Tracker — no limits",
            "Live progress bars on all tools",
        ],
    }


# ── 1. Check premium status ───────────────────────────────────────────────────

@router.get("/premium/{user_id}")
def get_premium_status(user_id: str):
    uid     = _validate_user_id(user_id)
    premium = db.is_premium(uid)
    record  = db.get_premium_record(uid) if premium else None
    return {
        "premium":    premium,
        "paid_at":    record.get("paid_at")    if record else None,
        "payment_id": record.get("payment_id") if record else None,
    }


# ── 2. Validate key (read-only, no auth) ─────────────────────────────────────

@router.get("/keys/validate/{key_str}")
def validate_key(key_str: str):
    """Check if a key is valid and unused without redeeming it."""
    key_str = key_str.strip().upper()
    if not _KEY_RE.match(key_str):
        return {"valid": False, "reason": "Invalid key format."}
    data = _get_key_data(key_str)
    if not data:
        return {"valid": False, "reason": "Key not found."}
    if data.get("used"):
        return {"valid": False, "reason": "Key has already been used."}
    return {"valid": True}


# ── 3. Redeem key ─────────────────────────────────────────────────────────────

@router.post("/keys/redeem", dependencies=[Depends(verify_app_request)])
def redeem_key(req: KeyRedeemRequest):
    """
    Redeem a premium key for a user.
    - Key must exist and be unused
    - User must not already be premium
    - Marks key as used and grants premium instantly
    """
    user_id = req.user_id
    key_str = req.key.upper()

    # Fast path: already premium
    if db.is_premium(user_id):
        return {
            "success":         True,
            "already_premium": True,
            "message":         "You are already premium! Enjoy Xissin.",
        }

    # Check key exists
    data = _get_key_data(key_str)
    if not data:
        raise HTTPException(status_code=404,
                            detail="Invalid key. Please check and try again.")

    # Check key unused
    if data.get("used"):
        raise HTTPException(status_code=409,
                            detail="This key has already been used.")

    # Mark key as used
    now             = db.ph_now().isoformat()
    data["used"]    = True
    data["used_by"] = user_id
    data["used_at"] = now
    _save_key_data(key_str, data)

    # Grant premium (price = 0 since it's key-based)
    db.set_premium(user_id, key_str, 0)

    # Log the redemption
    db.append_log({
        "action":  "key_redeemed",
        "user_id": user_id,
        "key":     key_str,
    })

    logger.info(f"✅ Key redeemed: {key_str} by user={user_id[:12]}...")
    return {
        "success": True,
        "premium": True,
        "message": "Key redeemed! You are now premium. Enjoy Xissin!",
    }


# ── Admin: Key management ──────────────────────────────────────────────────────

@router.get("/keys/admin/list", dependencies=[Depends(require_admin)])
def admin_list_keys():
    """List all generated keys with their status."""
    index = _get_key_index()
    keys  = []
    for k in index:
        data = _get_key_data(k)
        if data:
            keys.append(data)
    # Sort: unused first, then by created_at
    keys.sort(key=lambda x: (x.get("used", False), x.get("created_at", "")))
    total_used      = sum(1 for k in keys if k.get("used"))
    total_available = sum(1 for k in keys if not k.get("used"))
    return {
        "keys":            keys,
        "total":           len(keys),
        "total_used":      total_used,
        "total_available": total_available,
    }


@router.post("/keys/admin/generate", dependencies=[Depends(require_admin)])
def admin_generate_keys(req: GenerateKeysRequest):
    """Generate N new premium keys."""
    index    = _get_key_index()
    existing = set(index)
    new_keys = []
    now      = db.ph_now().isoformat()

    attempts = 0
    while len(new_keys) < req.count and attempts < req.count * 20:
        attempts += 1
        k = _generate_key()
        if k in existing:
            continue
        existing.add(k)
        new_keys.append(k)
        _save_key_data(k, {
            "key":        k,
            "used":       False,
            "used_by":    None,
            "used_at":    None,
            "created_at": now,
            "note":       req.note or "",
        })

    # Update index with all keys
    _save_key_index(list(existing))

    logger.info(f"🔑 Generated {len(new_keys)} premium key(s)")
    return {"generated": new_keys, "count": len(new_keys)}


@router.delete("/keys/admin/revoke/{key_str}", dependencies=[Depends(require_admin)])
def admin_revoke_key(key_str: str):
    """
    Revoke and delete a key.
    If the key was already used, also revokes the user's premium.
    """
    key_str = key_str.strip().upper()
    data    = _get_key_data(key_str)
    if not data:
        raise HTTPException(status_code=404, detail="Key not found.")

    # If used → revoke the user's premium too
    if data.get("used") and data.get("used_by"):
        db.revoke_premium(data["used_by"])
        logger.info(f"🗑️ Premium revoked for user={data['used_by']} (key revoked)")

    # Delete key data from Redis
    try:
        db.redis_delete(_rk(key_str))
    except Exception:
        pass

    # Remove from index
    index = [k for k in _get_key_index() if k != key_str]
    _save_key_index(index)

    logger.info(f"🗑️ Key revoked: {key_str}")
    return {"success": True, "key": key_str}


# ── Admin: Premium users (backward compat with existing admin panel) ───────────

@router.get("/admin/all", dependencies=[Depends(require_admin)])
def admin_get_all_payments():
    """Returns key redemption records (replaces old PayMongo records)."""
    index   = _get_key_index()
    records = []
    for k in index:
        data = _get_key_data(k)
        if data and data.get("used"):
            records.append({
                "payment_intent_id": data["key"],
                "user_id":           data.get("used_by", ""),
                "amount":            0,
                "type":              "premium_key",
                "status":            "paid",
                "created_at":        data.get("created_at", ""),
                "paid_at":           data.get("used_at", ""),
            })
    return {"payments": records}


@router.get("/admin/premium", dependencies=[Depends(require_admin)])
def admin_get_premium_users():
    return {"premium_users": db.get_all_premium()}


@router.post("/admin/grant/{user_id}", dependencies=[Depends(require_admin)])
def admin_grant_premium(user_id: str):
    """Manually grant premium to a user (for verified GCash payments)."""
    uid = _validate_user_id(user_id)
    db.set_premium(uid, "manual_admin", 0)
    logger.info(f"⭐ Premium manually granted to user={uid}")
    return {"success": True, "user_id": uid}


@router.delete("/admin/revoke/{user_id}", dependencies=[Depends(require_admin)])
def admin_revoke_premium(user_id: str):
    """Revoke premium from a user."""
    uid = _validate_user_id(user_id)
    db.revoke_premium(uid)
    logger.info(f"🗑️ Premium revoked from user={uid}")
    return {"success": True, "user_id": uid}
