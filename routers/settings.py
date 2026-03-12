"""
routers/settings.py — Server control settings (maintenance, version, features)
Settings are stored in Upstash Redis so they can be changed without Railway redeploy.
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

@router.get("/", dependencies=[Depends(require_admin)])
def get_settings():
    """Admin: get current server settings."""
    s = db.get_server_settings()
    return s

@router.post("/", dependencies=[Depends(require_admin)])
def save_settings(req: ServerSettings):
    """Admin: update server settings."""
    data = req.model_dump()
    db.save_server_settings(data)
    db.append_log({"action": "settings_updated", "maintenance": req.maintenance})
    return {"success": True, "settings": data}
