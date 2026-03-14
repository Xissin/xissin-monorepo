"""
pages/2_NGL_Logs.py — NGL Bomber usage logs and per-user stats
"""

import streamlit as st
import pandas as pd
from utils.api import get

st.set_page_config(page_title="NGL Logs · Xissin Admin", page_icon="💬", layout="wide")

if not st.session_state.get("authenticated"):
    st.warning("⚠️ Please login first.")
    st.stop()

st.markdown("## 💬 NGL Logs")
st.markdown("Every anonymous message send via NGL Bomber")
st.divider()

# ── Controls ───────────────────────────────────────────────────────────────────
col_a, col_b, col_c = st.columns([2, 1, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Filter by user ID, username, or target...")
with col_b:
    limit = st.selectbox("Show last", [50, 100, 200, 500], index=1)
with col_c:
    st.markdown("<br>", unsafe_allow_html=True)
    refresh = st.button("🔄 Refresh", use_container_width=True)

if refresh:
    st.cache_data.clear()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_ngl_data(limit):
    stats = {}
    logs  = []
    try: stats = get("/api/ngl/stats")
    except Exception as e: st.error(f"Stats error: {e}")
    try: logs  = get(f"/api/ngl/logs", {"limit": limit}).get("logs", [])
    except Exception as e: st.error(f"Logs error: {e}")
    return stats, logs

with st.spinner("Loading NGL data..."):
    stats, logs = load_ngl_data(limit)

# ── Stat cards ─────────────────────────────────────────────────────────────────
by_user = stats.get("by_user", [])
targets: dict = {}
for l in logs:
    t = l.get("target", "")
    if t:
        targets[t] = targets.get(t, 0) + (l.get("sent") or 0)
top_target = max(targets, key=targets.get) if targets else "-"

c1, c2, c3, c4 = st.columns(4)
c1.metric("💬 Total NGL Sent",  stats.get("total_ngl_sent", 0))
c2.metric("👥 Unique Users",    stats.get("user_count", 0))
c3.metric("🎯 Top Target",      f"@{top_target}" if top_target != "-" else "-")
c4.metric("📋 Logs Shown",      len(logs))

st.divider()

# ── Per-user breakdown ─────────────────────────────────────────────────────────
if by_user:
    with st.expander("📊 Per-User Breakdown", expanded=False):
        df_users = pd.DataFrame(by_user)
        df_users.columns = ["User ID", "Username", "Total Sent"]
        df_users = df_users.sort_values("Total Sent", ascending=False).reset_index(drop=True)
        df_users.index += 1
        st.dataframe(df_users, use_container_width=True)

# ── Logs table ─────────────────────────────────────────────────────────────────
st.markdown("### 📋 Send Logs")

if not logs:
    st.info("No NGL logs found.")
    st.stop()

df = pd.DataFrame(logs)

# Normalise columns
for col in ["ts", "user_id", "target", "sent", "failed", "quantity"]:
    if col not in df.columns:
        df[col] = "-" if col in ["ts", "user_id", "target"] else 0

df["ts"]       = df["ts"].astype(str).str[:16].str.replace("T", " ")
df["success%"] = df.apply(
    lambda r: f"{round((r['sent']/r['quantity'])*100)}%" if r.get("quantity", 0) > 0 else "-",
    axis=1,
)

# Search filter
if search.strip():
    q = search.strip().lower()
    mask = (
        df["user_id"].astype(str).str.lower().str.contains(q) |
        df["target"].astype(str).str.lower().str.contains(q)
    )
    df = df[mask]
    st.caption(f"Showing {len(df)} result(s) for **{search}**")

display_df = df[["ts", "user_id", "target", "sent", "failed", "quantity", "success%"]].copy()
display_df.columns = ["Time (PHT)", "User ID", "Target", "✅ Sent", "❌ Failed", "Qty", "Rate"]
display_df.index = range(1, len(display_df) + 1)

st.dataframe(
    display_df,
    use_container_width=True,
    column_config={
        "Target": st.column_config.TextColumn("Target (@username)"),
        "✅ Sent": st.column_config.NumberColumn(format="%d"),
        "❌ Failed": st.column_config.NumberColumn(format="%d"),
        "Rate": st.column_config.TextColumn("Success Rate"),
    },
)

# ── Target frequency chart ─────────────────────────────────────────────────────
if targets:
    st.markdown("### 🎯 Most Targeted Profiles")
    top_10 = dict(sorted(targets.items(), key=lambda x: x[1], reverse=True)[:10])
    chart_df = pd.DataFrame({"Target": list(top_10.keys()), "Messages Sent": list(top_10.values())})
    st.bar_chart(chart_df.set_index("Target"))
