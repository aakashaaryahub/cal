// Daily call-minute allowance: free users get a few minutes a day, Premium
// users more. Both are set in the admin dashboard (content key `callLimits`,
// 0 = unlimited). Days run midnight to midnight India time.
//
// Usage is the length of today's calls as reported when they end. Each call's
// Daily meeting token also expires when the allowance runs out, so a call
// can't run past it even if the app doesn't hang up.
const db = require('./db');
const content = require('./content');

const DEFAULTS = { freeMinutesPerDay: 15, premiumMinutesPerDay: 120 };
// Below this, starting a call isn't worth it for the other person.
const MIN_START_SECONDS = 30;
const IST_OFFSET_MS = 5.5 * 3600 * 1000;

function minutes(v, fallback) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n) : fallback;
}

function settings() {
  const c = content.allContent().callLimits || {};
  return {
    freeMinutesPerDay: minutes(c.freeMinutesPerDay, DEFAULTS.freeMinutesPerDay),
    premiumMinutesPerDay: minutes(c.premiumMinutesPerDay, DEFAULTS.premiumMinutesPerDay),
  };
}

/** Start of today and tomorrow in India, as Dates. */
function istDay(now = Date.now()) {
  const local = new Date(now + IST_OFFSET_MS);
  local.setUTCHours(0, 0, 0, 0);
  const start = new Date(local.getTime() - IST_OFFSET_MS);
  return { start, next: new Date(start.getTime() + 24 * 3600 * 1000) };
}

const sqlTime = (d) => d.toISOString().slice(0, 19).replace('T', ' ');

function usedSecondsToday(userId) {
  const row = db.get(
    `SELECT COALESCE(SUM(duration_seconds), 0) AS n FROM calls
     WHERE (caller_id = ? OR callee_id = ?) AND started_at >= ?`,
    [userId, userId, sqlTime(istDay().start)]
  );
  return Number(row?.n || 0);
}

/**
 * Today's allowance for a user row:
 * { premium, limitMinutes (0 = unlimited), usedSeconds, remainingSeconds (null = unlimited), resetsAt }
 */
function forUser(user) {
  const premium = db.isPremium(user);
  const s = settings();
  const limitMinutes = premium ? s.premiumMinutesPerDay : s.freeMinutesPerDay;
  const usedSeconds = usedSecondsToday(user.id);
  return {
    premium,
    limitMinutes,
    usedSeconds,
    remainingSeconds: limitMinutes === 0 ? null : Math.max(0, limitMinutes * 60 - usedSeconds),
    resetsAt: istDay().next.toISOString(),
  };
}

/** The 403 body for someone who has used today's minutes, or null if they can call. */
function blockedBody(user) {
  const a = forUser(user);
  if (a.remainingSeconds === null || a.remainingSeconds >= MIN_START_SECONDS) return null;
  let error;
  if (a.premium) {
    error = `You've used today's ${a.limitMinutes} minutes of calls. They reset at midnight.`;
  } else if (content.premiumEnabled()) {
    const premiumMinutes = settings().premiumMinutesPerDay;
    error = `You've used your ${a.limitMinutes} free minutes for today. Get Premium for ${
      premiumMinutes === 0 ? 'unlimited calls' : `${premiumMinutes} minutes a day`
    }, or come back tomorrow.`;
  } else {
    error = `You've used your ${a.limitMinutes} free minutes for today. Come back tomorrow!`;
  }
  return { ok: false, code: 'CALL_LIMIT', error, allowance: a };
}

module.exports = { settings, forUser, blockedBody, istDay, DEFAULTS };
