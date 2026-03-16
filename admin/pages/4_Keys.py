"""
pages/4_Keys.py — Generate, view, filter and revoke activation keys
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from utils.api import get, post
from utils.theme import inject_theme, page_header, auth_guard

st.set_page_config(page_title="Keys · Xissin Admin", page_icon="🔑", layout="wide")
inject_theme()
auth_guard()

page_header("🔑", "Key Manager", "GENERATE · REDEEM · REVOKE · DELETE")

# ── Fetch ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=30, show_spinner=False)
def load_keys():
    return get("/api/keys/list").get("keys", [])

col_r, _ = st.columns([1, 8])
with col_r:
    if st.button("↺  REFRESH", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

with st.spinner("Loading key registry..."):
    keys = load_keys()

now      = datetime.utcnow()
total    = len(keys)
redeemed = sum(1 for k in keys if k.get("redeemed"))
available= sum(1 for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now)
expired  = sum(1 for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now)

# ── Stat row ───────────────────────────────────────────────────────────────────
c1, c2, c3, c4 = st.columns(4)
stat_data = [
    (c1, "🔑", "TOTAL KEYS",  total,    "#00e5ff", 0.0),
    (c2, "🟢", "AVAILABLE",   available,"#00ff9d", 0.08),
    (c3, "✅", "REDEEMED",    redeemed, "#a855f7", 0.16),
    (c4, "❌", "EXPIRED",     expired,  "#ff4757", 0.24),
]
for col, icon, label, value, color, delay in stat_data:
    with col:
        st.markdown(f"""
        <div style='background:linear-gradient(135deg,{color}0d,transparent);
            border:1px solid {color}33;border-radius:12px;padding:16px;
            position:relative;overflow:hidden;
            animation:cardFadeIn .5s ease {delay}s both'>
            <div style='position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,transparent,{color},transparent)'></div>
            <div style='font-family:"Share Tech Mono",monospace;font-size:9px;
                color:{color}88;letter-spacing:2px;margin-bottom:8px'>{icon} {label}</div>
            <div style='font-family:"Exo 2",sans-serif;font-weight:900;font-size:30px;
                color:{color}'>{value}</div>
        </div>
        """, unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Generate section ───────────────────────────────────────────────────────────
st.markdown("""
<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
    ◈ KEY GENERATION
</div>
""", unsafe_allow_html=True)

tab_single, tab_bulk = st.tabs(["⚡ Single Key", "💥 Bulk Generate"])

with tab_single:
    with st.container(border=True):
        col_a, col_b, col_c = st.columns([1, 1, 2])
        with col_a:
            is_lifetime = st.checkbox("♾️ Lifetime Key", key="single_lifetime")
        with col_b:
            duration = st.number_input("Duration (days)", min_value=1, max_value=36500,
                                       value=30, disabled=is_lifetime, key="single_duration")
        with col_c:
            note = st.text_input("Note (optional)", placeholder="e.g. For @username", key="single_note")

        if st.button("⚡  GENERATE KEY", type="primary", key="btn_single", use_container_width=True):
            try:
                days   = 36500 if is_lifetime else int(duration)
                result = post("/api/keys/generate", {"duration_days": days, "note": note.strip()})
                key_str = result.get("key", "")
                st.markdown(f"""
                <div style='background:rgba(0,255,157,.06);border:1px solid rgba(0,255,157,.3);
                    border-radius:10px;padding:16px;margin-top:8px;text-align:center;
                    animation:fadeUp .3s ease'>
                    <div style='font-family:"Share Tech Mono",monospace;font-size:10px;
                        color:#5a7a9a;letter-spacing:2px;margin-bottom:8px'>✓ KEY GENERATED</div>
                    <div style='font-family:"Share Tech Mono",monospace;font-size:18px;
                        color:#00ff9d;letter-spacing:3px;font-weight:700'>{key_str}</div>
                    <div style='font-size:11px;color:#5a7a9a;margin-top:8px'>Click to copy ↑</div>
                </div>
                """, unsafe_allow_html=True)
                st.code(key_str, language=None)
                st.cache_data.clear()
            except Exception as e:
                st.error(f"Error: {e}")

with tab_bulk:
    with st.container(border=True):
        col_a, col_b, col_c, col_d = st.columns([1, 1, 1, 2])
        with col_a:
            bulk_count = st.number_input("How many keys?", min_value=1, max_value=100, value=5, key="bulk_count")
        with col_b:
            bulk_lifetime = st.checkbox("♾️ Lifetime", key="bulk_lifetime")
        with col_c:
            bulk_duration = st.number_input("Duration (days)", min_value=1, max_value=36500,
                                            value=30, disabled=bulk_lifetime, key="bulk_duration")
        with col_d:
            bulk_note = st.text_input("Note (optional)", placeholder="e.g. Giveaway batch", key="bulk_note")

        if st.button(f"💥  GENERATE {bulk_count} KEYS", type="primary", key="btn_bulk", use_container_width=True):
            days      = 36500 if bulk_lifetime else int(bulk_duration)
            generated = []
            failed    = 0
            progress  = st.progress(0, text="Generating keys...")
            for i in range(int(bulk_count)):
                try:
                    result = post("/api/keys/generate", {"duration_days": days, "note": bulk_note.strip()})
                    generated.append(result.get("key", ""))
                except Exception:
                    failed += 1
                progress.progress((i + 1) / int(bulk_count), text=f"Generating {i+1}/{int(bulk_count)}...")
            progress.empty()

            if generated:
                st.markdown(f"""
                <div style='background:rgba(0,255,157,.06);border:1px solid rgba(0,255,157,.25);
                    border-radius:10px;padding:12px 16px;margin-bottom:12px;
                    font-family:"Share Tech Mono",monospace;font-size:12px;color:#00ff9d'>
                    ✓ {len(generated)} KEYS GENERATED{f" · {failed} FAILED" if failed else ""}
                </div>
                """, unsafe_allow_html=True)
                all_keys_text = "\n".join(generated)
                st.text_area("Generated Keys (copy all)", value=all_keys_text,
                             height=min(200, len(generated) * 32 + 20), key="bulk_output")
                st.cache_data.clear()
            else:
                st.error("Failed to generate any keys.")

st.markdown("<br>", unsafe_allow_html=True)

# ── Filter + Table ─────────────────────────────────────────────────────────────
st.markdown("""
<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
    ◈ KEY REGISTRY
