import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api.dart';
import '../services/social_store.dart';
import '../theme/app_theme.dart';
import 'aurora_background.dart';
import 'common.dart';

/// Covers the whole app while the server can't be reached. Everything in the
/// app comes from the API, so there's nothing useful to show offline.
///
/// It pings the server on a heartbeat, so a dead server is noticed on every
/// screen, even ones that aren't making requests. Any other failed request
/// trips it straight away (see [Api.online]).
///
/// Live calls are left alone so people can still hang up; the cover appears
/// once the call screen closes.
class ServerGate extends StatefulWidget {
  final Widget child;
  const ServerGate({super.key, required this.child});

  @override
  State<ServerGate> createState() => _ServerGateState();
}

class _ServerGateState extends State<ServerGate> with WidgetsBindingObserver {
  static const _heartbeat = Duration(seconds: 4);
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.online.addListener(_onChange);
    _startHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Api.online.removeListener(_onChange);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startHeartbeat() {
    _timer?.cancel();
    // Each tick also re-checks CallGuard.busy, which isn't listenable.
    _timer = Timer.periodic(_heartbeat, (_) => _check());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      await Api.health();
    } catch (_) {
      // Api.online is already false.
    }
    _checking = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !Api.online.value && !CallGuard.busy;
    return Stack(
      children: [
        widget.child,
        if (blocked)
          Positioned.fill(
            child: Material(
              color: AppColors.background,
              child: AuroraBackground(
                intensity: 0.2,
                child: SafeArea(
                  child: ServerUnavailable(
                    message: 'Can\'t reach the VoxLink server.\nWe\'ll reconnect as soon as it\'s back.',
                    checking: _checking,
                    onRetry: _check,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ServerUnavailable extends StatelessWidget {
  final String message;
  final bool checking;
  final VoidCallback onRetry;

  const ServerUnavailable({super.key, required this.message, required this.onRetry, this.checking = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📡', style: TextStyle(fontSize: 56)).animate().shake(),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            child: GradientButton(label: 'Try again', height: 50, loading: checking, onTap: onRetry),
          ),
        ],
      ),
    );
  }
}
