"""
auto_edit_bot.py  —  XISSIN Auto-Edit Channel Bot
===================================================
When a key from a tracked channel post is redeemed, this bot
automatically edits that post to mark the key as claimed.

SETUP
-----
1.  @Spammersssbot must be ADMIN in @Xissin_0 with "Edit Messages" permission.
2.  Set environment variables in Railway:
        AUTO_EDIT_BOT_TOKEN   = 8402569615:AAG3td9o1iGcJqdnGZ0zYT2uC8G0yn0HYoI
        CHANNEL_USERNAME      = Xissin_0          (without @)
        ADMIN_ID              = 1910648163
        UPSTASH_REDIS_REST_URL
        UPSTASH_REDIS_REST_TOKEN

FEATURES
--------
• Auto-detects new channel posts that contain XISSIN keys
• Marks claimed keys with  ✅ (already redeemed)  in the post
• Instant edit triggered when a key is redeemed via the app
  (backend/routers/keys.py writes xissin:sync_now → bot wakes up)
• Background sync loop every 60 s as fallback
• Admin commands:
    /addpost <link>     – manually register a post
    /removepost <link>  – stop tracking a post
    /status             – show all tracked posts + claim stats
    /refresh <link>     – force-edit a specific post right now
    /synckeys           – re-scan all posts against registry
• Cleans up posts older than 30 days automatically
"""

import os
import re
import asyncio
import logging
import pickle
import base64
import time
from datetime import datetime, timedelta
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

BOT_TOKEN        = os.environ.get("AUTO_EDIT_BOT_TOKEN",
                                  "8402569615:AAG3td9o1iGcJqdnGZ0zYT2uC8G0yn0HYoI")
CHANNEL_USERNAME = os.environ.get("CHANNEL_USERNAME", "Xissin_0")   # no @
ADMIN_ID         = int(os.environ.get("ADMIN_ID", "1910648163"))
DATA_DIR         = Path(os.environ.get("AUTO_EDIT_DATA_DIR",
                                       os.environ.get("BOT_DATA_DIR", "/data")))

PH_TZ          = ZoneInfo("Asia/Manila")
KEY_PATTERN    = re.compile(r"XISSIN-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}")

# Upstash Redis keys
RK_REGISTRY      = "xissin:registry"          # read-only: key redemption data
RK_TRACKED_POSTS = "xissin:tracked_posts"     # read/write: this bot's data
RK_SYNC_NOW      = "xissin:sync_now"          # written by keys.py on redemption

TRACKED_POSTS_FILE = str(DATA_DIR / "tracked_posts.pkl")
MAX_POST_AGE_DAYS  = 30    # stop tracking posts older than this

# How often the background loop runs (seconds)
BG_POLL_INTERVAL = 60

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("auto_edit_bot")

# ──────────────────────────────────────────────────────────────────────────────
# REDIS HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def _upstash_url()   -> str: return os.environ.get("UPSTASH_REDIS_REST_URL",   "").rstrip("/")
def _upstash_token() -> str: return os.environ.get("UPSTASH_REDIS_REST_TOKEN", "")


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
        resp    = requests.post(
            f"{url}/set/{key}",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain"},
            data=encoded, timeout=10,
        )
        return resp.json().get("result") == "OK"
    except Exception as e:
        logger.error(f"Redis SET {key}: {e}")
        return False


def _redis_delete(key: str):
    url, token = _upstash_url(), _upstash_token()
    if not url or not token:
        return
    try:
        requests.get(f"{url}/del/{key}",
                     headers={"Authorization": f"Bearer {token}"}, timeout=5)
    except Exception:
        pass

# ──────────────────────────────────────────────────────────────────────────────
# TRACKED POSTS STORAGE
# tracked_posts = {
#     "<channel>/<msg_id>": {
#         "channel":       "Xissin_0",
#         "message_id":    2393,
#         "post_url":      "https://t.me/Xissin_0/2393",
#         "original_text": "...",
#         "keys_in_post":  ["XISSIN-...", ...],
#         "added_at":      datetime,
#     }
# }
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
        logger.info(f"Loaded {len(tracked_posts)} tracked posts")
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
# KEY REGISTRY HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def _load_key_registry() -> dict:
    data = _redis_get(RK_REGISTRY)
    return data if isinstance(data, dict) else {}


