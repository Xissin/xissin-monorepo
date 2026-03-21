"""pages/2_NGL_Logs.py — NGL Bomber full usage logs (all records, no cap)"""
import streamlit as st
import pandas as pd
from utils.api import get, get_heavy, _ALL
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="NGL Logs · Xissin Admin", page_icon="💬", layout="wide")
inject_theme()
auth_guard()
page_header("💬", "NGL Logs", "ANONYMOUS MESSAGE HISTORY · SEND ANALYTICS")

# ── Controls ──────────────────────────────────────────────────────────────────
col_a, col_b = st.columns([4, 1])
with col_a:
    search = st.text_input(
        "🔍 Search",
        placeholder="Filter by user ID, username, target, or message...",
        label_visibility="collapsed",
    )
with col_b:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=20, show_spinner=False)
def load_ngl():
    stats, logs = {}, []
    try:
        stats = get("/api/ngl/stats")
    except Exception:
        pass
    try:
        # _ALL = 10_000 — fetches the full history with no cap
        logs = get_heavy("/api/ngl/logs", {"limit": _ALL}).get("logs", [])
    except Exception:
        pass
    return stats, logs

with st.spinner("Loading NGL data..."):
    stats, logs = load_ngl()

# ── Metric cards ───────────────────────────────────────────────────────────────
by_user = stats.get("by_user", [])
targets: dict = {}
for l in logs:
    t = l.get("target", "")
    if t:
        targets[t] = targets.get(t, 0) + (l.get("sent") or 0)
top_target = max(targets, key=targets.get) if targets else "-"

# Source breakdown
client_count = sum(1 for l in logs if l.get("source") == "client")
server_count = len(logs) - client_count

