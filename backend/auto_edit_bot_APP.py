"""
auto_edit_bot.py  —  XISSIN Auto-Edit Channel Bot  (APP VERSION)
=================================================================
Belongs to: https://github.com/Xissin/xissin-monorepo
Bot token : @Xissinsbot  (8282381783:AAHs...)

FIX: This bot now ONLY reads keys stored under the prefix  app:key:<KEY>
     in Upstash Redis. It will NEVER touch tgbot: keys (Xissin-bot).
     This prevents the two systems from stepping on each other.

KEY NAMESPACING RULE
---------------------
  Xissin App keys    →  Redis key:  app:key:XISSIN-XXXX-XXXX-XXXX-XXXX
  Telegram Bot keys  →  Redis key:  tgbot:key:XISSIN-XXXX-XXXX-XXXX-XXXX

SETUP
-----
1.  Add @Xissinsbot as ADMIN in your channel with "Edit Messages" permission.
2.  Set environment variables (Railway):
        XISSIN_APP_AUTO_EDIT_BOT_TOKEN=8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY
        CHANNEL_USERNAME=Xissin_0
3.  This runs as part of the xissin-monorepo backend (start.py or Procfile).

FEATURES
--------
• Tracks every channel post that contains XISSIN-XXXX keys
• Only reacts to keys stored under  app:key:*  namespace
• Marks claimed keys with  ✅ (already redeemed)  in the post
• Admin /addpost <link>   →  manually register a post
• Admin /removepost <link>→  stop tracking a post
• Admin /status           →  show tracked posts + claim stats
• Admin /refresh <link>   →  force re-edit a post now
• Admin /synckeys         →  re-scan registry and update all posts
• Auto-detects new channel posts via channel_post handler
• Cleans up tracked posts older than 30 days automatically
• Persists tracked post data to Upstash under app:tracked_posts
"""

import os
import re
import asyncio
import logging
import pickle
import base64
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import requests
from telegram import Update, Bot
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    ContextTypes,
    filters,
)

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────────────────────────────────────

# Use a DIFFERENT env var name from the tgbot version to avoid accidents
BOT_TOKEN        = os.environ.get("XISSIN_APP_AUTO_EDIT_BOT_TOKEN",
                                  "8282381783:AAHs_2v8UGgNM48y1EulMhovNUkTw4ntpjY")
CHANNEL_USERNAME = os.environ.get("CHANNEL_USERNAME", "Xissin_0")   # no @
ADMIN_ID         = int(os.environ.get("ADMIN_ID", "1910648163"))
DATA_DIR         = Path(os.environ.get("AUTO_EDIT_DATA_DIR",
                                       os.environ.get("BOT_DATA_DIR", "/data")))

PH_TZ       = ZoneInfo("Asia/Manila")
KEY_PATTERN = re.compile(r"XISSIN-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}")

# ── Upstash Redis ──────────────────────────────────────────────────────────────
UPSTASH_URL_VAR   = "UPSTASH_REDIS_REST_URL"
UPSTASH_TOKEN_VAR = "UPSTASH_REDIS_REST_TOKEN"

# THIS BOT'S NAMESPACE — only reads/writes keys under app:*
# The tgbot bot uses  tgbot:*  — they will NEVER conflict.
APP_KEY_PREFIX   = "app:key:"           # e.g.  app:key:XISSIN-ABCD-1234-EFGH-5678
RK_TRACKED_POSTS = "app:tracked_posts"  # this bot's tracked post data
RK_REGISTRY      = "app:registry"       # app key registry (written by backend/keys.py)

TRACKED_POSTS_FILE = str(DATA_DIR / "app_tracked_posts.pkl")
MAX_POST_AGE_DAYS  = 30

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("auto_edit_bot[APP]")

# ──────────────────────────────────────────────────────────────────────────────
# REDIS HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def _upstash_url() -> str:
    return os.environ.get(UPSTASH_URL_VAR, "").rstrip("/")

def _upstash_token() -> str:
    return os.environ.get(UPSTASH_TOKEN_VAR, "")

def _redis_get(key: str):
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return None
    try:
        resp   = requests.get(f"{url}/get/{key}",
                              headers={"Authorization": f"Bearer {token}"}, timeout=10)
        result = resp.json().get("result")
        if result is None:
            return None
        return pickle.loads(base64.b64decode(result.encode("utf-8")))
    except Exception as e:
        logger.error(f"Redis GET {key}: {e}")
        return None

