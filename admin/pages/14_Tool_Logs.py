"""pages/14_Tool_Logs.py — URL Remover & Dup Remover usage logs"""
import streamlit as st
import pandas as pd
from utils.api import get, get_heavy, _ALL
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(
    page_title="Tool Logs · Xissin Admin",
    page_icon="🔧",
    layout="wide",
)
inject_theme()
auth_guard()
page_header("🔧", "Tool Logs", "URL REMOVER · DUP REMOVER · USAGE ANALYTICS")

# ── Controls ───────────────────────────────────────────────────────────────────
col_a, col_b, col_c = st.columns([3, 2, 1])
with col_a:
    search = st.text_input(
        "🔍 Filter by User ID",
        placeholder="User ID...",
        label_visibility="collapsed",
    )
with col_b:
    tool_filter = st.selectbox(
        "Tool",
        ["All Tools", "🔗 URL Remover", "🗂️ Dup Remover"],
        label_visibility="collapsed",
    )
with col_c:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_data():
    stats, logs = {}, []
    try:
        stats = get("/api/tools/stats")
    except Exception:
        pass
    try:
        logs = get_heavy("/api/tools/logs", {"limit": _ALL}).get("logs", [])
    except Exception:
        pass
    return stats, logs

with st.spinner("Loading tool usage data..."):
    stats, logs = load_data()

# ── Apply filters ──────────────────────────────────────────────────────────────
filtered = logs[:]
if search.strip():
    q        = search.strip().lower()
    filtered = [l for l in filtered
                if q in str(l.get("user_id", "")).lower()]
if tool_filter == "🔗 URL Remover":
    filtered = [l for l in filtered if l.get("tool") == "url_remover"]
elif tool_filter == "🗂️ Dup Remover":
    filtered = [l for l in filtered if l.get("tool") == "dup_remover"]

# ── Metric cards ───────────────────────────────────────────────────────────────
url_s  = stats.get("url_remover", {})
dup_s  = stats.get("dup_remover", {})

total_uses      = stats.get("total_uses",               0)
url_uses        = url_s.get("uses",                     0)
dup_uses        = dup_s.get("uses",                     0)
url_removed     = url_s.get("total_removed",            0)
dup_removed     = dup_s.get("total_removed",            0)
total_lines_in  = url_s.get("total_input",  0) + dup_s.get("total_input",  0)
total_removed   = url_removed + dup_removed

c1, c2, c3, c4, c5, c6 = st.columns(6)
for col, icon, label, value, color, delay in [
    (c1, "🔧", "TOTAL USES",     total_uses,     "#00e5ff", 0.00),
    (c2, "🔗", "URL REMOVER",    url_uses,       "#7B8CDE", 0.06),
    (c3, "🗂️", "DUP REMOVER",   dup_uses,       "#FFA94D", 0.12),
    (c4, "📄", "LINES IN",       total_lines_in, "#a855f7", 0.18),
    (c5, "✂️", "TOTAL REMOVED",  total_removed,  "#FF6B6B", 0.24),
    (c6, "📋", "LOGS SHOWN",     len(filtered),  "#00ff9d", 0.30),
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
                color:{color}'>{value:,}</div>
        </div>""", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Tool comparison ────────────────────────────────────────────────────────────
col_left, col_right = st.columns(2)

with col_left:
    st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;margin-bottom:12px'>◈ URL REMOVER STATS</div>""",
        unsafe_allow_html=True)
    with st.container(border=True):
        st.metric("Total Uses",       url_s.get("uses",            0))
        st.metric("Lines Processed",  url_s.get("total_input",     0))
        st.metric("URLs Removed",     url_s.get("total_removed",   0))
        st.metric("Avg Removal Rate", f"{url_s.get('avg_removal_rate', 0)}%")

with col_right:
    st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;margin-bottom:12px'>◈ DUP REMOVER STATS</div>""",
        unsafe_allow_html=True)
    with st.container(border=True):
        st.metric("Total Uses",        dup_s.get("uses",            0))
        st.metric("Lines Processed",   dup_s.get("total_input",     0))
        st.metric("Duplicates Removed",dup_s.get("total_removed",   0))
        st.metric("Avg Removal Rate",  f"{dup_s.get('avg_removal_rate', 0)}%")

# ── Per-user breakdown ─────────────────────────────────────────────────────────
by_user = stats.get("by_user", [])
if by_user:
    with st.expander("👥 Per-User Breakdown", expanded=False):
        df_u = pd.DataFrame(by_user)
        df_u.columns = ["User ID", "Username", "URL Remover", "Dup Remover", "Total Uses"]
        df_u = df_u.sort_values("Total Uses", ascending=False).reset_index(drop=True)
        df_u.index += 1
        st.dataframe(df_u, use_container_width=True)

st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 10px'>
    ◈ USAGE LOGS</div>""", unsafe_allow_html=True)

if not filtered:
    st.info("No tool usage logs found.")
    st.stop()

st.caption(f"Showing **{len(filtered)}** log entries")

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    for log in filtered:
        tool    = log.get("tool", "")
        is_url  = tool == "url_remover"
        color   = "#7B8CDE" if is_url else "#FFA94D"
        icon    = "🔗" if is_url else "🗂️"
        label   = "URL Remover" if is_url else "Dup Remover"
        ts      = (log.get("ts") or "")[:16].replace("T", " ")
        user_id = log.get("user_id",      "—")
        inp     = log.get("input_count",   0)
        out     = log.get("output_count",  0)
        removed = log.get("removed_count", 0)
        rate    = log.get("removal_rate",  0.0)

        rate_color = (
            "#7EE7C1" if rate >= 50
            else "#FFA726" if rate >= 20
            else "#FF6B6B"
        )

        st.markdown(f"""
        <div style='padding:12px 0;border-bottom:1px solid #1d2c4a'>
            <div style='display:flex;gap:12px;align-items:flex-start'>
                <div style='width:10px;height:10px;border-radius:50%;
                    background:{color};margin-top:5px;flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex;justify-content:space-between;flex-wrap:wrap;gap:6px'>
                        <span style='font-family:monospace;font-weight:700;
                            font-size:13px;color:{color}'>{icon} {label}</span>
                        <span style='font-size:10px;color:#7a8ab8'>{ts} PHT</span>
                    </div>
                    <div style='margin-top:6px;display:flex;flex-wrap:wrap;gap:8px'>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#A78BFA'>👤 {user_id}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#7a8ab8'>📄 {inp:,} lines in</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#7EE7C1'>✅ {out:,} kept</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#FF6B6B'>✂️ {removed:,} removed</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:{rate_color}'>📊 {rate}%</span>
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

with tab2:
    rows = []
    for log in filtered:
        tool   = log.get("tool", "")
        ts     = (log.get("ts") or "")[:16].replace("T", " ")
        rows.append({
            "Time (PHT)":    ts,
            "Tool":          "🔗 URL Remover" if tool == "url_remover" else "🗂️ Dup Remover",
            "User ID":       log.get("user_id",       "—"),
            "Lines In":      log.get("input_count",    0),
            "Lines Kept":    log.get("output_count",   0),
            "Removed":       log.get("removed_count",  0),
            "Removal Rate":  f"{log.get('removal_rate', 0.0)}%",
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_tool_logs.csv",
        mime      = "text/csv",
    )
