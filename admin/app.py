"""
app.py — Xissin Admin Panel · Cyberpunk Command Center
"""
import streamlit as st
from utils.api import verify_admin_key, health_check
from utils.theme import inject_theme, status_badge

st.set_page_config(page_title="Xissin Admin", page_icon="⚡", layout="wide", initial_sidebar_state="expanded")
inject_theme()

st.markdown("""
<style>
/* ── Hide sidebar dropdown arrow ─────────────────────────── */
details > summary { list-style: none !important; }
details > summary::-webkit-details-marker { display: none !important; }
details > summary::marker { display: none !important; }
[data-testid="stSidebarNavSeparator"] { display: none !important; }
section[data-testid="stSidebar"] details summary svg { display: none !important; }

/* ── Sidebar nav links ────────────────────────────────────── */
[data-testid="stSidebarNavLink"] {
    padding: 8px 12px !important; margin: 2px 0 !important;
    border-radius: 8px !important; font-family: 'Rajdhani', sans-serif !important;
    font-weight: 600 !important; font-size: 14px !important;
    letter-spacing: .5px !important; color: #7a8ab8 !important;
    transition: all .2s !important; border-left: 2px solid transparent !important;
}
[data-testid="stSidebarNavLink"]:hover {
    background: rgba(0,229,255,.06) !important; color: #c8d8f0 !important;
    border-left-color: rgba(0,229,255,.4) !important;
}
[data-testid="stSidebarNavLink"][aria-current="page"] {
    background: rgba(0,229,255,.1) !important; color: #00e5ff !important;
    border-left-color: #00e5ff !important;
}
@keyframes logoGlow {
    0%,100% { filter: drop-shadow(0 0 8px rgba(0,229,255,.5)); }
    50%     { filter: drop-shadow(0 0 24px rgba(0,229,255,.9)); }
}
@keyframes cornerScan { 0%,100%{opacity:.3} 50%{opacity:1} }
@keyframes titleReveal { from{opacity:0;letter-spacing:20px} to{opacity:1;letter-spacing:8px} }
@keyframes loginCardIn { from{opacity:0;transform:translateY(24px) scale(.97)} to{opacity:1;transform:translateY(0) scale(1)} }
</style>
""", unsafe_allow_html=True)

# ── Session init ───────────────────────────────────────────────────────────────
if "authenticated" not in st.session_state: st.session_state.authenticated = False
if "admin_key"     not in st.session_state: st.session_state.admin_key     = ""

# ── Auto-restore from URL param ────────────────────────────────────────────────
params = st.query_params
if not st.session_state.authenticated and params.get("ak"):
    saved = params.get("ak","")
    if saved and verify_admin_key(saved):
        st.session_state.authenticated = True
        st.session_state.admin_key     = saved

