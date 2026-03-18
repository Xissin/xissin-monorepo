"""
pages/8_SMS_Bomb_Logs.py — Dedicated SMS Bomb attack logs with per-service breakdown
"""

import streamlit as st
import pandas as pd
from utils.api import get, delete
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(
    page_title="SMS Bomb Logs · Xissin Admin",
    page_icon="💣",
    layout="wide",
)
inject_theme()
auth_guard()

page_header("💣", "SMS Bomb Logs", "ATTACK HISTORY · PER-SERVICE BREAKDOWN")

# ── Load ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=15, show_spinner=False)
def load_sms_logs(limit):
    return get("/api/sms/logs", {"limit": limit}).get("logs", [])

# ── Controls ──────────────────────────────────────────────────────────────────
col_a, col_b, col_c, col_d = st.columns([2, 2, 1, 1])
with col_a:
    search_user = st.text_input("🔍 Filter by User ID", placeholder="User ID...")
with col_b:
    search_phone = st.text_input("📱 Filter by Phone", placeholder="+639...")
with col_c:
    limit = st.selectbox("Show last", [50, 100, 200, 500], index=1)
with col_d:
    st.markdown("<br>", unsafe_allow_html=True)
    col_r, col_clr = st.columns(2)
    with col_r:
        if st.button("🔄", use_container_width=True, help="Refresh"):
            st.cache_data.clear()
            st.rerun()
    with col_clr:
        # Arm the confirmation — actual confirmation UI renders BELOW the controls
        # (outside the narrow column) so the warning is fully visible.
        if st.button("🗑️", use_container_width=True, help="Clear all logs"):
            st.session_state["confirm_clear_sms"] = True

# Confirmation banner — rendered at full width, OUTSIDE the column grid
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

with st.spinner("Loading SMS bomb logs..."):
    logs = load_sms_logs(limit)

# ── Filter ─────────────────────────────────────────────────────────────────────
if search_user.strip():
    logs = [l for l in logs if search_user.strip().lower() in str(l.get("user_id", "")).lower()]
if search_phone.strip():
    q = search_phone.strip().replace("+63", "").replace("0", "", 1)
    logs = [l for l in logs if q in str(l.get("phone", ""))]

# ── Summary stats ─────────────────────────────────────────────────────────────
if logs:
    total_attacks   = len(logs)
    total_sent      = sum(l.get("total_sent", 0) for l in logs)
    total_failed    = sum(l.get("total_failed", 0) for l in logs)
    unique_targets  = len({l.get("phone", "") for l in logs})
    unique_users    = len({l.get("user_id", "") for l in logs})
    avg_success     = round(sum(l.get("success_rate", 0) for l in logs) / max(total_attacks, 1), 1)

    m1, m2, m3, m4, m5, m6 = st.columns(6)
    m1.metric("💥 Total Attacks",    total_attacks)
    m2.metric("✅ Total SMS Sent",   total_sent)
    m3.metric("❌ Total Failed",     total_failed)
    m4.metric("📱 Unique Targets",   unique_targets)
    m5.metric("👤 Unique Users",     unique_users)
    m6.metric("📊 Avg Success Rate", f"{avg_success}%")
    st.divider()

st.caption(f"Showing **{len(logs)}** attack records")

if not logs:
    st.info("No SMS bomb logs found.")
    st.stop()

# ── Tabs ──────────────────────────────────────────────────────────────────────
tab1, tab2 = st.tabs(["🕐 Timeline", "📊 Table"])

with tab1:
    for log in logs:
        ts            = (log.get("ts") or "")[:16].replace("T", " ")
        user_id       = log.get("user_id", "—")
        phone         = log.get("phone", "—")
        rounds        = log.get("rounds", 1)
        total_sent    = log.get("total_sent", 0)
        total_failed  = log.get("total_failed", 0)
        total         = log.get("total", total_sent + total_failed)
        success_rate  = log.get("success_rate", 0)
        results       = log.get("results", [])

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
        <div style='padding:14px 0; border-bottom:1px solid #1d2c4a'>
            <div style='display:flex; gap:12px; align-items:flex-start'>
                <div style='width:10px; height:10px; border-radius:50%;
                    background:{dot_color}; margin-top:5px; flex-shrink:0'></div>
                <div style='flex:1'>
                    <div style='display:flex; justify-content:space-between; flex-wrap:wrap; gap:6px'>
                        <span style='font-family:monospace; font-weight:700;
                            font-size:13px; color:#FF6EC7'>💣 SMS Bomb</span>
                        <span style='font-size:10px; color:#7a8ab8'>{ts} PHT</span>
                    </div>
                    <div style='margin-top:6px; display:flex; flex-wrap:wrap; gap:8px'>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:#A78BFA'>👤 {user_id}</span>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:#38BDF8'>📱 {phone}</span>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:#FFA726'>🔁 {rounds} round{"s" if rounds > 1 else ""}</span>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:#7EE7C1'>✅ {total_sent} sent</span>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:#FF6B6B'>❌ {total_failed} failed</span>
                        <span style='background:#1a2340; border-radius:6px; padding:3px 8px;
                            font-size:11px; color:{rate_color}'>📊 {success_rate}%</span>
                    </div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

        if results:
            with st.expander(f"📋 Service breakdown ({len(results)} services × {rounds} round{'s' if rounds>1 else ''})"):
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
                for svc, stats in sorted(svc_map.items()):
                    status = "✅" if stats["sent"] > 0 else "❌"
                    rows.append({
                        "Status":  status,
                        "Service": svc,
                        "Sent":    stats["sent"],
                        "Failed":  stats["failed"],
                        "Message": stats["last_msg"][:60],
                    })
                df = pd.DataFrame(rows)
                st.dataframe(df, use_container_width=True, hide_index=True)

with tab2:
    rows = []
    for log in logs:
        ts            = (log.get("ts") or "")[:16].replace("T", " ")
        results       = log.get("results", [])
        services_ok   = len([r for r in results if r.get("success")])
        services_fail = len([r for r in results if not r.get("success")])
        rows.append({
            "Time (PHT)":   ts,
            "User ID":      log.get("user_id", "—"),
            "Phone":        log.get("phone", "—"),
            "Rounds":       log.get("rounds", 1),
            "SMS Sent":     log.get("total_sent", 0),
            "SMS Failed":   log.get("total_failed", 0),
            "Success Rate": f"{log.get('success_rate', 0)}%",
            "Svc ✅":       services_ok,
            "Svc ❌":       services_fail,
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)

    csv = df.to_csv(index=False).encode("utf-8")
    st.download_button(
        label="⬇️ Download as CSV",
        data=csv,
        file_name="xissin_sms_bomb_logs.csv",
        mime="text/csv",
    )
