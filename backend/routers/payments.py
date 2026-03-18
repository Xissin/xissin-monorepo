"""
routers/payments.py — Remove Ads payment via PayMongo (QRPh / QR code)

Flow:
  1. App POST /api/payments/create  → backend creates PayMongo Source (QRPh)
                                     → returns qr_image_url + source_id
  2. App shows QR code to user
  3. User scans QR in GCash/Maya/bank app and pays
  4. PayMongo sends webhook POST /api/payments/webhook
  5. Backend verifies → marks user premium → ads disappear

Environment variables needed in Railway:
  PAYMONGO_SECRET_KEY      = sk_live_xxxxx   (from PayMongo Dashboard → Developers)
  PAYMONGO_PUBLIC_KEY      = pk_live_xxxxx   (from PayMongo Dashboard → Developers)
  PAYMONGO_WEBHOOK_SECRET  = whsec_xxxxx     (from PayMongo Dashboard → Webhooks)
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

logger  = logging.getLogger(__name__)
router  = APIRouter()

# ── Config ────────────────────────────────────────────────────────────────────
PAYMONGO_BASE           = "https://api.paymongo.com/v1"
_DEFAULT_PRICE_CENTAVOS = 9900   # fallback ₱99.00
_DEFAULT_LABEL          = "Xissin — Remove Ads (Lifetime)"


def _get_remove_ads_price() -> int:
    """Read price from settings (centavos). Falls back to ₱99 if not set."""
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


# ── Request / Response models ─────────────────────────────────────────────────

class CreatePaymentRequest(BaseModel):
    user_id: str


class PaymentStatusRequest(BaseModel):
    source_id: str
    user_id:   str


# ── Helpers ───────────────────────────────────────────────────────────────────

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
        raise HTTPException(
            status_code=502,
            detail=f"Payment provider error: {resp.json().get('errors', [{}])[0].get('detail', 'Unknown error')}"
        )
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


# ── 0. Public product info endpoint (app fetches this on dialog open) ─────────

@router.get("/remove-ads-info")
def get_remove_ads_info():
    """Public — Flutter app fetches price, label, benefits before showing dialog."""
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


# ── 1. Create QRPh Payment Source ─────────────────────────────────────────────

@router.post("/create")
async def create_payment(req: CreatePaymentRequest):
    """
    Creates a QRPh source. Returns qr_image_url and source_id.
    The Flutter app displays the QR code for the user to scan.
    """
    user_id = str(req.user_id)

    # Don't charge if already premium
    if db.is_premium(user_id):
        return {"already_premium": True}

    # ✅ FIX: call the function, don't use undefined bare variable
    price = _get_remove_ads_price()

    payload = {
        "data": {
            "attributes": {
                "amount":   price,
                "currency": "PHP",
                "type":     "qrph",
                "redirect": {
                    "success": "https://xissin-app-backend-production.up.railway.app/api/payments/success",
                    "failed":  "https://xissin-app-backend-production.up.railway.app/api/payments/failed",
                },
                "metadata": {
                    "user_id":  user_id,
                    "product":  "remove_ads",
                },
                "billing": {
                    "name":  "Xissin User",
                    "email": f"user_{user_id}@xissin.app",
                    "phone": "+63",
                },
            }
        }
    }

    data = await _paymongo_post("/sources", payload)
    source = data.get("data", {})
    source_id   = source.get("id", "")
    attributes  = source.get("attributes", {})
    qr_image    = attributes.get("qr_code_image", "") or attributes.get("qr_image", "")
    redirect_url = attributes.get("redirect", {}).get("checkout_url", "")

    # Save as pending payment
    db.save_payment({
        "source_id":   source_id,
        "user_id":     user_id,
        "amount":      price,
        "status":      "pending",
        "type":        "qrph",
        "product":     "remove_ads",
        "created_at":  db.ph_now().isoformat(),
    })

    logger.info(f"💳 QRPh source created: {source_id} for user={user_id}")

    return {
        "source_id":    source_id,
        "qr_image_url": qr_image,
        "redirect_url": redirect_url,
        "amount":       price,
        "amount_php":   price / 100,
    }


# ── 2. Poll payment status (app polls this every 5 seconds) ──────────────────

@router.post("/status")
async def check_payment_status(req: PaymentStatusRequest):
    """
    App polls this every 5 seconds while showing the QR code.
    Returns {'paid': True/False, 'premium': True/False}
    """
    user_id = str(req.user_id)

    # Fast path: already marked premium
    if db.is_premium(user_id):
        return {"paid": True, "premium": True}

    # Check PayMongo directly
    try:
        data   = await _paymongo_get(f"/sources/{req.source_id}")
        source = data.get("data", {})
        status = source.get("attributes", {}).get("status", "")

        if status == "chargeable":
            price = _get_remove_ads_price()
            db.set_premium(user_id, req.source_id, price)
            db.save_payment({
                "source_id": req.source_id,
                "user_id":   user_id,
                "status":    "paid",
                "paid_at":   db.ph_now().isoformat(),
            })
            logger.info(f"✅ Payment confirmed via poll: user={user_id} source={req.source_id}")
            return {"paid": True, "premium": True}

        return {"paid": False, "premium": False, "source_status": status}

    except HTTPException:
        return {"paid": False, "premium": False}


# ── 3. Webhook (PayMongo calls this automatically on payment) ─────────────────

@router.post("/webhook")
async def payment_webhook(
    request:   Request,
    paymongo_signature: Optional[str] = Header(None, alias="paymongo-signature"),
):
    """
    PayMongo calls this endpoint automatically when a payment succeeds.
    Register this URL in PayMongo Dashboard → Webhooks:
      https://xissin-app-backend-production.up.railway.app/api/payments/webhook
    Events to subscribe: source.chargeable, payment.paid
    """
    body = await request.body()

    # Verify webhook signature if secret is configured
    wh_secret = _webhook_secret()
    if wh_secret and paymongo_signature:
        try:
            parts       = dict(p.split("=", 1) for p in paymongo_signature.split(","))
            ts          = parts.get("t", "")
            test_sig    = parts.get("te", "") or parts.get("li", "")
            to_sign     = f"{ts}.{body.decode()}"
            expected    = hmac.new(
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

    event_type = event.get("data", {}).get("attributes", {}).get("type", "")
    resource   = event.get("data", {}).get("attributes", {}).get("data", {})
    attributes = resource.get("attributes", {})
    metadata   = attributes.get("metadata") or {}
    user_id    = str(metadata.get("user_id", ""))
    resource_id= resource.get("id", "")

    logger.info(f"📬 Webhook received: type={event_type} user={user_id} id={resource_id}")

    if event_type in ("source.chargeable", "payment.paid") and user_id:
        if not db.is_premium(user_id):
            # ✅ FIX: call the function instead of bare undefined variable
            price = _get_remove_ads_price()
            db.set_premium(user_id, resource_id, price)
            db.save_payment({
                "source_id": resource_id,
                "user_id":   user_id,
                "status":    "paid",
                "paid_at":   db.ph_now().isoformat(),
            })
            logger.info(f"✅ Premium granted via webhook: user={user_id}")

    return {"received": True}


# ── 4. Check if user is premium (app calls on startup) ────────────────────────

@router.get("/premium/{user_id}")
async def get_premium_status(user_id: str):
    """App calls this on startup to check if ads should be removed."""
    premium = db.is_premium(str(user_id))
    record  = db.get_premium_record(str(user_id)) if premium else None
    return {
        "premium":    premium,
        "paid_at":    record.get("paid_at")    if record else None,
        "payment_id": record.get("payment_id") if record else None,
    }


# ── 5. Redirect pages (PayMongo redirects here after QR scan) ─────────────────

@router.get("/success")
def payment_success():
    return {"status": "success", "message": "Payment received! Open Xissin to continue."}


@router.get("/failed")
def payment_failed():
    return {"status": "failed", "message": "Payment was not completed. Please try again."}


# ── Admin endpoints ───────────────────────────────────────────────────────────

@router.get("/admin/all", dependencies=[Depends(require_admin)])
def admin_get_all_payments():
    return {"payments": db.get_all_payments()}


@router.get("/admin/premium", dependencies=[Depends(require_admin)])
def admin_get_premium_users():
    return {"premium_users": db.get_all_premium()}


@router.post("/admin/grant/{user_id}", dependencies=[Depends(require_admin)])
def admin_grant_premium(user_id: str):
    """Manually grant premium to a user (e.g. if they paid via GCash send)."""
    # ✅ FIX: call the function instead of bare undefined variable
    price = _get_remove_ads_price()
    db.set_premium(str(user_id), "manual_admin", price)
    return {"success": True, "user_id": user_id}


@router.delete("/admin/revoke/{user_id}", dependencies=[Depends(require_admin)])
def admin_revoke_premium(user_id: str):
    db.revoke_premium(str(user_id))
    return {"success": True, "user_id": user_id}