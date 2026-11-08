// Admin API: the web dashboard at /admin, plus editing what the app shows
// without an app update.
//
// Sign in with ADMIN_USERNAME / ADMIN_PASSWORD (POST /login) and send the
// returned token as `Authorization: Bearer <token>`. Scripts can instead send
// ADMIN_TOKEN as `x-admin-token`. Either way, unset = disabled.
//
//   POST   /api/admin/login              { username, password } -> { token }
//   GET    /api/admin/overview           totals, last 14 days, gender, countries
//   GET    /api/admin/daily-usage        Daily.co participant minutes: today, this month (UTC)
//   GET    /api/admin/users              ?q=&filter=all|onboarded|incomplete|premium&limit=&offset=
//   GET    /api/admin/users/:id          profile, calls, followers, following, reports, payments
//   GET    /api/admin/calls              ?kind=random|direct&limit=&offset=
//   GET    /api/admin/follows            ?limit=&offset=
//   POST   /api/admin/users/:id/demo-activity   testing only: demo friends, chat, report
//   GET    /api/admin/settings           { premiumEnabled }
//   PUT    /api/admin/settings           { premiumEnabled: true|false }
//   GET    /api/admin/content            all content keys
//   PUT    /api/admin/content/:key       { value: <any JSON> }
//   GET    /api/admin/plans              all plans, including inactive
//   PUT    /api/admin/plans/:id          { title, amountPaise, days, badge, sortOrder, active }
//   GET    /api/admin/reports            latest reports, for moderation
//   POST   /api/admin/users/:id/ban      { reason } bans the phone number (also blocks re-signup)
//   DELETE /api/admin/users/:id/ban      lifts the ban
//
// Message text is private and never exposed here; only counts are.
const crypto = require('crypto');
const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../db');
const content = require('../content');
const rel = require('../relations');
const daily = require('../daily');

const router = express.Router();

const SESSION_HOURS = 12;
const MAX_FAILURES = 5;
const LOCKOUT_MS = 15 * 60 * 1000;

const secret = () => process.env.JWT_SECRET || 'voxlink-dev-secret';

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function loginConfigured() {
  return Boolean(process.env.ADMIN_USERNAME) && String(process.env.ADMIN_PASSWORD || '').length >= 8;
}

// Failed sign-ins per IP, kept in memory: 5 tries, then a 15 minute lockout.
const failures = new Map();

router.post('/login', (req, res) => {
  if (!loginConfigured()) {
    return res.status(503).json({
      ok: false,
      error: 'Admin login is off. Set ADMIN_USERNAME and ADMIN_PASSWORD (8+ characters) in backend/.env and restart.',
    });
  }
  const now = Date.now();
  const f = failures.get(req.ip);
  if (f && f.count >= MAX_FAILURES && now - f.at < LOCKOUT_MS) {
    return res.status(429).json({ ok: false, error: 'Too many attempts. Try again in 15 minutes.' });
  }
  // Compare both so a wrong username takes as long as a wrong password.
  const userOk = safeEqual(req.body.username || '', process.env.ADMIN_USERNAME);
  const passOk = safeEqual(req.body.password || '', process.env.ADMIN_PASSWORD);
  if (!(userOk && passOk)) {
    const count = f && now - f.at < LOCKOUT_MS ? f.count + 1 : 1;
    failures.set(req.ip, { count, at: now });
    return res.status(401).json({ ok: false, error: 'Wrong username or password' });
  }
  failures.delete(req.ip);
  const token = jwt.sign({ role: 'admin' }, secret(), { expiresIn: `${SESSION_HOURS}h` });
  res.json({ ok: true, token, expiresIn: SESSION_HOURS * 3600 });
});

function adminOnly(req, res, next) {
  const expected = process.env.ADMIN_TOKEN || '';
  const given = String(req.headers['x-admin-token'] || '');
  if (expected.length >= 16 && given && safeEqual(given, expected)) return next();

  const header = req.headers.authorization || '';
  if (header.startsWith('Bearer ')) {
    try {
      // App users' tokens carry a userId, never this role.
      if (jwt.verify(header.slice(7), secret()).role === 'admin') return next();
    } catch {}
  }
  res.status(401).json({ ok: false, error: 'Admin sign-in required' });
}

router.use(adminOnly);

// ── Activity (read-only) ──

const count = (sql, params = []) => Number(db.get(sql, params)?.n || 0);

function page(req, max = 200) {
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), max);
  const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
  return { limit, offset };
}

