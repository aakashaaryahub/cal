const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const rel = require('../relations');
const content = require('../content');
const invites = require('../invites');

const router = express.Router();

router.get('/me', auth, (req, res) => {
  res.json({ ok: true, user: db.publicUser(req.user) });
});

router.put('/me', auth, (req, res) => {
  const name = String(req.body.name || '').trim().slice(0, 40);
  const age = Number(req.body.age);
  const city = String(req.body.city || '').trim().slice(0, 60);
  const country = String(req.body.country || '').trim().slice(0, 60);
  const countryCode = String(req.body.countryCode || '').trim().toUpperCase().slice(0, 2);
  const gender = String(req.body.gender || '').trim().toLowerCase();
  const bio = String(req.body.bio ?? req.user.bio ?? '').trim().slice(0, 120);

  if (name.length < 2) return res.status(400).json({ ok: false, error: 'Please enter your name' });
  if (!Number.isInteger(age) || age < 18 || age > 99) {
    return res.status(400).json({ ok: false, error: 'You must be 18 or older to use VoxLink' });
  }
  if (!city) return res.status(400).json({ ok: false, error: 'Please enter your city' });
  if (!country) return res.status(400).json({ ok: false, error: 'Please select your country' });
  if (!['male', 'female', 'other'].includes(gender)) {
    return res.status(400).json({ ok: false, error: 'Please select your gender' });
  }

  // An invite code only counts while signing up, and must exist.
  const inviteCode = req.body.inviteCode ? String(req.body.inviteCode) : '';
  const firstTime = !req.user.profile_completed;
  if (inviteCode && firstTime && !invites.inviterFor(inviteCode)) {
    return res.status(400).json({ ok: false, code: 'BAD_INVITE', error: 'That invite code doesn\'t exist' });
  }

  db.run(
    `UPDATE users
     SET name = ?, age = ?, city = ?, country = ?, country_code = ?, gender = ?, bio = ?,
         profile_completed = 1
     WHERE id = ?`,
    [name, age, city, country, countryCode, gender, bio, req.user.id]
  );
  if (inviteCode && firstTime) invites.redeem(req.user, inviteCode);

  const user = db.get('SELECT * FROM users WHERE id = ?', [req.user.id]);
  res.json({ ok: true, user: db.publicUser(user) });
});

// Who the user wants to be matched with. Anything but 'any' needs Premium.
router.put('/me/preferences', auth, (req, res) => {
  const genderPreference = String(req.body.genderPreference || '').trim().toLowerCase();
  if (!['any', 'female', 'male'].includes(genderPreference)) {
    return res.status(400).json({ ok: false, error: 'Invalid preference' });
  }
  if (genderPreference !== 'any' && content.premiumEnabled() && !db.isPremium(req.user)) {
    return res.status(403).json({ ok: false, code: 'PREMIUM_REQUIRED', error: 'Choosing who you talk to needs Premium' });
  }
  db.run('UPDATE users SET gender_preference = ? WHERE id = ?', [genderPreference, req.user.id]);
  const user = db.get('SELECT * FROM users WHERE id = ?', [req.user.id]);
  res.json({ ok: true, user: db.publicUser(user) });
});

router.get('/me/stats', auth, (req, res) => {
  const row = db.get(
    `SELECT COUNT(*) AS calls, COALESCE(SUM(duration_seconds), 0) AS seconds
     FROM calls
     WHERE (caller_id = ? OR callee_id = ?) AND status = 'completed'`,
    [req.user.id, req.user.id]
  );
  const countries = db.get(
    `SELECT COUNT(DISTINCT u.country) AS c
     FROM calls c
     JOIN users u ON u.id = CASE WHEN c.caller_id = ? THEN c.callee_id ELSE c.caller_id END
     WHERE (c.caller_id = ? OR c.callee_id = ?) AND c.status = 'completed' AND u.country != ''`,
    [req.user.id, req.user.id, req.user.id]
  );
  res.json({
    ok: true,
    stats: {
      calls: Number(row.calls),
      minutes: Math.round(Number(row.seconds) / 60),
      countries: Number(countries.c),
      ...rel.stats(req.user.id),
    },
  });
});

// Your invite code and how many people joined with it.
router.get('/me/invite', auth, (req, res) => {
  res.json({ ok: true, code: invites.codeFor(req.user), joined: invites.joinedCount(req.user.id) });
});

// Public, so the signup screen can check a code before the account exists.
router.get('/invites/:code', (req, res) => {
  const inviter = invites.inviterFor(req.params.code);
  if (!inviter) return res.status(404).json({ ok: false, error: 'That invite code doesn\'t exist' });
  res.json({ ok: true, inviter: { name: inviter.name.split(' ')[0] } });
});

// Another user's public card and your relationship with them.
// Permanently deletes the account and everything tied to it (Play requires
// in-app deletion). Payment records stay, with no personal data, for accounting.
router.delete('/me', auth, (req, res) => {
  const id = req.user.id;
  const pairs = [
    ['messages', 'sender_id', 'receiver_id'],
    ['votes', 'voter_id', 'target_id'],
    ['follows', 'follower_id', 'following_id'],
    ['blocks', 'blocker_id', 'blocked_id'],
    ['reports', 'reporter_id', 'reported_id'],
    ['calls', 'caller_id', 'callee_id'],
  ];
  for (const [table, a, b] of pairs) db.run(`DELETE FROM ${table} WHERE ${a} = ? OR ${b} = ?`, [id, id]);
  db.run('DELETE FROM subscriptions WHERE user_id = ?', [id]);
  db.run('DELETE FROM match_queue WHERE user_id = ?', [id]);
  db.run('DELETE FROM otps WHERE phone = ?', [req.user.phone]);
  db.run('UPDATE users SET invited_by = NULL WHERE invited_by = ?', [id]);
  db.run('DELETE FROM users WHERE id = ?', [id]);
  res.json({ ok: true });
});

router.get('/:id', auth, (req, res) => {
  const id = Number(req.params.id);
  const user = id ? db.get('SELECT * FROM users WHERE id = ?', [id]) : null;
  if (!user || rel.isBlocked(req.user.id, id)) {
    return res.status(404).json({ ok: false, error: 'User not found' });
  }
  res.json({ ok: true, profile: rel.profileFor(req.user.id, user) });
});

module.exports = router;
