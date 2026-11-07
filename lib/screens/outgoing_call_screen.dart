import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../services/api.dart';
import '../services/social_store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/permissions.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import 'call_screen.dart';

/// Ringing a friend. Hands over to [CallScreen] once they pick up.
class OutgoingCallScreen extends StatefulWidget {
  final Peer peer;
  const OutgoingCallScreen({super.key, required this.peer});

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  DirectCall? _call;
  Timer? _poll;
  String _status = 'Calling…';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    CallGuard.enter();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _poll?.cancel();
    final call = _call;
    // Hanging up while it still rings cancels it on the other phone.
    if (call != null && !_finished) Api.declineCall(call.id);
    CallGuard.exit();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await ensureMicPermission(context)) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      _call = await Api.startDirectCall(widget.peer.id);
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    } on ApiException catch (e) {
      _end(e.message);
    }
  }

  Future<void> _check() async {
    final id = _call?.id;
    if (id == null || _finished) return;
    try {
      final c = await Api.directCall(id);
      if (!mounted || _finished) return;
      if (c.isConnected) {
        _finished = true;
        _poll?.cancel();
        Navigator.of(context).pushReplacement(fadeRoute(CallScreen(
          callId: c.id,
          roomUrl: c.roomUrl!,
          token: c.token!,
          peer: widget.peer,
          isDirect: true,
        )));
      } else if (!c.isRinging) {
        _end(switch (c.status) {
          'declined' => '${widget.peer.name} is busy right now',
          'missed' => 'No answer',
          _ => 'Call ended',
        });
      }
    } catch (_) {}
  }

  void _end(String message) {
    _finished = true;
    _poll?.cancel();
    if (!mounted) return;
    setState(() => _status = message);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peer;
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.22,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_finished) const PulseRings(size: 260, color: AppColors.violet),
                    InitialsAvatar(name: peer.name, size: 130, countryCode: peer.countryCode)
                        .animate()
                        .scale(begin: const Offset(0.6, 0.6), duration: 600.ms, curve: Curves.elasticOut),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(peer.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              if (peer.location.isNotEmpty)
                Text(
                  '${flagEmoji(peer.countryCode)}  ${peer.location}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _status,
                  key: ValueKey(_status),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _finished ? AppColors.gold : AppColors.cyan,
                  ),
                ),
              ),
              const Spacer(),
              Pressable(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.danger.withValues(alpha: 0.5), blurRadius: 24)],
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.5),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