def _redis_set(key: str, data) -> bool:
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return False
    try:
        encoded = base64.b64encode(pickle.dumps(data)).decode("utf-8")
        resp    = requests.post(f"{url}/set/{key}",
                                headers={"Authorization": f"Bearer {token}",
                                         "Content-Type": "text/plain"},
                                data=encoded, timeout=10)
        return resp.json().get("result") == "OK"
    except Exception as e:
        logger.error(f"Redis SET {key}: {e}")
        return False

# ──────────────────────────────────────────────────────────────────────────────
# TRACKED POSTS STORAGE
# ──────────────────────────────────────────────────────────────────────────────

tracked_posts: dict = {}

def _load_tracked_posts():
    global tracked_posts
    data = _redis_get(RK_TRACKED_POSTS)
    if data is None:
        try:
            if Path(TRACKED_POSTS_FILE).exists():
                with open(TRACKED_POSTS_FILE, "rb") as f:
                    data = pickle.load(f)
        except Exception as e:
            logger.warning(f"Load tracked posts from file failed: {e}")
    if isinstance(data, dict):
        tracked_posts = data
        logger.info(f"[APP] Loaded {len(tracked_posts)} tracked posts")
    else:
        tracked_posts = {}

def _save_tracked_posts():
    _redis_set(RK_TRACKED_POSTS, tracked_posts)
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(TRACKED_POSTS_FILE, "wb") as f:
            pickle.dump(tracked_posts, f)
    except Exception as e:
        logger.warning(f"Save tracked posts to file failed: {e}")

# ──────────────────────────────────────────────────────────────────────────────
# KEY REGISTRY HELPERS  — ONLY reads  app:registry  from Redis
# ──────────────────────────────────────────────────────────────────────────────

def _load_key_registry() -> dict:
    """
    Load the app key registry from Upstash.
    Only keys stored under  app:registry  (written by backend/keys.py).
    TGBot keys under  tgbot:registry  are IGNORED entirely.
    """
    data = _redis_get(RK_REGISTRY)
    if isinstance(data, dict):
        return data
    # Fallback: try old shared registry but filter to app keys only
    old_registry = _redis_get("xissin:registry")
    if isinstance(old_registry, dict):
        filtered = {
            k: v for k, v in old_registry.items()
            if v.get("source", "") == "app"
        }
        logger.info(f"[APP] Fallback registry: {len(filtered)} app keys loaded")
        return filtered
    return {}

def _is_key_redeemed(key_str: str, registry: dict) -> tuple[bool, str]:
    """Returns (redeemed: bool, display_name: str)."""
    meta = registry.get(key_str)
    if not meta or not meta.get("redeemed"):
        return False, ""
    uname = meta.get("redeemed_by_username") or ""
    uid   = meta.get("redeemed_by", "")
    if uname and uname != "N/A":
        display = f"@{uname}"
    elif uid:
        display = f"ID:{uid}"
    else:
        display = "someone"
    return True, display

# ──────────────────────────────────────────────────────────────────────────────
# POST EDITING LOGIC
# ──────────────────────────────────────────────────────────────────────────────

def _build_edited_text(original_text: str, registry: dict) -> tuple[str, int, int]:
    """Scan the post text and mark redeemed app keys. Returns (new_text, total, redeemed)."""
    lines          = original_text.split("\n")
    total_keys     = 0
    redeemed_count = 0
    new_lines      = []

    for line in lines:
        match = KEY_PATTERN.search(line)
        if match:
            key_str = match.group(0)
            total_keys += 1
            redeemed, _ = _is_key_redeemed(key_str, registry)
            if redeemed:
                redeemed_count += 1
                clean_line = re.sub(
                    r"\s*[✅🔴]\s*\(already redeemed[^\)]*\)|\s*\(already redeemed[^\)]*\)",
                    "", line
                ).rstrip()
                line = f"{clean_line}  ✅ (already redeemed)"
        new_lines.append(line)

    new_text = "\n".join(new_lines)

    if total_keys > 0 and redeemed_count > 0:
        summary  = f"\n\n📊 {redeemed_count}/{total_keys} keys claimed"
        new_text = re.sub(r"\n+📊 \d+/\d+ keys claimed.*$", "", new_text, flags=re.MULTILINE)
        new_text = new_text.rstrip() + summary

    return new_text, total_keys, redeemed_count


