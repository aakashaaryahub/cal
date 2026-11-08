// Database access for premium plans and app content.
const db = require('./db');

function planFromRow(r) {
  const amountPaise = Number(r.amount_paise);
  const days = Number(r.days);
  return {
    id: r.id,
    title: r.title,
    amountPaise,
    price: amountPaise / 100,
    currency: 'INR',
    days,
    perWeek: Math.round((amountPaise / 100 / days) * 7),
    perDay: Math.round(amountPaise / 100 / days),
    badge: r.badge || null,
    sortOrder: Number(r.sort_order),
    active: Boolean(r.active),
  };
}

function plans({ includeInactive = false } = {}) {
  return db
    .all(`SELECT * FROM plans ${includeInactive ? '' : 'WHERE active = 1'} ORDER BY sort_order, amount_paise`)
    .map(planFromRow);
}

function plan(id) {
  const row = db.get('SELECT * FROM plans WHERE id = ?', [String(id)]);
  return row ? planFromRow(row) : null;
}

function savePlan(id, fields) {
  const existing = plan(id);
  const next = { ...(existing || {}), ...fields };
  if (!next.title || !(next.amountPaise > 0) || !(next.days > 0)) {
    throw Object.assign(new Error('title, amountPaise (> 0) and days (> 0) are required'), { status: 400 });
  }
  db.run(
    `INSERT INTO plans (id, title, amount_paise, days, badge, sort_order, active, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
     ON CONFLICT(id) DO UPDATE SET
       title = excluded.title, amount_paise = excluded.amount_paise, days = excluded.days,
       badge = excluded.badge, sort_order = excluded.sort_order, active = excluded.active,
       updated_at = excluded.updated_at`,
    [
      String(id),
      String(next.title),
      Math.round(Number(next.amountPaise)),
      Math.round(Number(next.days)),
      next.badge || null,
      Number(next.sortOrder || 0),
      next.active === false ? 0 : 1,
    ]
  );
  return plan(id);
}

/** All content keys as one object: { tips: [...], premium: {...}, ... } */
function allContent() {
  const out = {};
  for (const r of db.all('SELECT key, value FROM app_content')) {
    try {
      out[r.key] = JSON.parse(r.value);
    } catch {
      // A malformed row shouldn't take the whole config down.
    }
  }
  return out;
}

function setContent(key, value) {
  db.run(
    `INSERT INTO app_content (key, value, updated_at) VALUES (?, ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
    [String(key), JSON.stringify(value)]
  );
}

/** Changes whenever plans or content change; lets the app skip re-parsing. */
function version() {
  const row = db.get(
    `SELECT MAX(t) AS v FROM (
       SELECT MAX(updated_at) AS t FROM plans UNION ALL SELECT MAX(updated_at) FROM app_content
     )`
  );
  return String(row?.v || '');
}

/** Whether picking a gender to talk to needs Premium (admin switch, off by default). */
function premiumEnabled() {
  const row = db.get(`SELECT value FROM app_content WHERE key = 'premiumEnabled'`);
  try {
    return row ? JSON.parse(row.value) === true : false;
  } catch {
    return false;
  }
}

module.exports = { plans, plan, savePlan, allContent, setContent, version, premiumEnabled };
