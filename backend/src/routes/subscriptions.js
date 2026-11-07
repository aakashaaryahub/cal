// Premium plans, sold as consumable Google Play in-app products whose
// product ID equals the plan ID.
//
// Flow: app POSTs /order (checks the plan, returns the mode) -> app buys the
// product through Play Billing -> app POSTs /google-play/verify with the
// purchase token -> server checks it with Google, extends premium once per
// token, and consumes the purchase.
//
// Without Google Play credentials (and outside production) orders are created
// in "dev" mode so the purchase flow can be tested without real money.
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { auth } = require('../middleware/auth');
const content = require('../content');
const googlePlay = require('../googlePlay');

const router = express.Router();

function devPaymentsAllowed() {
  return !googlePlay.configured() && process.env.NODE_ENV !== 'production';
}

// Stacks on top of any premium time the user already has.
function grantPremium(userId, plan) {
  const user = db.get('SELECT * FROM users WHERE id = ?', [userId]);
  const base = db.isPremium(user) ? new Date(user.premium_until) : new Date();
  const expires = new Date(base.getTime() + plan.days * 24 * 60 * 60 * 1000).toISOString();
  db.insert(
    `INSERT INTO subscriptions (user_id, plan, amount, status, expires_at) VALUES (?, ?, ?, 'active', ?)`,
    [userId, plan.id, plan.amountPaise / 100, expires]
  );
  db.run('UPDATE users SET is_premium = 1, premium_until = ? WHERE id = ?', [expires, userId]);
  return db.get('SELECT * FROM users WHERE id = ?', [userId]);
}

router.get('/plans', (_req, res) => {
  res.json({ ok: true, plans: content.plans() });
});

router.get('/me', auth, (req, res) => {
  const user = db.publicUser(req.user);
  res.json({ ok: true, isPremium: user.isPremium, premiumUntil: user.premiumUntil });
});

router.post('/order', auth, (req, res) => {
  if (!content.premiumEnabled()) return res.status(403).json({ ok: false, error: 'Premium isn\'t available right now' });
  const plan = content.plan(req.body.plan);
  if (!plan || !plan.active) return res.status(400).json({ ok: false, error: 'This plan is no longer available' });

  if (googlePlay.configured()) return res.json({ ok: true, mode: 'google_play', productId: plan.id, plan });

  if (!devPaymentsAllowed()) {
    return res.status(503).json({ ok: false, error: 'Payments are not configured' });
  }
  const orderId = `dev_${crypto.randomBytes(6).toString('hex')}`;
  db.insert(
    `INSERT INTO payment_orders (user_id, plan, amount_paise, days, order_id, provider) VALUES (?, ?, ?, ?, ?, 'dev')`,
    [req.user.id, plan.id, plan.amountPaise, plan.days, orderId]
  );
  res.json({ ok: true, mode: 'dev', orderId, amountPaise: plan.amountPaise, currency: 'INR', plan });
});

// Dev-mode purchases only.
router.post('/verify', auth, (req, res) => {
  const orderId = String(req.body.orderId || '');
  const order = db.get('SELECT * FROM payment_orders WHERE order_id = ? AND user_id = ?', [orderId, req.user.id]);
  if (!order) return res.status(404).json({ ok: false, error: 'Order not found' });
  if (order.status === 'paid') {
    return res.json({ ok: true, user: db.publicUser(db.get('SELECT * FROM users WHERE id = ?', [req.user.id])) });
  }
  if (order.provider !== 'dev' || !devPaymentsAllowed()) {
    return res.status(400).json({ ok: false, error: 'Payment could not be verified' });
  }
  db.run(`UPDATE payment_orders SET status = 'paid', payment_id = 'dev' WHERE id = ?`, [order.id]);

  // Grant exactly what was ordered, even if the plan was edited since.
  const user = grantPremium(req.user.id, {
    id: order.plan,
    days: Number(order.days),
    amountPaise: Number(order.amount_paise),
  });
  res.json({ ok: true, user: db.publicUser(user) });
});

function consumeLater(productId, token) {
  googlePlay.consumeProductPurchase(productId, token).catch((err) => console.error(err.message));
}

// Safe to call repeatedly with the same token: the app resends purchases Play
// still holds on every launch until they are consumed.
router.post('/google-play/verify', auth, async (req, res, next) => {
  try {
    if (!googlePlay.configured()) return res.status(503).json({ ok: false, error: 'Payments are not configured' });
    const productId = String(req.body.productId || '');
    const token = String(req.body.purchaseToken || '');
    if (!productId || !token) return res.status(400).json({ ok: false, error: 'Payment could not be verified' });

    const done = () => {
      const order = db.get(`SELECT * FROM payment_orders WHERE order_id = ? AND provider = 'google_play'`, [token]);
      if (!order) return false;
      if (order.user_id !== req.user.id) {
        res.status(409).json({ ok: false, error: 'This purchase belongs to another account' });
      } else {
        consumeLater(productId, token);
        res.json({ ok: true, user: db.publicUser(db.get('SELECT * FROM users WHERE id = ?', [req.user.id])) });
      }
      return true;
    };
    if (done()) return;

    const purchase = await googlePlay.getProductPurchase(productId, token);
    if (!purchase || purchase.purchaseState === 1) {
      return res.status(400).json({ ok: false, error: 'Payment could not be verified' });
    }
    if (purchase.purchaseState === 2) return res.status(202).json({ ok: true, pending: true });
    if (purchase.obfuscatedExternalAccountId && purchase.obfuscatedExternalAccountId !== String(req.user.id)) {
      return res.status(409).json({ ok: false, error: 'This purchase belongs to another account' });
    }
    // Another request for this token may have finished while Google answered.
    if (done()) return;

    // Plans are never deleted (only switched off), so a paid product always has one.
    const plan = content.plan(productId);
    if (!plan) {
      console.error(`Play purchase for unknown plan ${productId}`);
      return res.status(400).json({ ok: false, error: 'Payment could not be verified' });
    }
    db.insert(
      `INSERT INTO payment_orders (user_id, plan, amount_paise, days, order_id, payment_id, provider, status)
       VALUES (?, ?, ?, ?, ?, ?, 'google_play', 'paid')`,
      [req.user.id, plan.id, plan.amountPaise, plan.days, token, purchase.orderId || null]
    );
    const user = grantPremium(req.user.id, plan);
    consumeLater(productId, token);
    res.json({ ok: true, user: db.publicUser(user) });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