def _is_key_redeemed(key_str: str, registry: dict) -> tuple[bool, str]:
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
    """
    Walk through the original post text and mark any redeemed keys.
    Returns (new_text, total_keys_in_post, redeemed_count).
    """
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
                # Strip old tag then append fresh one
                clean = re.sub(
                    r"\s*[✅🔴]\s*\(already redeemed[^)]*\)|\s*\(already redeemed[^)]*\)",
                    "", line,
                ).rstrip()
                line = f"{clean}  ✅ (already redeemed)"
        new_lines.append(line)

    new_text = "\n".join(new_lines)

    # Append a claim-count footer when at least one key has been claimed
    if total_keys > 0 and redeemed_count > 0:
        footer_marker = "─── claim status ───"
        # Remove old footer if present
        if footer_marker in new_text:
            new_text = re.sub(
                r"\n+─── claim status ───.*", "", new_text, flags=re.DOTALL
            ).rstrip()
        bar  = "█" * redeemed_count + "░" * (total_keys - redeemed_count)
        new_text += (
            f"\n\n{footer_marker}\n"
            f"🔑 {redeemed_count}/{total_keys} keys claimed  {bar}"
        )

    return new_text, total_keys, redeemed_count


async def _edit_post(bot: Bot, channel: str, message_id: int,
                     original_text: str, registry: dict) -> dict:
    """
    Build and apply the edited text to a channel post.
    Returns a result dict with status / counts / error.
    """
    new_text, total, redeemed = _build_edited_text(original_text, registry)

    if new_text == original_text:
        return {"status": "no_change", "total": total, "redeemed": redeemed}

    try:
        await bot.edit_message_text(
            chat_id=f"@{channel}",
            message_id=message_id,
            text=new_text,
        )
        logger.info(f"Edited @{channel}/{message_id}  ({redeemed}/{total} redeemed)")
        return {"status": "edited", "total": total, "redeemed": redeemed}
    except Exception as e:
        err = str(e)
        # "message is not modified" is not a real error
        if "message is not modified" in err.lower():
            return {"status": "no_change", "total": total, "redeemed": redeemed}
        logger.error(f"Edit @{channel}/{message_id}: {e}")
        return {"status": "error", "error": err, "total": total, "redeemed": redeemed}

# ──────────────────────────────────────────────────────────────────────────────
# SYNC ALL TRACKED POSTS
# ──────────────────────────────────────────────────────────────────────────────

async def _sync_all_posts(bot: Bot) -> int:
    """
    Iterate all tracked posts, edit any with newly-redeemed keys.
    Prune posts older than MAX_POST_AGE_DAYS.
    Returns the number of posts actually edited.
    """
    if not tracked_posts:
        return 0

    registry = _load_key_registry()
    now      = datetime.now(PH_TZ).replace(tzinfo=None)
    edited   = 0
    to_prune = []

    for post_key, info in list(tracked_posts.items()):
        added_at = info.get("added_at")
        if added_at and (now - added_at).days > MAX_POST_AGE_DAYS:
            to_prune.append(post_key)
            continue

        result = await _edit_post(
            bot,
            info["channel"],
            info["message_id"],
            info["original_text"],
            registry,
        )
        if result["status"] == "edited":
            edited += 1

    for pk in to_prune:
        logger.info(f"Pruning old post {pk}")
        del tracked_posts[pk]

    if to_prune:
        _save_tracked_posts()

    return edited

# ──────────────────────────────────────────────────────────────────────────────
# BACKGROUND SYNC LOOP
# Runs every BG_POLL_INTERVAL seconds.
# Also wakes up immediately when keys.py writes xissin:sync_now.
# ──────────────────────────────────────────────────────────────────────────────

