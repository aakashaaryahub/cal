// Leaderboards: today's total talk time, and all-time followers.
//
// "Today" is measured in LEADERBOARD_UTC_OFFSET_MINUTES (default 330 = IST),
// so the board resets at local midnight rather than UTC midnight.
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');

const router = express.Router();
const LIMIT = 50;

function offset() {
  const minutes = Number(process.env.LEADERBOARD_UTC_OFFSET_MINUTES ?? 330);
  return `${minutes >= 0 ? '+' : ''}${minutes} minutes`;
}

function talkTimeToday() {
  const off = offset();
  return db.all(
    `SELECT user_id, SUM(duration_seconds) AS seconds FROM (
       SELECT caller_id AS user_id, duration_seconds, started_at FROM calls WHERE status = 'completed'
       UNION ALL
       SELECT callee_id AS user_id, duration_seconds, started_at FROM calls WHERE status = 'completed'
     )
     WHERE datetime(started_at, ?) >= datetime('now', ?, 'start of day')
     GROUP BY user_id
     HAVING seconds > 0
     ORDER BY seconds DESC, user_id ASC`,
    [off, off]
  );
}

function followerCounts() {
  return db.all(
    `SELECT following_id AS user_id, COUNT(*) AS followers
     FROM follows GROUP BY following_id
     ORDER BY followers DESC, user_id ASC`
  );
}

function withUsers(rows, valueKey) {
  return rows.slice(0, LIMIT).map((r, i) => ({
    rank: i + 1,
    user: db.peerUser(db.get('SELECT * FROM users WHERE id = ?', [r.user_id])),
    value: Number(r[valueKey]),
  }));
}

function myEntry(rows, userId, valueKey) {
  const i = rows.findIndex((r) => Number(r.user_id) === Number(userId));
  return i === -1 ? { rank: null, value: 0 } : { rank: i + 1, value: Number(rows[i][valueKey]) };
}

router.get('/', auth, (req, res) => {
  const talk = talkTimeToday();
  const followers = followerCounts();
  res.json({
    ok: true,
    talkTime: withUsers(talk, 'seconds'),
    followers: withUsers(followers, 'followers'),
    me: {
      talkTime: myEntry(talk, req.user.id, 'seconds'),
      followers: myEntry(followers, req.user.id, 'followers'),
    },
  });
});

module.exports = router;