# ──────────────────────────────────────────────────────────────────────────────
def show_login():
    _, col, _ = st.columns([1, 1.1, 1])
    with col:
        st.markdown("""
        <div style='text-align:center;padding:50px 0 28px;animation:fadeUp .6s ease both'>
            <div style='position:relative;display:inline-block;padding:12px'>
                <div style='position:absolute;top:-4px;left:-4px;width:22px;height:22px;
                    border-top:2px solid rgba(0,229,255,.5);border-left:2px solid rgba(0,229,255,.5);
                    animation:cornerScan 2s ease-in-out infinite'></div>
                <div style='position:absolute;top:-4px;right:-4px;width:22px;height:22px;
                    border-top:2px solid rgba(168,85,247,.5);border-right:2px solid rgba(168,85,247,.5);
                    animation:cornerScan 2s ease-in-out .5s infinite'></div>
                <div style='position:absolute;bottom:-4px;left:-4px;width:22px;height:22px;
                    border-bottom:2px solid rgba(0,229,255,.5);border-left:2px solid rgba(0,229,255,.5);
                    animation:cornerScan 2s ease-in-out 1s infinite'></div>
                <div style='position:absolute;bottom:-4px;right:-4px;width:22px;height:22px;
                    border-bottom:2px solid rgba(168,85,247,.5);border-right:2px solid rgba(168,85,247,.5);
                    animation:cornerScan 2s ease-in-out 1.5s infinite'></div>
                <div style='font-size:50px;animation:logoGlow 3s ease-in-out infinite;display:inline-block'>⚡</div>
            </div>
            <h1 style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:36px;
                background:linear-gradient(135deg,#00e5ff,#a855f7,#f472b6);
                -webkit-background-clip:text;-webkit-text-fill-color:transparent;
                letter-spacing:8px;margin:16px 0 6px;animation:titleReveal .8s ease .2s both'>XISSIN</h1>
            <p style='font-family:"Share Tech Mono",monospace;font-size:11px;
                color:#3a5a7a;letter-spacing:4px;margin:0;animation:fadeUp .6s ease .4s both'>
                ◈ ADMIN COMMAND CENTER ◈</p>
        </div>
        """, unsafe_allow_html=True)

        st.markdown("""
        <div style='background:linear-gradient(145deg,rgba(0,20,40,.92),rgba(10,22,40,.96));
            border:1px solid rgba(0,229,255,.18);border-radius:16px;padding:28px 28px 24px;
            animation:loginCardIn .7s ease .3s both;
            box-shadow:0 0 60px rgba(0,229,255,.06),0 24px 60px rgba(0,0,0,.5);
            position:relative;overflow:hidden'>
            <div style='position:absolute;top:0;left:0;right:0;height:1px;
                background:linear-gradient(90deg,transparent,rgba(0,229,255,.6),rgba(168,85,247,.4),transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:10px;
                color:rgba(0,229,255,.35);letter-spacing:3px;margin-bottom:20px;
                display:flex;align-items:center;gap:8px'>
                <div style='flex:1;height:1px;background:rgba(0,229,255,.12)'></div>
                AUTHENTICATION REQUIRED
                <div style='flex:1;height:1px;background:rgba(0,229,255,.12)'></div>
            </div>
        """, unsafe_allow_html=True)

        key_input = st.text_input("key", type="password", placeholder="Enter your admin key...", label_visibility="collapsed")
        remember  = st.checkbox("🔒  Keep me logged in (survives page refresh)", value=True)
        login_btn = st.button("⚡  AUTHENTICATE", use_container_width=True, type="primary")

        st.markdown("</div>", unsafe_allow_html=True)

        if login_btn:
            if not key_input.strip():
                st.error("⚠️  Admin key is required.")
            else:
                with st.spinner("Verifying..."):
                    valid = verify_admin_key(key_input.strip())
                if valid:
                    st.session_state.authenticated = True
                    st.session_state.admin_key     = key_input.strip()
                    if remember:
                        st.query_params["ak"] = key_input.strip()
                    st.markdown("""
                    <div style='text-align:center;padding:12px;margin-top:10px;
                        background:rgba(0,255,157,.06);border:1px solid rgba(0,255,157,.2);
                        border-radius:10px;font-family:"Share Tech Mono",monospace;
                        color:#00ff9d;font-size:11px;letter-spacing:2px;animation:fadeUp .3s ease'>
                        ✓ ACCESS GRANTED · LOADING...
                    </div>""", unsafe_allow_html=True)
                    st.rerun()
                else:
                    st.error("❌  ACCESS DENIED — Invalid admin key.")

        st.markdown("""
        <div style='text-align:center;margin-top:16px;font-family:"Share Tech Mono",monospace;
            font-size:9px;color:#1a2a3a;letter-spacing:2px'>
            XISSIN · RAILWAY + UPSTASH · AES-256
        </div>""", unsafe_allow_html=True)


