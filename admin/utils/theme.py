"""
utils/theme.py — Xissin Admin · Cyberpunk Command Center Theme
Inject this once per page with:  from utils.theme import inject_theme; inject_theme()
"""

import streamlit as st

# ── Google Fonts ───────────────────────────────────────────────────────────────
FONTS = """
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Rajdhani:wght@400;500;600;700&family=Exo+2:wght@300;400;600;700;800;900&display=swap" rel="stylesheet">
"""

CSS = """
<style>
/* ── Variables ─────────────────────────────────────────────────────────────── */
:root {
  --bg:           #030b16;
  --bg2:          #060f1e;
  --bg3:          #0a1628;
  --border:       #0d2040;
  --border-glow:  #1a3a6a;
  --cyan:         #00e5ff;
  --cyan-dim:     #00b8d4;
  --purple:       #a855f7;
  --purple-dim:   #7c3aed;
  --pink:         #f472b6;
  --green:        #00ff9d;
  --orange:       #ff9500;
  --red:          #ff4757;
  --text:         #c8d8f0;
  --text-dim:     #5a7a9a;
  --text-bright:  #e8f4ff;
  --mono:         'Share Tech Mono', monospace;
  --heading:      'Exo 2', sans-serif;
  --body:         'Rajdhani', sans-serif;
}

/* ── Base ──────────────────────────────────────────────────────────────────── */
html, body, [data-testid="stAppViewContainer"] {
  background: var(--bg) !important;
  font-family: var(--body) !important;
  color: var(--text) !important;
}
[data-testid="stAppViewContainer"]::before {
  content: '';
  position: fixed;
  inset: 0;
  background:
    radial-gradient(ellipse 80% 50% at 10% 0%,   rgba(0,229,255,.04) 0%, transparent 60%),
    radial-gradient(ellipse 60% 40% at 90% 100%,  rgba(168,85,247,.05) 0%, transparent 60%),
    repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,229,255,.012) 2px, rgba(0,229,255,.012) 3px);
  pointer-events: none;
  z-index: 0;
}

/* ── Sidebar ───────────────────────────────────────────────────────────────── */
[data-testid="stSidebar"] {
  background: var(--bg2) !important;
  border-right: 1px solid var(--border) !important;
}
[data-testid="stSidebar"]::before {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, rgba(0,229,255,.04) 0%, transparent 40%);
  pointer-events: none;
}
[data-testid="stSidebar"] * { color: var(--text) !important; }
[data-testid="stSidebarNavLink"] {
  border-radius: 8px !important;
  transition: all .2s !important;
  font-family: var(--body) !important;
  font-weight: 600 !important;
  letter-spacing: .5px !important;
}
[data-testid="stSidebarNavLink"]:hover {
  background: rgba(0,229,255,.08) !important;
  border-left: 2px solid var(--cyan) !important;
}
[data-testid="stSidebarNavLink"][aria-current="page"] {
  background: rgba(0,229,255,.12) !important;
  border-left: 2px solid var(--cyan) !important;
  color: var(--cyan) !important;
}

/* ── Hide default header ───────────────────────────────────────────────────── */
[data-testid="stHeader"],
[data-testid="stDecoration"] { display: none !important; }

/* ── Typography ────────────────────────────────────────────────────────────── */
h1, h2, h3 {
  font-family: var(--heading) !important;
  font-weight: 800 !important;
  color: var(--text-bright) !important;
  letter-spacing: 1px !important;
}

/* ── Metric cards ──────────────────────────────────────────────────────────── */
[data-testid="metric-container"] {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  border-radius: 12px !important;
  padding: 16px !important;
  position: relative !important;
  overflow: hidden !important;
  transition: border-color .3s, box-shadow .3s !important;
  animation: cardFadeIn .5s ease both !important;
}
[data-testid="metric-container"]::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--cyan), transparent);
  animation: scanTop 4s ease-in-out infinite;
}
[data-testid="metric-container"]:hover {
  border-color: var(--cyan-dim) !important;
  box-shadow: 0 0 20px rgba(0,229,255,.12) !important;
}
[data-testid="metric-container"] [data-testid="stMetricLabel"] {
  font-family: var(--mono) !important;
  font-size: 11px !important;
  color: var(--text-dim) !important;
  letter-spacing: 1.5px !important;
  text-transform: uppercase !important;
}
[data-testid="metric-container"] [data-testid="stMetricValue"] {
  font-family: var(--heading) !important;
  font-weight: 800 !important;
  font-size: 28px !important;
  background: linear-gradient(135deg, var(--cyan), var(--purple)) !important;
  -webkit-background-clip: text !important;
  -webkit-text-fill-color: transparent !important;
  animation: countUp .6s ease both !important;
}

/* ── Buttons ───────────────────────────────────────────────────────────────── */
.stButton > button {
  font-family: var(--body) !important;
  font-weight: 700 !important;
  font-size: 13px !important;
  letter-spacing: .8px !important;
  border-radius: 8px !important;
  border: 1px solid var(--border-glow) !important;
  background: var(--bg3) !important;
  color: var(--text) !important;
  transition: all .2s ease !important;
  text-transform: uppercase !important;
}
.stButton > button:hover {
  border-color: var(--cyan) !important;
  color: var(--cyan) !important;
  box-shadow: 0 0 12px rgba(0,229,255,.2), inset 0 0 12px rgba(0,229,255,.05) !important;
  transform: translateY(-1px) !important;
}
.stButton > button[kind="primary"] {
  background: linear-gradient(135deg, rgba(0,229,255,.15), rgba(168,85,247,.15)) !important;
  border-color: var(--cyan-dim) !important;
  color: var(--cyan) !important;
}
.stButton > button[kind="primary"]:hover {
  background: linear-gradient(135deg, rgba(0,229,255,.25), rgba(168,85,247,.25)) !important;
  box-shadow: 0 0 20px rgba(0,229,255,.3) !important;
}

/* ── Inputs ────────────────────────────────────────────────────────────────── */
.stTextInput > div > div > input,
.stTextArea > div > div > textarea,
.stNumberInput > div > div > input {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  border-radius: 8px !important;
  color: var(--text-bright) !important;
  font-family: var(--mono) !important;
  font-size: 13px !important;
  transition: border-color .2s, box-shadow .2s !important;
}
.stTextInput > div > div > input:focus,
.stTextArea > div > div > textarea:focus {
  border-color: var(--cyan) !important;
  box-shadow: 0 0 0 2px rgba(0,229,255,.15) !important;
}
.stSelectbox > div > div,
.stMultiSelect > div > div {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  border-radius: 8px !important;
  color: var(--text) !important;
}
[data-baseweb="select"] > div { background: var(--bg3) !important; }
[data-baseweb="popover"] { background: var(--bg2) !important; border: 1px solid var(--border-glow) !important; }
[data-baseweb="menu"] { background: var(--bg2) !important; }
[data-baseweb="option"]:hover { background: rgba(0,229,255,.08) !important; }

/* ── Dataframe / Tables ────────────────────────────────────────────────────── */
[data-testid="stDataFrame"] {
  border: 1px solid var(--border-glow) !important;
  border-radius: 10px !important;
  overflow: hidden !important;
}
[data-testid="stDataFrame"] th {
  background: var(--bg3) !important;
  color: var(--cyan) !important;
  font-family: var(--mono) !important;
  font-size: 11px !important;
  letter-spacing: 1px !important;
  text-transform: uppercase !important;
  border-bottom: 1px solid var(--border-glow) !important;
}
[data-testid="stDataFrame"] td {
  font-family: var(--mono) !important;
  font-size: 12px !important;
  color: var(--text) !important;
  border-bottom: 1px solid var(--border) !important;
}
[data-testid="stDataFrame"] tr:hover td {
  background: rgba(0,229,255,.04) !important;
}

/* ── Containers / Cards ────────────────────────────────────────────────────── */
[data-testid="stVerticalBlockBorderWrapper"] {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  border-radius: 12px !important;
  transition: border-color .3s !important;
}
[data-testid="stVerticalBlockBorderWrapper"]:hover {
  border-color: rgba(0,229,255,.25) !important;
}

/* ── Expander ──────────────────────────────────────────────────────────────── */
[data-testid="stExpander"] {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  border-radius: 10px !important;
}
[data-testid="stExpander"] summary {
  font-family: var(--body) !important;
  font-weight: 700 !important;
  color: var(--text) !important;
}
[data-testid="stExpander"] summary:hover { color: var(--cyan) !important; }

/* ── Tabs ──────────────────────────────────────────────────────────────────── */
[data-testid="stTabs"] [role="tablist"] {
  border-bottom: 1px solid var(--border-glow) !important;
  gap: 4px !important;
}
[data-testid="stTabs"] [role="tab"] {
  font-family: var(--body) !important;
  font-weight: 700 !important;
  font-size: 13px !important;
  letter-spacing: .5px !important;
  color: var(--text-dim) !important;
  border-radius: 8px 8px 0 0 !important;
  padding: 8px 16px !important;
  transition: all .2s !important;
}
[data-testid="stTabs"] [role="tab"]:hover { color: var(--text) !important; }
[data-testid="stTabs"] [role="tab"][aria-selected="true"] {
  color: var(--cyan) !important;
  border-bottom: 2px solid var(--cyan) !important;
  background: rgba(0,229,255,.06) !important;
}

/* ── Progress bar ──────────────────────────────────────────────────────────── */
[data-testid="stProgress"] > div > div {
  background: linear-gradient(90deg, var(--cyan), var(--purple)) !important;
  border-radius: 4px !important;
  box-shadow: 0 0 8px rgba(0,229,255,.4) !important;
}
[data-testid="stProgress"] > div {
  background: var(--border) !important;
  border-radius: 4px !important;
}

/* ── Toggle / Checkbox ─────────────────────────────────────────────────────── */
[data-testid="stToggle"] [role="switch"][aria-checked="true"] {
  background: var(--cyan) !important;
  box-shadow: 0 0 8px rgba(0,229,255,.4) !important;
}

/* ── Alert boxes ───────────────────────────────────────────────────────────── */
[data-testid="stAlert"] {
  border-radius: 10px !important;
  font-family: var(--body) !important;
  font-weight: 600 !important;
}
.stSuccess  { background: rgba(0,255,157,.08) !important; border-color: rgba(0,255,157,.3) !important; color: var(--green) !important; }
.stError    { background: rgba(255,71,87,.08)  !important; border-color: rgba(255,71,87,.3)  !important; color: var(--red) !important; }
.stWarning  { background: rgba(255,149,0,.08)  !important; border-color: rgba(255,149,0,.3)  !important; color: var(--orange) !important; }
.stInfo     { background: rgba(0,229,255,.06)  !important; border-color: rgba(0,229,255,.25) !important; color: var(--cyan-dim) !important; }

/* ── Divider ───────────────────────────────────────────────────────────────── */
hr {
  border: none !important;
  height: 1px !important;
  background: linear-gradient(90deg, transparent, var(--border-glow), transparent) !important;
  margin: 16px 0 !important;
}

/* ── Scrollbar ─────────────────────────────────────────────────────────────── */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--bg2); }
::-webkit-scrollbar-thumb { background: var(--border-glow); border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--cyan-dim); }

/* ── Caption / small text ─────────────────────────────────────────────────── */
[data-testid="stCaptionContainer"] {
  font-family: var(--mono) !important;
  font-size: 11px !important;
  color: var(--text-dim) !important;
}

/* ── Code blocks ───────────────────────────────────────────────────────────── */
code, pre, [data-testid="stCode"] {
  background: var(--bg3) !important;
  border: 1px solid var(--border-glow) !important;
  color: var(--cyan) !important;
  font-family: var(--mono) !important;
  border-radius: 6px !important;
}

/* ── Spinner ───────────────────────────────────────────────────────────────── */
[data-testid="stSpinner"] {
  color: var(--cyan) !important;
}

/* ── Download button ───────────────────────────────────────────────────────── */
[data-testid="stDownloadButton"] > button {
  background: rgba(0,229,255,.08) !important;
  border: 1px solid var(--cyan-dim) !important;
  color: var(--cyan) !important;
  font-family: var(--body) !important;
  font-weight: 700 !important;
}

/* ── Keyframe animations ───────────────────────────────────────────────────── */
@keyframes cardFadeIn {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes scanTop {
  0%,100% { opacity: 0; }
  40%,60% { opacity: 1; }
}
@keyframes countUp {
  from { opacity: 0; transform: scale(.9); }
  to   { opacity: 1; transform: scale(1); }
}
@keyframes pulse {
  0%,100% { box-shadow: 0 0 0 0 rgba(0,229,255,.4); }
  50%     { box-shadow: 0 0 0 6px rgba(0,229,255,0); }
}
@keyframes glow {
  0%,100% { text-shadow: 0 0 8px rgba(0,229,255,.4); }
  50%     { text-shadow: 0 0 20px rgba(0,229,255,.8); }
}
@keyframes slideIn {
  from { opacity: 0; transform: translateX(-12px); }
  to   { opacity: 1; transform: translateX(0); }
}
@keyframes fadeUp {
  from { opacity: 0; transform: translateY(16px); }
  to   { opacity: 1; transform: translateY(0); }
}
@keyframes borderScan {
  0%   { background-position: 0% 50%; }
  100% { background-position: 100% 50%; }
}
@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
"""


