"""
pages/10_User_Map.py — Live user location map
Fixes applied:
  - Merged Philippines + World map into ONE map (auto-zooms to PH on open)
  - Location Table shown BELOW the map (no need to click a tab)
  - Removed </div> render bug in the legend/info column
  - Export tab kept as a separate tab
  - All original filters, stats, and features preserved
"""

import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(
    page_title="User Map · Xissin Admin",
    page_icon="📍",
    layout="wide",
)
inject_theme()
auth_guard()

# ── Safe folium import ────────────────────────────────────────────────────────
try:
    import folium
    from folium.plugins import MiniMap, Fullscreen, MarkerCluster, HeatMap
    from streamlit_folium import st_folium
    FOLIUM_OK = True
except ImportError as _e:
    FOLIUM_OK = False
    _folium_err_msg = str(_e)

page_header("📍", "User Map", "GLOBAL LOCATION TRACKER · PREMIUM · ANALYTICS")

if not FOLIUM_OK:
    st.error(
        f"❌ **Map library not installed:** `{_folium_err_msg}`\n\n"
        "Make sure `admin/requirements.txt` has `folium` and "
        "`streamlit-folium`, then redeploy."
    )
    st.stop()

from utils.api import get, post


# ── Helpers ───────────────────────────────────────────────────────────────────

def format_time(ts_str: str) -> str:
    try:
        return datetime.fromisoformat(ts_str).strftime("%b %d, %Y %I:%M %p")
    except Exception:
        return ts_str or "Unknown"


def time_ago(ts_str: str) -> str:
    try:
        dt = datetime.fromisoformat(ts_str)
        diff = datetime.now() - dt
        if diff < timedelta(minutes=1):
            return "Just now"
        if diff < timedelta(hours=1):
            return f"{int(diff.seconds / 60)}m ago"
        if diff < timedelta(days=1):
            return f"{int(diff.seconds / 3600)}h ago"
        return f"{diff.days}d ago"
    except Exception:
        return "Unknown"


def is_ph(lat: float, lng: float) -> bool:
    return 4.5 <= lat <= 21.5 and 116.0 <= lng <= 127.0


# ── Fetch data ─────────────────────────────────────────────────────────────────

@st.cache_data(ttl=30, show_spinner=False)
def load_locations():
    try:
        data = get("/api/location/all")
        if isinstance(data, dict):
            return list(data.values())
        if isinstance(data, list):
            return data
        return []
    except Exception as e:
        st.warning(f"⚠️ Could not load locations: {e}")
        return []


@st.cache_data(ttl=60, show_spinner=False)
def load_users():
    try:
        data = get("/api/users/list")
        if isinstance(data, dict) and "users" in data:
            return {u["user_id"]: u for u in data["users"] if "user_id" in u}
        if isinstance(data, dict):
            return data
        return {}
    except Exception:
        return {}


@st.cache_data(ttl=60, show_spinner=False)
def load_premium():
    try:
        data = get("/api/payments/admin/premium")
        return set(data.get("premium_users", {}).keys())
    except Exception:
        return set()


# ── Top action buttons ─────────────────────────────────────────────────────────
col_r, col_c, col_s1, col_s2, col_s3, col_s4 = st.columns([1, 1, 1, 1, 1, 1])

with col_r:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with col_c:
    if st.button("🗑️ Clear All", use_container_width=True, type="secondary"):
        try:
            post("/api/location/clear", {})
            st.cache_data.clear()
            st.success("Locations cleared.")
            st.rerun()
        except Exception as e:
            st.error(f"Error: {e}")

with st.spinner("Loading map data..."):
    locations = load_locations()
    users = load_users()
    premium_uids = load_premium()

# ── Classify locations ────────────────────────────────────────────────────────
ph_locs = []
world_locs = []

for loc in locations:
    try:
        lat = float(loc.get("lat", 0))
        lng = float(loc.get("lng", 0))
        if is_ph(lat, lng):
            ph_locs.append(loc)
        else:
            world_locs.append(loc)
    except (TypeError, ValueError):
        continue

with col_s1:
    st.metric("📍 Total Tracked", len(locations))
with col_s2:
    st.metric("🇵🇭 Philippines", len(ph_locs))
with col_s3:
    st.metric("🌍 Outside PH", len(world_locs))
with col_s4:
    st.metric("⭐ Premium Users", len(premium_uids))

