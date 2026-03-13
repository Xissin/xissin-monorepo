"""
database.py — Upstash Redis persistence layer for Xissin App API
Uses REST API (no redis-py needed — works on Railway without a Redis addon)
"""

import os
import json
import logging
import asyncio
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
RK_KEYS           = "xissin:app:keys"
RK_USERS          = "xissin:app:users"
RK_BANNED         = "xissin:app:banned"
RK_LOGS           = "xissin:app:logs"
RK_SMS_STATS      = "xissin:app:sms_stats"
RK_SETTINGS       = "xissin:app:settings"
RK_ANNOUNCEMENTS  = "xissin:app:announcements"   # ← NEW
RK_SMS_HISTORY    = "xissin:app:sms_history"     # ← NEW

# ── Default server settings ───────────────────────────────────────────────────
DEFAULT_SETTINGS = {
    "maintenance":          False,
    "maintenance_message":  "Xissin is under maintenance. We'll be back shortly!",
    "min_app_version":      "1.0.0",
    "latest_app_version":   "1.0.0",
    "feature_sms":          True,
    "feature_keys":         True,
}

MAX_ANNOUNCEMENTS = 10   # Keep only the 10 most recent
MAX_HISTORY_PER_USER = 20  # Keep 20 most recent SMS sessions per user

# ── In-memory cache ───────────────────────────────────────────────────────────
_cache: dict = {}

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
        body = resp.json()
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
                        "Content-Type": "text/plain",
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

def _redis_get(key: str):
    return asyncio.run(_redis_get_async(key))

def _redis_set(key: str, data) -> bool:
    return asyncio.run(_redis_set_async(key, data))


# ── Expired key pruning ───────────────────────────────────────────────────────

def _prune_expired_keys(keys_dict: dict) -> dict:
    now = ph_now().isoformat()
    pruned = {}
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

    raw_settings = await _redis_get_async(RK_SETTINGS) or {}
    merged_settings = {**DEFAULT_SETTINGS, **raw_settings}

    _cache["keys"]          = clean_keys
    _cache["users"]         = await _redis_get_async(RK_USERS)          or {}
    _cache["banned"]        = banned_set
    _cache["logs"]          = await _redis_get_async(RK_LOGS)           or []
    _cache["sms_stats"]     = await _redis_get_async(RK_SMS_STATS)      or {}
    _cache["settings"]      = merged_settings
    _cache["announcements"] = await _redis_get_async(RK_ANNOUNCEMENTS)  or []  # ← NEW
    _cache["sms_history"]   = await _redis_get_async(RK_SMS_HISTORY)    or {}  # ← NEW

    logger.info(
        f"✅ DB loaded — keys:{len(_cache['keys'])} "
        f"users:{len(_cache['users'])} "
        f"banned:{len(_cache['banned'])} "
        f"announcements:{len(_cache['announcements'])} "
        f"maintenance:{merged_settings.get('maintenance', False)}"
    )

# ── Keys ──────────────────────────────────────────────────────────────────────

def get_all_keys() -> dict:
    return _cache.get("keys", {})

def get_key(key_str: str) -> dict | None:
    return _cache.get("keys", {}).get(key_str)

def save_key(key_str: str, metadata: dict):
    _cache.setdefault("keys", {})[key_str] = metadata
    _cache["keys"] = _prune_expired_keys(_cache["keys"])
    _redis_set(RK_KEYS, _cache["keys"])

def delete_key(key_str: str):
    _cache.setdefault("keys", {}).pop(key_str, None)
    _redis_set(RK_KEYS, _cache["keys"])

# ── Users ─────────────────────────────────────────────────────────────────────

def get_all_users() -> dict:
    return _cache.get("users", {})

def get_user(user_id: str) -> dict | None:
    return _cache.get("users", {}).get(str(user_id))

def save_user(user_id: str, data: dict):
    _cache.setdefault("users", {})[str(user_id)] = data
    _redis_set(RK_USERS, _cache["users"])

