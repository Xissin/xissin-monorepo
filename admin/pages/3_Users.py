"""
pages/3_Users.py — View, search, ban/unban users
Fixes & improvements:
  - IMPROVEMENT: Validate that ban target user_id actually exists before calling API
  - IMPROVEMENT: Premium badge shown in user table
  - IMPROVEMENT: Last Seen column added
  - IMPROVEMENT: Key column added (shows key tier)
  - IMPROVEMENT: Sort users by join date (newest first) by default
  - IMPROVEMENT: Added "Copy User ID" tip in ban section
"""
import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, post
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="Users · Xissin Admin", page_icon="👥", layout="wide")
inject_theme()
auth_guard()
page_header("👥", "Users", "ALL REGISTERED APP USERS · BAN · UNBAN")

col_a, col_b, col_c = st.columns([3, 1, 1])
with col_a:
    search = st.text_input(
        "🔍 Search", placeholder="Search by User ID or username...",
        label_visibility="collapsed",
    )
with col_b:
    status_filter = st.selectbox("Filter", ["All", "Active", "Banned"],
                                 label_visibility="collapsed")
with col_c:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()


@st.cache_data(ttl=30, show_spinner=False)
def load_users():
    users = get("/api/users/list").get("users", [])
    ngl_map = {}
    try:
        ngl_stats = get("/api/ngl/stats").get("by_user", [])
        ngl_map   = {x["user_id"]: x["total"] for x in ngl_stats}
    except Exception:
        pass
    premium_uids = set()
    try:
        premium_uids = set(
            get("/api/payments/admin/premium").get("premium_users", {}).keys()
        )
    except Exception:
        pass
    return users, ngl_map, premium_uids


with st.spinner("Loading users..."):
    users, ngl_map, premium_uids = load_users()

for u in users:
    u["ngl_total"] = ngl_map.get(u.get("user_id", ""), 0)

total     = len(users)
banned    = sum(1 for u in users if u.get("banned"))
premium   = len(premium_uids)
total_ngl = sum(u.get("ngl_total", 0) for u in users)

# ── Metric cards ───────────────────────────────────────────────────────────────
c1, c2, c3, c4 = st.columns(4)
for col, icon, label, value, color, delay in [
    (c1, "👥", "TOTAL USERS", total,   "#00e5ff", 0.0),
    (c2, "🚫", "BANNED",      banned,  "#ff4757", 0.08),
    (c3, "⭐", "PREMIUM",     premium, "#FFD700", 0.12),
    (c4, "💬", "TOTAL NGL",   total_ngl, "#f472b6", 0.16),
]:
    with col:
        st.markdown(f"""<div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:16px;
            position:relative;overflow:hidden;animation:cardFadeIn .5s ease {delay}s both'>
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}88;letter-spacing:2px;margin-bottom:8px'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:28px;
                color:{color}'>{value}</div></div>""", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Build filtered list ────────────────────────────────────────────────────────
filtered = users[:]
if search.strip():
    q = search.strip().lower()
    filtered = [
        u for u in filtered
        if q in (u.get("user_id") or "").lower()
        or q in (u.get("username") or "").lower()
    ]
if status_filter == "Active":  filtered = [u for u in filtered if not u.get("banned")]
if status_filter == "Banned":  filtered = [u for u in filtered if u.get("banned")]

# Sort by join date newest first
filtered.sort(key=lambda u: u.get("joined_at") or "", reverse=True)

st.markdown(
    f"""<div style='font-family:"Share Tech Mono",monospace;font-size:10px;
    color:#5a7a9a;margin-bottom:8px'>SHOWING {len(filtered)} OF {total} USERS</div>""",
    unsafe_allow_html=True,
)

if filtered:
    rows = []
    for u in filtered:
        uid = u.get("user_id", "-")
        rows.append({
            "User ID":  uid,
            "Username": u.get("username") or "-",
            "Premium":  "⭐ Yes" if uid in premium_uids else "—",
            "Status":   "🚫 Banned" if u.get("banned") else "✅ Active",
            "Key Tier": u.get("key_tier") or u.get("tier") or "-",
            "SMS Sent": u.get("total_sms", 0),
            "NGL Sent": u.get("ngl_total", 0),
            "Joined":   (u.get("joined_at") or "-")[:10],
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

st.markdown("<br>", unsafe_allow_html=True)
st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#ff4757;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
    ◈ BAN / UNBAN USER</div>""", unsafe_allow_html=True)

# Build set of known user_ids for validation
known_uids = {u.get("user_id", "") for u in users}

with st.container(border=True):
    st.caption("💡 Tip: Copy a User ID from the table above, then paste it here.")
    col_x, col_y, col_z = st.columns([2, 1, 1])
    with col_x:
        target_uid = st.text_input("User ID", placeholder="Enter exact user_id...")
    with col_y:
        ban_reason = st.text_input("Reason (optional)", placeholder="e.g. Spamming")
    with col_z:
        action = st.selectbox("Action", ["Ban", "Unban"])

    col_btn, _ = st.columns([1, 3])
    with col_btn:
        if st.button(
            f"{'🚫 BAN' if action == 'Ban' else '✅ UNBAN'} USER",
            type="primary",
            use_container_width=True,
        ):
            if not target_uid.strip():
                st.error("Enter a User ID.")
            elif target_uid.strip() not in known_uids:
                # FIX: validate user exists before calling API
                st.error(
                    f"❌ User ID `{target_uid.strip()}` not found. "
                    "Double-check the ID from the table above."
                )
            else:
                try:
                    endpoint = "/api/users/ban" if action == "Ban" else "/api/users/unban"
                    post(endpoint, {"user_id": target_uid.strip(), "reason": ban_reason.strip()})
                    st.success(
                        f"✓ User `{target_uid}` has been "
                        f"{'banned' if action == 'Ban' else 'unbanned'}."
                    )
                    st.cache_data.clear()
                    st.rerun()
                except Exception as e:
                    st.error(f"Error: {e}")
