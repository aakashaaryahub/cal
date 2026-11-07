// Random-stranger matchmaking.
//
// Clients POST /join, then poll GET /status every ~1.5s. When two compatible
// users are waiting, a call row with a shared room name is created; the user
// whose request made the match gets it immediately, the other one on their
// next poll. Each gets the Daily room URL and their own meeting token.
// Entries that stop polling are treated as gone.
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const content = require('../content');
const daily = require('../daily');
const rel = require('../relations');

const router = express.Router();

const STALE_MS = 10 * 1000;
const FILTERS = ['any', 'male', 'female'];

function blockedIds(userId) {
  return db
    .all(
      `SELECT blocked_id AS id FROM blocks WHERE blocker_id = ?
       UNION
       SELECT blocker_id AS id FROM blocks WHERE blocked_id = ?`,
      [userId, userId]
    )
    .map((r) => Number(r.id));
}

function accepts(filter, gender) {
  return filter === 'any' || filter === gender;
}

function tryMatch(me) {
  const blocked = blockedIds(me.user_id);
  const candidates = db.all(
    `SELECT * FROM match_queue
     WHERE user_id != ? AND matched_call_id IS NULL AND last_poll > ?
     ORDER BY joined_at ASC`,
    [me.user_id, Date.now() - STALE_MS]
  );
  const other = candidates.find(
    (c) =>
      !blocked.includes(Number(c.user_id)) &&
      accepts(me.gender_filter, c.gender) &&
      accepts(c.gender_filter, me.gender)
  );
  if (!other) return null;

  const roomId = `vx_${crypto.randomBytes(8).toString('hex')}`;
  const callId = db.insert(
    `INSERT INTO calls (caller_id, callee_id, room_id, status, gender_filter)
     VALUES (?, ?, ?, 'connected', ?)`,
    [me.user_id, other.user_id, roomId, me.gender_filter]
  );
  db.run('UPDATE match_queue SET matched_call_id = ? WHERE user_id = ?', [callId, other.user_id]);
  db.run('DELETE FROM match_queue WHERE user_id = ?', [me.user_id]);
  return callId;
}

async function matchedPayload(callId, user) {
  const call = db.get('SELECT * FROM calls WHERE id = ?', [callId]);
  const peerId = Number(call.caller_id) === Number(user.id) ? call.callee_id : call.caller_id;
  const peer = db.get('SELECT * FROM users WHERE id = ?', [peerId]);
  const { roomUrl, token } = await daily.joinInfo(call.room_id, user);
  return {
    ok: true,
    status: 'matched',
    call: { id: Number(call.id), roomId: call.room_id, roomUrl, token },
    peer: rel.profileFor(user.id, peer),
  };
}

async function sendMatch(res, callId, user) {
  try {
    res.json(await matchedPayload(callId, user));
  } catch (err) {
    if (!(err instanceof daily.CallSetupError)) throw err;
    // Nobody can join this room: close the call instead of leaving it open.
    db.run(`UPDATE calls SET status = 'missed', ended_at = datetime('now') WHERE id = ? AND ended_at IS NULL`, [callId]);
    res.status(503).json({ ok: false, code: 'CALL_SETUP_FAILED', error: err.message });
  }
}

function waitingCount() {
  const row = db.get(
    'SELECT COUNT(*) AS c FROM match_queue WHERE matched_call_id IS NULL AND last_poll > ?',
    [Date.now() - STALE_MS]
  );
  return Number(row.c);
}

router.post('/join', auth, (req, res, next) => {
  if (!daily.isConfigured()) {
    return res.status(503).json({ ok: false, code: 'CALL_SETUP_FAILED', error: 'Voice calls aren\'t set up on the server yet.' });
  }
  const filter = String(req.body.genderFilter || 'any').toLowerCase();
  if (!FILTERS.includes(filter)) {
    return res.status(400).json({ ok: false, error: 'Invalid gender filter' });
  }
  if (filter !== 'any' && content.premiumEnabled() && !db.isPremium(req.user)) {
    return res.status(403).json({
      ok: false,
      error: 'Choosing who you talk to is a Premium feature',
      code: 'PREMIUM_REQUIRED',
    });
  }
  if (!req.user.profile_completed) {
    return res.status(400).json({ ok: false, error: 'Complete your profile first' });
  }

  const now = Date.now();
  db.run('DELETE FROM match_queue WHERE user_id = ?', [req.user.id]);
  db.insert(
    `INSERT INTO match_queue (user_id, gender, gender_filter, joined_at, last_poll)
     VALUES (?, ?, ?, ?, ?)`,
    [req.user.id, req.user.gender, filter, now, now]
  );

  const me = db.get('SELECT * FROM match_queue WHERE user_id = ?', [req.user.id]);
  const callId = tryMatch(me);
  if (callId) return sendMatch(res, callId, req.user).catch(next);
  res.json({ ok: true, status: 'searching', waiting: waitingCount() });
});

router.get('/status', auth, (req, res, next) => {
  const me = db.get('SELECT * FROM match_queue WHERE user_id = ?', [req.user.id]);
  if (!me) return res.json({ ok: true, status: 'idle' });

  if (me.matched_call_id) {
    db.run('DELETE FROM match_queue WHERE user_id = ?', [req.user.id]);
    return sendMatch(res, me.matched_call_id, req.user).catch(next);
  }

  db.run('UPDATE match_queue SET last_poll = ? WHERE user_id = ?', [Date.now(), req.user.id]);
  const callId = tryMatch({ ...me, last_poll: Date.now() });
  if (callId) return sendMatch(res, callId, req.user).catch(next);
  res.json({ ok: true, status: 'searching', waiting: waitingCount() });
});

router.delete('/', auth, (req, res) => {
  db.run('DELETE FROM match_queue WHERE user_id = ?', [req.user.id]);
  res.json({ ok: true });
});

router.get('/online-count', auth, (_req, res) => {
  const row = db.get(
    `SELECT COUNT(*) AS c FROM users
     WHERE profile_completed = 1 AND last_seen > datetime('now', '-10 minutes')`
  );
  res.json({ ok: true, count: Number(row.c) });
});

module.exports = router;
