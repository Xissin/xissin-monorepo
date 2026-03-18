"""
pages/7_Settings.py — Server control: maintenance, versioning, feature flags,
                       APK hosting, and Remove Ads product settings
"""
import re  # ← moved to top-level (was buried inside a conditional block)

import streamlit as st
from utils.api import get, post
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="Settings · Xissin Admin", page_icon="⚙️", layout="wide")
inject_theme()
auth_guard()

page_header("⚙️", "Server Control", "MAINTENANCE · FEATURES · VERSIONING · REMOVE ADS")

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_settings():
    return get("/api/settings/")


def _convert_drive_url(url: str) -> str:
    """Convert a Google Drive share link to a direct download URL."""
    if not url:
        return url
    if "uc?export=download" in url:
        return url
    m = re.search(r"/file/d/([a-zA-Z0-9_-]+)", url)
    if not m:
        m = re.search(r"[?&]id=([a-zA-Z0-9_-]+)", url)
    if m:
        return f"https://drive.google.com/uc?export=download&id={m.group(1)}"
    return url


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
            "Paste any Google Drive share link — the backend will auto-convert "
            "it to a direct download URL when saved."
        )
        raw_apk_url = st.text_input(
            "Google Drive APK Link",
            value=s.get("apk_download_url", ""),
            placeholder="https://drive.google.com/file/d/YOUR_FILE_ID/view?usp=sharing",
        )
        apk_version_notes = st.text_area(
            "Version Notes (shown in update dialog)",
            value=s.get("apk_version_notes", ""),
            height=80,
            placeholder="• Bug fixes\n• New feature added\n• Performance improvements",
        )
        if raw_apk_url:
            converted = _convert_drive_url(raw_apk_url)
            if converted != raw_apk_url:
                st.success(f"✅ Will be saved as:\n`{converted}`")
            else:
                st.info("🔗 Already a direct download URL.")

st.divider()

# ══════════════════════════════════════════════════════════════════════════════
# ROW 2 — Remove Ads Product Settings
# ══════════════════════════════════════════════════════════════════════════════
st.markdown("### 🚫 Remove Ads — Product Settings")
st.caption(
    "Changes here appear **instantly** in the app the next time the user "
    "opens the Remove Ads dialog. No app update needed."
)

ra_col1, ra_col2 = st.columns([1, 1])

with ra_col1:
    with st.container(border=True):
        current_price_php = (s.get("remove_ads_price") or 9900) / 100
        price_php = st.number_input(
            "💰 Price (₱ PHP)",
            min_value=1.0,
            max_value=9999.0,
            value=float(current_price_php),
            step=1.0,
            format="%.2f",
            help="Price in Philippine Peso. Will be converted to centavos for PayMongo.",
        )
        price_centavos = int(price_php * 100)
        st.caption(f"Stored as: **{price_centavos} centavos** → PayMongo amount")

        st.markdown("---")

        remove_ads_label = st.text_input(
            "🏷 Banner Label (shown in home screen)",
            value=s.get("remove_ads_label") or f"Remove Ads — ₱{int(current_price_php)} Lifetime",
            placeholder="Remove Ads — ₱99 Lifetime",
            help="Short label shown on the promo banner on the home screen.",
        )
        remove_ads_subtitle = st.text_input(
            "📝 Banner Subtitle",
            value=s.get("remove_ads_subtitle") or "Pay once via GCash · No ads forever",
            placeholder="Pay once via GCash · No ads forever",
        )
        remove_ads_description = st.text_area(
            "📄 Dialog Description",
            value=s.get("remove_ads_description") or "Enjoy Xissin completely ad-free — forever.",
            height=80,
            placeholder="Enjoy Xissin completely ad-free — forever.",
            help="Shown at the top of the Remove Ads purchase dialog.",
        )

with ra_col2:
    with st.container(border=True):
        st.markdown("#### ✅ Benefits List")
        st.caption(
            "Each line = one benefit bullet shown in the Remove Ads dialog. "
            "Add as many as you want — one per line."
        )

        current_benefits = s.get("remove_ads_benefits") or [
            "No more banner ads",
            "No more interstitial ads",
            "One-time payment — lifetime",
            "Pay via GCash / QRPh QR code",
        ]
        if isinstance(current_benefits, list):
            benefits_text = "\n".join(current_benefits)
        else:
            benefits_text = str(current_benefits)

        benefits_input = st.text_area(
            "Benefits (one per line)",
            value=benefits_text,
            height=260,
            label_visibility="collapsed",
            placeholder=(
                "No more banner ads\n"
                "No more interstitial ads\n"
                "One-time payment — lifetime\n"
                "Pay via GCash / QRPh QR code\n"
                "CODM account checker\n"
                "MLBB account checker\n"
                "Premium support"
            ),
        )

        parsed_benefits = [b.strip() for b in benefits_input.splitlines() if b.strip()]
        if parsed_benefits:
            st.markdown("**Preview:**")
            for b in parsed_benefits:
                st.markdown(f"✅ {b}")

# ── Current saved values summary ───────────────────────────────────────────────
st.divider()
with st.expander("💾 Current Saved Values", expanded=False):
    saved_apk   = s.get("apk_download_url", "-") or "-"
    display_apk = (saved_apk[:55] + "…") if len(saved_apk) > 58 else saved_apk
    cur_price   = (s.get("remove_ads_price") or 9900) / 100

    rows = [
        ("maintenance",            "🔴 ON" if s.get("maintenance") else "🟢 OFF"),
        ("min_app_version",        s.get("min_app_version", "-")),
        ("latest_app_version",     s.get("latest_app_version", "-")),
        ("feature_sms",            "✅ enabled" if s.get("feature_sms", True) else "❌ disabled"),
        ("feature_ngl",            "✅ enabled" if s.get("feature_ngl", True) else "❌ disabled"),
        ("apk_download_url",       display_apk),
        ("remove_ads_price",       f"₱{cur_price:.2f} ({s.get('remove_ads_price', 9900)} centavos)"),
        ("remove_ads_label",       s.get("remove_ads_label", "-") or "-"),
        ("remove_ads_description", s.get("remove_ads_description", "-") or "-"),
        ("remove_ads_benefits",    f"{len(current_benefits)} item(s)"),
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
            parsed = [b.strip() for b in benefits_input.splitlines() if b.strip()]
            payload = {
                "maintenance":            maintenance,
                "maintenance_message":    maint_msg.strip() or "Xissin is under maintenance.",
                "min_app_version":        min_ver.strip()    or "1.0.0",
                "latest_app_version":     latest_ver.strip() or "1.0.0",
                "feature_sms":            feature_sms,
                "feature_ngl":            feature_ngl,
                "apk_download_url":       raw_apk_url.strip(),
                "apk_version_notes":      apk_version_notes.strip(),
                # ── Remove Ads ──────────────────────────────────────────────
                "remove_ads_price":       price_centavos,
                "remove_ads_label":       remove_ads_label.strip(),
                "remove_ads_subtitle":    remove_ads_subtitle.strip(),
                "remove_ads_description": remove_ads_description.strip(),
                "remove_ads_benefits":    parsed,
            }
            post("/api/settings/", payload)
            st.success("✓ All settings saved successfully!")
            st.cache_data.clear()
            st.rerun()
        except Exception as e:
            st.error(f"Error saving settings: {e}")
