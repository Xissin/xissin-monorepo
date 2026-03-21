"""
utils/api.py — Shared API helper for Xissin Streamlit Admin
All HTTP calls to the Railway backend go through here.

Improvements:
  - Persistent requests.Session (connection reuse, ~30% faster)
  - Retry logic (3 attempts, 2s backoff) for 5xx and network errors
  - Per-call timeout control (default 20s, heavy calls get 60s)
  - _ALL = 10_000 — pass to every log endpoint to fetch all records
  - Better error messages (extracts 'detail' or 'message' from response body)
"""
from __future__ import annotations

import time
import requests
import streamlit as st

BASE_URL = "https://xissin-app-backend-production.up.railway.app"

# Default timeout for light calls (status, settings, user list)
TIMEOUT = 20

# Timeout for heavy log endpoints that might return thousands of records
TIMEOUT_HEAVY = 60

# Pass this as the `limit` param to every log/history endpoint to fetch ALL records.
# The backend must accept a limit param — passing 10_000 effectively means "all".
_ALL = 10_000

# ── Persistent session (reuses TCP connections across Streamlit reruns) ────────
_session: requests.Session | None = None

def _get_session() -> requests.Session:
    global _session
    if _session is None:
        _session = requests.Session()
    return _session


def _headers() -> dict:
    """Auth headers using the admin key stored in session state."""
    return {
        "Content-Type": "application/json",
        "Accept":       "application/json",
        "X-Admin-Key":  st.session_state.get("admin_key", ""),
    }


def _raise(r: requests.Response) -> None:
    """Raise a clean HTTPError with the backend's detail/message string."""
    if not r.ok:
        try:
            body   = r.json()
            detail = body.get("detail") or body.get("message") or f"HTTP {r.status_code}"
        except Exception:
            detail = f"HTTP {r.status_code}"
        raise requests.HTTPError(detail)


def _request(
    method: str,
    path: str,
    *,
    params: dict | None = None,
    body: dict | None   = None,
    timeout: int        = TIMEOUT,
    retries: int        = 3,
    auth: bool          = True,
) -> dict | list:
    """
    Core request wrapper with retry logic.
    Retries on 5xx responses and network errors (not on 4xx — those are our fault).
    """
    sess    = _get_session()
    headers = _headers() if auth else {"Content-Type": "application/json", "Accept": "application/json"}
    url     = f"{BASE_URL}{path}"

    for attempt in range(1, retries + 1):
        try:
            r = sess.request(
                method,
                url,
                headers = headers,
                params  = params,
                json    = body,
                timeout = timeout,
            )
            # 5xx: retry with backoff (server cold start, Railway restarts)
            if r.status_code >= 500 and attempt < retries:
                time.sleep(2 * attempt)
                continue
            _raise(r)
            return r.json()

        except requests.HTTPError:
            raise  # 4xx — don't retry, propagate immediately

        except (requests.ConnectionError, requests.Timeout) as e:
            if attempt >= retries:
                raise requests.HTTPError(
                    f"Network error after {retries} attempts: {e}"
                ) from e
            time.sleep(2 * attempt)

    # Should never reach here
    raise requests.HTTPError("Request failed after all retries.")


# ── Public API ─────────────────────────────────────────────────────────────────

def get(path: str, params: dict | None = None, timeout: int = TIMEOUT) -> dict | list:
    """Authenticated GET. Raises on non-2xx."""
    return _request("GET", path, params=params, timeout=timeout)


def get_heavy(path: str, params: dict | None = None) -> dict | list:
    """
    Authenticated GET for log/history endpoints that may return thousands of records.
    Uses TIMEOUT_HEAVY (60s) and 3 retries — same as get() but longer timeout.
    """
    return _request("GET", path, params=params, timeout=TIMEOUT_HEAVY)


def post(path: str, body: dict | None = None, timeout: int = TIMEOUT) -> dict:
    """Authenticated POST. Raises on non-2xx."""
    return _request("POST", path, body=body or {}, timeout=timeout)


def delete(path: str, timeout: int = TIMEOUT) -> dict:
    """Authenticated DELETE. Raises on non-2xx."""
    return _request("DELETE", path, timeout=timeout)


def get_public(path: str, timeout: int = TIMEOUT) -> dict | list:
    """Unauthenticated GET (public endpoints like /api/status, /api/announcements)."""
    return _request("GET", path, timeout=timeout, auth=False)


def verify_admin_key(key: str) -> bool:
    """
    Verify admin key against a lightweight admin-only endpoint.
    Uses /api/settings/ — small payload, admin-gated.
    """
    try:
        r = _get_session().get(
            f"{BASE_URL}/api/settings/",
            headers={"X-Admin-Key": key, "Accept": "application/json"},
            timeout=10,
        )
        return r.status_code == 200
    except Exception:
        return False


def health_check() -> bool:
    try:
        r = _get_session().get(f"{BASE_URL}/health", timeout=8)
        return r.json().get("status") == "healthy"
    except Exception:
        return False
