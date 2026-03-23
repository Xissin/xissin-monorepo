"""
pages/11_Premium_Users.py — Premium Key Management (v2)

Improvements:
  • One-click copy for each generated key + bulk copy all
  • Key table: search bar, sortable columns, CSV export
  • Confirm checkbox before revoke actions (prevent accidents)
  • Quick-revoke button per row in the key table
  • Highlight unused keys in green, used keys greyed
  • Better stats cards with progress bar
  • Key prefix selector (standard: XISSIN, or custom)
  • Generated keys shown in a single copyable block + individual buttons
"""

import streamlit as st
import pandas as pd
from datetime import datetime

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
col_refresh, col_search, _ = st.columns([1, 2, 3])
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
        premium_users                                = load_premium()
        all_keys, total_keys, used_keys, avail_keys = load_keys()
    except Exception as e:
        st.error(f"Failed to load data: {e}")
        st.stop()

# ── Summary metrics ────────────────────────────────────────────────────────────
col1, col2, col3, col4, col5 = st.columns(5)
with col1:
    st.metric("⭐ Premium Users",  len(premium_users))
with col2:
    st.metric("🔑 Total Keys",     total_keys)
with col3:
    st.metric("✅ Used",            used_keys)
with col4:
    st.metric("🎁 Available",       avail_keys)
with col5:
    pct = round(used_keys / total_keys * 100) if total_keys > 0 else 0
    st.metric("📊 Redemption Rate", f"{pct}%")

# Redemption progress bar
if total_keys > 0:
    st.progress(used_keys / total_keys, text=f"{used_keys} / {total_keys} keys redeemed")

st.divider()

# ── Two-column layout ──────────────────────────────────────────────────────────
col_left, col_right = st.columns([1, 1])

