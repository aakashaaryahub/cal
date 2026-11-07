// Who may do what to whom.
//
//   follow / vote  -> only people you've been matched with on a call
//   chat / call    -> only mutual followers ("friends")
//   blocked pairs  -> nothing at all
const db = require('./db');

function isBlocked(a, b) {
  return Boolean(
    db.get(
      `SELECT 1 FROM blocks
       WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)`,
      [a, b, b, a]
    )
  );
}

function follows(a, b) {
  return Boolean(db.get('SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ?', [a, b]));
}

function areFriends(a, b) {
  return follows(a, b) && follows(b, a) && !isBlocked(a, b);
}

function hadCall(a, b) {
  return Boolean(
    db.get(
      `SELECT 1 FROM calls
       WHERE room_id IS NOT NULL
         AND ((caller_id = ? AND callee_id = ?) OR (caller_id = ? AND callee_id = ?))
       LIMIT 1`,
      [a, b, b, a]
    )
  );
}

function stats(userId) {
  const followers = db.get('SELECT COUNT(*) AS c FROM follows WHERE following_id = ?', [userId]);
  const following = db.get('SELECT COUNT(*) AS c FROM follows WHERE follower_id = ?', [userId]);
  const karma = db.get('SELECT COALESCE(SUM(value), 0) AS s FROM votes WHERE target_id = ?', [userId]);
  return {
    followers: Number(followers.c),
    following: Number(following.c),
    karma: Number(karma.s),
  };
}

/** Public card for another user, plus how the viewer relates to them. */
function profileFor(viewerId, row) {
  const myVote = db.get('SELECT value FROM votes WHERE voter_id = ? AND target_id = ?', [viewerId, row.id]);
  const iFollow = follows(viewerId, row.id);
  const followsMe = follows(row.id, viewerId);
  return {
    ...db.peerUser(row),
    ...stats(row.id),
    iFollow,
    followsMe,
    isFriend: iFollow && followsMe,
    myVote: myVote ? Number(myVote.value) : 0,
    canInteract: hadCall(viewerId, row.id),
  };
}

module.exports = { isBlocked, follows, areFriends, hadCall, stats, profileFor };