st.divider()

# ── Filters ───────────────────────────────────────────────────────────────────
f1, f2, f3 = st.columns([1, 1, 1])
with f1:
    filter_premium = st.selectbox(
        "Filter by status",
        ["All Users", "⭐ Premium Only", "Free Users Only"],
        label_visibility="collapsed",
    )
with f2:
    filter_time = st.selectbox(
        "Filter by last seen",
        ["All Time", "Last 24 Hours", "Last 7 Days", "Last 30 Days"],
        label_visibility="collapsed",
    )
with f3:
    map_style = st.selectbox(
        "Map style",
        ["Dark (CartoDB)", "Satellite (Esri)", "Street (OpenStreetMap)", "Heatmap"],
        label_visibility="collapsed",
    )


# ── Apply filters ─────────────────────────────────────────────────────────────
def apply_filters(locs):
    result = []
    now = datetime.now()
    for loc in locs:
        uid = loc.get("user_id", "")

        if filter_premium == "⭐ Premium Only" and uid not in premium_uids:
            continue
        if filter_premium == "Free Users Only" and uid in premium_uids:
            continue

        if filter_time != "All Time":
            ts = loc.get("updated_at", "")
            try:
                dt = datetime.fromisoformat(ts)
                diff = now - dt
                if filter_time == "Last 24 Hours" and diff > timedelta(hours=24):
                    continue
                if filter_time == "Last 7 Days" and diff > timedelta(days=7):
                    continue
                if filter_time == "Last 30 Days" and diff > timedelta(days=30):
                    continue
            except Exception:
                pass

        result.append(loc)
    return result


filtered_ph = apply_filters(ph_locs)
filtered_world = apply_filters(world_locs)
filtered_all = filtered_ph + filtered_world


# ── Build tile URL ─────────────────────────────────────────────────────────────
def _tile_url(style: str):
    if style == "Satellite (Esri)":
        return (
            "https://server.arcgisonline.com/ArcGIS/rest/services/"
            "World_Imagery/MapServer/tile/{z}/{y}/{x}",
            "Esri WorldImagery",
        )
    if style == "Street (OpenStreetMap)":
        return (
            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            "OpenStreetMap",
        )
    return None, "CartoDB dark_matter"


