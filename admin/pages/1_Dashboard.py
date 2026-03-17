"""
pages/1_Dashboard.py — Overview stats, server status, top NGL users, recent logs
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, get_public
from utils.theme import inject_theme, page_header, auth_guard, status_badge

st.set_page_config(page_title="Dashboard · Xissin Admin", page_icon="📊", layout="wide")
inject_theme()
auth_guard()

page_header("📊", "Dashboard", "REAL-TIME OVERVIEW · AUTO-REFRESH 30s")

col_r, _ = st.columns([1, 8])
with col_r:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_dashboard_data():
    results = {}
    try: results["users"]   = get("/api/users/list").get("users", [])
    except: results["users"] = []
    try: results["status"]  = get_public("/api/status")
    except: results["status"] = {}
    try: results["ngl"]     = get("/api/ngl/stats")
    except: results["ngl"] = {}
    try: results["logs"]    = get("/api/users/logs/recent", {"limit": 12}).get("logs", [])
    except: results["logs"] = []
    try: results["ann"]     = get_public("/api/announcements")
    except: results["ann"] = []
    return results

with st.spinner("Loading command center..."):
    data = load_dashboard_data()

users    = data["users"]
status   = data["status"]
ngl      = data["ngl"]
logs     = data["logs"]
ann_list = data["ann"]
now      = datetime.utcnow()

banned_users = sum(1 for u in users if u.get("banned"))
total_sms    = sum(u.get("total_sms", 0) for u in users)
total_ngl    = ngl.get("total_ngl_sent", 0)

# ── Animated metric cards ──────────────────────────────────────────────────────
st.markdown("""
<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
    ◈ SYSTEM METRICS
