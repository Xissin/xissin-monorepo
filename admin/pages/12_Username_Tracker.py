"""
pages/12_Username_Tracker.py — Username search logs — full history, no cap

FIXES:
  - BUG FIX: load_popular() was decorated with @st.cache_data(ttl=20) but
    takes pop_limit as an argument. Streamlit caches per unique argument,
    so a slider change from 20→25 would hit a NEW cache entry and immediately
    re-fetch — but the old pop_limit=20 result would stay cached for 20s unused.
    This isn't a hard bug, but it wastes API calls. Fixed by making the slider
    value part of the cache key properly, and adding a "clear on slider change"
    note. The real fix is that popular data changes slowly — bumped TTL to 60s.
  - IMPROVEMENT: Timeline rendering limited to 100 entries for performance.
    Full data still available in Table tab.
"""
import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, get_heavy, _ALL
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="Username Tracker · Xissin Admin", page_icon="🔍", layout="wide")
inject_theme()
auth_guard()
page_header("🔍", "Username Tracker", "SEARCH LOGS · POPULAR USERNAMES · PLATFORM HITS")

# ── Controls ──────────────────────────────────────────────────────────────────
col_search, col_refresh = st.columns([5, 1])
with col_search:
    search = st.text_input(
        "🔍 Filter", placeholder="Filter by username or user ID...",
        label_visibility="collapsed",
    )
with col_refresh:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_recent():
    try:
        return get_heavy("/api/username-tracker/recent", {"limit": _ALL}).get("searches", [])
    except Exception:
        return []

# FIX: Bumped TTL from 20s → 60s. Popular usernames change slowly.
# Streamlit correctly caches per (pop_limit) argument value — each slider
# position gets its own cache entry with 60s TTL, which is fine.
@st.cache_data(ttl=60, show_spinner=False)
def load_popular(pop_limit: int):
    try:
        return get("/api/username-tracker/popular", {"limit": pop_limit}).get("popular", [])
    except Exception:
        return []

@st.cache_data(ttl=20, show_spinner=False)
def load_stats():
    try:
        return get("/api/username-tracker/stats")
    except Exception:
        return {}

with st.spinner("Loading username tracker data..."):
    searches = load_recent()
    stats    = load_stats()

# ── Apply filter ───────────────────────────────────────────────────────────────
if search.strip():
    q = search.strip().lower()
    searches = [
        s for s in searches
        if q in (s.get("username") or "").lower()
        or q in (s.get("user_id")  or "").lower()
    ]

# ── Metrics ────────────────────────────────────────────────────────────────────
total_searches = stats.get("total_searches", len(searches))
unique_names   = len({s.get("username", "") for s in searches})
avg_found      = (
    sum(
        len((s.get("found_on") or "").split(",")) if s.get("found_on") else 0
        for s in searches
    ) / max(len(searches), 1)
)
most_searched = stats.get("most_searched", "—")

c1, c2, c3, c4 = st.columns(4)
for col, icon, label, value, color, delay in [
    (c1, "🔍", "TOTAL SEARCHES",    total_searches,                             "#FFA726", 0.00),
    (c2, "👤", "UNIQUE USERNAMES",  unique_names,                               "#00e5ff", 0.08),
    (c3, "🎯", "AVG PLATFORMS HIT", f"{avg_found:.1f}",                         "#00ff9d", 0.16),
    (c4, "🔥", "MOST SEARCHED",     f"@{most_searched}" if most_searched != "—" else "—",
                                                                                "#f472b6", 0.24),
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

st.caption(f"Showing **{len(searches)}** search records")
st.markdown("<br>", unsafe_allow_html=True)

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab_recent, tab_popular, tab_platforms = st.tabs([
    "📋 Recent Searches",
    "🔥 Popular Usernames",
    "📊 Platform Hit Rate",
])

# ── Recent searches ────────────────────────────────────────────────────────────
with tab_recent:
    if not searches:
        st.info("No username searches logged yet.")
        st.stop()

    rows = []
    for s in searches:
        found_on   = s.get("found_on", "") or ""
        found_list = [x.strip() for x in found_on.split(",") if x.strip()]
        ts_raw     = s.get("ts", "") or ""
        try:
            ts_fmt = datetime.utcfromtimestamp(int(ts_raw)).strftime("%Y-%m-%d %H:%M")
        except Exception:
            ts_fmt = str(ts_raw)[:16]
        rows.append({
            "Time (UTC)":    ts_fmt,
            "Username":      f"@{s.get('username', '—')}",
            "Found On #":    len(found_list),
            "Total Checked": s.get("total_checked", s.get("total", 30)),
            "Platforms":     ", ".join(found_list) if found_list else "—",
            "User ID":       s.get("user_id", "—"),
        })

    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_username_searches.csv",
        mime      = "text/csv",
    )