c1, c2, c3, c4, c5, c6 = st.columns(6)
for col, icon, label, value, color, delay in [
    (c1, "💬", "TOTAL SENT",    stats.get("total_ngl_sent", 0), "#f472b6", 0.00),
    (c2, "👥", "UNIQUE USERS",  stats.get("user_count", 0),     "#a855f7", 0.06),
    (c3, "🎯", "TOP TARGET",    f"@{top_target}" if top_target != "-" else "-", "#00e5ff", 0.12),
    (c4, "📋", "TOTAL LOGS",    len(logs),                      "#00ff9d", 0.18),
    (c5, "📱", "FROM PHONE",    client_count,                   "#FFA726", 0.24),
    (c6, "🖥️", "FROM SERVER",   server_count,                   "#38BDF8", 0.30),
]:
    with col:
        st.markdown(f"""
        <div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:16px;
            position:relative;overflow:hidden;animation:cardFadeIn .5s ease {delay}s both'>
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}88;letter-spacing:2px;margin-bottom:8px'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:26px;
                color:{color}'>{value}</div>
        </div>""", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Per-user breakdown ─────────────────────────────────────────────────────────
if by_user:
    with st.expander("📊 Per-User Breakdown", expanded=False):
        df_u = pd.DataFrame(by_user)
        df_u.columns = ["User ID", "Username", "Total Sent"]
        df_u = df_u.sort_values("Total Sent", ascending=False).reset_index(drop=True)
        df_u.index += 1
        st.dataframe(df_u, use_container_width=True)

st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 10px'>
    ◈ SEND LOGS</div>""", unsafe_allow_html=True)

if not logs:
    st.info("No NGL logs found.")
    st.stop()

# ── Build dataframe ────────────────────────────────────────────────────────────
df = pd.DataFrame(logs)
for col in ["ts", "user_id", "target", "message", "source"]:
    if col not in df.columns:
        df[col] = "-"
for col in ["sent", "failed", "quantity"]:
    if col not in df.columns:
        df[col] = 0

df["ts"] = df["ts"].astype(str).str[:16].str.replace("T", " ")
df["success%"] = df.apply(
    lambda r: f"{round((r['sent'] / r['quantity']) * 100)}%"
    if r.get("quantity", 0) > 0 else "-",
    axis=1,
)
df["source"] = df["source"].fillna("server")

# ── Search filter ──────────────────────────────────────────────────────────────
if search.strip():
    q = search.strip().lower()
    mask = (
        df["user_id"].astype(str).str.lower().str.contains(q) |
        df["target"].astype(str).str.lower().str.contains(q) |
        df["message"].astype(str).str.lower().str.contains(q) |
        df["source"].astype(str).str.lower().str.contains(q)
    )
    df = df[mask]

st.caption(f"Showing **{len(df)}** log entries")

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    for _, row in df.iterrows():
        source = row.get("source", "server")
        source_badge = (
            "<span style='background:#A78BFA22;color:#A78BFA;border-radius:4px;"
            "padding:2px 7px;font-size:10px;font-weight:700'>📱 CLIENT</span>"
            if source == "client" else
            "<span style='background:#38BDF822;color:#38BDF8;border-radius:4px;"
            "padding:2px 7px;font-size:10px;font-weight:700'>🖥️ SERVER</span>"
        )
        sent   = row.get("sent", 0)
        failed = row.get("failed", 0)
        qty    = row.get("quantity", sent + failed)
        rate   = f"{round((sent / qty) * 100)}%" if qty > 0 else "—"
        dot    = "#7EE7C1" if sent > 0 else "#FF6B6B"

        msg_preview = str(row.get("message", ""))[:80]
        if len(str(row.get("message", ""))) > 80:
            msg_preview += "…"

        st.markdown(f"""
        <div style='padding:14px 0; border-bottom:1px solid #1d2c4a'>
            <div style='display:flex; gap:12px; align-items:flex-start'>
                <div style='width:10px; height:10px; border-radius:50%;
                    background:{dot}; margin-top:5px; flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex; justify-content:space-between; flex-wrap:wrap; gap:6px'>
                        <span style='font-family:monospace; font-weight:700;
                            font-size:13px; color:#f472b6'>💬 NGL Bomb &nbsp; {source_badge}</span>
                        <span style='font-size:10px; color:#7a8ab8'>{row["ts"]} PHT</span>
                    </div>
                    <div style='margin-top:6px; display:flex; flex-wrap:wrap; gap:8px'>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#A78BFA'>👤 {row.get("user_id","—")}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#00e5ff'>🎯 @{row.get("target","—")}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#7EE7C1'>✅ {sent} sent</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#FF6B6B'>❌ {failed} failed</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#FFA726'>📊 {rate}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#7a8ab8'>x{qty} qty</span>
                    </div>
                    <div style='margin-top:6px;font-size:11px;color:#5a7a9a;
                        font-style:italic'>"{msg_preview}"</div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

with tab2:
    display_df = df[["ts", "user_id", "target", "message", "sent", "failed", "quantity", "success%", "source"]].copy()
    display_df.columns = ["Time (PHT)", "User ID", "Target", "Message", "✅ Sent", "❌ Failed", "Qty", "Rate", "Source"]
    display_df.index   = range(1, len(display_df) + 1)
    st.dataframe(display_df, use_container_width=True)

    csv = display_df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_ngl_logs.csv",
        mime      = "text/csv",
    )

# ── Most targeted profiles ─────────────────────────────────────────────────────
if targets:
    st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 10px'>
        ◈ MOST TARGETED PROFILES</div>""", unsafe_allow_html=True)
    top10  = dict(sorted(targets.items(), key=lambda x: x[1], reverse=True)[:10])
    max_v  = max(top10.values())
    colors = ["#f472b6","#a855f7","#00e5ff","#00ff9d","#ff9500",
              "#ff4757","#00b8d4","#FFA726","#7EE7C1","#38BDF8"]
    for i, (target, count) in enumerate(top10.items()):
        pct = int((count / max_v) * 100)
        c   = colors[i % len(colors)]
        st.markdown(f"""
        <div style='margin-bottom:10px'>
            <div style='display:flex;justify-content:space-between;margin-bottom:4px'>
                <span style='font-family:"Share Tech Mono",monospace;font-size:12px;color:#c8d8f0'>
                    @{target}</span>
                <span style='font-family:"Share Tech Mono",monospace;font-size:12px;color:{c}'>
                    {count} msgs</span>
            </div>
            <div style='background:rgba(255,255,255,.04);border-radius:3px;height:4px'>
                <div style='background:{c};width:{pct}%;height:100%;border-radius:3px;
                    box-shadow:0 0 6px {c}66'></div>
            </div>
        </div>""", unsafe_allow_html=True)
