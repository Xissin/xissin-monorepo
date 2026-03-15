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

# ── Upstash credentials ───────────────────────────────────────────────────────

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
RK_KEYS          = "xissin:app:keys"
RK_USERS         = "xissin:app:users"
RK_BANNED        = "xissin:app:banned"
RK_LOGS          = "xissin:app:logs"
RK_SMS_STATS     = "xissin:app:sms_stats"
RK_NGL_STATS     = "xissin:app:ngl_stats"
RK_SETTINGS      = "xissin:app:settings"
RK_ANNOUNCEMENTS = "xissin:app:announcements"
RK_SMS_HISTORY   = "xissin:app:sms_history"
RK_SMS_LOGS      = "xissin:app:sms_logs"       # ← NEW: dedicated SMS bomb logs
RK_DEVICE_INFO   = "xissin:app:device_info"    # ← NEW: per-user device info

# ── Default server settings ───────────────────────────────────────────────────
DEFAULT_SETTINGS = {
    "maintenance":         False,
    "maintenance_message": "Xissin is under maintenance. We'll be back shortly!",
    "min_app_version":     "1.0.0",
    "latest_app_version":  "1.0.0",
    "feature_sms":         True,
    "feature_keys":        True,
    "feature_ngl":         True,
}

MAX_ANNOUNCEMENTS    = 10
MAX_HISTORY_PER_USER = 20
MAX_LOGS             = 500
MAX_SMS_LOGS         = 1000   # ← NEW

# ── In-memory cache + lock ────────────────────────────────────────────────────
_cache: dict      = {}
_cache_lock       = threading.Lock()

def ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Low-level async Upstash helpers ──────────────────────────────────────────

async def _redis_get_async(key: str):
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(
                f"{_url()}/get/{key}",
                headers={"Authorization": f"Bearer {_token()}"},
            )
        if resp.status_code != 200:
            return None
        body   = resp.json()
        result = body.get("result")
        if result is None:
            return None
        return json.loads(result)
    except Exception as e:
        logger.error(f"Redis GET {key} failed: {e}")
        return None


async def _redis_set_async(key: str, data) -> bool:
    for attempt in range(1, 4):
        try:
            encoded = json.dumps(data, default=str)
            async with httpx.AsyncClient(timeout=10) as client:
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
            logger.error(f"Redis SET {key} attempt {attempt} failed: {e}")
            if attempt < 3:
                await asyncio.sleep(attempt)
    return False


# ── Sync wrappers ─────────────────────────────────────────────────────────────
_bg_loop: asyncio.AbstractEventLoop | None = None
_bg_loop_lock = threading.Lock()


def _get_bg_loop() -> asyncio.AbstractEventLoop:
    global _bg_loop
    if _bg_loop is not None and _bg_loop.is_running():
        return _bg_loop
    with _bg_loop_lock:
        if _bg_loop is None or not _bg_loop.is_running():
            loop = asyncio.new_event_loop()
            t = threading.Thread(target=loop.run_forever, daemon=True, name="redis-bg-loop")
            t.start()
            _bg_loop = loop
    return _bg_loop


def _redis_get(key: str):
    loop   = _get_bg_loop()
    future = asyncio.run_coroutine_threadsafe(_redis_get_async(key), loop)
    try:
        return future.result(timeout=15)
    except Exception as e:
        logger.error(f"_redis_get({key}) timeout/error: {e}")
        return None


def _redis_set(key: str, data) -> bool:
    loop = _get_bg_loop()
    asyncio.run_coroutine_threadsafe(_redis_set_async(key, data), loop)
    return True


# ── Expired key pruning ───────────────────────────────────────────────────────

def _prune_expired_keys(keys_dict: dict) -> dict:
    now     = ph_now().isoformat()
    pruned  = {}
    removed = 0
    for k, meta in keys_dict.items():
        expires_at = meta.get("expires_at", "")
        try:
            if expires_at and expires_at < now:
                removed += 1
                continue
        except Exception:
            pass
        pruned[k] = meta
    if removed:
        logger.info(f"🧹 Pruned {removed} expired key(s) from Redis")
    return pruned


# ── Public API ────────────────────────────────────────────────────────────────

