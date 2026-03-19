"""pages/2_NGL_Logs.py — NGL Bomber usage logs"""
import streamlit as st
import pandas as pd
from utils.api import get
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="NGL Logs · Xissin Admin", page_icon="💬", layout="wide")
inject_theme(); auth_guard()
page_header("💬", "NGL Logs", "ANONYMOUS MESSAGE HISTORY · SEND ANALYTICS")

col_a, col_b, col_c = st.columns([2,1,1])
with col_a: search = st.text_input("🔍 Search", placeholder="Filter by user ID, username, or target...", label_visibility="collapsed")
with col_b: limit  = st.selectbox("Show last", [50,100,200,500], index=1, label_visibility="collapsed")
with col_c:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()  # FIX: was missing — cache cleared but page never reloaded

@st.cache_data(ttl=20, show_spinner=False)
def load_ngl(limit):
    stats, logs = {}, []
    try:
        stats = get("/api/ngl/stats")
    except Exception:
        pass
    try:
        logs = get("/api/ngl/logs", {"limit": limit}).get("logs", [])
    except Exception:
        pass
    return stats, logs

with st.spinner("Loading NGL data..."):
    stats, logs = load_ngl(limit)

by_user = stats.get("by_user", [])
targets = {}
for l in logs:
    t = l.get("target","")
    if t: targets[t] = targets.get(t, 0) + (l.get("sent") or 0)
top_target = max(targets, key=targets.get) if targets else "-"

c1,c2,c3,c4 = st.columns(4)
for col, icon, label, value, color, delay in [
    (c1,"💬","TOTAL SENT",  stats.get("total_ngl_sent",0),"#f472b6",0.0),
    (c2,"👥","UNIQUE USERS",stats.get("user_count",0),    "#a855f7",0.08),
    (c3,"🎯","TOP TARGET",  f"@{top_target}" if top_target!="-" else "-","#00e5ff",0.16),
    (c4,"📋","LOGS SHOWN",  len(logs),                    "#00ff9d",0.24),
]:
    with col:
        st.markdown(f"""<div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:16px;
            position:relative;overflow:hidden;animation:cardFadeIn .5s ease {delay}s both'>
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}88;letter-spacing:2px;margin-bottom:8px'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:28px;
                color:{color}'>{value}</div></div>""", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

if by_user:
    with st.expander("📊 Per-User Breakdown", expanded=False):
        df_u = pd.DataFrame(by_user)
        df_u.columns = ["User ID","Username","Total Sent"]
        df_u = df_u.sort_values("Total Sent", ascending=False).reset_index(drop=True)
        df_u.index += 1
        st.dataframe(df_u, use_container_width=True)

st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 10px'>
    ◈ SEND LOGS</div>""", unsafe_allow_html=True)

if not logs: st.info("No NGL logs found."); st.stop()

df = pd.DataFrame(logs)
for col in ["ts","user_id","target","message","sent","failed","quantity"]:
    if col not in df.columns: df[col] = "-" if col in ["ts","user_id","target","message"] else 0
df["ts"] = df["ts"].astype(str).str[:16].str.replace("T"," ")
df["success%"] = df.apply(lambda r: f"{round((r['sent']/r['quantity'])*100)}%" if r.get("quantity",0)>0 else "-", axis=1)
if search.strip():
    q = search.strip().lower()
    mask = (df["user_id"].astype(str).str.lower().str.contains(q) |
            df["target"].astype(str).str.lower().str.contains(q) |
            df["message"].astype(str).str.lower().str.contains(q))
    df = df[mask]

display_df = df[["ts","user_id","target","message","sent","failed","quantity","success%"]].copy()
display_df.columns = ["Time (PHT)","User ID","Target","Message","✅ Sent","❌ Failed","Qty","Rate"]
display_df.index = range(1, len(display_df)+1)
st.dataframe(display_df, use_container_width=True)

if targets:
    st.markdown("""<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
        color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin:16px 0 10px'>
        ◈ MOST TARGETED PROFILES</div>""", unsafe_allow_html=True)
    top10 = dict(sorted(targets.items(), key=lambda x: x[1], reverse=True)[:10])
    max_v = max(top10.values())
    for i,(target,count) in enumerate(top10.items()):
        pct = int((count/max_v)*100)
        colors = ["#f472b6","#a855f7","#00e5ff","#00ff9d","#ff9500","#ff4757","#00b8d4","#f472b6","#a855f7","#00e5ff"]
        c = colors[i%len(colors)]
        st.markdown(f"""<div style='margin-bottom:10px'>
            <div style='display:flex;justify-content:space-between;margin-bottom:4px'>
                <span style='font-family:"Share Tech Mono",monospace;font-size:12px;color:#c8d8f0'>@{target}</span>
                <span style='font-family:"Share Tech Mono",monospace;font-size:12px;color:{c}'>{count}</span>
            </div>
            <div style='background:rgba(255,255,255,.04);border-radius:3px;height:4px'>
                <div style='background:{c};width:{pct}%;height:100%;border-radius:3px;box-shadow:0 0 6px {c}66'></div>
            </div></div>""", unsafe_allow_html=True)
