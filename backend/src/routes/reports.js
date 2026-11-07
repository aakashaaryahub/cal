const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');

const router = express.Router();

router.post('/reports', auth, (req, res) => {
  const reportedId = Number(req.body.userId);
  const reason = String(req.body.reason || '').trim();
  if (!reportedId || !reason) {
    return res.status(400).json({ ok: false, error: 'User and reason are required' });
  }
  db.insert(
    'INSERT INTO reports (reporter_id, reported_id, reason) VALUES (?, ?, ?)',
    [req.user.id, reportedId, reason]
  );
  res.json({ ok: true, message: 'Report submitted' });
});

router.post('/blocks', auth, (req, res) => {
  const blockedId = Number(req.body.userId);
  if (!blockedId || blockedId === Number(req.user.id)) {
    return res.status(400).json({ ok: false, error: 'Invalid user' });
  }
  db.run(
    'INSERT OR IGNORE INTO blocks (blocker_id, blocked_id) VALUES (?, ?)',
    [req.user.id, blockedId]
  );
  db.run(
    'DELETE FROM follows WHERE (follower_id = ? AND following_id = ?) OR (follower_id = ? AND following_id = ?)',
    [req.user.id, blockedId, blockedId, req.user.id]
  );
  db.run(
    'DELETE FROM votes WHERE (voter_id = ? AND target_id = ?) OR (voter_id = ? AND target_id = ?)',
    [req.user.id, blockedId, blockedId, req.user.id]
  );
  res.json({ ok: true, blocked: true });
});

router.get('/blocks', auth, (req, res) => {
  const rows = db.all(
    `SELECT u.id, u.name, b.created_at
     FROM blocks b
     JOIN users u ON u.id = b.blocked_id
     WHERE b.blocker_id = ?
     ORDER BY b.id DESC`,
    [req.user.id]
  );
  res.json({
    ok: true,
    blocks: rows.map((r) => ({ id: Number(r.id), name: r.name, createdAt: r.created_at })),
  });
});

module.exports = router;