function userRow(u) {
  return {
    id: Number(u.id),
    phone: u.phone,
    name: u.name || '',
    age: Number(u.age || 0),
    gender: u.gender || '',
    city: u.city || '',
    country: u.country || '',
    countryCode: u.country_code || '',
    onboarded: Boolean(u.profile_completed),
    isPremium: db.isPremium(u),
    premiumUntil: u.premium_until || null,
    banned: Boolean(db.banFor(u.phone)),
    createdAt: u.created_at,
    lastSeen: u.last_seen,
  };
}

const USER_STATS = `
  (SELECT COUNT(*) FROM follows WHERE following_id = u.id) AS followers,
  (SELECT COUNT(*) FROM follows WHERE follower_id = u.id) AS following,
  (SELECT COUNT(*) FROM calls WHERE caller_id = u.id OR callee_id = u.id) AS calls,
  (SELECT COALESCE(SUM(duration_seconds), 0) FROM calls WHERE caller_id = u.id OR callee_id = u.id) AS talk_seconds,
  (SELECT COUNT(*) FROM reports WHERE reported_id = u.id) AS reports_against`;

function withStats(u) {
  return {
    ...userRow(u),
    followers: Number(u.followers),
    following: Number(u.following),
    calls: Number(u.calls),
    talkSeconds: Number(u.talk_seconds),
    reportsAgainst: Number(u.reports_against),
  };
}

const person = (id, name, phone) => ({ id: Number(id), name: name || '', phone });

function callRow(c) {
  return {
    id: Number(c.id),
    kind: c.kind,
    status: c.status,
    durationSeconds: Number(c.duration_seconds || 0),
    genderFilter: c.gender_filter,
    startedAt: c.started_at,
    endedAt: c.ended_at,
    caller: person(c.caller_id, c.caller_name, c.caller_phone),
    callee: person(c.callee_id, c.callee_name, c.callee_phone),
  };
}

const CALLS_SELECT = `
  SELECT c.*, a.name AS caller_name, a.phone AS caller_phone, b.name AS callee_name, b.phone AS callee_phone
  FROM calls c JOIN users a ON a.id = c.caller_id JOIN users b ON b.id = c.callee_id`;

function followRow(f) {
  return {
    id: Number(f.id),
    createdAt: f.created_at,
    mutual: Boolean(f.mutual),
    follower: person(f.follower_id, f.follower_name, f.follower_phone),
    following: person(f.following_id, f.following_name, f.following_phone),
  };
}

const FOLLOWS_SELECT = `
  SELECT f.*, a.name AS follower_name, a.phone AS follower_phone, b.name AS following_name, b.phone AS following_phone,
         EXISTS (SELECT 1 FROM follows r WHERE r.follower_id = f.following_id AND r.following_id = f.follower_id) AS mutual
  FROM follows f JOIN users a ON a.id = f.follower_id JOIN users b ON b.id = f.following_id`;

// Days are UTC calendar days, oldest first.
function lastDays(n) {
  const days = [];
  for (let i = n - 1; i >= 0; i--) days.push(new Date(Date.now() - i * 864e5).toISOString().slice(0, 10));
  return days;
}

