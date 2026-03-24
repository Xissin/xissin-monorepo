# ============================================================
#  admin/pages/15_CODM_Cookies.py  —  v6
#  Manage DataDome cookie pool and proxy pool for CODM checker.
#  Testing moved to Termux — health check tab removed.
#
#  Features:
#    - Paginated list view, bulk text view for large pools
#    - Dedup detection, danger zone, upload .txt file
#    - Append / Replace / Clear All
# ============================================================

import re
import streamlit as st
from utils.api import get, post, delete

st.set_page_config(
    page_title="CODM Cookies & Proxies — Xissin Admin",
    page_icon="🍪",
    layout="wide",
)

if not st.session_state.get("authenticated"):
    st.error("🔒 Please log in from the main page.")
    st.stop()

# ── Constants ─────────────────────────────────────────────────
BULK_THRESHOLD = 50
PAGE_SIZE      = 30

# ── Helpers ───────────────────────────────────────────────────

def _health_badge(count, low_threshold=3):
    if count == 0:             return "🔴 Empty"
    if count < low_threshold:  return f"🟡 Low ({count})"
    return f"🟢 Good ({count})"


def _normalize_cookie(raw):
    raw = raw.strip()
    if raw.lower().startswith("datadome="):
        raw = raw[len("datadome="):]
    return raw.strip("; ")


def _normalize_cookies(lines):
    return [_normalize_cookie(l) for l in lines if l.strip()]


_PROXY_RE = re.compile(
    r"^(https?://|socks[45]://)?([^:@/\s]+:[^:@/\s]+@)?[^:@/\s]+:\d{1,5}$",
    re.IGNORECASE,
)


def _validate_proxy(p):
    return bool(_PROXY_RE.match(p.strip()))


def _mask_proxy(proxy):
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


def _as_download(lines):
    return "\n".join(lines).encode("utf-8")


def _bulk_text(lines, mask_fn=None):
    out = []
    for i, l in enumerate(lines, 1):
        display = mask_fn(l) if mask_fn else l
        out.append(f"{i:>4}. {display}")
    return "\n".join(out)


def _short_cookie(c, n=30):
    return f"{c[:n]}…{c[-8:]}" if len(c) > n + 10 else c


# ── Page header ───────────────────────────────────────────────
st.markdown("## 🍪 CODM — Cookies & Proxy Pool")
st.markdown(
    "Manage DataDome cookies and proxy pool for the CODM checker. "
    "Changes are stored in **Upstash Redis** and take effect immediately."
)
st.divider()

tab_cookies, tab_proxies, tab_help = st.tabs(
    ["🍪 DataDome Cookies", "🔀 Proxy Pool", "📖 Help"]
)


