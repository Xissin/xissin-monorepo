"""
routers/payments.py — Remove Ads payment via PayMongo QRPh
Uses the NEW Payment Intent workflow (NOT the deprecated /sources workflow)

Flow:
  1. App POST /api/payments/create
       → backend creates PaymentIntent + PaymentMethod (qrph) + Attach
       → returns qr_image_url (base64) + payment_intent_id
  2. App shows QR code to user (base64 image)
  3. User scans QR in GCash / Maya / any bank app and pays
  4. PayMongo sends webhook POST /api/payments/webhook  (payment.paid)
  5. Backend verifies → marks user premium → ads disappear

Environment variables in Railway:
  PAYMONGO_SECRET_KEY      = sk_live_xxxxx
  PAYMONGO_PUBLIC_KEY      = pk_live_xxxxx
  PAYMONGO_WEBHOOK_SECRET  = whsec_xxxxx   (from PayMongo Dashboard → Webhooks)
"""

import base64
import hashlib
import hmac
import logging
import os
import httpx

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel
from typing import Optional

import database as db
from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Config ────────────────────────────────────────────────────────────────────
PAYMONGO_BASE           = "https://api.paymongo.com/v1"
_DEFAULT_PRICE_CENTAVOS = 9900   # ₱99.00
_DEFAULT_LABEL          = "Xissin — Remove Ads (Lifetime)"
BACKEND_URL             = "https://xissin-app-backend-production.up.railway.app"


def _get_remove_ads_price() -> int:
    try:
        s = db.get_server_settings()
        return int(s.get("remove_ads_price") or _DEFAULT_PRICE_CENTAVOS)
    except Exception:
        return _DEFAULT_PRICE_CENTAVOS


def _secret_key() -> str:
    k = os.environ.get("PAYMONGO_SECRET_KEY", "").strip()
    if not k:
        raise RuntimeError("PAYMONGO_SECRET_KEY not set in Railway environment.")
    return k


def _auth_header() -> str:
    encoded = base64.b64encode(f"{_secret_key()}:".encode()).decode()
    return f"Basic {encoded}"


def _webhook_secret() -> str:
    return os.environ.get("PAYMONGO_WEBHOOK_SECRET", "").strip()


# ── Request models ────────────────────────────────────────────────────────────

class CreatePaymentRequest(BaseModel):
    user_id: str


class PaymentStatusRequest(BaseModel):
    payment_intent_id: str
    user_id: str


# ── HTTP helpers ──────────────────────────────────────────────────────────────

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
        errors = resp.json().get("errors", [{}])
        detail = errors[0].get("detail", "Unknown payment provider error")
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


# ── 0. Public info endpoint ───────────────────────────────────────────────────

@router.get("/remove-ads-info")
def get_remove_ads_info():
    """Flutter app fetches this on dialog open to show price & benefits."""
    s = db.get_server_settings()
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


# ── 1. Create QRPh Payment (NEW Payment Intent workflow) ─────────────────────

@router.post("/create")
async def create_payment(req: CreatePaymentRequest):
    """
    Step 1: Create PaymentIntent
    Step 2: Create PaymentMethod (type=qrph)
    Step 3: Attach PaymentMethod → returns QR base64 image
    """
    user_id = str(req.user_id)

    if db.is_premium(user_id):
        return {"already_premium": True}

    price = _get_remove_ads_price()

    # ── Step 1: Create Payment Intent ────────────────────────────────────────
    intent_payload = {
        "data": {
            "attributes": {
                "amount":   price,
                "currency": "PHP",
                "payment_method_allowed": ["qrph"],
                "description": "Xissin — Remove Ads Lifetime",
                "metadata": {
                    "user_id": user_id,
                    "product": "remove_ads",
                },
            }
        }
    }
    intent_data = await _paymongo_post("/payment_intents", intent_payload)
    intent_id   = intent_data["data"]["id"]
    client_key  = intent_data["data"]["attributes"]["client_key"]

    # ── Step 2: Create QRPh Payment Method ───────────────────────────────────
    pm_payload = {
        "data": {
            "attributes": {
                "type": "qrph",
                "billing": {
                    "name":  "Xissin User",
                    "email": f"user_{user_id}@xissin.app",
                },
            }
        }
    }
    pm_data = await _paymongo_post("/payment_methods", pm_payload)
    pm_id   = pm_data["data"]["id"]

    # ── Step 3: Attach PaymentMethod to PaymentIntent ─────────────────────────
    attach_payload = {
        "data": {
            "attributes": {
                "payment_method": pm_id,
                "client_key":     client_key,
                "return_url":     f"{BACKEND_URL}/api/payments/success",
            }
        }
    }
    attach_data = await _paymongo_post(
        f"/payment_intents/{intent_id}/attach", attach_payload
    )

    # ── Extract QR image from next_action ─────────────────────────────────────
    next_action = attach_data["data"]["attributes"].get("next_action") or {}
    code_block  = next_action.get("code") or {}
    qr_image    = code_block.get("image_url", "")   # base64 PNG string

    # Save pending payment
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
        "qr_image_url":      qr_image,   # base64 — show directly in Flutter Image.memory()
        "amount":            price,
        "amount_php":        price / 100,
    }


