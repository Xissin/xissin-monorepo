# ============================================================
#  admin/pages/15_CODM_Cookies.py  —  v4
#  Manage DataDome cookie pool and proxy pool for CODM checker.
#  Stored in Upstash Redis — no Railway redeployment needed.
#
#  v4 fixes:
#  - Fixed StreamlitDuplicateElementId: all buttons now have unique keys
#  - Fixed PC lag: pools > BULK_THRESHOLD items use a single text area
#    instead of rendering thousands of individual widgets
#  - Paginated per-item delete view (max PAGE_SIZE rows at a time)
#  - Danger zone clear-all buttons preserved with unique keys
# ============================================================

import re
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

# ── Constants ─────────────────────────────────────────────────
# If pool has more than this many items, skip per-row widgets
# and show a scrollable text area instead (prevents lag).
BULK_THRESHOLD = 50
PAGE_SIZE      = 30   # rows shown per page in paginated view

# ── Helpers ───────────────────────────────────────────────────

def _health_badge(count: int, low_threshold: int = 3) -> str:
    if count == 0:        return "🔴 Empty"
    if count < low_threshold: return f"🟡 Low ({count})"
    return f"🟢 Good ({count})"


def _normalize_cookie(raw: str) -> str:
    raw = raw.strip()
    if raw.lower().startswith("datadome="):
        raw = raw[len("datadome="):]
    return raw.strip("; ")


def _normalize_cookies(lines: list[str]) -> list[str]:
    return [_normalize_cookie(l) for l in lines if l.strip()]


_PROXY_RE = re.compile(
    r"^(https?://|socks[45]://)?([^:@/\s]+:[^:@/\s]+@)?[^:@/\s]+:\d{1,5}$",
    re.IGNORECASE,
)


def _validate_proxy(p: str) -> bool:
    return bool(_PROXY_RE.match(p.strip()))


def _mask_proxy(proxy: str) -> str:
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


