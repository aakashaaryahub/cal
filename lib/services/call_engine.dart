import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/foundation.dart';

enum CallPhase { idle, connecting, connected, reconnecting, ended }

enum CallEndReason { hungUp, peerLeft, noAnswer, network, error, limitReached }

class CallException implements Exception {
  final String message;
  CallException(this.message);
  @override
  String toString() => message;
}

/// Thin wrapper around the Daily SDK for 1:1 audio calls.
///
/// The server creates a private two-person room per call and gives each side
/// the room URL plus its own meeting token. Both join with the camera off; the
/// call counts as connected once the other person is in the room.
class CallEngine {
  CallEngine._();
  static final instance = CallEngine._();

  final phase = ValueNotifier<CallPhase>(CallPhase.idle);

  /// 0..1 voice levels that drive the call animations. Daily reports who is
  /// speaking rather than how loud, so the speaker's level flickers in a
  /// natural-looking range and the other side's falls to zero.
  final myLevel = ValueNotifier<double>(0);
  final peerLevel = ValueNotifier<double>(0);

  CallEndReason? endReason;

  /// Small JSON messages from the other person, sent over the call (e.g. the
  /// current conversation topic).
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();

  CallClient? _client;
  StreamSubscription<Event>? _events;
  bool _inCall = false;
  bool? _localSpeaking; // null: nobody
  Timer? _levels;
  final _random = Random();

  Future<void> join({required String roomUrl, required String token}) async {
    if (roomUrl.isEmpty || token.isEmpty) {
      throw CallException('The server didn\'t send the call details. Please try again.');
    }
    endReason = null;
    _inCall = true;
    phase.value = CallPhase.connecting;
    try {
      final client = await CallClient.create();
      _client = client;
      _events = client.events.listen(_onEvent);
      await client.join(
        url: Uri.parse(roomUrl),
        token: token,
        clientSettings: const ClientSettingsUpdate.set(
          inputs: InputSettingsUpdate.set(
            camera: CameraInputSettingsUpdate.set(isEnabled: BoolUpdate.set(false)),
            microphone: MicrophoneInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
          ),
        ),
      );
      if (!_inCall) return; // hung up while joining
      await client.setAudioDevice(deviceId: DeviceId.earpiece);
      if (client.participants.remote.isNotEmpty) _peerJoined();
    } catch (e) {
      debugPrint('Daily join failed: $e');
      await leave(CallEndReason.error);
      throw CallException('Couldn\'t join the call. Check your connection and try again.');
    }
  }

  /// Sends [message] to the other person in the call. Never throws.
  Future<void> send(Map<String, dynamic> message) async {
    final client = _client;
    if (client == null || !_inCall) return;
    try {
      await client.sendAppMessage(jsonEncode(message), null);
    } catch (e) {
      debugPrint('Daily app message failed: $e');
    }
  }

  void _received(String data) {
    try {
      Object? value = jsonDecode(data);
      // Depending on the platform the payload may arrive JSON-encoded twice.
      if (value is String) value = jsonDecode(value);
      if (value is Map) _messages.add(Map<String, dynamic>.from(value));
    } catch (_) {}
  }

  Future<void> setMuted(bool muted) async => _client?.setInputsEnabled(microphone: !muted);

  Future<void> setSpeaker(bool on) async =>
      _client?.setAudioDevice(deviceId: on ? DeviceId.speakerPhone : DeviceId.earpiece);

  /// Ends the call locally. Safe to call more than once.
  Future<void> leave([CallEndReason reason = CallEndReason.hungUp]) async {
    if (!_inCall) return;
    _inCall = false;
    endReason ??= reason;
    final client = _client;
    _client = null;
    await _events?.cancel();
    _events = null;
    _setSpeaking(null);
    if (client != null) {
      try {
        await client.leave();
      } catch (e) {
        debugPrint('Daily leave failed: $e');
      }
      try {
        await client.dispose();
      } catch (_) {}
    }
    phase.value = CallPhase.ended;
  }

  void _peerJoined() {
    if (_inCall) phase.value = CallPhase.connected;
  }

  void _remoteEnded(CallEndReason reason) {
    if (!_inCall) return;
    endReason = reason;
    leave(reason);
  }

  void _onEvent(Event event) {
    switch (event) {
      case ParticipantJoinedEvent(:final participant) when !participant.info.isLocal:
        _peerJoined();
      case ParticipantLeftEvent(:final participant) when !participant.info.isLocal:
        _remoteEnded(CallEndReason.peerLeft);
      case AppMessageReceivedEvent(:final data):
        _received(data);
      case ActiveSpeakerChangedEvent(:final participant):
        _setSpeaking(participant?.info.isLocal);
      case CallStateUpdatedEvent(:final stateData) when stateData.state == CallState.left:
        // Left without hanging up: ejected, room deleted by the other side, or the network dropped.
        _remoteEnded(CallEndReason.network);
      case ErrorEvent(:final message):
        debugPrint('Daily error: $message');
        _remoteEnded(CallEndReason.network);
      default:
        break;
    }
  }

  void _setSpeaking(bool? local) {
    _localSpeaking = local;
    _levels?.cancel();
    _levels = null;
    myLevel.value = 0;
    peerLevel.value = 0;
    if (local == null) return;
    _levels = Timer.periodic(const Duration(milliseconds: 140), (_) {
      final level = 0.35 + _random.nextDouble() * 0.6;
      (_localSpeaking == true ? myLevel : peerLevel).value = level;
    });
  }
}