# ── 2. Poll payment status ────────────────────────────────────────────────────

@router.post("/status")
async def check_payment_status(req: PaymentStatusRequest):
    """
    App polls every 5 seconds while QR is displayed.
    NOTE: Per PayMongo docs, prefer webhook over polling.
    """
    user_id = str(req.user_id)

    # Fast path
    if db.is_premium(user_id):
        return {"paid": True, "premium": True}

    try:
        data       = await _paymongo_get(f"/payment_intents/{req.payment_intent_id}")
        attributes = data["data"]["attributes"]
        status     = attributes.get("status", "")

        if status == "succeeded":
            price = _get_remove_ads_price()
            db.set_premium(user_id, req.payment_intent_id, price)
            db.save_payment({
                "payment_intent_id": req.payment_intent_id,
                "user_id":           user_id,
                "status":            "paid",
                "paid_at":           db.ph_now().isoformat(),
            })
            logger.info(f"✅ Payment confirmed via poll: user={user_id} intent={req.payment_intent_id}")
            return {"paid": True, "premium": True}

        # QR expired — tell app to regenerate
        if status == "awaiting_payment_method":
            return {"paid": False, "premium": False, "expired": True, "intent_status": status}

        return {"paid": False, "premium": False, "intent_status": status}

    except HTTPException:
        return {"paid": False, "premium": False}


# ── 3. Webhook ────────────────────────────────────────────────────────────────

@router.post("/webhook")
async def payment_webhook(
    request: Request,
    paymongo_signature: Optional[str] = Header(None, alias="paymongo-signature"),
):
    """
    Register in PayMongo Dashboard → Webhooks:
      URL: https://xissin-app-backend-production.up.railway.app/api/payments/webhook
      Events: payment.paid, payment.failed, qrph.expired
    """
    body = await request.body()

    # Verify signature
    wh_secret = _webhook_secret()
    if wh_secret and paymongo_signature:
        try:
            parts    = dict(p.split("=", 1) for p in paymongo_signature.split(","))
            ts       = parts.get("t", "")
            test_sig = parts.get("te", "") or parts.get("li", "")
            to_sign  = f"{ts}.{body.decode()}"
            expected = hmac.new(
                wh_secret.encode(), to_sign.encode(), hashlib.sha256
            ).hexdigest()
            if not hmac.compare_digest(expected, test_sig):
                logger.warning("⚠️ Webhook signature mismatch")
                raise HTTPException(status_code=400, detail="Invalid signature")
        except HTTPException:
            raise
        except Exception as e:
            logger.warning(f"Webhook signature check error (non-fatal): {e}")

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
        if not db.is_premium(user_id):
            price = _get_remove_ads_price()
            db.set_premium(user_id, intent_id, price)
            db.save_payment({
                "payment_intent_id": intent_id,
                "user_id":           user_id,
                "status":            "paid",
                "paid_at":           db.ph_now().isoformat(),
            })
            logger.info(f"✅ Premium granted via webhook: user={user_id}")

    elif event_type == "payment.failed":
        logger.warning(f"❌ Payment failed: user={user_id} id={resource_id}")

    elif event_type == "qrph.expired":
        logger.info(f"⏰ QRPh expired: id={resource_id}")

    return {"received": True}


# ── 4. Premium status ─────────────────────────────────────────────────────────

@router.get("/premium/{user_id}")
async def get_premium_status(user_id: str):
    premium = db.is_premium(str(user_id))
    record  = db.get_premium_record(str(user_id)) if premium else None
    return {
        "premium":    premium,
        "paid_at":    record.get("paid_at")    if record else None,
        "payment_id": record.get("payment_id") if record else None,
    }


# ── 5. Redirect pages ─────────────────────────────────────────────────────────

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
    price = _get_remove_ads_price()
    db.set_premium(str(user_id), "manual_admin", price)
    return {"success": True, "user_id": user_id}


@router.delete("/admin/revoke/{user_id}", dependencies=[Depends(require_admin)])
def admin_revoke_premium(user_id: str):
    db.revoke_premium(str(user_id))
    return {"success": True, "user_id": user_id}
