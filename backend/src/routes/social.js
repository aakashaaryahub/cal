// Follows, votes and the friends/chats overview.
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const rel = require('../relations');

const router = express.Router();

/** Loads the target user and checks the viewer may act on them. */
function target(req, res) {
  const id = Number(req.params.id);
  const user = id && id !== Number(req.user.id) ? db.get('SELECT * FROM users WHERE id = ?', [id]) : null;
  if (!user || rel.isBlocked(req.user.id, id)) {
    res.status(404).json({ ok: false, error: 'User not found' });
    return null;
  }
  return user;
}

router.post('/follows/:id', auth, (req, res) => {
  const user = target(req, res);
  if (!user) return;
  if (!rel.hadCall(req.user.id, user.id)) {
    return res.status(403).json({ ok: false, error: 'You can only follow people you\'ve talked to' });
  }
  db.run('INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [req.user.id, user.id]);
  res.json({ ok: true, profile: rel.profileFor(req.user.id, user) });
});

router.delete('/follows/:id', auth, (req, res) => {
  const user = target(req, res);
  if (!user) return;
  db.run('DELETE FROM follows WHERE follower_id = ? AND following_id = ?', [req.user.id, user.id]);
  res.json({ ok: true, profile: rel.profileFor(req.user.id, user) });
});

// value: 1 (upvote), -1 (downvote) or 0 (remove vote)
router.post('/votes/:id', auth, (req, res) => {
  const user = target(req, res);
  if (!user) return;
  const value = Number(req.body.value);
  if (![1, -1, 0].includes(value)) return res.status(400).json({ ok: false, error: 'Invalid vote' });
  if (!rel.hadCall(req.user.id, user.id)) {
    return res.status(403).json({ ok: false, error: 'You can only vote on people you\'ve talked to' });
  }
  db.run('DELETE FROM votes WHERE voter_id = ? AND target_id = ?', [req.user.id, user.id]);
  if (value !== 0) {
    db.run('INSERT INTO votes (voter_id, target_id, value) VALUES (?, ?, ?)', [req.user.id, user.id, value]);
  }
  res.json({ ok: true, profile: rel.profileFor(req.user.id, user) });
});

/**
 * Everything the Chats tab needs:
 *  friends   - mutual followers, newest conversation first, with unread counts
 *  followers - people who follow you that you haven't followed back
 */
router.get('/follows', auth, (req, res) => {
  const me = req.user.id;
  const friendRows = db.all(
    `SELECT u.* FROM users u
     JOIN follows a ON a.following_id = u.id AND a.follower_id = ?
     JOIN follows b ON b.follower_id = u.id AND b.following_id = ?`,
    [me, me]
  );
  const friends = friendRows
    .filter((u) => !rel.isBlocked(me, u.id))
    .map((u) => {
      const last = db.get(
        `SELECT * FROM messages
         WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
         ORDER BY id DESC LIMIT 1`,
        [me, u.id, u.id, me]
      );
      const unread = db.get(
        'SELECT COUNT(*) AS c FROM messages WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL',
        [u.id, me]
      );
      return {
        user: db.peerUser(u),
        lastMessage: last
          ? { text: last.text, fromMe: Number(last.sender_id) === Number(me), createdAt: last.created_at }
          : null,
        unread: Number(unread.c),
      };
    })
    .sort((a, b) => (b.lastMessage?.createdAt || '').localeCompare(a.lastMessage?.createdAt || ''));

  const followerRows = db.all(
    `SELECT u.* FROM users u
     JOIN follows f ON f.follower_id = u.id AND f.following_id = ?
     WHERE u.id NOT IN (SELECT following_id FROM follows WHERE follower_id = ?)
     ORDER BY f.created_at DESC`,
    [me, me]
  );
  const followers = followerRows.filter((u) => !rel.isBlocked(me, u.id)).map((u) => db.peerUser(u));

  res.json({ ok: true, friends, followers, unreadTotal: friends.reduce((n, f) => n + f.unread, 0) });
});

module.exports = router;
