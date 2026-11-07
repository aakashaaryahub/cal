import 'package:flutter/foundation.dart';
import '../models/remote_config.dart';
import 'api.dart';

/// Holds the server-driven config. Nothing is cached on the device: the app
/// loads it from the API on launch and can't start without it.
class ConfigStore {
  static final notifier = ValueNotifier<RemoteConfig>(RemoteConfig.empty);

  static RemoteConfig get current => notifier.value;

  /// Fetches the latest config. Throws [ApiException] if the server is unreachable.
  static Future<void> load() async {
    notifier.value = RemoteConfig(await Api.appConfig());
  }

  /// Like [load], but a failure keeps the config already in memory.
  static Future<void> refresh() async {
    try {
      await load();
    } catch (_) {}
  }
}
