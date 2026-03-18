"""
routers/payments.py — Remove Ads payment via PayMongo QRPh
Hardened for multi-user production use.

Security & reliability features:
  ✅ Duplicate payment protection  — reuses active intent if user taps button twice
  ✅ Rate limiting                 — max 3 payment attempts per user per hour
  ✅ Input validation              — rejects invalid/malicious user_id values
  ✅ Ownership check on /status   — user can only poll their own payment intent
  ✅ Webhook HMAC verification    — FAILS CLOSED: rejects if secret or sig missing
  ✅ Idempotent premium granting  — safe to call set_premium multiple times
  ✅ Auto-cleanup on expiry/fail  — pending intent keys cleared automatically
"""

import base64
import hashlib
import hmac
import logging
import os
import re
import httpx

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, field_validator
from typing import Optional

import database as db
from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Config ────────────────────────────────────────────────────────────────────
PAYMONGO_BASE           = "https://api.paymongo.com/v1"
_DEFAULT_PRICE_CENTAVOS = 9900   # ₱99.00
BACKEND_URL             = "https://xissin-app-backend-production.up.railway.app"

_MAX_ATTEMPTS_PER_HOUR = 3
_USER_ID_RE = re.compile(r'^[a-zA-Z0-9_\-\.]{1,64}$')


# ── Validation ────────────────────────────────────────────────────────────────

def _validate_user_id(user_id: str) -> str:
    uid = str(user_id).strip()
    if not _USER_ID_RE.match(uid):
        raise HTTPException(status_code=400, detail="Invalid user_id format.")
    return uid


# ── PayMongo config ───────────────────────────────────────────────────────────

def _get_remove_ads_price() -> int:
    try:
        s = db.get_server_settings()
        return int(s.get("remove_ads_price") or _DEFAULT_PRICE_CENTAVOS)
    except Exception:
        return _DEFAULT_PRICE_CENTAVOS


def _secret_key() -> str:
    k = os.environ.get("PAYMONGO_SECRET_KEY", "").strip()
    if not k:
        raise RuntimeError("PAYMONGO_SECRET_KEY not set.")
    return k


def _auth_header() -> str:
    encoded = base64.b64encode(f"{_secret_key()}:".encode()).decode()
    return f"Basic {encoded}"


def _webhook_secret() -> str:
    """
    Returns the webhook secret, or raises if not configured.
    We do NOT allow empty webhook secrets in production.
    """
    secret = os.environ.get("PAYMONGO_WEBHOOK_SECRET", "").strip()
    return secret


# ── PayMongo HTTP helpers ─────────────────────────────────────────────────────

async def _paymongo_post(endpoint: str, payload: dict) -> dict:
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            f"{PAYMONGO_BASE}{endpoint}",
            headers={
                "Authorization": _auth_header(),
                "Content-Type":  "application/json",
            },
            json=payload,
        )
    if resp.status_code not in (200, 201):
        logger.error(f"PayMongo {endpoint} error {resp.status_code}: {resp.text}")
        try:
            errors = resp.json().get("errors", [{}])
            detail = errors[0].get("detail", "Payment provider error")
        except Exception:
            detail = "Payment provider error"
        raise HTTPException(status_code=502, detail=detail)
    return resp.json()


async def _paymongo_get(endpoint: str) -> dict:
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            f"{PAYMONGO_BASE}{endpoint}",
            headers={"Authorization": _auth_header()},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="Payment provider error")
    return resp.json()


# ── Redis key helpers ─────────────────────────────────────────────────────────

def _rate_limit_key(user_id: str) -> str:
    return f"xissin:pay:rl:{user_id}"

def _pending_intent_key(user_id: str) -> str:
    return f"xissin:pay:pending:{user_id}"


def _check_and_increment_rate_limit(user_id: str):
    try:
        key   = _rate_limit_key(user_id)
        count = db.redis_get(key)
        count = int(count) if count else 0
        if count >= _MAX_ATTEMPTS_PER_HOUR:
            raise HTTPException(
                status_code=429,
                detail="Too many payment attempts. Please wait before trying again."
            )
        db.redis_incr(key, ttl_seconds=3600)
    except HTTPException:
        raise
    except Exception:
        pass


