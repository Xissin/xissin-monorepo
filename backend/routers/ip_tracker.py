"""
routers/ip_tracker.py — IP & Domain Tracker  (v2 — multi-provider with fallback)

Providers tried in order (all free, no key required):
  1. ip-api.com   — best data (HTTP only, works server-side fine)
  2. ipapi.co     — HTTPS, good data, 1000 req/day per IP
  3. ip.guide     — HTTPS, minimal but reliable

• No user key required — free public tool
• Accepts: raw IPv4, IPv6, domain, or full URL (strips protocol/path)
• Rate-limited: 15 requests/minute per IP
• Logs every lookup to dedicated Redis list + activity log
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
import httpx
import re
import os
import logging
import json
from limiter import limiter
import database as db

router = APIRouter()
logger = logging.getLogger(__name__)

_REDIS_URL   = os.environ.get("UPSTASH_REDIS_REST_URL", "")
_REDIS_TOKEN = os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")

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
    query:        str        # resolved IP returned by the provider
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
    provider:     str  = ""   # which API provider answered


class IpLogRequest(BaseModel):
    """Received from the Flutter app after a direct lookup."""
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
    try:
        await _redis("LPUSH", "xissin:ip_tracker:logs", json.dumps(entry))
        await _redis("LTRIM", "xissin:ip_tracker:logs", 0, MAX_IP_LOGS - 1)

        country = entry.get("country", "")
        if country:
            await _redis("ZINCRBY", "xissin:ip_tracker:countries", 1, country)

        await _redis("INCR", "xissin:ip_tracker:total")
    except Exception as exc:
        logger.warning(f"[IpTracker] _save_ip_log failed (non-fatal): {exc}")


# ── Multi-provider lookup ──────────────────────────────────────────────────────

async def _try_ip_api(query: str, client: httpx.AsyncClient) -> dict | None:
    """
    Provider 1: ip-api.com
    HTTP only — but this is fine because it's a server-side call from Railway.
    Returns None on failure so the caller can try the next provider.
    """
    fields = (
        "status,message,country,countryCode,regionName,city,zip,"
        "lat,lon,timezone,isp,org,as,query,mobile,proxy,hosting"
    )
    try:
        resp = await client.get(
            f"http://ip-api.com/json/{query}",
            params={"fields": fields},
            timeout=8,
        )
        if resp.status_code != 200:
            logger.warning(f"[IpTracker] ip-api.com returned {resp.status_code}")
            return None
        data = resp.json()
        if data.get("status") == "fail":
            # If the query itself is invalid, propagate fail — don't try other providers
            return {"_fail": True, "message": data.get("message", "Invalid IP or domain.")}
        return {
            "provider":     "ip-api.com",
            "query":        data.get("query", query),
            "country":      data.get("country", ""),
            "country_code": data.get("countryCode", ""),
            "region_name":  data.get("regionName", ""),
            "city":         data.get("city", ""),
            "zip_code":     data.get("zip", ""),
            "lat":          float(data.get("lat") or 0),
            "lon":          float(data.get("lon") or 0),
            "timezone":     data.get("timezone", ""),
            "isp":          data.get("isp", ""),
            "org":          data.get("org", ""),
            "as_info":      data.get("as", ""),
            "mobile":       bool(data.get("mobile", False)),
            "proxy":        bool(data.get("proxy", False)),
            "hosting":      bool(data.get("hosting", False)),
        }
    except Exception as exc:
        logger.warning(f"[IpTracker] ip-api.com error: {exc}")
        return None


async def _try_ipapi_co(query: str, client: httpx.AsyncClient) -> dict | None:
    """
    Provider 2: ipapi.co — HTTPS, 1 000 req/day free (no key needed).
    Returns None on failure.
    """
    try:
        resp = await client.get(
            f"https://ipapi.co/{query}/json/",
            headers={"User-Agent": "xissin-app/2.0"},
            timeout=8,
        )
        if resp.status_code == 429:
            logger.warning("[IpTracker] ipapi.co rate-limited")
            return None
        if resp.status_code != 200:
            logger.warning(f"[IpTracker] ipapi.co returned {resp.status_code}")
            return None
        data = resp.json()
        # ipapi.co returns {"error": true, "reason": "..."} for invalid IPs
        if data.get("error"):
            reason = data.get("reason", "Invalid IP or domain.")
            return {"_fail": True, "message": reason}
        return {
            "provider":     "ipapi.co",
            "query":        data.get("ip", query),
            "country":      data.get("country_name", ""),
            "country_code": data.get("country_code", ""),
            "region_name":  data.get("region", ""),
            "city":         data.get("city", ""),
            "zip_code":     data.get("postal", ""),
            "lat":          float(data.get("latitude") or 0),
            "lon":          float(data.get("longitude") or 0),
            "timezone":     data.get("timezone", ""),
            "isp":          data.get("org", ""),   # ipapi.co puts org+isp in "org"
            "org":          data.get("org", ""),
            "as_info":      data.get("asn", ""),
            "mobile":       False,   # ipapi.co free tier doesn't provide this
            "proxy":        False,
            "hosting":      False,
        }
    except Exception as exc:
        logger.warning(f"[IpTracker] ipapi.co error: {exc}")
        return None


async def _try_ipguide(query: str, client: httpx.AsyncClient) -> dict | None:
    """
    Provider 3: ip.guide — HTTPS, completely free, no key, no rate limit published.
    Minimal data but reliable fallback.
    Returns None on failure.
    """
    try:
        resp = await client.get(
            f"https://ip.guide/{query}",
            headers={"Accept": "application/json", "User-Agent": "xissin-app/2.0"},
            timeout=8,
        )
        if resp.status_code != 200:
            logger.warning(f"[IpTracker] ip.guide returned {resp.status_code}")
            return None
        data = resp.json()
        # ip.guide structure: {"ip": "...", "network": {...}, "location": {...}}
        loc = data.get("location") or {}
        net = data.get("network") or {}
        return {
            "provider":     "ip.guide",
            "query":        data.get("ip", query),
            "country":      loc.get("country", ""),
            "country_code": loc.get("country_code", ""),
            "region_name":  loc.get("region", ""),
            "city":         loc.get("city", ""),
            "zip_code":     loc.get("postal_code", ""),
            "lat":          float(loc.get("latitude") or 0),
            "lon":          float(loc.get("longitude") or 0),
            "timezone":     loc.get("timezone", ""),
            "isp":          net.get("name", ""),
            "org":          net.get("name", ""),
            "as_info":      str(net.get("autonomous_system", {}).get("asn", "")),
            "mobile":       False,
            "proxy":        False,
            "hosting":      False,
        }
    except Exception as exc:
        logger.warning(f"[IpTracker] ip.guide error: {exc}")
        return None


async def _multi_lookup(query: str) -> dict:
    """
    Try providers in order. Returns normalised result dict.
    Raises HTTPException if all providers fail.
    """
    async with httpx.AsyncClient() as client:
        for fn in [_try_ip_api, _try_ipapi_co, _try_ipguide]:
            result = await fn(query, client)
            if result is None:
                continue   # provider error — try next
            if result.get("_fail"):
                # Query is invalid — don't try other providers
                return result
            return result

    raise HTTPException(
        status_code=503,
        detail="All IP lookup providers are currently unavailable. Please try again in a moment.",
    )


# ── Lookup endpoint ────────────────────────────────────────────────────────────

@router.post("/lookup", response_model=IpLookupResponse)
@limiter.limit("15/minute")
async def lookup_ip(req: IpLookupRequest, request: Request):
    """
    Looks up geolocation + network info for any IP, domain, or URL.
    Uses multiple providers with automatic fallback.
    """
    try:
        data = await _multi_lookup(req.query)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[IpTracker] unexpected error: {e}")
        raise HTTPException(status_code=500, detail="IP lookup failed. Please try again.")

    if data.get("_fail"):
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

    lat      = data["lat"]
    lon      = data["lon"]
    maps_url = (
        f"https://www.google.com/maps?q={lat},{lon}"
        if (lat != 0 or lon != 0) else ""
    )

    provider     = data.get("provider", "")
    resolved_ip  = data.get("query", req.query)
    isp          = data.get("isp", "")
    country      = data.get("country", "")
    city         = data.get("city", "")

    logger.info(
        f"[IpTracker] OK [{provider}]: input={req.query!r} → {resolved_ip} "
        f"| {city}, {data.get('country_code', '')} "
        f"| ISP: {isp[:40]}"
    )

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
        "provider": provider,
    }
    await _save_ip_log(entry)

    try:
        db.append_log({
            "action":  "ip_lookup",
            "user_id": req.user_id,
            "query":   req.query,
            "country": data.get("country_code", ""),
            "city":    city,
            "provider": provider,
        })
    except Exception:
        pass

    return IpLookupResponse(
        success=True,
        query=resolved_ip,
        country=country,
        country_code=data.get("country_code", ""),
        region_name=data.get("region_name", ""),
        city=city,
        zip_code=data.get("zip_code", ""),
        lat=lat,
        lon=lon,
        timezone=data.get("timezone", ""),
        isp=isp,
        org=data.get("org", ""),
        as_info=data.get("as_info", ""),
        mobile=data.get("mobile", False),
        proxy=data.get("proxy", False),
        hosting=data.get("hosting", False),
        maps_url=maps_url,
        provider=provider,
    )


# ── App: log endpoint ──────────────────────────────────────────────────────────

@router.post("/log")
async def log_ip_lookup(req: IpLogRequest):
    """Called by the Flutter app to log a lookup result."""
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
