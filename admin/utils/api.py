"""
utils/api.py — Shared API helper for Xissin Streamlit Admin
All HTTP calls to the Railway backend go through here.
"""

import requests
import streamlit as st

BASE_URL = "https://xissin-app-backend-production.up.railway.app"
TIMEOUT  = 15


def _headers() -> dict:
    """Build auth headers using the admin key stored in session state."""
    return {
        "Content-Type": "application/json",
        "Accept":       "application/json",
        "X-Admin-Key":  st.session_state.get("admin_key", ""),
    }


def get(path: str, params: dict = None) -> dict | list:
    """GET request. Raises on non-2xx."""
    r = requests.get(f"{BASE_URL}{path}", headers=_headers(), params=params, timeout=TIMEOUT)
    _raise(r)
    return r.json()


def post(path: str, body: dict = None) -> dict:
    """POST request. Raises on non-2xx."""
    r = requests.post(f"{BASE_URL}{path}", headers=_headers(), json=body or {}, timeout=TIMEOUT)
    _raise(r)
    return r.json()


def delete(path: str) -> dict:
    """DELETE request. Raises on non-2xx."""
    r = requests.delete(f"{BASE_URL}{path}", headers=_headers(), timeout=TIMEOUT)
    _raise(r)
    return r.json()


def get_public(path: str) -> dict | list:
    """Public GET (no auth header needed)."""
    r = requests.get(f"{BASE_URL}{path}", timeout=TIMEOUT)
    _raise(r)
    return r.json()


def _raise(r: requests.Response):
    if not r.ok:
        try:
            detail = r.json().get("detail") or r.json().get("message") or f"HTTP {r.status_code}"
        except Exception:
            detail = f"HTTP {r.status_code}"
        raise requests.HTTPError(detail)


def verify_admin_key(key: str) -> bool:
    """Try hitting a protected endpoint. Returns True if key is valid."""
    try:
        r = requests.get(
            f"{BASE_URL}/api/users/list",
            headers={"X-Admin-Key": key},
            timeout=TIMEOUT,
        )
        return r.status_code == 200
    except Exception:
        return False


def health_check() -> bool:
    try:
        r = requests.get(f"{BASE_URL}/health", timeout=8)
        return r.json().get("status") == "healthy"
    except Exception:
        return False
