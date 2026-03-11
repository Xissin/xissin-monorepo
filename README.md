# Xissin App — Backend API

FastAPI backend for the **Xissin Multi-Tool Flutter App**.  
Hosted on Railway · Storage via Upstash Redis.

## Features
- 🔑 Key System — generate, redeem, revoke activation keys
- 👤 User Management — register, ban, unban, view logs
- 💣 SMS Bomber — 14 PH services, parallel execution

## API Endpoints

### Keys
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/keys/generate` | Admin | Generate a new key |
| POST | `/api/keys/redeem` | None | Redeem a key |
| POST | `/api/keys/revoke` | Admin | Revoke a key |
| GET  | `/api/keys/list` | Admin | List all keys |
| GET  | `/api/keys/validate/{key}` | None | Validate key |
| GET  | `/api/keys/status/{user_id}` | None | Check user key status |

### Users
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/users/register` | None | Register a new user |
| GET  | `/api/users/list` | Admin | List all users |
| POST | `/api/users/ban` | Admin | Ban a user |
| POST | `/api/users/unban` | Admin | Unban a user |
| GET  | `/api/users/logs/recent` | Admin | View action logs |
| GET  | `/api/users/check/{user_id}` | None | Check user status |

### SMS Bomber
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/sms/bomb` | None (key required) | Fire the SMS bomber |
| GET  | `/api/sms/services` | None | List available services |

## Admin Authentication
Pass `X-Admin-Key: your_secret_key` header for all admin endpoints.

## Environment Variables (Railway)
```
UPSTASH_REDIS_REST_URL=https://...
UPSTASH_REDIS_REST_TOKEN=...
ADMIN_API_KEY=your_secure_admin_key_here
PORT=8000
```

## Local Development
```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

## Deploy to Railway
1. Push this repo to GitHub
2. Connect repo in Railway → New Project → Deploy from GitHub
3. Set the environment variables above
4. Railway auto-deploys on every push 🚀