async def init_db():
    global _cache

    _get_bg_loop()

    raw_keys   = await _redis_get_async(RK_KEYS)   or {}
    clean_keys = _prune_expired_keys(raw_keys)
    if len(clean_keys) != len(raw_keys):
        await _redis_set_async(RK_KEYS, clean_keys)

    raw_banned = await _redis_get_async(RK_BANNED) or []
    if isinstance(raw_banned, list):
        banned_set = set(raw_banned)
    elif isinstance(raw_banned, set):
        banned_set = raw_banned
    else:
        banned_set = set()

    raw_settings    = await _redis_get_async(RK_SETTINGS) or {}
    merged_settings = {**DEFAULT_SETTINGS, **raw_settings}

    with _cache_lock:
        _cache["keys"]          = clean_keys
        _cache["users"]         = await _redis_get_async(RK_USERS)         or {}
        _cache["banned"]        = banned_set
        _cache["logs"]          = await _redis_get_async(RK_LOGS)          or []
        _cache["sms_stats"]     = await _redis_get_async(RK_SMS_STATS)     or {}
        _cache["ngl_stats"]     = await _redis_get_async(RK_NGL_STATS)     or {}
        _cache["settings"]      = merged_settings
        _cache["announcements"] = await _redis_get_async(RK_ANNOUNCEMENTS) or []
        _cache["sms_history"]   = await _redis_get_async(RK_SMS_HISTORY)   or {}
        _cache["sms_logs"]      = await _redis_get_async(RK_SMS_LOGS)      or []   # ← NEW
        _cache["device_info"]   = await _redis_get_async(RK_DEVICE_INFO)   or {}   # ← NEW

    logger.info(
        f"✅ DB loaded — keys:{len(_cache['keys'])} "
        f"users:{len(_cache['users'])} "
        f"banned:{len(_cache['banned'])} "
        f"announcements:{len(_cache['announcements'])} "
        f"sms_logs:{len(_cache['sms_logs'])} "
        f"maintenance:{merged_settings.get('maintenance', False)}"
    )

# ── Keys ──────────────────────────────────────────────────────────────────────

def get_all_keys() -> dict:
    with _cache_lock:
        return dict(_cache.get("keys", {}))

def get_key(key_str: str) -> dict | None:
    with _cache_lock:
        return _cache.get("keys", {}).get(key_str)

def save_key(key_str: str, metadata: dict):
    with _cache_lock:
        _cache.setdefault("keys", {})[key_str] = metadata
        _cache["keys"] = _prune_expired_keys(_cache["keys"])
        snapshot = dict(_cache["keys"])
    _redis_set(RK_KEYS, snapshot)

def delete_key(key_str: str):
    with _cache_lock:
        _cache.setdefault("keys", {}).pop(key_str, None)
        snapshot = dict(_cache["keys"])
    _redis_set(RK_KEYS, snapshot)

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
        stats             = _cache.setdefault("sms_stats", {})
        stats[str(user_id)] = stats.get(str(user_id), 0) + count
        snapshot          = dict(stats)
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

# ── SMS Bomb Logs (dedicated, admin-visible) ──────────────────────────────────

def append_sms_log(entry: dict):
    """Store a full SMS bomb attack log with service-level results."""
    with _cache_lock:
        logs = _cache.setdefault("sms_logs", [])
        logs.append({**entry, "ts": ph_now().isoformat()})
        if len(logs) > MAX_SMS_LOGS:
            _cache["sms_logs"] = logs[-MAX_SMS_LOGS:]
        snapshot = list(_cache["sms_logs"])
    _redis_set(RK_SMS_LOGS, snapshot)

def get_sms_logs(limit: int = 100) -> list:
    """Return most-recent SMS bomb logs first."""
    with _cache_lock:
        return list(reversed(_cache.get("sms_logs", [])))[:limit]

def clear_sms_logs():
    """Admin: wipe all SMS bomb logs."""
    with _cache_lock:
        _cache["sms_logs"] = []
    _redis_set(RK_SMS_LOGS, [])

# ── Device Info ───────────────────────────────────────────────────────────────

def save_device_info(user_id: str, info: dict):
    """Upsert device info for a user. Updated on every app launch."""
    uid = str(user_id)
    with _cache_lock:
        devices           = _cache.setdefault("device_info", {})
        devices[uid]      = {**info, "user_id": uid}
        snapshot          = dict(devices)
    _redis_set(RK_DEVICE_INFO, snapshot)

def get_device_info(user_id: str) -> dict | None:
    with _cache_lock:
        return _cache.get("device_info", {}).get(str(user_id))

def get_all_device_info() -> dict:
    with _cache_lock:
        return dict(_cache.get("device_info", {}))

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
    logger.info(f"⚙️ Server settings updated: maintenance={merged.get('maintenance')}")
