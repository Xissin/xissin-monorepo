# ============================================================
#  admin/pages/15_CODM_Cookies.py  —  v5
#  Manage DataDome cookie pool and proxy pool for CODM checker.
#
#  v5 NEW: 🧪 Health Check tab
#    - "Test All Cookies" — batch tests every cookie from Railway's
#      own IP via the new /api/codm/test-cookies backend endpoint.
#      Shows ✅/❌, latency, reason. Auto-remove dead cookies option.
#    - "Test All Proxies" — same for proxy pool.
#    - Per-item test buttons in paginated list view.
#    - Summary metrics: Good / Dead / Untested counts.
#
#  v4 features kept:
#    - Paginated list view, bulk text view for large pools
#    - Dedup detection, danger zone, upload .txt file
#    - Append / Replace / Clear All
# ============================================================

import re
import time
import streamlit as st
from utils.api import get, post, delete, _request, TIMEOUT_HEAVY

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

tab_cookies, tab_proxies, tab_health, tab_help = st.tabs(
    ["🍪 DataDome Cookies", "🔀 Proxy Pool", "🧪 Health Check", "📖 Help"]
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

            ck_results = st.session_state.get("ck_test_results", {})
            for i, cookie in page_items:
                display = _short_cookie(cookie)
                result  = ck_results.get(cookie)
                # Status badge from previous test run
                if result is not None:
                    badge = "✅" if result["ok"] else "❌"
                    latency_str = f" {result['latency_ms']}ms" if result.get("latency_ms") else ""
                    detail_str  = f" — {result['detail']}" if result.get("detail") else ""
                    label = f"{i:>3}. {display}  {badge}{latency_str}{detail_str}"
                else:
                    label = f"{i:>3}. {display}"

                col_a, col_test, col_del = st.columns([9, 1, 1])
                col_a.code(label, language=None)

                if col_test.button("🔍", key=f"ck_test_{i}", help="Test this cookie now"):
                    with st.spinner(f"Testing cookie #{i}…"):
                        try:
                            res = post("/api/codm/test-cookie", {"cookie": cookie}, timeout=20)
                            ck_results[cookie] = res
                            st.session_state["ck_test_results"] = ck_results
                            if res.get("ok"):
                                st.success(f"✅ Cookie #{i}: {res.get('detail', 'Valid')}")
                            else:
                                st.error(f"❌ Cookie #{i}: {res.get('detail', 'Failed')}")
                        except Exception as e:
                            st.error(f"❌ Test error: {e}")
                    st.rerun()

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

            px_results = st.session_state.get("px_test_results", {})
            for i, proxy in ppage_items:
                display = _mask_proxy(proxy)
                result  = px_results.get(proxy)
                is_valid = _validate_proxy(proxy)
                fmt_badge = "✅" if is_valid else "⚠️ bad format"
                if result is not None:
                    test_badge  = "✅" if result["ok"] else "❌"
                    latency_str = f" {result['latency_ms']}ms" if result.get("latency_ms") else ""
                    label = f"{i:>3}. {display}  {test_badge}{latency_str}"
                else:
                    label = f"{i:>3}. {display}  {fmt_badge}"

                col_a, col_test, col_del = st.columns([9, 1, 1])
                col_a.code(label, language=None)
                if col_test.button("🔍", key=f"px_test_{i}", help="Test this proxy now"):
                    with st.spinner(f"Testing proxy #{i}…"):
                        try:
                            res = post("/api/codm/test-proxy", {"proxy": proxy}, timeout=20)
                            px_results[proxy] = res
                            st.session_state["px_test_results"] = px_results
                            if res.get("ok"):
                                st.success(f"✅ Proxy #{i}: {res.get('detail', 'Alive')}")
                            else:
                                st.error(f"❌ Proxy #{i}: {res.get('detail', 'Dead')}")
                        except Exception as e:
                            st.error(f"❌ Test error: {e}")
                    st.rerun()
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
#  TAB 3 — 🧪 Health Check  (NEW v5)
# ══════════════════════════════════════════════════════════════
with tab_health:
    st.markdown("### 🧪 Health Check — Cookies & Proxies")
    st.markdown(
        "Tests run **from Railway's server IP** — the exact same conditions as your CODM checker. "
        "Results are cached in this session. Refresh the page or click **Clear Results** to reset."
    )
    st.info(
        "💡 **How it works:**\n"
        "- **Cookie test**: Makes a real Garena prelogin request with the cookie. "
        "`200` = DataDome bypassed ✅. `403` = blocked/expired ❌.\n"
        "- **Proxy test**: Routes a Garena request through the proxy. "
        "Any HTTP response = proxy alive ✅. Timeout/refused = dead ❌."
    )

    # ── Fetch current pools ───────────────────────────────────
    try:
        ck_data  = get("/api/codm/cookies")
        hc_cookies = ck_data.get("cookies", [])
    except Exception as e:
        st.error(f"❌ Could not load cookies: {e}")
        hc_cookies = []

    try:
        px_data  = get("/api/codm/proxies")
        hc_proxies = px_data.get("proxies", [])
    except Exception as e:
        st.error(f"❌ Could not load proxies: {e}")
        hc_proxies = []

    # ── Session state for results ─────────────────────────────
    if "hc_cookie_results" not in st.session_state:
        st.session_state["hc_cookie_results"] = {}   # cookie → result dict
    if "hc_proxy_results" not in st.session_state:
        st.session_state["hc_proxy_results"]  = {}   # proxy  → result dict

    ck_res = st.session_state["hc_cookie_results"]
    px_res = st.session_state["hc_proxy_results"]

    col_clear1, col_clear2 = st.columns([1, 5])
    if col_clear1.button("🗑️ Clear Results", key="hc_clear_results"):
        st.session_state["hc_cookie_results"] = {}
        st.session_state["hc_proxy_results"]  = {}
        ck_res, px_res = {}, {}
        st.success("✅ Results cleared.")

    st.divider()

    # ──────────────────────────────────────────────────────────
    #  COOKIES SECTION
    # ──────────────────────────────────────────────────────────
    st.markdown("#### 🍪 DataDome Cookies")

    if not hc_cookies:
        st.warning("⚠️ No cookies in pool. Add cookies in the **DataDome Cookies** tab first.")
    else:
        # Summary metrics
        tested   = [c for c in hc_cookies if c in ck_res]
        good     = [c for c in tested if ck_res[c]["ok"]]
        dead     = [c for c in tested if not ck_res[c]["ok"]]
        untested = [c for c in hc_cookies if c not in ck_res]

        mc1, mc2, mc3, mc4 = st.columns(4)
        mc1.metric("🍪 Total",    len(hc_cookies))
        mc2.metric("✅ Good",     len(good),     delta=f"+{len(good)}"    if good    else None)
        mc3.metric("❌ Dead",     len(dead),     delta=f"-{len(dead)}"    if dead    else None, delta_color="inverse")
        mc4.metric("⏳ Untested", len(untested))

        # Action row
        ca1, ca2, ca3 = st.columns([2, 2, 2])

        with ca1:
            if st.button("▶️ Test All Cookies", type="primary",
                         use_container_width=True, key="hc_test_all_ck"):
                progress = st.progress(0, text="Starting cookie tests…")
                status   = st.empty()
                total    = len(hc_cookies)
                done     = 0
                errors   = 0

                # Call batch endpoint — concurrent on Railway side
                try:
                    with st.spinner(f"Testing {total} cookie(s) via Railway backend…"):
                        results = _request(
                            "POST", "/api/codm/test-cookies",
                            body={"cookies": hc_cookies},
                            timeout=max(60, total * 3),  # generous timeout for large pools
                        )
                    for r in results:
                        ck_res[r["cookie"]] = r
                        done += 1
                        if not r["ok"]:
                            errors += 1
                        progress.progress(done / total,
                                          text=f"Tested {done}/{total} — "
                                               f"✅ {done - errors} good  ❌ {errors} dead")
                    st.session_state["hc_cookie_results"] = ck_res
                    progress.progress(1.0, text=f"Done! ✅ {done - errors} good  ❌ {errors} dead")
                    st.success(f"✅ Tested {total} cookie(s): **{done - errors} valid**, **{errors} dead**.")
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ Batch test failed: {e}")

        with ca2:
            dead_list = [c for c in hc_cookies if c in ck_res and not ck_res[c]["ok"]]
            if dead_list:
                if st.button(f"🗑️ Remove {len(dead_list)} Dead Cookie(s)",
                             use_container_width=True, key="hc_remove_dead_ck"):
                    dead_set = set(dead_list)
                    survivors = [c for c in hc_cookies if c not in dead_set]
                    try:
                        if survivors:
                            post("/api/codm/cookies", {"cookies": survivors})
                            st.success(f"✅ Removed {len(dead_list)} dead cookie(s). Pool = {len(survivors)}.")
                        else:
                            delete("/api/codm/cookies")
                            st.success("✅ All cookies were dead — pool cleared.")
                        # Clear dead from results cache
                        for c in dead_list:
                            ck_res.pop(c, None)
                        st.session_state["hc_cookie_results"] = ck_res
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
            else:
                st.button("🗑️ Remove Dead Cookies", use_container_width=True,
                          key="hc_remove_dead_ck_disabled", disabled=True)

        with ca3:
            if tested:
                good_pct = int(len(good) / len(tested) * 100) if tested else 0
                st.metric("🏥 Pass Rate", f"{good_pct}%", help=f"{len(good)}/{len(tested)} tested cookies passed")

        # ── Results table ─────────────────────────────────────
        st.markdown("---")
        if ck_res:
            # Sort: dead first (so admin sees problems immediately), then by latency
            sorted_cookies = sorted(
                hc_cookies,
                key=lambda c: (ck_res.get(c, {}).get("ok", True),
                               ck_res.get(c, {}).get("latency_ms", 0))
            )
            for idx, cookie in enumerate(sorted_cookies):
                display = _short_cookie(cookie, 40)
                result  = ck_res.get(cookie)
                if result is None:
                    icon   = "⏳"
                    badge  = "Not tested"
                    color  = "grey"
                elif result["ok"]:
                    icon   = "✅"
                    latency = result.get("latency_ms", 0)
                    badge  = f"Valid — {latency}ms"
                    color  = "green"
                else:
                    icon   = "❌"
                    badge  = result.get("detail", "Failed")[:80]
                    color  = "red"

                row_a, row_b = st.columns([9, 1])
                row_a.markdown(
                    f"`{icon}` **{display}**  "
                    f"<span style='color:{color};font-size:11px'>{badge}</span>",
                    unsafe_allow_html=True,
                )
                if row_b.button("🔍", key=f"hc_ck_retest_{idx}", help="Re-test"):
                    with st.spinner("Testing…"):
                        try:
                            r = post("/api/codm/test-cookie", {"cookie": cookie}, timeout=20)
                            ck_res[cookie] = r
                            st.session_state["hc_cookie_results"] = ck_res
                            if r.get("ok"):
                                st.success(f"✅ {r.get('detail', 'Valid')}")
                            else:
                                st.error(f"❌ {r.get('detail', 'Failed')}")
                        except Exception as e:
                            st.error(f"❌ {e}")
                    st.rerun()
        else:
            st.caption("No results yet. Click **▶️ Test All Cookies** to start.")

    st.divider()

    # ──────────────────────────────────────────────────────────
    #  PROXIES SECTION
    # ──────────────────────────────────────────────────────────
    st.markdown("#### 🔀 Proxy Pool")

    if not hc_proxies:
        st.warning("⚠️ No proxies in pool. Add proxies in the **Proxy Pool** tab first.")
    else:
        tested_px   = [p for p in hc_proxies if p in px_res]
        good_px     = [p for p in tested_px if px_res[p]["ok"]]
        dead_px     = [p for p in tested_px if not px_res[p]["ok"]]
        untested_px = [p for p in hc_proxies if p not in px_res]

        mp1, mp2, mp3, mp4 = st.columns(4)
        mp1.metric("🔀 Total",    len(hc_proxies))
        mp2.metric("✅ Alive",    len(good_px), delta=f"+{len(good_px)}" if good_px else None)
        mp3.metric("❌ Dead",     len(dead_px), delta=f"-{len(dead_px)}" if dead_px else None, delta_color="inverse")
        mp4.metric("⏳ Untested", len(untested_px))

        pa1, pa2, pa3 = st.columns([2, 2, 2])

        with pa1:
            if st.button("▶️ Test All Proxies", type="primary",
                         use_container_width=True, key="hc_test_all_px"):
                total  = len(hc_proxies)
                errors = 0
                progress = st.progress(0, text="Starting proxy tests…")
                try:
                    with st.spinner(f"Testing {total} proxy(ies) via Railway backend…"):
                        results = _request(
                            "POST", "/api/codm/test-proxies",
                            body={"proxies": hc_proxies},
                            timeout=max(60, total * 3),
                        )
                    done = 0
                    for r in results:
                        px_res[r["proxy"]] = r
                        done += 1
                        if not r["ok"]:
                            errors += 1
                        progress.progress(done / total,
                                          text=f"Tested {done}/{total} — "
                                               f"✅ {done - errors} alive  ❌ {errors} dead")
                    st.session_state["hc_proxy_results"] = px_res
                    progress.progress(1.0, text=f"Done! ✅ {done - errors} alive  ❌ {errors} dead")
                    st.success(f"✅ Tested {total} proxy(ies): **{done - errors} alive**, **{errors} dead**.")
                    st.rerun()
                except Exception as e:
                    st.error(f"❌ Batch test failed: {e}")

        with pa2:
            dead_px_list = [p for p in hc_proxies if p in px_res and not px_res[p]["ok"]]
            if dead_px_list:
                if st.button(f"🗑️ Remove {len(dead_px_list)} Dead Proxy(ies)",
                             use_container_width=True, key="hc_remove_dead_px"):
                    dead_set   = set(dead_px_list)
                    survivors  = [p for p in hc_proxies if p not in dead_set]
                    try:
                        if survivors:
                            post("/api/codm/proxies", {"proxies": survivors})
                            st.success(f"✅ Removed {len(dead_px_list)} dead proxy(ies). Pool = {len(survivors)}.")
                        else:
                            delete("/api/codm/proxies")
                            st.success("✅ All proxies were dead — pool cleared.")
                        for p in dead_px_list:
                            px_res.pop(p, None)
                        st.session_state["hc_proxy_results"] = px_res
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
            else:
                st.button("🗑️ Remove Dead Proxies", use_container_width=True,
                          key="hc_remove_dead_px_disabled", disabled=True)

        with pa3:
            if tested_px:
                good_pct = int(len(good_px) / len(tested_px) * 100)
                avg_lat  = (sum(px_res[p].get("latency_ms", 0) for p in good_px) // max(len(good_px), 1))
                st.metric("⚡ Avg Latency", f"{avg_lat}ms",
                          help=f"Average latency across {len(good_px)} live proxy(ies)")

        # ── Results table ─────────────────────────────────────
        st.markdown("---")
        if px_res:
            sorted_proxies = sorted(
                hc_proxies,
                key=lambda p: (px_res.get(p, {}).get("ok", True),
                               px_res.get(p, {}).get("latency_ms", 0))
            )
            for idx, proxy in enumerate(sorted_proxies):
                display = _mask_proxy(proxy)
                result  = px_res.get(proxy)
                if result is None:
                    icon, badge, color = "⏳", "Not tested", "grey"
                elif result["ok"]:
                    latency = result.get("latency_ms", 0)
                    icon    = "✅"
                    badge   = f"Alive — {latency}ms"
                    color   = "green"
                else:
                    icon    = "❌"
                    badge   = result.get("detail", "Dead")[:80]
                    color   = "red"

                row_a, row_b = st.columns([9, 1])
                row_a.markdown(
                    f"`{icon}` **{display}**  "
                    f"<span style='color:{color};font-size:11px'>{badge}</span>",
                    unsafe_allow_html=True,
                )
                if row_b.button("🔍", key=f"hc_px_retest_{idx}", help="Re-test"):
                    with st.spinner("Testing…"):
                        try:
                            r = post("/api/codm/test-proxy", {"proxy": proxy}, timeout=20)
                            px_res[proxy] = r
                            st.session_state["hc_proxy_results"] = px_res
                            if r.get("ok"):
                                st.success(f"✅ {r.get('detail', 'Alive')}")
                            else:
                                st.error(f"❌ {r.get('detail', 'Dead')}")
                        except Exception as e:
                            st.error(f"❌ {e}")
                    st.rerun()
        else:
            st.caption("No results yet. Click **▶️ Test All Proxies** to start.")


# ══════════════════════════════════════════════════════════════
#  TAB 4 — Help
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

**Priority per request:**
```
User-provided proxy (Flutter)  →  Redis pool (random)  →  direct connection
```

---

#### 🧪 Health Check
- Tests run **from Railway's IP** — not your browser. Results reflect what the CODM checker actually experiences.
- **Cookie test**: 200 = DataDome bypassed ✅. 403 = expired/blocked ❌.
- **Proxy test**: Any HTTP response = alive ✅. Timeout/refused = dead ❌.
- Use **▶️ Test All** then **🗑️ Remove Dead** to clean your pool in two clicks.
- Results are cached in your current browser session — click **🗑️ Clear Results** to reset.

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
- Health checks are **concurrent on the backend** — testing 50 cookies takes ~10–15s total, not 50×10s.
""")
