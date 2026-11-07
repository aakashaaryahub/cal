// Everything the app needs to render that isn't per-user: plans, copy, lists,
// and client settings. Public, so the splash and onboarding screens can use it.
const express = require('express');
const db = require('../db');
const content = require('../content');
const daily = require('../daily');

const router = express.Router();

/** Countries of people active in the last day, most common first. */
function activeCountries() {
  const rows = db.all(
    `SELECT country_code AS cc, COUNT(*) AS n FROM users
     WHERE profile_completed = 1 AND country_code != '' AND last_seen > datetime('now', '-1 day')
     GROUP BY country_code ORDER BY n DESC LIMIT 12`
  );
  return rows.map((r) => r.cc);
}

router.get('/', (_req, res) => {
  res.json({
    ok: true,
    version: content.version(),
    calls: { provider: 'daily', enabled: daily.isConfigured() },
    premiumEnabled: content.premiumEnabled(),
    plans: content.plans(),
    content: content.allContent(),
    activeCountries: activeCountries(),
    limits: { minAge: 18, maxAge: 99 },
  });
});

module.exports = router;
