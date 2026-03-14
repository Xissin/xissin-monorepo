"""
pages/4_Keys.py — Generate, view, filter and revoke activation keys
"""

import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
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

# ── Generate key ───────────────────────────────────────────────────────────────
with st.expander("➕ Generate New Key", expanded=False):
    col_a, col_b, col_c = st.columns([1, 1, 2])
    with col_a:
        is_lifetime = st.checkbox("♾️ Lifetime Key")
    with col_b:
        duration = st.number_input("Duration (days)", min_value=1, max_value=36500, value=30, disabled=is_lifetime)
    with col_c:
        note = st.text_input("Note (optional)", placeholder="e.g. For @username")

    if st.button("⚡ Generate Key", type="primary"):
        try:
            days = 36500 if is_lifetime else int(duration)
            result = post("/api/keys/generate", {"duration_days": days, "note": note.strip()})
            generated_key = result.get("key", "")
            st.success(f"✓ Key generated!")
            st.code(generated_key, language=None)
            st.caption("Click to copy ☝️")
            st.cache_data.clear()
        except Exception as e:
            st.error(f"Error: {e}")

st.divider()

# ── Filter + Table ─────────────────────────────────────────────────────────────
col_a, col_b = st.columns([3, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Search by key, note, or redeemed by...")
with col_b:
    key_filter = st.selectbox("Filter", ["All", "Available", "Redeemed", "Expired"])

# Apply filters
filtered = keys[:]
if search.strip():
    q = search.strip().lower()
    filtered = [k for k in filtered if
                q in (k.get("key") or "").lower() or
                q in (k.get("note") or "").lower() or
                q in (k.get("redeemed_by") or "").lower()]

if key_filter == "Available": filtered = [k for k in filtered if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now]
if key_filter == "Redeemed":  filtered = [k for k in filtered if k.get("redeemed")]
if key_filter == "Expired":   filtered = [k for k in filtered if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now]

st.caption(f"Showing **{len(filtered)}** of {total} keys")

if not filtered:
    st.info("No keys match your filter.")
    st.stop()

# Build dataframe
rows = []
for k in filtered:
    exp_dt  = datetime.fromisoformat(k["expires_at"])
    expired_flag = exp_dt <= now
    is_life = k.get("lifetime") or k.get("duration_days", 0) >= 36500

    if k.get("redeemed"):
        status = "✅ Redeemed"
    elif expired_flag:
        status = "❌ Expired"
    else:
        status = "🟢 Available"

    days_left = ""
    if not k.get("redeemed") and not expired_flag and not is_life:
        d = (exp_dt - now).days
        days_left = f"{d}d left"

    rows.append({
        "Key":          k.get("key", "-"),
        "Status":       status,
        "Duration":     "♾️ Lifetime" if is_life else f"{k.get('duration_days', '-')}d",
        "Days Left":    days_left,
        "Created":      (k.get("created_at") or "-")[:10],
        "Expires":      (k.get("expires_at") or "-")[:10],
        "Redeemed By":  k.get("redeemed_by") or "-",
        "Redeemed At":  (k.get("redeemed_at") or "-")[:10],
        "Note":         k.get("note") or "-",
    })

df = pd.DataFrame(rows)
df.index = range(1, len(df) + 1)
st.dataframe(df, use_container_width=True)

st.divider()

# ── Revoke key ─────────────────────────────────────────────────────────────────
st.markdown("### 🗑️ Revoke Key")
col_r, col_btn = st.columns([3, 1])
with col_r:
    revoke_key = st.text_input("Key to revoke", placeholder="XISSIN-XXXX-XXXX-XXXX-XXXX")
with col_btn:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🗑️ Revoke", type="primary", use_container_width=True):
        if not revoke_key.strip():
            st.error("Enter a key to revoke.")
        else:
            try:
                post("/api/keys/revoke", {"key": revoke_key.strip()})
                st.success(f"✓ Key `{revoke_key}` has been revoked.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")