def _save_pending_intent(user_id: str, intent_id: str):
    try:
        db.redis_set(_pending_intent_key(user_id), intent_id, ttl_seconds=1800)
    except Exception:
        pass


def _get_pending_intent(user_id: str) -> Optional[str]:
    try:
        return db.redis_get(_pending_intent_key(user_id))
    except Exception:
        return None


def _clear_pending_intent(user_id: str):
    try:
        db.redis_delete(_pending_intent_key(user_id))
    except Exception:
        pass


# ── Request models ────────────────────────────────────────────────────────────

class CreatePaymentRequest(BaseModel):
    user_id: str

    @field_validator("user_id")
    @classmethod
    def validate_uid(cls, v):
        v = str(v).strip()
        if not _USER_ID_RE.match(v):
            raise ValueError("Invalid user_id")
        return v


class PaymentStatusRequest(BaseModel):
    payment_intent_id: str
    user_id: str

    @field_validator("user_id")
    @classmethod
    def validate_uid(cls, v):
        v = str(v).strip()
        if not _USER_ID_RE.match(v):
            raise ValueError("Invalid user_id")
        return v

    @field_validator("payment_intent_id")
    @classmethod
    def validate_intent_id(cls, v):
        v = str(v).strip()
        if not v.startswith("pi_") or len(v) > 100:
            raise ValueError("Invalid payment_intent_id")
        return v


# ── 0. Public info ────────────────────────────────────────────────────────────

@router.get("/remove-ads-info")
def get_remove_ads_info():
    """Flutter app fetches this on dialog open to show price & benefits."""
    s     = db.get_server_settings()
    price = int(s.get("remove_ads_price") or _DEFAULT_PRICE_CENTAVOS)
    return {
        "price":       price,
        "price_php":   price / 100,
        "label":       s.get("remove_ads_label")       or f"Remove Ads — ₱{price // 100} Lifetime",
        "subtitle":    s.get("remove_ads_subtitle")    or "Pay once via GCash · No ads forever",
        "description": s.get("remove_ads_description") or "Enjoy Xissin completely ad-free — forever.",
        "benefits":    s.get("remove_ads_benefits")    or [
            "No more banner ads",
            "No more interstitial ads",
            "One-time payment — lifetime",
            "Pay via GCash / QRPh QR code",
        ],
    }


# ── 1. Create Payment ─────────────────────────────────────────────────────────

@router.post("/create")
async def create_payment(req: CreatePaymentRequest):
    """
    Creates a QRPh Payment Intent.
    Guards:
      1. Already premium → return immediately
      2. Active pending intent exists → reuse QR (no double charge)
      3. Rate limit → 3 attempts per hour
    """
    user_id = req.user_id

    # Fast path — already premium
    if db.is_premium(user_id):
        return {"already_premium": True}

    # Duplicate protection — reuse active QR
    existing_intent_id = _get_pending_intent(user_id)
    if existing_intent_id:
        try:
            data       = await _paymongo_get(f"/payment_intents/{existing_intent_id}")
            attributes = data["data"]["attributes"]
            status     = attributes.get("status", "")
            if status in ("awaiting_payment_method", "processing"):
                next_action = attributes.get("next_action") or {}
                code_block  = next_action.get("code") or {}
                qr_image    = code_block.get("image_url", "")
                price       = _get_remove_ads_price()
                logger.info(f"♻️ Reusing intent {existing_intent_id} for user={user_id}")
                return {
                    "payment_intent_id": existing_intent_id,
                    "qr_image_url":      qr_image,
                    "amount":            price,
                    "amount_php":        price / 100,
                    "reused":            True,
                }
        except Exception:
            _clear_pending_intent(user_id)

    # Rate limit check
    _check_and_increment_rate_limit(user_id)

    price = _get_remove_ads_price()

    # Step 1: Create Payment Intent
    intent_data = await _paymongo_post(
        "/payment_intents",
        {
            "data": {
                "attributes": {
                    "amount":                 price,
                    "currency":               "PHP",
                    "payment_method_allowed": ["qrph"],
                    "capture_type":           "automatic",
                    "metadata":               {"user_id": user_id},
                    "description":            "Xissin — Remove Ads (Lifetime)",
                }
            }
        },
    )
    intent_id  = intent_data["data"]["id"]
    client_key = intent_data["data"]["attributes"]["client_key"]

    # Step 2: Create Payment Method (QRPh)
    pm_data = await _paymongo_post(
        "/payment_methods",
        {
            "data": {
                "attributes": {
                    "type":     "qrph",
                    "metadata": {"user_id": user_id},
                }
            }
        },
    )
    pm_id = pm_data["data"]["id"]

    # Step 3: Attach → get QR image
    attach_data = await _paymongo_post(
        f"/payment_intents/{intent_id}/attach",
        {
            "data": {
                "attributes": {
                    "payment_method": pm_id,
                    "client_key":     client_key,
                    "return_url":     f"{BACKEND_URL}/api/payments/success",
                }
            }
        }
    )

    next_action = attach_data["data"]["attributes"].get("next_action") or {}
    code_block  = next_action.get("code") or {}
    qr_image    = code_block.get("image_url", "")

    _save_pending_intent(user_id, intent_id)

    db.save_payment({
        "payment_intent_id": intent_id,
        "payment_method_id": pm_id,
        "user_id":           user_id,
        "amount":            price,
        "status":            "pending",
        "type":              "qrph",
        "product":           "remove_ads",
        "created_at":        db.ph_now().isoformat(),
    })

    logger.info(f"💳 QRPh intent created: {intent_id} for user={user_id}")

    return {
        "payment_intent_id": intent_id,
        "qr_image_url":      qr_image,
        "amount":            price,
        "amount_php":        price / 100,
    }