router.get('/overview', (_req, res) => {
  const premium = db.all('SELECT * FROM users WHERE is_premium = 1').filter(db.isPremium).length;
  const mutualFollows = count(
    `SELECT COUNT(*) AS n FROM follows f
     WHERE EXISTS (SELECT 1 FROM follows r WHERE r.follower_id = f.following_id AND r.following_id = f.follower_id)`
  );
  const totals = {
    users: count('SELECT COUNT(*) AS n FROM users'),
    onboarded: count('SELECT COUNT(*) AS n FROM users WHERE profile_completed = 1'),
    premium,
    activeNow: count(`SELECT COUNT(*) AS n FROM users WHERE last_seen >= datetime('now', '-5 minutes')`),
    active24h: count(`SELECT COUNT(*) AS n FROM users WHERE last_seen >= datetime('now', '-1 day')`),
    calls: count('SELECT COUNT(*) AS n FROM calls'),
    connectedCalls: count('SELECT COUNT(*) AS n FROM calls WHERE duration_seconds > 0'),
    talkSeconds: count('SELECT COALESCE(SUM(duration_seconds), 0) AS n FROM calls'),
    avgCallSeconds: Math.round(count('SELECT COALESCE(AVG(duration_seconds), 0) AS n FROM calls WHERE duration_seconds > 0')),
    follows: count('SELECT COUNT(*) AS n FROM follows'),
    friendPairs: mutualFollows / 2,
    messages: count('SELECT COUNT(*) AS n FROM messages'),
    reports: count('SELECT COUNT(*) AS n FROM reports'),
    blocks: count('SELECT COUNT(*) AS n FROM blocks'),
    revenuePaise: count(`SELECT COALESCE(SUM(amount_paise), 0) AS n FROM payment_orders WHERE status = 'paid' AND provider != 'dev'`),
    testPayments: count(`SELECT COUNT(*) AS n FROM payment_orders WHERE status = 'paid' AND provider = 'dev'`),
    invitedUsers: count('SELECT COUNT(*) AS n FROM users WHERE invited_by IS NOT NULL AND profile_completed = 1'),
    inviters: count('SELECT COUNT(DISTINCT invited_by) AS n FROM users WHERE invited_by IS NOT NULL AND profile_completed = 1'),
  };

  const days = lastDays(14);
  const since = days[0];
  const byDay = (sql) => Object.fromEntries(db.all(sql, [since]).map((r) => [r.d, r]));
  const signups = byDay(`SELECT date(created_at) AS d, COUNT(*) AS n FROM users WHERE date(created_at) >= ? GROUP BY d`);
  const calls = byDay(
    `SELECT date(started_at) AS d,
            SUM(kind = 'random') AS random, SUM(kind = 'direct') AS direct,
            COALESCE(SUM(duration_seconds), 0) AS talk
     FROM calls WHERE date(started_at) >= ? GROUP BY d`
  );
  const daily = days.map((d) => ({
    date: d,
    signups: Number(signups[d]?.n || 0),
    randomCalls: Number(calls[d]?.random || 0),
    directCalls: Number(calls[d]?.direct || 0),
    talkMinutes: Math.round(Number(calls[d]?.talk || 0) / 60),
  }));

  const gender = db
    .all(`SELECT gender, COUNT(*) AS n FROM users WHERE profile_completed = 1 GROUP BY gender ORDER BY n DESC`)
    .map((r) => ({ gender: r.gender || 'unknown', count: Number(r.n) }));
  const countries = db
    .all(
      `SELECT country, country_code, COUNT(*) AS n FROM users
       WHERE profile_completed = 1 AND country != '' GROUP BY country ORDER BY n DESC LIMIT 8`
    )
    .map((r) => ({ country: r.country, countryCode: r.country_code, count: Number(r.n) }));

  res.json({ ok: true, totals, daily, gender, countries });
});

// Daily's meetings log is slow to page through, so it's read at most every 5 minutes.
const USAGE_TTL_MS = 5 * 60 * 1000;
let usageCache = null;

router.get('/daily-usage', async (_req, res) => {
  if (!daily.isConfigured()) return res.json({ ok: true, configured: false });
  if (usageCache && Date.now() - usageCache.at < USAGE_TTL_MS) return res.json(usageCache.body);

  const now = new Date();
  const monthStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1) / 1000;
  const dayStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()) / 1000;
  let log;
  try {
    log = await daily.meetings(monthStart, Math.ceil(Date.now() / 1000) + 60);
  } catch (err) {
    console.error('[admin] daily usage:', err.message);
    return res.status(502).json({ ok: false, error: "Couldn't read usage from Daily. Check DAILY_API_KEY." });
  }
  const sum = (list) => Math.ceil(list.reduce((s, m) => s + m.participantSeconds, 0) / 60);
  const today = log.meetings.filter((m) => m.start >= dayStart);
  // The app's own call log, as a cross-check: two people per call.
  const appSeconds = count(
    `SELECT COALESCE(SUM(duration_seconds), 0) AS n FROM calls WHERE started_at >= ?`,
    [new Date(monthStart * 1000).toISOString().slice(0, 19).replace('T', ' ')]
  );
  const body = {
    ok: true,
    configured: true,
    month: { label: now.toISOString().slice(0, 7), meetings: log.meetings.length, participantMinutes: sum(log.meetings) },
    today: { meetings: today.length, participantMinutes: sum(today) },
    ongoing: log.meetings.filter((m) => m.ongoing).length,
    appEstimateMinutes: Math.ceil((appSeconds * 2) / 60),
    complete: log.complete,
    checkedAt: new Date().toISOString(),
  };
  usageCache = { at: Date.now(), body };
  res.json(body);
});

