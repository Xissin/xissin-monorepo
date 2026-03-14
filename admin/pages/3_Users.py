"""
pages/3_Users.py — View, search, ban/unban users. Shows SMS + NGL usage per user.
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, post

st.set_page_config(page_title="Users · Xissin Admin", page_icon="👥", layout="wide")

if not st.session_state.get("authenticated"):
    st.warning("⚠️ Please login first.")
    st.stop()

st.markdown("## 👥 Users")
st.markdown("All registered app users")
st.divider()

# ── Controls ───────────────────────────────────────────────────────────────────
col_a, col_b, col_c = st.columns([3, 1, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Search by User ID or username...")
with col_b:
    status_filter = st.selectbox("Filter", ["All", "Active", "Banned", "Has Key", "No Key"])
with col_c:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_users():
    users   = get("/api/users/list").get("users", [])
    ngl_map = {}
    try:
        ngl_stats = get("/api/ngl/stats").get("by_user", [])
        ngl_map   = {x["user_id"]: x["total"] for x in ngl_stats}
    except Exception:
        pass
    return users, ngl_map

with st.spinner("Loading users..."):
    users, ngl_map = load_users()

# Enrich
now = datetime.utcnow()
for u in users:
    u["ngl_total"] = ngl_map.get(u.get("user_id", ""), 0)
    expires = u.get("key_expires", "")
    u["_has_key"] = bool(u.get("active_key") and expires and datetime.fromisoformat(expires) > now)

# ── Stat cards ─────────────────────────────────────────────────────────────────
total   = len(users)
banned  = sum(1 for u in users if u.get("banned"))
has_key = sum(1 for u in users if u.get("_has_key"))
total_ngl = sum(u.get("ngl_total", 0) for u in users)

c1, c2, c3, c4 = st.columns(4)
c1.metric("👥 Total Users",  total)
c2.metric("✅ With Key",      has_key)
c3.metric("🚫 Banned",        banned)
c4.metric("💬 Total NGL",     total_ngl)

st.divider()

# ── Filter ─────────────────────────────────────────────────────────────────────
filtered = users[:]
if search.strip():
    q = search.strip().lower()
    filtered = [u for u in filtered if
                q in (u.get("user_id") or "").lower() or
                q in (u.get("username") or "").lower()]

if status_filter == "Active":  filtered = [u for u in filtered if not u.get("banned")]
if status_filter == "Banned":  filtered = [u for u in filtered if u.get("banned")]
if status_filter == "Has Key": filtered = [u for u in filtered if u.get("_has_key")]
if status_filter == "No Key":  filtered = [u for u in filtered if not u.get("_has_key")]

st.caption(f"Showing **{len(filtered)}** of {total} users")

# ── Table ─────────────────────────────────────────────────────────────────────
if not filtered:
    st.info("No users match your filter.")
    st.stop()

rows = []
for u in filtered:
    key_exp = (u.get("key_expires") or "")[:10]
    rows.append({
        "User ID":     u.get("user_id", "-"),
        "Username":    u.get("username") or "-",
        "Status":      "🚫 Banned" if u.get("banned") else "✅ Active",
        "Key":         f"🔑 Active (exp {key_exp})" if u.get("_has_key") else "❌ No Key",
        "SMS Sent":    u.get("total_sms", 0),
        "NGL Sent":    u.get("ngl_total", 0),
        "Joined":      (u.get("joined_at") or "-")[:10],
    })

df = pd.DataFrame(rows)
df.index = range(1, len(df) + 1)
st.dataframe(df, use_container_width=True)

st.divider()

# ── Ban / Unban action ────────────────────────────────────────────────────────
st.markdown("### 🔨 Ban / Unban User")
col_x, col_y, col_z = st.columns([2, 1, 1])
with col_x:
    target_uid = st.text_input("User ID", placeholder="Enter exact user_id...")
with col_y:
    ban_reason = st.text_input("Reason (optional)", placeholder="e.g. Spamming")
with col_z:
    st.markdown("<br>", unsafe_allow_html=True)
    action = st.selectbox("Action", ["Ban", "Unban"])

col_btn, _ = st.columns([1, 3])
with col_btn:
    if st.button(f"{'🚫 Ban' if action == 'Ban' else '✅ Unban'} User", type="primary", use_container_width=True):
        if not target_uid.strip():
            st.error("Please enter a User ID.")
        else:
            try:
                endpoint = "/api/users/ban" if action == "Ban" else "/api/users/unban"
                post(endpoint, {"user_id": target_uid.strip(), "reason": ban_reason.strip()})
                st.success(f"✓ User `{target_uid}` has been {'banned' if action == 'Ban' else 'unbanned'}.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")
