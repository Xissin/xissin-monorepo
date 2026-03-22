"""
pages/9_Device_Info.py — Rich device information for all registered app users

New fields displayed:
  - Battery level + state (with visual bar)
  - Network type (WiFi / mobile / none)
  - Screen resolution + pixel density
  - Locale + Timezone
  - CPU / ABI support (Android)
  - Security patch date + Base OS (Android)
  - Bootloader, Codename, Fingerprint
  - App build number + package name
  - Brand breakdown chart
  - Android version breakdown chart
  - Battery overview
  - Network type breakdown
  - Screen resolution distribution
  - Security patch age analysis
"""

import streamlit as st
import pandas as pd
from collections import Counter
from utils.api import get, post
from utils.theme import inject_theme, page_header, auth_guard, notify, render_notify

st.set_page_config(
    page_title="Device Info · Xissin Admin",
    page_icon="📱",
    layout="wide",
)
inject_theme()
auth_guard()

render_notify()  # ← shows queued toasts after rerun
page_header("📱", "Device Info", "HARDWARE · OS · BATTERY · NETWORK · SECURITY")

# ── Load ───────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_devices():
    return get("/api/users/devices").get("devices", [])

# ── Top controls ───────────────────────────────────────────────────────────────
col_a, col_b, col_c, col_d = st.columns([3, 1, 1, 1])
with col_a:
    search = st.text_input("🔍 Search",
        placeholder="Filter by user ID, model, brand, locale, timezone...")
with col_b:
    platform_filter = st.selectbox("Platform", ["All", "android", "ios"])
with col_c:
    network_filter = st.selectbox("Network", ["All", "wifi", "mobile", "none"])
with col_d:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        notify("Device info refreshed.", kind="info")
        st.rerun()

with st.spinner("Loading device info..."):
    devices = load_devices()

# ── Apply filters ──────────────────────────────────────────────────────────────
if platform_filter != "All":
    devices = [d for d in devices
               if d.get("platform", "").lower() == platform_filter]
if network_filter != "All":
    devices = [d for d in devices
               if d.get("network_type", "").lower() == network_filter]
if search.strip():
    q = search.strip().lower()
    devices = [d for d in devices
               if q in str(d.get("user_id",      "")).lower()
               or q in str(d.get("model",        "")).lower()
               or q in str(d.get("brand",        "")).lower()
               or q in str(d.get("manufacturer", "")).lower()
               or q in str(d.get("locale",       "")).lower()
               or q in str(d.get("timezone",     "")).lower()]

# ── Summary metrics ────────────────────────────────────────────────────────────
if devices:
    total        = len(devices)
    android_cnt  = sum(1 for d in devices if d.get("platform") == "android")
    ios_cnt      = sum(1 for d in devices if d.get("platform") == "ios")
    emulator_cnt = sum(1 for d in devices
                       if d.get("is_emulator") is True
                       or d.get("is_physical_device") is False)
    physical_cnt = total - emulator_cnt
    wifi_cnt     = sum(1 for d in devices if d.get("network_type", "") == "wifi")
    mobile_cnt   = sum(1 for d in devices if d.get("network_type", "") == "mobile")
    charging_cnt = sum(1 for d in devices if d.get("battery_state", "") == "charging")
    batt_vals    = [d.get("battery_level") for d in devices
                    if d.get("battery_level") is not None]
    avg_batt     = int(sum(batt_vals) / len(batt_vals)) if batt_vals else None

    m1, m2, m3, m4, m5, m6, m7, m8 = st.columns(8)
    m1.metric("📱 Total",       total)
    m2.metric("🤖 Android",     android_cnt)
    m3.metric("🍎 iOS",         ios_cnt)
    m4.metric("✅ Physical",    physical_cnt)
    m5.metric("🚨 Emulator",    emulator_cnt)
    m6.metric("📶 WiFi",        wifi_cnt)
    m7.metric("📡 Mobile Data", mobile_cnt)
    m8.metric("🔋 Avg Battery", f"{avg_batt}%" if avg_batt is not None else "—")
    st.divider()

st.caption(f"Showing **{len(devices)}** devices")

if not devices:
    st.info("No device data collected yet. Users need to open the app at least once.")
    st.stop()

# ── Chart colors palette ───────────────────────────────────────────────────────
PALETTE = ["#00e5ff","#a855f7","#f472b6","#00ff9d","#ff9500",
           "#ff4757","#38BDF8","#ffd700","#7EE7C1","#ff6b6b"]

