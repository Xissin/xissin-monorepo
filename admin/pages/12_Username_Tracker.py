"""
admin/pages/12_Username_Tracker.py
Streamlit admin page — shows username search logs from the backend.
"""

import streamlit as st
import requests
import os
from datetime import datetime

# ── Page config ───────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="Username Tracker — Xissin Admin",
    page_icon="🔍",
    layout="wide",
)

# ── Helpers ───────────────────────────────────────────────────────────────────

BACKEND = os.environ.get(
    "BACKEND_URL",
    "https://xissin-app-backend-production.up.railway.app",
).rstrip("/")

ADMIN_KEY = os.environ.get("ADMIN_API_KEY", "")


def _headers():
    return {"X-Admin-Key": ADMIN_KEY} if ADMIN_KEY else {}


def _get(path: str):
    try:
        r = requests.get(f"{BACKEND}{path}", headers=_headers(), timeout=8)
        r.raise_for_status()
        return r.json()
    except Exception as exc:
        st.error(f"Backend error: {exc}")
        return None


def _fmt_ts(ts_str: str) -> str:
    try:
        return datetime.utcfromtimestamp(int(ts_str)).strftime("%Y-%m-%d %H:%M UTC")
    except Exception:
        return ts_str or "—"


# ── Page ──────────────────────────────────────────────────────────────────────

st.title("🔍 Username Tracker")
st.caption("Shows all username searches made through the Xissin app.")

tab_recent, tab_popular = st.tabs(["📋 Recent Searches", "🔥 Popular Usernames"])

# ─── Recent searches ──────────────────────────────────────────────────────────
with tab_recent:
    col_refresh, col_limit = st.columns([1, 2])
    with col_refresh:
        refresh = st.button("🔄 Refresh", key="refresh_recent")
    with col_limit:
        limit = st.slider("Max rows", 10, 200, 50, step=10)

    if refresh or True:  # always load on first render
        data = _get(f"/api/username-tracker/recent?limit={limit}")
        if data:
            searches = data.get("searches", [])
            if not searches:
                st.info("No username searches logged yet.")
            else:
                # Build display rows
                rows = []
                for s in searches:
                    found_on   = s.get("found_on", "")
                    found_list = [x.strip() for x in found_on.split(",") if x.strip()] if found_on else []
                    rows.append({
                        "Time (UTC)":   _fmt_ts(s.get("ts", "")),
                        "Username":     f"@{s.get('username', '—')}",
                        "Found On":     len(found_list),
                        "Total":        s.get("total", "30"),
                        "Platforms":    ", ".join(found_list) if found_list else "—",
                        "User ID":      s.get("user_id", "—"),
                    })

                # Summary metrics
                mc1, mc2, mc3 = st.columns(3)
                mc1.metric("Total Searches Shown", len(rows))
                avg_found = (
                    sum(r["Found On"] for r in rows) / len(rows)
                    if rows else 0
                )
                mc2.metric("Avg Platforms Found", f"{avg_found:.1f}")
                unique_users = len({r["Username"] for r in rows})
                mc3.metric("Unique Usernames", unique_users)

                st.divider()
                st.dataframe(rows, use_container_width=True, hide_index=True)

# ─── Popular usernames ────────────────────────────────────────────────────────
with tab_popular:
    col_r2, col_lim2 = st.columns([1, 2])
    with col_r2:
        st.button("🔄 Refresh", key="refresh_popular")
    with col_lim2:
        pop_limit = st.slider("Top N", 5, 50, 20, step=5)

    pop_data = _get(f"/api/username-tracker/popular?limit={pop_limit}")
    if pop_data:
        popular = pop_data.get("popular", [])
        if not popular:
            st.info("No popular usernames yet.")
        else:
            # Bar chart
            chart_data = {
                "Username": [f"@{p['username']}" for p in popular],
                "Searches": [p["count"] for p in popular],
            }
            st.bar_chart(
                data={row["Username"]: row["Searches"]
                      for row in
                      [{"Username": f"@{p['username']}", "Searches": p["count"]}
                       for p in popular]},
            )

            # Table
            st.dataframe(
                [{"Rank": i + 1,
                  "Username": f"@{p['username']}",
                  "Total Searches": p["count"]}
                 for i, p in enumerate(popular)],
                use_container_width=True,
                hide_index=True,
            )
