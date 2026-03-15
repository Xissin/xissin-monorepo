"""
pages/4_Keys.py — Generate, view, filter and revoke activation keys
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, post

st.set_page_config(page_title="Keys · Xissin Admin", page_icon="🔑", layout="wide")

if not st.session_state.get("authenticated"):
    st.warning("⚠️ Please login first.")
    st.stop()

st.markdown("## 🔑 Key Manager")
st.markdown("Generate and manage activation keys")
st.divider()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_keys():
    return get("/api/keys/list").get("keys", [])

col_refresh, _ = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with st.spinner("Loading keys..."):
    keys = load_keys()

now = datetime.utcnow()

# Stats
total     = len(keys)
redeemed  = sum(1 for k in keys if k.get("redeemed"))
available = sum(1 for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now)
expired   = sum(1 for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now)

c1, c2, c3, c4 = st.columns(4)
c1.metric("🔑 Total Keys",  total)
c2.metric("🟢 Available",   available)
c3.metric("✅ Redeemed",    redeemed)
c4.metric("❌ Expired",     expired)

st.divider()

# ── Generate Single Key ────────────────────────────────────────────────────────
with st.expander("➕ Generate Single Key", expanded=False):
    col_a, col_b, col_c = st.columns([1, 1, 2])
    with col_a:
        is_lifetime = st.checkbox("♾️ Lifetime Key", key="single_lifetime")
    with col_b:
        duration = st.number_input(
            "Duration (days)", min_value=1, max_value=36500,
            value=30, disabled=is_lifetime, key="single_duration"
        )
    with col_c:
        note = st.text_input("Note (optional)", placeholder="e.g. For @username", key="single_note")

    if st.button("⚡ Generate Key", type="primary", key="btn_single"):
        try:
            days   = 36500 if is_lifetime else int(duration)
            result = post("/api/keys/generate", {"duration_days": days, "note": note.strip()})
            st.success("✓ Key generated!")
            st.code(result.get("key", ""), language=None)
            st.caption("Click to copy ☝️")
            st.cache_data.clear()
        except Exception as e:
            st.error(f"Error: {e}")

# ── Generate Multiple Keys ─────────────────────────────────────────────────────
with st.expander("⚡ Generate Multiple Keys (Bulk)", expanded=False):
    st.markdown("Generate several keys at once. All keys will have the same duration.")

    col_a, col_b, col_c, col_d = st.columns([1, 1, 1, 2])
    with col_a:
        bulk_count = st.number_input(
            "How many keys?", min_value=1, max_value=100,
            value=5, key="bulk_count"
        )
    with col_b:
        bulk_lifetime = st.checkbox("♾️ Lifetime", key="bulk_lifetime")
    with col_c:
        bulk_duration = st.number_input(
            "Duration (days)", min_value=1, max_value=36500,
            value=30, disabled=bulk_lifetime, key="bulk_duration"
        )
    with col_d:
        bulk_note = st.text_input(
            "Note (optional)", placeholder="e.g. Giveaway batch",
            key="bulk_note"
        )

    if st.button(f"⚡ Generate {bulk_count} Keys", type="primary", key="btn_bulk"):
        days       = 36500 if bulk_lifetime else int(bulk_duration)
        note_text  = bulk_note.strip()
        generated  = []
        failed     = 0

        progress = st.progress(0, text="Generating keys...")
        for i in range(int(bulk_count)):
            try:
                result = post("/api/keys/generate", {
                    "duration_days": days,
                    "note": note_text,
                })
                generated.append(result.get("key", ""))
            except Exception:
                failed += 1
            progress.progress((i + 1) / int(bulk_count), text=f"Generating {i+1}/{int(bulk_count)}...")

        progress.empty()

        if generated:
            st.success(f"✓ {len(generated)} key(s) generated!" + (f" ({failed} failed)" if failed else ""))

            # Show all keys in a copyable text area
            all_keys_text = "\n".join(generated)
            st.text_area(
                "Generated Keys (copy all)",
                value=all_keys_text,
                height=min(200, len(generated) * 32 + 20),
                key="bulk_output",
            )

            # FIX: Replaced nested expander with plain container (Streamlit forbids expander inside expander)
            st.markdown("**📋 View as list:**")
            with st.container():
                for i, k in enumerate(generated, 1):
                    st.code(k, language=None)

            st.cache_data.clear()
        else:
            st.error("Failed to generate any keys. Check backend logs.")

st.divider()

# ── Filter + Table ─────────────────────────────────────────────────────────────
col_a, col_b = st.columns([3, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Search by key, note, or redeemed by...")
with col_b:
    key_filter = st.selectbox("Filter", ["All", "Available", "Redeemed", "Expired"])

filtered = keys[:]
if search.strip():
    q = search.strip().lower()
    filtered = [k for k in filtered if
                q in (k.get("key")         or "").lower() or
                q in (k.get("note")        or "").lower() or
                q in (k.get("redeemed_by") or "").lower()]

if key_filter == "Available":
    filtered = [k for k in filtered if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now]
if key_filter == "Redeemed":
    filtered = [k for k in filtered if k.get("redeemed")]
if key_filter == "Expired":
    filtered = [k for k in filtered if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now]

st.caption(f"Showing **{len(filtered)}** of {total} keys")

if not filtered:
    st.info("No keys match your filter.")
    st.stop()

rows = []
for k in filtered:
    exp_dt   = datetime.fromisoformat(k["expires_at"])
    is_life  = k.get("lifetime") or k.get("duration_days", 0) >= 36500
    exp_flag = exp_dt <= now

    if k.get("redeemed"):
        status = "✅ Redeemed"
    elif exp_flag:
        status = "❌ Expired"
    else:
        status = "🟢 Available"

    days_left = ""
    if not k.get("redeemed") and not exp_flag and not is_life:
        days_left = f"{(exp_dt - now).days}d left"

    rows.append({
        "Key":         k.get("key", "-"),
        "Status":      status,
        "Duration":    "♾️ Lifetime" if is_life else f"{k.get('duration_days', '-')}d",
        "Days Left":   days_left,
        "Created":     (k.get("created_at") or "-")[:10],
        "Expires":     (k.get("expires_at") or "-")[:10],
        "Redeemed By": k.get("redeemed_by") or "-",
        "Redeemed At": (k.get("redeemed_at") or "-")[:10],
        "Note":        k.get("note") or "-",
    })

df = pd.DataFrame(rows)
df.index = range(1, len(df) + 1)
st.dataframe(df, use_container_width=True)

st.divider()

# ── Revoke key ─────────────────────────────────────────────────────────────────
st.markdown("### 🗑️ Revoke Key")
col_r, col_btn = st.columns([3, 1])
with col_r:
    revoke_key_input = st.text_input("Key to revoke", placeholder="XISSIN-XXXX-XXXX-XXXX-XXXX")
with col_btn:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🗑️ Revoke", type="primary", use_container_width=True):
        if not revoke_key_input.strip():
            st.error("Enter a key to revoke.")
        else:
            try:
                post("/api/keys/revoke", {"key": revoke_key_input.strip()})
                st.success(f"✓ Key `{revoke_key_input}` revoked.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

st.divider()

# ── Delete Unredeemed Keys ─────────────────────────────────────────────────────
st.markdown("### 🧹 Delete Unredeemed Keys")
st.caption("Only keys that have **NOT been redeemed** can be deleted. Redeemed keys are protected.")

# ── Delete Single Unredeemed Key ──────────────────────────────────────────────
with st.expander("🗑️ Delete Single Unredeemed Key", expanded=False):
    unredeemed_keys = [k for k in keys if not k.get("redeemed")]

    if not unredeemed_keys:
        st.info("No unredeemed keys available to delete.")
    else:
        key_options = {
            f"{k.get('key', '-')}  ({'❌ Expired' if datetime.fromisoformat(k['expires_at']) <= now else '🟢 Available'})  {('· ' + k['note']) if k.get('note') else ''}": k.get("key")
            for k in unredeemed_keys
        }
        selected_label = st.selectbox(
            "Select key to delete",
            options=list(key_options.keys()),
            key="delete_single_select"
        )
        selected_key = key_options[selected_label]

        st.warning(f"⚠️ You are about to permanently delete: `{selected_key}`")

        col_confirm, col_btn2 = st.columns([3, 1])
        with col_confirm:
            confirm_text = st.text_input(
                "Type the key to confirm deletion",
                placeholder="XISSIN-XXXX-XXXX-XXXX-XXXX",
                key="delete_single_confirm"
            )
        with col_btn2:
            st.markdown("<br>", unsafe_allow_html=True)
            if st.button("🗑️ Delete Key", type="primary", use_container_width=True, key="btn_delete_single"):
                if confirm_text.strip() != selected_key:
                    st.error("❌ Confirmation does not match. Type the exact key.")
                else:
                    try:
                        post("/api/keys/delete", {"key": selected_key})
                        st.success(f"✓ Key `{selected_key}` deleted successfully.")
                        st.cache_data.clear()
                        st.rerun()
                    except Exception as e:
                        st.error(f"Error: {e}")

# ── Bulk Delete Unredeemed Keys ────────────────────────────────────────────────
with st.expander("💣 Bulk Delete Unredeemed Keys", expanded=False):
    st.markdown("Delete all **expired** or all **available** unredeemed keys at once.")

    expired_keys   = [k for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now]
    available_keys = [k for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now]

    col_exp, col_avail = st.columns(2)

    # ── Delete all expired unredeemed ─────────────────────────────────────────
    with col_exp:
        st.markdown(f"**❌ Expired Unredeemed: `{len(expired_keys)}`**")
        if not expired_keys:
            st.info("No expired unredeemed keys.")
        else:
            if "confirm_bulk_expired" not in st.session_state:
                st.session_state["confirm_bulk_expired"] = False

            if not st.session_state["confirm_bulk_expired"]:
                if st.button(f"🗑️ Delete All {len(expired_keys)} Expired Keys", type="primary", key="btn_bulk_delete_expired_1"):
                    st.session_state["confirm_bulk_expired"] = True
                    st.rerun()
            else:
                st.warning("⚠️ This will permanently delete ALL expired unredeemed keys!")
                col_yes, col_no = st.columns(2)
                with col_yes:
                    if st.button("✅ Yes, Delete All", type="primary", key="btn_bulk_expired_confirm"):
                        deleted = 0
                        failed  = 0
                        progress = st.progress(0, text="Deleting expired keys...")
                        for i, k in enumerate(expired_keys):
                            try:
                                post("/api/keys/delete", {"key": k.get("key")})
                                deleted += 1
                            except Exception:
                                failed += 1
                            progress.progress((i + 1) / len(expired_keys), text=f"Deleting {i+1}/{len(expired_keys)}...")
                        progress.empty()
                        st.session_state["confirm_bulk_expired"] = False
                        st.success(f"✓ Deleted {deleted} expired key(s)." + (f" ({failed} failed)" if failed else ""))
                        st.cache_data.clear()
                        st.rerun()
                with col_no:
                    if st.button("❌ Cancel", key="btn_bulk_expired_cancel"):
                        st.session_state["confirm_bulk_expired"] = False
                        st.rerun()

    # ── Delete all available unredeemed ──────────────────────────────────────
    with col_avail:
        st.markdown(f"**🟢 Available Unredeemed: `{len(available_keys)}`**")
        if not available_keys:
            st.info("No available unredeemed keys.")
        else:
            st.warning("⚠️ This deletes valid unused keys permanently!")
            confirm_avail = st.text_input(
                'Type **DELETE** to confirm',
                placeholder="DELETE",
                key="confirm_avail_input"
            )
            if st.button(f"🗑️ Delete All {len(available_keys)} Available Keys", type="primary", key="btn_bulk_delete_available"):
                if confirm_avail.strip() != "DELETE":
                    st.error("❌ Type DELETE in the box above to confirm.")
                else:
                    deleted = 0
                    failed  = 0
                    progress = st.progress(0, text="Deleting available keys...")
                    for i, k in enumerate(available_keys):
                        try:
                            post("/api/keys/delete", {"key": k.get("key")})
                            deleted += 1
                        except Exception:
                            failed += 1
                        progress.progress((i + 1) / len(available_keys), text=f"Deleting {i+1}/{len(available_keys)}...")
                    progress.empty()
                    st.success(f"✓ Deleted {deleted} available key(s)." + (f" ({failed} failed)" if failed else ""))
                    st.cache_data.clear()
                    st.rerun()
