"""
pages/4_Crash_Reports.py — Crash & error reports from the Flutter app

NEW PAGE — the backend has /api/crash-report router but no admin page existed.
Displays all crash logs sent by the Flutter CrashReporter service.
"""
import streamlit as st
import pandas as pd
from utils.api import get, get_heavy, delete, _ALL
from utils.theme import inject_theme, page_header, auth_guard, notify, render_notify

st.set_page_config(
    page_title="Crash Reports · Xissin Admin",
    page_icon="🐛",
    layout="wide",
)
inject_theme()
auth_guard()
render_notify()

page_header("🐛", "Crash Reports", "FLUTTER APP ERRORS · STACK TRACES · DEVICE INFO")

# ── Controls ──────────────────────────────────────────────────────────────────
col_a, col_b, col_c, col_d = st.columns([3, 2, 1, 1])
with col_a:
    search = st.text_input(
        "🔍 Search",
        placeholder="Filter by user ID, error type, or message...",
        label_visibility="collapsed",
    )
with col_b:
    type_filter = st.selectbox(
        "Type",
        ["All", "ZONE ERROR", "FLUTTER ERROR", "UNCAUGHT", "MANUAL"],
        label_visibility="collapsed",
    )
with col_c:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()
with col_d:
    if st.button("🗑️ Clear All", use_container_width=True, type="secondary"):
        st.session_state["confirm_clear_crashes"] = True

# Confirmation banner
if st.session_state.get("confirm_clear_crashes"):
    st.warning("⚠️ **Clear ALL crash reports?** This cannot be undone.")
    c_yes, c_no = st.columns([1, 1])
    with c_yes:
        if st.button("✅ Yes, clear all", type="primary", use_container_width=True):
            try:
                delete("/api/crash-report/logs")
                notify("🗑️ All crash reports cleared.", kind="warning")
                st.cache_data.clear()
                st.session_state["confirm_clear_crashes"] = False
                st.rerun()
            except Exception as e:
                st.error(str(e))
                st.session_state["confirm_clear_crashes"] = False
    with c_no:
        if st.button("❌ Cancel", use_container_width=True):
            st.session_state["confirm_clear_crashes"] = False
            st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_crashes():
    try:
        return get_heavy("/api/crash-report/logs", {"limit": _ALL}).get("logs", [])
    except Exception:
        return []

with st.spinner("Loading crash reports..."):
    logs = load_crashes()

# ── Filters ────────────────────────────────────────────────────────────────────
if type_filter != "All":
    logs = [l for l in logs if l.get("type", "").upper() == type_filter]

if search.strip():
    q = search.strip().lower()
    logs = [
        l for l in logs
        if q in str(l.get("user_id",   "")).lower()
        or q in str(l.get("type",      "")).lower()
        or q in str(l.get("error",     "")).lower()
        or q in str(l.get("message",   "")).lower()
    ]

# ── Metrics ────────────────────────────────────────────────────────────────────
total      = len(logs)
unique_u   = len({l.get("user_id", "") for l in logs if l.get("user_id")})
zone_errs  = sum(1 for l in logs if l.get("type", "").upper() == "ZONE ERROR")
fl_errs    = sum(1 for l in logs if l.get("type", "").upper() == "FLUTTER ERROR")

c1, c2, c3, c4 = st.columns(4)
for col, icon, label, value, color, delay in [
    (c1, "🐛", "TOTAL CRASHES",    total,      "#FF6B6B", 0.00),
    (c2, "👤", "UNIQUE USERS",     unique_u,   "#a855f7", 0.08),
    (c3, "💥", "ZONE ERRORS",      zone_errs,  "#FFA726", 0.16),
    (c4, "⚡", "FLUTTER ERRORS",   fl_errs,    "#38BDF8", 0.24),
]:
    with col:
        st.markdown(f"""
        <div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:16px;
            position:relative;overflow:hidden;animation:cardFadeIn .5s ease {delay}s both'>
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}88;letter-spacing:2px;margin-bottom:8px'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:26px;
                color:{color}'>{value}</div>
        </div>""", unsafe_allow_html=True)

st.caption(f"Showing **{len(logs)}** crash reports")

if not logs:
    st.info("No crash reports found. This is a good sign! 🎉")
    st.stop()

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    # Limit timeline to last 200 for performance — full data in Table tab
    display_logs = logs[:200]
    if len(logs) > 200:
        st.info(f"Showing last 200 of {len(logs)} crashes in Timeline. See Table tab for all records.")

    for log in display_logs:
        ts       = (log.get("ts") or "")[:16].replace("T", " ")
        err_type = log.get("type", "UNKNOWN").upper()
        user_id  = log.get("user_id",   "anonymous")
        error    = log.get("error",     "") or log.get("message", "") or "No message"
        stack    = log.get("stack",     "") or ""
        platform = log.get("platform",  "") or ""
        version  = log.get("version",   "") or ""

        color = {
            "ZONE ERROR":     "#FF6B6B",
            "FLUTTER ERROR":  "#FFA726",
            "UNCAUGHT":       "#f472b6",
            "MANUAL":         "#38BDF8",
        }.get(err_type, "#7a8ab8")

        err_preview = str(error)[:120] + ("…" if len(str(error)) > 120 else "")

        st.markdown(f"""
        <div style='padding:14px 0; border-bottom:1px solid #1d2c4a'>
            <div style='display:flex; gap:12px; align-items:flex-start'>
                <div style='width:10px; height:10px; border-radius:50%;
                    background:{color}; margin-top:5px; flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex; justify-content:space-between; flex-wrap:wrap; gap:6px'>
                        <span style='font-family:monospace; font-weight:700;
                            font-size:13px; color:{color}'>🐛 {err_type}</span>
                        <span style='font-size:10px; color:#7a8ab8'>{ts} PHT</span>
                    </div>
                    <div style='margin-top:6px; display:flex; flex-wrap:wrap; gap:8px'>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#A78BFA'>👤 {user_id}</span>
                        {f"<span style='background:#1a2340;border-radius:6px;padding:3px 8px;font-size:11px;color:#7a8ab8'>📱 {platform}</span>" if platform else ""}
                        {f"<span style='background:#1a2340;border-radius:6px;padding:3px 8px;font-size:11px;color:#7a8ab8'>v{version}</span>" if version else ""}
                    </div>
                    <div style='margin-top:8px;font-size:11px;color:#FF6B6B;
                        font-family:monospace;background:#1a0f0f;padding:8px 10px;
                        border-radius:6px;border-left:3px solid {color}'>
                        {err_preview}
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

        if stack:
            with st.expander("📋 Full Stack Trace"):
                st.code(stack[:3000], language="python")

with tab2:
    rows = []
    for log in logs:
        ts    = (log.get("ts") or "")[:16].replace("T", " ")
        error = log.get("error", "") or log.get("message", "") or ""
        rows.append({
            "Time (PHT)":  ts,
            "Type":        log.get("type", "—"),
            "User ID":     log.get("user_id",  "—"),
            "Platform":    log.get("platform", "—"),
            "Version":     log.get("version",  "—"),
            "Error":       str(error)[:100],
            "Has Stack":   "✅" if log.get("stack") else "—",
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_crash_reports.csv",
        mime      = "text/csv",
    )