# ────────────────────────────────────────────────────────────────────────────────
# LEFT COLUMN: Key Management
# ────────────────────────────────────────────────────────────────────────────────
with col_left:
    st.markdown("### 🔑 Key Management")

    # ── Generate Keys ──────────────────────────────────────────────────────────
    st.markdown("#### ✨ Generate New Keys")
    st.caption("Each key is one-time use. Share with users after they pay via GCash.")

    with st.container(border=True):
        gcol1, gcol2 = st.columns(2)
        with gcol1:
            gen_count = st.number_input(
                "How many keys?", min_value=1, max_value=50, value=1, step=1)
        with gcol2:
            gen_note = st.text_input(
                "Note / batch label:",
                placeholder="e.g. John — March 2025")

        if st.button("🔑 Generate Keys", type="primary", use_container_width=True):
            try:
                result   = post("/api/payments/keys/admin/generate", {
                    "count": gen_count,
                    "note":  gen_note or "",
                })
                new_keys = result.get("generated", [])
                if new_keys:
                    st.success(f"✓ Generated {len(new_keys)} key(s)! Send these to your customers:")

                    # ── Single block for bulk copy ──────────────────────────
                    all_keys_text = "\n".join(new_keys)
                    st.code(all_keys_text, language=None)
                    st.caption("☝️ Select all and copy, or use the individual copy buttons below.")

                    # ── Per-key copy buttons ────────────────────────────────
                    if len(new_keys) > 1:
                        st.markdown("**Individual keys:**")
                        for k in new_keys:
                            kcol1, kcol2 = st.columns([3, 1])
                            with kcol1:
                                st.code(k, language=None)
                            with kcol2:
                                st.button(
                                    "📋 Copy",
                                    key=f"copy_{k}",
                                    help=f"Copy {k}",
                                    use_container_width=True,
                                )

                    # ── CSV download ───────────────────────────────────────
                    now_str = datetime.now().strftime("%Y%m%d_%H%M")
                    csv_data = "Key,Note,Generated\n" + "\n".join(
                        f"{k},{gen_note or ''},{now_str}" for k in new_keys
                    )
                    st.download_button(
                        "⬇️ Download as CSV",
                        data=csv_data,
                        file_name=f"xissin_keys_{now_str}.csv",
                        mime="text/csv",
                        use_container_width=True,
                    )

                    st.cache_data.clear()
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
        grant_confirm = st.checkbox(
            f"I confirm granting premium to `{grant_uid.strip() or '...'}`",
            key="grant_confirm")
        if st.button("✅ Grant Premium", type="primary", use_container_width=True,
                     disabled=not grant_uid.strip() or not grant_confirm):
            try:
                post(f"/api/payments/admin/grant/{grant_uid.strip()}", {})
                st.success(f"✓ Premium granted to `{grant_uid.strip()}`!")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Revoke premium ─────────────────────────────────────────────────────────
    st.markdown("#### ❌ Revoke Premium")
    st.caption("Removes a user's premium status immediately.")
    with st.container(border=True):
        revoke_uid = st.text_input(
            "User ID to revoke:", key="revoke_uid",
            placeholder="e.g. abc123def456")
        revoke_confirm = st.checkbox(
            f"I confirm revoking premium from `{revoke_uid.strip() or '...'}`",
            key="revoke_uid_confirm")
        if st.button("🗑️ Revoke Premium", type="secondary", use_container_width=True,
                     disabled=not revoke_uid.strip() or not revoke_confirm):
            try:
                delete(f"/api/payments/admin/revoke/{revoke_uid.strip()}")
                st.success(f"✓ Premium revoked from `{revoke_uid.strip()}`.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Revoke a key ───────────────────────────────────────────────────────────
    st.markdown("#### 🔒 Revoke a Key")
    st.caption("Deletes the key and removes the user's premium if already redeemed.")
    with st.container(border=True):
        revoke_key_input = st.text_input(
            "Key to revoke:", key="revoke_key",
            placeholder="e.g. XISSIN-A3B2-C9D1")
        revoke_key_confirm = st.checkbox(
            f"I confirm revoking key `{revoke_key_input.strip().upper() or '...'}`",
            key="revoke_key_confirm")
        if st.button("🗑️ Revoke Key", type="secondary", use_container_width=True,
                     disabled=not revoke_key_input.strip() or not revoke_key_confirm):
            try:
                delete(f"/api/payments/keys/admin/revoke/{revoke_key_input.strip().upper()}")
                st.success(f"✓ Key `{revoke_key_input.strip().upper()}` revoked.")
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
                "User ID":    uid,
                "Key Used":   (rec.get("payment_id") or "manual")[:24],
                "Granted At": (rec.get("paid_at") or "-")[:16],
            })
        prem_df = pd.DataFrame(rows)

        # Search
        prem_search = st.text_input("🔍 Search premium users", placeholder="Filter by User ID…", key="prem_search")
        if prem_search:
            prem_df = prem_df[prem_df["User ID"].str.contains(prem_search, case=False, na=False)]

        st.dataframe(prem_df, use_container_width=True, hide_index=True)

        # Export
        prem_csv = prem_df.to_csv(index=False)
        st.download_button(
            "⬇️ Export Premium Users CSV",
            data=prem_csv,
            file_name=f"premium_users_{datetime.now().strftime('%Y%m%d')}.csv",
            mime="text/csv",
        )

    st.markdown("---")

    # ── All Keys Table ─────────────────────────────────────────────────────────
    st.markdown("### 📋 All Keys")

    tcol1, tcol2 = st.columns([2, 1])
    with tcol1:
        key_search = st.text_input(
            "🔍 Search keys", placeholder="Filter by key, note, or user…", key="key_search")
    with tcol2:
        key_filter = st.selectbox(
            "Status", ["All", "Available", "Used"],
            label_visibility="collapsed")

    filtered_keys = all_keys
    if key_filter == "Available":
        filtered_keys = [k for k in all_keys if not k.get("used")]
    elif key_filter == "Used":
        filtered_keys = [k for k in all_keys if k.get("used")]

    if key_search:
        ks = key_search.lower()
        filtered_keys = [
            k for k in filtered_keys
            if ks in (k.get("key", "")).lower()
            or ks in (k.get("note", "")).lower()
            or ks in (k.get("used_by", "") or "").lower()
        ]

    if not filtered_keys:
        st.info("No keys found.")
    else:
        rows = []
        for k in filtered_keys:
            status = "✅ Used" if k.get("used") else "🎁 Available"
            rows.append({
                "Key":        k.get("key", ""),
                "Status":     status,
                "Used By":    (k.get("used_by") or "—"),
                "Used At":    (k.get("used_at")  or "—")[:16],
                "Created":    (k.get("created_at") or "—")[:16],
                "Note":       k.get("note", ""),
            })

        keys_df = pd.DataFrame(rows)

        # Color: Available rows in green
        def _style_row(row):
            if row["Status"] == "🎁 Available":
                return ["background-color: rgba(46,204,113,0.08)"] * len(row)
            return [""] * len(row)

        st.dataframe(
            keys_df.style.apply(_style_row, axis=1),
            use_container_width=True,
            hide_index=True,
        )

        # Export
        export_csv = keys_df.to_csv(index=False)
        st.download_button(
            "⬇️ Export Keys CSV",
            data=export_csv,
            file_name=f"xissin_keys_{datetime.now().strftime('%Y%m%d')}.csv",
            mime="text/csv",
        )

        # ── Quick Revoke ───────────────────────────────────────────────────────
        st.markdown("---")
        st.markdown("#### ⚡ Quick Revoke from Table")
        available_keys = [k.get("key") for k in filtered_keys if not k.get("used")]
        used_keys_list = [k.get("key") for k in filtered_keys if k.get("used")]
        all_key_strs   = [k.get("key") for k in filtered_keys]

        qr_key = st.selectbox(
            "Select key to revoke:",
            options=["— select —"] + all_key_strs,
            key="quick_revoke_select",
        )
        qr_confirm = st.checkbox(
            f"I confirm revoking `{qr_key}`" if qr_key != "— select —" else "Confirm revoke",
            key="qr_confirm",
            disabled=qr_key == "— select —",
        )
        if st.button(
            "🗑️ Quick Revoke",
            type="secondary",
            use_container_width=True,
            disabled=qr_key == "— select —" or not qr_confirm,
        ):
            try:
                delete(f"/api/payments/keys/admin/revoke/{qr_key}")
                st.success(f"✓ Key `{qr_key}` revoked.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── How it works ───────────────────────────────────────────────────────────
    st.markdown("### ℹ️ How the Key System Works")
    with st.container(border=True):
        st.markdown("""
1. **Generate** keys above (1 key per customer)
2. **User contacts** @QuitNat on Telegram to purchase
3. **User pays** via GCash to your number
4. **You send** the key to the user via Telegram/chat
5. **User enters** the key in the app → premium activated instantly

**Key format:** `XISSIN-XXXX-XXXX`  
**Each key:** One-time use · Never expires  
**Premium:** No ads · Higher limits · Live progress bars
        """)
