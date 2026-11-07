const jwt = require('jsonwebtoken');
const db = require('../db');

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ ok: false, error: 'Unauthorized' });
  }
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET || 'voxlink-dev-secret');
    const user = db.get('SELECT * FROM users WHERE id = ?', [payload.userId]);
    if (!user) return res.status(401).json({ ok: false, error: 'Unauthorized' });
    db.run(`UPDATE users SET last_seen = datetime('now') WHERE id = ?`, [user.id]);
    req.user = user;
    next();
  } catch {
    return res.status(401).json({ ok: false, error: 'Unauthorized' });
  }
}

function signToken(userId) {
  return jwt.sign(
    { userId },
    process.env.JWT_SECRET || 'voxlink-dev-secret',
    { expiresIn: '30d' }
  );
}

module.exports = { auth, signToken };
