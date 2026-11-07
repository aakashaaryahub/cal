# VoxLink

Anonymous voice calls with random strangers. Flutter app + Node.js backend, with voice over [Daily](https://www.daily.co) and payments through Google Play Billing.

**Flow:** splash → onboarding (name, age, gender, city, country, phone + OTP) → home. The session is saved on the device, so returning users go straight to home. Users who already have an account (new phone, reinstall, or after logging out) tap **Log in** on the intro screen and only verify their phone number.

**Premium** lets users choose to talk only to women or only to men. It is **off by default**: everyone can pick any gender for free and the app hides Premium. Switch it on from the admin dashboard's **Settings** tab when you're ready to charge; the server enforces it immediately and apps pick it up on their next launch.

**Invites** are the growth loop. Every user has an invite code (Profile → Invite friends, or the Chats tab when they have no friends yet). Anyone who signs up with it becomes their friend straight away, so they can chat and call without meeting on a random call first. The share text and an optional download link are the `invite` content key.

Plans, once Premium is on:

| Plan    | Price  | Per week |
|---------|--------|----------|
| Weekly  | ₹499   | ₹499     |
| Monthly | ₹999   | ₹233     |
| Yearly  | ₹4,999 | ₹96      |

Plans are one-time payments for the period and don't auto-renew; buying again adds the days on top. Each plan is a consumable Google Play in-app product with the same ID, and Play charges the price set in Play Console (the app shows Play's price). The database price is only a fallback for display and the revenue figure. See [Editing content and prices](#editing-content-and-prices).

## Quick start

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env    # fill in the keys you have
npm start               # http://localhost:3000
```

Everything works without keys, in a test mode:

| Missing key | What happens |
|---|---|
| `POWERSTEXT_*` | OTPs are printed in the server console and shown in the app |
| `GOOGLE_PLAY_*` | Purchases ask "Activate without paying?" instead of opening Google Play |
| `DAILY_API_KEY` | Voice calls are off: tapping connect shows "Voice calls aren't set up" |

Setting `NODE_ENV=production` turns off both test shortcuts.

### 2. Daily (voice calls)

1. Sign up at [dashboard.daily.co](https://dashboard.daily.co) and copy the API key from **Developers**.
2. Put it in `backend/.env` as `DAILY_API_KEY` and restart. The server log shows `Daily voice calls on <your-domain>.daily.co` when the key works.

For every call the server creates a private, audio-only room for two people and gives each person their own meeting token. The room is deleted when the call ends and expires after 4 hours regardless. The app needs no call keys of its own.

### 3. Google Play Billing (premium)

1. In Play Console, open the app → **Monetize with Play → Products → One-time products** and create one product per plan. The **product ID must equal the plan ID** (`weekly`, `monthly`, `yearly`). Set the prices there and activate them.
2. In [Google Cloud Console](https://console.cloud.google.com), enable the **Google Play Android Developer API**, create a service account and download a JSON key.
3. In Play Console → **Users and permissions**, invite the service account's email with **View financial data** and **Manage orders and subscriptions** for this app.
4. Set `GOOGLE_PLAY_PACKAGE=com.voxlink.app` and `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (the key file's contents) on the server.

The app buys through Play, the server checks the purchase token with Google, adds the days once per token and consumes the purchase. Purchases that didn't finish (app closed mid-payment, slow UPI) are resent every time the app opens. Real purchases only work in a build installed from a Play testing track, by a tester account; add your Gmail under **Settings → License testing** to buy without being charged.

### 4. Run the app

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<your-PC-LAN-IP>:3000/api
```

- On the Android emulator you can leave out `API_BASE_URL`; it defaults to `http://10.0.2.2:3000/api`.
- To test a real call you need **two devices** (or a device plus an emulator) signed in with different phone numbers, both tapping connect at the same time.
- Daily needs Android 7.0+ and iOS 14+.

## Deploying the backend (Render)

`render.yaml` describes the whole service. In Render: **New → Blueprint**, pick this GitHub repo, fill in the secret values it asks for, and create. It runs `backend/` on Node with a 1 GB disk at `/var/data` for the database, at `https://voxlink-api.onrender.com`. Every push to the main branch redeploys.

Build the app against it with `--dart-define=API_BASE_URL=https://voxlink-api.onrender.com/api`.

## Admin dashboard

Open **http://localhost:3000/admin** and sign in with `ADMIN_USERNAME` / `ADMIN_PASSWORD` from `backend/.env` (password 8+ characters; leave either empty to turn the dashboard off). Sessions last 12 hours, and 5 wrong passwords lock that IP out for 15 minutes.

It's read-only and shows:

- **Overview:** users, onboarded vs. unfinished signups, active now / last 24 h, premium, calls, talk time, follows, messages, reports, revenue, plus daily charts for the last 14 days and gender/country splits
- **Users:** search and filter every account; click one for their calls, followers, following, reports, blocks and payments
- **Calls:** who called whom, random match or friend call, status, duration
- **Follows:** who follows whom, with mutual follows marked as friends
- **Reports:** who reported whom and why
- **Settings:** the Premium on/off switch

The overview also counts users who joined through an invite, and each user's panel shows who invited them and how many people they've brought in.

Message text is private and never shown; only counts are.

**Testing follows and chats without a call.** Following needs a past call and chatting needs a mutual follow, so on one device those screens stay empty. Open any onboarded user in the dashboard and press **Add demo friends & chat**. That account gets Priya (friend, with a chat), Rahul (follows them) and Meera (past call, has reported them). Turned off when `NODE_ENV=production`.

**Starting over.** To delete every user and their calls, follows, chats, reports and payments (plans and app content stay), stop the server and run `npm run reset-users -- --yes` in `backend/`. A backup of the old database is saved in `backend/data/`.

## Editing content and prices

Everything the app displays comes from the API. Per-user data (profiles, calls, chats, follows, votes, leaderboards) is always live. App-wide content comes from `GET /api/app-config`:

| Key | What it controls |
|---|---|
| `plans` table | Premium plans: title, price, duration, badge, order, on/off |
| `intro` | Onboarding headline, subtitle, chips, sample avatars |
| `tips` | Rotating tips on the Talk tab |
| `genderOptions` | "I want to talk to" choices, and which ones need Premium |
| `matching` | Messages shown while searching |
| `premium` | Paywall title, subtitle, benefits, footer |
| `reportReasons` | Choices in the report sheet |

The response also says whether voice calls are enabled (`DAILY_API_KEY` is set) and lists the countries of today's active users.

Nothing is cached on the device except the login token. On launch the app loads the config and the user's profile from the API, and won't go past the splash screen until both load. The app pings `GET /api/health` every 4 s on every screen. If that or any other request fails, a full-screen "Can't reach the server" cover appears until the server answers again. It stays out of the way during a live call so people can still hang up. The app has no built-in content, so a key missing from the database shows as empty.

**To edit**, set `ADMIN_TOKEN` (16+ characters) in `backend/.env`, restart, then:

```bash
# Change the weekly price to ₹399
curl -X PUT localhost:3000/api/admin/plans/weekly -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" -d '{"amountPaise": 39900}'

# Add a plan / hide a plan
curl -X PUT localhost:3000/api/admin/plans/quarterly -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" -d '{"title":"3 Months","amountPaise":199900,"days":90,"sortOrder":3}'
curl -X PUT localhost:3000/api/admin/plans/yearly -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" -d '{"active": false}'

# Replace any content key (send the whole value)
curl -X PUT localhost:3000/api/admin/content/tips -H "x-admin-token: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" -d '{"value":[{"emoji":"🎉","text":"Weekend special!"}]}'

# See current content, all plans, and user reports
curl localhost:3000/api/admin/content -H "x-admin-token: $ADMIN_TOKEN"
curl localhost:3000/api/admin/plans   -H "x-admin-token: $ADMIN_TOKEN"
curl localhost:3000/api/admin/reports -H "x-admin-token: $ADMIN_TOKEN"
```

Changes reach the app the next time it starts, and the paywall re-fetches plans whenever it opens. Prices buyers pay are set in Play Console; change them there too. A new plan needs a Play product with the same ID (lowercase letters, digits, `_` and `.`), or the app can't sell it.

`backend/src/defaults.js` only seeds an empty database. Editing it doesn't change an existing one.

## How matching works

1. The app `POST /api/match/join` with the gender filter (`any` for free users).
2. It polls `GET /api/match/status` every 1.5 s.
3. When two compatible users are waiting, the server creates a call with a shared room ID.
4. The server creates a private Daily room for the call and gives each person the room URL and their own meeting token. Both apps join with the microphone on and the camera off; the call starts when the other person arrives.

Blocked users are never matched again. Peers only see name, age, gender, city and country, never the phone number.

The queue lives in a single-process SQLite database (`sql.js`). That's fine for a launch, but before running more than one server instance, move the queue to Redis or Postgres.

## Before you publish

- **Random-chat apps** get extra review on both stores. You'll need working report/block (already built), an 18+ age gate (already enforced), a privacy policy, and a moderation process for reports.
- **SMS.** OTPs go out through PowersText with a DLT-registered template, so only Indian (+91) mobile numbers can sign up. The message text in `backend/src/sms.js` must match the template word for word; if you change the template, change it there too.
- **Android release.** The app ID is `com.voxlink.app`. Release builds are signed with the upload key in `android/key.properties` (see `android/key.properties.example`); without it they fall back to debug keys, which Play rejects.
- **iOS.** After the first `pod install`, add this to the `post_install` block in `ios/Podfile` so `permission_handler` can request the microphone:

  ```ruby
  target.build_configurations.each do |config|
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_MICROPHONE=1']
  end
  ```

## Project layout

```
lib/
  config/app_config.dart       build-time keys (--dart-define)
  services/
    api.dart                   REST client
    call_engine.dart           Daily wrapper (join/leave, mute, speaker, who's speaking)
    payments.dart              Google Play Billing + server verification
    storage.dart               on-device session
  screens/
    splash_screen.dart
    onboarding/                6-step onboarding with OTP
    home/                      Talk · Recent · Profile tabs
    matching_screen.dart       radar search, polling
    call_screen.dart           in-call UI driven by live voice levels
    call_summary_screen.dart   rating, next stranger, report
    premium_screen.dart        plans + purchase
  widgets/                     aurora background, pulse rings, pressable, etc.
backend/src/
  routes/auth.js               OTP send/verify (hashed codes, rate limits)
  routes/match.js              matchmaking queue
  routes/calls.js              history, end call (also deletes the voice room)
  routes/subscriptions.js      plans, Play purchase verification
  googlePlay.js                Google Play Developer API (check + consume purchases)
  routes/config.js             GET /api/app-config (plans, content, client settings)
  routes/admin.js              edit plans/content, view reports (ADMIN_TOKEN)
  routes/social.js             follows, votes, friends list
  routes/chats.js              messages between friends
  routes/direct.js             calling a friend (ring / accept / decline)
  routes/leaderboard.js        today's talk time, most followers
  content.js, defaults.js      plans/content storage and first-run seed values
  daily.js                     Daily rooms and meeting tokens (REST API)
```
