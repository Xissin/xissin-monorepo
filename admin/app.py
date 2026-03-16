"""
app.py — Xissin Admin Panel · Cyberpunk Command Center
Main entry point. Handles login / session auth.
"""

import streamlit as st
from utils.api import verify_admin_key, health_check
from utils.theme import inject_theme, status_badge

st.set_page_config(
    page_title="Xissin Admin",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

inject_theme()

# ── Session init ───────────────────────────────────────────────────────────────
if "authenticated" not in st.session_state:
    st.session_state.authenticated = False
if "admin_key" not in st.session_state:
    st.session_state.admin_key = ""

# ── Login page ─────────────────────────────────────────────────────────────────
def show_login():
    # Full-page animated background
    st.markdown("""
    <style>
    [data-testid="stAppViewContainer"] {
        background:
            radial-gradient(ellipse 70% 60% at 15% 10%,  rgba(0,229,255,.07)  0%, transparent 55%),
            radial-gradient(ellipse 60% 50% at 85% 90%,  rgba(168,85,247,.08) 0%, transparent 55%),
            radial-gradient(ellipse 50% 40% at 50% 50%,  rgba(0,180,255,.03)  0%, transparent 60%),
            #030b16 !important;
    }
    /* Animated grid lines */
    [data-testid="stAppViewContainer"]::after {
        content: '';
        position: fixed;
        inset: 0;
        background-image:
            linear-gradient(rgba(0,229,255,.04) 1px, transparent 1px),
            linear-gradient(90deg, rgba(0,229,255,.04) 1px, transparent 1px);
        background-size: 60px 60px;
        pointer-events: none;
        animation: gridDrift 20s linear infinite;
    }
    @keyframes gridDrift {
        from { background-position: 0 0; }
        to   { background-position: 60px 60px; }
    }
    @keyframes logoGlow {
        0%,100% { filter: drop-shadow(0 0 8px rgba(0,229,255,.5)); }
        50%     { filter: drop-shadow(0 0 24px rgba(0,229,255,.9)); }
    }
    @keyframes titleReveal {
        from { opacity:0; letter-spacing:20px; }
        to   { opacity:1; letter-spacing:8px; }
    }
    @keyframes loginCardIn {
        from { opacity:0; transform: translateY(30px) scale(.97); }
        to   { opacity:1; transform: translateY(0) scale(1); }
    }
    @keyframes borderRotate {
        0%   { background-position: 0% 50%; }
        100% { background-position: 200% 50%; }
    }
    </style>
    """, unsafe_allow_html=True)

    _, col, _ = st.columns([1, 1.1, 1])
    with col:
        # Logo + title
        st.markdown("""
        <div style='text-align:center; padding:60px 0 32px; animation:fadeUp .6s ease both'>
            <div style='font-size:56px; animation:logoGlow 3s ease-in-out infinite;
                display:inline-block'>⚡</div>
            <h1 style='font-family:"Exo 2",sans-serif; font-weight:900; font-size:38px;
                background:linear-gradient(135deg,#00e5ff,#a855f7,#f472b6);
                -webkit-background-clip:text; -webkit-text-fill-color:transparent;
                letter-spacing:8px; margin:12px 0 4px;
                animation:titleReveal .8s ease .2s both;
                text-transform:uppercase'>XISSIN</h1>
            <p style='font-family:"Share Tech Mono",monospace; font-size:11px;
                color:#5a7a9a; letter-spacing:4px; text-transform:uppercase;
                margin:0; animation:fadeUp .6s ease .4s both'>
                ◈ ADMIN COMMAND CENTER ◈
            </p>
        </div>
        """, unsafe_allow_html=True)

        # Login card
        st.markdown("""
        <div style='background:linear-gradient(135deg,rgba(0,229,255,.05),rgba(168,85,247,.05));
            border:1px solid rgba(0,229,255,.2); border-radius:16px; padding:28px;
            animation:loginCardIn .7s ease .3s both;
            box-shadow:0 0 40px rgba(0,229,255,.08), inset 0 0 40px rgba(0,0,0,.3)'>
            <div style='font-family:"Share Tech Mono",monospace; font-size:11px;
                color:#00e5ff; letter-spacing:2px; margin-bottom:20px; opacity:.7'>
                ── AUTHENTICATION REQUIRED ──
            </div>
        """, unsafe_allow_html=True)

        key_input = st.text_input(
            "Admin Key",
            type="password",
            placeholder="Enter admin key...",
            label_visibility="collapsed",
        )

        col_a, col_b = st.columns([1.5, 1])
        with col_a:
            remember = st.checkbox("Remember session", value=True)

        login_btn = st.button("⚡  AUTHENTICATE", use_container_width=True, type="primary")

        st.markdown("</div>", unsafe_allow_html=True)

        if login_btn:
            if not key_input.strip():
                st.error("⚠️ Admin key required.")
            else:
                with st.spinner("Verifying credentials..."):
                    valid = verify_admin_key(key_input.strip())
                if valid:
                    st.session_state.authenticated = True
                    st.session_state.admin_key     = key_input.strip()
                    st.markdown("""
                    <div style='text-align:center;padding:12px;
                        font-family:"Share Tech Mono",monospace;color:#00ff9d;
                        font-size:12px;letter-spacing:2px;animation:fadeUp .3s ease'>
                        ✓ ACCESS GRANTED · LOADING DASHBOARD...
                    </div>
                    """, unsafe_allow_html=True)
                    st.rerun()
                else:
                    st.error("❌ ACCESS DENIED — Invalid admin key.")

        # Footer
        st.markdown("""
        <div style='text-align:center; margin-top:24px;
            font-family:"Share Tech Mono",monospace; font-size:10px;
            color:#2a3a5a; letter-spacing:2px; animation:fadeUp .6s ease .6s both'>
            XISSIN · RAILWAY + UPSTASH · ENCRYPTED
        </div>
        """, unsafe_allow_html=True)


# ── Main app (post-login) ──────────────────────────────────────────────────────
def show_app():
    with st.sidebar:
        # Brand
        st.markdown("""
        <div style='padding:16px 4px 20px; animation:slideIn .4s ease'>
            <div style='display:flex;align-items:center;gap:10px;margin-bottom:20px'>
                <div style='width:38px;height:38px;border-radius:10px;
                    background:linear-gradient(135deg,rgba(0,229,255,.15),rgba(168,85,247,.15));
                    border:1px solid rgba(0,229,255,.3);
                    display:flex;align-items:center;justify-content:center;
                    font-size:18px;box-shadow:0 0 16px rgba(0,229,255,.2);
                    animation:logoGlow 3s ease-in-out infinite'>⚡</div>
                <div>
                    <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:16px;
                        background:linear-gradient(135deg,#00e5ff,#a855f7);
                        -webkit-background-clip:text;-webkit-text-fill-color:transparent;
                        letter-spacing:3px;text-transform:uppercase'>XISSIN</div>
                    <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                        color:#2a4a6a;letter-spacing:2px'>ADMIN PANEL</div>
                </div>
            </div>
        """, unsafe_allow_html=True)

        # Backend status
        online = health_check()
        st.markdown(f"""
            <div style='background:linear-gradient(135deg,rgba(0,229,255,.04),rgba(168,85,247,.04));
                border:1px solid rgba(0,229,255,.15);border-radius:10px;
                padding:12px 14px;margin-bottom:16px'>
                <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                    color:#2a4a6a;letter-spacing:2px;margin-bottom:8px'>BACKEND STATUS</div>
                <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
                    color:#00b8d4;margin-bottom:6px'>railway.app</div>
                {status_badge(online)}
            </div>
        </div>
        """, unsafe_allow_html=True)

        st.markdown("---")

        if st.button("🚪  LOGOUT", use_container_width=True):
            st.session_state.authenticated = False
            st.session_state.admin_key     = ""
            st.rerun()

    # Welcome home screen
    st.markdown("""
    <style>
    @keyframes logoGlow {
        0%,100% { filter:drop-shadow(0 0 8px rgba(0,229,255,.5)); }
        50%     { filter:drop-shadow(0 0 24px rgba(0,229,255,.9)); }
    }
    </style>
    <div style='text-align:center;padding:80px 20px;animation:fadeUp .6s ease'>
        <div style='font-size:60px;margin-bottom:20px;
            animation:logoGlow 3s ease-in-out infinite;display:inline-block'>⚡</div>
        <h2 style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:28px;
            background:linear-gradient(135deg,#00e5ff,#a855f7);
            -webkit-background-clip:text;-webkit-text-fill-color:transparent;
            letter-spacing:4px;text-transform:uppercase;margin-bottom:8px'>
            COMMAND CENTER
        </h2>
        <p style='font-family:"Share Tech Mono",monospace;font-size:12px;
            color:#5a7a9a;letter-spacing:2px'>
            SELECT A MODULE FROM THE SIDEBAR
        </p>
        <div style='display:inline-flex;gap:6px;margin-top:24px;flex-wrap:wrap;justify-content:center'>
            <span style='background:rgba(0,229,255,.08);border:1px solid rgba(0,229,255,.2);
                border-radius:6px;padding:4px 10px;font-family:"Share Tech Mono",monospace;
                font-size:10px;color:#00e5ff;letter-spacing:1px'>📊 DASHBOARD</span>
            <span style='background:rgba(168,85,247,.08);border:1px solid rgba(168,85,247,.2);
                border-radius:6px;padding:4px 10px;font-family:"Share Tech Mono",monospace;
                font-size:10px;color:#a855f7;letter-spacing:1px'>🔑 KEYS</span>
            <span style='background:rgba(244,114,182,.08);border:1px solid rgba(244,114,182,.2);
                border-radius:6px;padding:4px 10px;font-family:"Share Tech Mono",monospace;
                font-size:10px;color:#f472b6;letter-spacing:1px'>👥 USERS</span>
            <span style='background:rgba(0,255,157,.08);border:1px solid rgba(0,255,157,.2);
                border-radius:6px;padding:4px 10px;font-family:"Share Tech Mono",monospace;
                font-size:10px;color:#00ff9d;letter-spacing:1px'>💣 SMS LOGS</span>
        </div>
    </div>
    """, unsafe_allow_html=True)


# ── Router ─────────────────────────────────────────────────────────────────────
if not st.session_state.authenticated:
    show_login()
else:
    show_app()
