// OTP delivery through PowersText (bulk.powerstext.in), an Indian DLT SMS
// gateway. Configure it in .env to send real SMS; otherwise codes are printed
// to the server console (and returned to the app outside production).
//
// DLT only delivers text that matches the registered template word for word,
// so the message below must stay exactly as registered for POWERSTEXT_TEMPLATE_ID.
const API_URL = 'https://bulk.powerstext.in/http-tokenkeyapi.php';
const otpMessage = (code) => `Use this verification code ${code} to verify your mobile number on APP DE`;

/** Thrown when a number can't get an SMS; the message is safe to show users. */
class SmsError extends Error {}

function smsConfigured() {
  return Boolean(
    process.env.POWERSTEXT_AUTH_KEY && process.env.POWERSTEXT_SENDER_ID && process.env.POWERSTEXT_TEMPLATE_ID
  );
}

async function sendOtpSms(phone, code) {
  if (!smsConfigured()) {
    console.log(`[otp] ${phone} -> ${code}`);
    return;
  }

  // Phones are stored as E.164; the gateway wants the 10-digit Indian number.
  const match = /^\+91([6-9]\d{9})$/.exec(phone);
  if (!match) throw new SmsError('Codes can only be sent to Indian (+91) mobile numbers right now');

  const url = new URL(API_URL);
  url.search = new URLSearchParams({
    'authentic-key': process.env.POWERSTEXT_AUTH_KEY,
    senderid: process.env.POWERSTEXT_SENDER_ID,
    route: process.env.POWERSTEXT_ROUTE || '1',
    number: match[1],
    message: otpMessage(code),
    templateid: process.env.POWERSTEXT_TEMPLATE_ID,
  });

  let res;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  } catch (err) {
    console.error('[sms] gateway unreachable:', err.message);
    throw new SmsError('Couldn\'t send the code right now. Please try again.');
  }
  const body = await res.text();
  let json = {};
  try {
    json = JSON.parse(body);
  } catch {}
  // Failures look like {"Status":"Failed","Code":"016","Description":"No Numbers Found"}.
  if (!res.ok || /fail|error|invalid/i.test(String(json.Status || ''))) {
    console.error(`[sms] send to ${phone} failed (${res.status}): ${body}`);
    throw new SmsError('Couldn\'t send the code to this number. Check it and try again.');
  }
  console.log(`[sms] code sent to ${phone}: ${body}`);
}

module.exports = { sendOtpSms, smsConfigured, SmsError };