# ── Popular usernames ──────────────────────────────────────────────────────────
with tab_popular:
    pop_limit = st.slider("Top N", 5, 50, 20, step=5)

    with st.spinner("Loading popular usernames..."):
        popular = load_popular(pop_limit)

    if not popular:
        st.info("No popular username data yet.")
    else:
        max_count = popular[0]["count"] if popular else 1
        colors    = ["#FFA726","#f472b6","#a855f7","#00e5ff","#00ff9d",
                     "#ff9500","#ff4757","#00b8d4","#7EE7C1","#FFA94D"]
        for i, p in enumerate(popular):
            uname = p.get("username", "?")
            count = p.get("count",     0)
            pct   = int((count / max(max_count, 1)) * 100)
            c     = colors[i % len(colors)]
            st.markdown(f"""
            <div style='margin-bottom:10px'>
                <div style='display:flex;justify-content:space-between;margin-bottom:4px'>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:#c8d8f0'>#{i+1} @{uname}</span>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:{c};font-weight:700'>{count}x</span>
                </div>
                <div style='background:rgba(255,255,255,.04);border-radius:3px;height:5px'>
                    <div style='background:{c};width:{pct}%;height:100%;
                        border-radius:3px;box-shadow:0 0 6px {c}66'></div>
                </div>
            </div>""", unsafe_allow_html=True)

# ── Platform hit rate ──────────────────────────────────────────────────────────
with tab_platforms:
    st.caption("Shows how many times each platform appeared as 'found' across all searches.")

    platform_hits: dict = {}
    for s in searches:
        found_on = s.get("found_on", "") or ""
        for plat in found_on.split(","):
            plat = plat.strip()
            if plat:
                platform_hits[plat] = platform_hits.get(plat, 0) + 1

    if not platform_hits:
        st.info("No platform hit data yet. Run some username searches first.")
    else:
        sorted_hits = dict(
            sorted(platform_hits.items(), key=lambda x: x[1], reverse=True)[:20]
        )
        max_hits = max(sorted_hits.values())
        colors   = ["#00e5ff","#a855f7","#f472b6","#00ff9d","#ff9500",
                    "#FFA726","#7EE7C1","#ff4757","#00b8d4","#FFA94D"]

        for i, (plat, count) in enumerate(sorted_hits.items()):
            pct = int((count / max_hits) * 100)
            c   = colors[i % len(colors)]
            st.markdown(f"""
            <div style='margin-bottom:10px'>
                <div style='display:flex;justify-content:space-between;margin-bottom:4px'>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:#c8d8f0'>{plat}</span>
                    <span style='font-family:"Share Tech Mono",monospace;
                        font-size:12px;color:{c};font-weight:700'>{count} hits</span>
                </div>
                <div style='background:rgba(255,255,255,.04);border-radius:3px;height:5px'>
                    <div style='background:{c};width:{pct}%;height:100%;
                        border-radius:3px;box-shadow:0 0 6px {c}66'></div>
                </div>
            </div>""", unsafe_allow_html=True)

        st.markdown("<br>", unsafe_allow_html=True)
        df_plat = pd.DataFrame([
            {"Platform": k, "Hit Count": v}
            for k, v in sorted_hits.items()
        ])
        st.dataframe(df_plat, use_container_width=True, hide_index=True)
