"""
pages/6_Announcements.py — Post, view and delete app announcements

FIXES:
  - BUG FIX: Preview icon unpacking was confusing:
      _, icon_preview = COLOR_MAP[ann_type][1], COLOR_MAP[ann_type][2]
    This silently discards the color from COLOR_MAP. Simplified to:
      icon_preview = COLOR_MAP[ann_type][2]
  - IMPROVEMENT: "Clear All" confirmation uses notify() toast after rerun
  - IMPROVEMENT: Active count badge in section header
"""
import streamlit as st
from utils.api import get_public, post, delete
from utils.theme import inject_theme, page_header, auth_guard, notify, render_notify

st.set_page_config(page_title="Announcements · Xissin Admin", page_icon="📢", layout="wide")
inject_theme()
auth_guard()
render_notify()

page_header("📢", "Announcements", "BROADCAST · POST · DELETE")

# ── Color / icon map ───────────────────────────────────────────────────────────
# Tuple: (background, border_color, icon_emoji)
COLOR_MAP = {
    "info":    ("rgba(56,189,248,.07)",  "#38BDF8", "ℹ️"),
    "warning": ("rgba(255,167,38,.07)",  "#FFA726", "⚠️"),
    "success": ("rgba(126,231,193,.07)", "#7EE7C1", "✅"),
    "error":   ("rgba(255,107,107,.07)", "#FF6B6B", "🔴"),
}
PREVIEW_COLOR_MAP = {
    "info":    ("rgba(56,189,248,.1)",  "#38BDF8"),
    "warning": ("rgba(255,167,38,.1)",  "#FFA726"),
    "success": ("rgba(126,231,193,.1)", "#7EE7C1"),
    "error":   ("rgba(255,107,107,.1)", "#FF6B6B"),
}

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=15, show_spinner=False)
def load_announcements():
    return get_public("/api/announcements")

col_ctrl, _ = st.columns([1, 5])
with col_ctrl:
    if st.button("🔄 Refresh"):
        st.cache_data.clear()
        st.rerun()

with st.spinner("Loading announcements..."):
    ann_list = load_announcements()

col_left, col_right = st.columns([1, 1])

# ── Post new ───────────────────────────────────────────────────────────────────
with col_left:
    st.markdown("### ✏️ Post Announcement")
    with st.container(border=True):
        title    = st.text_input("Title", placeholder="e.g. Maintenance Notice")
        message  = st.text_area("Message", placeholder="Write your announcement here...", height=120)
        ann_type = st.selectbox("Type", ["info", "warning", "success", "error"])

        if title or message:
            st.markdown("**Preview:**")
            bg, col      = PREVIEW_COLOR_MAP[ann_type]
            # FIX: was: _, icon_preview = COLOR_MAP[ann_type][1], COLOR_MAP[ann_type][2]
            # That discarded COLOR_MAP[ann_type][1] (the color) into a throwaway variable.
            # Simplified to a direct index lookup:
            icon_preview = COLOR_MAP[ann_type][2]
            st.markdown(f"""
            <div style='background:{bg}; border:1px solid {col}40; border-radius:12px;
                padding:12px 14px; margin-top:8px'>
                <div style='font-size:13px; font-weight:700; color:{col}'>{icon_preview} {title or "Title"}</div>
                <div style='font-size:12px; color:#7a8ab8; margin-top:4px'>
                    {message or "Message preview..."}
                </div>
            </div>
            """, unsafe_allow_html=True)

        if st.button("📢 Post Announcement", type="primary", use_container_width=True):
            if not title.strip():
                st.error("Title is required.")
            elif not message.strip():
                st.error("Message is required.")
            else:
                try:
                    post("/api/announcements", {
                        "title":   title.strip(),
                        "message": message.strip(),
                        "type":    ann_type,
                    })
                    notify("✅ Announcement posted!", kind="success")
                    st.cache_data.clear()
                    st.rerun()
                except Exception as e:
                    st.error(f"Error: {e}")

# ── Active announcements ───────────────────────────────────────────────────────
with col_right:
    active_count = len(ann_list)
    st.markdown(f"### 📋 Active ({active_count})")

    if not ann_list:
        st.info("No active announcements.")
    else:
        for ann in ann_list:
            atype  = ann.get("type", "info")
            bg, col, icon = COLOR_MAP.get(atype, COLOR_MAP["info"])
            ts     = (ann.get("created_at") or "")[:16].replace("T", " ")
            ann_id = ann.get("id", "")

            st.markdown(f"""
            <div style='background:{bg}; border:1px solid {col}40; border-radius:12px;
                padding:12px 16px; margin-bottom:10px'>
                <div style='display:flex; justify-content:space-between; align-items:center'>
                    <div style='font-size:13px; font-weight:700; color:{col}'>
                        {icon} {ann.get('title', '')}
                    </div>
                    <span style='font-size:10px; color:#7a8ab8'>{ts}</span>
                </div>
                <div style='font-size:12px; color:#7a8ab8; margin-top:4px; line-height:1.5'>
                    {ann.get('message', '')}
                </div>
                <div style='font-size:10px; color:#7a8ab8; margin-top:6px'>ID: {ann_id}</div>
            </div>
            """, unsafe_allow_html=True)

            if st.button(f"🗑️ Delete  [{ann.get('title','')}]", key=f"del_{ann_id}"):
                try:
                    delete(f"/api/announcements/{ann_id}")
                    notify(f"🗑️ Deleted: {ann.get('title','')}", kind="info")
                    st.cache_data.clear()
                    st.rerun()
                except Exception as e:
                    st.error(f"Error: {e}")

st.divider()

# ── Clear all — with two-step confirmation ─────────────────────────────────────
st.markdown("### 🗑️ Clear All Announcements")
st.warning("⚠️ This will delete ALL active announcements immediately.")

if "confirm_clear_ann" not in st.session_state:
    st.session_state["confirm_clear_ann"] = False

if not st.session_state["confirm_clear_ann"]:
    if st.button("🗑️ Clear All", type="primary"):
        st.session_state["confirm_clear_ann"] = True
        st.rerun()
else:
    st.error("⚠️ **Are you sure?** This cannot be undone.")
    col_yes, col_no = st.columns([1, 1])
    with col_yes:
        if st.button("✅ Yes, delete all", type="primary", use_container_width=True):
            try:
                delete("/api/announcements")
                notify("🗑️ All announcements cleared.", kind="warning")
                st.cache_data.clear()
                st.session_state["confirm_clear_ann"] = False
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")
                st.session_state["confirm_clear_ann"] = False
    with col_no:
        if st.button("❌ Cancel", use_container_width=True):
            st.session_state["confirm_clear_ann"] = False
            st.rerun()
