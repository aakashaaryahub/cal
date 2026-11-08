const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { auth, signToken, BANNED } = require('../middleware/auth');
const { sendOtpSms, smsConfigured, SmsError } = require('../sms');

const router = express.Router();

const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 30 * 1000;
const MAX_ATTEMPTS = 5;

// Phones are stored in E.164 form, e.g. +919876543210.
function normalizePhone(phone) {
  const digits = String(phone || '').replace(/[^\d]/g, '');
  if (digits.length < 8 || digits.length > 15) return null;
  // Indian numbers (+91) are always 10 digits after the country code.
  if (digits.startsWith('91') && digits.length !== 12) return null;
  return `+${digits}`;
}

function hashOtp(phone, code) {
  return crypto.createHash('sha256').update(`${phone}:${code}`).digest('hex');
}

// Logging in (mode: 'login') is only for numbers that finished signing up.
function hasAccount(phone) {
  return Boolean(db.get('SELECT id FROM users WHERE phone = ? AND profile_completed = 1', [phone]));
}

// Google Play's reviewers can't receive our SMS, so one number set on the
// server (REVIEW_PHONE) gets a fixed code (REVIEW_OTP, 6 digits) instead.
function reviewOtp(phone) {
  const reviewPhone = normalizePhone(process.env.REVIEW_PHONE);
  const code = String(process.env.REVIEW_OTP || '');
  return reviewPhone && phone === reviewPhone && /^\d{6}$/.test(code) ? code : null;
}

const NO_ACCOUNT = { ok: false, code: 'NO_ACCOUNT', error: 'No account found with this number. Sign up first.' };

router.post('/otp/send', async (req, res, next) => {
  try {
    const phone = normalizePhone(req.body.phone);
    if (!phone) {
      return res.status(400).json({ ok: false, error: 'Enter a valid phone number (10 digits for India)' });
    }
    if (db.banFor(phone)) return res.status(403).json(BANNED);
    if (req.body.mode === 'login' && !hasAccount(phone)) {
      return res.status(404).json(NO_ACCOUNT);
    }

    const last = db.get('SELECT * FROM otps WHERE phone = ? ORDER BY id DESC LIMIT 1', [phone]);
    if (last && Date.now() - new Date(`${last.created_at.replace(' ', 'T')}Z`).getTime() < RESEND_COOLDOWN_MS) {
      return res.status(429).json({ ok: false, error: 'Please wait a few seconds before requesting another code' });
    }

    const fixedCode = reviewOtp(phone);
    const code = fixedCode || String(crypto.randomInt(0, 1000000)).padStart(6, '0');
    const expires = new Date(Date.now() + OTP_TTL_MS).toISOString();
    db.run('DELETE FROM otps WHERE phone = ?', [phone]);
    db.insert('INSERT INTO otps (phone, code, expires_at) VALUES (?, ?, ?)', [phone, hashOtp(phone, code), expires]);

    try {
      if (!fixedCode) await sendOtpSms(phone, code);
    } catch (err) {
      // The code never arrived: drop it so the user can retry straight away.
      db.run('DELETE FROM otps WHERE phone = ?', [phone]);
      if (err instanceof SmsError) return res.status(502).json({ ok: false, error: err.message });
      throw err;
    }

    const body = { ok: true, message: 'OTP sent', expiresIn: OTP_TTL_MS / 1000 };
    // Without an SMS provider the code is handed back so the app can be tested.
    if (!smsConfigured() && process.env.NODE_ENV !== 'production') body.debugOtp = code;
    res.json(body);
  } catch (err) {
    next(err);
  }
});

router.post('/otp/verify', (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const otp = String(req.body.otp || '').trim();
  if (!phone || !/^\d{6}$/.test(otp)) {
    return res.status(400).json({ ok: false, error: 'Invalid phone or OTP' });
  }
  if (db.banFor(phone)) return res.status(403).json(BANNED);
  // Checked again here so a login can never create an account.
  if (req.body.mode === 'login' && !hasAccount(phone)) {
    return res.status(404).json(NO_ACCOUNT);
  }

  const row = db.get('SELECT * FROM otps WHERE phone = ? ORDER BY id DESC LIMIT 1', [phone]);
  if (!row || new Date(row.expires_at) < new Date()) {
    return res.status(400).json({ ok: false, error: 'OTP expired. Please request a new one' });
  }
  if (Number(row.attempts) >= MAX_ATTEMPTS) {
    return res.status(429).json({ ok: false, error: 'Too many attempts. Please request a new code' });
  }
  if (row.code !== hashOtp(phone, otp)) {
    db.run('UPDATE otps SET attempts = attempts + 1 WHERE id = ?', [row.id]);
    return res.status(400).json({ ok: false, error: 'Incorrect OTP' });
  }

  db.run('DELETE FROM otps WHERE phone = ?', [phone]);

  let user = db.get('SELECT * FROM users WHERE phone = ?', [phone]);
  if (!user) {
    const id = db.insert(
      `INSERT INTO users (phone, is_online, last_seen) VALUES (?, 1, datetime('now'))`,
      [phone]
    );
    user = db.get('SELECT * FROM users WHERE id = ?', [id]);
  } else {
    db.run(`UPDATE users SET is_online = 1, last_seen = datetime('now') WHERE id = ?`, [user.id]);
    user = db.get('SELECT * FROM users WHERE id = ?', [user.id]);
  }

  res.json({ ok: true, token: signToken(user.id), user: db.publicUser(user) });
});

router.get('/me', auth, (req, res) => {
  res.json({ ok: true, user: db.publicUser(req.user) });
});

router.post('/logout', auth, (req, res) => {
  db.run(`UPDATE users SET is_online = 0, last_seen = datetime('now') WHERE id = ?`, [req.user.id]);
  db.run('DELETE FROM match_queue WHERE user_id = ?', [req.user.id]);
  res.json({ ok: true });
});

module.exports = router;
