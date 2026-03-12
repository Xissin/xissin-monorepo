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
RK_KEYS      = "xissin:app:keys"
RK_USERS     = "xissin:app:users"
RK_BANNED    = "xissin:app:banned"
RK_LOGS      = "xissin:app:logs"
RK_SMS_STATS = "xissin:app:sms_stats"

# ── In-memory cache ───────────────────────────────────────────────────────────
_cache: dict = {}

def ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Low-level async Upstash helpers ──────────────────────────────────────────

async def _redis_get_async(key: str):
    """Async fetch a JSON value from Upstash Redis."""
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
    """Async store a JSON value in Upstash Redis."""
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


# ── Sync wrappers (called from FastAPI sync route handlers) ───────────────────
# FastAPI runs sync routes in a threadpool — asyncio.run() is safe there
# because there is NO running event loop in that thread.

def _redis_get(key: str):
    return asyncio.run(_redis_get_async(key))

def _redis_set(key: str, data) -> bool:
    return asyncio.run(_redis_set_async(key, data))


# ── Expired key pruning ───────────────────────────────────────────────────────

def _prune_expired_keys(keys_dict: dict) -> dict:
    """Remove expired keys to keep Redis storage lean."""
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
    """
    ✅ ASYNC — awaited from FastAPI lifespan.
    Loads all data from Upstash into in-memory cache on startup.
    """
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

    _cache["keys"]      = clean_keys
    _cache["users"]     = await _redis_get_async(RK_USERS)     or {}
    _cache["banned"]    = banned_set
    _cache["logs"]      = await _redis_get_async(RK_LOGS)      or []
    _cache["sms_stats"] = await _redis_get_async(RK_SMS_STATS) or {}

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