def _bulk_text(lines: list[str], mask_fn=None) -> str:
    """Return a numbered text block — single widget, no lag."""
    out = []
    for i, l in enumerate(lines, 1):
        display = mask_fn(l) if mask_fn else l
        out.append(f"{i:>4}. {display}")
    return "\n".join(out)


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

    with st.spinner("Loading cookies from Redis…"):
        try:
            data         = get("/api/codm/cookies")
            raw_cookies  = data.get("cookies", [])
            source: str  = data.get("source", "unknown")
            count: int   = data.get("count", 0)
            last_updated = data.get("last_updated", "")
        except Exception as e:
            st.error(f"❌ Failed to fetch cookies: {e}")
            raw_cookies, source, count, last_updated = [], "error", 0, ""

    # ── Metrics ───────────────────────────────────────────────
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("🍪 Pool Size",  count)
    c2.metric("📍 Source",     "Redis" if source == "redis" else ("Env fallback" if source == "env" else source))
    c3.metric("🏥 Health",     _health_badge(count))
    c4.metric("🕐 Last Saved", last_updated or "—")

    # ── ☢️ Danger Zone ────────────────────────────────────────
    st.markdown("---")
    with st.expander("☢️ **DANGER ZONE — Clear Entire Cookie Pool**", expanded=False):
        st.error(
            f"⚠️ This will **permanently delete all {count} DataDome cookie(s)** from Redis.\n\n"
            "The backend falls back to the `CODM_COOKIES` env var on Railway if set, "
            "otherwise the checker will get blocked.\n\n**This action cannot be undone.**"
        )
        dz_warn, dz_btn = st.columns([3, 1])
        dz_warn.caption("Only do this if you want a completely fresh pool. Paste fresh cookies below after clearing.")
        if count == 0:
            dz_btn.info("Pool already empty.")
        else:
            if dz_btn.button("☢️ Clear ALL Cookies", type="primary",
                             use_container_width=True, key="ck_danger_clear"):
                if st.session_state.get("ck_danger_confirm"):
                    try:
                        delete("/api/codm/cookies")
                        st.success("✅ All DataDome cookies cleared from Redis.")
                        st.session_state["ck_danger_confirm"] = False
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
                else:
                    st.session_state["ck_danger_confirm"] = True
                    st.warning("⚠️ **Click again to confirm.** All cookies will be permanently deleted.")

    # ── Duplicate detection ───────────────────────────────────
    st.markdown("---")
    dupes = len(raw_cookies) - len(set(raw_cookies))
    if dupes > 0:
        st.warning(f"⚠️ **{dupes} duplicate(s) detected.** Click Dedup to clean up.")
        if st.button("🧹 Dedup Pool", key="ck_dedup"):
            deduped = list(dict.fromkeys(raw_cookies))
            try:
                post("/api/codm/cookies", {"cookies": deduped})
                st.success(f"✅ Deduped — {len(raw_cookies)} → {len(deduped)} cookies.")
                st.rerun()
            except Exception as e:
                st.error(f"❌ {e}")

    # ── Current pool display ──────────────────────────────────
    if raw_cookies:
        hc, dc = st.columns([8, 2])
        hc.markdown(f"**Stored cookies ({len(raw_cookies)}):**")
        dc.download_button(
            label="⬇️ Download .txt",
            data=_as_download(raw_cookies),
            file_name="codm_cookies.txt",
            mime="text/plain",
            use_container_width=True,
            key="ck_download",
        )

        if count > BULK_THRESHOLD:
            # ── BULK VIEW (no per-row widgets — no lag) ───────
            st.info(
                f"ℹ️ Pool has **{count} cookies** — showing bulk view to prevent lag. "
                f"Use the **☢️ Danger Zone** above to wipe all, or **Replace All** below to overwrite."
            )
            masked = [
                f"{c[:30]}…{c[-8:]}" if len(c) > 40 else c
                for c in raw_cookies
            ]
            st.text_area(
                "Cookie pool (read-only bulk view)",
                value=_bulk_text(masked),
                height=300,
                disabled=True,
                key="ck_bulk_view",
            )
        else:
            # ── PAGINATED PER-ROW DELETE ──────────────────────
            page_key = "ck_page"
            if page_key not in st.session_state:
                st.session_state[page_key] = 0

            total_pages = max(1, (len(raw_cookies) + PAGE_SIZE - 1) // PAGE_SIZE)
            page = st.session_state[page_key]
            page = max(0, min(page, total_pages - 1))

            start = page * PAGE_SIZE
            end   = min(start + PAGE_SIZE, len(raw_cookies))
            page_items = list(enumerate(raw_cookies, 1))[start:end]

            if total_pages > 1:
                pc1, pc2, pc3 = st.columns([1, 3, 1])
                if pc1.button("◀ Prev", key="ck_prev", disabled=page == 0):
                    st.session_state[page_key] = page - 1
                    st.rerun()
                pc2.caption(f"Page {page + 1} / {total_pages}  (rows {start+1}–{end})")
                if pc3.button("Next ▶", key="ck_next", disabled=page >= total_pages - 1):
                    st.session_state[page_key] = page + 1
                    st.rerun()

            for i, cookie in page_items:
                display = cookie if len(cookie) <= 60 else f"{cookie[:40]}…{cookie[-10:]}"
                col_a, col_b = st.columns([11, 1])
                col_a.code(f"{i:>3}. {display}", language=None)
                if col_b.button("🗑️", key=f"ck_del_{i}", help="Remove this cookie"):
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
                        st.error(f"❌ {e}")
    else:
        st.info(
            "ℹ️ No cookies in Redis. The backend will fall back to the "
            "`CODM_COOKIES` environment variable on Railway if set."
        )

    # ── Add / Replace ─────────────────────────────────────────
    st.markdown("---")
    st.markdown("### ➕ Add / Replace Cookies")
    st.markdown(
        "Paste fresh DataDome cookies — **one per line**. "
        "`datadome=VALUE` prefix is stripped automatically. "
        "You can paste thousands of lines here — it won't lag."
    )

    new_cookies_raw = st.text_area(
        "DataDome Cookies (one per line)",
        height=200,
        placeholder="datadome=ABC123...xyz\nDEF456...abc\n# Lines starting with # are ignored",
        key="ck_input",
    )

    preview_lines = [
        _normalize_cookie(l)
        for l in new_cookies_raw.splitlines()
        if l.strip() and not l.strip().startswith("#")
    ]
    if preview_lines:
        st.caption(f"📋 **{len(preview_lines)}** valid line(s) ready to save.")

    col_replace, col_append, col_clear = st.columns([2, 2, 1])

    with col_replace:
        if st.button("💾 Replace All", type="primary",
                     use_container_width=True, key="ck_replace"):
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
                    st.success(
                        res.get("message",
                            f"✅ Added {len(new_only)} new cookie(s) "
                            f"({len(preview_lines) - len(new_only)} duplicate(s) skipped). "
                            f"Pool now has {len(merged)}."
                        )
                    )
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

    # ── Upload .txt file ──────────────────────────────────────
    st.markdown("---")
    st.markdown("### 📁 Upload Cookie File (.txt)")
    st.caption("Each non-empty line = one cookie. `datadome=VALUE` prefix stripped automatically.")

    uploaded = st.file_uploader(
        "Upload cookie .txt file",
        type=["txt"],
        key="ck_file_upload",
        help="Each non-empty line will be normalized and added.",
    )

    if uploaded is not None:
        raw_content = uploaded.read().decode("utf-8", errors="ignore")
        file_lines  = _normalize_cookies([
            l for l in raw_content.splitlines()
            if l.strip() and not l.strip().startswith("#")
        ])
        if file_lines:
            existing_set  = set(raw_cookies)
            dupes_in_file = [l for l in file_lines if l in existing_set]
            new_in_file   = [l for l in file_lines if l not in existing_set]

            st.success(f"📂 File loaded: **{len(file_lines)} cookie(s)** found.")
            st.caption(
                f"🆕 New: **{len(new_in_file)}**   |   "
                f"🔁 Already in pool: **{len(dupes_in_file)}**"
            )

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

    with st.spinner("Loading proxies from Redis…"):
        try:
            pdata           = get("/api/codm/proxies")
            current_proxies = pdata.get("proxies", [])
            pcount: int     = pdata.get("count", 0)
        except Exception as e:
            st.error(f"❌ Failed to fetch proxies: {e}")
            current_proxies, pcount = [], 0

    # ── Metrics ───────────────────────────────────────────────
    p1, p2, p3 = st.columns(3)
    p1.metric("🔀 Pool Size", pcount)
    p2.metric("🏥 Health",    _health_badge(pcount, low_threshold=2))
    p3.metric("🔄 Routing",   "Via proxy pool" if pcount > 0 else "Direct connection")

    # ── ☢️ Danger Zone ────────────────────────────────────────
    st.markdown("---")
    with st.expander("☢️ **DANGER ZONE — Clear Entire Proxy Pool**", expanded=False):
        st.error(
            f"⚠️ This will **permanently delete all {pcount} proxy(ies)** from Redis.\n\n"
            "The backend will fall back to a direct connection — "
            "this may trigger DataDome blocks if your Railway IP has been flagged.\n\n"
            "**This action cannot be undone.**"
        )
        pz_warn, pz_btn = st.columns([3, 1])
        pz_warn.caption("Only do this to fully reset the proxy pool. Paste fresh proxies below after clearing.")
        if pcount == 0:
            pz_btn.info("Pool already empty.")
        else:
            if pz_btn.button("☢️ Clear ALL Proxies", type="primary",
                             use_container_width=True, key="px_danger_clear"):
                if st.session_state.get("px_danger_confirm"):
                    try:
                        delete("/api/codm/proxies")
                        st.success("✅ All proxies cleared. Backend will use direct connection.")
                        st.session_state["px_danger_confirm"] = False
                        st.rerun()
                    except Exception as e:
                        st.error(f"❌ {e}")
                else:
                    st.session_state["px_danger_confirm"] = True
                    st.warning("⚠️ **Click again to confirm.** All proxies will be permanently deleted.")

    # ── Duplicate detection ───────────────────────────────────
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

    # ── Current pool display ──────────────────────────────────
    if current_proxies:
        ph, pd = st.columns([8, 2])
        ph.markdown(f"**Stored proxies ({len(current_proxies)}):**")
        pd.download_button(
            label="⬇️ Download .txt",
            data=_as_download(current_proxies),
            file_name="codm_proxies.txt",
            mime="text/plain",
            use_container_width=True,
            key="px_download",
        )

        if pcount > BULK_THRESHOLD:
            # ── BULK VIEW ─────────────────────────────────────
            st.info(
                f"ℹ️ Pool has **{pcount} proxies** — showing bulk view to prevent lag. "
                "Use **☢️ Danger Zone** above to wipe all, or **Replace All** below to overwrite."
            )
            st.text_area(
                "Proxy pool (read-only bulk view)",
                value=_bulk_text(current_proxies, mask_fn=_mask_proxy),
                height=300,
                disabled=True,
                key="px_bulk_view",
            )
        else:
            # ── PAGINATED PER-ROW DELETE ──────────────────────
            ppage_key = "px_page"
            if ppage_key not in st.session_state:
                st.session_state[ppage_key] = 0

            ptotal_pages = max(1, (len(current_proxies) + PAGE_SIZE - 1) // PAGE_SIZE)
            ppage = st.session_state[ppage_key]
            ppage = max(0, min(ppage, ptotal_pages - 1))

            pstart = ppage * PAGE_SIZE
            pend   = min(pstart + PAGE_SIZE, len(current_proxies))
            ppage_items = list(enumerate(current_proxies, 1))[pstart:pend]

            if ptotal_pages > 1:
                pp1, pp2, pp3 = st.columns([1, 3, 1])
                if pp1.button("◀ Prev", key="px_prev", disabled=ppage == 0):
                    st.session_state[ppage_key] = ppage - 1
                    st.rerun()
                pp2.caption(f"Page {ppage + 1} / {ptotal_pages}  (rows {pstart+1}–{pend})")
                if pp3.button("Next ▶", key="px_next", disabled=ppage >= ptotal_pages - 1):
                    st.session_state[ppage_key] = ppage + 1
                    st.rerun()

            for i, proxy in ppage_items:
                display  = _mask_proxy(proxy)
                is_valid = _validate_proxy(proxy)
                status   = "✅" if is_valid else "⚠️ bad format"
                col_a, col_b = st.columns([11, 1])
                col_a.code(f"{i:>3}. {display}  {status}", language=None)
                if col_b.button("🗑️", key=f"px_del_{i}", help="Remove this proxy"):
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
                        st.error(f"❌ {e}")
    else:
        st.info("ℹ️ No proxies in pool. The backend will use a direct connection.")

    # ── Add / Replace proxies ─────────────────────────────────
    st.markdown("---")
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
        key="px_input",
    )

    proxy_lines     = [l.strip() for l in new_proxies_raw.splitlines()
                       if l.strip() and not l.strip().startswith("#")]
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

    # ── Upload proxy .txt ─────────────────────────────────────
    st.markdown("---")
    st.markdown("### 📁 Upload Proxy File (.txt)")
    uploaded_proxy = st.file_uploader(
        "Upload proxy file (.txt)",
        type=["txt"],
        key="px_file_upload",
        help="Each non-empty line = one proxy. Invalid formats are skipped.",
    )
    if uploaded_proxy is not None:
        pcontent    = uploaded_proxy.read().decode("utf-8", errors="ignore")
        all_plines  = [l.strip() for l in pcontent.splitlines()
                       if l.strip() and not l.strip().startswith("#")]
        pfile_valid = [p for p in all_plines if _validate_proxy(p)]
        pfile_bad   = [p for p in all_plines if not _validate_proxy(p)]

        if pfile_valid:
            st.success(f"📂 File loaded: **{len(pfile_valid)} valid proxy(ies)** found.")
            if pfile_bad:
                st.caption(f"⚠️ {len(pfile_bad)} invalid line(s) will be skipped.")

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
    st.markdown("""
#### 🍪 DataDome Cookies
DataDome is the bot-detection system Garena uses. Without a valid DataDome cookie
the backend gets blocked (HTTP 403). These cookies expire, so refresh them periodically.

**How to get fresh cookies:**
1. Open `fresh_cookie.txt` from your local CODM Python script.
2. Each line starting with `datadome=` is a valid cookie.
3. Paste them here or upload the file — the prefix is stripped automatically.

**Cookie priority:**
```
Redis (codm:cookies)  →  Railway env var CODM_COOKIES  →  no cookie (likely blocked)
```

**Rotation:** The backend picks one cookie at random per request.

---

#### 🔀 Proxy Pool
Proxies route Garena API traffic through different IPs. Helps when your Railway
server IP gets rate-limited or blocked.

**Supported formats:**
```
http://user:pass@host:port     ← recommended
http://host:port
host:port                      ← http:// assumed
socks5://host:port
```

**Priority per request:**
```
User-provided proxy (Flutter app)  →  Redis pool (random)  →  direct connection
```

---

#### ⚡ Performance Notes
- Pools over **{BULK_THRESHOLD} items** switch to a fast bulk text view instead of per-row widgets — this prevents browser/PC lag when you have thousands of entries.
- You can safely paste thousands of cookies in the text area — the input field itself does not lag; only the rendered list would, which is why bulk view kicks in automatically.
- Use **☢️ Danger Zone** to wipe a stale pool instantly, then paste fresh data.

---

#### 🔄 Cookie Refresh Schedule
| Age | Action |
|---|---|
| < 6 hours  | ✅ Fresh — no action needed |
| 6–24 hours | ⚠️ May work, consider refreshing |
| > 24 hours | ❌ Likely expired — refresh ASAP |

---

#### 🏥 Health Badges
| Badge | Meaning |
|---|---|
| 🔴 Empty | No entries in pool |
| 🟡 Low   | Less than 3 cookies / 2 proxies |
| 🟢 Good  | Pool has enough entries |
""".replace("{BULK_THRESHOLD}", str(BULK_THRESHOLD)))
