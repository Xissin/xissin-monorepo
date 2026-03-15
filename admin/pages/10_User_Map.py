"""
pages/10_User_Map.py — Live Philippines user location map
Shows all users who have location services enabled as pins on an interactive map.
Admin only — users never see this page.
"""

import streamlit as st
import pandas as pd
from datetime import datetime

st.set_page_config(
    page_title="User Map · Xissin Admin",
    page_icon="📍",
    layout="wide",
)

if not st.session_state.get("authenticated"):
    st.warning("⚠️ Please login first.")
    st.stop()

# ── Custom CSS ─────────────────────────────────────────────────────────────────
st.markdown("""
<style>
[data-testid="stAppViewContainer"] { background: #08101f; }
[data-testid="stSidebar"]          { background: #0d1830; border-right: 1px solid #1d2c4a; }
[data-testid="stSidebar"] *        { color: #eef2ff !important; }
[data-testid="stHeader"]           { display: none; }
[data-testid="metric-container"] {
    background: #0d1830;
    border: 1px solid #1d2c4a;
    border-radius: 14px;
    padding: 16px !important;
}
.stButton > button {
    border-radius: 10px !important;
    font-weight: 700 !important;
    border: 1px solid #1d2c4a !important;
}
hr { border-color: #1d2c4a !important; }
</style>
""", unsafe_allow_html=True)

# ── Safe folium import ─────────────────────────────────────────────────────────
# If folium is not installed yet (admin not redeployed), the page will still
# SHOW in the sidebar and display a clear error instead of vanishing silently.
try:
    import folium
    from folium.plugins import MiniMap, Fullscreen, MarkerCluster
    from streamlit_folium import st_folium
    FOLIUM_OK = True
except ImportError as _e:
    FOLIUM_OK       = False
    _folium_err_msg = str(_e)

st.markdown("## 📍 User Location Map")
st.markdown("Real-time Philippines map — shows last known location of each user.")
st.divider()

# ── Show clear install error if folium is missing ──────────────────────────────
if not FOLIUM_OK:
    st.error(
        f"❌ **Map library not installed:** `{_folium_err_msg}`\n\n"
        "**How to fix:**\n"
        "1. Make sure `admin/requirements.txt` has `folium==0.17.0` and `streamlit-folium==0.20.0`\n"
        "2. Push to GitHub → Railway will auto-redeploy\n"
        "3. Reload this page after redeploy"
    )
    st.code("folium==0.17.0\nstreamlit-folium==0.20.0", language="text")
    st.stop()

# ── API helpers ────────────────────────────────────────────────────────────────
from utils.api import get, post

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
        data = get("/api/users/")
        if isinstance(data, dict):
            return data
        return {}
    except Exception:
        return {}

# ── Controls ───────────────────────────────────────────────────────────────────
col_refresh, col_clear, col_stats, col_stats2, col_stats3 = st.columns([1, 1, 1, 1, 1])