# ── 2. Poll status ────────────────────────────────────────────────────────────

@router.post("/status")
async def check_payment_status(req: PaymentStatusRequest):
    """
    Flutter polls every 5s while QR is shown.
    Security: verifies the intent belongs to the requesting user.
    """
    user_id = req.user_id

    if db.is_premium(user_id):
        _clear_pending_intent(user_id)
        return {"paid": True, "premium": True}

    try:
        data       = await _paymongo_get(f"/payment_intents/{req.payment_intent_id}")
        attributes = data["data"]["attributes"]
        status     = attributes.get("status", "")

        metadata       = attributes.get("metadata") or {}
        intent_user_id = str(metadata.get("user_id", ""))
        if intent_user_id and intent_user_id != user_id:
            logger.warning(
                f"⚠️ SECURITY: user={user_id} tried to poll "
                f"intent owned by user={intent_user_id}"
            )
            raise HTTPException(status_code=403, detail="Forbidden")

        if status == "succeeded":
            price = _get_remove_ads_price()
            db.set_premium(user_id, req.payment_intent_id, price)
            db.save_payment({
                "payment_intent_id": req.payment_intent_id,
                "user_id":           user_id,
                "status":            "paid",
                "paid_at":           db.ph_now().isoformat(),
            })
            _clear_pending_intent(user_id)
            logger.info(f"✅ Confirmed via poll: user={user_id}")
            return {"paid": True, "premium": True}

        if status == "awaiting_payment_method":
            _clear_pending_intent(user_id)
            return {
                "paid":          False,
                "premium":       False,
                "expired":       True,
                "intent_status": status,
            }

        return {"paid": False, "premium": False, "intent_status": status}

    except HTTPException:
        raise
    except Exception:
        return {"paid": False, "premium": False}


# ── 3. Webhook ────────────────────────────────────────────────────────────────

