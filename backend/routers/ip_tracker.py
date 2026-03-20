"""
routers/ip_tracker.py — IP & Domain Tracker

Proxies ip-api.com lookups through the Xissin backend.
• No user key required — free public tool
• Accepts: raw IPv4, IPv6, domain, or full URL (strips protocol/path)
• Rate-limited: 15 requests/minute per IP
• Logs every lookup for admin panel visibility
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
import httpx
import re
import logging
from limiter import limiter
import database as db

router = APIRouter()
logger = logging.getLogger(__name__)

# ip-api.com fields we request
_FIELDS = (
    "status,message,country,countryCode,regionName,city,zip,"
    "lat,lon,timezone,isp,org,as,query,mobile,proxy,hosting"
)


# ── Request / Response models ─────────────────────────────────────────────────

class IpLookupRequest(BaseModel):
    query: str = Field(..., min_length=1, max_length=253,
                       description="IP address, domain name, or full URL")

    @field_validator("query")
    @classmethod
    def clean_query(cls, v: str) -> str:
        v = v.strip()
        # Strip protocol
        v = re.sub(r"^https?://", "", v, flags=re.IGNORECASE)
        # Strip path, query string, fragment
        v = v.split("/")[0]
        v = v.split("?")[0]
        v = v.split("#")[0]
        # Strip port for domains only — preserve raw IPv4 with port
        is_ipv4 = bool(re.match(r"^\d{1,3}(\.\d{1,3}){3}$", v))
        if not is_ipv4:
            v = v.split(":")[0]
        v = v.strip()
        if not v:
            raise ValueError("Could not extract a valid IP or domain.")
        return v


class IpLookupResponse(BaseModel):
    success:      bool
    query:        str        # resolved IP returned by ip-api.com
    country:      str  = ""
    country_code: str  = ""
    region_name:  str  = ""
    city:         str  = ""
    zip_code:     str  = ""
    lat:          float = 0.0
    lon:          float = 0.0
    timezone:     str  = ""
    isp:          str  = ""
    org:          str  = ""
    as_info:      str  = ""
    mobile:       bool = False
    proxy:        bool = False
    hosting:      bool = False
    maps_url:     str  = ""
    error:        str  = ""


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/lookup", response_model=IpLookupResponse)
@limiter.limit("15/minute")
async def lookup_ip(req: IpLookupRequest, request: Request):
    """
    Looks up geolocation + network info for any IP, domain, or URL.
    Powered by ip-api.com (free, no key required).
    """
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"https://ip-api.com/json/{req.query}",
                params={"fields": _FIELDS},
                timeout=10,
            )
    except httpx.TimeoutException:
        raise HTTPException(504, "IP lookup timed out. Try again.")
    except Exception as e:
        logger.error(f"[IpTracker] http error: {e}")
        raise HTTPException(502, "IP lookup service unreachable.")

    if resp.status_code != 200:
        raise HTTPException(502, f"IP lookup service error ({resp.status_code}).")

    data = resp.json()

    # ip-api returns status=fail for invalid inputs
    if data.get("status") == "fail":
        logger.info(f"[IpTracker] fail: query={req.query} msg={data.get('message')}")
        return IpLookupResponse(
            success=False,
            query=req.query,
            error=data.get("message", "Invalid IP or domain."),
        )

    lat = float(data.get("lat") or 0)
    lon = float(data.get("lon") or 0)
    maps_url = (
        f"https://www.google.com/maps?q={lat},{lon}"
        if (lat != 0 or lon != 0) else ""
    )

    resolved_ip = data.get("query", req.query)
    isp         = data.get("isp", "")

    logger.info(
        f"[IpTracker] OK: input={req.query!r} → {resolved_ip} "
        f"| {data.get('city', '')}, {data.get('countryCode', '')} "
        f"| ISP: {isp[:40]}"
    )

    # Log to admin panel (non-blocking — ignore errors)
    try:
        db.append_log({
            "action":      "ip_tracker_lookup",
            "input":       req.query,
            "resolved_ip": resolved_ip,
            "country":     data.get("countryCode", ""),
            "city":        data.get("city", ""),
            "isp":         isp,
            "proxy":       bool(data.get("proxy", False)),
            "hosting":     bool(data.get("hosting", False)),
        })
    except Exception:
        pass

    return IpLookupResponse(
        success=True,
        query=resolved_ip,
        country=data.get("country", ""),
        country_code=data.get("countryCode", ""),
        region_name=data.get("regionName", ""),
        city=data.get("city", ""),
        zip_code=data.get("zip", ""),
        lat=lat,
        lon=lon,
        timezone=data.get("timezone", ""),
        isp=isp,
        org=data.get("org", ""),
        as_info=data.get("as", ""),
        mobile=bool(data.get("mobile", False)),
        proxy=bool(data.get("proxy", False)),
        hosting=bool(data.get("hosting", False)),
        maps_url=maps_url,
    )