# ── Build map ─────────────────────────────────────────────────────────────────
def build_map(locs, center, zoom):
    """
    Single unified map. center + zoom set to Philippines by default.
    All worldwide markers are still plotted — user can pan/zoom out freely.
    """
    tile_url, tile_name = _tile_url(map_style)

    if tile_url:
        m = folium.Map(location=center, zoom_start=zoom, prefer_canvas=True)
        folium.TileLayer(tile_url, name=tile_name, attr=tile_name).add_to(m)
    else:
        m = folium.Map(
            location=center,
            zoom_start=zoom,
            tiles="CartoDB dark_matter",
            prefer_canvas=True,
        )

    try:
        MiniMap(toggle_display=True).add_to(m)
        Fullscreen().add_to(m)
    except Exception:
        pass

    # Heatmap mode
    if map_style == "Heatmap":
        heat_data = []
        for loc in locs:
            try:
                heat_data.append([float(loc["lat"]), float(loc["lng"])])
            except Exception:
                pass
        if heat_data:
            HeatMap(heat_data, radius=20, blur=15, min_opacity=0.4).add_to(m)
        return m

    # Normal markers with clustering
    try:
        cluster = MarkerCluster(
            options={"maxClusterRadius": 40, "disableClusteringAtZoom": 12}
        ).add_to(m)
        use_cluster = True
    except Exception:
        cluster = m
        use_cluster = False

    for loc in locs:
        try:
            lat = float(loc["lat"])
            lng = float(loc["lng"])
            uid = loc.get("user_id", "unknown")
            accuracy = loc.get("accuracy")
            updated = format_time(loc.get("updated_at", ""))
            ago = time_ago(loc.get("updated_at", ""))
            city = loc.get("city", "") or "—"
            region = loc.get("region", "") or "—"
            country = loc.get("country", "") or ("PH" if is_ph(lat, lng) else "—")

            user_data = users.get(uid, {})
            username = (
                user_data.get("username")
                or user_data.get("telegram_name")
                or uid[:10] + "..."
            )

            is_premium_user = uid in premium_uids
            acc_text = f"{float(accuracy):.0f}m" if accuracy else "N/A"

            if is_premium_user:
                icon_color = "orange"
                icon_name = "star"
                status_line = "⭐ Premium — Ad-Free"
            elif is_ph(lat, lng):
                icon_color = "green"
                icon_name = "user"
                status_line = "👤 Free User (PH)"
            else:
                icon_color = "red"
                icon_name = "globe"
                status_line = "🌍 Outside PH"

            premium_badge = (
                "<div style='background:#FFD70022; border:1px solid #FFD70066;"
                "border-radius:4px; padding:2px 6px; margin:4px 0; font-size:11px;"
                "color:#FFD700'>⭐ PREMIUM — Remove Ads Purchased</div>"
                if is_premium_user
                else ""
            )

            popup_html = (
                "<div style='font-family:monospace; min-width:220px; font-size:13px'>"
                "<div style='background:#1e3a5f; color:#5B8CFF; padding:6px 10px;"
                "font-weight:700; border-radius:6px 6px 0 0; margin:-5px -5px 8px'>"
                f"📍 {username}"
                "</div>"
                f"{premium_badge}"
                f"<b>User ID:</b> {uid[:18]}{'...' if len(uid) > 18 else ''}<br>"
                f"<b>City:</b> {city}<br>"
                f"<b>Region:</b> {region}<br>"
                f"<b>Country:</b> {country}<br>"
                f"<b>Accuracy:</b> {acc_text}<br>"
                f"<b>Status:</b> {status_line}<br>"
                f"<b>Last seen:</b> {updated}<br>"
                f"<b style='color:#7EE7C1'>{ago}</b>"
                "</div>"
            )

            marker = folium.Marker(
                location=[lat, lng],
                popup=folium.Popup(popup_html, max_width=280),
                tooltip=f"{'⭐' if is_premium_user else '👤'} {username} · {ago}",
                icon=folium.Icon(color=icon_color, icon=icon_name, prefix="fa"),
            )

            if accuracy and float(accuracy) < 5000:
                circle_color = "#FFD700" if is_premium_user else "#5B8CFF"
                folium.Circle(
                    location=[lat, lng],
                    radius=float(accuracy),
                    color=circle_color,
                    fill=True,
                    fill_color=circle_color,
                    fill_opacity=0.08,
                    weight=1,
                ).add_to(m)

            if use_cluster:
                marker.add_to(cluster)
            else:
                marker.add_to(m)

        except Exception:
            continue

    return m


# ── TABS: Map+Table  |  Export ─────────────────────────────────────────────────
tab_map, tab_export = st.tabs(["🗺️ Map & Locations", "📥 Export"])