def inject_theme():
    """Inject the full Cyberpunk Command Center theme into any Streamlit page."""
    st.markdown(FONTS + CSS, unsafe_allow_html=True)


def page_header(icon: str, title: str, subtitle: str = ""):
    """Render an animated page header with gradient title."""
    sub_html = f"<p style='font-family:var(--mono);font-size:12px;color:var(--text-dim);letter-spacing:2px;margin:4px 0 0'>{subtitle}</p>" if subtitle else ""
    st.markdown(f"""
    <div style='animation:fadeUp .5s ease both; margin-bottom:8px'>
        <div style='display:flex; align-items:center; gap:12px'>
            <div style='width:42px;height:42px;border-radius:10px;
                background:linear-gradient(135deg,rgba(0,229,255,.15),rgba(168,85,247,.15));
                border:1px solid rgba(0,229,255,.3);
                display:flex;align-items:center;justify-content:center;
                font-size:20px;box-shadow:0 0 16px rgba(0,229,255,.2)'>
                {icon}
            </div>
            <div>
                <h2 style='font-family:Exo 2,sans-serif;font-weight:900;font-size:24px;
                    background:linear-gradient(135deg,#00e5ff,#a855f7);
                    -webkit-background-clip:text;-webkit-text-fill-color:transparent;
                    margin:0;letter-spacing:2px;text-transform:uppercase'>
                    {title}
                </h2>
                {sub_html}
            </div>
        </div>
    </div>
    """, unsafe_allow_html=True)
    st.markdown("""
    <div style='height:1px;background:linear-gradient(90deg,var(--cyan),var(--purple),transparent);
        margin-bottom:20px;animation:borderScan 3s linear infinite;
        background-size:200% 100%'></div>
    """, unsafe_allow_html=True)