# ══════════════════════════════════════════════════════════════════════════════
# TABS
# ══════════════════════════════════════════════════════════════════════════════
tab_cards, tab_table, tab_analytics, tab_security = st.tabs([
    "📋 Device Cards",
    "📊 Full Table",
    "📈 Analytics",
    "🚨 Security",
])


# ─────────────────────────────────────────────────────────────────────────────
# TAB 1 — DEVICE CARDS
# ─────────────────────────────────────────────────────────────────────────────
with tab_cards:
    COLS_PER_ROW = 2
    for i in range(0, len(devices), COLS_PER_ROW):
        row_devices = devices[i:i + COLS_PER_ROW]
        cols        = st.columns(COLS_PER_ROW)
        for j, d in enumerate(row_devices):
            with cols[j]:
                is_emulator  = (d.get("is_emulator") is True
                                or d.get("is_physical_device") is False)
                platform     = d.get("platform", "unknown").upper()
                brand        = d.get("brand") or d.get("manufacturer") or "—"
                model        = d.get("model", "Unknown")
                os_ver       = (d.get("android_version")
                                or d.get("system_version") or "—")
                sdk          = d.get("sdk_int")
                sec_patch    = d.get("security_patch",    "") or ""
                codename     = d.get("codename",          "") or ""
                app_ver      = d.get("app_version",       "—")
                build_num    = d.get("app_build_number",  "") or ""
                pkg_name     = d.get("package_name",      "") or ""
                last_seen    = (d.get("last_seen") or "")[:16].replace("T", " ")
                user_id      = d.get("user_id", "—")
                battery_lvl  = d.get("battery_level")
                battery_st   = d.get("battery_state",     "") or ""
                network      = d.get("network_type",      "") or "—"
                screen_res   = d.get("screen_resolution", "") or "—"
                screen_den   = d.get("screen_density",    "") or ""
                locale       = d.get("locale",            "") or "—"
                timezone     = d.get("timezone",          "") or "—"
                abis         = d.get("supported_abis",    []) or []
                hardware     = d.get("hardware",          "") or ""
                product      = d.get("product",           "") or ""
                fingerprint  = d.get("fingerprint",       "") or ""
                bootloader   = d.get("bootloader",        "") or ""

                border_color = "#FF6B6B" if is_emulator else "#7EE7C1"
                emu_badge = (
                    '<span style="background:#FF6B6B22;color:#FF6B6B;'
                    'border-radius:4px;padding:2px 7px;font-size:10px;font-weight:700">'
                    '🚨 EMULATOR</span>'
                    if is_emulator else
                    '<span style="background:#7EE7C122;color:#7EE7C1;'
                    'border-radius:4px;padding:2px 7px;font-size:10px;font-weight:700">'
                    '✅ PHYSICAL</span>'
                )
                plat_icon  = "🍎" if platform == "IOS" else "🤖"
                sdk_text   = f" · SDK {sdk}" if sdk else ""
                batt_pct   = battery_lvl if battery_lvl is not None else 0
                batt_color = ("#ff4757" if batt_pct < 20
                              else "#ff9500" if batt_pct < 50
                              else "#00ff9d")
                batt_icon  = ("⚡" if battery_st == "charging"
                              else "🔋" if batt_pct > 20 else "🪫")
                batt_text  = (f"{batt_icon} {batt_pct}%"
                              if battery_lvl is not None else "🔋 —")
                if battery_st == "charging":
                    batt_text += " ⚡"
                net_icon   = ("📶" if network == "wifi"
                              else "📡" if network == "mobile" else "❌")
                abi_text   = ", ".join(abis[:2]) if abis else "—"

                # Build grid rows — only non-empty fields
                def _row(icon, label, val):
                    if not val or val == "—":
                        return ""
                    return (
                        f"<div><span style='color:#5a7a9a'>{icon} {label}</span>"
                        f"<br><span style='color:#e2e8f0'>{val}</span></div>"
                    )

                grid_html = "".join([
                    _row("📦", "App",        f"v{app_ver}" + (f"  #{build_num}" if build_num else "")),
                    _row(net_icon, "Network", network.upper() if network != "—" else "—"),
                    _row("🖥", "Screen",     screen_res + (f"  {screen_den}" if screen_den else "")),
                    _row("🌐", "Locale",     locale),
                    _row("⏰", "Timezone",   timezone),
                    _row("🔒", "Sec. Patch", sec_patch) if platform == "ANDROID" else "",
                    _row("🏷", "Codename",   codename)  if platform == "ANDROID" else "",
                    _row("🧠", "CPU ABI",    abi_text)  if platform == "ANDROID" and abis else "",
                    _row("⚙️", "Hardware",   hardware)  if hardware else "",
                    _row("📦", "Product",    product)   if product else "",
                    _row("🔄", "Bootloader", bootloader) if bootloader else "",
                ])

                html = (
                    f"<div style='background:#0a1020;"
                    f"border:1px solid {border_color}40;"
                    f"border-left:3px solid {border_color};"
                    f"border-radius:12px;padding:16px;margin-bottom:12px'>"

                    # Header
                    f"<div style='display:flex;justify-content:space-between;"
                    f"align-items:flex-start;margin-bottom:10px'>"
                    f"<span style='font-size:11px;font-family:monospace;color:#A78BFA'>"
                    f"{user_id[:22]}{'…' if len(user_id)>22 else ''}</span>"
                    f"{emu_badge}</div>"

                    # Device name
                    f"<div style='font-size:16px;font-weight:800;color:#e2e8f0;"
                    f"margin-bottom:2px'>{plat_icon} {brand} {model}</div>"
                    f"<div style='font-size:11px;color:#7a8ab8;margin-bottom:10px'>"
                    f"{platform} {os_ver}{sdk_text}"
                    f"{'  ·  '+codename if codename else ''}</div>"

                    # Divider
                    f"<div style='border-top:1px solid rgba(255,255,255,0.05);"
                    f"margin-bottom:10px'></div>"

                    # Info grid
                    f"<div style='display:grid;grid-template-columns:1fr 1fr;"
                    f"gap:6px;font-size:11px'>{grid_html}</div>"

                    # Battery bar
                    f"<div style='margin-top:12px'>"
                    f"<div style='display:flex;justify-content:space-between;"
                    f"margin-bottom:4px;font-size:11px'>"
                    f"<span style='color:#5a7a9a'>Battery</span>"
                    f"<span style='color:{batt_color};font-weight:700'>{batt_text}</span>"
                    f"</div>"
                    f"<div style='background:rgba(255,255,255,0.07);"
                    f"border-radius:4px;height:4px'>"
                    f"<div style='background:{batt_color};width:{batt_pct}%;"
                    f"height:100%;border-radius:4px'></div>"
                    f"</div></div>"

                    # Footer
                    f"<div style='margin-top:10px;padding-top:8px;"
                    f"border-top:1px solid rgba(255,255,255,0.04);"
                    f"font-size:10px;color:#3a5a7a;"
                    f"display:flex;justify-content:space-between'>"
                    f"<span>🕒 {last_seen} PHT</span>"
                    f"<span>{pkg_name}</span>"
                    f"</div>"
                    f"</div>"
                )
                st.markdown(html, unsafe_allow_html=True)

                # ── 🔑 Owner Bypass button ────────────────────────────────
                if not is_emulator:
                    btn_label = f"🔑 Set as Owner Bypass"
                    if st.button(btn_label, key=f"bypass_{user_id}_{i}_{j}",
                                 use_container_width=True):
                        try:
                            s = get("/api/settings/")
                            existing = s.get("owner_bypass_ids") or []
                            if user_id not in existing:
                                existing.append(user_id)
                                s["owner_bypass_ids"] = existing
                                post("/api/settings/", s)
                                notify(f"✅ {user_id[:20]} added to Owner Bypass!", kind="success")
                            else:
                                notify(f"ℹ️ Already in Owner Bypass list.", kind="info")
                            st.rerun()
                        except Exception as e:
                            notify(f"Failed: {e}", kind="error")
                            st.rerun()