async def _edit_post(bot: Bot, channel: str, message_id: int,
                     original_text: str, registry: dict) -> dict:
    """Edit the channel post. Returns a result dict."""
    new_text, total_keys, redeemed_count = _build_edited_text(original_text, registry)

    if new_text == original_text:
        return {"status": "unchanged", "total": total_keys, "redeemed": redeemed_count}

    try:
        await bot.edit_message_text(
            chat_id=f"@{channel}",
            message_id=message_id,
            text=new_text,
        )
        return {"status": "edited", "total": total_keys, "redeemed": redeemed_count}
    except Exception as e:
        err = str(e)
        if "message is not modified" in err.lower():
            return {"status": "unchanged", "total": total_keys, "redeemed": redeemed_count}
        if "message to edit not found" in err.lower():
            return {"status": "not_found", "total": total_keys, "redeemed": redeemed_count}
        logger.error(f"Edit post {channel}/{message_id}: {e}")
        return {"status": "error", "error": err[:80], "total": total_keys, "redeemed": redeemed_count}


def _parse_post_url(url: str) -> tuple[str, int] | None:
    m = re.match(r"https?://t\.me/([^/]+)/(\d+)", url.strip())
    return (m.group(1), int(m.group(2))) if m else None

# ──────────────────────────────────────────────────────────────────────────────
# BACKGROUND SYNC
# ──────────────────────────────────────────────────────────────────────────────

async def _sync_all_posts(bot: Bot) -> int:
    """Re-check every tracked post against app registry. Returns edited count."""
    registry  = _load_key_registry()
    now       = datetime.now(PH_TZ).replace(tzinfo=None)
    edited    = 0
    to_remove = []

    for post_key, info in list(tracked_posts.items()):
        added_at = info.get("added_at")
        if added_at and (now - added_at).days > MAX_POST_AGE_DAYS:
            to_remove.append(post_key)
            continue

        result = await _edit_post(bot, info["channel"], info["message_id"],
                                  info["original_text"], registry)
        if result["status"] == "edited":
            edited += 1
            logger.info(f"[APP] Synced {post_key}: {result['redeemed']}/{result['total']} claimed")
        elif result["status"] == "not_found":
            to_remove.append(post_key)

    for k in to_remove:
        del tracked_posts[k]

    if to_remove or edited:
        _save_tracked_posts()

    return edited


async def background_sync(app: Application):
    """Runs forever, syncing app posts every 30 seconds."""
    await asyncio.sleep(15)
    while True:
        try:
            edited = await _sync_all_posts(app.bot)
            if edited:
                logger.info(f"[APP] Background sync: edited {edited} post(s)")
        except Exception as e:
            logger.error(f"[APP] Background sync error: {e}")
        await asyncio.sleep(30)

# ──────────────────────────────────────────────────────────────────────────────
# COMMAND HANDLERS
# ──────────────────────────────────────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return
    await update.message.reply_text(
        "🤖 XISSIN AUTO-EDIT BOT  [APP]\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        "⚠️ This bot ONLY tracks App keys (app:key:*)\n"
        "   TGBot keys (tgbot:key:*) are completely ignored.\n\n"
        "Commands:\n"
        "/addpost <link>     — track a channel post\n"
        "/removepost <link>  — stop tracking a post\n"
        "/status             — show all tracked posts\n"
        "/refresh <link>     — force re-edit a post now\n"
        "/synckeys           — sync all tracked posts\n"
        "/help               — show this message\n\n"
        f"📡 Channel  : @{CHANNEL_USERNAME}\n"
        f"🔑 Namespace: app:key:*\n"
        f"🔄 Sync rate: every 30 seconds\n"
        f"📅 Auto-expire: {MAX_POST_AGE_DAYS} days",
        parse_mode=None,
    )


