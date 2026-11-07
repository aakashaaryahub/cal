import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/user_profile.dart';
import 'storage.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  final String? code;

  ApiException(this.message, {this.status = 0, this.code});

  bool get isPremiumRequired => code == 'PREMIUM_REQUIRED';
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

class MatchResult {
  final String status; // searching | matched | idle
  final int waiting;
  final int? callId;
  final Peer? peer;

  /// Daily room to join and this user's meeting token for it.
  final String? roomUrl;
  final String? token;

  MatchResult.fromJson(Map<String, dynamic> j)
      : status = (j['status'] ?? 'idle').toString(),
        waiting = (j['waiting'] as num?)?.toInt() ?? 0,
        callId = (j['call']?['id'] as num?)?.toInt(),
        roomUrl = j['call']?['roomUrl']?.toString(),
        token = j['call']?['token']?.toString(),
        peer = j['peer'] == null ? null : Peer.fromJson(Map<String, dynamic>.from(j['peer']));

  bool get isMatched => status == 'matched' && roomUrl != null && token != null && peer != null;
}

class Plan {
  final String id;
  final String title;
  final int price;
  final int perWeek;
  final int days;
  final String? badge;

  Plan.fromJson(Map<String, dynamic> j)
      : id = j['id'].toString(),
        title = j['title'].toString(),
        price = (j['price'] as num).round(),
        perWeek = (j['perWeek'] as num).round(),
        days = (j['days'] as num).toInt(),
        badge = j['badge']?.toString();
}

class CallRecord {
  final int id;
  final Peer? peer;
  final String status;
  final String kind; // random | direct
  final int durationSeconds;
  final DateTime? startedAt;

  CallRecord.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        peer = j['peer'] == null ? null : Peer.fromJson(Map<String, dynamic>.from(j['peer'])),
        status = (j['status'] ?? '').toString(),
        kind = (j['kind'] ?? 'random').toString(),
        durationSeconds = (j['durationSeconds'] as num?)?.toInt() ?? 0,
        startedAt = parseServerTime(j['startedAt']);
}

/// SQLite stores UTC as "YYYY-MM-DD HH:MM:SS".
DateTime? parseServerTime(Object? v) =>
    v == null ? null : DateTime.tryParse('${v.toString().replaceFirst(' ', 'T')}Z')?.toLocal();

class ChatMessage {
  final int id;
  final String text;
  final bool fromMe;
  final DateTime? createdAt;

  ChatMessage.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        text = j['text'].toString(),
        fromMe = j['fromMe'] == true,
        createdAt = parseServerTime(j['createdAt']);
}

class FriendThread {
  final Peer user;
  final String? lastText;
  final bool lastFromMe;
  final DateTime? lastAt;
  final int unread;

  FriendThread.fromJson(Map<String, dynamic> j)
      // Friends are mutual followers by definition.
      : user = Peer.fromJson({...Map<String, dynamic>.from(j['user']), 'iFollow': true, 'followsMe': true, 'canInteract': true}),
        lastText = j['lastMessage']?['text']?.toString(),
        lastFromMe = j['lastMessage']?['fromMe'] == true,
        lastAt = parseServerTime(j['lastMessage']?['createdAt']),
        unread = (j['unread'] as num?)?.toInt() ?? 0;
}

class SocialOverview {
  final List<FriendThread> friends;
  final List<Peer> followers;
  final int unreadTotal;

  SocialOverview.fromJson(Map<String, dynamic> j)
      : friends = (j['friends'] as List).map((f) => FriendThread.fromJson(Map<String, dynamic>.from(f))).toList(),
        // People who follow you and you haven't followed back.
        followers = (j['followers'] as List)
            .map((u) => Peer.fromJson({...Map<String, dynamic>.from(u), 'followsMe': true, 'canInteract': true}))
            .toList(),
        unreadTotal = (j['unreadTotal'] as num?)?.toInt() ?? 0;
}

class DirectCall {
  final int id;
  final String status; // ringing | connected | declined | missed | cancelled | completed
  final Peer peer;

  /// Set once connected: the Daily room and this user's meeting token.
  final String? roomUrl;
  final String? token;

  DirectCall.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        status = j['status'].toString(),
        roomUrl = j['roomUrl']?.toString(),
        token = j['token']?.toString(),
        peer = Peer.fromJson(Map<String, dynamic>.from(j['peer']));

  bool get isRinging => status == 'ringing';
  bool get isConnected => status == 'connected' && roomUrl != null && token != null;
}

class LeaderEntry {
  final int rank;
  final Peer user;
  final int value;

  LeaderEntry.fromJson(Map<String, dynamic> j)
      : rank = (j['rank'] as num).toInt(),
        user = Peer.fromJson(Map<String, dynamic>.from(j['user'])),
        value = (j['value'] as num).toInt();
}

