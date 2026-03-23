"""
routers/settings.py — Server control settings
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional, List
import re
import database as db
from auth import require_admin

router = APIRouter()


def _normalize_drive_url(raw_url: str) -> str:
    if not raw_url:
        return raw_url
    if "uc?export=download" in raw_url:
        return raw_url
    match = re.search(r"/file/d/([a-zA-Z0-9_-]+)", raw_url)
    if not match:
        match = re.search(r"[?&]id=([a-zA-Z0-9_-]+)", raw_url)
    if match:
        file_id = match.group(1)
        return f"https://drive.google.com/uc?export=download&id={file_id}"
    return raw_url


class ServerSettings(BaseModel):
    maintenance:             bool            = False
    maintenance_message:     Optional[str]   = "Xissin is under maintenance. We'll be back shortly!"
    min_app_version:         Optional[str]   = "1.0.0"
    latest_app_version:      Optional[str]   = "1.0.0"
    feature_sms:             bool            = True
    feature_keys:            bool            = True
    feature_ngl:             bool            = True
    feature_url_remover:     bool            = True
    feature_dup_remover:     bool            = True
    feature_ip_tracker:      bool            = True
    feature_username_tracker:bool            = True
    feature_codm_checker:    bool            = True
    apk_download_url:        Optional[str]   = ""
    apk_version_notes:       Optional[str]   = ""
    # ── Owner bypass — these device IDs skip maintenance mode ────────────────
    owner_bypass_ids:        Optional[List[str]] = []
    # ── Remove Ads product settings ──────────────────────────────────────────
    remove_ads_price:        Optional[int]   = 9900          # in centavos (₱99.00)
    remove_ads_label:        Optional[str]   = "Remove Ads — ₱99 Lifetime"
    remove_ads_subtitle:     Optional[str]   = "Pay once via GCash · No ads forever"
    remove_ads_description:  Optional[str]   = "Enjoy Xissin completely ad-free — forever."
    remove_ads_benefits:     Optional[List[str]] = [
        "No more banner ads",
        "No more interstitial ads",
        "One-time payment — lifetime",
        "Pay via GCash / QRPh QR code",
    ]


@router.get("/", dependencies=[Depends(require_admin)])
def get_settings():
    return db.get_server_settings()


@router.post("/", dependencies=[Depends(require_admin)])
def save_settings(req: ServerSettings):
    data = req.model_dump()

    # Auto-convert the Drive URL before storing
    if data.get("apk_download_url"):
        data["apk_download_url"] = _normalize_drive_url(data["apk_download_url"])

    # Clean up bypass IDs — strip whitespace, remove empty strings
    if data.get("owner_bypass_ids"):
        data["owner_bypass_ids"] = [
            i.strip() for i in data["owner_bypass_ids"] if i and i.strip()
        ]

    db.save_server_settings(data)
    db.append_log({"action": "settings_updated", "maintenance": req.maintenance})
    return {"success": True, "settings": data}


# ── Public version check ───────────────────────────────────────────────────────
@router.get("/version")
def get_version():
    """Public — app uses this to check for updates."""
    settings = db.get_server_settings()
    return {
        "min_app_version":     settings.get("min_app_version",    "1.0.0"),
        "latest_app_version":  settings.get("latest_app_version", "1.0.0"),
        "maintenance":         settings.get("maintenance",        False),
        "maintenance_message": settings.get("maintenance_message",""),
        "apk_download_url":    settings.get("apk_download_url",  ""),
        "apk_version_notes":   settings.get("apk_version_notes", ""),
    }