def stat_card(icon: str, label: str, value, color: str = "#00e5ff", delay: float = 0):
    """Render a standalone animated stat card."""
    st.markdown(f"""
    <div style='background:var(--bg3);border:1px solid var(--border-glow);border-radius:12px;
        padding:16px 20px;position:relative;overflow:hidden;
        animation:cardFadeIn .5s ease {delay}s both;
        transition:border-color .3s,box-shadow .3s'
        onmouseover="this.style.borderColor='{color}';this.style.boxShadow='0 0 20px {color}33'"
        onmouseout="this.style.borderColor='var(--border-glow)';this.style.boxShadow='none'">
        <div style='position:absolute;top:0;left:0;right:0;height:2px;
            background:linear-gradient(90deg,transparent,{color},transparent)'></div>
        <div style='font-family:var(--mono);font-size:10px;color:var(--text-dim);
            letter-spacing:2px;text-transform:uppercase;margin-bottom:8px'>{icon} {label}</div>
        <div style='font-family:Exo 2,sans-serif;font-weight:900;font-size:30px;
            color:{color};line-height:1'>{value}</div>
    </div>
    """, unsafe_allow_html=True)


def status_badge(online: bool):
    """Animated online/offline status badge."""
    color = "#00ff9d" if online else "#ff4757"
    label = "ONLINE" if online else "OFFLINE"
    return f"""
    <span style='display:inline-flex;align-items:center;gap:6px;
        background:{"rgba(0,255,157,.1)" if online else "rgba(255,71,87,.1)"};
        border:1px solid {color}44;border-radius:20px;
        padding:4px 10px;font-family:var(--mono);font-size:11px;color:{color}'>
        <span style='width:7px;height:7px;border-radius:50%;background:{color};
            animation:pulse 2s infinite'></span>
        {label}
    </span>
    """


def auth_guard():
    """Check authentication — stop page if not logged in."""
    if not st.session_state.get("authenticated"):
        st.markdown("""
        <div style='text-align:center;padding:80px 20px;animation:fadeUp .5s ease'>
            <div style='font-size:48px;margin-bottom:16px'>🔒</div>
            <p style='font-family:var(--mono);color:var(--text-dim);letter-spacing:2px'>
                ACCESS DENIED · AUTHENTICATION REQUIRED
            </p>
            <p style='color:var(--text-dim);font-size:13px'>
                Return to the main page to login.
            </p>
        </div>
        """, unsafe_allow_html=True)
        st.stop()