router.get('/users', (req, res) => {
  const { limit, offset } = page(req);
  const where = [];
  const params = [];
  const q = String(req.query.q || '').trim();
  if (q) {
    where.push('(u.name LIKE ? OR u.phone LIKE ? OR u.city LIKE ? OR u.country LIKE ?)');
    params.push(...Array(4).fill(`%${q}%`));
  }
  const filter = String(req.query.filter || 'all');
  if (filter === 'onboarded') where.push('u.profile_completed = 1');
  if (filter === 'incomplete') where.push('u.profile_completed = 0');
  if (filter === 'premium') where.push('u.is_premium = 1');
  const clause = where.length ? `WHERE ${where.join(' AND ')}` : '';

  let rows = db.all(`SELECT u.*, ${USER_STATS} FROM users u ${clause} ORDER BY u.id DESC`, params);
  // Expiry lives in an ISO string; filter in JS so lapsed premium drops out.
  if (filter === 'premium') rows = rows.filter(db.isPremium);
  res.json({ ok: true, total: rows.length, users: rows.slice(offset, offset + limit).map(withStats) });
});

router.get('/users/:id', (req, res) => {
  const id = Number(req.params.id);
  const u = db.get(`SELECT u.*, ${USER_STATS} FROM users u WHERE u.id = ?`, [id]);
  if (!u) return res.status(404).json({ ok: false, error: 'User not found' });

  const calls = db.all(`${CALLS_SELECT} WHERE c.caller_id = ? OR c.callee_id = ? ORDER BY c.id DESC LIMIT 200`, [id, id]);
  const followers = db.all(`${FOLLOWS_SELECT} WHERE f.following_id = ? ORDER BY f.id DESC`, [id]);
  const following = db.all(`${FOLLOWS_SELECT} WHERE f.follower_id = ? ORDER BY f.id DESC`, [id]);
  const reports = db.all(
    `SELECT r.id, r.reason, r.created_at, r.reporter_id, a.name AS reporter_name, r.reported_id, b.name AS reported_name
     FROM reports r JOIN users a ON a.id = r.reporter_id JOIN users b ON b.id = r.reported_id
     WHERE r.reported_id = ? OR r.reporter_id = ? ORDER BY r.id DESC`,
    [id, id]
  );
  const blocks = db.all(
    `SELECT k.created_at, k.blocker_id, a.name AS blocker_name, k.blocked_id, b.name AS blocked_name
     FROM blocks k JOIN users a ON a.id = k.blocker_id JOIN users b ON b.id = k.blocked_id
     WHERE k.blocker_id = ? OR k.blocked_id = ? ORDER BY k.id DESC`,
    [id, id]
  );
  const payments = db.all(
    `SELECT plan, amount_paise, days, provider, status, created_at FROM payment_orders WHERE user_id = ? ORDER BY id DESC`,
    [id]
  );

  res.json({
    ok: true,
    demoEnabled: demoEnabled(),
    user: {
      ...withStats(u),
      inviteCode: u.invite_code || null,
      invitedBy: u.invited_by ? person(u.invited_by, db.get('SELECT name FROM users WHERE id = ?', [u.invited_by])?.name) : null,
      banReason: db.banFor(u.phone)?.reason || null,
      invitesJoined: count('SELECT COUNT(*) AS n FROM users WHERE invited_by = ? AND profile_completed = 1', [id]),
      messagesSent: count('SELECT COUNT(*) AS n FROM messages WHERE sender_id = ?', [id]),
      messagesReceived: count('SELECT COUNT(*) AS n FROM messages WHERE receiver_id = ?', [id]),
    },
    calls: calls.map(callRow),
    followers: followers.map(followRow),
    following: following.map(followRow),
    reports: reports.map((r) => ({
      id: Number(r.id),
      reason: r.reason,
      createdAt: r.created_at,
      reporter: person(r.reporter_id, r.reporter_name),
      reported: person(r.reported_id, r.reported_name),
    })),
    blocks: blocks.map((b) => ({
      createdAt: b.created_at,
      blocker: person(b.blocker_id, b.blocker_name),
      blocked: person(b.blocked_id, b.blocked_name),
    })),
    payments: payments.map((p) => ({
      plan: p.plan,
      amountPaise: Number(p.amount_paise),
      days: Number(p.days),
      provider: p.provider,
      status: p.status,
      createdAt: p.created_at,
    })),
  });
});