</div>
""", unsafe_allow_html=True)

col_a, col_b = st.columns([3, 1])
with col_a:
    search = st.text_input("🔍 Search", placeholder="Search by key, note, or redeemed by...", label_visibility="collapsed")
with col_b:
    key_filter = st.selectbox("Filter", ["All", "Available", "Redeemed", "Expired"], label_visibility="collapsed")

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

st.markdown(f"""
<div style='font-family:"Share Tech Mono",monospace;font-size:10px;
    color:#5a7a9a;margin-bottom:8px'>
    SHOWING {len(filtered)} OF {total} KEYS
</div>
""", unsafe_allow_html=True)

if filtered:
    rows = []
    for k in filtered:
        exp_dt  = datetime.fromisoformat(k["expires_at"])
        is_life = k.get("lifetime") or k.get("duration_days", 0) >= 36500
        exp_flag= exp_dt <= now
        if k.get("redeemed"):    status_str = "✅ Redeemed"
        elif exp_flag:           status_str = "❌ Expired"
        else:                    status_str = "🟢 Available"
        days_left = ""
        if not k.get("redeemed") and not exp_flag and not is_life:
            days_left = f"{(exp_dt - now).days}d left"
        rows.append({
            "Key":         k.get("key", "-"),
            "Status":      status_str,
            "Duration":    "♾️ Lifetime" if is_life else f"{k.get('duration_days','-')}d",
            "Days Left":   days_left,
            "Created":     (k.get("created_at") or "-")[:10],
            "Expires":     (k.get("expires_at") or "-")[:10],
            "Redeemed By": k.get("redeemed_by") or "-",
            "Redeemed At": (k.get("redeemed_at") or "-")[:10],
            "Note":        k.get("note") or "-",
        })
    df = pd.DataFrame(rows)
    df.index = range(1, len(df) + 1)
    st.dataframe(df, use_container_width=True)
else:
    st.markdown("<p style='color:#5a7a9a;font-family:Share Tech Mono,monospace;font-size:12px'>No keys match your filter.</p>", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── Revoke + Delete section ────────────────────────────────────────────────────
st.markdown("""
<div style='font-family:"Share Tech Mono",monospace;font-size:11px;
    color:#2a4a6a;letter-spacing:3px;text-transform:uppercase;margin-bottom:12px'>
    ◈ DANGER ZONE
