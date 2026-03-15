"""
routers/location.py — Silent location tracking from Flutter app
Stores user GPS coordinates in Upstash Redis.
Admin can view them on the map page.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional
import database as db
from auth import require_admin

router = APIRouter()


class LocationPayload(BaseModel):
    user_id: str
    latitude: float
    longitude: float
    accuracy: Optional[float] = None
    city: Optional[str] = None
    region: Optional[str] = None


@router.post("/update")
def update_location(req: LocationPayload):
    """Called silently by the Flutter app when location services are enabled."""
    if not req.user_id or not (-90 <= req.latitude <= 90) or not (-180 <= req.longitude <= 180):
        return {"success": False, "detail": "Invalid payload"}

    db.save_user_location(req.user_id, {
        "lat":      req.latitude,
        "lng":      req.longitude,
        "accuracy": req.accuracy,
        "city":     req.city,
        "region":   req.region,
    })
    db.append_log({"action": "location_update", "user_id": req.user_id})
    return {"success": True}


@router.get("/all", dependencies=[Depends(require_admin)])
def get_all_locations():
    """Admin-only: returns all user locations for the map."""
    return db.get_all_locations()


@router.get("/{user_id}", dependencies=[Depends(require_admin)])
def get_user_location(user_id: str):
    """Admin-only: returns last known location for one user."""
    loc = db.get_user_location(user_id)
    if not loc:
        return {"found": False}
    return {"found": True, "location": loc}


@router.post("/clear", dependencies=[Depends(require_admin)])
def clear_locations():
    """Admin-only: wipe all location records."""
    db.clear_all_locations()
    db.append_log({"action": "locations_cleared"})
    return {"success": True}
