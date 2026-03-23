"""
database.py — Upstash Redis persistence layer for Xissin App API
Uses REST API (no redis-py needed — works on Railway without a Redis addon)
"""

import os
import json
import logging
import asyncio
import threading
import httpx
from datetime import datetime
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)

PH_TZ = ZoneInfo("Asia/Manila")

def _url() -> str:
    v = os.environ.get("UPSTASH_REDIS_REST_URL", "").strip().rstrip("/")
    if not v:
        raise RuntimeError("UPSTASH_REDIS_REST_URL environment variable is not set!")
    return v

def _token() -> str:
    v = os.environ.get("UPSTASH_REDIS_REST_TOKEN", "").strip()
    if not v:
        raise RuntimeError("UPSTASH_REDIS_REST_TOKEN environment variable is not set!")
    return v

# ── Redis keys ────────────────────────────────────────────────────────────────
RK_USERS         = "xissin:app:users"
RK_BANNED        = "xissin:app:banned"
RK_LOGS          = "xissin:app:logs"
RK_SMS_STATS     = "xissin:app:sms_stats"
RK_NGL_STATS     = "xissin:app:ngl_stats"
RK_SETTINGS      = "xissin:app:settings"
RK_ANNOUNCEMENTS = "xissin:app:announcements"
RK_SMS_HISTORY   = "xissin:app:sms_history"
RK_SMS_LOGS      = "xissin:app:sms_logs"
RK_DEVICE_INFO   = "xissin:app:device_info"
RK_LOCATIONS     = "xissin:app:locations"
RK_PREMIUM       = "xissin:app:premium"
RK_PAYMENTS      = "xissin:app:payments"

DEFAULT_SETTINGS = {
    "maintenance":         False,
    "maintenance_message": "Xissin is under maintenance. We'll be back shortly!",
    "min_app_version":     "1.0.0",
    "latest_app_version":  "1.0.0",
    "feature_sms":              True,
    "feature_ngl":              True,
    "feature_url_remover":      True,
    "feature_dup_remover":      True,
    "feature_ip_tracker":       True,
    "feature_username_tracker": True,
    "feature_codm_checker":     True,
}

MAX_ANNOUNCEMENTS    = 10
MAX_HISTORY_PER_USER = 20
MAX_LOGS             = 500
MAX_SMS_LOGS         = 1000
MAX_PAYMENTS         = 1000

_cache: dict      = {}
_cache_lock       = threading.Lock()

_CONNECT_TIMEOUT  = 5
_READ_TIMEOUT     = 8
_MAX_RETRIES      = 3
_RETRY_DELAYS     = [0.5, 1.5, 3.0]

def _timeout() -> httpx.Timeout:
    return httpx.Timeout(connect=_CONNECT_TIMEOUT, read=_READ_TIMEOUT,
                         write=_READ_TIMEOUT, pool=_CONNECT_TIMEOUT)

def ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Low-level async Upstash helpers ──────────────────────────────────────────

async def _redis_get_async(key: str):
    last_err = None
    for attempt in range(_MAX_RETRIES):
        try:
            async with httpx.AsyncClient(timeout=_timeout()) as client:
                resp = await client.get(
                    f"{_url()}/get/{key}",
                    headers={"Authorization": f"Bearer {_token()}"},
                )
            if resp.status_code != 200:
                return None
            result = resp.json().get("result")
            if result is None:
                return None
            return json.loads(result)
        except Exception as e:
            last_err = e
            if attempt < _MAX_RETRIES - 1:
                await asyncio.sleep(_RETRY_DELAYS[attempt])
    logger.error(f"Redis GET {key} failed after {_MAX_RETRIES} attempts: {last_err}")
    return None


