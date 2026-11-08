import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api.dart';
import '../services/social_store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/permissions.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import 'call_screen.dart';

/// A friend is calling. Closes itself if they hang up or it times out.
class IncomingCallScreen extends StatefulWidget {
  final DirectCall call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _poll;
  Timer? _buzz;
  bool _answering = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    CallGuard.enter();
    _buzz = Timer.periodic(const Duration(milliseconds: 1400), (_) => HapticFeedback.heavyImpact());
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _buzz?.cancel();
    if (!_handled) Api.declineCall(widget.call.id);
    CallGuard.exit();
    super.dispose();
  }

  Future<void> _check() async {
    if (_answering) return;
    try {
      final c = await Api.directCall(widget.call.id);
      if (!mounted || c.isRinging) return;
      _handled = true;
      _stopRinging();
      showToast(context, 'Missed call from ${widget.call.peer.name}');
      Navigator.pop(context);
    } catch (_) {}
  }

  void _stopRinging() {
    _poll?.cancel();
    _buzz?.cancel();
  }

  Future<void> _accept() async {
    setState(() => _answering = true);
    _buzz?.cancel();
    if (!await ensureMicPermission(context)) {
      if (mounted) setState(() => _answering = false);
      return;
    }
    try {
      final c = await Api.acceptCall(widget.call.id);
      _handled = true;
      _stopRinging();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeRoute(CallScreen(
        callId: c.id,
        roomUrl: c.roomUrl!,
        token: c.token!,
        peer: c.peer,
        isDirect: true,
        limitSeconds: c.limitSeconds,
      )));
    } on ApiException catch (e) {
      _handled = true;
      _stopRinging();
      if (!mounted) return;
      showToast(context, e.message, error: true);
      Navigator.pop(context);
    }
  }

  void _decline() {
    _handled = true;
    _stopRinging();
    Api.declineCall(widget.call.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.call.peer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        body: AuroraBackground(
          intensity: 0.26,
          colors: const [AppColors.green, AppColors.violet, AppColors.cyan],
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Text(
                  'INCOMING CALL',
                  style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w800, color: AppColors.green),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 700.ms),
                const Spacer(),
                SizedBox(
                  width: 280,
                  height: 280,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const PulseRings(size: 280, color: AppColors.green, period: Duration(milliseconds: 1600)),
                      InitialsAvatar(name: peer.name, size: 140, countryCode: peer.countryCode)
                          .animate(onPlay: (c) => c.repeat())
                          .shake(hz: 4, rotation: 0.03, duration: 500.ms)
                          .then(delay: 900.ms),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(peer.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                if (peer.location.isNotEmpty)
                  Text(
                    '${flagEmoji(peer.countryCode)}  ${peer.location}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 56),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _button(Icons.call_end_rounded, 'Decline', AppColors.danger, _answering ? null : _decline),
                      _button(Icons.call_rounded, 'Accept', AppColors.green, _answering ? null : _accept, wiggle: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String label, Color color, VoidCallback? onTap, {bool wiggle = false}) {
    Widget circle = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 24)],
      ),
      child: _answering && wiggle
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : Icon(icon, color: Colors.white, size: 34),
    );
    if (wiggle && !_answering) {
      circle = circle
          .animate(onPlay: (c) => c.repeat())
          .moveY(begin: 0, end: -8, duration: 300.ms, curve: Curves.easeOut)
          .then()
          .moveY(begin: -8, end: 0, duration: 500.ms, curve: Curves.bounceOut)
          .then(delay: 500.ms);
    }
    return Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      child: Column(
        children: [
          circle,
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