</div>
""", unsafe_allow_html=True)

tab_revoke, tab_del_single, tab_del_bulk = st.tabs(["🗑️ Revoke Key", "🗑️ Delete Single", "💣 Bulk Delete"])

with tab_revoke:
    with st.container(border=True):
        col_r, col_btn = st.columns([3, 1])
        with col_r:
            revoke_key_input = st.text_input("Key to revoke", placeholder="XISSIN-XXXX-XXXX-XXXX-XXXX")
        with col_btn:
            st.markdown("<br>", unsafe_allow_html=True)
            if st.button("🗑️  REVOKE", type="primary", use_container_width=True):
                if not revoke_key_input.strip():
                    st.error("Enter a key to revoke.")
                else:
                    try:
                        post("/api/keys/revoke", {"key": revoke_key_input.strip()})
                        st.success(f"✓ Key revoked.")
                        st.cache_data.clear()
                        st.rerun()
                    except Exception as e:
                        st.error(f"Error: {e}")

with tab_del_single:
    unredeemed_keys = [k for k in keys if not k.get("redeemed")]
    with st.container(border=True):
        if not unredeemed_keys:
            st.info("No unredeemed keys to delete.")
        else:
            key_options = {
                f"{k.get('key','-')}  ({'❌ Expired' if datetime.fromisoformat(k['expires_at'])<=now else '🟢 Available'})  {('· '+k['note']) if k.get('note') else ''}": k.get("key")
                for k in unredeemed_keys
            }
            selected_label = st.selectbox("Select key to delete", options=list(key_options.keys()))
            selected_key   = key_options[selected_label]
            st.warning(f"⚠️ About to permanently delete: `{selected_key}`")
            col_c, col_b2 = st.columns([3, 1])
            with col_c:
                confirm_text = st.text_input("Type the key to confirm", placeholder="XISSIN-XXXX-XXXX-XXXX-XXXX")
            with col_b2:
                st.markdown("<br>", unsafe_allow_html=True)
                if st.button("🗑️  DELETE", type="primary", use_container_width=True):
                    if confirm_text.strip() != selected_key:
                        st.error("❌ Confirmation does not match.")
                    else:
                        try:
                            post("/api/keys/delete", {"key": selected_key})
                            st.success(f"✓ Key deleted.")
                            st.cache_data.clear()
                            st.rerun()
                        except Exception as e:
                            st.error(f"Error: {e}")

with tab_del_bulk:
    expired_keys   = [k for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) <= now]
    available_keys = [k for k in keys if not k.get("redeemed") and datetime.fromisoformat(k["expires_at"]) > now]
    col_exp, col_avail = st.columns(2)

    with col_exp:
        with st.container(border=True):
            st.markdown(f"""
            <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
                color:#ff4757;letter-spacing:1px;margin-bottom:8px'>
                ❌ EXPIRED UNREDEEMED: {len(expired_keys)}
            </div>
            """, unsafe_allow_html=True)
            if not expired_keys:
                st.info("No expired unredeemed keys.")
            else:
                if "confirm_bulk_expired" not in st.session_state:
                    st.session_state["confirm_bulk_expired"] = False
                if not st.session_state["confirm_bulk_expired"]:
                    if st.button(f"🗑️ Delete All {len(expired_keys)} Expired", type="primary"):
                        st.session_state["confirm_bulk_expired"] = True
                        st.rerun()
                else:
                    st.warning("⚠️ This will permanently delete all expired keys!")
                    col_yes, col_no = st.columns(2)
                    with col_yes:
                        if st.button("✅ Confirm Delete", type="primary"):
                            deleted, failed = 0, 0
                            prog = st.progress(0)
                            for i, k in enumerate(expired_keys):
                                try:
                                    post("/api/keys/delete", {"key": k.get("key")})
                                    deleted += 1
                                except: failed += 1
                                prog.progress((i+1)/len(expired_keys))
                            prog.empty()
                            st.session_state["confirm_bulk_expired"] = False
                            st.success(f"✓ Deleted {deleted} key(s).")
                            st.cache_data.clear()
                            st.rerun()
                    with col_no:
                        if st.button("❌ Cancel"):
                            st.session_state["confirm_bulk_expired"] = False
                            st.rerun()

    with col_avail:
        with st.container(border=True):
            st.markdown(f"""
            <div style='font-family:"Share Tech Mono",monospace;font-size:11px;
                color:#ff9500;letter-spacing:1px;margin-bottom:8px'>
                🟢 AVAILABLE UNREDEEMED: {len(available_keys)}
            </div>
            """, unsafe_allow_html=True)
            if not available_keys:
                st.info("No available unredeemed keys.")
            else:
                st.warning("⚠️ This deletes valid unused keys permanently!")
                confirm_avail = st.text_input("Type DELETE to confirm", placeholder="DELETE")
                if st.button(f"🗑️ Delete All {len(available_keys)} Available", type="primary"):
                    if confirm_avail.strip() != "DELETE":
                        st.error("❌ Type DELETE to confirm.")
                    else:
                        deleted, failed = 0, 0
                        prog = st.progress(0)
                        for i, k in enumerate(available_keys):
                            try:
                                post("/api/keys/delete", {"key": k.get("key")})
                                deleted += 1
                            except: failed += 1
                            prog.progress((i+1)/len(available_keys))
                        prog.empty()
                        st.success(f"✓ Deleted {deleted} key(s).")
                        st.cache_data.clear()
                        st.rerun()