router.get('/calls', (req, res) => {
  const { limit, offset } = page(req);
  const kind = ['random', 'direct'].includes(req.query.kind) ? req.query.kind : null;
  const clause = kind ? 'WHERE c.kind = ?' : '';
  const params = kind ? [kind] : [];
  const total = count(`SELECT COUNT(*) AS n FROM calls c ${clause}`, params);
  const rows = db.all(`${CALLS_SELECT} ${clause} ORDER BY c.id DESC LIMIT ? OFFSET ?`, [...params, limit, offset]);
  res.json({ ok: true, total, calls: rows.map(callRow) });
});

router.get('/follows', (req, res) => {
  const { limit, offset } = page(req);
  const total = count('SELECT COUNT(*) AS n FROM follows');
  const rows = db.all(`${FOLLOWS_SELECT} ORDER BY f.id DESC LIMIT ? OFFSET ?`, [limit, offset]);
  res.json({ ok: true, total, follows: rows.map(followRow) });
});

// ── Demo activity (testing only) ──
//
// Calls only connect between two real devices, and following and chatting
// need a call first. This gives one account a few demo people it is already
// connected to, so those screens can be tried. Off in production.
const demoEnabled = () => process.env.NODE_ENV !== 'production';

const DEMO_PEOPLE = [
  // Numbers start with 5, so they're never real Indian mobiles and never get an SMS.
  // Mutual follow with a short chat: shows under Chats.
  { role: 'friend', phone: '+915550000001', name: 'Priya', age: 23, gender: 'female', city: 'Mumbai' },
  // Follows you: shows under followers; follow back to make a friend.
  { role: 'follower', phone: '+915550000002', name: 'Rahul', age: 26, gender: 'male', city: 'Delhi' },
  // Only a past call: follow her from call history; she has reported you.
  { role: 'caller', phone: '+915550000003', name: 'Meera', age: 24, gender: 'female', city: 'Bengaluru' },
];

