# VoxLink API

Node.js + SQLite (sql.js) backend. See the root `README.md` for setup.

```bash
npm install
cp .env.example .env
npm start
```

Send `Authorization: Bearer <token>` on every route except OTP send/verify and the plans list.

| Section | Method | Path |
|---|---|---|
| Auth | POST | `/api/auth/otp/send` `{ phone }` (E.164, e.g. `+919876543210`) |
| Auth | POST | `/api/auth/otp/verify` `{ phone, otp }` → `{ token, user }` |
| Auth | GET | `/api/auth/me` |
| Auth | POST | `/api/auth/logout` |
| Profile | GET/PUT | `/api/users/me` `{ name, age, gender, city, country, countryCode }` |
| Profile | GET | `/api/users/me/stats` |
| Match | POST | `/api/match/join` `{ genderFilter: any \| male \| female }` (403 `CALL_LIMIT` when today's minutes are used up) |
| Match | GET | `/api/match/status` (poll; returns `matched` with `call.roomUrl`, `call.token`, `call.limitSeconds`, `peer`) |
| Match | DELETE | `/api/match` |
| Match | GET | `/api/match/online-count` |
| Match | GET | `/api/match/allowance` today's call minutes: `{ premium, limitMinutes, usedSeconds, remainingSeconds }` |
| Calls | GET | `/api/calls` |
| Calls | PATCH | `/api/calls/:id/end` `{ durationSeconds }` |
| Premium | GET | `/api/subscriptions/plans`, `/api/subscriptions/me` |
| Premium | POST | `/api/subscriptions/order` `{ plan }` → `{ mode: google_play, productId }` (or a dev order) |
| Premium | POST | `/api/subscriptions/google-play/verify` `{ productId, purchaseToken }` (202 `{ pending }` while Play is still processing) |
| Premium | POST | `/api/subscriptions/verify` `{ orderId }` (dev orders only) |
| Safety | POST | `/api/reports` `{ userId, reason }`, `/api/blocks` `{ userId }` |

A gender filter other than `any` returns `403 { code: "PREMIUM_REQUIRED" }` for users without active premium.