async def _redis_set_async(key: str, data) -> bool:
    last_err = None
    for attempt in range(_MAX_RETRIES):
        try:
            encoded = json.dumps(data, default=str)
            async with httpx.AsyncClient(timeout=_timeout()) as client:
                resp = await client.post(
                    f"{_url()}/set/{key}",
                    headers={
                        "Authorization": f"Bearer {_token()}",
                        "Content-Type":  "text/plain",
                    },
                    content=encoded,
                )
            if resp.status_code == 200 and resp.json().get("result") == "OK":
                return True
        except Exception as e:
            last_err = e
            if attempt < _MAX_RETRIES - 1:
                await asyncio.sleep(_RETRY_DELAYS[attempt])
    logger.error(
        f"Upstash SET {key}: all {_MAX_RETRIES} attempts failed. "
        f"DATA WILL BE LOST ON REDEPLOY. Last error: {last_err}"
    )
    return False


async def _redis_delete_async(key: str) -> bool:
    for attempt in range(_MAX_RETRIES):
        try:
            async with httpx.AsyncClient(timeout=_timeout()) as client:
                resp = await client.get(
                    f"{_url()}/del/{key}",
                    headers={"Authorization": f"Bearer {_token()}"},
                )
            return resp.status_code == 200
        except Exception as e:
            if attempt < _MAX_RETRIES - 1:
                await asyncio.sleep(_RETRY_DELAYS[attempt])
    return False


# ── Sync wrappers (background event loop) ────────────────────────────────────
_bg_loop: asyncio.AbstractEventLoop | None = None
_bg_loop_lock = threading.Lock()


def _get_bg_loop() -> asyncio.AbstractEventLoop:
    global _bg_loop
    if _bg_loop is not None and _bg_loop.is_running():
        return _bg_loop
    with _bg_loop_lock:
        if _bg_loop is None or not _bg_loop.is_running():
            loop = asyncio.new_event_loop()
            t = threading.Thread(target=loop.run_forever,
                                 daemon=True, name="redis-bg-loop")
            t.start()
            _bg_loop = loop
    return _bg_loop


def _redis_get(key: str):
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(_redis_get_async(key), loop)
    try:
        return future.result(timeout=45)
    except Exception as e:
        logger.error(f"_redis_get({key}) timeout/error: {e}")
        return None


def _redis_set(key: str, data) -> bool:
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(_redis_set_async(key, data), loop)
    try:
        return future.result(timeout=15)   # ← WAIT for write to complete
    except Exception as e:
        logger.error(f"_redis_set({key}) timeout/error: {e}")
        return False


def _redis_delete(key: str) -> bool:
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(_redis_delete_async(key), loop)
    try:
        return future.result(timeout=20)
    except Exception:
        return False


# ── Init ──────────────────────────────────────────────────────────────────────

async def init_db():
    global _cache

    _get_bg_loop()

    raw_users    = await _redis_get_async(RK_USERS)    or {}
    raw_banned   = await _redis_get_async(RK_BANNED)   or []
    raw_logs     = await _redis_get_async(RK_LOGS)     or []
    raw_sms      = await _redis_get_async(RK_SMS_STATS) or {}
    raw_ngl      = await _redis_get_async(RK_NGL_STATS) or {}
    raw_settings = await _redis_get_async(RK_SETTINGS) or {}
    raw_anns     = await _redis_get_async(RK_ANNOUNCEMENTS) or []
    raw_hist     = await _redis_get_async(RK_SMS_HISTORY) or {}
    raw_sms_logs = await _redis_get_async(RK_SMS_LOGS)  or []
    raw_devices  = await _redis_get_async(RK_DEVICE_INFO) or {}
    raw_locs     = await _redis_get_async(RK_LOCATIONS) or {}
    raw_premium  = await _redis_get_async(RK_PREMIUM)  or {}
    raw_payments = await _redis_get_async(RK_PAYMENTS) or []

    banned_set = set(raw_banned) if isinstance(raw_banned, list) else set()

    merged_settings = {**DEFAULT_SETTINGS, **raw_settings}

    with _cache_lock:
        _cache = {
            "users":         raw_users    if isinstance(raw_users, dict)   else {},
            "banned":        banned_set,
            "logs":          raw_logs     if isinstance(raw_logs, list)    else [],
            "sms_stats":     raw_sms      if isinstance(raw_sms, dict)     else {},
            "ngl_stats":     raw_ngl      if isinstance(raw_ngl, dict)     else {},
            "settings":      merged_settings,
            "announcements": raw_anns     if isinstance(raw_anns, list)    else [],
            "sms_history":   raw_hist     if isinstance(raw_hist, dict)    else {},
            "sms_logs":      raw_sms_logs if isinstance(raw_sms_logs, list) else [],
            "device_info":   raw_devices  if isinstance(raw_devices, dict) else {},
            "locations":     raw_locs     if isinstance(raw_locs, dict)    else {},
            "premium":       raw_premium  if isinstance(raw_premium, dict) else {},
            "payments":      raw_payments if isinstance(raw_payments, list) else [],
        }

    logger.info(
        f"✅ DB loaded — "
        f"users:{len(_cache['users'])} "
        f"banned:{len(_cache['banned'])} "
        f"sms_logs:{len(_cache['sms_logs'])} "
        f"locations:{len(_cache['locations'])} "
        f"premium:{len(_cache['premium'])} "
        f"maintenance:{merged_settings.get('maintenance', False)}"
    )