# ─────────────────────────────────────────────────────────────────────────────
# TAB 2 — FULL TABLE
# ─────────────────────────────────────────────────────────────────────────────
with tab_table:
    rows = []
    for d in devices:
        is_emu   = (d.get("is_emulator") is True
                    or d.get("is_physical_device") is False)
        batt_lvl = d.get("battery_level")
        abis     = d.get("supported_abis", []) or []
        rows.append({
            "User ID":        d.get("user_id",       "—"),
            "Platform":       (d.get("platform")     or "—").upper(),
            "Brand":          d.get("brand") or d.get("manufacturer") or "—",
            "Model":          d.get("model",         "—"),
            "OS Version":     d.get("android_version") or d.get("system_version") or "—",
            "SDK":            d.get("sdk_int",        "—"),
            "Sec. Patch":     d.get("security_patch", "—") or "—",
            "Codename":       d.get("codename",       "—") or "—",
            "Base OS":        d.get("base_os",        "—") or "—",
            "App Version":    d.get("app_version",    "—"),
            "Build #":        d.get("app_build_number","—") or "—",
            "Package":        d.get("package_name",   "—") or "—",
            "Screen":         d.get("screen_resolution","—") or "—",
            "Density":        d.get("screen_density", "—") or "—",
            "Network":        (d.get("network_type")  or "—").upper(),
            "Battery":        f"{batt_lvl}%" if batt_lvl is not None else "—",
            "Batt State":     (d.get("battery_state") or "—").capitalize(),
            "Locale":         d.get("locale",         "—") or "—",
            "Timezone":       d.get("timezone",       "—") or "—",
            "CPU ABI":        ", ".join(abis[:2]) if abis else "—",
            "Hardware":       d.get("hardware",       "—") or "—",
            "Board":          d.get("board",          "—") or "—",
            "Bootloader":     d.get("bootloader",     "—") or "—",
            "Product":        d.get("product",        "—") or "—",
            "Physical?":      "❌ EMULATOR" if is_emu else "✅ Physical",
            "Last Seen PHT":  (d.get("last_seen") or "")[:16].replace("T", " "),
        })

    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)

    default_vis = [
        "User ID", "Brand", "Model", "OS Version", "SDK",
        "App Version", "Screen", "Network", "Battery", "Batt State",
        "Locale", "Timezone", "Physical?", "Last Seen PHT",
    ]
    show_cols = st.multiselect(
        "Visible columns", list(df.columns), default=default_vis
    )
    if show_cols:
        df = df[show_cols]

    st.dataframe(df, use_container_width=True, height=520)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        label="⬇️ Download Full CSV",
        data=csv,
        file_name="xissin_device_info.csv",
        mime="text/csv",
    )


