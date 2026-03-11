"""
database.py — Upstash Redis persistence layer for Xissin App API
Uses REST API (no redis-py needed — works on Railway without a Redis addon)

Changes:
  - Replaced pickle with JSON (security fix — pickle allows arbitrary code execution)
  - Auto-prunes expired keys on every save (prevents Redis bloat)
"""

import os
import json
import time
import logging
import requests
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
RK_BANNED    = "xissin:app:banned"     # list of banned user_ids (JSON-safe)
RK_LOGS      = "xissin:app:logs"       # list of action log dicts
RK_SMS_STATS = "xissin:app:sms_stats"  # dict of user_id → total SMS sent

# ── In-memory cache (survives process lifetime, refreshed from Redis) ─────────
_cache: dict = {}

def ph_now() -> datetime:
    return datetime.now(PH_TZ).replace(tzinfo=None)

# ── Low-level Upstash helpers ─────────────────────────────────────────────────

def _redis_get(key: str):
    """Fetch a JSON value from Upstash Redis."""
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
        # Result is a JSON string stored as a plain string in Redis
        return json.loads(result)
    except Exception as e:
        logger.error(f"Redis GET {key} failed: {e}")
        return None


def _redis_set(key: str, data) -> bool:
    """Store a JSON-serialisable value in Upstash Redis."""
    for attempt in range(1, 4):
        try:
            encoded = json.dumps(data, default=str)  # default=str handles datetime objects
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


# ── Expired key pruning ───────────────────────────────────────────────────────

def _prune_expired_keys(keys_dict: dict) -> dict:
    """
    Remove keys that are expired AND already redeemed, or expired AND unredeemed.
    This keeps Redis storage lean — no point storing keys nobody can ever use.
    """
    now = ph_now().isoformat()
    pruned = {}
    removed = 0
    for k, meta in keys_dict.items():
        expires_at = meta.get("expires_at", "")
        try:
            if expires_at and expires_at < now:
                # Key is expired — remove it regardless of redeemed status
                removed += 1
                continue
        except Exception:
            pass
        pruned[k] = meta
    if removed:
        logger.info(f"🧹 Pruned {removed} expired key(s) from Redis")
    return pruned


# ── Public API ────────────────────────────────────────────────────────────────

def init_db():
    """Load all data from Upstash into memory on startup."""
    global _cache

    raw_keys = _redis_get(RK_KEYS) or {}
    # Prune expired keys immediately on load
    clean_keys = _prune_expired_keys(raw_keys)
    if len(clean_keys) != len(raw_keys):
        # Save pruned version back to Redis right away
        _redis_set(RK_KEYS, clean_keys)

    raw_banned = _redis_get(RK_BANNED) or []
    # banned was previously a set — handle both list and set gracefully
    if isinstance(raw_banned, list):
        banned_set = set(raw_banned)
    elif isinstance(raw_banned, set):
        banned_set = raw_banned
    else:
        banned_set = set()

    _cache["keys"]      = clean_keys
    _cache["users"]     = _redis_get(RK_USERS)     or {}
    _cache["banned"]    = banned_set
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
    # Prune expired keys every time we save to keep Redis lean
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
    # Store as list for JSON compatibility
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
