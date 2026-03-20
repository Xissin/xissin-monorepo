"""
routers/ip_tracker.py — IP & Domain Tracker

Proxies ip-api.com lookups through the Xissin backend.
• No user key required — free public tool
• Accepts: raw IPv4, IPv6, domain, or full URL (strips protocol/path)
• Rate-limited: 15 requests/minute per IP
• Logs every lookup to dedicated Redis list + activity log
• /log endpoint receives direct lookups from the Flutter app
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
import httpx
import re
import os
import logging
from limiter import limiter
import database as db

router = APIRouter()
logger = logging.getLogger(__name__)

_REDIS_URL   = os.environ.get("UPSTASH_REDIS_REST_URL", "")
_REDIS_TOKEN = os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")

# ip-api.com fields we request
_FIELDS = (
    "status,message,country,countryCode,regionName,city,zip,"
    "lat,lon,timezone,isp,org,as,query,mobile,proxy,hosting"
)

MAX_IP_LOGS = 500


# ── Upstash REST helper ────────────────────────────────────────────────────────

async def _redis(*cmd):
    """Execute a single Redis command via Upstash REST API."""
    if not _REDIS_URL or not _REDIS_TOKEN:
        raise RuntimeError("Upstash env vars not set")
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.post(
            _REDIS_URL,
            headers={"Authorization": f"Bearer {_REDIS_TOKEN}"},
            json=list(cmd),
        )
        resp.raise_for_status()
        return resp.json().get("result")


# ── Request / Response models ─────────────────────────────────────────────────

class IpLookupRequest(BaseModel):
    query:   str = Field(..., min_length=1, max_length=253,
                         description="IP address, domain name, or full URL")
    user_id: str = "anonymous"

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


class IpLogRequest(BaseModel):
    """Received from the Flutter app after a direct ip-api.com lookup."""
    user_id:     str   = "anonymous"
    query:       str   = ""
    resolved_ip: str   = ""
    country:     str   = ""
    city:        str   = ""
    isp:         str   = ""
    lat:         float = 0.0
    lon:         float = 0.0
    success:     bool  = True


# ── Helpers ───────────────────────────────────────────────────────────────────

def _ph_ts() -> str:
    return db.ph_now().strftime("%Y-%m-%dT%H:%M:%S")


async def _save_ip_log(entry: dict):
    """Store a dedicated IP tracker log entry in Redis."""
    import json
    try:
        await _redis("LPUSH", "xissin:ip_tracker:logs", json.dumps(entry))
        await _redis("LTRIM", "xissin:ip_tracker:logs", 0, MAX_IP_LOGS - 1)

        # Country frequency counter
        country = entry.get("country", "")
        if country:
            await _redis("ZINCRBY", "xissin:ip_tracker:countries", 1, country)

        # Total counter
        await _redis("INCR", "xissin:ip_tracker:total")
    except Exception as exc:
        logger.warning(f"[IpTracker] _save_ip_log failed (non-fatal): {exc}")


# ── Lookup endpoint ────────────────────────────────────────────────────────────

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
        entry = {
            "ts":      _ph_ts(),
            "query":   req.query,
            "ip":      req.query,
            "user_id": req.user_id,
            "country": "",
            "city":    "",
            "isp":     "",
            "lat":     0.0,
            "lon":     0.0,
            "success": False,
        }
        await _save_ip_log(entry)
        return IpLookupResponse(
            success=False,
            query=req.query,
            error=data.get("message", "Invalid IP or domain."),
        )

    lat         = float(data.get("lat") or 0)
    lon         = float(data.get("lon") or 0)
    maps_url    = (
        f"https://www.google.com/maps?q={lat},{lon}"
        if (lat != 0 or lon != 0) else ""
    )
    resolved_ip = data.get("query", req.query)
    isp         = data.get("isp", "")
    country     = data.get("country", "")
    city        = data.get("city", "")

    logger.info(
        f"[IpTracker] OK: input={req.query!r} → {resolved_ip} "
        f"| {city}, {data.get('countryCode', '')} "
        f"| ISP: {isp[:40]}"
    )

    # Save dedicated IP log
    entry = {
        "ts":      _ph_ts(),
        "query":   req.query,
        "ip":      resolved_ip,
        "user_id": req.user_id,
        "country": country,
        "city":    city,
        "isp":     isp,
        "lat":     lat,
        "lon":     lon,
        "success": True,
    }
    await _save_ip_log(entry)

    # Also append to activity log (action name matches Activity Logs filter)
    try:
        db.append_log({
            "action":  "ip_lookup",
            "user_id": req.user_id,
            "query":   req.query,
            "country": data.get("countryCode", ""),
            "city":    city,
        })
    except Exception:
        pass

    return IpLookupResponse(
        success=True,
        query=resolved_ip,
        country=country,
        country_code=data.get("countryCode", ""),
        region_name=data.get("regionName", ""),
        city=city,
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


# ── App: log endpoint (called by Flutter after direct ip-api.com lookup) ──────

@router.post("/log")
async def log_ip_lookup(req: IpLogRequest):
    """
    Called by the Flutter app to log a direct ip-api.com lookup.
    The app calls ip-api.com directly for speed, then reports here
    so the admin panel can see all lookups.
    """
    entry = {
        "ts":      _ph_ts(),
        "query":   req.query,
        "ip":      req.resolved_ip,
        "user_id": req.user_id,
        "country": req.country,
        "city":    req.city,
        "isp":     req.isp,
        "lat":     req.lat,
        "lon":     req.lon,
        "success": req.success,
    }
    await _save_ip_log(entry)

    # Also write to activity log
    try:
        db.append_log({
            "action":  "ip_lookup",
            "user_id": req.user_id,
            "query":   req.query,
            "country": req.country,
            "city":    req.city,
        })
    except Exception:
        pass

    return {"status": "logged"}


# ── Admin: logs ────────────────────────────────────────────────────────────────

@router.get("/logs")
async def get_ip_logs(limit: int = 100):
    """Admin: recent IP lookup logs."""
    import json
    try:
        raw = await _redis("LRANGE", "xissin:ip_tracker:logs", 0, limit - 1)
        if not raw:
            return {"logs": []}
        logs = []
        for item in raw:
            try:
                logs.append(json.loads(item) if isinstance(item, str) else item)
            except Exception:
                pass
        return {"logs": logs}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── Admin: stats ───────────────────────────────────────────────────────────────

@router.get("/stats")
async def get_ip_stats():
    """Admin: IP tracker summary stats."""
    try:
        total_raw = await _redis("GET", "xissin:ip_tracker:total")
        total = int(total_raw or 0)

        # Top country from sorted set
        top_raw = await _redis(
            "ZREVRANGE", "xissin:ip_tracker:countries", 0, 0, "WITHSCORES"
        )
        top_country = top_raw[0] if top_raw else "—"

        return {
            "total_lookups": total,
            "top_country":   top_country,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