async def cmd_addpost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return

    args = context.args
    if not args:
        await update.message.reply_text(
            "❌ Usage: /addpost <telegram_post_link>\n"
            "Example: /addpost https://t.me/Xissin_0/2393",
            parse_mode=None,
        )
        return

    url    = args[0]
    parsed = _parse_post_url(url)
    if not parsed:
        await update.message.reply_text(
            "❌ Invalid link. Expected: https://t.me/ChannelUsername/MessageID",
            parse_mode=None,
        )
        return

    channel, message_id = parsed
    post_key = f"{channel}/{message_id}"

    if post_key in tracked_posts:
        await update.message.reply_text(f"ℹ️ Post already tracked: {url}", parse_mode=None)
        return

    status_msg = await update.message.reply_text("⏳ Fetching post...", parse_mode=None)
    try:
        msg = await context.bot.forward_message(
            chat_id=update.effective_chat.id,
            from_chat_id=f"@{channel}",
            message_id=message_id,
        )
        original_text = msg.text or msg.caption or ""
        await msg.delete()
    except Exception as e:
        await status_msg.edit_text(
            f"❌ Could not fetch post: {e}\n\n"
            "Make sure this bot is admin in the channel with 'Edit Messages' permission.",
            parse_mode=None,
        )
        return

    if not original_text:
        await status_msg.edit_text("❌ Post has no text content.", parse_mode=None)
        return

    keys_in_post = KEY_PATTERN.findall(original_text)
    if not keys_in_post:
        await status_msg.edit_text(
            "⚠️ No XISSIN keys found in that post.\n"
            "Post registered anyway for monitoring.",
            parse_mode=None,
        )

    tracked_posts[post_key] = {
        "channel":       channel,
        "message_id":    message_id,
        "post_url":      url,
        "original_text": original_text,
        "keys_in_post":  keys_in_post,
        "added_at":      datetime.now(PH_TZ).replace(tzinfo=None),
    }
    _save_tracked_posts()

    registry = _load_key_registry()
    result   = await _edit_post(context.bot, channel, message_id, original_text, registry)

    await status_msg.edit_text(
        f"✅ POST REGISTERED! [APP NAMESPACE]\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 {url}\n"
        f"🔑 Keys found    : {len(keys_in_post)}\n"
        f"✅ Already claimed: {result.get('redeemed', 0)}\n"
        f"🔄 Edit status   : {result['status']}\n\n"
        f"ᴛʜɪꜱ ᴘᴏꜱᴛ ᴡɪʟʟ ɴᴏᴡ ʙᴇ ᴜᴘᴅᴀᴛᴇᴅ ᴀᴜᴛᴏᴍᴀᴛɪᴄᴀʟʟʏ.",
        parse_mode=None,
    )


async def cmd_removepost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return

    args = context.args
    if not args:
        await update.message.reply_text("❌ Usage: /removepost <post_link>", parse_mode=None)
        return

    url    = args[0]
    parsed = _parse_post_url(url)
    if not parsed:
        await update.message.reply_text("❌ Invalid link format.", parse_mode=None)
        return

    channel, message_id = parsed
    post_key = f"{channel}/{message_id}"

    if post_key not in tracked_posts:
        await update.message.reply_text("ℹ️ That post is not being tracked.", parse_mode=None)
        return

    del tracked_posts[post_key]
    _save_tracked_posts()
    await update.message.reply_text(f"✅ Stopped tracking:\n{url}", parse_mode=None)


async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return

    if not tracked_posts:
        await update.message.reply_text(
            "📭 No posts are currently being tracked.\n"
            "Use /addpost <link> to start tracking.",
            parse_mode=None,
        )
        return

    registry = _load_key_registry()
    now      = datetime.now(PH_TZ).replace(tzinfo=None)

    lines = [
        "📊 TRACKED POSTS STATUS  [APP]\n━━━━━━━━━━━━━━━━━━━━━━━━━",
        f"Total tracked: {len(tracked_posts)}\n",
    ]

    for post_key, info in sorted(tracked_posts.items(),
                                  key=lambda x: x[1].get("added_at", now), reverse=True):
        keys_in_post = info.get("keys_in_post", [])
        claimed      = sum(1 for k in keys_in_post if _is_key_redeemed(k, registry)[0])
        age          = (now - info["added_at"]).days if info.get("added_at") else "?"
        bar_full     = "█" * claimed
        bar_empty    = "░" * (len(keys_in_post) - claimed)
        lines.append(
            f"🔗 {info.get('post_url', post_key)}\n"
            f"   🔑 {claimed}/{len(keys_in_post)} claimed  {bar_full}{bar_empty}\n"
            f"   📅 Added {age} day(s) ago\n"
        )

    await update.message.reply_text("\n".join(lines), parse_mode=None)


