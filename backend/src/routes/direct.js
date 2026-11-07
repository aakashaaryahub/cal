// Calling a friend directly.
//
// Caller POSTs /direct-calls -> a 'ringing' call row. The callee's app polls
// /incoming and shows a ringing screen; accept/decline updates the row, and
// the caller polls GET /:id to learn the outcome. Unanswered calls become
// 'missed' after RING_SECONDS.
//
// Polling only works while the callee has the app open. Ringing a closed app
// needs push notifications (FCM / APNs VoIP), which this doesn't include.
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const rel = require('../relations');
const daily = require('../daily');

const router = express.Router();
const RING_SECONDS = 35;

function expireStale() {
  db.run(
    `UPDATE calls SET status = 'missed', ended_at = datetime('now')
     WHERE kind = 'direct' AND status = 'ringing'
       AND started_at < datetime('now', ?)`,
    [`-${RING_SECONDS} seconds`]
  );
}

// Once connected, each side also gets the Daily room URL and its own token.
async function payload(call, viewer) {
  const peerId = Number(call.caller_id) === Number(viewer.id) ? call.callee_id : call.caller_id;
  const connected = call.status === 'connected';
  const join = connected ? await daily.joinInfo(call.room_id, viewer) : null;
  return {
    id: Number(call.id),
    status: call.status,
    roomId: connected ? call.room_id : null,
    roomUrl: join?.roomUrl ?? null,
    token: join?.token ?? null,
    peer: db.peerUser(db.get('SELECT * FROM users WHERE id = ?', [peerId])),
  };
}

// Sends the call, or a 503 when its voice room can't be set up.
async function sendCall(res, call, viewer) {
  try {
    res.json({ ok: true, call: await payload(call, viewer) });
  } catch (err) {
    if (!(err instanceof daily.CallSetupError)) throw err;
    res.status(503).json({ ok: false, code: 'CALL_SETUP_FAILED', error: err.message });
  }
}

function myCall(req, res) {
  expireStale();
  const call = db.get(`SELECT * FROM calls WHERE id = ? AND kind = 'direct'`, [Number(req.params.id)]);
  const mine = call && [Number(call.caller_id), Number(call.callee_id)].includes(Number(req.user.id));
  if (!mine) {
    res.status(404).json({ ok: false, error: 'Call not found' });
    return null;
  }
  return call;
}

router.post('/', auth, (req, res, next) => {
  if (!daily.isConfigured()) {
    return res.status(503).json({ ok: false, code: 'CALL_SETUP_FAILED', error: 'Voice calls aren\'t set up on the server yet.' });
  }
  const calleeId = Number(req.body.userId);
  if (!calleeId || !rel.areFriends(req.user.id, calleeId)) {
    return res.status(403).json({ ok: false, error: 'You can call once you both follow each other', code: 'NOT_FRIENDS' });
  }
  expireStale();
  // Cancel anything this caller left ringing.
  db.run(
    `UPDATE calls SET status = 'cancelled', ended_at = datetime('now')
     WHERE kind = 'direct' AND status = 'ringing' AND caller_id = ?`,
    [req.user.id]
  );
  const roomId = `vxd_${crypto.randomBytes(8).toString('hex')}`;
  const id = db.insert(
    `INSERT INTO calls (caller_id, callee_id, room_id, kind, status) VALUES (?, ?, ?, 'direct', 'ringing')`,
    [req.user.id, calleeId, roomId]
  );
  sendCall(res, db.get('SELECT * FROM calls WHERE id = ?', [id]), req.user).catch(next);
});

router.get('/incoming', auth, (req, res, next) => {
  expireStale();
  const call = db.get(
    `SELECT * FROM calls WHERE kind = 'direct' AND status = 'ringing' AND callee_id = ? ORDER BY id DESC LIMIT 1`,
    [req.user.id]
  );
  if (!call) return res.json({ ok: true, call: null });
  sendCall(res, call, req.user).catch(next);
});

router.get('/:id', auth, (req, res, next) => {
  const call = myCall(req, res);
  if (call) sendCall(res, call, req.user).catch(next);
});

router.post('/:id/accept', auth, (req, res, next) => {
  const call = myCall(req, res);
  if (!call) return;
  if (Number(call.callee_id) !== Number(req.user.id) || call.status !== 'ringing') {
    return res.status(409).json({ ok: false, error: 'This call is no longer ringing' });
  }
  db.run(`UPDATE calls SET status = 'connected', started_at = datetime('now') WHERE id = ?`, [call.id]);
  sendCall(res, db.get('SELECT * FROM calls WHERE id = ?', [call.id]), req.user).catch(next);
});

router.post('/:id/decline', auth, (req, res) => {
  const call = myCall(req, res);
  if (!call) return;
  if (call.status === 'ringing') {
    const status = Number(call.caller_id) === Number(req.user.id) ? 'cancelled' : 'declined';
    db.run(`UPDATE calls SET status = ?, ended_at = datetime('now') WHERE id = ?`, [status, call.id]);
  }
  res.json({ ok: true });
});

module.exports = router;