# ── Users ─────────────────────────────────────────────────────────────────────

def get_all_users() -> dict:
    with _cache_lock:
        return dict(_cache.get("users", {}))

def get_user(user_id: str) -> dict | None:
    with _cache_lock:
        return _cache.get("users", {}).get(str(user_id))

def save_user(user_id: str, data: dict):
    with _cache_lock:
        _cache.setdefault("users", {})[str(user_id)] = data
        snapshot = dict(_cache["users"])
    _redis_set(RK_USERS, snapshot)

def is_banned(user_id: str) -> bool:
    with _cache_lock:
        return str(user_id) in _cache.get("banned", set())

def ban_user(user_id: str):
    with _cache_lock:
        _cache.setdefault("banned", set()).add(str(user_id))
        snapshot = list(_cache["banned"])
    _redis_set(RK_BANNED, snapshot)

def unban_user(user_id: str):
    with _cache_lock:
        _cache.setdefault("banned", set()).discard(str(user_id))
        snapshot = list(_cache["banned"])
    _redis_set(RK_BANNED, snapshot)

# ── Action Logs ───────────────────────────────────────────────────────────────

def append_log(entry: dict):
    with _cache_lock:
        logs = _cache.setdefault("logs", [])
        logs.append({**entry, "ts": ph_now().isoformat()})
        if len(logs) > MAX_LOGS:
            _cache["logs"] = logs[-MAX_LOGS:]
        snapshot = list(_cache["logs"])
    _redis_set(RK_LOGS, snapshot)

def get_logs(limit: int = 50) -> list:
    with _cache_lock:
        return list(reversed(_cache.get("logs", [])))[:limit]

# ── SMS Stats ─────────────────────────────────────────────────────────────────

def increment_sms_stat(user_id: str, count: int = 1):
    with _cache_lock:
        stats               = _cache.setdefault("sms_stats", {})
        stats[str(user_id)] = stats.get(str(user_id), 0) + count
        snapshot            = dict(stats)
    _redis_set(RK_SMS_STATS, snapshot)

def get_sms_stat(user_id: str) -> int:
    with _cache_lock:
        return _cache.get("sms_stats", {}).get(str(user_id), 0)

def get_all_sms_stats() -> dict:
    with _cache_lock:
        return dict(_cache.get("sms_stats", {}))

# ── NGL Stats ─────────────────────────────────────────────────────────────────

def increment_ngl_stat(user_id: str, count: int = 1):
    with _cache_lock:
        stats               = _cache.setdefault("ngl_stats", {})
        stats[str(user_id)] = stats.get(str(user_id), 0) + count
        snapshot            = dict(stats)
    _redis_set(RK_NGL_STATS, snapshot)

