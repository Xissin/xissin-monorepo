"""
pages/7_Settings.py — Server control: maintenance, versioning, feature flags,
                       APK hosting, and Owner Bypass.

FIXES:
  - REMOVED dead "Remove Ads Product Settings" section — the backend
    hardcodes all values in get_remove_ads_info() and NEVER reads
    remove_ads_price / remove_ads_label / remove_ads_description /
    remove_ads_benefits from Redis. Writing those fields was pure dead code.
  - Replaced with a read-only "Premium Key System" info panel.
"""
import re

import streamlit as st
from utils.api import get, post
from utils.theme import inject_theme, page_header, auth_guard, notify, render_notify

st.set_page_config(page_title="Settings · Xissin Admin", page_icon="⚙️", layout="wide")
inject_theme()
auth_guard()
render_notify()

page_header("⚙️", "Server Control", "MAINTENANCE · FEATURES · VERSIONING · OWNER BYPASS")

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_settings():
    return get("/api/settings/")


def _validate_github_url(url: str) -> bool:
    if not url:
        return False
    return "github.com" in url and "/releases/download/" in url


col_refresh, _ = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        notify("Settings refreshed.", kind="info")
        st.rerun()

with st.spinner("Loading settings..."):
    try:
        s = load_settings()
    except Exception as e:
        st.error(f"Failed to load settings: {e}")
        st.stop()

# ── Status banner ──────────────────────────────────────────────────────────────
if s.get("maintenance"):
    st.error("🔴 **MAINTENANCE MODE IS CURRENTLY ON** — All users see the maintenance screen.")
else:
    st.success("🟢 **APP IS ONLINE** — All features available to users.")

st.divider()

# ══════════════════════════════════════════════════════════════════════════════
# ROW 1 — App Features + Versioning
# ══════════════════════════════════════════════════════════════════════════════
col_left, col_right = st.columns([1, 1])

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
        feature_url_remover = st.toggle("🔗 URL Remover", value=s.get("feature_url_remover", True))
        feature_dup_remover = st.toggle("🗑️ Dup Remover", value=s.get("feature_dup_remover", True))
        feature_ip_tracker  = st.toggle("📍 IP Tracker", value=s.get("feature_ip_tracker", True))
        feature_username_tracker = st.toggle("🕵️ Username Tracker", value=s.get("feature_username_tracker", True))
        feature_codm_checker= st.toggle("🎮 CODM Checker", value=s.get("feature_codm_checker", True))

    st.markdown("### 💬 Maintenance Message")
    with st.container(border=True):
        maint_msg = st.text_area(
            "Message shown to users when maintenance is ON",
            value=s.get("maintenance_message",
                         "Xissin is under maintenance. We'll be back shortly!"),
            height=100,
            label_visibility="collapsed",
        )

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
            "Paste the GitHub Releases direct download URL. "
            "SHA-256 will always match — no Google Drive needed."
        )
        raw_apk_url = st.text_input(
            "GitHub Release APK URL",
            value=s.get("apk_download_url", ""),
            placeholder="https://github.com/Xissin/xissin-monorepo/releases/download/v1.6.0/Xissin-v1.6.0.apk",
        )
        apk_version_notes = st.text_area(
            "Version Notes (shown in update dialog)",
            value=s.get("apk_version_notes", ""),
            height=80,
            placeholder="• Bug fixes\n• New feature added\n• Performance improvements",
        )
        apk_sha256 = st.text_input(
            "APK SHA-256 Checksum",
            value=s.get("apk_sha256", ""),
            placeholder="e.g. a3f1c9e2b847d605...",
            help="SHA-256 hash of the APK file. The app checks this before installing.",
        )

        if apk_sha256:
            if len(apk_sha256.strip()) == 64 and all(c in "0123456789abcdefABCDEF" for c in apk_sha256.strip()):
                st.success("✅ Valid SHA-256 hash (64 hex characters)")
            else:
                st.error("❌ Invalid hash — must be exactly 64 hex characters")

        if raw_apk_url:
            if _validate_github_url(raw_apk_url):
                st.success("✅ Valid GitHub Releases URL.")
            else:
                st.warning(
                    "⚠️ This doesn't look like a GitHub Releases URL.\n\n"
                    "Expected format:\n"
                    "`https://github.com/Xissin/xissin-monorepo/releases/download/vX.X.X/Xissin-vX.X.X.apk`"
                )

st.divider()

# ══════════════════════════════════════════════════════════════════════════════
# ROW 2 — Owner Bypass Devices
# ══════════════════════════════════════════════════════════════════════════════
st.markdown("### 🔑 Owner Bypass Devices")
st.caption(
    "Device IDs listed here will **bypass maintenance mode** and always access the app normally. "
    "Add your own phone's device ID here so you can test the app even during maintenance."
)

with st.container(border=True):
    bypass_col1, bypass_col2 = st.columns([2, 1])

    with bypass_col1:
        current_bypass = s.get("owner_bypass_ids") or []
        if isinstance(current_bypass, list):
            bypass_text = "\n".join(current_bypass)
        else:
            bypass_text = str(current_bypass)

        bypass_input = st.text_area(
            "Bypass Device IDs (one per line)",
            value=bypass_text,
            height=120,
            placeholder="e.g.\nREXG64TVDL3BWXYZ\nabc123def456...",
            help="Each line = one device ID that bypasses maintenance mode.",
        )
        parsed_bypass = [b.strip() for b in bypass_input.splitlines() if b.strip()]

    with bypass_col2:
        st.markdown("**ℹ️ How to get your Device ID:**")
        st.markdown(
            "1. Open the app on your phone\n"
            "2. Go to Admin Panel → **Device Info** page\n"
            "3. Find the **Android ID** field\n"
            "4. Copy it and paste it here"
        )
        if parsed_bypass:
            st.success(f"✅ {len(parsed_bypass)} device(s) will bypass maintenance.")
        else:
            st.info("No bypass devices set.")

