"""
limiter.py — Shared rate limiter instance.
Imported by main.py and all routers. Avoids circular imports.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