class Leaderboard {
  final List<LeaderEntry> talkTime;
  final List<LeaderEntry> followers;
  final int? myTalkRank;
  final int myTalkSeconds;
  final int? myFollowerRank;
  final int myFollowers;

  Leaderboard.fromJson(Map<String, dynamic> j)
      : talkTime = (j['talkTime'] as List).map((e) => LeaderEntry.fromJson(Map<String, dynamic>.from(e))).toList(),
        followers = (j['followers'] as List).map((e) => LeaderEntry.fromJson(Map<String, dynamic>.from(e))).toList(),
        myTalkRank = (j['me']['talkTime']['rank'] as num?)?.toInt(),
        myTalkSeconds = (j['me']['talkTime']['value'] as num).toInt(),
        myFollowerRank = (j['me']['followers']['rank'] as num?)?.toInt(),
        myFollowers = (j['me']['followers']['value'] as num).toInt();
}

class Api {
  static const _timeout = Duration(seconds: 15);

  /// False after a request fails to reach the server; true again on the next
  /// response. The app blocks its UI while this is false.
  static final online = ValueNotifier<bool>(true);

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (Storage.token != null) 'Authorization': 'Bearer ${Storage.token}',
    };

    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await req.send().timeout(_timeout));
    } on TimeoutException {
      online.value = false;
      throw ApiException('The server is taking too long. Check your connection.');
    } catch (_) {
      online.value = false;
      throw ApiException('Can\'t reach VoxLink right now. Check your internet connection.');
    }
    online.value = true;

    Map<String, dynamic> json = {};
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (res.statusCode >= 400 || json['ok'] == false) {
      throw ApiException(
        (json['error'] ?? 'Something went wrong (${res.statusCode})').toString(),
        status: res.statusCode,
        code: json['code']?.toString(),
      );
    }
    return json;
  }

  /// Throws [ApiException] if the server is down.
  static Future<void> health() => _request('GET', '/health');

  // ── App config (plans, content, client settings) ──
  static Future<Map<String, dynamic>> appConfig() => _request('GET', '/app-config');

  // ── Auth ──
  /// With [login], the server only accepts numbers that already have an account.
  static Future<String?> sendOtp(String phone, {bool login = false}) async {
    final res = await _request('POST', '/auth/otp/send', body: {'phone': phone, if (login) 'mode': 'login'});
    return res['debugOtp']?.toString();
  }

  static Future<(String, UserProfile)> verifyOtp(String phone, String otp, {bool login = false}) async {
    final res = await _request('POST', '/auth/otp/verify',
        body: {'phone': phone, 'otp': otp, if (login) 'mode': 'login'});
    return (
      res['token'].toString(),
      UserProfile.fromJson(Map<String, dynamic>.from(res['user'])),
    );
  }

  static Future<UserProfile> me() async {
    final res = await _request('GET', '/auth/me');
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user']));
  }

  static Future<void> logout() async {
    try {
      await _request('POST', '/auth/logout');
    } catch (_) {}
  }

  /// Permanently deletes the signed-in account.
  static Future<void> deleteAccount() => _request('DELETE', '/users/me');

  // ── Profile ──
  static Future<UserProfile> saveProfile({
    required String name,
    required int age,
    required String gender,
    required String city,
    required String country,
    required String countryCode,
    String? inviteCode,
  }) async {
    final res = await _request('PUT', '/users/me', body: {
      'name': name,
      'age': age,
      'gender': gender,
      'city': city,
      'country': country,
      'countryCode': countryCode,
      if (inviteCode != null) 'inviteCode': inviteCode,
    });
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user']));
  }

  // ── Invites ──
  /// The inviter's first name; throws [ApiException] for an unknown code.
  static Future<String> checkInvite(String code) async {
    final res = await _request('GET', '/users/invites/${Uri.encodeComponent(code)}');
    return res['inviter']['name'].toString();
  }

  /// This user's invite code and how many people joined with it.
  static Future<(String, int)> myInvite() async {
    final res = await _request('GET', '/users/me/invite');
    return (res['code'].toString(), (res['joined'] as num?)?.toInt() ?? 0);
  }

  static Future<UserProfile> savePreferences({required String genderPreference}) async {
    final res = await _request('PUT', '/users/me/preferences', body: {'genderPreference': genderPreference});
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user']));
  }

  static Future<Map<String, int>> stats() async {
    final res = await _request('GET', '/users/me/stats');
    return Map<String, dynamic>.from(res['stats'])
        .map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  // ── Matching ──
  static Future<int> onlineCount() async {
    final res = await _request('GET', '/match/online-count');
    return (res['count'] as num?)?.toInt() ?? 0;
  }

  static Future<MatchResult> joinQueue(String genderFilter) async =>
      MatchResult.fromJson(await _request('POST', '/match/join', body: {'genderFilter': genderFilter}));

  static Future<MatchResult> pollMatch() async =>
      MatchResult.fromJson(await _request('GET', '/match/status'));

  static Future<void> leaveQueue() async {
    try {
      await _request('DELETE', '/match');
    } catch (_) {}
  }

  // ── Calls ──
  static Future<List<CallRecord>> callHistory() async {
    final res = await _request('GET', '/calls');
    return (res['calls'] as List)
        .map((c) => CallRecord.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  static Future<void> endCall(int callId, int durationSeconds) async {
    try {
      await _request('PATCH', '/calls/$callId/end', body: {'durationSeconds': durationSeconds});
    } catch (_) {}
  }

  // ── Safety ──
  static Future<void> report(int userId, String reason) =>
      _request('POST', '/reports', body: {'userId': userId, 'reason': reason});

  static Future<void> block(int userId) => _request('POST', '/blocks', body: {'userId': userId});

  // ── People & social ──
  static Future<Peer> profile(int userId) async =>
      Peer.fromJson(Map<String, dynamic>.from((await _request('GET', '/users/$userId'))['profile']));

  static Future<Peer> follow(int userId) async =>
      Peer.fromJson(Map<String, dynamic>.from((await _request('POST', '/follows/$userId'))['profile']));

  static Future<Peer> unfollow(int userId) async =>
      Peer.fromJson(Map<String, dynamic>.from((await _request('DELETE', '/follows/$userId'))['profile']));

  /// [value] is 1 (upvote), -1 (downvote) or 0 (clear).
  static Future<Peer> vote(int userId, int value) async => Peer.fromJson(
      Map<String, dynamic>.from((await _request('POST', '/votes/$userId', body: {'value': value}))['profile']));

  static Future<SocialOverview> social() async => SocialOverview.fromJson(await _request('GET', '/follows'));

  // ── Chat ──
  static Future<(List<ChatMessage>, int)> messages(int userId, {int after = 0}) async {
    final res = await _request('GET', '/chats/$userId/messages${after > 0 ? '?after=$after' : ''}');
    final list = (res['messages'] as List).map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))).toList();
    return (list, (res['seenUpTo'] as num?)?.toInt() ?? 0);
  }

  static Future<ChatMessage> sendMessage(int userId, String text) async => ChatMessage.fromJson(
      Map<String, dynamic>.from((await _request('POST', '/chats/$userId/messages', body: {'text': text}))['message']));

  // ── Direct calls between friends ──
  static Future<DirectCall> startDirectCall(int userId) async => DirectCall.fromJson(
      Map<String, dynamic>.from((await _request('POST', '/direct-calls', body: {'userId': userId}))['call']));

  static Future<DirectCall?> incomingCall() async {
    final c = (await _request('GET', '/direct-calls/incoming'))['call'];
    return c == null ? null : DirectCall.fromJson(Map<String, dynamic>.from(c));
  }

  static Future<DirectCall> directCall(int id) async =>
      DirectCall.fromJson(Map<String, dynamic>.from((await _request('GET', '/direct-calls/$id'))['call']));

  static Future<DirectCall> acceptCall(int id) async =>
      DirectCall.fromJson(Map<String, dynamic>.from((await _request('POST', '/direct-calls/$id/accept'))['call']));

  static Future<void> declineCall(int id) async {
    try {
      await _request('POST', '/direct-calls/$id/decline');
    } catch (_) {}
  }

  // ── Leaderboard ──
  static Future<Leaderboard> leaderboard() async => Leaderboard.fromJson(await _request('GET', '/leaderboard'));

  // ── Premium ──
  static Future<List<Plan>> plans() async {
    final res = await _request('GET', '/subscriptions/plans');
    return (res['plans'] as List).map((p) => Plan.fromJson(Map<String, dynamic>.from(p))).toList();
  }

  static Future<Map<String, dynamic>> createOrder(String planId) =>
      _request('POST', '/subscriptions/order', body: {'plan': planId});

  /// Completes a dev-mode (test) order.
  static Future<UserProfile> verifyPayment({required String orderId}) async {
    final res = await _request('POST', '/subscriptions/verify', body: {'orderId': orderId});
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user']));
  }

  /// Returns null while Google still reports the payment as pending.
  static Future<UserProfile?> verifyPlayPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final res = await _request('POST', '/subscriptions/google-play/verify', body: {
      'productId': productId,
      'purchaseToken': purchaseToken,
    });
    if (res['pending'] == true) return null;
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user']));
  }
}
