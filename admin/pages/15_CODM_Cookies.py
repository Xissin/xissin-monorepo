# ============================================================
#  admin/pages/15_CODM_Cookies.py  —  v2
#  Manage DataDome cookie pool and proxy pool for CODM checker.
#  Stored in Upstash Redis — no Railway redeployment needed.
#
#  Improvements over v1:
#  - Cookie / proxy health badge (🔴 empty → 🟡 low → 🟢 good)
#  - Duplicate detection + one-click dedup
#  - Cookie format normalizer on save (handles raw value / datadome=VALUE)
#  - Proxy format validator before saving (warns on bad format)
#  - Download current pool as .txt
#  - Last-saved timestamp stored alongside pool in Redis
# ============================================================

import io
import re
import streamlit as st
from datetime import datetime, timezone
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

# ── Helpers ───────────────────────────────────────────────────

def _health_badge(count: int, low_threshold: int = 3) -> str:
    if count == 0:
        return "🔴 Empty"
    if count < low_threshold:
        return f"🟡 Low ({count})"
    return f"🟢 Good ({count})"


def _normalize_cookie(raw: str) -> str:
    """Ensure cookie is stored as raw datadome value (no prefix)."""
    raw = raw.strip()
    # Strip 'datadome=' prefix — backend adds it when setting the cookie
    if raw.lower().startswith("datadome="):
        raw = raw[len("datadome="):]
    # Strip any surrounding semicolons
    raw = raw.strip("; ")
    return raw


def _normalize_cookies(lines: list[str]) -> list[str]:
    return [_normalize_cookie(l) for l in lines if l.strip()]


_PROXY_RE = re.compile(
    r"^(https?://|socks[45]://)?([^:@/\s]+:[^:@/\s]+@)?[^:@/\s]+:\d{1,5}$",
    re.IGNORECASE,
)


def _validate_proxy(p: str) -> bool:
    return bool(_PROXY_RE.match(p.strip()))


def _mask_proxy(proxy: str) -> str:
    """http://user:PASS@host:port → http://user:****@host:port"""
    if "@" not in proxy:
        return proxy
    try:
        parts = proxy.split("@", 1)
        creds = parts[0].split("://", 1)
        if len(creds) == 2:
            user_pass = creds[1].split(":", 1)
            if len(user_pass) == 2:
                return f"{creds[0]}://{user_pass[0]}:****@{parts[1]}"
    except Exception:
        pass
    return proxy


def _as_download(lines: list[str]) -> bytes:
    return "\n".join(lines).encode("utf-8")


# ── Page header ───────────────────────────────────────────────
st.markdown("## 🍪 CODM — Cookies & Proxy Pool")
st.markdown(
    "Manage DataDome cookies and proxy pool for the CODM checker. "
    "Changes are stored in **Upstash Redis** and take effect immediately — "
    "no Railway redeployment required."
)
st.divider()

tab_cookies, tab_proxies, tab_help = st.tabs(
    ["🍪 DataDome Cookies", "🔀 Proxy Pool", "📖 Help"]
)


