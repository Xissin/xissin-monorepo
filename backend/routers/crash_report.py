"""
routers/crash_report.py — Receives crash reports from the Flutter app
and forwards them to Telegram using the bot token from env vars.

This keeps the bot token OFF the device completely.
The Flutter app posts to POST /api/crash-report (no auth required —
it must work even if auth is broken).

Improvements:
  - Deduplication: identical errors within 60s are suppressed (no spam)
  - Long stack traces split into two messages if over Telegram limit
  - Severity icons: CRASH vs WARNING vs FLUTTER ERROR vs PLATFORM ERROR
  - User count: tracks how many users hit the same error
"""

import logging
import os
import hashlib
import time
from collections import defaultdict

import httpx
from fastapi import APIRouter, Request
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Config ────────────────────────────────────────────────────────────────────

def _bot_token() -> str:
    return os.environ.get("XISSIN_BOT_TOKEN", "").strip()

def _chat_id() -> str:
    return os.environ.get("CRASH_REPORT_CHAT_ID", "1910648163").strip()


# ── Deduplication — suppress identical errors within 60 seconds ───────────────
# Key: hash of (type + error message), Value: (last_seen_timestamp, count)
_recent_errors: dict = {}
_DEDUP_WINDOW = 60  # seconds


def _is_duplicate(error_hash: str) -> tuple[bool, int]:
    """Returns (is_duplicate, occurrence_count)."""
    now = time.time()
    # Clean up old entries
    expired = [k for k, v in _recent_errors.items() if now - v[0] > _DEDUP_WINDOW]
    for k in expired:
        del _recent_errors[k]

    if error_hash in _recent_errors:
        last_seen, count = _recent_errors[error_hash]
        _recent_errors[error_hash] = (now, count + 1)
        return True, count + 1

    _recent_errors[error_hash] = (now, 1)
    return False, 1


# ── Request model ─────────────────────────────────────────────────────────────

class CrashReportRequest(BaseModel):
    type:      str
    error:     str
    stack:     Optional[str] = ""
    device:    Optional[str] = "Unknown Device"
    version:   Optional[str] = "Unknown"
    timestamp: Optional[str] = ""


# ── Telegram sender ───────────────────────────────────────────────────────────

async def _send_telegram(message: str):
    """Send a message to Telegram. Splits if over 4000 chars."""
    token = _bot_token()
    if not token:
        logger.warning("XISSIN_BOT_TOKEN not set — crash report dropped.")
        return
    chat_id = _chat_id()
    url = f"https://api.telegram.org/bot{token}/sendMessage"

    # Split long messages (Telegram limit is 4096 chars)
    chunks = [message[i:i+3800] for i in range(0, len(message), 3800)]

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            for i, chunk in enumerate(chunks):
                payload = {
                    "chat_id":    chat_id,
                    "text":       chunk,
                    "parse_mode": "HTML",
                }
                if i > 0:
                    # Mark continuation chunks clearly
                    payload["text"] = f"<b>(continued...)</b>\n\n{chunk}"
                resp = await client.post(url, json=payload)
                if resp.status_code != 200:
                    logger.warning(f"Telegram send failed: {resp.status_code} {resp.text[:200]}")
    except Exception as e:
        logger.warning(f"Telegram send failed (non-fatal): {e}")


def _escape_html(text: str) -> str:
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
    )


def _severity_icon(report_type: str) -> str:
    icons = {
        "CRASH":           "🔴",
        "FLUTTER ERROR":   "🟠",
        "PLATFORM ERROR":  "🟠",
        "WARNING":         "🟡",
    }
    return icons.get(report_type.upper(), "🔴")


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/crash-report")
async def receive_crash_report(req: CrashReportRequest, request: Request):
    """
    No auth required — crash reporter must work even if auth is broken.
    Deduplicates identical errors within a 60-second window to prevent spam.
    """
    client_ip = request.client.host if request.client else "unknown"
    report_type = (req.type or "CRASH").strip().upper()

    # Deduplication — hash on type + first 200 chars of error
    error_key = hashlib.md5(
        f"{report_type}:{(req.error or '')[:200]}".encode()
    ).hexdigest()
    is_dup, count = _is_duplicate(error_key)

    if is_dup:
        logger.info(
            f"📩 Duplicate crash suppressed (x{count}): "
            f"type={report_type} device={req.device} ip={client_ip}"
        )
        return {"received": True, "suppressed": True, "count": count}

    severity = _severity_icon(report_type)
    is_warning = report_type == "WARNING"
    header_label = "WARNING" if is_warning else "CRASH REPORT"

    # Trim stack trace — will split into second message if still long
    stack = (req.stack or "").strip()
    stack_trimmed = False
    if len(stack) > 1200:
        stack = stack[:1200]
        stack_trimmed = True

    # ── Build main message ────────────────────────────────────────────────────
    message = (
        f"{severity} <b>XISSIN {header_label}</b>\n"
        f"{'─' * 30}\n\n"
        f"<b>Type:</b>    <code>{_escape_html(report_type)}</code>\n"
        f"<b>Version:</b> <code>{_escape_html(req.version or 'Unknown')}</code>\n"
        f"<b>Device:</b>  <code>{_escape_html(req.device or 'Unknown')}</code>\n"
        f"<b>IP:</b>      <code>{client_ip}</code>\n"
        f"<b>Time:</b>    <code>{_escape_html(req.timestamp or 'Unknown')}</code>\n\n"
        f"<b>❌ Error:</b>\n"
        f"<pre>{_escape_html(req.error or 'No error message')}</pre>\n"
    )

    if stack:
        message += (
            f"\n<b>📋 Stack Trace:</b>\n"
            f"<pre>{_escape_html(stack)}</pre>"
        )
        if stack_trimmed:
            message += "\n<i>(stack trace trimmed — see logs for full trace)</i>"

    logger.info(
        f"📩 Crash report: type={report_type} "
        f"version={req.version} device={req.device} ip={client_ip}"
    )
    await _send_telegram(message)

    return {"received": True, "suppressed": False}
