"""pages/8_SMS_Bomb_Logs.py — SMS Bomb attack logs — full history, no cap"""
import streamlit as st
import pandas as pd
from utils.api import get_heavy, delete, _ALL
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="SMS Bomb Logs · Xissin Admin", page_icon="💣", layout="wide")
inject_theme()
auth_guard()
page_header("💣", "SMS Bomb Logs", "ATTACK HISTORY · PER-SERVICE BREAKDOWN")

# ── Controls ──────────────────────────────────────────────────────────────────
col_a, col_b, col_c, col_d = st.columns([2, 2, 1, 1])
with col_a:
    search_user = st.text_input("🔍 Filter by User ID", placeholder="User ID...",
                                label_visibility="collapsed")
with col_b:
    search_phone = st.text_input("📱 Filter by Phone", placeholder="+639...",
                                 label_visibility="collapsed")
with col_c:
    source_filter = st.selectbox("Source", ["All", "📱 Client", "🖥️ Server"],
                                 label_visibility="collapsed")
with col_d:
    col_r, col_clr = st.columns(2)
    with col_r:
        if st.button("🔄", use_container_width=True, help="Refresh"):
            st.cache_data.clear()
            st.rerun()
    with col_clr:
        if st.button("🗑️", use_container_width=True, help="Clear all logs"):
            st.session_state["confirm_clear_sms"] = True

# Confirmation banner — full width, outside columns
if st.session_state.get("confirm_clear_sms"):
    st.warning("⚠️ **Clear ALL SMS bomb logs?** This cannot be undone.")
    c_yes, c_no = st.columns([1, 1])
    with c_yes:
        if st.button("✅ Yes, clear all", type="primary", use_container_width=True):
            try:
                delete("/api/sms/logs")
                st.success("✓ All SMS logs cleared.")
                st.cache_data.clear()
                st.session_state["confirm_clear_sms"] = False
                st.rerun()
            except Exception as e:
                st.error(str(e))
                st.session_state["confirm_clear_sms"] = False
    with c_no:
        if st.button("❌ Cancel", use_container_width=True):
            st.session_state["confirm_clear_sms"] = False
            st.rerun()

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=15, show_spinner=False)
def load_sms_logs():
    # _ALL = 10_000 — no cap, fetch full history
    return get_heavy("/api/sms/logs", {"limit": _ALL}).get("logs", [])

with st.spinner("Loading SMS bomb logs..."):
    logs = load_sms_logs()

# ── Filters ────────────────────────────────────────────────────────────────────
if search_user.strip():
    logs = [l for l in logs
            if search_user.strip().lower() in str(l.get("user_id", "")).lower()]
if search_phone.strip():
    raw  = search_phone.strip().lstrip("+").lstrip("63").lstrip("0")
    logs = [l for l in logs
            if raw in str(l.get("phone", "")).lstrip("+63").lstrip("0")]
if source_filter == "📱 Client":
    logs = [l for l in logs if l.get("source") == "client"]
elif source_filter == "🖥️ Server":
    logs = [l for l in logs if l.get("source", "server") == "server"]

# ── Summary stats ──────────────────────────────────────────────────────────────
if logs:
    total_attacks  = len(logs)
    total_sent     = sum(l.get("total_sent",   0) for l in logs)
    total_failed   = sum(l.get("total_failed", 0) for l in logs)
    unique_targets = len({l.get("phone", "") for l in logs})
    unique_users   = len({l.get("user_id", "") for l in logs})
    avg_success    = round(
        sum(l.get("success_rate", 0) for l in logs) / max(total_attacks, 1), 1
    )
    client_cnt     = sum(1 for l in logs if l.get("source") == "client")
    server_cnt     = total_attacks - client_cnt

    m1, m2, m3, m4, m5, m6, m7, m8 = st.columns(8)
    m1.metric("💥 Total Attacks",   total_attacks)
    m2.metric("✅ SMS Sent",        total_sent)
    m3.metric("❌ SMS Failed",      total_failed)
    m4.metric("📱 Unique Targets",  unique_targets)
    m5.metric("👤 Unique Users",    unique_users)
    m6.metric("📊 Avg Success",     f"{avg_success}%")
    m7.metric("📱 From Phone",      client_cnt)
    m8.metric("🖥️ From Server",     server_cnt)
    st.divider()

st.caption(f"Showing **{len(logs)}** attack records")

if not logs:
    st.info("No SMS bomb logs found.")
    st.stop()

