# ============================================================
#  admin/pages/15_CODM_Cookies.py
#  Manage DataDome cookie pool and proxy pool for CODM checker
#  Stored in Upstash Redis — no Railway redeployment needed
# ============================================================

import streamlit as st
from utils.api import get, post, delete

st.set_page_config(
    page_title="CODM Cookies & Proxies — Xissin Admin",
    page_icon="🍪",
    layout="wide",
)

# ── Auth guard ────────────────────────────────────────────────
if not st.session_state.get("authenticated"):
    st.error("🔒 Please log in from the main page.")
    st.stop()

# ── Page header ───────────────────────────────────────────────
st.markdown("## 🍪 CODM — Cookies & Proxy Pool")
st.markdown(
    "Manage DataDome cookies and proxy pool for the CODM checker. "
    "Changes are stored in **Upstash Redis** and take effect immediately — "
    "no Railway redeployment required.",
)
st.divider()

# ── Tabs ──────────────────────────────────────────────────────
tab_cookies, tab_proxies, tab_help = st.tabs(
    ["🍪 DataDome Cookies", "🔀 Proxy Pool", "📖 Help"]
)


# ══════════════════════════════════════════════════════════════
#  TAB 1 — DataDome Cookies
# ══════════════════════════════════════════════════════════════
with tab_cookies:
    st.markdown("### Current Cookie Pool")

    # ── Fetch current cookies ─────────────────────────────────
    with st.spinner("Loading cookies from Redis…"):
        try:
            data = get("/api/codm/cookies")
            current_cookies: list = data.get("cookies", [])
            source: str = data.get("source", "unknown")
            count: int = data.get("count", 0)
        except Exception as e:
            st.error(f"❌ Failed to fetch cookies: {e}")
            current_cookies = []
            source = "error"
            count = 0

    # ── Status badge ─────────────────────────────────────────
    col1, col2, col3 = st.columns(3)
    col1.metric("🍪 Total Cookies", count)
    col2.metric(
        "📍 Source",
        "Upstash Redis" if source == "redis" else ("Env Var (fallback)" if source == "env" else source),
    )
    col3.metric("🔄 Status", "✅ Active" if count > 0 else "⚠️ Empty — using env fallback")

    st.markdown("---")

    # ── Show existing cookies ─────────────────────────────────
    if current_cookies:
        st.markdown(f"**Stored cookies ({len(current_cookies)}):**")
        for i, cookie in enumerate(current_cookies, 1):
            # Truncate for display — show first 60 chars + last 10 chars
            display = cookie if len(cookie) <= 80 else f"{cookie[:60]}…{cookie[-10:]}"
            col_a, col_b = st.columns([10, 1])
            col_a.code(f"{i:>2}. {display}", language=None)
            if col_b.button("🗑️", key=f"del_cookie_{i}", help="Remove this cookie"):
                # Remove this specific cookie and re-save the rest
                updated = [c for j, c in enumerate(current_cookies, 1) if j != i]
                try:
                    if updated:
                        post("/api/codm/cookies", {"cookies": updated})
                        st.success(f"✅ Cookie #{i} removed.")
                    else:
                        delete("/api/codm/cookies")
                        st.success("✅ Last cookie removed. Pool is now empty.")
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ Failed to remove cookie: {e}")
    else:
        st.info(
            "ℹ️ No cookies in Redis. The backend will fall back to the "
            "`CODM_COOKIES` environment variable on Railway if set."
        )

    st.markdown("---")

    # ── Add / Replace cookies ─────────────────────────────────
    st.markdown("### ➕ Add / Replace Cookies")
    st.markdown(
        "Paste your fresh DataDome cookies below — **one per line**. "
        "Each line should be `datadome=VALUE` or just the raw value. "
        "The backend picks one at random for each check request."
    )

    new_cookies_raw = st.text_area(
        "DataDome Cookies (one per line)",
        height=200,
        placeholder=(
            "datadome=ABC123...xyz\n"
            "datadome=DEF456...abc\n"
            "# Lines starting with # are ignored"
        ),
        key="cookie_input",
    )

    col_replace, col_append, col_clear = st.columns([2, 2, 1])

    with col_replace:
        if st.button("💾 Replace All", type="primary", use_container_width=True):
            lines = [
                l.strip()
                for l in new_cookies_raw.splitlines()
                if l.strip() and not l.strip().startswith("#")
            ]
            if not lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    res = post("/api/codm/cookies", {"cookies": lines})
                    st.success(res.get("message", f"✅ {len(lines)} cookie(s) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_append:
        if st.button("➕ Append to Pool", use_container_width=True):
            lines = [
                l.strip()
                for l in new_cookies_raw.splitlines()
                if l.strip() and not l.strip().startswith("#")
            ]
            if not lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    merged = current_cookies + [l for l in lines if l not in current_cookies]
                    res = post("/api/codm/cookies", {"cookies": merged})
                    st.success(res.get("message", f"✅ Added {len(lines)} cookie(s). Pool now has {len(merged)}."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_clear:
        if st.button("🗑️ Clear All", use_container_width=True):
            if st.session_state.get("confirm_clear_cookies"):
                try:
                    delete("/api/codm/cookies")
                    st.success("✅ Cookie pool cleared.")
                    st.session_state["confirm_clear_cookies"] = False
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
            else:
                st.session_state["confirm_clear_cookies"] = True
                st.warning("⚠️ Click again to confirm clear.")

    # ── Upload .txt file ─────────────────────────────────────
    st.markdown("---")
    st.markdown("### 📁 Upload fresh_cookie.txt")
    st.markdown("Upload your `fresh_cookie.txt` file directly — each line is added as a cookie.")

    uploaded = st.file_uploader(
        "Upload cookie file (.txt)",
        type=["txt"],
        help="Each non-empty line will be treated as a cookie entry.",
    )

    if uploaded is not None:
        content = uploaded.read().decode("utf-8", errors="ignore")
        file_lines = [
            l.strip()
            for l in content.splitlines()
            if l.strip() and not l.strip().startswith("#")
        ]
        if file_lines:
            st.markdown(f"**Preview ({len(file_lines)} lines):**")
            preview = "\n".join(
                f"{i:>2}. {l[:80]}{'…' if len(l) > 80 else ''}"
                for i, l in enumerate(file_lines[:10], 1)
            )
            if len(file_lines) > 10:
                preview += f"\n… and {len(file_lines) - 10} more"
            st.code(preview, language=None)

            col_save_file, col_append_file = st.columns(2)
            with col_save_file:
                if st.button("💾 Replace Pool with File", type="primary", use_container_width=True):
                    try:
                        res = post("/api/codm/cookies", {"cookies": file_lines})
                        st.success(res.get("message", f"✅ {len(file_lines)} cookie(s) saved."))
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
            with col_append_file:
                if st.button("➕ Append File to Pool", use_container_width=True):
                    try:
                        merged = current_cookies + [l for l in file_lines if l not in current_cookies]
                        res = post("/api/codm/cookies", {"cookies": merged})
                        st.success(res.get("message", f"✅ Pool now has {len(merged)} cookie(s)."))
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
        else:
            st.warning("⚠️ File appears empty or has no valid lines.")


# ══════════════════════════════════════════════════════════════
#  TAB 2 — Proxy Pool
# ══════════════════════════════════════════════════════════════
with tab_proxies:
    st.markdown("### Current Proxy Pool")
    st.markdown(
        "Proxies are used server-side (Railway backend) when checking CODM accounts. "
        "Users can also supply their own proxy from the Flutter app. "
        "Backend picks a random proxy from this pool if none is provided by the user."
    )

    # ── Fetch current proxies ─────────────────────────────────
    with st.spinner("Loading proxies from Redis…"):
        try:
            pdata = get("/api/codm/proxies")
            current_proxies: list = pdata.get("proxies", [])
            pcount: int = pdata.get("count", 0)
        except Exception as e:
            st.error(f"❌ Failed to fetch proxies: {e}")
            current_proxies = []
            pcount = 0

    col1, col2 = st.columns(2)
    col1.metric("🔀 Total Proxies", pcount)
    col2.metric("🔄 Status", "✅ Active" if pcount > 0 else "⚠️ No proxies — direct connection used")

    st.markdown("---")

    # ── Show existing proxies ─────────────────────────────────
    if current_proxies:
        st.markdown(f"**Stored proxies ({len(current_proxies)}):**")
        for i, proxy in enumerate(current_proxies, 1):
            # Mask password in display if present
            display = proxy
            if "@" in proxy:
                # http://user:PASS@host:port → http://user:****@host:port
                try:
                    parts = proxy.split("@", 1)
                    creds = parts[0].split("://", 1)
                    if len(creds) == 2:
                        user_pass = creds[1].split(":", 1)
                        if len(user_pass) == 2:
                            display = f"{creds[0]}://{user_pass[0]}:****@{parts[1]}"
                except Exception:
                    pass
            col_a, col_b = st.columns([10, 1])
            col_a.code(f"{i:>2}. {display}", language=None)
            if col_b.button("🗑️", key=f"del_proxy_{i}", help="Remove this proxy"):
                updated = [p for j, p in enumerate(current_proxies, 1) if j != i]
                try:
                    if updated:
                        post("/api/codm/proxies", {"proxies": updated})
                        st.success(f"✅ Proxy #{i} removed.")
                    else:
                        delete("/api/codm/proxies")
                        st.success("✅ Last proxy removed. Pool is now empty.")
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ Failed to remove proxy: {e}")
    else:
        st.info("ℹ️ No proxies in pool. The backend will use a direct connection.")

    st.markdown("---")

    # ── Add / Replace proxies ─────────────────────────────────
    st.markdown("### ➕ Add / Replace Proxies")
    st.markdown(
        "Supported formats (one per line):\n"
        "- `http://user:pass@host:port`\n"
        "- `http://host:port`\n"
        "- `host:port` (http assumed)\n"
        "- `socks5://host:port`"
    )

    new_proxies_raw = st.text_area(
        "Proxies (one per line)",
        height=180,
        placeholder=(
            "http://user:pass@192.168.1.1:8080\n"
            "http://proxy2.example.com:3128\n"
            "socks5://user:pass@proxy3.example.com:1080"
        ),
        key="proxy_input",
    )

    col_preplace, col_pappend, col_pclear = st.columns([2, 2, 1])

    with col_preplace:
        if st.button("💾 Replace All Proxies", type="primary", use_container_width=True):
            lines = [
                l.strip()
                for l in new_proxies_raw.splitlines()
                if l.strip() and not l.strip().startswith("#")
            ]
            if not lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    res = post("/api/codm/proxies", {"proxies": lines})
                    st.success(res.get("message", f"✅ {len(lines)} proxy(ies) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_pappend:
        if st.button("➕ Append Proxies", use_container_width=True):
            lines = [
                l.strip()
                for l in new_proxies_raw.splitlines()
                if l.strip() and not l.strip().startswith("#")
            ]
            if not lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    merged = current_proxies + [l for l in lines if l not in current_proxies]
                    res = post("/api/codm/proxies", {"proxies": merged})
                    st.success(res.get("message", f"✅ Pool now has {len(merged)} proxy(ies)."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_pclear:
        if st.button("🗑️ Clear All Proxies", use_container_width=True):
            if st.session_state.get("confirm_clear_proxies"):
                try:
                    delete("/api/codm/proxies")
                    st.success("✅ Proxy pool cleared.")
                    st.session_state["confirm_clear_proxies"] = False
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
            else:
                st.session_state["confirm_clear_proxies"] = True
                st.warning("⚠️ Click again to confirm clear.")

    # ── Upload proxy .txt ─────────────────────────────────────
    st.markdown("---")
    st.markdown("### 📁 Upload proxy list .txt")
    uploaded_proxy = st.file_uploader(
        "Upload proxy file (.txt)",
        type=["txt"],
        key="proxy_file",
        help="Each non-empty line = one proxy.",
    )
    if uploaded_proxy is not None:
        pcontent = uploaded_proxy.read().decode("utf-8", errors="ignore")
        pfile_lines = [
            l.strip()
            for l in pcontent.splitlines()
            if l.strip() and not l.strip().startswith("#")
        ]
        if pfile_lines:
            st.markdown(f"**Preview ({len(pfile_lines)} proxies):**")
            ppreview = "\n".join(
                f"{i:>2}. {l}" for i, l in enumerate(pfile_lines[:8], 1)
            )
            if len(pfile_lines) > 8:
                ppreview += f"\n… and {len(pfile_lines) - 8} more"
            st.code(ppreview, language=None)

            if st.button("💾 Replace Pool with File", key="save_proxy_file", type="primary"):
                try:
                    res = post("/api/codm/proxies", {"proxies": pfile_lines})
                    st.success(res.get("message", f"✅ {len(pfile_lines)} proxy(ies) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
        else:
            st.warning("⚠️ File appears empty or has no valid lines.")


# ══════════════════════════════════════════════════════════════
#  TAB 3 — Help
# ══════════════════════════════════════════════════════════════
with tab_help:
    st.markdown("### 📖 How It Works")

    st.markdown("""
#### 🍪 DataDome Cookies
DataDome is the bot-detection system Garena uses. Without a valid DataDome cookie,
the backend gets blocked (HTTP 403). These cookies expire, so you need to refresh
them periodically.

**How to get fresh cookies:**
1. Open `fresh_cookie.txt` from your local CODM Python script.
2. Each line starting with `datadome=` is a valid cookie.
3. Paste them here or upload the file directly — no Railway redeploy needed.

**Cookie priority:**
```
Redis (codm:cookies)  →  Railway env var CODM_COOKIES  →  no cookie (likely blocked)
```

**Rotation:** The backend picks one cookie at random per request, spreading load
across your cookie pool and reducing ban risk.

---

#### 🔀 Proxy Pool
Proxies route Garena API traffic through different IPs. This helps when:
- Your Railway server IP gets rate-limited or blocked.
- You want to check combos from different regions.

**Supported formats:**
```
http://user:pass@host:port     ← recommended (authenticated)
http://host:port               ← unauthenticated
host:port                      ← http:// is assumed
socks5://host:port             ← SOCKS5 supported
```

**Proxy priority (per request):**
```
User-provided proxy (Flutter app)  →  Redis pool (random)  →  direct connection
```

> 💡 **Tip:** Free proxies are unreliable. Use paid residential proxies for best results
> with Garena's DataDome protection.

---

#### 🔄 Refresh Schedule (Recommendation)
| Cookie age | Action |
|---|---|
| < 6 hours  | ✅ Still fresh, no action needed |
| 6–24 hours | ⚠️ May work, but consider refreshing |
| > 24 hours | ❌ Likely expired — refresh ASAP |

Replace cookies whenever you see consistent `403` or `blocked` errors in CODM checker logs.
""")