@router.post("/webhook")
async def payment_webhook(
    request: Request,
    paymongo_signature: Optional[str] = Header(None, alias="paymongo-signature"),
):
    """
    PayMongo calls this when payment.paid / payment.failed / qrph.expired fires.

    SECURITY — FAILS CLOSED:
      - If PAYMONGO_WEBHOOK_SECRET is not set → reject all webhook calls (500 config error)
      - If paymongo-signature header is missing → reject (401)
      - If HMAC signature does not match → reject (400)
      - We never grant premium if we cannot verify the request origin.
    """
    body = await request.body()

    wh_secret = _webhook_secret()

    # Hard requirement: webhook secret must be configured
    if not wh_secret:
        logger.error(
            "❌ PAYMONGO_WEBHOOK_SECRET is not set. "
            "All webhook calls are being rejected. Set this env var in Railway."
        )
        raise HTTPException(
            status_code=500,
            detail="Webhook not configured on server. Contact admin."
        )

    # Hard requirement: signature header must be present
    if not paymongo_signature:
        logger.warning("⚠️ Webhook received without paymongo-signature header — rejected.")
        raise HTTPException(status_code=401, detail="Missing webhook signature")

    # Verify HMAC signature
    try:
        parts    = dict(p.split("=", 1) for p in paymongo_signature.split(","))
        ts       = parts.get("t", "")
        test_sig = parts.get("te", "") or parts.get("li", "")
        to_sign  = f"{ts}.{body.decode()}"
        expected = hmac.new(
            wh_secret.encode(), to_sign.encode(), hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(expected, test_sig):
            logger.warning("⚠️ Webhook signature mismatch — possible spoofed request!")
            raise HTTPException(status_code=400, detail="Invalid signature")
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"⚠️ Webhook sig parse error — rejecting: {e}")
        raise HTTPException(status_code=400, detail="Malformed signature header")

    try:
        event = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    event_type  = event.get("data", {}).get("attributes", {}).get("type", "")
    resource    = event.get("data", {}).get("attributes", {}).get("data", {})
    attributes  = resource.get("attributes", {})
    metadata    = attributes.get("metadata") or {}
    user_id     = str(metadata.get("user_id", ""))
    resource_id = resource.get("id", "")
    intent_id   = attributes.get("payment_intent_id", resource_id)

    logger.info(f"📬 Webhook: type={event_type} user={user_id} id={resource_id}")

    if event_type == "payment.paid" and user_id:
        if not _USER_ID_RE.match(user_id):
            logger.warning(f"⚠️ Webhook has invalid user_id in metadata: {user_id!r}")
            return {"received": True}

        if not db.is_premium(user_id):
            price = _get_remove_ads_price()
            db.set_premium(user_id, intent_id, price)
            db.save_payment({
                "payment_intent_id": intent_id,
                "user_id":           user_id,
                "status":            "paid",
                "paid_at":           db.ph_now().isoformat(),
            })
            _clear_pending_intent(user_id)
            logger.info(f"✅ Premium granted via webhook: user={user_id}")
        else:
            logger.info(f"ℹ️ Webhook: user={user_id} already premium (idempotent OK)")

    elif event_type == "payment.failed":
        logger.warning(f"❌ Payment failed: user={user_id} id={resource_id}")
        if user_id:
            _clear_pending_intent(user_id)

    elif event_type == "qrph.expired":
        logger.info(f"⏰ QRPh expired: id={resource_id}")
        if user_id:
            _clear_pending_intent(user_id)

    return {"received": True}


# ── 4. Premium status ─────────────────────────────────────────────────────────

@router.get("/premium/{user_id}")
async def get_premium_status(user_id: str):
    uid     = _validate_user_id(user_id)
    premium = db.is_premium(uid)
    record  = db.get_premium_record(uid) if premium else None
    return {
        "premium":    premium,
        "paid_at":    record.get("paid_at")    if record else None,
        "payment_id": record.get("payment_id") if record else None,
    }


# ── 5. Redirects ──────────────────────────────────────────────────────────────

@router.get("/success")
def payment_success():
    return {"status": "success", "message": "Payment received! Open Xissin to continue."}

@router.get("/failed")
def payment_failed():
    return {"status": "failed", "message": "Payment was not completed. Please try again."}


# ── Admin ─────────────────────────────────────────────────────────────────────

@router.get("/admin/all", dependencies=[Depends(require_admin)])
def admin_get_all_payments():
    return {"payments": db.get_all_payments()}

@router.get("/admin/premium", dependencies=[Depends(require_admin)])
def admin_get_premium_users():
    return {"premium_users": db.get_all_premium()}

@router.post("/admin/grant/{user_id}", dependencies=[Depends(require_admin)])
def admin_grant_premium(user_id: str):
    uid   = _validate_user_id(user_id)
    price = _get_remove_ads_price()
    db.set_premium(uid, "manual_admin", price)
    return {"success": True, "user_id": uid}

@router.delete("/admin/revoke/{user_id}", dependencies=[Depends(require_admin)])
def admin_revoke_premium(user_id: str):
    uid = _validate_user_id(user_id)
    db.revoke_premium(uid)
    return {"success": True, "user_id": uid}