# ══════════════════════════════════════════════════════════════
#  TAB 1 — DataDome Cookies
# ══════════════════════════════════════════════════════════════
with tab_cookies:

    with st.spinner("Loading cookies…"):
        try:
            data         = get("/api/codm/cookies")
            raw_cookies  = data.get("cookies", [])
            source       = data.get("source", "unknown")
            count        = data.get("count", 0)
            last_updated = data.get("last_updated", "")
        except Exception as e:
            st.error(f"❌ Failed to fetch cookies: {e}")
            raw_cookies, source, count, last_updated = [], "error", 0, ""

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("🍪 Pool Size",  count)
    c2.metric("📍 Source",     "Redis" if source == "redis" else ("Env fallback" if source == "env" else source))
    c3.metric("🏥 Health",     _health_badge(count))
    c4.metric("🕐 Last Saved", last_updated or "—")

    st.markdown("---")
    with st.expander("☢️ **DANGER ZONE — Clear Entire Cookie Pool**", expanded=False):
        st.error(
            f"⚠️ This will **permanently delete all {count} DataDome cookie(s)** from Redis.\n\n"
            "**This action cannot be undone.**"
        )
        dz_warn, dz_btn = st.columns([3, 1])
        dz_warn.caption("Only do this for a full reset. Paste fresh cookies below after clearing.")
        if count == 0:
            dz_btn.info("Pool already empty.")
        else:
            if dz_btn.button("☢️ Clear ALL Cookies", type="primary",
                             use_container_width=True, key="ck_danger_clear"):
                if st.session_state.get("ck_danger_confirm"):
                    try:
                        delete("/api/codm/cookies")
                        st.success("✅ All DataDome cookies cleared.")
                        st.session_state["ck_danger_confirm"] = False
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
                else:
                    st.session_state["ck_danger_confirm"] = True
                    st.warning("⚠️ Click again to confirm.")

    st.markdown("---")
    dupes = len(raw_cookies) - len(set(raw_cookies))
    if dupes > 0:
        st.warning(f"⚠️ **{dupes} duplicate(s) detected.**")
        if st.button("🧹 Dedup Pool", key="ck_dedup"):
            deduped = list(dict.fromkeys(raw_cookies))
            try:
                post("/api/codm/cookies", {"cookies": deduped})
                st.success(f"✅ Deduped — {len(raw_cookies)} → {len(deduped)} cookies.")
                st.rerun()
            except Exception as e:
                st.error(f"❌ {e}")

    if raw_cookies:
        hc, dc = st.columns([8, 2])
        hc.markdown(f"**Stored cookies ({len(raw_cookies)}):**")
        dc.download_button(label="⬇️ Download .txt", data=_as_download(raw_cookies),
                           file_name="codm_cookies.txt", mime="text/plain",
                           use_container_width=True, key="ck_download")

        if count > BULK_THRESHOLD:
            st.info(f"ℹ️ Pool has **{count} cookies** — bulk view to prevent lag.")
            masked = [f"{c[:30]}…{c[-8:]}" if len(c) > 40 else c for c in raw_cookies]
            st.text_area("Cookie pool (read-only)", value=_bulk_text(masked),
                         height=300, disabled=True, key="ck_bulk_view")
        else:
            page_key = "ck_page"
            if page_key not in st.session_state:
                st.session_state[page_key] = 0
            total_pages = max(1, (len(raw_cookies) + PAGE_SIZE - 1) // PAGE_SIZE)
            page = max(0, min(st.session_state[page_key], total_pages - 1))
            start = page * PAGE_SIZE
            end   = min(start + PAGE_SIZE, len(raw_cookies))
            page_items = list(enumerate(raw_cookies, 1))[start:end]

            if total_pages > 1:
                pc1, pc2, pc3 = st.columns([1, 3, 1])
                if pc1.button("◀ Prev", key="ck_prev", disabled=page == 0):
                    st.session_state[page_key] = page - 1; st.rerun()
                pc2.caption(f"Page {page + 1} / {total_pages}  (rows {start+1}–{end})")
                if pc3.button("Next ▶", key="ck_next", disabled=page >= total_pages - 1):
                    st.session_state[page_key] = page + 1; st.rerun()

            for i, cookie in page_items:
                display = _short_cookie(cookie)
                label   = f"{i:>3}. {display}"

                col_a, col_del = st.columns([10, 1])
                col_a.code(label, language=None)

                if col_del.button("🗑️", key=f"ck_del_{i}", help="Remove this cookie"):
                    updated = [c for j, c in enumerate(raw_cookies, 1) if j != i]
                    try:
                        if updated:
                            post("/api/codm/cookies", {"cookies": updated})
                            st.success(f"✅ Cookie #{i} removed.")
                        else:
                            delete("/api/codm/cookies")
                            st.success("✅ Last cookie removed. Pool empty.")
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
    else:
        st.info("ℹ️ No cookies in Redis. Backend falls back to CODM_COOKIES env var.")

    # ── Add / Replace ─────────────────────────────────────────
    st.markdown("---")
    st.markdown("### ➕ Add / Replace Cookies")
    st.markdown("Paste fresh DataDome cookies — **one per line**. `datadome=VALUE` prefix stripped automatically.")

    new_cookies_raw = st.text_area(
        "DataDome Cookies (one per line)", height=200,
        placeholder="datadome=ABC123...xyz\nDEF456...abc",
        key="ck_input",
    )
    preview_lines = [_normalize_cookie(l) for l in new_cookies_raw.splitlines()
                     if l.strip() and not l.strip().startswith("#")]
    if preview_lines:
        st.caption(f"📋 **{len(preview_lines)}** valid line(s) ready to save.")

    col_replace, col_append, col_clear = st.columns([2, 2, 1])
    with col_replace:
        if st.button("💾 Replace All", type="primary", use_container_width=True, key="ck_replace"):
            if not preview_lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    res = post("/api/codm/cookies", {"cookies": preview_lines})
                    st.success(res.get("message", f"✅ {len(preview_lines)} cookie(s) saved."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
    with col_append:
        if st.button("➕ Append to Pool", use_container_width=True, key="ck_append"):
            if not preview_lines:
                st.warning("⚠️ No valid lines found.")
            else:
                try:
                    existing = set(raw_cookies)
                    new_only = [l for l in preview_lines if l not in existing]
                    merged   = raw_cookies + new_only
                    res = post("/api/codm/cookies", {"cookies": merged})
                    st.success(res.get("message",
                        f"✅ Added {len(new_only)} new cookie(s) "
                        f"({len(preview_lines) - len(new_only)} duplicate(s) skipped). Pool = {len(merged)}."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
    with col_clear:
        if st.button("🗑️ Clear All", use_container_width=True, key="ck_clear_small"):
            if st.session_state.get("ck_clear_confirm"):
                try:
                    delete("/api/codm/cookies")
                    st.success("✅ Cookie pool cleared.")
                    st.session_state["ck_clear_confirm"] = False
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
            else:
                st.session_state["ck_clear_confirm"] = True
                st.warning("⚠️ Click again to confirm.")

    st.markdown("---")
    st.markdown("### 📁 Upload Cookie File (.txt)")
    uploaded = st.file_uploader("Upload cookie .txt file", type=["txt"], key="ck_file_upload")
    if uploaded is not None:
        file_lines = _normalize_cookies([
            l for l in uploaded.read().decode("utf-8", errors="ignore").splitlines()
            if l.strip() and not l.strip().startswith("#")
        ])
        if file_lines:
            existing_set  = set(raw_cookies)
            new_in_file   = [l for l in file_lines if l not in existing_set]
            dupes_in_file = [l for l in file_lines if l in existing_set]
            st.success(f"📂 File loaded: **{len(file_lines)} cookie(s)**.")
            st.caption(f"🆕 New: **{len(new_in_file)}**   |   🔁 Already in pool: **{len(dupes_in_file)}**")
            col_sf, col_af = st.columns(2)
            with col_sf:
                if st.button("💾 Replace Pool with File", type="primary",
                             use_container_width=True, key="ck_file_replace"):
                    try:
                        res = post("/api/codm/cookies", {"cookies": file_lines})
                        st.success(res.get("message", f"✅ {len(file_lines)} cookie(s) saved."))
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
            with col_af:
                if st.button("➕ Append File to Pool", use_container_width=True, key="ck_file_append"):
                    try:
                        merged = raw_cookies + new_in_file
                        res = post("/api/codm/cookies", {"cookies": merged})
                        st.success(res.get("message",
                            f"✅ Added {len(new_in_file)} new. Pool = {len(merged)}."))
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
        else:
            st.warning("⚠️ File empty or no valid lines.")


# ══════════════════════════════════════════════════════════════
#  TAB 2 — Proxy Pool
# ══════════════════════════════════════════════════════════════
with tab_proxies:

    with st.spinner("Loading proxies…"):
        try:
            pdata           = get("/api/codm/proxies")
            current_proxies = pdata.get("proxies", [])
            pcount          = pdata.get("count", 0)
        except Exception as e:
            st.error(f"❌ Failed to fetch proxies: {e}")
            current_proxies, pcount = [], 0

    p1, p2, p3 = st.columns(3)
    p1.metric("🔀 Pool Size", pcount)
    p2.metric("🏥 Health",    _health_badge(pcount, low_threshold=2))
    p3.metric("🔄 Routing",   "Via proxy pool" if pcount > 0 else "Direct connection")

    st.markdown("---")
    with st.expander("☢️ **DANGER ZONE — Clear Entire Proxy Pool**", expanded=False):
        st.error(
            f"⚠️ This will **permanently delete all {pcount} proxy(ies)** from Redis.\n\n"
            "Backend falls back to direct connection. **Cannot be undone.**"
        )
        pz_warn, pz_btn = st.columns([3, 1])
        pz_warn.caption("Only do this for a full reset.")
        if pcount == 0:
            pz_btn.info("Pool already empty.")
        else:
            if pz_btn.button("☢️ Clear ALL Proxies", type="primary",
                             use_container_width=True, key="px_danger_clear"):
                if st.session_state.get("px_danger_confirm"):
                    try:
                        delete("/api/codm/proxies")
                        st.success("✅ All proxies cleared.")
                        st.session_state["px_danger_confirm"] = False
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
                else:
                    st.session_state["px_danger_confirm"] = True
                    st.warning("⚠️ Click again to confirm.")

    st.markdown("---")
    pdupes = len(current_proxies) - len(set(current_proxies))
    if pdupes > 0:
        st.warning(f"⚠️ {pdupes} duplicate proxy(ies) detected.")
        if st.button("🧹 Dedup Proxy Pool", key="px_dedup"):
            deduped = list(dict.fromkeys(current_proxies))
            try:
                post("/api/codm/proxies", {"proxies": deduped})
                st.success(f"✅ Deduped — {len(current_proxies)} → {len(deduped)} proxies.")
                st.rerun()
            except Exception as e:
                st.error(f"❌ {e}")

    if current_proxies:
        ph, pd = st.columns([8, 2])
        ph.markdown(f"**Stored proxies ({len(current_proxies)}):**")
        pd.download_button(label="⬇️ Download .txt", data=_as_download(current_proxies),
                           file_name="codm_proxies.txt", mime="text/plain",
                           use_container_width=True, key="px_download")

        if pcount > BULK_THRESHOLD:
            st.info(f"ℹ️ Pool has **{pcount} proxies** — bulk view to prevent lag.")
            st.text_area("Proxy pool (read-only)", value=_bulk_text(current_proxies, mask_fn=_mask_proxy),
                         height=300, disabled=True, key="px_bulk_view")
        else:
            ppage_key = "px_page"
            if ppage_key not in st.session_state:
                st.session_state[ppage_key] = 0
            ptotal_pages = max(1, (len(current_proxies) + PAGE_SIZE - 1) // PAGE_SIZE)
            ppage = max(0, min(st.session_state[ppage_key], ptotal_pages - 1))
            pstart = ppage * PAGE_SIZE
            pend   = min(pstart + PAGE_SIZE, len(current_proxies))
            ppage_items = list(enumerate(current_proxies, 1))[pstart:pend]

            if ptotal_pages > 1:
                pp1, pp2, pp3 = st.columns([1, 3, 1])
                if pp1.button("◀ Prev", key="px_prev", disabled=ppage == 0):
                    st.session_state[ppage_key] = ppage - 1; st.rerun()
                pp2.caption(f"Page {ppage + 1} / {ptotal_pages}  (rows {pstart+1}–{pend})")
                if pp3.button("Next ▶", key="px_next", disabled=ppage >= ptotal_pages - 1):
                    st.session_state[ppage_key] = ppage + 1; st.rerun()

            for i, proxy in ppage_items:
                display  = _mask_proxy(proxy)
                is_valid = _validate_proxy(proxy)
                fmt_badge = "✅" if is_valid else "⚠️ bad format"
                label    = f"{i:>3}. {display}  {fmt_badge}"

                col_a, col_del = st.columns([10, 1])
                col_a.code(label, language=None)

                if col_del.button("🗑️", key=f"px_del_{i}", help="Remove this proxy"):
                    updated = [p for j, p in enumerate(current_proxies, 1) if j != i]
                    try:
                        if updated:
                            post("/api/codm/proxies", {"proxies": updated})
                            st.success(f"✅ Proxy #{i} removed.")
                        else:
                            delete("/api/codm/proxies")
                            st.success("✅ Last proxy removed. Pool empty.")
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
    else:
        st.info("ℹ️ No proxies in pool. Backend will use direct connection.")

    st.markdown("---")
    st.markdown("### ➕ Add / Replace Proxies")
    st.markdown("**Supported formats (one per line):**\n```\nhttp://user:pass@host:port\nhttp://host:port\nhost:port\nsocks5://host:port\n```")

    new_proxies_raw = st.text_area("Proxies (one per line)", height=160,
                                   placeholder="http://user:pass@192.168.1.1:8080\nhost:port",
                                   key="px_input")
    proxy_lines     = [l.strip() for l in new_proxies_raw.splitlines()
                       if l.strip() and not l.strip().startswith("#")]
    valid_proxies   = [p for p in proxy_lines if _validate_proxy(p)]
    invalid_proxies = [p for p in proxy_lines if not _validate_proxy(p)]
    if proxy_lines:
        st.caption(f"📋 {len(valid_proxies)} valid  |  "
                   f"{'⚠️ ' + str(len(invalid_proxies)) + ' invalid (will be skipped)' if invalid_proxies else '✅ all valid'}")
        if invalid_proxies:
            with st.expander("⚠️ Invalid lines (will be skipped)"):
                for p in invalid_proxies:
                    st.code(p, language=None)

    col_preplace, col_pappend, col_pclear = st.columns([2, 2, 1])
    with col_preplace:
        if st.button("💾 Replace All Proxies", type="primary",
                     use_container_width=True, key="px_replace"):
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
        if st.button("➕ Append Proxies", use_container_width=True, key="px_append"):
            if not valid_proxies:
                st.warning("⚠️ No valid proxy lines found.")
            else:
                try:
                    existing_set = set(current_proxies)
                    new_only = [p for p in valid_proxies if p not in existing_set]
                    merged   = current_proxies + new_only
                    res = post("/api/codm/proxies", {"proxies": merged})
                    st.success(res.get("message",
                        f"✅ Added {len(new_only)} proxy(ies). Pool = {len(merged)}."))
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
    with col_pclear:
        if st.button("🗑️ Clear All", use_container_width=True, key="px_clear_small"):
            if st.session_state.get("px_clear_confirm"):
                try:
                    delete("/api/codm/proxies")
                    st.success("✅ Proxy pool cleared.")
                    st.session_state["px_clear_confirm"] = False
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ {e}")
            else:
                st.session_state["px_clear_confirm"] = True
                st.warning("⚠️ Click again to confirm.")

    st.markdown("---")
    st.markdown("### 📁 Upload Proxy File (.txt)")
    uploaded_proxy = st.file_uploader("Upload proxy file (.txt)", type=["txt"], key="px_file_upload")
    if uploaded_proxy is not None:
        pcontent   = uploaded_proxy.read().decode("utf-8", errors="ignore")
        all_plines = [l.strip() for l in pcontent.splitlines()
                      if l.strip() and not l.strip().startswith("#")]
        pfile_valid = [p for p in all_plines if _validate_proxy(p)]
        pfile_bad   = [p for p in all_plines if not _validate_proxy(p)]
        if pfile_valid:
            st.success(f"📂 File loaded: **{len(pfile_valid)} valid proxy(ies)**.")
            if pfile_bad:
                st.caption(f"⚠️ {len(pfile_bad)} invalid line(s) skipped.")
            if st.button("💾 Replace Pool with File", key="px_file_replace", type="primary"):
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
    st.markdown(f"""
#### 🍪 DataDome Cookies
DataDome is Garena's bot-detection system. Without a valid cookie the backend gets HTTP 403.
Cookies expire (usually within 6–24 hours), so refresh them periodically.

**How to get fresh cookies:**
1. Open `https://100082.connect.garena.com` in Chrome.
2. DevTools (F12) → Application → Cookies → copy the `datadome` value.
3. Paste here — the `datadome=` prefix is stripped automatically.

**How to test cookies (Termux):**
```bash
curl -s -o /dev/null -w "%{{http_code}}" \\
  "https://100082.connect.garena.com/api/prelogin?app_id=100082&account=test@test.com&format=json" \\
  -H "Cookie: datadome=YOUR_COOKIE_VALUE"
# 200 = valid ✅   403 = expired ❌
```

**Cookie priority:**
```
Redis (codm:cookies)  →  Railway env CODM_COOKIES  →  no cookie (likely blocked)
```
The backend picks a **random** cookie per request.

---

#### 🔀 Proxy Pool
Routes Garena traffic through different IPs to avoid rate-limits.

**Supported formats:**
```
http://user:pass@host:port     ← recommended
http://host:port
host:port                      ← http:// assumed
socks5://host:port
```

**How to test proxies (Termux):**
```bash
curl -s -o /dev/null -w "%{{http_code}}" \\
  --proxy "http://host:port" \\
  "https://100082.connect.garena.com/api/prelogin?app_id=100082&account=test@test.com&format=json"
# Any HTTP response = alive ✅   Connection error = dead ❌
```

**Priority per request:**
```
User-provided proxy (Flutter)  →  Redis pool (random)  →  direct connection
```

---

#### 🔄 Cookie Refresh Schedule
| Age | Action |
|---|---|
| < 6 hours  | ✅ Fresh |
| 6–24 hours | ⚠️ May work, consider refreshing |
| > 24 hours | ❌ Likely expired — refresh ASAP |

---

#### 🏥 Health Badges
| Badge | Meaning |
|---|---|
| 🔴 Empty | No entries in pool |
| 🟡 Low   | Less than 3 cookies / 2 proxies |
| 🟢 Good  | Pool has enough entries |

---

#### ⚡ Performance Notes
- Pools over **{BULK_THRESHOLD} items** use bulk text view to prevent browser lag.
""")
