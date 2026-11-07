import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';

/// Friends list + unread counts, shared by the Chats tab and the nav badge.
class SocialStore {
  static final overview = ValueNotifier<SocialOverview?>(null);

  static Future<void> refresh() async {
    try {
      overview.value = await Api.social();
    } catch (_) {}
  }
}

/// Screens that hold the microphone (matching, ringing, in a call) register
/// here so an incoming-call screen never pops up on top of them.
class CallGuard {
  static int _depth = 0;
  static bool get busy => _depth > 0;
  static void enter() => _depth++;
  static void exit() => _depth = max(0, _depth - 1);
}
