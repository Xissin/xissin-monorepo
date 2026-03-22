"""
pages/11_Premium_Users.py — Premium Key Management
Replaced PayMongo with a key-based system.
Admin generates keys → shares with users who pay via GCash → users redeem in app.
"""

import streamlit as st
import pandas as pd
from utils.api import get, post, delete

st.set_page_config(
    page_title="Premium Keys · Xissin Admin",
    page_icon="🔑",
    layout="wide",
)
from utils.theme import inject_theme, page_header, auth_guard
inject_theme()
auth_guard()

page_header("🔑", "Premium Keys", "KEY GENERATION · PREMIUM USERS · MANUAL GRANTS")

# ── Refresh ────────────────────────────────────────────────────────────────────
col_refresh, _ = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()


@st.cache_data(ttl=30, show_spinner=False)
def load_premium():
    return get("/api/payments/admin/premium").get("premium_users", {})


@st.cache_data(ttl=30, show_spinner=False)
def load_keys():
    data = get("/api/payments/keys/admin/list")
    return data.get("keys", []), data.get("total", 0), data.get("total_used", 0), data.get("total_available", 0)


with st.spinner("Loading data..."):
    try:
        premium_users                                  = load_premium()
        all_keys, total_keys, used_keys, avail_keys   = load_keys()
    except Exception as e:
        st.error(f"Failed to load data: {e}")
        st.stop()

# ── Summary metrics ────────────────────────────────────────────────────────────
col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("⭐ Premium Users",    len(premium_users))
with col2:
    st.metric("🔑 Total Keys",      total_keys)
with col3:
    st.metric("✅ Keys Used",        used_keys)
with col4:
    st.metric("🎁 Keys Available",   avail_keys)

st.divider()

# ── Two-column layout ──────────────────────────────────────────────────────────
col_left, col_right = st.columns([1, 1])

# ────────────────────────────────────────────────────────────────────────────────
# LEFT COLUMN: Key Management
# ────────────────────────────────────────────────────────────────────────────────
with col_left:
    st.markdown("### 🔑 Key Management")

    # ── Generate keys ──────────────────────────────────────────────────────────
    st.markdown("#### ✨ Generate New Keys")
    st.caption("Each key can only be used once. Share with users after they pay via GCash.")
    with st.container(border=True):
        gen_count = st.number_input(
            "How many keys?", min_value=1, max_value=50, value=1, step=1)
        gen_note  = st.text_input(
            "Optional note (e.g. customer name / batch label):",
            placeholder="e.g. John Doe — March 2026")
        if st.button("🔑 Generate Keys", type="primary", use_container_width=True):
            try:
                result = post("/api/payments/keys/admin/generate", {
                    "count": gen_count,
                    "note":  gen_note or "",
                })
                new_keys = result.get("generated", [])
                if new_keys:
                    st.success(f"✓ Generated {len(new_keys)} key(s)!")
                    st.markdown("**Copy and send these keys to your customers:**")
                    for k in new_keys:
                        st.code(k, language=None)
                    st.cache_data.clear()
                    st.rerun()
                else:
                    st.warning("No keys generated. Try again.")
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Manual grant ───────────────────────────────────────────────────────────
    st.markdown("#### 🎁 Manually Grant Premium")
    st.caption("Use this if a user paid and you want to grant premium without a key.")
    with st.container(border=True):
        grant_uid = st.text_input(
            "User ID to grant premium:", key="grant_uid",
            placeholder="e.g. abc123def456")
        if st.button("✅ Grant Premium", type="primary", use_container_width=True,
                     disabled=not grant_uid.strip()):
            try:
                post(f"/api/payments/admin/grant/{grant_uid.strip()}", {})
                st.success(f"✓ Premium granted to {grant_uid.strip()}!")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Revoke premium ─────────────────────────────────────────────────────────
    st.markdown("#### ❌ Revoke Premium")
    st.caption("Removes a user's premium status.")
    with st.container(border=True):
        revoke_uid = st.text_input(
            "User ID to revoke:", key="revoke_uid",
            placeholder="e.g. abc123def456")
        if st.button("🗑️ Revoke Premium", type="secondary", use_container_width=True,
                     disabled=not revoke_uid.strip()):
            try:
                delete(f"/api/payments/admin/revoke/{revoke_uid.strip()}")
                st.success(f"✓ Premium revoked from {revoke_uid.strip()}.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Revoke a key ───────────────────────────────────────────────────────────
    st.markdown("#### 🔒 Revoke a Key")
    st.caption("If a key was used fraudulently, revoke it (also removes user's premium).")
    with st.container(border=True):
        revoke_key = st.text_input(
            "Key to revoke:", key="revoke_key",
            placeholder="e.g. XISSIN-A3B2-C9D1")
        if st.button("🗑️ Revoke Key", type="secondary", use_container_width=True,
                     disabled=not revoke_key.strip()):
            try:
                delete(f"/api/payments/keys/admin/revoke/{revoke_key.strip().upper()}")
                st.success(f"✓ Key {revoke_key.strip().upper()} revoked.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")


# ────────────────────────────────────────────────────────────────────────────────
# RIGHT COLUMN: Premium users + All keys table
# ────────────────────────────────────────────────────────────────────────────────
with col_right:
    # ── Premium Users ──────────────────────────────────────────────────────────
    st.markdown("### ⭐ Premium Users")
    if not premium_users:
        st.info("No premium users yet.")
    else:
        rows = []
        for uid, rec in premium_users.items():
            rows.append({
                "User ID":    uid[:20] + "…" if len(uid) > 20 else uid,
                "Key Used":   (rec.get("payment_id") or "manual")[:20],
                "Granted At": (rec.get("paid_at") or "-")[:16],
            })
        st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)

    st.markdown("---")

    # ── All Keys Table ─────────────────────────────────────────────────────────
    st.markdown("### 📋 All Keys")
    key_filter = st.selectbox(
        "Filter",
        ["All", "Available", "Used"],
        label_visibility="collapsed",
    )

    filtered_keys = all_keys
    if key_filter == "Available":
        filtered_keys = [k for k in all_keys if not k.get("used")]
    elif key_filter == "Used":
        filtered_keys = [k for k in all_keys if k.get("used")]

    if not filtered_keys:
        st.info("No keys found.")
    else:
        rows = []
        for k in filtered_keys:
            status = "✅ Used" if k.get("used") else "🎁 Available"
            rows.append({
                "Key":        k.get("key", ""),
                "Status":     status,
                "Used By":    (k.get("used_by") or "-")[:20],
                "Used At":    (k.get("used_at")  or "-")[:16],
                "Created":    (k.get("created_at") or "-")[:16],
                "Note":       k.get("note", ""),
            })
        st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)

    st.markdown("---")

    # ── How it works ───────────────────────────────────────────────────────────
    st.markdown("### ℹ️ How the Key System Works")
    with st.container(border=True):
        st.markdown("""
1. **Generate** keys above (1 key per customer)
2. **User contacts** @QuitNat on Telegram to purchase
3. **User pays** via GCash to your number
4. **You send** the key to the user
5. **User enters** the key in the app → premium activated instantly

**Key format:** `XISSIN-XXXX-XXXX`  
**Each key:** One-time use, never expires  
**Premium features:** No ads, higher limits, live progress
        """)
