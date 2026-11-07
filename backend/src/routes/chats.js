// Text chat between mutual followers. The app polls with ?after=<lastId>.
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const rel = require('../relations');

const router = express.Router();

function formatMessage(m, me) {
  return {
    id: Number(m.id),
    text: m.text,
    fromMe: Number(m.sender_id) === Number(me),
    createdAt: m.created_at,
    readAt: m.read_at,
  };
}

function friendOr403(req, res) {
  const other = Number(req.params.id);
  if (!other || !rel.areFriends(req.user.id, other)) {
    res.status(403).json({
      ok: false,
      error: 'You can chat once you both follow each other',
      code: 'NOT_FRIENDS',
    });
    return null;
  }
  return other;
}

router.get('/:id/messages', auth, (req, res) => {
  const other = friendOr403(req, res);
  if (!other) return;
  const me = req.user.id;
  const after = Number(req.query.after) || 0;
  const rows = after
    ? db.all(
        `SELECT * FROM messages
         WHERE id > ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
         ORDER BY id ASC`,
        [after, me, other, other, me]
      )
    : db
        .all(
          `SELECT * FROM messages
           WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
           ORDER BY id DESC LIMIT 100`,
          [me, other, other, me]
        )
        .reverse();

  db.run(
    `UPDATE messages SET read_at = datetime('now')
     WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL`,
    [other, me]
  );
  // The newest message I sent that they've read, for "Seen" receipts.
  const seen = db.get(
    `SELECT MAX(id) AS id FROM messages WHERE sender_id = ? AND receiver_id = ? AND read_at IS NOT NULL`,
    [me, other]
  );
  res.json({
    ok: true,
    messages: rows.map((m) => formatMessage(m, me)),
    seenUpTo: Number(seen?.id || 0),
  });
});

router.post('/:id/messages', auth, (req, res) => {
  const other = friendOr403(req, res);
  if (!other) return;
  const text = String(req.body.text || '').trim().slice(0, 1000);
  if (!text) return res.status(400).json({ ok: false, error: 'Message is empty' });
  const id = db.insert('INSERT INTO messages (sender_id, receiver_id, text) VALUES (?, ?, ?)', [
    req.user.id,
    other,
    text,
  ]);
  res.json({ ok: true, message: formatMessage(db.get('SELECT * FROM messages WHERE id = ?', [id]), req.user.id) });
});

module.exports = router;
