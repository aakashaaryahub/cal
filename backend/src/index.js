require('dotenv').config();
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const db = require('./db');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const matchRoutes = require('./routes/match');
const callRoutes = require('./routes/calls');
const subscriptionRoutes = require('./routes/subscriptions');
const reportRoutes = require('./routes/reports');
const socialRoutes = require('./routes/social');
const chatRoutes = require('./routes/chats');
const directCallRoutes = require('./routes/direct');
const leaderboardRoutes = require('./routes/leaderboard');
const configRoutes = require('./routes/config');
const adminRoutes = require('./routes/admin');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// The app pings /api/health to tell whether the server is up.
const health = (_req, res) => res.json({ ok: true, service: 'voxlink-api' });
app.get('/health', health);
app.get('/api/health', health);

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/match', matchRoutes);
app.use('/api/calls', callRoutes);
app.use('/api/subscriptions', subscriptionRoutes);
app.use('/api', reportRoutes);
app.use('/api', socialRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/direct-calls', directCallRoutes);
app.use('/api/leaderboard', leaderboardRoutes);
app.use('/api/app-config', configRoutes);
app.use('/api/admin', adminRoutes);

// Admin dashboard (signs in against /api/admin/login).
app.use('/admin', express.static(path.join(__dirname, '..', 'admin')));

// Public pages linked from the Play listing: home page, privacy policy, terms, child safety standards and web account deletion.
const publicDir = path.join(__dirname, '..', 'public');
app.use('/public', express.static(publicDir));
const supportEmail = String(process.env.SUPPORT_EMAIL || '').replace(/[^\w.+@-]/g, '');
for (const page of ['index', 'privacy', 'terms', 'child-safety', 'delete-account']) {
  const html = fs.readFileSync(path.join(publicDir, `${page}.html`), 'utf8').replaceAll('{{SUPPORT_EMAIL}}', supportEmail);
  app.get(page === 'index' ? '/' : `/${page}`, (_req, res) => res.type('html').send(html));
}

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ ok: false, error: 'Server error' });
});

db.init()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`VoxLink API running on http://0.0.0.0:${PORT}`);
      if (!require('./sms').smsConfigured()) console.log('SMS not configured: OTPs are printed here');
      require('./daily').describeDomain().then((line) => console.log(line));
    });
  })
  .catch((err) => {
    console.error('Failed to start database', err);
    process.exit(1);
  });