# ──────────────────────────────────────────────────────────────────────────────
def show_app():
    with st.sidebar:
        st.markdown("""
        <div style='padding:12px 4px 14px;animation:slideIn .4s ease'>
            <div style='display:flex;align-items:center;gap:10px;margin-bottom:14px'>
                <div style='width:36px;height:36px;border-radius:10px;
                    background:linear-gradient(135deg,rgba(0,229,255,.15),rgba(168,85,247,.15));
                    border:1px solid rgba(0,229,255,.3);
                    display:flex;align-items:center;justify-content:center;
                    font-size:17px;box-shadow:0 0 14px rgba(0,229,255,.2);
                    animation:logoGlow 3s ease-in-out infinite'>⚡</div>
                <div>
                    <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:15px;
                        background:linear-gradient(135deg,#00e5ff,#a855f7);
                        -webkit-background-clip:text;-webkit-text-fill-color:transparent;
                        letter-spacing:3px;text-transform:uppercase'>XISSIN</div>
                    <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                        color:#2a4a6a;letter-spacing:2px'>ADMIN PANEL</div>
                </div>
            </div>
        </div>
        """, unsafe_allow_html=True)

        online = health_check()
        st.markdown(f"""
        <div style='background:rgba(0,229,255,.03);border:1px solid rgba(0,229,255,.1);
            border-radius:10px;padding:12px 14px;margin-bottom:4px'>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:#2a4a6a;letter-spacing:2px;margin-bottom:8px'>BACKEND STATUS</div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
                color:#00b8d4;margin-bottom:8px'>railway.app</div>
            {status_badge(online)}
        </div>
        """, unsafe_allow_html=True)

        st.markdown("---")

        if st.button("🚪  LOGOUT", use_container_width=True):
            st.session_state.authenticated = False
            st.session_state.admin_key     = ""
            st.query_params.clear()
            st.rerun()

    st.markdown("""
    <div style='text-align:center;padding:80px 20px;animation:fadeUp .6s ease'>
        <div style='font-size:58px;margin-bottom:20px;
            animation:logoGlow 3s ease-in-out infinite;display:inline-block'>⚡</div>
        <h2 style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:26px;
            background:linear-gradient(135deg,#00e5ff,#a855f7);
            -webkit-background-clip:text;-webkit-text-fill-color:transparent;
            letter-spacing:4px;text-transform:uppercase;margin-bottom:8px'>COMMAND CENTER</h2>
        <p style='font-family:"Share Tech Mono",monospace;font-size:11px;
            color:#3a5a7a;letter-spacing:3px;margin-bottom:24px'>SELECT A MODULE FROM THE SIDEBAR</p>
        <div style='display:inline-flex;gap:8px;flex-wrap:wrap;justify-content:center'>
            <span style='background:rgba(0,229,255,.07);border:1px solid rgba(0,229,255,.2);border-radius:6px;padding:5px 12px;font-family:"Share Tech Mono",monospace;font-size:10px;color:#00e5ff;letter-spacing:1px'>📊 DASHBOARD</span>
            <span style='background:rgba(168,85,247,.07);border:1px solid rgba(168,85,247,.2);border-radius:6px;padding:5px 12px;font-family:"Share Tech Mono",monospace;font-size:10px;color:#a855f7;letter-spacing:1px'>🔑 KEYS</span>
            <span style='background:rgba(244,114,182,.07);border:1px solid rgba(244,114,182,.2);border-radius:6px;padding:5px 12px;font-family:"Share Tech Mono",monospace;font-size:10px;color:#f472b6;letter-spacing:1px'>👥 USERS</span>
            <span style='background:rgba(0,255,157,.07);border:1px solid rgba(0,255,157,.2);border-radius:6px;padding:5px 12px;font-family:"Share Tech Mono",monospace;font-size:10px;color:#00ff9d;letter-spacing:1px'>💣 SMS LOGS</span>
            <span style='background:rgba(255,149,0,.07);border:1px solid rgba(255,149,0,.2);border-radius:6px;padding:5px 12px;font-family:"Share Tech Mono",monospace;font-size:10px;color:#ff9500;letter-spacing:1px'>📍 MAP</span>
        </div>
    </div>
    """, unsafe_allow_html=True)


# ── Router ─────────────────────────────────────────────────────────────────────
if not st.session_state.authenticated:
    show_login()
else:
    show_app()