# ─────────────────────────────────────────────────────────────────────────────
# TAB 3 — ANALYTICS
# ─────────────────────────────────────────────────────────────────────────────
with tab_analytics:
    st.markdown("### 📈 Device Analytics")

    def _bar_chart(counts, title, colors=PALETTE):
        st.markdown(f"#### {title}")
        if not counts:
            st.caption("No data.")
            return
        max_v = counts[0][1]
        for idx, (label, cnt) in enumerate(counts):
            pct = int(cnt / max(max_v, 1) * 100)
            c   = colors[idx % len(colors)]
            st.markdown(
                f"<div style='margin-bottom:8px'>"
                f"<div style='display:flex;justify-content:space-between;"
                f"font-size:12px;margin-bottom:3px'>"
                f"<span style='color:#c8d8f0'>{label}</span>"
                f"<span style='color:{c};font-weight:700'>{cnt}</span></div>"
                f"<div style='background:rgba(255,255,255,.06);border-radius:4px;height:5px'>"
                f"<div style='background:{c};width:{pct}%;height:100%;"
                f"border-radius:4px'></div></div></div>",
                unsafe_allow_html=True,
            )

    a1, a2 = st.columns(2)
    with a1:
        brands = [d.get("brand") or d.get("manufacturer") or "Unknown" for d in devices]
        _bar_chart(Counter(brands).most_common(10), "📱 Top Brands")
    with a2:
        vers = [d.get("android_version") or d.get("system_version") or "Unknown"
                for d in devices]
        _bar_chart(Counter(vers).most_common(10), "🤖 OS Version Distribution")

    st.divider()
    b1, b2, b3 = st.columns(3)

    with b1:
        net_colors = {"WIFI":    "#00ff9d", "MOBILE": "#00e5ff",
                      "NONE":    "#ff4757", "UNKNOWN": "#5a7a9a"}
        net_counts = Counter(
            (d.get("network_type") or "unknown").upper() for d in devices
        ).most_common()
        st.markdown("#### 📶 Network Type")
        for nt, cnt in net_counts:
            pct = int(cnt / len(devices) * 100)
            c   = net_colors.get(nt, "#a855f7")
            st.markdown(
                f"<div style='margin-bottom:8px'>"
                f"<div style='display:flex;justify-content:space-between;"
                f"font-size:12px;margin-bottom:3px'>"
                f"<span style='color:#c8d8f0'>{nt}</span>"
                f"<span style='color:{c}'>{cnt} ({pct}%)</span></div>"
                f"<div style='background:rgba(255,255,255,.06);border-radius:4px;height:5px'>"
                f"<div style='background:{c};width:{pct}%;height:100%;"
                f"border-radius:4px'></div></div></div>",
                unsafe_allow_html=True,
            )

    with b2:
        batt_st_colors = {"charging": "#ffd700", "full": "#00ff9d",
                          "discharging": "#00e5ff", "unknown": "#5a7a9a"}
        batt_states = Counter(
            (d.get("battery_state") or "unknown").lower() for d in devices
        ).most_common()
        st.markdown("#### 🔋 Battery State")
        for bs, cnt in batt_states:
            c   = batt_st_colors.get(bs, "#a855f7")
            pct = int(cnt / len(devices) * 100)
            st.markdown(
                f"<div style='margin-bottom:8px'>"
                f"<div style='display:flex;justify-content:space-between;"
                f"font-size:12px;margin-bottom:3px'>"
                f"<span style='color:#c8d8f0'>{bs.capitalize()}</span>"
                f"<span style='color:{c}'>{cnt} ({pct}%)</span></div>"
                f"<div style='background:rgba(255,255,255,.06);border-radius:4px;height:5px'>"
                f"<div style='background:{c};width:{pct}%;height:100%;"
                f"border-radius:4px'></div></div></div>",
                unsafe_allow_html=True,
            )

    with b3:
        tz_counts = Counter(
            d.get("timezone") or "Unknown" for d in devices
        ).most_common(6)
        _bar_chart(tz_counts, "⏰ Top Timezones",
                   colors=["#a855f7"] * 10)

    st.divider()

    # Battery level display per device
    st.markdown("#### 🔋 Battery Level Per Device")
    batt_vals = [(d.get("user_id", "?")[:12], d.get("battery_level"))
                 for d in devices if d.get("battery_level") is not None]
    if batt_vals:
        batt_vals.sort(key=lambda x: x[1])
        COLS_PER = 5
        for chunk_start in range(0, len(batt_vals), COLS_PER):
            chunk      = batt_vals[chunk_start:chunk_start + COLS_PER]
            batt_cols  = st.columns(len(chunk))
            for ci, (uid, lvl) in enumerate(chunk):
                c = ("#ff4757" if lvl < 20 else "#ff9500" if lvl < 50 else "#00ff9d")
                with batt_cols[ci]:
                    st.markdown(
                        f"<div style='text-align:center;background:#0a1020;"
                        f"border:1px solid {c}44;border-radius:8px;padding:8px 6px'>"
                        f"<div style='font-size:18px;font-weight:800;color:{c}'>{lvl}%</div>"
                        f"<div style='font-size:9px;color:#5a7a9a;margin-top:2px'>{uid}</div>"
                        f"</div>",
                        unsafe_allow_html=True,
                    )
    else:
        st.info("No battery data yet (requires app update).")

    st.divider()

    # Screen resolution distribution
    st.markdown("#### 🖥 Screen Resolutions")
    res_counts = Counter(
        d.get("screen_resolution") or "Unknown" for d in devices
    ).most_common(8)
    if res_counts:
        res_cols = st.columns(min(len(res_counts), 4))
        for ri, (res, cnt) in enumerate(res_counts):
            with res_cols[ri % 4]:
                st.markdown(
                    f"<div style='background:#0a1020;border:1px solid #38BDF844;"
                    f"border-radius:8px;padding:10px;text-align:center;margin-bottom:8px'>"
                    f"<div style='font-size:13px;font-weight:700;color:#38BDF8'>{res}</div>"
                    f"<div style='font-size:11px;color:#5a7a9a'>{cnt} device(s)</div>"
                    f"</div>",
                    unsafe_allow_html=True,
                )
    else:
        st.info("No screen data yet (requires app update).")

    st.divider()

    # Locale distribution
    st.markdown("#### 🌐 Top Locales")
    locale_counts = Counter(
        d.get("locale") or "Unknown" for d in devices
    ).most_common(8)
    _bar_chart(locale_counts, "", colors=["#38BDF8"] * 10)


