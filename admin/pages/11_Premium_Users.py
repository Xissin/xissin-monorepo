"""
pages/11_Premium_Users.py — Manage Remove Ads premium users & payment records
"""

import streamlit as st
import pandas as pd
from utils.api import get, post, delete

st.set_page_config(
    page_title="Premium Users · Xissin Admin",
    page_icon="⭐",
    layout="wide",
)
from utils.theme import inject_theme, page_header, auth_guard
inject_theme()
auth_guard()

page_header("⭐", "Premium Users", "REMOVE ADS · PAYMENTS · MANUAL GRANTS")

# ── Refresh ────────────────────────────────────────────────────────────────────
col_refresh, _ = st.columns([1, 5])
with col_refresh:
    if st.button("🔄 Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()


@st.cache_data(ttl=30, show_spinner=False)
def load_premium():
    return get("/api/payments/admin/premium").get("premium_users", {})


@st.cache_data(ttl=30, show_spinner=False)
def load_payments():
    return get("/api/payments/admin/all").get("payments", [])


with st.spinner("Loading premium data..."):
    try:
        premium_users = load_premium()
        payments      = load_payments()
    except Exception as e:
        st.error(f"Failed to load data: {e}")
        st.stop()

# ── Summary metrics ────────────────────────────────────────────────────────────
total_premium  = len(premium_users)
total_payments = len(payments)
paid_payments  = [p for p in payments if p.get("status") == "paid"]
total_revenue  = sum(p.get("amount", 0) for p in paid_payments) / 100  # centavos → PHP

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("⭐ Premium Users",    total_premium)
with col2:
    st.metric("💳 Total Payments",  total_payments)
with col3:
    st.metric("✅ Successful Pays", len(paid_payments))
with col4:
    st.metric("💰 Total Revenue",   f"₱{total_revenue:,.2f}")

st.divider()

# ── Two column layout ──────────────────────────────────────────────────────────
col_left, col_right = st.columns([1, 1])

# ── LEFT: Premium Users ────────────────────────────────────────────────────────
with col_left:
    st.markdown("### ⭐ Premium Users")

    if not premium_users:
        st.info("No premium users yet.")
    else:
        rows = []
        for uid, rec in premium_users.items():
            rows.append({
                "User ID":    uid,
                "Paid At":    rec.get("paid_at", "-"),
                "Payment ID": (rec.get("payment_id") or "-")[:20] + "…"
                              if len(rec.get("payment_id") or "") > 20
                              else rec.get("payment_id", "-"),
                "Amount":     f"₱{rec.get('amount', 0) / 100:.2f}",
                "Type":       rec.get("type", "remove_ads"),
            })
        df = pd.DataFrame(rows)
        st.dataframe(df, use_container_width=True, hide_index=True)

    st.markdown("---")

    # ── Manual Grant ──────────────────────────────────────────────────────────
    st.markdown("#### 🎁 Manually Grant Premium")
    st.caption("Use this if a user paid via GCash send / cash and you verified it.")
    with st.container(border=True):
        grant_uid = st.text_input("User ID to grant premium:", key="grant_uid",
                                  placeholder="e.g. abc123def456")
        if st.button("✅ Grant Premium", type="primary",
                     use_container_width=True, disabled=not grant_uid.strip()):
            try:
                post(f"/api/payments/admin/grant/{grant_uid.strip()}", {})
                st.success(f"✓ Premium granted to {grant_uid.strip()}!")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

    st.markdown("---")

    # ── Revoke ────────────────────────────────────────────────────────────────
    st.markdown("#### ❌ Revoke Premium")
    st.caption("Removes premium status. Use for refunds or abuse.")
    with st.container(border=True):
        revoke_uid = st.text_input("User ID to revoke:", key="revoke_uid",
                                   placeholder="e.g. abc123def456")
        if st.button("🗑️ Revoke Premium", type="secondary",
                     use_container_width=True, disabled=not revoke_uid.strip()):
            try:
                delete(f"/api/payments/admin/revoke/{revoke_uid.strip()}")
                st.success(f"✓ Premium revoked from {revoke_uid.strip()}.")
                st.cache_data.clear()
                st.rerun()
            except Exception as e:
                st.error(f"Error: {e}")

# ── RIGHT: Payment Records ─────────────────────────────────────────────────────
with col_right:
    st.markdown("### 💳 Payment Records")

    status_filter = st.selectbox(
        "Filter by status",
        ["All", "paid", "pending", "failed"],
        label_visibility="collapsed",
    )

    filtered = payments if status_filter == "All" else [
        p for p in payments if p.get("status") == status_filter
    ]

    if not filtered:
        st.info("No payment records found.")
    else:
        rows = []
        for p in filtered[:100]:  # show latest 100
            status = p.get("status", "pending")
            emoji  = "✅" if status == "paid" else ("⏳" if status == "pending" else "❌")
            rows.append({
                "Status":    f"{emoji} {status}",
                "User ID":   p.get("user_id", "-"),
                "Amount":    f"₱{p.get('amount', 0) / 100:.2f}",
                "Type":      p.get("type", "qrph"),
                "Created":   (p.get("created_at") or "-")[:16],
                "Paid At":   (p.get("paid_at")    or "-")[:16],
            })
        df = pd.DataFrame(rows)
        st.dataframe(df, use_container_width=True, hide_index=True)

    st.markdown("---")
    st.markdown("#### 🔗 PayMongo Webhook Setup")
    with st.container(border=True):
        st.caption("Register this URL in PayMongo → Settings → Webhooks:")
        st.code(
            "https://xissin-app-backend-production.up.railway.app/api/payments/webhook",
            language=None,
        )
        st.caption("Subscribe to events:")
        st.code("source.chargeable\npayment.paid", language=None)
        st.info(
            "💡 After registering the webhook, copy the **Webhook Secret** "
            "from PayMongo and add it to Railway as:\n\n"
            "`PAYMONGO_WEBHOOK_SECRET = whsec_xxxxx`"
        )
