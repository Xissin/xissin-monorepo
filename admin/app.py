"""
app.py — Xissin Admin Panel (Streamlit)
Main entry point. Handles login / session auth.
"""

import streamlit as st
from utils.api import verify_admin_key, health_check

# ── Page config ────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="Xissin Admin",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Custom CSS ─────────────────────────────────────────────────────────────────
st.markdown("""
<style>
/* Dark background */
[data-testid="stAppViewContainer"] { background: #08101f; }
[data-testid="stSidebar"]          { background: #0d1830; border-right: 1px solid #1d2c4a; }
[data-testid="stSidebar"] * { color: #eef2ff !important; }

/* Hide default Streamlit header */
[data-testid="stHeader"] { display: none; }

/* Metric cards */
[data-testid="metric-container"] {
    background: #0d1830;
    border: 1px solid #1d2c4a;
    border-radius: 14px;
    padding: 16px !important;
}

/* Buttons */
.stButton > button {
    border-radius: 10px !important;
    font-weight: 700 !important;
    border: 1px solid #1d2c4a !important;
}
.stButton > button:hover { border-color: #5B8CFF !important; }

/* Inputs */
.stTextInput > div > div > input,
.stTextArea > div > div > textarea,
.stSelectbox > div > div {
    background: #121f3a !important;
    border: 1px solid #1d2c4a !important;
    border-radius: 10px !important;
    color: #eef2ff !important;
}

/* Dataframe */
[data-testid="stDataFrame"] {
    border: 1px solid #1d2c4a;
    border-radius: 12px;
}

/* Divider */
hr { border-color: #1d2c4a !important; }

/* Success / Error / Info / Warning colors */
.stSuccess  { background: rgba(126,231,193,.1) !important; border-color: rgba(126,231,193,.3) !important; }
.stError    { background: rgba(255,107,107,.1) !important; border-color: rgba(255,107,107,.3) !important; }
.stWarning  { background: rgba(255,167,38,.1)  !important; border-color: rgba(255,167,38,.3)  !important; }
.stInfo     { background: rgba(91,140,255,.1)  !important; border-color: rgba(91,140,255,.3)  !important; }
</style>
""", unsafe_allow_html=True)

# ── Session init ───────────────────────────────────────────────────────────────
if "authenticated" not in st.session_state:
    st.session_state.authenticated = False
if "admin_key" not in st.session_state:
    st.session_state.admin_key = ""

# ── Login gate ─────────────────────────────────────────────────────────────────
def show_login():
    col1, col2, col3 = st.columns([1, 1.2, 1])
    with col2:
        st.markdown("""
        <div style='text-align:center; padding: 40px 0 20px'>
            <div style='font-size:52px'>⚡</div>
            <h1 style='font-size:32px; font-weight:900; letter-spacing:8px;
                background:linear-gradient(135deg,#5B8CFF,#A78BFA);
                -webkit-background-clip:text; -webkit-text-fill-color:transparent;
                margin:10px 0 4px'>XISSIN</h1>
            <p style='color:#7a8ab8; font-size:12px; letter-spacing:3px; text-transform:uppercase;
                margin-bottom:32px'>Admin Control Panel</p>
        </div>
        """, unsafe_allow_html=True)

        with st.container(border=True):
            st.markdown("#### 🔑 Admin Key")
            key_input = st.text_input(
                "Admin Key",
                type="password",
                placeholder="Enter your admin key...",
                label_visibility="collapsed",
            )

            col_a, col_b = st.columns([1, 1])
            with col_a:
                remember = st.checkbox("Remember me", value=True)
            with col_b:
                st.markdown("")  # spacer

            login_btn = st.button("Login →", use_container_width=True, type="primary")

            if login_btn:
                if not key_input.strip():
                    st.error("Please enter your admin key.")
                else:
                    with st.spinner("Verifying..."):
                        valid = verify_admin_key(key_input.strip())
                    if valid:
                        st.session_state.authenticated = True
                        st.session_state.admin_key     = key_input.strip()
                        st.success("✓ Login successful!")
                        st.rerun()
                    else:
                        st.error("❌ Invalid admin key.")

        st.markdown("""
        <p style='text-align:center; color:#7a8ab8; font-size:11px; margin-top:20px'>
            Xissin Admin · Powered by Railway + Upstash
        </p>
        """, unsafe_allow_html=True)


# ── Main app (post-login) ──────────────────────────────────────────────────────
def show_app():
    # Sidebar
    with st.sidebar:
        st.markdown("""
        <div style='display:flex; align-items:center; gap:10px; margin-bottom:24px; padding:4px 0'>
            <div style='width:36px; height:36px; border-radius:10px;
                background:linear-gradient(135deg,#5B8CFF,#A78BFA);
                display:flex; align-items:center; justify-content:center;
                font-size:18px; box-shadow:0 0 18px rgba(91,140,255,.35)'>⚡</div>
            <span style='font-size:16px; font-weight:800; letter-spacing:3px;
                background:linear-gradient(135deg,#5B8CFF,#A78BFA);
                -webkit-background-clip:text; -webkit-text-fill-color:transparent'>XISSIN</span>
        </div>
        """, unsafe_allow_html=True)

        # Backend status
        online = health_check()
        status_color = "#7EE7C1" if online else "#FF6B6B"
        status_text  = "🟢 Online" if online else "🔴 Offline"
        st.markdown(f"""
        <div style='background:#121f3a; border:1px solid #1d2c4a; border-radius:12px;
            padding:12px 14px; margin-bottom:20px'>
            <div style='font-size:10px; color:#7a8ab8; text-transform:uppercase;
                letter-spacing:1px; margin-bottom:4px'>Backend</div>
            <div style='font-size:11px; font-family:monospace; color:#7EE7C1'>railway.app</div>
            <div style='font-size:12px; color:{status_color}; margin-top:4px;
                font-weight:700'>{status_text}</div>
        </div>
        """, unsafe_allow_html=True)

        st.markdown("---")

        if st.button("🚪 Logout", use_container_width=True):
            st.session_state.authenticated = False
            st.session_state.admin_key     = ""
            st.rerun()

    # Main content — redirect to dashboard by default
    st.markdown("""
    <div style='text-align:center; padding:60px 20px'>
        <div style='font-size:60px; margin-bottom:16px'>⚡</div>
        <h2 style='font-size:24px; font-weight:800; letter-spacing:4px;
            background:linear-gradient(135deg,#5B8CFF,#A78BFA);
            -webkit-background-clip:text; -webkit-text-fill-color:transparent'>
            Welcome to Xissin Admin
        </h2>
        <p style='color:#7a8ab8; margin-top:8px'>
            Use the sidebar to navigate to any section.
        </p>
    </div>
    """, unsafe_allow_html=True)


# ── Router ─────────────────────────────────────────────────────────────────────
if not st.session_state.authenticated:
    show_login()
else:
    show_app()
