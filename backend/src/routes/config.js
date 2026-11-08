// Everything the app needs to render that isn't per-user: plans, copy, lists,
// and client settings. Public, so the splash and onboarding screens can use it.
const express = require('express');
const db = require('../db');
const content = require('../content');
const daily = require('../daily');
const limits = require('../limits');

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

/** Fills {freeMinutes} / {premiumMinutes} in content text from the current call limits. */
function fillLimits(value) {
  const s = limits.settings();
  const minutes = { free: s.freeMinutesPerDay, premium: s.premiumMinutesPerDay };
  const json = JSON.stringify(value).replace(/\{(free|premium)Minutes\}( minutes)?/g, (_m, which, unit, offset, all) => {
    const n = minutes[which];
    if (n > 0) return `${n}${unit || ''}`;
    // 0 means unlimited; capitalise at the start of a string.
    return (all[offset - 1] === '"' ? 'Unlimited' : 'unlimited') + (unit || '');
  });
  return JSON.parse(json);
}

router.get('/', (_req, res) => {
  res.json({
    ok: true,
    version: content.version(),
    calls: { provider: 'daily', enabled: daily.isConfigured() },
    premiumEnabled: content.premiumEnabled(),
    plans: content.plans(),
    content: fillLimits(content.allContent()),
    activeCountries: activeCountries(),
    limits: { minAge: 18, maxAge: 99 },
  });
});

module.exports = router;
