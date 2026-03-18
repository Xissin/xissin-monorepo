"""
routers/location.py — Silent location tracking from Flutter app
Stores user GPS coordinates in Upstash Redis.
Includes reverse geocoding to resolve City + Region automatically.
Admin can view them on the map page.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional
import httpx
import logging
import database as db
from auth import require_admin

router = APIRouter()
logger = logging.getLogger(__name__)


class LocationPayload(BaseModel):
    user_id:   str
    latitude:  float
    longitude: float
    accuracy:  Optional[float] = None
    city:      Optional[str]   = None
    region:    Optional[str]   = None


async def _reverse_geocode(lat: float, lng: float) -> dict:
    """
    Uses OpenStreetMap Nominatim (free, no API key needed) to get
    city and region from coordinates.
    Returns {"city": "...", "region": "...", "country": "..."}
    """
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(
                "https://nominatim.openstreetmap.org/reverse",
                params={
                    "lat":            lat,
                    "lon":            lng,
                    "format":         "json",
                    "addressdetails": 1,
                    "zoom":           10,
                },
                headers={"User-Agent": "XissinApp/1.0"},
            )
        if resp.status_code != 200:
            return {}

        data    = resp.json()
        address = data.get("address", {})

        # City: try multiple fields Nominatim uses
        city = (
            address.get("city")
            or address.get("town")
            or address.get("municipality")
            or address.get("village")
            or address.get("suburb")
            or ""
        )

        # Region: province or state
        region = (
            address.get("province")
            or address.get("state")
            or address.get("region")
            or ""
        )

        country = address.get("country_code", "").upper()

        return {"city": city, "region": region, "country": country}

    except Exception as e:
        logger.warning(f"Reverse geocode failed for {lat},{lng}: {e}")
        return {}


@router.post("/update")
async def update_location(req: LocationPayload):
    """
    Called silently by the Flutter app when location services are enabled.
    Location records are NEVER deleted automatically — they persist forever
    until an admin manually clears them.
    """
    if (
        not req.user_id
        or not (-90  <= req.latitude  <= 90)
        or not (-180 <= req.longitude <= 180)
    ):
        return {"success": False, "detail": "Invalid payload"}

    # Use city/region from app if provided, otherwise reverse geocode
    city   = req.city   or ""
    region = req.region or ""
    country = ""

    if not city or not region:
        geo = await _reverse_geocode(req.latitude, req.longitude)
        city    = city    or geo.get("city",    "")
        region  = region  or geo.get("region",  "")
        country = geo.get("country", "")

    db.save_user_location(req.user_id, {
        "lat":      req.latitude,
        "lng":      req.longitude,
        "accuracy": req.accuracy,
        "city":     city,
        "region":   region,
        "country":  country,
    })

    return {"success": True}


@router.get("/all", dependencies=[Depends(require_admin)])
def get_all_locations():
    """Admin-only: returns ALL user locations — including outside PH."""
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
