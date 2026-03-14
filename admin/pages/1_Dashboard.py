"""
pages/1_Dashboard.py — Overview stats, server status, top NGL users, recent logs
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, get_public

st.set_page_config(page_title="Dashboard · Xissin Admin", page_icon="📊", layout="wide")

if not st.session_state.get("authenticated"):
    st.warning("⚠️ Please login first.")
    st.stop()

# ── Page header ────────────────────────────────────────────────────────────────
st.markdown("## 📊 Dashboard")
st.markdown("Overview of your Xissin backend")
st.divider()

if st.button("🔄 Refresh", type="secondary"):
    st.cache_data.clear()
    st.rerun()

# ── Fetch all data in parallel ─────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_dashboard_data():
    results = {}
    try: results["users"]   = get("/api/users/list").get("users", [])
    except: results["users"] = []
    try: results["keys"]    = get("/api/keys/list").get("keys", [])
    except: results["keys"] = []
    try: results["status"]  = get_public("/api/status")
    except: results["status"] = {}
    try: results["ngl"]     = get("/api/ngl/stats")
    except: results["ngl"] = {}
    try: results["logs"]    = get("/api/users/logs/recent", {"limit": 12}).get("logs", [])
    except: results["logs"] = []
    try: results["ann"]     = get_public("/api/announcements")
    except: results["ann"] = []
    return results

with st.spinner("Loading dashboard..."):
    data = load_dashboard_data()

users    = data["users"]
keys     = data["keys"]
status   = data["status"]
ngl      = data["ngl"]
logs     = data["logs"]
ann_list = data["ann"]

now = datetime.utcnow()

# Key stats
active_keys  = sum(1 for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now) if keys else 0
banned_users = sum(1 for u in users if u.get("banned"))
total_sms    = sum(u.get("total_sms", 0) for u in users)
total_ngl    = ngl.get("total_ngl_sent", 0)

# ── Stat cards ──────────────────────────────────────────────────────────────────
st.markdown("### 📈 Overview")
c1, c2, c3, c4, c5, c6, c7, c8 = st.columns(8)
c1.metric("👥 Total Users",   len(users))
c2.metric("🟢 Active Keys",   active_keys)
c3.metric("🔑 Total Keys",    len(keys))
c4.metric("🚫 Banned",        banned_users)
c5.metric("📱 SMS Sent",      total_sms)
c6.metric("💬 NGL Sent",      total_ngl)
c7.metric("📢 Announcements", len(ann_list))
c8.metric("📦 App Version",   status.get("latest_app_version", "-"))

st.divider()

# ── Server status + Top NGL + Recent logs ─────────────────────────────────────
col_left, col_right = st.columns([1, 1])

with col_left:
    st.markdown("### 🖥️ Server Status")

    maint     = status.get("maintenance", False)
    features  = status.get("features", {})

    if maint:
        st.error("🔴 MAINTENANCE MODE IS ON")
    else:
        st.success("🟢 APP IS ONLINE")

    st.markdown(f"""
    | Key | Value |
    |---|---|
    | API Version | `{status.get('api_version', '-')}` |
    | Min App Version | `{status.get('min_app_version', '-')}` |
    | Latest App Version | `{status.get('latest_app_version', '-')}` |
    | SMS Bomber | {'✅ Enabled' if features.get('sms_bomber') else '❌ Disabled'} |
    | NGL Bomber | {'✅ Enabled' if features.get('ngl_bomber') else '❌ Disabled'} |
    | Key Manager | {'✅ Enabled' if features.get('key_manager') else '❌ Disabled'} |
    | Announcements | {'✅ Enabled' if features.get('announcements') else '❌ Disabled'} |
    """)

    st.markdown("### 🏆 Top NGL Users")
    top_ngl = ngl.get("by_user", [])
    if top_ngl:
        for u in top_ngl[:5]:
            name  = u.get("username") or u.get("user_id", "?")
            total = u.get("total", 0)
            max_v = top_ngl[0].get("total", 1)
            pct   = int((total / max_v) * 100)
            st.markdown(f"""
            <div style='margin-bottom:10px'>
                <div style='display:flex; justify-content:space-between; margin-bottom:4px'>
                    <span style='font-size:13px; font-weight:700'>{name}</span>
                    <span style='font-size:13px; color:#FF6EC7; font-weight:800; font-family:monospace'>{total}</span>
                </div>
                <div style='background:#121f3a; border-radius:4px; height:6px'>
                    <div style='background:linear-gradient(90deg,#FF6EC7,#FF9A44);
                        width:{pct}%; height:100%; border-radius:4px'></div>
                </div>
            </div>
            """, unsafe_allow_html=True)
    else:
        st.info("No NGL activity yet.")

with col_right:
    st.markdown("### 🕐 Recent Activity")
    if logs:
        LOG_COLORS = {
            "key_generated":      "#5B8CFF",
            "key_redeemed":       "#7EE7C1",
            "key_revoked":        "#FF6B6B",
            "user_registered":    "#A78BFA",
            "user_banned":        "#FF6B6B",
            "user_unbanned":      "#7EE7C1",
            "sms_bomb":           "#FFA726",
            "ngl_sent":           "#FF6EC7",
            "settings_updated":   "#38BDF8",
            "announcement_created": "#FFA726",
        }
        for log in logs[:12]:
            action = log.get("action", "")
            color  = LOG_COLORS.get(action, "#7a8ab8")
            ts     = (log.get("ts") or "")[:16].replace("T", " ")
            uid    = log.get("user_id", "")
            target = log.get("target", "")
            sent   = log.get("sent", "")

            meta_parts = []
            if uid:    meta_parts.append(f"User: {uid}")
            if target: meta_parts.append(f"→ @{target}")
            if sent != "": meta_parts.append(f"Sent: {sent}")
            meta = " · ".join(meta_parts)

            st.markdown(f"""
            <div style='display:flex; gap:10px; padding:8px 0;
                border-bottom:1px solid #1d2c4a; align-items:flex-start'>
                <div style='width:8px; height:8px; border-radius:50%;
                    background:{color}; margin-top:5px; flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex; justify-content:space-between'>
                        <span style='font-size:12px; font-weight:700; font-family:monospace;
                            color:{color}'>{action}</span>
                        <span style='font-size:10px; color:#7a8ab8'>{ts}</span>
                    </div>
                    <div style='font-size:11px; color:#7a8ab8; margin-top:2px'>{meta}</div>
                </div>
            </div>
            """, unsafe_allow_html=True)
    else:
        st.info("No logs yet.")