st.divider()

# ══════════════════════════════════════════════════════════════════════════════
# ROW 3 — Premium Key System Info
# FIX: Replaced dead PayMongo "Remove Ads Product Settings" with an info panel.
# The backend hardcodes all premium dialog values in payments.py → get_remove_ads_info().
# Nothing reads remove_ads_price / remove_ads_label / remove_ads_benefits from Redis.
# To update what users see in the Get Premium dialog, edit payments.py directly.
# ══════════════════════════════════════════════════════════════════════════════
st.markdown("### ⭐ Premium Key System")
st.caption(
    "The premium dialog content is defined in `backend/routers/payments.py → get_remove_ads_info()`. "
    "Edit that file and redeploy to change what users see."
)

with st.container(border=True):
    st.markdown("""
**Current premium flow:**
1. User taps **Get Premium** in the app
2. Dialog shows benefits + link to contact **@QuitNat on Telegram**
3. User pays via **GCash** → receives a key (format: `XISSIN-XXXX-XXXX`)
4. User enters key in app → premium activated instantly

To manage keys and premium users, go to the **🔑 Premium Keys** page.
    """)

    st.info(
        "💡 To change the benefits list, price display, or Telegram handle "
        "shown in the app, edit `backend/routers/payments.py` → "
        "`_benefits` list and `_TELEGRAM` constant, then redeploy on Railway."
    )

st.divider()

# ── Current saved values summary ───────────────────────────────────────────────
with st.expander("💾 Current Saved Values", expanded=False):
    saved_apk   = s.get("apk_download_url", "-") or "-"
    display_apk = (saved_apk[:55] + "…") if len(saved_apk) > 58 else saved_apk

    rows = [
        ("maintenance",         "🔴 ON" if s.get("maintenance") else "🟢 OFF"),
        ("min_app_version",     s.get("min_app_version", "-")),
        ("latest_app_version",  s.get("latest_app_version", "-")),
        ("feature_sms",         "✅ enabled" if s.get("feature_sms", True) else "❌ disabled"),
        ("feature_ngl",         "✅ enabled" if s.get("feature_ngl", True) else "❌ disabled"),
        ("feature_url_remover", "✅ enabled" if s.get("feature_url_remover", True) else "❌ disabled"),
        ("feature_dup_remover", "✅ enabled" if s.get("feature_dup_remover", True) else "❌ disabled"),
        ("feature_ip_tracker",  "✅ enabled" if s.get("feature_ip_tracker", True) else "❌ disabled"),
        ("feature_username_tracker", "✅ enabled" if s.get("feature_username_tracker", True) else "❌ disabled"),
        ("feature_codm_checker","✅ enabled" if s.get("feature_codm_checker", True) else "❌ disabled"),
        ("apk_download_url",    display_apk),
        ("apk_sha256",          (s.get("apk_sha256", "") or "-")[:20] + ("…" if len(s.get("apk_sha256",""))>20 else "")),
        ("owner_bypass_ids",    f"{len(current_bypass)} device(s)"),
    ]
    for key, val in rows:
        st.markdown(
            f"<div style='display:flex;justify-content:space-between;padding:6px 0;"
            f"border-bottom:1px solid #1d2c4a;font-size:12px'>"
            f"<span style='font-family:monospace;color:#5B8CFF'>{key}</span>"
            f"<span style='color:#eef2ff'>{val}</span></div>",
            unsafe_allow_html=True,
        )

# ── Save ───────────────────────────────────────────────────────────────────────
st.divider()
col_save, _ = st.columns([1, 3])
with col_save:
    if st.button("💾 Save All Settings", type="primary", use_container_width=True):
        try:
            parsed_byp = [b.strip() for b in bypass_input.splitlines() if b.strip()]
            payload = {
                "maintenance":         maintenance,
                "maintenance_message": maint_msg.strip() or "Xissin is under maintenance.",
                "min_app_version":     min_ver.strip()    or "1.0.0",
                "latest_app_version":  latest_ver.strip() or "1.0.0",
                "feature_sms":         feature_sms,
                "feature_ngl":         feature_ngl,
                "feature_url_remover": feature_url_remover,
                "feature_dup_remover": feature_dup_remover,
                "feature_ip_tracker":  feature_ip_tracker,
                "feature_username_tracker": feature_username_tracker,
                "feature_codm_checker": feature_codm_checker,
                "owner_bypass_ids":    parsed_byp,
                "apk_download_url":    raw_apk_url.strip(),
                "apk_version_notes":   apk_version_notes.strip(),
                "apk_sha256":          apk_sha256.strip(),
            }
            post("/api/settings/", payload)
            if maintenance:
                notify("🔴 Maintenance mode ON — users are now blocked.", kind="warning")
            else:
                notify("✅ Settings saved successfully!", kind="success")
            st.cache_data.clear()
            st.rerun()
        except Exception as e:
            notify(f"Failed to save settings: {e}", kind="error")
