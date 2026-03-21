"""pages/13_IP_Tracker_Logs.py — IP Tracker lookup logs — full history, no cap"""
import streamlit as st
import pandas as pd
from utils.api import get, get_heavy, _ALL
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="IP Tracker Logs · Xissin Admin", page_icon="🌐", layout="wide")
inject_theme()
auth_guard()
page_header("🌐", "IP Tracker Logs", "LOOKUP HISTORY · COUNTRY BREAKDOWN · SEARCHABLE")

# ── Controls ───────────────────────────────────────────────────────────────────
col_a, col_b, col_c = st.columns([2, 2, 1])
with col_a:
    search_query = st.text_input(
        "🔍 Filter by IP/Domain", placeholder="e.g. 8.8.8.8 or facebook.com...",
        label_visibility="collapsed",
    )
with col_b:
    search_user = st.text_input(
        "👤 Filter by User ID", placeholder="User ID...",
        label_visibility="collapsed",
    )
with col_c:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_ip_logs():
    try:
        return get_heavy("/api/ip-tracker/logs", {"limit": _ALL}).get("logs", [])
    except Exception:
        return []

@st.cache_data(ttl=30, show_spinner=False)
def load_ip_stats():
    try:
        return get("/api/ip-tracker/stats")
    except Exception:
        return {}

with st.spinner("Loading IP tracker data..."):
    logs  = load_ip_logs()
    stats = load_ip_stats()

# ── Apply filters ──────────────────────────────────────────────────────────────
if search_query.strip():
    q    = search_query.strip().lower()
    logs = [l for l in logs
            if q in str(l.get("query", "")).lower()
            or q in str(l.get("ip",    "")).lower()]
if search_user.strip():
    u    = search_user.strip().lower()
    logs = [l for l in logs if u in str(l.get("user_id", "")).lower()]

# ── Metric cards ───────────────────────────────────────────────────────────────
total_lookups = stats.get("total_lookups", len(logs))
unique_ips    = len({l.get("query",   "") for l in logs})
unique_users  = len({l.get("user_id", "") for l in logs})
top_country   = stats.get("top_country", "—")

c1, c2, c3, c4 = st.columns(4)
for col, icon, label, value, color, delay in [
    (c1, "🌐", "TOTAL LOOKUPS",  total_lookups, "#7EE7C1", 0.00),
    (c2, "🔎", "UNIQUE QUERIES", unique_ips,    "#00e5ff", 0.08),
    (c3, "👤", "UNIQUE USERS",   unique_users,  "#a855f7", 0.16),
    (c4, "🗺️", "TOP COUNTRY",   top_country,   "#FFA726", 0.24),
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

st.caption(f"Showing **{len(logs)}** lookup records")

if not logs:
    st.info("No IP lookup logs found.")
    st.stop()

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab1, tab2, tab3 = st.tabs(["🕐 Timeline", "📊 Table", "🗺️ Country Breakdown"])

with tab1:
    for log in logs:
        ts      = (log.get("ts") or "")[:16].replace("T", " ")
        query   = log.get("query",   "—")
        user_id = log.get("user_id", "—")
        country = log.get("country", "")
        city    = log.get("city",    "")
        isp     = log.get("isp",     "")
        ip      = log.get("ip",      "")
        success = log.get("success",  True)

        dot_color = "#7EE7C1" if success else "#FF6B6B"

        location_parts = []
        if city:    location_parts.append(city)
        if country: location_parts.append(country)
        location_str = ", ".join(location_parts) if location_parts else "—"

        isp_badge = (
            f"<span style='background:#1a2340;border-radius:6px;padding:3px 8px;"
            f"font-size:11px;color:#7EE7C1'>🖥️ {isp[:35]}</span>"
            if isp else ""
        )
        loc_badge = (
            f"<span style='background:#1a2340;border-radius:6px;padding:3px 8px;"
            f"font-size:11px;color:#38BDF8'>📍 {location_str}</span>"
            if location_str != "—" else ""
        )
        ip_badge = (
            f"<span style='background:#1a2340;border-radius:6px;padding:3px 8px;"
            f"font-size:11px;color:#FFA726'>🔢 {ip}</span>"
            if ip and ip != query else ""
        )

        st.markdown(f"""
        <div style='padding:12px 0;border-bottom:1px solid #1d2c4a'>
            <div style='display:flex;gap:12px;align-items:flex-start'>
                <div style='width:10px;height:10px;border-radius:50%;
                    background:{dot_color};margin-top:5px;flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex;justify-content:space-between;flex-wrap:wrap;gap:6px'>
                        <span style='font-family:monospace;font-weight:700;
                            font-size:13px;color:#7EE7C1'>🌐 {query}</span>
                        <span style='font-size:10px;color:#7a8ab8'>{ts} PHT</span>
                    </div>
                    <div style='margin-top:6px;display:flex;flex-wrap:wrap;gap:8px'>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#A78BFA'>👤 {user_id}</span>
                        {loc_badge}
                        {isp_badge}
                        {ip_badge}
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

with tab2:
    rows = []
    for log in logs:
        ts = (log.get("ts") or "")[:16].replace("T", " ")
        rows.append({
            "Time (PHT)": ts,
            "Query":      log.get("query",   "—"),
            "IP":         log.get("ip",      "—"),
            "Country":    log.get("country", "—"),
            "City":       log.get("city",    "—"),
            "ISP":        (log.get("isp") or "—")[:40],
            "User ID":    log.get("user_id", "—"),
            "Success":    "✅" if log.get("success", True) else "❌",
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_ip_tracker_logs.csv",
        mime      = "text/csv",
    )

with tab3:
    country_counts: dict = {}
    for log in logs:
        c = log.get("country", "Unknown") or "Unknown"
        country_counts[c] = country_counts.get(c, 0) + 1

    if not country_counts:
        st.info("No country data available.")
    else:
        sorted_countries = dict(
            sorted(country_counts.items(), key=lambda x: x[1], reverse=True)[:20]
        )
        max_count = max(sorted_countries.values())
        colors    = ["#7EE7C1","#00e5ff","#FFA726","#a855f7","#f472b6",
                     "#ff9500","#00ff9d","#ff4757","#00b8d4","#38BDF8"]

        for i, (country, count) in enumerate(sorted_countries.items()):
            pct = int((count / max_count) * 100)
            c   = colors[i % len(colors)]
            st.markdown(f"""
            <div style='margin-bottom:10px'>
                <div style='display:flex;justify-content:space-between;margin-bottom:4px'>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:#c8d8f0'>{country}</span>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:{c};font-weight:700'>{count}</span>
                </div>
                <div style='background:rgba(255,255,255,.04);border-radius:3px;height:5px'>
                    <div style='background:{c};width:{pct}%;height:100%;
                        border-radius:3px;box-shadow:0 0 6px {c}66'></div>
                </div>
            </div>""", unsafe_allow_html=True)

        # Also show as sortable dataframe
        st.markdown("<br>", unsafe_allow_html=True)
        df_c = pd.DataFrame([
            {"Country": k, "Lookups": v}
            for k, v in sorted_countries.items()
        ])
        st.dataframe(df_c, use_container_width=True, hide_index=True)