def get_ngl_stat(user_id: str) -> int:
    with _cache_lock:
        return _cache.get("ngl_stats", {}).get(str(user_id), 0)

def get_all_ngl_stats() -> dict:
    with _cache_lock:
        return dict(_cache.get("ngl_stats", {}))

# ── SMS History ───────────────────────────────────────────────────────────────

def append_sms_history(user_id: str, entry: dict):
    uid = str(user_id)
    with _cache_lock:
        history           = _cache.setdefault("sms_history", {})
        user_hist         = list(history.get(uid, []))
        user_hist.append({**entry, "ts": ph_now().isoformat()})
        if len(user_hist) > MAX_HISTORY_PER_USER:
            user_hist = user_hist[-MAX_HISTORY_PER_USER:]
        history[uid] = user_hist
        snapshot     = {k: list(v) for k, v in history.items()}
    _redis_set(RK_SMS_HISTORY, snapshot)

def get_sms_history(user_id: str) -> list:
    uid = str(user_id)
    with _cache_lock:
        history = _cache.get("sms_history", {}).get(uid, [])
        return list(reversed(history))

# ── SMS Bomb Logs ─────────────────────────────────────────────────────────────

def append_sms_log(entry: dict):
    with _cache_lock:
        logs = _cache.setdefault("sms_logs", [])
        logs.append({**entry, "ts": ph_now().isoformat()})
        if len(logs) > MAX_SMS_LOGS:
            _cache["sms_logs"] = logs[-MAX_SMS_LOGS:]
        snapshot = list(_cache["sms_logs"])
    _redis_set(RK_SMS_LOGS, snapshot)

def get_sms_logs(limit: int = 100) -> list:
    with _cache_lock:
        return list(reversed(_cache.get("sms_logs", [])))[:limit]

def clear_sms_logs():
    with _cache_lock:
        _cache["sms_logs"] = []
    _redis_set(RK_SMS_LOGS, [])

# ── Device Info ───────────────────────────────────────────────────────────────

def save_device_info(user_id: str, info: dict):
    uid = str(user_id)
    with _cache_lock:
        devices      = _cache.setdefault("device_info", {})
        devices[uid] = {**info, "user_id": uid}
        snapshot     = dict(devices)
    _redis_set(RK_DEVICE_INFO, snapshot)

def get_device_info(user_id: str) -> dict | None:
    with _cache_lock:
        return _cache.get("device_info", {}).get(str(user_id))

def get_all_device_info() -> dict:
    with _cache_lock:
        return dict(_cache.get("device_info", {}))

# ── User Locations ────────────────────────────────────────────────────────────

def save_user_location(user_id: str, location: dict):
    uid = str(user_id)
    with _cache_lock:
        locs      = _cache.setdefault("locations", {})
        locs[uid] = {**location, "user_id": uid,
                     "updated_at": ph_now().isoformat()}
        snapshot  = dict(locs)
    _redis_set(RK_LOCATIONS, snapshot)

def get_user_location(user_id: str) -> dict | None:
    with _cache_lock:
        return _cache.get("locations", {}).get(str(user_id))

def get_all_locations() -> dict:
    with _cache_lock:
        return dict(_cache.get("locations", {}))

def clear_all_locations():
    with _cache_lock:
        _cache["locations"] = {}
    _redis_set(RK_LOCATIONS, {})

# ── Announcements ─────────────────────────────────────────────────────────────

def get_announcements() -> list:
    with _cache_lock:
        return list(reversed(_cache.get("announcements", [])))

def add_announcement(ann: dict):
    with _cache_lock:
        anns = _cache.setdefault("announcements", [])
        anns.append(ann)
        if len(anns) > MAX_ANNOUNCEMENTS:
            _cache["announcements"] = anns[-MAX_ANNOUNCEMENTS:]
        snapshot = list(_cache["announcements"])
    _redis_set(RK_ANNOUNCEMENTS, snapshot)