# ── Tabs ───────────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    for log in logs:
        ts           = (log.get("ts") or "")[:16].replace("T", " ")
        user_id      = log.get("user_id",       "—")
        phone        = log.get("phone",         "—")
        rounds       = log.get("rounds",         1)
        total_sent   = log.get("total_sent",     0)
        total_failed = log.get("total_failed",   0)
        total        = log.get("total", total_sent + total_failed)
        success_rate = log.get("success_rate",   0)
        results      = log.get("results",       [])
        source       = log.get("source",    "server")

        source_badge = (
            "<span style='background:#A78BFA22;color:#A78BFA;border-radius:4px;"
            "padding:2px 7px;font-size:10px;font-weight:700'>📱 CLIENT</span>"
            if source == "client" else
            "<span style='background:#38BDF822;color:#38BDF8;border-radius:4px;"
            "padding:2px 7px;font-size:10px;font-weight:700'>🖥️ SERVER</span>"
        )

        if success_rate >= 70:
            dot_color  = "#7EE7C1"
            rate_color = "#7EE7C1"
        elif success_rate >= 30:
            dot_color  = "#FFA726"
            rate_color = "#FFA726"
        else:
            dot_color  = "#FF6B6B"
            rate_color = "#FF6B6B"

        st.markdown(f"""
        <div style='padding:14px 0;border-bottom:1px solid #1d2c4a'>
            <div style='display:flex;gap:12px;align-items:flex-start'>
                <div style='width:10px;height:10px;border-radius:50%;
                    background:{dot_color};margin-top:5px;flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex;justify-content:space-between;flex-wrap:wrap;gap:6px'>
                        <span style='font-family:monospace;font-weight:700;
                            font-size:13px;color:#FF6EC7'>💣 SMS Bomb &nbsp; {source_badge}</span>
                        <span style='font-size:10px;color:#7a8ab8'>{ts} PHT</span>
                    </div>
                    <div style='margin-top:6px;display:flex;flex-wrap:wrap;gap:8px'>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#A78BFA'>👤 {user_id}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#38BDF8'>📱 {phone}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#FFA726'>🔁 {rounds} round{"s" if rounds > 1 else ""}</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#7EE7C1'>✅ {total_sent} sent</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:#FF6B6B'>❌ {total_failed} failed</span>
                        <span style='background:#1a2340;border-radius:6px;padding:3px 8px;
                            font-size:11px;color:{rate_color}'>📊 {success_rate}%</span>
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

        if results:
            with st.expander(
                f"📋 Service breakdown ({len(results)} services"
                f" × {rounds} round{'s' if rounds > 1 else ''})"
            ):
                svc_map: dict = {}
                for r in results:
                    svc = r.get("service", "—")
                    ok  = r.get("success", False)
                    if svc not in svc_map:
                        svc_map[svc] = {"sent": 0, "failed": 0, "last_msg": ""}
                    if ok:
                        svc_map[svc]["sent"]    += 1
                    else:
                        svc_map[svc]["failed"]  += 1
                    svc_map[svc]["last_msg"] = r.get("message", "")

                rows = []
                for svc, s in sorted(svc_map.items()):
                    rows.append({
                        "Status":  "✅" if s["sent"] > 0 else "❌",
                        "Service": svc,
                        "Sent":    s["sent"],
                        "Failed":  s["failed"],
                        "Message": s["last_msg"][:60],
                    })
                svc_df = pd.DataFrame(rows)
                st.dataframe(svc_df, use_container_width=True, hide_index=True)

with tab2:
    rows = []
    for log in logs:
        ts           = (log.get("ts") or "")[:16].replace("T", " ")
        results      = log.get("results", [])
        services_ok  = len([r for r in results if r.get("success")])
        services_fail= len([r for r in results if not r.get("success")])
        rows.append({
            "Time (PHT)":   ts,
            "User ID":      log.get("user_id",       "—"),
            "Phone":        log.get("phone",         "—"),
            "Source":       log.get("source",    "server"),
            "Rounds":       log.get("rounds",          1),
            "SMS Sent":     log.get("total_sent",      0),
            "SMS Failed":   log.get("total_failed",    0),
            "Success Rate": f"{log.get('success_rate', 0)}%",
            "Svc ✅":       services_ok,
            "Svc ❌":       services_fail,
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        "⬇️ Download as CSV",
        data      = csv,
        file_name = "xissin_sms_bomb_logs.csv",
        mime      = "text/csv",
    )
