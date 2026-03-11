"""
database.py — Upstash Redis persistence layer for Xissin App API
Uses REST API (no redis-py needed — works on Railway without a Redis addon)
"""

import os
import json
import time
import logging
import requests
import base64
import pickle
from datetime import datetime
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)

PH_TZ = ZoneInfo("Asia/Manila")

# ── Upstash credentials ───────────────────────────────────────────────────────
# ⚠️ NEVER hardcode these — always set them in Railway environment variables!

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
RK_KEYS      = "xissin:app:keys"       # dict of key_string → key metadata
RK_USERS     = "xissin:app:users"      # dict of user_id → user metadata
RK_BANNED    = "xissin:app:banned"     # set of banned user_ids
RK_LOGS      = "xissin:app:logs"       # list of action log dicts
RK_SMS_STATS = "xissin:app:sms_stats"  # dict of user_id → total SMS sent

# ── In-memory cache (survives process lifetime, refreshed from Redis) ─────────
_cache: dict = {}

def ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Low-level Upstash helpers ─────────────────────────────────────────────────

def _redis_get(key: str):
    try:
        resp = requests.get(
            f"{_url()}/get/{key}",
            headers={"Authorization": f"Bearer {_token()}"},
            timeout=10,
        )
        if resp.status_code != 200:
            return None
        body = resp.json()
        result = body.get("result")
        if result is None:
            return None
        return pickle.loads(base64.b64decode(result.encode("utf-8")))
    except Exception as e:
        logger.error(f"Redis GET {key} failed: {e}")
        return None


def _redis_set(key: str, data) -> bool:
    for attempt in range(1, 4):
        try:
            encoded = base64.b64encode(pickle.dumps(data)).decode("utf-8")
            resp = requests.post(
                f"{_url()}/set/{key}",
                headers={"Authorization": f"Bearer {_token()}", "Content-Type": "text/plain"},
                data=encoded,
                timeout=10,
            )
            if resp.status_code == 200 and resp.json().get("result") == "OK":
                return True
        except Exception as e:
            logger.error(f"Redis SET {key} attempt {attempt} failed: {e}")
            if attempt < 3:
                time.sleep(attempt)
    return False


# ── Public API ────────────────────────────────────────────────────────────────

def init_db():
    """Load all data from Upstash into memory on startup."""
    global _cache
    _cache["keys"]      = _redis_get(RK_KEYS)      or {}
    _cache["users"]     = _redis_get(RK_USERS)     or {}
    _cache["banned"]    = _redis_get(RK_BANNED)    or set()
    _cache["logs"]      = _redis_get(RK_LOGS)      or []
    _cache["sms_stats"] = _redis_get(RK_SMS_STATS) or {}
    logger.info(
        f"✅ DB loaded — keys:{len(_cache['keys'])} "
        f"users:{len(_cache['users'])} "
        f"banned:{len(_cache['banned'])}"
    )

# ── Keys ──────────────────────────────────────────────────────────────────────

def get_all_keys() -> dict:
    return _cache.get("keys", {})

def get_key(key_str: str) -> dict | None:
    return _cache.get("keys", {}).get(key_str)

def save_key(key_str: str, metadata: dict):
    _cache.setdefault("keys", {})[key_str] = metadata
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
    _redis_set(RK_BANNED, _cache["banned"])

def unban_user(user_id: str):
    _cache.setdefault("banned", set()).discard(str(user_id))
    _redis_set(RK_BANNED, _cache["banned"])

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
