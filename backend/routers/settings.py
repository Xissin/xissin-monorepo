"""
routers/settings.py — Server control settings (maintenance, version, features, APK hosting)
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional
import re
import database as db
from auth import require_admin

router = APIRouter()


def _normalize_drive_url(raw_url: str) -> str:
    """
    Accepts any Google Drive share URL format and converts it to a
    direct-download URL.  Returns the original string unchanged if it
    doesn't look like a Drive link.

    Supported input formats:
      https://drive.google.com/file/d/<ID>/view?usp=sharing
      https://drive.google.com/open?id=<ID>
      https://drive.google.com/uc?export=download&id=<ID>   <- already correct
    """
    if not raw_url:
        return raw_url

    # Already a direct-download link — leave it alone
    if "uc?export=download" in raw_url:
        return raw_url

    # Extract the file ID
    match = re.search(r"/file/d/([a-zA-Z0-9_-]+)", raw_url)
    if not match:
        match = re.search(r"[?&]id=([a-zA-Z0-9_-]+)", raw_url)

    if match:
        file_id = match.group(1)
        return f"https://drive.google.com/uc?export=download&id={file_id}"

    # Unrecognised format — return as-is so we don't silently break things
    return raw_url


class ServerSettings(BaseModel):
    maintenance: bool = False
    maintenance_message: Optional[str] = "Xissin is under maintenance. We'll be back shortly!"
    min_app_version: Optional[str] = "1.0.0"
    latest_app_version: Optional[str] = "1.0.0"
    feature_sms: bool = True
    feature_keys: bool = True
    feature_ngl: bool = True
    # APK download — store whatever the admin pastes; we normalise on save
    apk_download_url: Optional[str] = ""
    apk_version_notes: Optional[str] = ""   # short changelog shown in update dialog


@router.get("/", dependencies=[Depends(require_admin)])
def get_settings():
    return db.get_server_settings()


@router.post("/", dependencies=[Depends(require_admin)])
def save_settings(req: ServerSettings):
    data = req.model_dump()

    # Auto-convert the Drive URL before storing
    if data.get("apk_download_url"):
        data["apk_download_url"] = _normalize_drive_url(data["apk_download_url"])

    db.save_server_settings(data)
    db.append_log({"action": "settings_updated", "maintenance": req.maintenance})
    return {"success": True, "settings": data}


# ── Public version check endpoint (no admin required) ─────────────────────────
@router.get("/version")
def get_version():
    """Public endpoint — app uses this to check for updates."""
    settings = db.get_server_settings()
    return {
        "min_app_version":     settings.get("min_app_version",    "1.0.0"),
        "latest_app_version":  settings.get("latest_app_version", "1.0.0"),
        "maintenance":         settings.get("maintenance",        False),
        "maintenance_message": settings.get("maintenance_message",""),
        "apk_download_url":    settings.get("apk_download_url",  ""),
        "apk_version_notes":   settings.get("apk_version_notes", ""),
    }