# ══════════════════════════════════════════════════════════════
#  TAB 1 — DataDome Cookies
# ══════════════════════════════════════════════════════════════
with tab_cookies:

    # ── Fetch ─────────────────────────────────────────────────
    with st.spinner("Loading cookies from Redis…"):
        try:
            data           = get("/api/codm/cookies")
            raw_cookies    = data.get("cookies", [])
            source: str    = data.get("source", "unknown")
            count: int     = data.get("count", 0)
            last_updated   = data.get("last_updated", "")
        except Exception as e:
            st.error(f"❌ Failed to fetch cookies: {e}")
            raw_cookies, source, count, last_updated = [], "error", 0, ""

    # ── Metrics row ───────────────────────────────────────────
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("🍪 Pool Size",   count)
    col2.metric("📍 Source",      "Redis" if source == "redis" else ("Env fallback" if source == "env" else source))
    col3.metric("🏥 Health",      _health_badge(count))
    col4.metric("🕐 Last Saved",  last_updated if last_updated else "—")

    # ── Duplicate detection ───────────────────────────────────
    dupes = len(raw_cookies) - len(set(raw_cookies))
    if dupes > 0:
        st.warning(
            f"⚠️ **{dupes} duplicate cookie(s) detected** in the pool. "
            "Click **Dedup Pool** below to clean them up."
        )
        if st.button("🧹 Dedup Pool", key="dedup_cookies"):
            deduped = list(dict.fromkeys(raw_cookies))   # preserve order
            try:
                post("/api/codm/cookies", {"cookies": deduped})
                st.success(f"✅ Pool deduped — {len(raw_cookies)} → {len(deduped)} cookies.")
                st.rerun()
            except Exception as e:
                st.error(f"❌ {e}")

    st.markdown("---")

    # ── Current pool display ──────────────────────────────────
    if raw_cookies:
        head_col, dl_col = st.columns([8, 2])
        head_col.markdown(f"**Stored cookies ({len(raw_cookies)}):**")
        dl_col.download_button(
            label="⬇️ Download .txt",
            data=_as_download(raw_cookies),
            file_name="codm_cookies.txt",
            mime="text/plain",
            use_container_width=True,
        )

        for i, cookie in enumerate(raw_cookies, 1):
            # Show first 40 + last 10 chars — enough to verify identity without exposing full value
            display = cookie if len(cookie) <= 60 else f"{cookie[:40]}…{cookie[-10:]}"
            col_a, col_b = st.columns([11, 1])
            col_a.code(f"{i:>2}. {display}", language=None)
            if col_b.button("🗑️", key=f"del_cookie_{i}", help="Remove this cookie"):
                updated = [c for j, c in enumerate(raw_cookies, 1) if j != i]
                try:
                    if updated:
                        post("/api/codm/cookies", {"cookies": updated})
                        st.success(f"✅ Cookie #{i} removed. Pool now has {len(updated)}.")
                    else:
                        delete("/api/codm/cookies")
                        st.success("✅ Last cookie removed. Pool is now empty.")
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ Failed to remove: {e}")
    else:
        st.info(
            "ℹ️ No cookies in Redis. The backend will fall back to the "
            "`CODM_COOKIES` environment variable on Railway if set."
        )

    st.markdown("---")

    # ── Add / Replace ─────────────────────────────────────────
    st.markdown("### ➕ Add / Replace Cookies")
    st.markdown(
        "Paste your fresh DataDome cookies — **one per line**. "
        "Both `datadome=VALUE` and raw `VALUE` formats are accepted — "
        "the prefix is stripped automatically before saving."
    )

    new_cookies_raw = st.text_area(
        "DataDome Cookies (one per line)",
        height=180,
        placeholder=(
            "datadome=ABC123...xyz\n"
            "DEF456...abc\n"
            "# Lines starting with # are ignored"
        ),
        key="cookie_input",
    )

    # Live preview of what will actually be saved
    preview_lines = [
        _normalize_cookie(l)
        for l in new_cookies_raw.splitlines()
        if l.strip() and not l.strip().startswith("#")
    ]
    if preview_lines:
        st.caption(f"📋 {len(preview_lines)} valid line(s) ready to save.")

    col_replace, col_append, col_clear = st.columns([2, 2, 1])

    with col_replace:
        if st.button("💾 Replace All", type="primary", use_container_width=True):
            lines = preview_lines
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
            lines = preview_lines
            if not lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    existing = set(raw_cookies)
                    new_only = [l for l in lines if l not in existing]
                    merged   = raw_cookies + new_only
                    res = post("/api/codm/cookies", {"cookies": merged})
                    st.success(
                        res.get("message",
                            f"✅ Added {len(new_only)} new cookie(s) "
                            f"({len(lines) - len(new_only)} duplicate(s) skipped). "
                            f"Pool now has {len(merged)}."
                        )
                    )
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

    # ── Upload .txt file ──────────────────────────────────────
    st.markdown("---")
    st.markdown("### 📁 Upload Cookie File (.txt)")
    st.caption("Each non-empty line is treated as one cookie. Both `datadome=VALUE` and raw values are accepted.")

    uploaded = st.file_uploader(
        "Upload cookie .txt file",
        type=["txt"],
        help="Each non-empty line will be normalized and added.",
    )

    if uploaded is not None:
        raw_content = uploaded.read().decode("utf-8", errors="ignore")
        file_lines  = _normalize_cookies([
            l for l in raw_content.splitlines()
            if l.strip() and not l.strip().startswith("#")
        ])
        if file_lines:
            existing_set = set(raw_cookies)
            dupes_in_file = [l for l in file_lines if l in existing_set]
            new_in_file   = [l for l in file_lines if l not in existing_set]

            st.markdown(f"**Preview — {len(file_lines)} line(s) found:**")
            preview_text = "\n".join(
                f"{i:>2}. {l[:70]}{'…' if len(l) > 70 else ''}"
                for i, l in enumerate(file_lines[:10], 1)
            )
            if len(file_lines) > 10:
                preview_text += f"\n… and {len(file_lines) - 10} more"
            st.code(preview_text, language=None)

            if dupes_in_file:
                st.caption(f"ℹ️ {len(dupes_in_file)} line(s) already in pool will be skipped on Append.")

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
                        merged = raw_cookies + new_in_file
                        res = post("/api/codm/cookies", {"cookies": merged})
                        st.success(
                            res.get("message",
                                f"✅ Added {len(new_in_file)} new cookie(s) "
                                f"({len(dupes_in_file)} duplicate(s) skipped). "
                                f"Pool now has {len(merged)}."
                            )
                        )
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
        else:
            st.warning("⚠️ File appears empty or contains no valid lines.")


