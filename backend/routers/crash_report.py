"""
routers/crash_report.py — Receives crash reports from the Flutter app
and forwards them to Telegram using the bot token from env vars.

This keeps the bot token OFF the device completely.
The Flutter app posts to POST /api/crash-report (no auth required —
it's low-sensitivity and must work even if auth is broken).
"""

import hashlib
import hmac
import logging
import os
import time

import httpx
from fastapi import APIRouter, Request
from pydantic import BaseModel
from typing import Optional

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Config — read from Railway env vars ──────────────────────────────────────

def _bot_token() -> str:
    return os.environ.get("XISSIN_BOT_TOKEN", "").strip()

def _chat_id() -> str:
    return os.environ.get("CRASH_REPORT_CHAT_ID", "1910648163").strip()


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
    token = _bot_token()
    if not token:
        logger.warning("XISSIN_BOT_TOKEN not set — crash report dropped.")
        return
    chat_id = _chat_id()
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            await client.post(url, json={
                "chat_id":    chat_id,
                "text":       message,
                "parse_mode": "HTML",
            })
    except Exception as e:
        logger.warning(f"Telegram send failed (non-fatal): {e}")


def _escape_html(text: str) -> str:
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
    )


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/crash-report")
async def receive_crash_report(req: CrashReportRequest, request: Request):
    """
    No auth required — crash reporter must work even in broken states.
    Rate limit is handled by slowapi on the limiter in main_backend.py.
    """
    client_ip = request.client.host if request.client else "unknown"

    icon = "🚨" if req.type not in ("WARNING",) else "⚠️"
    label = "CRASH REPORT" if req.type != "WARNING" else "WARNING"

    # Trim stack to avoid Telegram 4096-char limit
    stack = req.stack or ""
    if len(stack) > 800:
        stack = stack[:800] + "\n... (trimmed)"

    message = (
        f"{icon} <b>XISSIN {label}</b>\n\n"
        f"🔴 <b>Type:</b> {_escape_html(req.type)}\n"
        f"📦 <b>Version:</b> {_escape_html(req.version or 'Unknown')}\n"
        f"📱 <b>Device:</b> {_escape_html(req.device or 'Unknown')}\n"
        f"🌐 <b>IP:</b> {client_ip}\n"
        f"🕐 <b>Time:</b> {_escape_html(req.timestamp or '')}\n\n"
        f"❌ <b>Error:</b>\n<code>{_escape_html(req.error)}</code>\n"
    )

    if stack:
        message += f"\n📋 <b>Stack Trace:</b>\n<code>{_escape_html(stack)}</code>\n"

    logger.info(f"📩 Crash report received: type={req.type} device={req.device} ip={client_ip}")
    await _send_telegram(message)

    return {"received": True}
