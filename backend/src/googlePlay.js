// Google Play Developer API: checks and consumes in-app purchases.
//
// Needs GOOGLE_PLAY_PACKAGE (the app ID) and GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
// (the service account key file's contents). The service account must be
// invited in Play Console -> Users and permissions with "View financial data"
// and "Manage orders and subscriptions".
const jwt = require('jsonwebtoken');

const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

let account;
let cachedToken = { value: null, expiresAt: 0 };

function serviceAccount() {
  if (account === undefined) {
    try {
      account = JSON.parse(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || 'null');
    } catch {
      console.error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON');
      account = null;
    }
  }
  return account;
}

function configured() {
  const sa = serviceAccount();
  return Boolean(process.env.GOOGLE_PLAY_PACKAGE && sa && sa.client_email && sa.private_key);
}

async function accessToken() {
  if (cachedToken.value && Date.now() < cachedToken.expiresAt) return cachedToken.value;
  const sa = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    { iss: sa.client_email, scope: SCOPE, aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 },
    sa.private_key,
    { algorithm: 'RS256' }
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Google auth failed: ${JSON.stringify(body)}`);
  cachedToken = { value: body.access_token, expiresAt: Date.now() + (body.expires_in - 60) * 1000 };
  return cachedToken.value;
}

function productUrl(productId, purchaseToken) {
  return `${API}/${encodeURIComponent(process.env.GOOGLE_PLAY_PACKAGE)}/purchases/products/${encodeURIComponent(
    productId
  )}/tokens/${encodeURIComponent(purchaseToken)}`;
}

// Returns Google's ProductPurchase, or null when the token is unknown to Google.
// purchaseState: 0 purchased, 1 cancelled, 2 pending.
async function getProductPurchase(productId, purchaseToken) {
  const res = await fetch(productUrl(productId, purchaseToken), {
    headers: { Authorization: `Bearer ${await accessToken()}` },
  });
  if (res.status === 400 || res.status === 404 || res.status === 410) return null;
  const body = await res.json();
  if (!res.ok) throw new Error(`Play purchase lookup failed: ${JSON.stringify(body)}`);
  return body;
}

// Consuming also acknowledges, so Google won't auto-refund after 3 days, and
// lets the user buy the same plan again.
async function consumeProductPurchase(productId, purchaseToken) {
  const res = await fetch(`${productUrl(productId, purchaseToken)}:consume`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await accessToken()}` },
  });
  if (!res.ok) throw new Error(`Play consume failed (${res.status}): ${await res.text()}`);
}

module.exports = { configured, getProductPurchase, consumeProductPurchase };