# ══════════════════════════════════════════════════════════════════════════════
# TAB 1 — UNIFIED MAP + LOCATION TABLE BELOW
# ══════════════════════════════════════════════════════════════════════════════
with tab_map:

    # ── Map section ───────────────────────────────────────────────────────────
    map_col, info_col = st.columns([3, 1])

    with map_col:
        if not filtered_all:
            st.info("📡 No locations match the current filters.")
        else:
            # Always open zoomed into Philippines; user can pan out to see world
            m = build_map(filtered_all, center=[12.8797, 121.7740], zoom=6)
            st_folium(
                m,
                width=None,
                height=580,
                returned_objects=[],
                use_container_width=True,
                key="map_unified",
            )

    with info_col:
        # ── Legend ────────────────────────────────────────────────────────────
        st.markdown("### 📊 Legend")
        with st.container(border=True):
            st.markdown(
                "<div style='font-size:13px; line-height:2.4'>"
                "🟠 <b>Orange ⭐</b> — Premium user<br>"
                "🟢 <b>Green</b> — Free user (PH)<br>"
                "🔴 <b>Red</b> — Outside PH<br>"
                "⭕ <b>Circle</b> — GPS accuracy<br>"
                "🔵 <b>Cluster</b> — Multiple nearby"
                "</div>",
                unsafe_allow_html=True,
            )

        # ── Stats ─────────────────────────────────────────────────────────────
        st.markdown("### 📈 Stats")
        with st.container(border=True):
            ph_premium = sum(
                1 for loc in filtered_ph if loc.get("user_id") in premium_uids
            )
            st.metric("Total on Map", len(filtered_all))
            st.metric("🇵🇭 PH Users", len(filtered_ph))
            st.metric("🌍 Outside PH", len(filtered_world))
            st.metric("⭐ PH Premium", ph_premium)

        # ── Last refresh ──────────────────────────────────────────────────────
        st.markdown("### 🕒 Last Refresh")
        with st.container(border=True):
            st.markdown(
                f"<div style='font-size:12px; color:#7EE7C1'>"
                f"{datetime.now().strftime('%b %d %Y %I:%M:%S %p')}</div>",
                unsafe_allow_html=True,
            )

    # ── Location Table (always visible, scroll down) ──────────────────────────
    st.divider()
    st.markdown("### 📋 Location Table")

    if not locations:
        st.info("No location records found.")
    else:
        rows = []
        for loc in locations:
            uid = loc.get("user_id", "—")
            user_d = users.get(uid, {})
            username = user_d.get("username") or user_d.get("telegram_name") or "—"
            is_prem = uid in premium_uids

            try:
                lat_val = round(float(loc.get("lat", 0)), 4)
                lng_val = round(float(loc.get("lng", 0)), 4)
            except Exception:
                lat_val = lng_val = 0

            rows.append({
                "User ID":   uid[:18] + ("..." if len(uid) > 18 else ""),
                "Username":  username,
                "Premium":   "⭐ Yes" if is_prem else "—",
                "Latitude":  lat_val,
                "Longitude": lng_val,
                "Accuracy":  f"{float(loc['accuracy']):.0f}m"
                             if loc.get("accuracy") else "—",
                "City":      loc.get("city", "") or "—",
                "Region":    loc.get("region", "") or "—",
                "Country":   loc.get("country", "")
                             or ("PH" if is_ph(lat_val, lng_val) else "—"),
                "In PH":     "🇵🇭" if is_ph(lat_val, lng_val) else "🌍",
                "Last Seen": format_time(loc.get("updated_at", "")),
                "Time Ago":  time_ago(loc.get("updated_at", "")),
            })

        df = pd.DataFrame(rows)

        # Search box
        search = st.text_input(
            "🔍 Search by User ID, Username, City, or Region",
            placeholder="Type to filter...",
            label_visibility="collapsed",
        )
        if search:
            mask = (
                df["User ID"].str.contains(search, case=False, na=False)
                | df["City"].str.contains(search, case=False, na=False)
                | df["Region"].str.contains(search, case=False, na=False)
                | df["Username"].str.contains(search, case=False, na=False)
            )
            df = df[mask]

        st.dataframe(df, use_container_width=True, height=420, hide_index=True)
        st.caption(f"Showing {len(df)} of {len(rows)} records")


# ══════════════════════════════════════════════════════════════════════════════
# TAB 2 — EXPORT
# ══════════════════════════════════════════════════════════════════════════════
with tab_export:
    st.markdown("### 📥 Export Location Data")
    st.caption("Download all location records as a CSV file.")

    if not locations:
        st.info("No data to export.")
    else:
        export_rows = []
        for loc in locations:
            uid = loc.get("user_id", "")
            user_d = users.get(uid, {})
            try:
                lat_val = round(float(loc.get("lat", 0)), 6)
                lng_val = round(float(loc.get("lng", 0)), 6)
            except Exception:
                lat_val = lng_val = 0

            export_rows.append({
                "user_id":   uid,
                "username":  user_d.get("username") or "—",
                "premium":   "yes" if uid in premium_uids else "no",
                "latitude":  lat_val,
                "longitude": lng_val,
                "accuracy":  loc.get("accuracy", ""),
                "city":      loc.get("city", "") or "",
                "region":    loc.get("region", "") or "",
                "country":   loc.get("country", "") or "",
                "in_ph":     "yes" if is_ph(lat_val, lng_val) else "no",
                "last_seen": loc.get("updated_at", ""),
            })

        df_export = pd.DataFrame(export_rows)
        csv = df_export.to_csv(index=False)

        st.download_button(
            label="⬇️  Download CSV",
            data=csv,
            file_name=f"xissin_locations_{datetime.now().strftime('%Y%m%d_%H%M')}.csv",
            mime="text/csv",
            type="primary",
            use_container_width=True,
        )
        st.dataframe(df_export.head(10), use_container_width=True, hide_index=True)
        st.caption(f"Preview — first 10 of {len(export_rows)} rows")
