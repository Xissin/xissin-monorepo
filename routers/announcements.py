"""
routers/announcements.py — Admin announcements shown in the app home screen.

Types: info | warning | error | success
Admin creates/deletes; app fetches active list.
"""

import uuid
from datetime import datetime
from zoneinfo import ZoneInfo
from typing import Optional, Literal

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

import database as db
from auth import require_admin

router = APIRouter()

PH_TZ = ZoneInfo("Asia/Manila")

AnnouncementType = Literal["info", "warning", "error", "success"]

# ── Models ────────────────────────────────────────────────────────────────────

class CreateAnnouncementRequest(BaseModel):
    title: str
    message: str
    type: AnnouncementType = "info"

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("")
def get_announcements():
    """
    Public — app fetches this on home screen load.
    Returns active announcements ordered newest-first.
    """
    return db.get_announcements()


@router.post("", dependencies=[Depends(require_admin)])
def create_announcement(req: CreateAnnouncementRequest):
    """Admin: post a new announcement to all app users."""
    if not req.title.strip():
        raise HTTPException(status_code=400, detail="Title cannot be empty")
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    ann = {
        "id":         str(uuid.uuid4())[:8],
        "title":      req.title.strip(),
        "message":    req.message.strip(),
        "type":       req.type,
        "created_at": datetime.now(PH_TZ).replace(tzinfo=None).isoformat(),
    }
    db.add_announcement(ann)
    db.append_log({"action": "announcement_created", "title": req.title, "type": req.type})
    return {"success": True, "announcement": ann}


@router.delete("/{ann_id}", dependencies=[Depends(require_admin)])
def delete_announcement(ann_id: str):
    """Admin: remove an announcement by its short ID."""
    deleted = db.delete_announcement(ann_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Announcement not found")
    db.append_log({"action": "announcement_deleted", "ann_id": ann_id})
    return {"success": True, "message": f"Announcement {ann_id} deleted"}


@router.delete("", dependencies=[Depends(require_admin)])
def clear_all_announcements():
    """Admin: remove all announcements at once."""
    db.clear_announcements()
    db.append_log({"action": "announcements_cleared"})
    return {"success": True, "message": "All announcements cleared"}