def delete_announcement(ann_id: str) -> bool:
    with _cache_lock:
        anns     = _cache.get("announcements", [])
        new_anns = [a for a in anns if a.get("id") != ann_id]
        if len(new_anns) == len(anns):
            return False
        _cache["announcements"] = new_anns
        snapshot = list(new_anns)
    _redis_set(RK_ANNOUNCEMENTS, snapshot)
    return True

def clear_announcements():
    with _cache_lock:
        _cache["announcements"] = []
    _redis_set(RK_ANNOUNCEMENTS, [])

# ── Server Settings ───────────────────────────────────────────────────────────

def get_server_settings() -> dict:
    with _cache_lock:
        stored = dict(_cache.get("settings", {}))
    return {**DEFAULT_SETTINGS, **stored}

def save_server_settings(data: dict):
    merged = {**DEFAULT_SETTINGS, **data}
    with _cache_lock:
        _cache["settings"] = merged
    _redis_set(RK_SETTINGS, merged)
    logger.info(
        f"⚙️ Server settings updated: "
        f"maintenance={merged.get('maintenance')}"
    )

# ── Premium Users (Remove Ads) ────────────────────────────────────────────────

def is_premium(user_id: str) -> bool:
    with _cache_lock:
        record = _cache.get("premium", {}).get(str(user_id))
    if not record:
        return False
    expiry = record.get("expires_at")
    if expiry is None:
        return True  # lifetime
    try:
        return datetime.fromisoformat(expiry) > ph_now()
    except Exception:
        return True

def set_premium(user_id: str, payment_id: str, amount: int = 9900):
    uid = str(user_id)
    record = {
        "user_id":    uid,
        "payment_id": payment_id,
        "amount":     amount,
        "paid_at":    ph_now().isoformat(),
        "expires_at": None,
        "type":       "remove_ads",
    }
    with _cache_lock:
        _cache.setdefault("premium", {})[uid] = record
        snapshot = dict(_cache["premium"])
    _redis_set(RK_PREMIUM, snapshot)
    append_log({
        "action":     "premium_granted",
        "user_id":    uid,
        "payment_id": payment_id,
        "amount":     amount,
    })
    logger.info(f"⭐ Premium granted: user={uid} payment={payment_id}")

def revoke_premium(user_id: str):
    uid = str(user_id)
    with _cache_lock:
        _cache.get("premium", {}).pop(uid, None)
        snapshot = dict(_cache["premium"])
    _redis_set(RK_PREMIUM, snapshot)
    append_log({"action": "premium_revoked", "user_id": uid})
    logger.info(f"❌ Premium revoked: user={uid}")

def get_premium_record(user_id: str) -> dict | None:
    with _cache_lock:
        return _cache.get("premium", {}).get(str(user_id))

def get_all_premium() -> dict:
    with _cache_lock:
        return dict(_cache.get("premium", {}))

# ── Payment Records ───────────────────────────────────────────────────────────

def save_payment(record: dict):
    with _cache_lock:
        payments = _cache.setdefault("payments", [])
        pid = record.get("payment_intent_id") or record.get("source_id")
        existing = next(
            (i for i, p in enumerate(payments)
             if p.get("payment_intent_id") == pid or p.get("source_id") == pid),
            None
        )
        if existing is not None:
            payments[existing] = {**payments[existing], **record}
        else:
            payments.append(record)
        if len(payments) > MAX_PAYMENTS:
            _cache["payments"] = payments[-MAX_PAYMENTS:]
        snapshot = list(_cache["payments"])
    _redis_set(RK_PAYMENTS, snapshot)

def get_payment_by_id(payment_intent_id: str) -> dict | None:
    with _cache_lock:
        payments = _cache.get("payments", [])
    return next(
        (p for p in payments
         if p.get("payment_intent_id") == payment_intent_id
         or p.get("source_id") == payment_intent_id),
        None
    )