</div>
""", unsafe_allow_html=True)

cols = st.columns(6)
metrics = [
    ("👥", "USERS",        len(users),    "#00e5ff", 0.0),
    ("🚫", "BANNED",       banned_users,  "#ff4757", 0.05),
    ("📱", "SMS SENT",     total_sms,     "#ff9500", 0.1),
    ("💬", "NGL SENT",     total_ngl,     "#f472b6", 0.15),
    ("📢", "ANNOUNCES",    len(ann_list), "#00b8d4", 0.2),
    ("📦", "APP VERSION",  status.get("latest_app_version", "-"), "#a855f7", 0.25),
]
for col, (icon, label, value, color, delay) in zip(cols, metrics):
    with col:
        st.markdown(f"""
        <div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:14px 12px;
            position:relative;overflow:hidden;
            animation:cardFadeIn .5s ease {delay}s both;
            transition:all .3s ease;cursor:default'
            onmouseover="this.style.borderColor='{color}88';this.style.boxShadow='0 0 20px {color}22'"
            onmouseout="this.style.borderColor='{color}33';this.style.boxShadow='none'">
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}99;letter-spacing:2px;margin-bottom:8px;
                text-transform:uppercase'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:26px;
                color:{color};line-height:1;animation:countUp .6s ease {delay}s both'>
                {value}
            </div>
        </div>
        """, unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Two-column layout ──────────────────────────────────────────────────────────
col_left, col_right = st.columns([1, 1], gap="large")

with col_left:
    # Server status
    maint    = status.get("maintenance", False)
    features = status.get("features", {})

    st.markdown(f"""
    <div style='animation:fadeUp .5s ease .2s both'>
        <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
            color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
            ◈ SERVER STATUS
        </div>
        <div style='background:{"rgba(255,71,87,.08)" if maint else "rgba(0,255,157,.06)"};
            border:1px solid {"rgba(255,71,87,.3)" if maint else "rgba(0,255,157,.25)"};
            border-radius:12px;padding:20px;margin-bottom:16px'>
            <div style='display:flex;align-items:center;gap:10px;margin-bottom:14px'>
                <span style='width:10px;height:10px;border-radius:50%;
                    background:{"#ff4757" if maint else "#00ff9d"};
                    animation:pulse 2s infinite'></span>
                <span style='font-family:"Exo 2",sans-serif;font-weight:800;font-size:14px;
                    color:{"#ff4757" if maint else "#00ff9d"};letter-spacing:2px'>
                    {"⚠ MAINTENANCE MODE" if maint else "✓ APP ONLINE"}
                </span>
            </div>
            <div style='display:grid;gap:8px'>
    """, unsafe_allow_html=True)

    info_rows = [
        ("API VERSION",      status.get("api_version", "-"),          "#00e5ff"),
        ("MIN APP VERSION",  status.get("min_app_version", "-"),       "#a855f7"),
        ("LATEST VERSION",   status.get("latest_app_version", "-"),    "#00ff9d"),
        ("SMS BOMBER",       "✓ ENABLED" if features.get("sms_bomber") else "✗ DISABLED",
                             "#00ff9d" if features.get("sms_bomber") else "#ff4757"),
        ("NGL BOMBER",       "✓ ENABLED" if features.get("ngl_bomber") else "✗ DISABLED",
                             "#00ff9d" if features.get("ngl_bomber") else "#ff4757"),
    ]
    for k, v, c in info_rows:
        st.markdown(f"""
            <div style='display:flex;justify-content:space-between;
                padding:6px 0;border-bottom:1px solid rgba(0,229,255,.07)'>
                <span style='font-family:"Share Tech Mono",monospace;font-size:10px;
                    color:#5a7a9a;letter-spacing:1px'>{k}</span>
                <span style='font-family:"Share Tech Mono",monospace;font-size:10px;
                    color:{c};font-weight:700'>{v}</span>
            </div>
        """, unsafe_allow_html=True)

    st.markdown("</div></div></div>", unsafe_allow_html=True)

    # Top NGL users
    st.markdown("""
    <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 12px'>
        ◈ TOP NGL USERS
    </div>
    """, unsafe_allow_html=True)
    top_ngl = ngl.get("by_user", [])
    if top_ngl:
        for i, u in enumerate(top_ngl[:5]):
            name  = u.get("username") or u.get("user_id", "?")
            total = u.get("total", 0)
            max_v = top_ngl[0].get("total", 1)
            pct   = int((total / max(max_v, 1)) * 100)
            colors = ["#f472b6", "#a855f7", "#00e5ff", "#00ff9d", "#ff9500"]
            c = colors[i % len(colors)]
            st.markdown(f"""
            <div style='margin-bottom:12px;animation:slideIn .4s ease {i*0.08}s both'>
                <div style='display:flex;justify-content:space-between;margin-bottom:5px'>
                    <span style='font-family:"Exo 2",sans-serif;font-weight:700;
                        font-size:13px;color:#c8d8f0'>#{i+1} {name}</span>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:13px;color:{c};font-weight:700'>{total}</span>
                </div>
                <div style='background:rgba(255,255,255,.05);border-radius:4px;height:5px'>
                    <div style='background:linear-gradient(90deg,{c},{c}88);
                        width:{pct}%;height:100%;border-radius:4px;
                        box-shadow:0 0 6px {c}66;
                        transition:width .8s ease'></div>
                </div>
            </div>
            """, unsafe_allow_html=True)
    else:
        st.markdown("<p style='color:#5a7a9a;font-size:13px'>No NGL activity yet.</p>", unsafe_allow_html=True)


with col_right:
    st.markdown("""
    <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
        ◈ RECENT ACTIVITY FEED
    </div>
    """, unsafe_allow_html=True)

    LOG_CFG = {
        "user_registered":     ("#00e5ff", "👤"),
        "user_banned":         ("#ff4757", "🚫"),
        "user_unbanned":       ("#00ff9d", "✅"),
        "sms_bomb":            ("#ff9500", "💣"),
        "ngl_sent":            ("#f472b6", "💬"),
        "settings_updated":    ("#00b8d4", "⚙️"),
        "announcement_created":("#ff9500", "📢"),
    }

    st.markdown("""
    <div style='background:var(--bg3);border:1px solid var(--border-glow);
        border-radius:12px;padding:16px;max-height:520px;overflow-y:auto'>
    """, unsafe_allow_html=True)

    if logs:
        for i, log in enumerate(logs[:12]):
            action = log.get("action", "")
            color, icon = LOG_CFG.get(action, ("#5a7a9a", "•"))
            ts     = (log.get("ts") or "")[:16].replace("T", " ")
            uid    = log.get("user_id", "")
            target = log.get("target", "")
            sent   = log.get("sent", "")
            meta_parts = []
            if uid:    meta_parts.append(f"uid:{uid[:12]}")
            if target: meta_parts.append(f"@{target}")
            if sent != "": meta_parts.append(f"sent:{sent}")
            meta = " · ".join(meta_parts)

            st.markdown(f"""
            <div style='display:flex;gap:10px;padding:9px 0;
                border-bottom:1px solid rgba(0,229,255,.06);
                animation:slideIn .3s ease {i*0.04}s both'>
                <div style='display:flex;flex-direction:column;align-items:center;
                    padding-top:2px'>
                    <div style='width:8px;height:8px;border-radius:50%;
                        background:{color};flex-shrink:0;
                        box-shadow:0 0 6px {color}88'></div>
                    <div style='width:1px;flex:1;background:rgba(0,229,255,.06);
                        margin-top:4px'></div>
                </div>
                <div style='flex:1;padding-bottom:2px'>
                    <div style='display:flex;justify-content:space-between;
                        align-items:center'>
                        <span style='font-family:"Share Tech Mono",monospace;
                            font-size:11px;font-weight:700;color:{color}'>
                            {icon} {action}
                        </span>
                        <span style='font-family:"Share Tech Mono",monospace;
                            font-size:9px;color:#2a4a6a'>{ts}</span>
                    </div>
                    <div style='font-family:"Share Tech Mono",monospace;
                        font-size:10px;color:#5a7a9a;margin-top:2px'>{meta}</div>
                </div>
            </div>
            """, unsafe_allow_html=True)
    else:
        st.markdown("<p style='color:#5a7a9a;font-size:13px;text-align:center;padding:20px'>No logs yet.</p>", unsafe_allow_html=True)

    st.markdown("</div>", unsafe_allow_html=True)
