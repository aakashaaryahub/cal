// Voice rooms on Daily (daily.co), through its REST API.
//
// Every call gets its own private room for two people, audio only, which
// expires after MAX_CALL_SECONDS. Each person joins with their own meeting
// token, so knowing the room URL isn't enough to get in. Rooms are deleted
// when the call ends.
//
// Needs DAILY_API_KEY (dashboard.daily.co -> Developers).
const API = 'https://api.daily.co/v1';
const MAX_CALL_SECONDS = 4 * 3600;

/** A failure the app can show as-is. */
class CallSetupError extends Error {}

const isConfigured = () => Boolean(process.env.DAILY_API_KEY);

async function request(method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: { Authorization: `Bearer ${process.env.DAILY_API_KEY}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(`Daily ${method} ${path} failed (${res.status}): ${json.info || json.error || 'no details'}`);
    err.status = res.status;
    err.info = String(json.info || '');
    throw err;
  }
  return json;
}

// Both people in a call ask for the same room at about the same time, so
// creation is shared through one promise per room.
const rooms = new Map();

function ensureRoom(name) {
  if (!rooms.has(name)) {
    const exp = Math.floor(Date.now() / 1000) + MAX_CALL_SECONDS;
    const created = request('POST', '/rooms', {
      name,
      privacy: 'private',
      properties: {
        exp,
        eject_at_room_exp: true,
        max_participants: 2,
        start_video_off: true,
        enable_screenshare: false,
        enable_chat: false,
      },
    }).catch((err) => {
      // Already made (e.g. before a server restart): look it up instead.
      if (err.status === 400 && /already exists/i.test(err.info)) return request('GET', `/rooms/${name}`);
      throw err;
    });
    rooms.set(name, created);
    created.catch(() => rooms.delete(name));
    // The room expires on its own; forget it here too.
    setTimeout(() => rooms.delete(name), MAX_CALL_SECONDS * 1000).unref();
  }
  return rooms.get(name);
}

/**
 * What one person needs to join: the room URL and their own meeting token.
 * Throws CallSetupError when calls aren't set up or Daily is unreachable.
 */
async function joinInfo(roomName, user) {
  if (!isConfigured()) throw new CallSetupError('Voice calls aren\'t set up on the server yet (DAILY_API_KEY is missing).');
  try {
    const room = await ensureRoom(roomName);
    const { token } = await request('POST', '/meeting-tokens', {
      properties: {
        room_name: roomName,
        user_id: String(user.id),
        user_name: user.name || 'Stranger',
        exp: Math.floor(Date.now() / 1000) + MAX_CALL_SECONDS,
        eject_at_token_exp: true,
        start_video_off: true,
        enable_screenshare: false,
      },
    });
    return { roomUrl: room.url, token };
  } catch (err) {
    console.error('[daily]', err.message);
    throw new CallSetupError('Couldn\'t start the call. Please try again.');
  }
}

/** Ends the call for everyone still in it. Never throws. */
function deleteRoom(roomName) {
  if (!isConfigured() || !roomName) return;
  rooms.delete(roomName);
  request('DELETE', `/rooms/${roomName}`).catch((err) => {
    if (err.status !== 404) console.error('[daily]', err.message);
  });
}

/** Checks the API key against the domain endpoint, for the startup log. */
async function describeDomain() {
  if (!isConfigured()) return 'DAILY_API_KEY not set: voice calls are off';
  try {
    const domain = await request('GET', '/');
    return `Daily voice calls on ${domain.domain_name}.daily.co`;
  } catch (err) {
    return `Daily API key rejected or unreachable: ${err.message}`;
  }
}

module.exports = { isConfigured, joinInfo, deleteRoom, describeDomain, CallSetupError };
