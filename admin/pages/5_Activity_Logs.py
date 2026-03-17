"""pages/5_Activity_Logs.py — Full activity log with action type filter"""
import streamlit as st
import pandas as pd
from utils.api import get
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="Activity Logs · Xissin Admin", page_icon="📋", layout="wide")
inject_theme(); auth_guard()
page_header("📋", "Activity Logs", "ALL BACKEND ACTIONS · FILTERED · SEARCHABLE")

col_a, col_b, col_c, col_d = st.columns([2, 1, 1, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Filter by user ID, target, key...")
with col_b:
    action_filter = st.selectbox("Action Type", [
        "All", "ngl_sent", "sms_bomb",
        "user_registered", "user_banned", "user_unbanned",
        "settings_updated", "announcement_created",
    ])
with col_c:
    limit = st.selectbox("Show last", [25, 50, 100, 200, 500], index=1)
with col_d:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_logs(limit):
    return get("/api/users/logs/recent", {"limit": limit}).get("logs", [])

with st.spinner("Loading logs..."):
    logs = load_logs(limit)

# ── Filter ─────────────────────────────────────────────────────────────────────
if action_filter != "All":
    logs = [l for l in logs if l.get("action") == action_filter]

if search.strip():
    q = search.strip().lower()
    logs = [l for l in logs if
            q in str(l.get("user_id", "")).lower() or
            q in str(l.get("target", "")).lower() or
            q in str(l.get("key", "")).lower() or
            q in str(l.get("phone", "")).lower()]

st.markdown(f'''<div style='font-family:"Share Tech Mono",monospace;font-size:10px;
    color:#5a7a9a;margin-bottom:8px'>SHOWING {len(logs)} LOG ENTRIES</div>''', unsafe_allow_html=True)

if not logs:
    st.info("No logs match your filter.")
    st.stop()

# ── Timeline view ─────────────────────────────────────────────────────────────
LOG_COLORS = {
    "user_registered":    "#A78BFA",
    "user_banned":        "#FF6B6B",
    "user_unbanned":      "#7EE7C1",
    "sms_bomb":           "#FFA726",
    "ngl_sent":           "#FF6EC7",
    "settings_updated":   "#38BDF8",
    "announcement_created":"#FFA726",
    "announcement_deleted":"#7a8ab8",
    "announcements_cleared":"#7a8ab8",
}

tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    for log in logs:
        action = log.get("action", "")
        color  = LOG_COLORS.get(action, "#7a8ab8")
        ts     = (log.get("ts") or "")[:16].replace("T", " ")

        meta_parts = []
        if log.get("user_id"):    meta_parts.append(f"User: {log['user_id']}")
        if log.get("username"):   meta_parts.append(f"@{log['username']}")
        if log.get("target"):     meta_parts.append(f"→ @{log['target']}")
        if log.get("key"):        meta_parts.append(f"Key: {log['key'][:16]}...")
        if log.get("phone"):      meta_parts.append(f"Phone: {log['phone']}")
        if log.get("sent") is not None:
            meta_parts.append(f"Sent: {log['sent']}, Failed: {log.get('failed', 0)}")
        if log.get("total_sent") is not None:
            meta_parts.append(f"Sent: {log['total_sent']}, Failed: {log.get('total_failed', 0)}")
        if log.get("reason"):     meta_parts.append(f"Reason: {log['reason']}")
        if log.get("days"):       meta_parts.append(f"{log['days']}d")
        if log.get("title"):      meta_parts.append(f'"{log["title"]}"')
        meta = " · ".join(meta_parts)

        st.markdown(f"""
        <div style='display:flex; gap:12px; padding:10px 0;
            border-bottom:1px solid #1d2c4a; align-items:flex-start'>
            <div style='width:8px; height:8px; border-radius:50%;
                background:{color}; margin-top:6px; flex-shrink:0'></div>
            <div style='flex:1'>
                <div style='display:flex; justify-content:space-between; gap:10px'>
                    <span style='font-size:12px; font-weight:700;
                        font-family:monospace; color:{color}'>{action}</span>
                    <span style='font-size:10px; color:#7a8ab8; white-space:nowrap'>{ts} PHT</span>
                </div>
                <div style='font-size:11px; color:#7a8ab8; margin-top:3px; line-height:1.5'>{meta}</div>
            </div>
        </div>
        """, unsafe_allow_html=True)

with tab2:
    rows = []
    for log in logs:
        ts = (log.get("ts") or "")[:16].replace("T", " ")
        meta_parts = []
        if log.get("user_id"):  meta_parts.append(log["user_id"])
        if log.get("target"):   meta_parts.append(f"→@{log['target']}")
        if log.get("phone"):    meta_parts.append(log["phone"])
        if log.get("sent") is not None:
            meta_parts.append(f"S:{log['sent']} F:{log.get('failed',0)}")
        rows.append({
            "Time":   ts,
            "Action": log.get("action", "-"),
            "Detail": " ".join(meta_parts),
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)
