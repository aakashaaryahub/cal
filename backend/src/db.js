const fs = require('fs');
const path = require('path');
const initSqlJs = require('sql.js');

// DATA_DIR points at a persistent disk in production (e.g. /var/data, a Render disk).
const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'voxlink.sqlite');
const schemaPath = path.join(__dirname, 'schema.sql');

let db;
let saveTimer;

function persist() {
  if (!db) return;
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
  const data = db.export();
  fs.writeFileSync(dbPath, Buffer.from(data));
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 50);
}

function bindAndRun(sql, params = []) {
  const stmt = db.prepare(sql);
  stmt.bind(params);
  stmt.step();
  stmt.free();
}

function all(sql, params = []) {
  const stmt = db.prepare(sql);
  stmt.bind(params);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function get(sql, params = []) {
  return all(sql, params)[0] || null;
}

function run(sql, params = []) {
  bindAndRun(sql, params);
  scheduleSave();
}

function insert(sql, params = []) {
  bindAndRun(sql, params);
  const row = get('SELECT last_insert_rowid() AS id');
  scheduleSave();
  return row ? Number(row.id) : 0;
}

function columnNames(table) {
  return all(`PRAGMA table_info(${table})`).map((c) => c.name);
}

// Brings databases created by older versions of the app up to date.
function migrate() {
  db.exec('DROP TABLE IF EXISTS match_queue');
  const addColumns = {
    users: {
      country: "TEXT NOT NULL DEFAULT ''",
      country_code: "TEXT NOT NULL DEFAULT ''",
      gender_preference: "TEXT NOT NULL DEFAULT 'any'",
      invite_code: 'TEXT',
      invited_by: 'INTEGER',
    },
    otps: { attempts: 'INTEGER NOT NULL DEFAULT 0' },
    calls: { room_id: 'TEXT', kind: "TEXT NOT NULL DEFAULT 'random'" },
    messages: { read_at: 'TEXT' },
    payment_orders: { days: 'INTEGER NOT NULL DEFAULT 0' },
  };
  for (const [table, cols] of Object.entries(addColumns)) {
    if (!all(`SELECT name FROM sqlite_master WHERE type='table' AND name=?`, [table]).length) continue;
    const existing = columnNames(table);
    for (const [col, def] of Object.entries(cols)) {
      if (!existing.includes(col)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${col} ${def}`);
    }
  }
  // The first version only took 10-digit Indian numbers and stored them
  // without a country code; phones are now E.164, so those users couldn't log in.
  if (all(`SELECT name FROM sqlite_master WHERE type='table' AND name='users'`).length) {
    db.exec(`UPDATE users SET phone = '+91' || phone
      WHERE length(phone) = 10 AND phone NOT GLOB '*[^0-9]*'
        AND NOT EXISTS (SELECT 1 FROM users u WHERE u.phone = '+91' || users.phone)`);
  }
}

async function init() {
  const SQL = await initSqlJs();
  if (fs.existsSync(dbPath)) {
    const file = fs.readFileSync(dbPath);
    db = new SQL.Database(file);
  } else {
    db = new SQL.Database();
  }
  migrate();
  db.exec(fs.readFileSync(schemaPath, 'utf8'));
  seedDefaults();
  persist();
}

// Fills in plans and content keys that don't exist yet. Never overwrites
// existing rows, so edits made through the admin API survive restarts.
function seedDefaults() {
  const { PLANS, CONTENT, CONTENT_REVISION, REVISED_KEYS } = require('./defaults');
  const upsertPlan = (p) =>
    bindAndRun(
      `INSERT INTO plans (id, title, amount_paise, days, badge, sort_order, active, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(id) DO UPDATE SET
         title = excluded.title, amount_paise = excluded.amount_paise, days = excluded.days,
         badge = excluded.badge, sort_order = excluded.sort_order, active = excluded.active,
         updated_at = excluded.updated_at`,
      [p.id, p.title, p.amountPaise, p.days, p.badge, p.sortOrder, p.active === false ? 0 : 1]
    );
  if (!get('SELECT 1 FROM plans LIMIT 1')) PLANS.forEach(upsertPlan);
  for (const [key, value] of Object.entries(CONTENT)) {
    bindAndRun('INSERT OR IGNORE INTO app_content (key, value) VALUES (?, ?)', [key, JSON.stringify(value)]);
  }

  // A release that changed plans or content applies them once, over older values.
  const row = get(`SELECT value FROM app_content WHERE key = 'contentRevision'`);
  const applied = Number(row ? JSON.parse(row.value) : 1);
  if (applied < CONTENT_REVISION) {
    PLANS.forEach(upsertPlan);
    for (const key of REVISED_KEYS) {
      bindAndRun(
        `INSERT INTO app_content (key, value, updated_at) VALUES (?, ?, datetime('now'))
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
        [key, JSON.stringify(CONTENT[key])]
      );
    }
    bindAndRun(
      `INSERT INTO app_content (key, value, updated_at) VALUES ('contentRevision', ?, datetime('now'))
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      [JSON.stringify(CONTENT_REVISION)]
    );
    console.log(`[db] applied content revision ${CONTENT_REVISION}`);
  }
}

function isPremium(row) {
  return Boolean(row.is_premium) && Boolean(row.premium_until) && new Date(row.premium_until) > new Date();
}

function banFor(phone) {
  return get('SELECT * FROM banned_phones WHERE phone = ?', [String(phone)]);
}

function publicUser(row, extra = {}) {
  if (!row) return null;
  return {
    id: Number(row.id),
    phone: row.phone,
    name: row.name || '',
    age: Number(row.age || 0),
    city: row.city || '',
    country: row.country || '',
    countryCode: row.country_code || '',
    gender: row.gender || '',
    bio: row.bio || '',
    avatarUrl: row.avatar_url || null,
    language: row.language || 'English',
    notificationsEnabled: Boolean(row.notifications_enabled),
    genderPreference: row.gender_preference || 'any',
    profileCompleted: Boolean(row.profile_completed),
    isPremium: isPremium(row),
    premiumUntil: row.premium_until || null,
    isOnline: Boolean(row.is_online),
    lastSeen: row.last_seen,
    createdAt: row.created_at,
    ...extra,
  };
}

// What a stranger is allowed to see about the person they're talking to.
function peerUser(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    name: row.name || 'Stranger',
    age: Number(row.age || 0),
    city: row.city || '',
    country: row.country || '',
    countryCode: row.country_code || '',
    gender: row.gender || '',
  };
}

module.exports = { init, all, get, run, insert, persist, publicUser, peerUser, isPremium, banFor };