async def background_sync(application: Application):
    """
    Dual-mode background loop:
    • Polls xissin:sync_now every 5 s for instant-trigger
    • Falls back to full sync every BG_POLL_INTERVAL s
    """
    bot             = application.bot
    last_full_sync  = 0.0
    last_seen_trigger = None    # last value of xissin:sync_now we acted on

    logger.info("Background sync loop started")

    while True:
        try:
            now_ts = time.monotonic()

            # ── Check for instant trigger written by keys.py ──────────────
            trigger_val = _redis_get(RK_SYNC_NOW)
            if trigger_val and trigger_val != last_seen_trigger:
                last_seen_trigger = trigger_val
                logger.info(f"Instant sync triggered: {trigger_val}")
                edited = await _sync_all_posts(bot)
                logger.info(f"Instant sync done: {edited} post(s) edited")
                _redis_delete(RK_SYNC_NOW)   # clear the flag
                last_full_sync = now_ts      # reset full-sync timer

            # ── Regular 60-second fallback sync ───────────────────────────
            elif now_ts - last_full_sync >= BG_POLL_INTERVAL:
                edited = await _sync_all_posts(bot)
                if edited:
                    logger.info(f"Background sync: {edited} post(s) edited")
                last_full_sync = now_ts

        except Exception as e:
            logger.error(f"Background sync error: {e}")

        await asyncio.sleep(5)   # check every 5 s for instant triggers

# ──────────────────────────────────────────────────────────────────────────────
# URL HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def _parse_post_url(url: str) -> tuple[str, int] | None:
    """
    Parse  https://t.me/Xissin_0/2393  →  ("Xissin_0", 2393)
    Returns None if the URL doesn't match.
    """
    m = re.match(r"https?://t\.me/([^/]+)/(\d+)", url.strip())
    if not m:
        return None
    return m.group(1), int(m.group(2))

# ──────────────────────────────────────────────────────────────────────────────
# ADMIN COMMANDS
# ──────────────────────────────────────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ADMIN_ID:
        return
    await update.message.reply_text(
        "🤖 XISSIN AUTO-EDIT BOT\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "Commands:\n"
        "/addpost <link>     – Track a channel post\n"
        "/removepost <link>  – Stop tracking a post\n"
        "/status             – Show tracked posts + claim stats\n"
        "/refresh <link>     – Force-edit a post right now\n"
        "/synckeys           – Sync all posts against key registry\n",
        parse_mode=None,
    )


async def cmd_addpost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Manually register a channel post to track."""
    if update.effective_user.id != ADMIN_ID:
        return

    args = context.args
    if not args:
        await update.message.reply_text("❌ Usage: /addpost <post_link>", parse_mode=None)
        return

    url    = args[0]
    parsed = _parse_post_url(url)
    if not parsed:
        await update.message.reply_text(
            "❌ Invalid link. Expected: https://t.me/ChannelName/MessageID",
            parse_mode=None,
        )
        return

    channel, message_id = parsed
    post_key = f"{channel}/{message_id}"
    status_msg = await update.message.reply_text("⏳ Fetching post…", parse_mode=None)

    # Fetch the message to read its text
    try:
        msg = await context.bot.forward_message(
            chat_id=ADMIN_ID, from_chat_id=f"@{channel}", message_id=message_id
        )
        text = msg.text or msg.caption or ""
        # Try to delete the forwarded copy to keep admin chat clean
        try:
            await msg.delete()
        except Exception:
            pass
    except Exception as e:
        await status_msg.edit_text(
            f"❌ Could not fetch post.\nError: {e}\n\n"
            "Make sure the bot is admin in the channel.",
            parse_mode=None,
        )
        return

    keys_in_post = KEY_PATTERN.findall(text)
    if not keys_in_post:
        await status_msg.edit_text(
            "⚠️ No XISSIN keys found in that post.\nPost not tracked.",
            parse_mode=None,
        )
        return

    tracked_posts[post_key] = {
        "channel":       channel,
        "message_id":    message_id,
        "post_url":      url,
        "original_text": text,
        "keys_in_post":  keys_in_post,
        "added_at":      datetime.now(PH_TZ).replace(tzinfo=None),
    }
    _save_tracked_posts()

    registry = _load_key_registry()
    result   = await _edit_post(context.bot, channel, message_id, text, registry)

    await status_msg.edit_text(
        f"✅ POST REGISTERED!\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 {url}\n"
        f"🔑 Keys found     : {len(keys_in_post)}\n"
        f"✅ Already claimed: {result.get('redeemed', 0)}\n"
        f"🔄 Edit status    : {result['status']}\n\n"
        f"ᴛʜɪꜱ ᴘᴏꜱᴛ ᴡɪʟʟ ɴᴏᴡ ʙᴇ ᴜᴘᴅᴀᴛᴇᴅ ᴀᴜᴛᴏᴍᴀᴛɪᴄᴀʟʟʏ.",
        parse_mode=None,
    )


async def cmd_removepost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Stop tracking a post."""
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
    """Show all tracked posts and their claim stats."""
    if update.effective_user.id != ADMIN_ID:
        return

    if not tracked_posts:
        await update.message.reply_text(
            "📭 No posts are currently being tracked.\n"
            "Use /addpost <link> to start.",
            parse_mode=None,
        )
        return

    registry = _load_key_registry()
    now      = datetime.now(PH_TZ).replace(tzinfo=None)

    lines = [
        "📊 TRACKED POSTS STATUS\n━━━━━━━━━━━━━━━━━━━━━━━━━",
        f"Total tracked: {len(tracked_posts)}\n",
    ]

    for post_key, info in sorted(
        tracked_posts.items(),
        key=lambda x: x[1].get("added_at", now),
        reverse=True,
    ):
        keys_in_post = info.get("keys_in_post", [])
        claimed  = sum(1 for k in keys_in_post if _is_key_redeemed(k, registry)[0])
        age      = (now - info["added_at"]).days if info.get("added_at") else "?"
        bar_full = "█" * claimed
        bar_empty = "░" * (len(keys_in_post) - claimed)
        lines.append(
            f"🔗 {info.get('post_url', post_key)}\n"
            f"   🔑 {claimed}/{len(keys_in_post)} claimed  {bar_full}{bar_empty}\n"
            f"   📅 Added {age} day(s) ago\n"
        )

    await update.message.reply_text("\n".join(lines), parse_mode=None)


