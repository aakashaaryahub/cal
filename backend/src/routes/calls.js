const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const daily = require('../daily');

const router = express.Router();

function formatCall(row, me) {
  const iAmCaller = Number(row.caller_id) === Number(me);
  const other = db.get('SELECT * FROM users WHERE id = ?', [iAmCaller ? row.callee_id : row.caller_id]);
  return {
    id: Number(row.id),
    peer: db.peerUser(other),
    kind: row.kind || 'random',
    status: row.status,
    durationSeconds: Number(row.duration_seconds || 0),
    startedAt: row.started_at,
    endedAt: row.ended_at,
  };
}

function callForUser(req, res) {
  const call = db.get('SELECT * FROM calls WHERE id = ?', [Number(req.params.id)]);
  if (!call) {
    res.status(404).json({ ok: false, error: 'Call not found' });
    return null;
  }
  const mine = [Number(call.caller_id), Number(call.callee_id)].includes(Number(req.user.id));
  if (!mine) {
    res.status(403).json({ ok: false, error: 'Forbidden' });
    return null;
  }
  return call;
}

router.get('/', auth, (req, res) => {
  const rows = db.all(
    `SELECT * FROM calls
     WHERE (caller_id = ? OR callee_id = ?) AND room_id IS NOT NULL
     ORDER BY id DESC
     LIMIT 50`,
    [req.user.id, req.user.id]
  );
  res.json({ ok: true, calls: rows.map((r) => formatCall(r, req.user.id)) });
});

// Both participants report the end; the longer duration wins. The first
// report also deletes the voice room, which ends it for the other side.
router.patch('/:id/end', auth, (req, res) => {
  const call = callForUser(req, res);
  if (!call) return;
  const duration = Math.max(0, Math.min(6 * 3600, Math.round(Number(req.body.durationSeconds) || 0)));
  const status = duration > 0 ? 'completed' : 'missed';
  db.run(
    `UPDATE calls
     SET status = CASE WHEN status = 'completed' THEN status ELSE ? END,
         duration_seconds = MAX(duration_seconds, ?),
         ended_at = COALESCE(ended_at, datetime('now'))
     WHERE id = ?`,
    [status, duration, call.id]
  );
  daily.deleteRoom(call.room_id);
  res.json({ ok: true, call: formatCall(db.get('SELECT * FROM calls WHERE id = ?', [call.id]), req.user.id) });
});

module.exports = router;