def get_all_payments(limit: int = 200) -> list:
    with _cache_lock:
        return list(reversed(_cache.get("payments", [])))[:limit]


# ── Raw Redis helpers with TTL (for rate limiting & pending intent tracking) ──
# These go DIRECTLY to Upstash REST without touching the in-memory cache.
# Used by payments.py for short-lived keys that should auto-expire.

def redis_get(key: str) -> str | None:
    """
    Get a raw string value from Redis (not JSON-decoded).
    Returns None if key doesn't exist.
    """
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(_redis_raw_get(key), loop)
    try:
        return future.result(timeout=10)
    except Exception:
        return None


def redis_set(key: str, value: str, ttl_seconds: int = 0) -> bool:
    """
    Set a raw string value in Redis with optional TTL (seconds).
    ttl_seconds=0 means no expiry.
    """
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(
        _redis_raw_set(key, value, ttl_seconds), loop
    )
    try:
        return future.result(timeout=10)
    except Exception:
        return False


def redis_incr(key: str, ttl_seconds: int = 0) -> int:
    """
    Atomically increment a Redis counter.
    Sets TTL only if the key is NEW (first increment).
    Returns the new value, or 0 on error.
    """
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(
        _redis_raw_incr(key, ttl_seconds), loop
    )
    try:
        return future.result(timeout=10)
    except Exception:
        return 0


def redis_delete(key: str) -> bool:
    """Delete a raw Redis key."""
    return _redis_delete(key)


# ── Async implementations for raw Redis helpers ───────────────────────────────

async def _redis_raw_get(key: str) -> str | None:
    """GET key → returns raw string result (not JSON parsed)."""
    try:
        async with httpx.AsyncClient(timeout=_timeout()) as client:
            resp = await client.get(
                f"{_url()}/get/{key}",
                headers={"Authorization": f"Bearer {_token()}"},
            )
        if resp.status_code != 200:
            return None
        result = resp.json().get("result")
        return str(result) if result is not None else None
    except Exception as e:
        logger.warning(f"redis_raw_get({key}) error: {e}")
        return None


async def _redis_raw_set(key: str, value: str, ttl_seconds: int = 0) -> bool:
    """
    SET key value [EX ttl_seconds]
    Uses Upstash pipeline-style URL: /set/key/value/EX/ttl
    Value is URL-encoded to handle special characters in JSON strings.
    """
    try:
        from urllib.parse import quote
        encoded_value = quote(str(value), safe='')
        if ttl_seconds > 0:
            url = f"{_url()}/set/{key}/{encoded_value}/EX/{ttl_seconds}"
        else:
            url = f"{_url()}/set/{key}/{encoded_value}"
        async with httpx.AsyncClient(timeout=_timeout()) as client:
            resp = await client.get(
                url,
                headers={"Authorization": f"Bearer {_token()}"},
            )
        return resp.status_code == 200 and resp.json().get("result") == "OK"
    except Exception as e:
        logger.warning(f"redis_raw_set({key}) error: {e}")
        return False


async def _redis_raw_incr(key: str, ttl_seconds: int = 0) -> int:
    """
    INCR key then SET expiry if key is brand new (value == 1).
    Returns the new integer value.
    """
    try:
        async with httpx.AsyncClient(timeout=_timeout()) as client:
            # INCR
            resp = await client.get(
                f"{_url()}/incr/{key}",
                headers={"Authorization": f"Bearer {_token()}"},
            )
        if resp.status_code != 200:
            return 0
        new_val = int(resp.json().get("result", 0))

        # Set TTL only on first increment to avoid resetting expiry on every call
        if new_val == 1 and ttl_seconds > 0:
            async with httpx.AsyncClient(timeout=_timeout()) as client:
                await client.get(
                    f"{_url()}/expire/{key}/{ttl_seconds}",
                    headers={"Authorization": f"Bearer {_token()}"},
                )
        return new_val
    except Exception as e:
        logger.warning(f"redis_raw_incr({key}) error: {e}")
        return 0