# ─────────────────────────────────────────────────────────────────────────────
# TAB 4 — SECURITY
# ─────────────────────────────────────────────────────────────────────────────
with tab_security:
    emulators = [d for d in devices
                 if d.get("is_emulator") is True
                 or d.get("is_physical_device") is False]

    if not emulators:
        st.success("✅ No emulators or virtual machines detected.")
    else:
        st.warning(
            f"**{len(emulators)} suspicious device(s)** detected running on "
            "an emulator or virtual machine."
        )
        for d in emulators:
            last_seen  = (d.get("last_seen") or "")[:16].replace("T", " ")
            hardware   = d.get("hardware",         "—") or "—"
            product    = d.get("product",          "—") or "—"
            fp         = d.get("fingerprint",      "—") or "—"
            sdk        = d.get("sdk_int",          "—")
            locale     = d.get("locale",           "—") or "—"
            network    = d.get("network_type",     "—") or "—"
            screen     = d.get("screen_resolution","—") or "—"
            battery    = d.get("battery_level")
            batt_text  = f"{battery}%" if battery is not None else "—"

            st.markdown(
                f"<div style='background:#FF6B6B0d;border:1px solid #FF6B6B44;"
                f"border-radius:10px;padding:16px;margin-bottom:12px'>"
                f"<div style='font-size:13px;font-weight:700;color:#FF6B6B;"
                f"margin-bottom:10px'>🚨 {d.get('user_id','—')}</div>"
                f"<div style='display:grid;grid-template-columns:repeat(3,1fr);"
                f"gap:10px;font-size:11px;color:#e2e8f0'>"
                f"<div><span style='color:#5a7a9a'>Platform</span><br>"
                f"{(d.get('platform') or '—').upper()}</div>"
                f"<div><span style='color:#5a7a9a'>Brand / Model</span><br>"
                f"{d.get('brand','—')} {d.get('model','—')}</div>"
                f"<div><span style='color:#5a7a9a'>OS (SDK)</span><br>"
                f"{d.get('android_version') or d.get('system_version') or '—'} "
                f"(SDK {sdk})</div>"
                f"<div><span style='color:#5a7a9a'>Hardware</span><br>{hardware}</div>"
                f"<div><span style='color:#5a7a9a'>Product</span><br>{product}</div>"
                f"<div><span style='color:#5a7a9a'>Network</span><br>{network.upper()}</div>"
                f"<div><span style='color:#5a7a9a'>Screen</span><br>{screen}</div>"
                f"<div><span style='color:#5a7a9a'>Battery</span><br>{batt_text}</div>"
                f"<div><span style='color:#5a7a9a'>Locale</span><br>{locale}</div>"
                f"</div>"
                f"<div style='margin-top:10px;font-size:9px;color:#3a5a7a;"
                f"word-break:break-all'>"
                f"Fingerprint: {fp[:90]}{'…' if len(fp)>90 else ''}</div>"
                f"<div style='font-size:10px;color:#5a7a9a;margin-top:4px'>"
                f"🕒 Last seen: {last_seen} PHT</div>"
                f"</div>",
                unsafe_allow_html=True,
            )

    # Security patch age
    st.divider()
    st.markdown("### 🔒 Security Patch Overview (Android)")
    patch_counts = Counter(
        d.get("security_patch") or "Unknown"
        for d in devices if d.get("platform") == "android"
    ).most_common(10)

    if patch_counts:
        max_p = patch_counts[0][1]
        for patch, cnt in patch_counts:
            is_recent = any(yr in patch for yr in ("2024", "2025", "2026"))
            pc  = "#00ff9d" if is_recent else "#ff4757" if patch != "Unknown" else "#5a7a9a"
            pct = int(cnt / max(max_p, 1) * 100)
            label_suffix = " ✅ Recent" if is_recent else " ⚠️ Outdated" if patch != "Unknown" else ""
            st.markdown(
                f"<div style='margin-bottom:8px'>"
                f"<div style='display:flex;justify-content:space-between;"
                f"font-size:12px;margin-bottom:3px'>"
                f"<span style='color:#c8d8f0'>{patch}{label_suffix}</span>"
                f"<span style='color:{pc};font-weight:700'>{cnt} device(s)</span></div>"
                f"<div style='background:rgba(255,255,255,.06);border-radius:4px;height:5px'>"
                f"<div style='background:{pc};width:{pct}%;height:100%;"
                f"border-radius:4px'></div></div></div>",
                unsafe_allow_html=True,
            )
    else:
        st.info("No security patch data yet (Android only, requires app update).")