async def cmd_refresh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return

    args = context.args
    if not args:
        await update.message.reply_text("❌ Usage: /refresh <post_link>", parse_mode=None)
        return

    url    = args[0]
    parsed = _parse_post_url(url)
    if not parsed:
        await update.message.reply_text("❌ Invalid link format.", parse_mode=None)
        return

    channel, message_id = parsed
    post_key = f"{channel}/{message_id}"

    if post_key not in tracked_posts:
        await update.message.reply_text(
            "ℹ️ That post is not tracked. Use /addpost first.", parse_mode=None
        )
        return

    info     = tracked_posts[post_key]
    registry = _load_key_registry()
    result   = await _edit_post(context.bot, channel, message_id, info["original_text"], registry)

    await update.message.reply_text(
        f"🔄 REFRESH RESULT  [APP]\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 {url}\n"
        f"📊 Status   : {result['status']}\n"
        f"🔑 Total    : {result.get('total', '?')}\n"
        f"✅ Claimed  : {result.get('redeemed', '?')}\n"
        + (f"⚠️ Error    : {result.get('error')}\n" if result.get("error") else ""),
        parse_mode=None,
    )


async def cmd_synckeys(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return

    status_msg = await update.message.reply_text(
        f"🔄 Syncing {len(tracked_posts)} post(s)…", parse_mode=None
    )
    edited = await _sync_all_posts(context.bot)
    await status_msg.edit_text(
        f"✅ SYNC COMPLETE  [APP]\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📝 Posts updated : {edited}\n"
        f"📊 Total tracked : {len(tracked_posts)}",
        parse_mode=None,
    )

# ──────────────────────────────────────────────────────────────────────────────
# AUTO-DETECT NEW CHANNEL POSTS
# ──────────────────────────────────────────────────────────────────────────────

async def handle_channel_post(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Auto-register new channel posts that contain XISSIN keys."""
    msg = update.channel_post
    if not msg:
        return

    chat  = msg.chat
    uname = (chat.username or "").lower()
    if uname != CHANNEL_USERNAME.lower():
        return

    text       = msg.text or msg.caption or ""
    keys_found = KEY_PATTERN.findall(text)
    if not keys_found:
        return

    channel  = chat.username
    post_key = f"{channel}/{msg.message_id}"

    if post_key in tracked_posts:
        return

    tracked_posts[post_key] = {
        "channel":       channel,
        "message_id":    msg.message_id,
        "post_url":      f"https://t.me/{channel}/{msg.message_id}",
        "original_text": text,
        "keys_in_post":  keys_found,
        "added_at":      datetime.now(PH_TZ).replace(tzinfo=None),
    }
    _save_tracked_posts()
    logger.info(f"[APP] Auto-registered {post_key} with {len(keys_found)} key(s)")

    try:
        await context.bot.send_message(
            ADMIN_ID,
            f"📌 ɴᴇᴡ ᴘᴏꜱᴛ ᴀᴜᴛᴏ-ᴛʀᴀᴄᴋᴇᴅ  [APP]\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🔗 https://t.me/{channel}/{msg.message_id}\n"
            f"🔑 Keys found: {len(keys_found)}\n"
            f"🔑 Namespace : app:key:*\n"
            f"🔄 Will update when keys are redeemed.",
            parse_mode=None,
        )
    except Exception:
        pass

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

def main():
    _load_tracked_posts()

    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start",      cmd_start))
    app.add_handler(CommandHandler("help",       cmd_start))
    app.add_handler(CommandHandler("addpost",    cmd_addpost))
    app.add_handler(CommandHandler("removepost", cmd_removepost))
    app.add_handler(CommandHandler("status",     cmd_status))
    app.add_handler(CommandHandler("refresh",    cmd_refresh))
    app.add_handler(CommandHandler("synckeys",   cmd_synckeys))

    app.add_handler(MessageHandler(filters.ChatType.CHANNEL, handle_channel_post))

    async def post_init(application: Application):
        asyncio.create_task(background_sync(application))

    app.post_init = post_init

    logger.info(f"[APP] Starting auto_edit_bot | Channel: @{CHANNEL_USERNAME} | Namespace: app:key:*")
    app.run_polling(allowed_updates=["message", "channel_post", "callback_query"])


if __name__ == "__main__":
    main()