async def cmd_refresh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Force-edit a specific post right now."""
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
            "ℹ️ That post is not tracked. Use /addpost first.",
            parse_mode=None,
        )
        return

    info     = tracked_posts[post_key]
    registry = _load_key_registry()
    result   = await _edit_post(
        context.bot, channel, message_id, info["original_text"], registry
    )

    await update.message.reply_text(
        f"🔄 REFRESH RESULT\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔗 {url}\n"
        f"📊 Status   : {result['status']}\n"
        f"🔑 Total    : {result.get('total', '?')}\n"
        f"✅ Claimed  : {result.get('redeemed', '?')}\n"
        + (f"⚠️ Error    : {result.get('error')}\n" if result.get("error") else ""),
        parse_mode=None,
    )


async def cmd_synckeys(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Sync all tracked posts against current key_registry."""
    if update.effective_user.id != ADMIN_ID:
        return

    status_msg = await update.message.reply_text(
        f"🔄 Syncing {len(tracked_posts)} post(s)…",
        parse_mode=None,
    )
    edited = await _sync_all_posts(context.bot)
    await status_msg.edit_text(
        f"✅ SYNC COMPLETE\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"📝 Posts updated : {edited}\n"
        f"📊 Total tracked : {len(tracked_posts)}",
        parse_mode=None,
    )

# ──────────────────────────────────────────────────────────────────────────────
# AUTO-DETECT NEW CHANNEL POSTS
# ──────────────────────────────────────────────────────────────────────────────

async def handle_channel_post(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """
    When the bot sees a new post in @Xissin_0 that contains XISSIN keys,
    automatically register it for tracking.
    """
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
        return   # already tracking

    tracked_posts[post_key] = {
        "channel":       channel,
        "message_id":    msg.message_id,
        "post_url":      f"https://t.me/{channel}/{msg.message_id}",
        "original_text": text,
        "keys_in_post":  keys_found,
        "added_at":      datetime.now(PH_TZ).replace(tzinfo=None),
    }
    _save_tracked_posts()
    logger.info(f"Auto-registered channel post {post_key} with {len(keys_found)} key(s)")

    # Notify admin
    try:
        await context.bot.send_message(
            ADMIN_ID,
            f"📌 ɴᴇᴡ ᴘᴏꜱᴛ ᴀᴜᴛᴏ-ᴛʀᴀᴄᴋᴇᴅ\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🔗 https://t.me/{channel}/{msg.message_id}\n"
            f"🔑 Keys found: {len(keys_found)}\n"
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

    logger.info(f"auto_edit_bot started | Channel: @{CHANNEL_USERNAME}")
    app.run_polling(allowed_updates=["message", "channel_post", "callback_query"])


if __name__ == "__main__":
    main()