# ══════════════════════════════════════════════════════════════
#  TAB 2 — Proxy Pool
# ══════════════════════════════════════════════════════════════
with tab_proxies:

    # ── Fetch ─────────────────────────────────────────────────
    with st.spinner("Loading proxies from Redis…"):
        try:
            pdata           = get("/api/codm/proxies")
            current_proxies = pdata.get("proxies", [])
            pcount: int     = pdata.get("count", 0)
        except Exception as e:
            st.error(f"❌ Failed to fetch proxies: {e}")
            current_proxies, pcount = [], 0

    # ── Metrics row ───────────────────────────────────────────
    col1, col2, col3 = st.columns(3)
    col1.metric("🔀 Pool Size",  pcount)
    col2.metric("🏥 Health",     _health_badge(pcount, low_threshold=2))
    col3.metric("🔄 Routing",    "Via proxy pool" if pcount > 0 else "Direct connection (no proxies)")

    # ── Duplicate detection ───────────────────────────────────
    pdupes = len(current_proxies) - len(set(current_proxies))
    if pdupes > 0:
        st.warning(f"⚠️ {pdupes} duplicate proxy(ies) detected.")
        if st.button("🧹 Dedup Proxy Pool", key="dedup_proxies"):
            deduped = list(dict.fromkeys(current_proxies))
            try:
                post("/api/codm/proxies", {"proxies": deduped})
                st.success(f"✅ Pool deduped — {len(current_proxies)} → {len(deduped)} proxies.")
                st.rerun()
            except Exception as e:
                st.error(f"❌ {e}")

    st.markdown("---")

    # ── Current pool display ──────────────────────────────────
    if current_proxies:
        head_col, dl_col = st.columns([8, 2])
        head_col.markdown(f"**Stored proxies ({len(current_proxies)}):**")
        dl_col.download_button(
            label="⬇️ Download .txt",
            data=_as_download(current_proxies),
            file_name="codm_proxies.txt",
            mime="text/plain",
            use_container_width=True,
        )

        for i, proxy in enumerate(current_proxies, 1):
            display   = _mask_proxy(proxy)
            is_valid  = _validate_proxy(proxy)
            status    = "✅" if is_valid else "⚠️ bad format"
            col_a, col_b = st.columns([11, 1])
            col_a.code(f"{i:>2}. {display}  {status}", language=None)
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
                    st.error(f"❌ Failed to remove: {e}")
    else:
        st.info("ℹ️ No proxies in pool. The backend will use a direct connection.")

    st.markdown("---")

    # ── Add / Replace proxies ─────────────────────────────────
    st.markdown("### ➕ Add / Replace Proxies")
    st.markdown(
        "**Supported formats (one per line):**\n"
        "```\n"
        "http://user:pass@host:port\n"
        "http://host:port\n"
        "host:port               ← http:// assumed\n"
        "socks5://host:port\n"
        "```"
    )

    new_proxies_raw = st.text_area(
        "Proxies (one per line)",
        height=160,
        placeholder=(
            "http://user:pass@192.168.1.1:8080\n"
            "http://proxy.example.com:3128\n"
            "socks5://user:pass@proxy3.example.com:1080"
        ),
        key="proxy_input",
    )

    # Live validation preview
    proxy_lines = [
        l.strip()
        for l in new_proxies_raw.splitlines()
        if l.strip() and not l.strip().startswith("#")
    ]
    valid_proxies   = [p for p in proxy_lines if _validate_proxy(p)]
    invalid_proxies = [p for p in proxy_lines if not _validate_proxy(p)]

    if proxy_lines:
        st.caption(
            f"📋 {len(valid_proxies)} valid  |  "
            f"{'⚠️ ' + str(len(invalid_proxies)) + ' invalid (will be skipped)' if invalid_proxies else '✅ all valid'}"
        )
        if invalid_proxies:
            with st.expander("⚠️ Invalid proxy lines (will be skipped)", expanded=False):
                for p in invalid_proxies:
                    st.code(p, language=None)

    col_preplace, col_pappend, col_pclear = st.columns([2, 2, 1])

    with col_preplace:
        if st.button("💾 Replace All Proxies", type="primary", use_container_width=True):
            if not valid_proxies:
                st.warning("⚠️ No valid proxy lines found.")
            else:
                try:
                    res = post("/api/codm/proxies", {"proxies": valid_proxies})
                    st.success(res.get("message", f"✅ {len(valid_proxies)} proxy(ies) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_pappend:
        if st.button("➕ Append Proxies", use_container_width=True):
            if not valid_proxies:
                st.warning("⚠️ No valid proxy lines found.")
            else:
                try:
                    existing_set = set(current_proxies)
                    new_only = [p for p in valid_proxies if p not in existing_set]
                    merged   = current_proxies + new_only
                    res = post("/api/codm/proxies", {"proxies": merged})
                    st.success(
                        res.get("message",
                            f"✅ Added {len(new_only)} proxy(ies) "
                            f"({len(valid_proxies) - len(new_only)} duplicate(s) skipped). "
                            f"Pool now has {len(merged)}."
                        )
                    )
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")

    with col_pclear:
        if st.button("🗑️ Clear All", use_container_width=True):
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
    st.markdown("### 📁 Upload Proxy File (.txt)")
    uploaded_proxy = st.file_uploader(
        "Upload proxy file (.txt)",
        type=["txt"],
        key="proxy_file",
        help="Each non-empty line = one proxy. Invalid formats are skipped.",
    )
    if uploaded_proxy is not None:
        pcontent    = uploaded_proxy.read().decode("utf-8", errors="ignore")
        all_plines  = [l.strip() for l in pcontent.splitlines() if l.strip() and not l.strip().startswith("#")]
        pfile_valid = [p for p in all_plines if _validate_proxy(p)]
        pfile_bad   = [p for p in all_plines if not _validate_proxy(p)]

        if pfile_valid:
            st.markdown(f"**Preview — {len(pfile_valid)} valid proxy(ies):**")
            ppreview = "\n".join(
                f"{i:>2}. {_mask_proxy(l)}" for i, l in enumerate(pfile_valid[:8], 1)
            )
            if len(pfile_valid) > 8:
                ppreview += f"\n… and {len(pfile_valid) - 8} more"
            st.code(ppreview, language=None)

            if pfile_bad:
                st.caption(f"⚠️ {len(pfile_bad)} invalid line(s) in file will be skipped.")

            if st.button("💾 Replace Pool with File", key="save_proxy_file", type="primary"):
                try:
                    res = post("/api/codm/proxies", {"proxies": pfile_valid})
                    st.success(res.get("message", f"✅ {len(pfile_valid)} proxy(ies) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
        else:
            st.warning("⚠️ File appears empty or has no valid proxy lines.")


# ══════════════════════════════════════════════════════════════
#  TAB 3 — Help
# ══════════════════════════════════════════════════════════════
with tab_help:
    st.markdown("### 📖 How It Works")
    st.markdown("""
#### 🍪 DataDome Cookies
DataDome is the bot-detection system Garena uses. Without a valid DataDome cookie
the backend gets blocked (HTTP 403). These cookies expire, so you need to refresh
them periodically.

**How to get fresh cookies:**
1. Open `fresh_cookie.txt` from your local CODM Python script.
2. Each line starting with `datadome=` is a valid cookie.
3. Paste them here or upload the file — the prefix is stripped automatically.

**Cookie priority:**
```
Redis (codm:cookies)  →  Railway env var CODM_COOKIES  →  no cookie (likely blocked)
```

**Rotation:** The backend picks one cookie at random per request, spreading load
across your cookie pool and reducing ban risk.

---

#### 🔀 Proxy Pool
Proxies route Garena API traffic through different IPs. This helps when:
- Your Railway server IP gets rate-limited or blocked by DataDome.
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

> 💡 **Tip:** Free proxies are unreliable. Use paid residential proxies for best
> results with Garena's DataDome protection.

---

#### 🔄 Refresh Schedule (Recommendation)
| Cookie age | Action |
|---|---|
| < 6 hours  | ✅ Still fresh, no action needed |
| 6–24 hours | ⚠️ May work, but consider refreshing |
| > 24 hours | ❌ Likely expired — refresh ASAP |

Replace cookies whenever you see consistent `403` or `blocked` errors in your
CODM checker logs.

---

#### 🏥 Health Badges
| Badge | Meaning |
|---|---|
| 🔴 Empty | No cookies/proxies in pool |
| 🟡 Low   | Less than 3 cookies or 2 proxies |
| 🟢 Good  | Pool has enough entries |
""")
