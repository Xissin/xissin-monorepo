"""
pages/9_Device_Info.py — Device information for all registered app users
Shows model, brand, OS, emulator detection, last seen time.
"""

import streamlit as st
import pandas as pd
from utils.api import get
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(
    page_title="Device Info · Xissin Admin",
    page_icon="📱",
    layout="wide",
)
inject_theme()
auth_guard()

page_header("📱", "Device Info", "HARDWARE · EMULATOR DETECTION · LAST SEEN")

# ── Load ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_devices():
    return get("/api/users/devices").get("devices", [])

col_a, col_b, col_c = st.columns([3, 1, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Filter by user ID, model, brand...")
with col_b:
    platform_filter = st.selectbox("Platform", ["All", "android", "ios"])
with col_c:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with st.spinner("Loading device info..."):
    devices = load_devices()

# ── Filter ─────────────────────────────────────────────────────────────────────
if platform_filter != "All":
    devices = [d for d in devices if d.get("platform", "").lower() == platform_filter]
if search.strip():
    q = search.strip().lower()
    devices = [d for d in devices
               if q in str(d.get("user_id", "")).lower()
               or q in str(d.get("model", "")).lower()
               or q in str(d.get("brand", "")).lower()
               or q in str(d.get("manufacturer", "")).lower()]

# ── Summary metrics ────────────────────────────────────────────────────────────
if devices:
    total        = len(devices)
    android_cnt  = sum(1 for d in devices if d.get("platform") == "android")
    ios_cnt      = sum(1 for d in devices if d.get("platform") == "ios")
    emulator_cnt = sum(1 for d in devices if d.get("is_emulator") is True
                       or d.get("is_physical_device") is False)
    physical_cnt = total - emulator_cnt

    m1, m2, m3, m4, m5 = st.columns(5)
    m1.metric("📱 Total Devices",   total)
    m2.metric("🤖 Android",         android_cnt)
    m3.metric("🍎 iOS",             ios_cnt)
    m4.metric("✅ Physical",        physical_cnt)
    m5.metric("🚨 Emulator / VM",   emulator_cnt)
    st.divider()

st.caption(f"Showing **{len(devices)}** devices")

if not devices:
    st.info("No device data collected yet. Users need to open the app at least once.")
    st.stop()

# ── Cards view ─────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["📋 Cards", "📊 Table"])

with tab1:
    cols_per_row = 3
    for i in range(0, len(devices), cols_per_row):
        row_devices = devices[i:i + cols_per_row]
        cols        = st.columns(cols_per_row)
        for j, device in enumerate(row_devices):
            with cols[j]:
                is_emulator = device.get("is_emulator") is True or \
                              device.get("is_physical_device") is False

                platform    = device.get("platform", "unknown").upper()
                brand       = device.get("brand") or device.get("manufacturer") or "—"
                model       = device.get("model", "Unknown Model")
                os_version  = (
                    device.get("android_version") or
                    device.get("system_version") or "—"
                )
                sdk         = device.get("sdk_int")
                app_version = device.get("app_version", "—")
                last_seen   = (device.get("last_seen") or "")[:16].replace("T", " ")
                user_id     = device.get("user_id", "—")

                border_color = "#FF6B6B" if is_emulator else "#7EE7C1"
                emu_badge    = (
                    '<span style="background:#FF6B6B22; color:#FF6B6B; '
                    'border-radius:4px; padding:2px 6px; font-size:10px; '
                    'font-weight:700">🚨 EMULATOR</span>'
                    if is_emulator else
                    '<span style="background:#7EE7C122; color:#7EE7C1; '
                    'border-radius:4px; padding:2px 6px; font-size:10px; '
                    'font-weight:700">✅ PHYSICAL</span>'
                )
                plat_icon = "🍎" if platform == "IOS" else "🤖"
                sdk_text  = f" · SDK {sdk}" if sdk else ""

                st.markdown(f"""
                <div style='background:#0f1629; border:1px solid {border_color}40;
                    border-left:3px solid {border_color}; border-radius:10px;
                    padding:14px; margin-bottom:10px'>
                    <div style='display:flex; justify-content:space-between;
                        align-items:flex-start; margin-bottom:8px'>
                        <span style='font-size:11px; font-family:monospace;
                            color:#A78BFA'>{user_id[:20]}{"…" if len(user_id)>20 else ""}</span>
                        {emu_badge}
                    </div>
                    <div style='font-size:15px; font-weight:700;
                        color:#e2e8f0; margin-bottom:2px'>
                        {plat_icon} {brand} {model}
                    </div>
                    <div style='font-size:11px; color:#7a8ab8; margin-bottom:8px'>
                        {platform} {os_version}{sdk_text}
                    </div>
                    <div style='display:flex; gap:8px; flex-wrap:wrap'>
                        <span style='background:#1a2340; border-radius:4px;
                            padding:2px 7px; font-size:10px; color:#38BDF8'>
                            App v{app_version}
                        </span>
                        <span style='background:#1a2340; border-radius:4px;
                            padding:2px 7px; font-size:10px; color:#7a8ab8'>
                            🕒 {last_seen} PHT
                        </span>
                    </div>
                </div>
                """, unsafe_allow_html=True)

with tab2:
    rows = []
    for d in devices:
        is_emulator = d.get("is_emulator") is True or d.get("is_physical_device") is False
        rows.append({
            "User ID":       d.get("user_id", "—"),
            "Platform":      (d.get("platform") or "—").upper(),
            "Brand":         d.get("brand") or d.get("manufacturer") or "—",
            "Model":         d.get("model", "—"),
            "OS Version":    d.get("android_version") or d.get("system_version") or "—",
            "SDK":           d.get("sdk_int", "—"),
            "App Version":   d.get("app_version", "—"),
            "Physical?":     "❌ EMULATOR" if is_emulator else "✅ Physical",
            "Last Seen PHT": (d.get("last_seen") or "")[:16].replace("T", " "),
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        label="⬇️ Download as CSV",
        data=csv,
        file_name="xissin_device_info.csv",
        mime="text/csv",
    )

# ── Emulator alert ─────────────────────────────────────────────────────────────
emulators = [d for d in devices
             if d.get("is_emulator") is True or d.get("is_physical_device") is False]
if emulators:
    st.divider()
    st.markdown("### 🚨 Detected Emulators / Virtual Machines")
    st.warning(
        f"**{len(emulators)} suspicious device(s)** detected. "
        "These users are running Xissin on an emulator or virtual machine."
    )
    for d in emulators:
        last_seen = (d.get("last_seen") or "")[:16].replace("T", " ")
        st.markdown(f"""
        <div style='background:#FF6B6B11; border:1px solid #FF6B6B44;
            border-radius:8px; padding:12px; margin-bottom:8px;
            font-size:12px; color:#e2e8f0'>
            <b style='color:#FF6B6B'>🚨 {d.get("user_id", "—")}</b>
            &nbsp;·&nbsp; {(d.get("platform") or "—").upper()}
            &nbsp;·&nbsp; {d.get("brand", "—")} {d.get("model", "—")}
            &nbsp;·&nbsp; OS: {d.get("android_version") or d.get("system_version") or "—"}
            &nbsp;·&nbsp; <span style='color:#7a8ab8'>Last seen: {last_seen} PHT</span>
        </div>
        """, unsafe_allow_html=True)
