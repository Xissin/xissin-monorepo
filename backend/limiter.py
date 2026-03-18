"""
limiter.py — SlowAPI rate limiter configuration for Xissin backend

Protects against:
  - API abuse / scraping
  - Brute-force admin key guessing
  - Payment endpoint flooding
  - Free SMS/NGL bombing via API bypass

All limits are per IP address.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200/minute"],   # global fallback for all routes
)

# ── Per-endpoint limits (apply these as decorators in routers) ────────────────
#
#   @limiter.limit("5/minute")     ← payment creation
#   @limiter.limit("60/minute")    ← general API
#   @limiter.limit("10/minute")    ← admin login attempts
#   @limiter.limit("3/minute")     ← SMS/NGL bomb (already rate-limited by service)
#
# Usage in router:
#   from limiter import limiter
#   from fastapi import Request
#
#   @router.post("/create")
#   @limiter.limit("5/minute")
#   async def create_payment(request: Request, ...):
