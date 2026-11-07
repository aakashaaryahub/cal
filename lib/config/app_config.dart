import 'dart:io';

/// Build-time configuration. Pass values with --dart-define, e.g.
///
///   flutter run --dart-define=API_BASE_URL=https://api.yourdomain.com/api
///
/// Voice calls need nothing here: the server hands out a Daily room and
/// token for every call.
class AppConfig {
  static const appName = 'VoxLink';

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // Android emulator reaches the host machine through 10.0.2.2.
    if (Platform.isAndroid) return 'http://10.0.2.2:3000/api';
    return 'http://127.0.0.1:3000/api';
  }

  /// Public pages served by the backend (also linked from the Play listing).
  static String get siteUrl => apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  static String get privacyPolicyUrl => '$siteUrl/privacy';
}
