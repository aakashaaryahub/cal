// Invite codes: anyone who signs up with your code becomes your friend right
// away (a mutual follow), so you can chat and call without meeting on a random
// call first. Codes look like AAKASH427 and are created the first time a user
// opens their invite.
const crypto = require('crypto');
const db = require('./db');

const CODE_RE = /^[A-Z0-9]{4,16}$/;

function normalize(code) {
  const c = String(code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  return CODE_RE.test(c) ? c : null;
}

/** The user's code, created on first use. */
function codeFor(user) {
  if (user.invite_code) return user.invite_code;
  const base = String(user.name || '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 6) || 'VOX';
  for (let i = 0; i < 20; i++) {
    const code = base + crypto.randomInt(100, 1000);
    if (!db.get('SELECT 1 FROM users WHERE invite_code = ?', [code])) {
      db.run('UPDATE users SET invite_code = ? WHERE id = ?', [code, user.id]);
      return code;
    }
  }
  const code = 'VOX' + crypto.randomBytes(4).toString('hex').toUpperCase();
  db.run('UPDATE users SET invite_code = ? WHERE id = ?', [code, user.id]);
  return code;
}

function inviterFor(code) {
  const c = normalize(code);
  return c ? db.get('SELECT * FROM users WHERE invite_code = ? AND profile_completed = 1', [c]) : null;
}

/**
 * Links a new user to whoever invited them and makes them friends.
 * Only for users who haven't been invited before; returns the inviter or null.
 */
function redeem(newUser, code) {
  const inviter = inviterFor(code);
  if (!inviter || Number(inviter.id) === Number(newUser.id) || newUser.invited_by) return null;
  db.run('UPDATE users SET invited_by = ? WHERE id = ?', [inviter.id, newUser.id]);
  db.run('INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [inviter.id, newUser.id]);
  db.run('INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [newUser.id, inviter.id]);
  return inviter;
}

function joinedCount(userId) {
  return Number(db.get('SELECT COUNT(*) AS n FROM users WHERE invited_by = ? AND profile_completed = 1', [userId]).n);
}

module.exports = { normalize, codeFor, inviterFor, redeem, joinedCount };
