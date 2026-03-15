"""
routers/settings.py — Server control settings (maintenance, version, features)
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional
import database as db
from auth import require_admin

router = APIRouter()

class ServerSettings(BaseModel):
    maintenance: bool = False
    maintenance_message: Optional[str] = "Xissin is under maintenance. We'll be back shortly!"
    min_app_version: Optional[str] = "1.0.0"
    latest_app_version: Optional[str] = "1.0.0"
    feature_sms: bool = True
    feature_keys: bool = True
    feature_ngl: bool = True

@router.get("/", dependencies=[Depends(require_admin)])
def get_settings():
    return db.get_server_settings()

@router.post("/", dependencies=[Depends(require_admin)])
def save_settings(req: ServerSettings):
    data = req.model_dump()
    db.save_server_settings(data)
    db.append_log({"action": "settings_updated", "maintenance": req.maintenance})
    return {"success": True, "settings": data}

# ── Public version check endpoint (no admin required) ─────────────────────────
@router.get("/version")
def get_version():
    """Public endpoint — app uses this to check for updates."""
    settings = db.get_server_settings()
    return {
        "min_app_version": settings.get("min_app_version", "1.0.0"),
        "latest_app_version": settings.get("latest_app_version", "1.0.0"),
        "maintenance": settings.get("maintenance", False),
        "maintenance_message": settings.get("maintenance_message", ""),
    }