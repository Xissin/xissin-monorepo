"""
pages/7_Settings.py — Server control: maintenance, versioning, feature flags, APK hosting
"""

import streamlit as st
from utils.api import get, post

st.set_page_config(page_title="Settings · Xissin Admin", page_icon="⚙️", layout="wide")
from utils.theme import inject_theme, page_header, auth_guard
inject_theme()

auth_guard()

page_header("⚙️", "Server Control", "MAINTENANCE · FEATURES · VERSIONING · APK UPDATE")

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_settings():
    return get("/api/settings/")

col_refresh, _ = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with st.spinner("Loading settings..."):
    try:
        s = load_settings()
    except Exception as e:
        st.error(f"Failed to load settings: {e}")
        st.stop()

# Status banner
if s.get("maintenance"):
    st.error("🔴 **MAINTENANCE MODE IS CURRENTLY ON** — All users see the maintenance screen.")
else:
    st.success("🟢 **APP IS ONLINE** — All features available to users.")

st.divider()

col_left, col_right = st.columns([1, 1])

# ── LEFT COLUMN ────────────────────────────────────────────────────────────────
with col_left:
    st.markdown("### 🔧 App Features")
    with st.container(border=True):
        maintenance = st.toggle(
            "🔴 Maintenance Mode",
            value=s.get("maintenance", False),
            help="When ON, all app users see a maintenance screen.",
        )
        if maintenance:
            st.warning("⚠️ Users will see the maintenance screen when this is saved!")

        st.markdown("---")
        feature_sms = st.toggle("📱 SMS Bomber", value=s.get("feature_sms", True))
        feature_ngl = st.toggle("💬 NGL Bomber", value=s.get("feature_ngl", True))

    st.markdown("### 💬 Maintenance Message")
    with st.container(border=True):
        maint_msg = st.text_area(
            "Message shown to users when maintenance is ON",
            value=s.get("maintenance_message", "Xissin is under maintenance. We'll be back shortly!"),
            height=100,
            label_visibility="collapsed",
        )

# ── RIGHT COLUMN ───────────────────────────────────────────────────────────────
with col_right:
    st.markdown("### 📦 App Versioning")
    with st.container(border=True):
        min_ver = st.text_input(
            "Minimum App Version",
            value=s.get("min_app_version", "1.0.0"),
            help="Users below this version are forced to update.",
        )
        latest_ver = st.text_input(
            "Latest App Version",
            value=s.get("latest_app_version", "1.0.0"),
            help="The current latest version shown in the app.",
        )

    st.markdown("### 🚀 APK Download (Auto-Update)")
    with st.container(border=True):
        st.caption(
            "Paste any Google Drive share link — the backend will auto-convert it "
            "to a direct download URL when saved."
        )

        raw_apk_url = st.text_input(
            "Google Drive APK Link",
            value=s.get("apk_download_url", ""),
            placeholder="https://drive.google.com/file/d/YOUR_FILE_ID/view?usp=sharing",
            help="Paste the link exactly as Google Drive gives it to you.",
        )

        apk_version_notes = st.text_area(
            "Version Notes (shown in update dialog)",
            value=s.get("apk_version_notes", ""),
            height=90,
            placeholder="• Bug fixes\n• New feature added\n• Performance improvements",
            help="What changed in this version. Shown to users before they download.",
        )

        # Preview the converted URL
        if raw_apk_url:
            import re
            def _preview_convert(url):
                if "uc?export=download" in url:
                    return url
                m = re.search(r"/file/d/([a-zA-Z0-9_-]+)", url)
                if not m:
                    m = re.search(r"[?&]id=([a-zA-Z0-9_-]+)", url)
                if m:
                    return f"https://drive.google.com/uc?export=download&id={m.group(1)}"
                return url

            converted = _preview_convert(raw_apk_url)
            if converted != raw_apk_url:
                st.success(f"✅ Will be saved as direct download:\n`{converted}`")
            else:
                st.info(f"🔗 Already a direct download URL.")

    st.markdown("### 💾 Current Saved Values")
    with st.container(border=True):
        saved_apk = s.get("apk_download_url", "-") or "-"
        # Truncate long URLs for display
        display_apk = (saved_apk[:55] + "…") if len(saved_apk) > 58 else saved_apk

        rows = [
            ("maintenance",        "🔴 ON" if s.get("maintenance") else "🟢 OFF"),
            ("min_app_version",    s.get("min_app_version", "-")),
            ("latest_app_version", s.get("latest_app_version", "-")),
            ("feature_sms",        "✅ enabled" if s.get("feature_sms", True) else "❌ disabled"),
            ("feature_ngl",        "✅ enabled" if s.get("feature_ngl", True) else "❌ disabled"),
            ("apk_download_url",   display_apk),
            ("apk_version_notes",  (s.get("apk_version_notes") or "-")[:40]),
        ]
        for key, val in rows:
            st.markdown(f"""
            <div style='display:flex; justify-content:space-between; padding:6px 0;
                border-bottom:1px solid #1d2c4a; font-size:12px'>
                <span style='font-family:monospace; color:#5B8CFF'>{key}</span>
                <span style='color:#eef2ff'>{val}</span>
            </div>
            """, unsafe_allow_html=True)

st.divider()

# ── Save ───────────────────────────────────────────────────────────────────────
col_save, _ = st.columns([1, 3])
with col_save:
    if st.button("💾 Save Settings", type="primary", use_container_width=True):
        try:
            payload = {
                "maintenance":         maintenance,
                "maintenance_message": maint_msg.strip() or "Xissin is under maintenance.",
                "min_app_version":     min_ver.strip() or "1.0.0",
                "latest_app_version":  latest_ver.strip() or "1.0.0",
                "feature_sms":         feature_sms,
                "feature_ngl":         feature_ngl,
                "apk_download_url":    raw_apk_url.strip(),
                "apk_version_notes":   apk_version_notes.strip(),
            }
            post("/api/settings/", payload)
            st.success("✓ Settings saved successfully!")
            st.cache_data.clear()
            st.rerun()
        except Exception as e:
            st.error(f"Error saving settings: {e}")