router.post('/users/:id/demo-activity', (req, res) => {
  if (!demoEnabled()) return res.status(403).json({ ok: false, error: 'Demo activity is off in production' });
  const me = db.get('SELECT * FROM users WHERE id = ?', [Number(req.params.id)]);
  if (!me) return res.status(404).json({ ok: false, error: 'User not found' });
  if (!me.profile_completed) return res.status(400).json({ ok: false, error: 'This user hasn\'t finished signing up' });
  const id = Number(me.id);

  const people = [];
  DEMO_PEOPLE.forEach((p, i) => {
    if (p.phone === me.phone) return;
    let demo = db.get('SELECT * FROM users WHERE phone = ?', [p.phone]);
    if (!demo) {
      const newId = db.insert(
        `INSERT INTO users (phone, name, age, gender, city, country, country_code, profile_completed, last_seen)
         VALUES (?, ?, ?, ?, ?, 'India', 'IN', 1, datetime('now'))`,
        [p.phone, p.name, p.age, p.gender, p.city]
      );
      demo = db.get('SELECT * FROM users WHERE id = ?', [newId]);
    }
    const did = Number(demo.id);
    db.run('DELETE FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)', [id, did, did, id]);

    // A finished random call, which is what allows following and voting.
    if (!rel.hadCall(id, did)) {
      const seconds = 180 + i * 150;
      const ago = `-${(i + 1) * 3} hours`;
      db.insert(
        `INSERT INTO calls (caller_id, callee_id, room_id, kind, status, duration_seconds, started_at, ended_at)
         VALUES (?, ?, ?, 'random', 'completed', ?, datetime('now', ?), datetime('now', ?, ?))`,
        [did, id, `demo_${did}_${id}`, seconds, ago, ago, `+${seconds} seconds`]
      );
    }

    if (p.role === 'friend' || p.role === 'follower') {
      db.run('INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [did, id]);
      db.run('INSERT OR REPLACE INTO votes (voter_id, target_id, value) VALUES (?, ?, 1)', [did, id]);
    }
    if (p.role === 'friend') {
      db.run('INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [id, did]);
      const chatted = db.get(
        'SELECT 1 FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)',
        [id, did, did, id]
      );
      if (!chatted) {
        const lines = [
          [did, id, 'Hey! Loved talking to you earlier 😊', '-150 minutes', true],
          [id, did, 'Haha same, that was fun!', '-140 minutes', true],
          [did, id, 'Call again tonight?', '-20 minutes', false],
        ];
        for (const [from, to, text, at, read] of lines) {
          db.insert(
            `INSERT INTO messages (sender_id, receiver_id, text, read_at, created_at)
             VALUES (?, ?, ?, ${read ? "datetime('now', ?)" : 'NULL'}, datetime('now', ?))`,
            read ? [from, to, text, at, at] : [from, to, text, at]
          );
        }
      }
    }
    if (p.role === 'caller' && !db.get('SELECT 1 FROM reports WHERE reporter_id = ? AND reported_id = ?', [did, id])) {
      db.insert('INSERT INTO reports (reporter_id, reported_id, reason) VALUES (?, ?, ?)', [did, id, 'Demo report (testing)']);
    }
    people.push({ id: did, name: demo.name, role: p.role });
  });

  res.json({ ok: true, people });
});

// ── Settings ──

router.post('/users/:id/ban', (req, res) => {
  const u = db.get('SELECT * FROM users WHERE id = ?', [Number(req.params.id)]);
  if (!u) return res.status(404).json({ ok: false, error: 'User not found' });
  const reason = String(req.body.reason || '').trim().slice(0, 200);
  db.run('INSERT OR REPLACE INTO banned_phones (phone, reason) VALUES (?, ?)', [u.phone, reason]);
  // Out of the queue now; every later request is refused by the auth middleware.
  db.run('DELETE FROM match_queue WHERE user_id = ?', [u.id]);
  db.run('UPDATE users SET is_online = 0 WHERE id = ?', [u.id]);
  res.json({ ok: true });
});

router.delete('/users/:id/ban', (req, res) => {
  const u = db.get('SELECT * FROM users WHERE id = ?', [Number(req.params.id)]);
  if (!u) return res.status(404).json({ ok: false, error: 'User not found' });
  db.run('DELETE FROM banned_phones WHERE phone = ?', [u.phone]);
  res.json({ ok: true });
});

router.get('/settings', (_req, res) => {
  res.json({ ok: true, premiumEnabled: content.premiumEnabled() });
});

router.put('/settings', (req, res) => {
  if (typeof req.body.premiumEnabled !== 'boolean') {
    return res.status(400).json({ ok: false, error: 'Body must be { "premiumEnabled": true | false }' });
  }
  content.setContent('premiumEnabled', req.body.premiumEnabled);
  res.json({ ok: true, premiumEnabled: content.premiumEnabled() });
});

// ── Content & plans ──

router.get('/content', (_req, res) => {
  res.json({ ok: true, content: content.allContent(), version: content.version() });
});

router.put('/content/:key', (req, res) => {
  const key = String(req.params.key);
  if (!/^[a-zA-Z0-9_]{1,64}$/.test(key)) return res.status(400).json({ ok: false, error: 'Invalid key' });
  if (req.body.value === undefined) return res.status(400).json({ ok: false, error: 'Body must be { "value": ... }' });
  content.setContent(key, req.body.value);
  res.json({ ok: true, key, value: content.allContent()[key] });
});

router.get('/plans', (_req, res) => {
  res.json({ ok: true, plans: content.plans({ includeInactive: true }) });
});

router.put('/plans/:id', (req, res) => {
  const id = String(req.params.id);
  // New plan IDs must also be valid Google Play product IDs (no hyphens).
  if (!content.plan(id) && !/^[a-z0-9][a-z0-9_.]{0,31}$/.test(id)) {
    return res.status(400).json({ ok: false, error: 'Plan id: lowercase letters, digits, _ and . only' });
  }
  const fields = {};
  for (const k of ['title', 'amountPaise', 'days', 'badge', 'sortOrder', 'active']) {
    if (req.body[k] !== undefined) fields[k] = req.body[k];
  }
  try {
    res.json({ ok: true, plan: content.savePlan(id, fields) });
  } catch (err) {
    res.status(err.status || 500).json({ ok: false, error: err.message });
  }
});

router.get('/reports', (_req, res) => {
  const rows = db.all(
    `SELECT r.id, r.reason, r.created_at,
            r.reporter_id, a.name AS reporter_name,
            r.reported_id, b.name AS reported_name, b.phone AS reported_phone,
            (SELECT COUNT(*) FROM reports x WHERE x.reported_id = r.reported_id) AS total_reports
     FROM reports r
     JOIN users a ON a.id = r.reporter_id
     JOIN users b ON b.id = r.reported_id
     ORDER BY r.id DESC LIMIT 200`
  );
  res.json({ ok: true, reports: rows });
});

module.exports = router;
