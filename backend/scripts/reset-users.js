// Deletes every user and everything tied to them (calls, follows, chats,
// reports, payments...). Plans and app content are kept.
//
//   npm run reset-users -- --yes
//
// Stop the server first: it holds the database in memory and would write the
// old data straight back. A backup is saved next to the database.
require('dotenv').config();
const fs = require('fs');
const http = require('http');
const path = require('path');
const initSqlJs = require('sql.js');

// DATA_DIR points at a persistent disk in production (e.g. /var/data, a Render disk).
const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'voxlink.sqlite');
const TABLES = ['messages', 'votes', 'follows', 'blocks', 'reports', 'calls', 'subscriptions', 'payment_orders', 'match_queue', 'otps', 'users'];

function serverRunning() {
  const port = process.env.PORT || 3000;
  return new Promise((resolve) => {
    const req = http.get({ host: '127.0.0.1', port, path: '/api/health', timeout: 1500 }, (res) => {
      res.resume();
      resolve(true);
    });
    req.on('timeout', () => req.destroy());
    req.on('error', () => resolve(false));
  });
}

async function main() {
  if (!process.argv.includes('--yes')) {
    console.log('This deletes ALL users, calls, follows, chats, reports and payments (plans and app content stay).');
    console.log('Run again with --yes to do it:  npm run reset-users -- --yes');
    process.exit(1);
  }
  if (!fs.existsSync(dbPath)) {
    console.log('No database yet, nothing to delete.');
    return;
  }
  if (await serverRunning()) {
    console.error(`The server is running on port ${process.env.PORT || 3000}. Stop it first (Ctrl+C in its terminal), then run this again.`);
    process.exit(1);
  }

  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
  const backup = path.join(dataDir, `voxlink.backup-${stamp}.sqlite`);
  fs.copyFileSync(dbPath, backup);

  const SQL = await initSqlJs();
  const db = new SQL.Database(fs.readFileSync(dbPath));
  const existing = new Set(db.exec("SELECT name FROM sqlite_master WHERE type = 'table'")[0]?.values.flat() || []);
  for (const table of TABLES.filter((t) => existing.has(t))) {
    const n = db.exec(`SELECT COUNT(*) FROM ${table}`)[0].values[0][0];
    db.run(`DELETE FROM ${table}`);
    console.log(`  ${table.padEnd(15)} ${n} deleted`);
  }
  // New users start again from ID 1.
  if (existing.has('sqlite_sequence')) {
    db.run(`DELETE FROM sqlite_sequence WHERE name IN (${TABLES.map(() => '?').join(', ')})`, TABLES);
  }
  fs.writeFileSync(dbPath, Buffer.from(db.export()));
  console.log(`\nDone. Backup of the old data: ${path.relative(process.cwd(), backup)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