def is_banned(user_id: str) -> bool:
    return str(user_id) in _cache.get("banned", set())

def ban_user(user_id: str):
    _cache.setdefault("banned", set()).add(str(user_id))
    _redis_set(RK_BANNED, list(_cache["banned"]))

def unban_user(user_id: str):
    _cache.setdefault("banned", set()).discard(str(user_id))
    _redis_set(RK_BANNED, list(_cache["banned"]))

# ── Action Logs ───────────────────────────────────────────────────────────────

MAX_LOGS = 500

def append_log(entry: dict):
    logs = _cache.setdefault("logs", [])
    logs.append({**entry, "ts": ph_now().isoformat()})
    if len(logs) > MAX_LOGS:
        _cache["logs"] = logs[-MAX_LOGS:]
    _redis_set(RK_LOGS, _cache["logs"])

def get_logs(limit: int = 50) -> list:
    return list(reversed(_cache.get("logs", [])))[:limit]

# ── SMS Stats ─────────────────────────────────────────────────────────────────

def increment_sms_stat(user_id: str, count: int = 1):
    stats = _cache.setdefault("sms_stats", {})
    stats[str(user_id)] = stats.get(str(user_id), 0) + count
    _redis_set(RK_SMS_STATS, stats)

def get_sms_stat(user_id: str) -> int:
    return _cache.get("sms_stats", {}).get(str(user_id), 0)

# ── SMS History (per user session log) — NEW ──────────────────────────────────

def append_sms_history(user_id: str, entry: dict):
    """
    Append one SMS session to the user's history.
    entry = { ts, phone_masked, success, total }
    Keeps only MAX_HISTORY_PER_USER most recent entries.
    """
    uid = str(user_id)
    history = _cache.setdefault("sms_history", {})
    user_hist = history.get(uid, [])
    user_hist.append({**entry, "ts": ph_now().isoformat()})
    if len(user_hist) > MAX_HISTORY_PER_USER:
        user_hist = user_hist[-MAX_HISTORY_PER_USER:]
    history[uid] = user_hist
    _redis_set(RK_SMS_HISTORY, history)

def get_sms_history(user_id: str) -> list:
    """Return history for one user, newest-first."""
    uid = str(user_id)
    history = _cache.get("sms_history", {}).get(uid, [])
    return list(reversed(history))

# ── Announcements — NEW ───────────────────────────────────────────────────────

def get_announcements() -> list:
    """Return all announcements, newest-first."""
    return list(reversed(_cache.get("announcements", [])))

def add_announcement(ann: dict):
    """Add a new announcement; prune if over MAX_ANNOUNCEMENTS."""
    anns = _cache.setdefault("announcements", [])
    anns.append(ann)
    if len(anns) > MAX_ANNOUNCEMENTS:
        _cache["announcements"] = anns[-MAX_ANNOUNCEMENTS:]
    _redis_set(RK_ANNOUNCEMENTS, _cache["announcements"])

def delete_announcement(ann_id: str) -> bool:
    """Delete by short ID. Returns True if found and deleted."""
    anns = _cache.get("announcements", [])
    new_anns = [a for a in anns if a.get("id") != ann_id]
    if len(new_anns) == len(anns):
        return False  # Not found
    _cache["announcements"] = new_anns
    _redis_set(RK_ANNOUNCEMENTS, new_anns)
    return True

def clear_announcements():
    """Delete all announcements."""
    _cache["announcements"] = []
    _redis_set(RK_ANNOUNCEMENTS, [])

# ── Server Settings ───────────────────────────────────────────────────────────

def get_server_settings() -> dict:
    stored = _cache.get("settings", {})
    return {**DEFAULT_SETTINGS, **stored}

def save_server_settings(data: dict):
    merged = {**DEFAULT_SETTINGS, **data}
    _cache["settings"] = merged
    _redis_set(RK_SETTINGS, merged)
    logger.info(f"⚙️ Server settings updated: maintenance={merged.get('maintenance')}")
