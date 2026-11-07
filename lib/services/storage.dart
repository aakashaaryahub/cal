import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

/// Keeps the session token on the device so users skip onboarding on every
/// launch. That's the only thing stored locally: the profile and preferences
/// live in the database, are loaded from GET /auth/me on launch, and are only
/// held in memory.
class Storage {
  static const _kToken = 'auth_token';
  static const _kLegacyUser = 'user_profile';

  static late SharedPreferences _prefs;

  /// Current user; screens listen to this so premium changes show instantly.
  static final userNotifier = ValueNotifier<UserProfile?>(null);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Older builds cached the profile on the device.
    await _prefs.remove(_kLegacyUser);
    await _prefs.remove('remote_config');
    await _prefs.remove('gender_preference');
  }

  static String? get token => _prefs.getString(_kToken);

  static bool get hasToken => token?.isNotEmpty ?? false;

  static UserProfile? get user => userNotifier.value;

  static bool get isSignedIn => hasToken && (user?.profileCompleted ?? false);

  static Future<void> saveToken(String token) => _prefs.setString(_kToken, token);

  static Future<void> saveUser(UserProfile user) async {
    userNotifier.value = user;
  }

  static Future<void> clear() async {
    await _prefs.remove(_kToken);
    userNotifier.value = null;
  }
}