with col_refresh:
    if st.button("🔄 Refresh Map", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with col_clear:
    if st.button("🗑️ Clear All Locations", use_container_width=True, type="secondary"):
        try:
            post("/api/location/clear", {})
            st.cache_data.clear()
            st.success("Locations cleared.")
            st.rerun()
        except Exception as e:
            st.error(f"Error: {e}")

with st.spinner("Loading locations..."):
    locations = load_locations()
    users     = load_users()

# ── Filter Philippines bounding box ───────────────────────────────────────────
PH_LAT_MIN, PH_LAT_MAX =  4.5,  21.5
PH_LNG_MIN, PH_LNG_MAX = 116.0, 127.0

valid_locs = []
for loc in locations:
    try:
        lat = float(loc.get("lat", 0))
        lng = float(loc.get("lng", 0))
        if PH_LAT_MIN <= lat <= PH_LAT_MAX and PH_LNG_MIN <= lng <= PH_LNG_MAX:
            valid_locs.append(loc)
    except (TypeError, ValueError):
        continue

with col_stats:
    st.metric("📍 Total Tracked", len(locations))
with col_stats2:
    st.metric("🇵🇭 In Philippines", len(valid_locs))
with col_stats3:
    st.metric("🌍 Outside PH", len(locations) - len(valid_locs))

st.divider()

# ── Build Folium Map ───────────────────────────────────────────────────────────
PH_CENTER = [12.8797, 121.7740]

m = folium.Map(
    location=PH_CENTER,
    zoom_start=6,
    tiles="CartoDB dark_matter",
    prefer_canvas=True,
)

try:
    MiniMap(toggle_display=True, tile_layer="CartoDB dark_matter").add_to(m)
    Fullscreen().add_to(m)
    cluster     = MarkerCluster(
        options={"maxClusterRadius": 40, "disableClusteringAtZoom": 12}
    ).add_to(m)
    use_cluster = True
except Exception:
    use_cluster = False
    cluster     = m

def format_time(ts_str: str) -> str:
    try:
        dt = datetime.fromisoformat(ts_str)
        return dt.strftime("%b %d, %Y %I:%M %p")
    except Exception:
        return ts_str or "Unknown"

# ── Add markers ────────────────────────────────────────────────────────────────
pinned = 0
for loc in valid_locs:
    try:
        lat       = float(loc["lat"])
        lng       = float(loc["lng"])
        uid       = loc.get("user_id", "unknown")
        accuracy  = loc.get("accuracy")
        updated   = format_time(loc.get("updated_at", ""))
        city      = loc.get("city",   "")
        region    = loc.get("region", "")
        user_data = users.get(uid, {})
        username  = (
            user_data.get("username")
            or user_data.get("telegram_name")
            or uid[:8] + "..."
        )
        has_key   = "🔑 Active Key" if user_data.get("key_active") else "🔒 No Key"
        acc_text  = f"{float(accuracy):.0f}m" if accuracy else "N/A"
        city_line = f"<b>City:</b> {city}<br>"    if city   else ""
        reg_line  = f"<b>Region:</b> {region}<br>" if region else ""

        popup_html = f"""
        <div style='font-family:monospace; min-width:200px; font-size:13px'>
            <div style='background:#1e3a5f; color:#5B8CFF; padding:6px 10px;
                font-weight:700; border-radius:6px 6px 0 0; margin:-5px -5px 8px'>
                📍 {username}
            </div>
            <b>User ID:</b> {uid[:16]}...<br>
            {city_line}{reg_line}
            <b>Accuracy:</b> {acc_text}<br>
            <b>Status:</b> {has_key}<br>
            <b>Last seen:</b> {updated}
        </div>
        """

        icon_color = "green" if user_data.get("key_active") else "blue"
        marker = folium.Marker(
            location=[lat, lng],
            popup=folium.Popup(popup_html, max_width=260),
            tooltip=f"👤 {username}",
            icon=folium.Icon(color=icon_color, icon="user", prefix="fa"),
        )

        if accuracy and float(accuracy) < 5000:
            folium.Circle(
                location=[lat, lng],
                radius=float(accuracy),
                color="#5B8CFF",
                fill=True,
                fill_color="#5B8CFF",
                fill_opacity=0.08,
                weight=1,
            ).add_to(m)

        if use_cluster:
            marker.add_to(cluster)
        else:
            marker.add_to(m)

        pinned += 1
    except Exception:
        continue

# ── Render map ─────────────────────────────────────────────────────────────────
if len(locations) == 0:
    st.info(
        "📡 **No location data yet.**\n\n"
        "Users need to allow location permission when the Xissin app asks. "
        "Once they do, their pin will appear here automatically."
    )
elif pinned == 0:
    st.warning(
        f"⚠️ {len(locations)} record(s) found but none are inside Philippines coordinates."
    )

map_col, info_col = st.columns([3, 1])

with map_col:
    st_folium(
        m,
        width=None,
        height=600,
        returned_objects=[],
        use_container_width=True,
    )

with info_col:
    st.markdown("### 📊 Legend")
    with st.container(border=True):
        st.markdown("""
        <div style='font-size:13px; line-height:2.2'>
            🟢 <b>Green</b> — Active key<br>
            🔵 <b>Blue</b> — No active key<br>
            ⭕ <b>Circle</b> — GPS accuracy<br>
            🔵 <b>Cluster</b> — Multiple nearby
        </div>
        """, unsafe_allow_html=True)

    st.markdown("### ℹ️ Info")
    with st.container(border=True):
        st.markdown("""
        <div style='font-size:12px; color:#7a8ab8; line-height:1.9'>
            Refreshes every <b>30s</b>.<br>
            Philippines only.<br>
            Click pin for details.<br>
            Admin eyes only 👁️
        </div>
        """, unsafe_allow_html=True)

    st.markdown("### 🕒 Updated")
    with st.container(border=True):
        st.markdown(
            f"<div style='font-size:12px; color:#7EE7C1'>"
            f"{datetime.now().strftime('%b %d %Y, %I:%M:%S %p')}"
            f"</div>",
            unsafe_allow_html=True,
        )

st.divider()

# ── Location table ─────────────────────────────────────────────────────────────
if locations:
    st.markdown("### 📋 Location Records")
    rows = []
    for loc in locations:
        uid      = loc.get("user_id", "—")
        user_d   = users.get(uid, {})
        username = user_d.get("username") or user_d.get("telegram_name") or "—"
        try:
            lat_val = round(float(loc.get("lat", 0)), 5)
            lng_val = round(float(loc.get("lng", 0)), 5)
        except Exception:
            lat_val = lng_val = 0
        rows.append({
            "User ID":     uid[:16] + ("..." if len(uid) > 16 else ""),
            "Username":    username,
            "Latitude":    lat_val,
            "Longitude":   lng_val,
            "Accuracy":    f"{float(loc['accuracy']):.0f}m" if loc.get("accuracy") else "—",
            "City":        loc.get("city")   or "—",
            "Region":      loc.get("region") or "—",
            "Last Update": format_time(loc.get("updated_at", "")),
        })
    df = pd.DataFrame(rows)
    st.dataframe(df, use_container_width=True, height=300)
