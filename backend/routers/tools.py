"""
routers/tools.py — Local Tool Usage Logs

Receives fire-and-forget usage stats from URL Remover and Dup Remover.
No actual tool logic runs here — the tools run 100% on-device.
This endpoint only records: which tool, how many lines in/out.

NOTE: We deliberately do NOT log the actual file content or filenames.
That is the user's private data. We only store counts.

POST /api/tools/log   — called by app after tool finishes
GET  /api/tools/logs  — admin: full history
GET  /api/tools/stats — admin: totals by tool and user
"""

from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel, Field, field_validator
from typing import Literal
from datetime import datetime
from zoneinfo import ZoneInfo

import database as db
from limiter import limiter
from auth import require_admin, verify_app_request

router = APIRouter()
PH_TZ  = ZoneInfo("Asia/Manila")

_VALID_TOOLS = {"url_remover", "dup_remover"}


def _ph_now() -> str:
    return datetime.now(PH_TZ).replace(tzinfo=None).isoformat()


# ── Models ─────────────────────────────────────────────────────────────────────

class ToolLogRequest(BaseModel):
    user_id:       str = Field(..., min_length=1, max_length=50)
    tool:          str = Field(..., min_length=1, max_length=30)
    input_count:   int = Field(default=0, ge=0)
    output_count:  int = Field(default=0, ge=0)
    removed_count: int = Field(default=0, ge=0)

    @field_validator("user_id")
    @classmethod
    def clean_user_id(cls, v: str) -> str:
        return v.strip()

    @field_validator("tool")
    @classmethod
    def validate_tool(cls, v: str) -> str:
        v = v.strip().lower()
        if v not in _VALID_TOOLS:
            raise ValueError(f"Unknown tool '{v}'. Must be one of: {_VALID_TOOLS}")
        return v


# ── POST /tools/log — called by app, fire-and-forget ──────────────────────────

@router.post("/log", dependencies=[Depends(verify_app_request)])
@limiter.limit("30/minute")
async def log_tool_usage(req: ToolLogRequest, request: Request):
    """
    Records a local tool usage event.
    No file content is stored — only counts.
    """
    user = db.get_user(req.user_id)
    if not user:
        raise HTTPException(status_code=403, detail="User not registered.")
    if db.is_banned(req.user_id):
        raise HTTPException(status_code=403, detail="Your account has been banned.")

    removal_rate = (
        round(req.removed_count / req.input_count * 100, 1)
        if req.input_count > 0 else 0.0
    )

    # Write to activity log (appears in Activity Logs page)
    db.append_log({
        "action":        "tool_used",
        "user_id":       req.user_id,
        "tool":          req.tool,
        "input_count":   req.input_count,
        "output_count":  req.output_count,
        "removed_count": req.removed_count,
        "removal_rate":  removal_rate,
    })

    # Write to dedicated tools log (appears in Tool Logs page)
    _append_tool_log({
        "user_id":       req.user_id,
        "tool":          req.tool,
        "input_count":   req.input_count,
        "output_count":  req.output_count,
        "removed_count": req.removed_count,
        "removal_rate":  removal_rate,
        "ts":            _ph_now(),
    })

    return {"success": True, "logged": True}


# ── Redis helpers ─────────────────────────────────────────────────────────────
# Store tool logs in a Redis list: "tools_log" — same pattern as sms/ngl logs.

_TOOLS_LOG_KEY = "tools_log"
_MAX_TOOLS_LOG = 10_000


def _append_tool_log(entry: dict) -> None:
    """Push a tool log entry to Redis (lpush + ltrim to cap at 10k)."""
    import json
    try:
        r = db._redis()           # reuse whatever redis client db.py exposes
        r.lpush(_TOOLS_LOG_KEY, json.dumps(entry))
        r.ltrim(_TOOLS_LOG_KEY, 0, _MAX_TOOLS_LOG - 1)
    except Exception:
        pass                      # fire-and-forget — never crash the endpoint


def _get_tool_logs(limit: int = 10_000) -> list:
    """Fetch up to `limit` tool log entries from Redis."""
    import json
    try:
        r    = db._redis()
        raw  = r.lrange(_TOOLS_LOG_KEY, 0, limit - 1)
        return [json.loads(item) for item in raw]
    except Exception:
        return []


# ── GET /tools/logs — admin ───────────────────────────────────────────────────

@router.get("/logs", dependencies=[Depends(require_admin)])
def get_tool_logs(limit: int = 10_000):
    """Admin: full tool usage log history."""
    logs = _get_tool_logs(limit=limit)
    return {"total": len(logs), "logs": logs}


# ── GET /tools/stats — admin ──────────────────────────────────────────────────

@router.get("/stats", dependencies=[Depends(require_admin)])
def get_tool_stats():
    """Admin: aggregate stats by tool and by user."""
    logs = _get_tool_logs(limit=10_000)

    url_logs = [l for l in logs if l.get("tool") == "url_remover"]
    dup_logs = [l for l in logs if l.get("tool") == "dup_remover"]

    def _agg(tool_logs: list) -> dict:
        if not tool_logs:
            return {
                "uses": 0, "total_input": 0,
                "total_removed": 0, "avg_removal_rate": 0.0,
            }
        return {
            "uses":              len(tool_logs),
            "total_input":       sum(l.get("input_count",   0) for l in tool_logs),
            "total_removed":     sum(l.get("removed_count", 0) for l in tool_logs),
            "avg_removal_rate":  round(
                sum(l.get("removal_rate", 0) for l in tool_logs) / len(tool_logs), 1
            ),
        }

    # Per-user breakdown
    user_map: dict = {}
    for l in logs:
        uid  = l.get("user_id", "")
        tool = l.get("tool", "")
        if uid not in user_map:
            user_map[uid] = {"url_remover": 0, "dup_remover": 0, "total": 0}
        user_map[uid][tool] = user_map[uid].get(tool, 0) + 1
        user_map[uid]["total"] += 1

    users_db = db.get_all_users()
    by_user  = sorted(
        [
            {
                "user_id":     uid,
                "username":    users_db.get(uid, {}).get("username", ""),
                "url_remover": counts.get("url_remover", 0),
                "dup_remover": counts.get("dup_remover", 0),
                "total":       counts.get("total", 0),
            }
            for uid, counts in user_map.items()
        ],
        key=lambda x: x["total"],
        reverse=True,
    )

    return {
        "total_uses":  len(logs),
        "url_remover": _agg(url_logs),
        "dup_remover": _agg(dup_logs),
        "by_user":     by_user,
    }
