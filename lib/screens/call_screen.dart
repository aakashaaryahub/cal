import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../services/api.dart';
import '../services/call_engine.dart';
import '../services/config_store.dart';
import '../services/social_store.dart';
import '../services/topic_deck.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import '../widgets/social_widgets.dart';
import '../widgets/topic_card.dart';
import 'call_summary_screen.dart';
import 'matching_screen.dart';

class CallScreen extends StatefulWidget {
  final int callId;
  final String roomUrl;
  final String token;
  final Peer peer;
  final String genderFilter;

  /// A call to a friend (vs. a random match): no "Next" button.
  final bool isDirect;

  /// Seconds left of today's call minutes; the call ends when they run out.
  /// null = no limit.
  final int? limitSeconds;

  const CallScreen({
    super.key,
    required this.callId,
    required this.roomUrl,
    required this.token,
    required this.peer,
    this.genderFilter = 'any',
    this.isDirect = false,
    this.limitSeconds,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _connectTimeout = Duration(seconds: 20);

  final _engine = CallEngine.instance;
  Timer? _ticker;
  Timer? _timeout;
  int _seconds = 0;
  bool _muted = false;
  bool _speaker = false;
  bool _leaving = false;
  String? _error;
  late Peer _peer = widget.peer;

  // Conversation topics: the same deck on both phones, kept in step over the call.
  late final _topics = TopicDeck(widget.callId);
  bool _topicsOpen = true;
  String? _topicNote;
  StreamSubscription<Map<String, dynamic>>? _messages;

  @override
  void initState() {
    super.initState();
    CallGuard.enter();
    _engine.phase.addListener(_onPhase);
    _messages = _engine.messages.listen(_onMessage);
    _join();
  }

  @override
  void dispose() {
    _messages?.cancel();
    _engine.phase.removeListener(_onPhase);
    _ticker?.cancel();
    _timeout?.cancel();
    _engine.leave();
    CallGuard.exit();
    super.dispose();
  }

  Future<void> _join() async {
    _timeout = Timer(_connectTimeout, () {
      if (_engine.phase.value == CallPhase.connecting) _engine.leave(CallEndReason.noAnswer);
    });
    try {
      await _engine.join(roomUrl: widget.roomUrl, token: widget.token);
    } catch (e) {
      _timeout?.cancel();
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onPhase() {
    final phase = _engine.phase.value;
    if (phase == CallPhase.connected && _ticker == null) {
      _timeout?.cancel();
      HapticFeedback.mediumImpact();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
        final limit = widget.limitSeconds;
        if (limit != null && _seconds >= limit) _engine.leave(CallEndReason.limitReached);
      });
    }
    if (phase == CallPhase.ended) _finish();
    if (mounted) setState(() {});
  }

  /// Ends the call and either shows the summary or jumps to the next stranger.
  Future<void> _finish({bool next = false}) async {
    if (_leaving) return;
    _leaving = true;
    _ticker?.cancel();
    _timeout?.cancel();
    await _engine.leave();
    Api.endCall(widget.callId, _seconds);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    // "Next" with no minutes left would only be refused by the server.
    final limit = widget.limitSeconds;
    if (next && limit != null && limit - _seconds < 30) next = false;
    final page = next
        ? MatchingScreen(genderFilter: widget.genderFilter)
        : CallSummaryScreen(
            peer: _peer,
            seconds: _seconds,
            reason: _engine.endReason ?? CallEndReason.hungUp,
            genderFilter: widget.genderFilter,
          );
    Navigator.of(context).pushReplacement(fadeRoute(page));
  }

  void _nextTopic() {
    HapticFeedback.selectionClick();
    setState(() {
      _topics.position++;
      _topicNote = null;
    });
    _engine.send({'type': 'topic', 'position': _topics.position});
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['type'] != 'topic' || !mounted) return;
    final position = (m['position'] as num?)?.toInt();
    if (position == null || position == _topics.position) return;
    setState(() {
      _topics.position = position;
      _topicsOpen = true;
      _topicNote = '${_peer.name.split(' ').first} picked a new topic';
    });
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine.setMuted(_muted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    await _engine.setSpeaker(_speaker);
  }

  Future<void> _report() async {
    final reason = await showReportSheet(context, widget.peer.name);
    if (reason == null) return;
    try {
      await Api.report(widget.peer.id, reason);
      await Api.block(widget.peer.id);
      if (mounted) showToast(context, 'Thanks. ${widget.peer.name} is reported and blocked.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _engine.phase.value;
    final connected = phase == CallPhase.connected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        body: AuroraBackground(
          intensity: connected ? 0.26 : 0.16,
          colors: const [AppColors.violet, AppColors.pink, AppColors.cyan],
          child: SafeArea(
            child: Column(
              children: [
                _topBar(phase),
                Expanded(
                  child: _error != null
                      ? _errorView()
                      // Shrinks on short screens to leave room for the topic card. The width
                      // stays fixed: some children (the follow button) need a bounded width.
                      : LayoutBuilder(
                          builder: (context, box) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(width: box.maxWidth, child: _peerView(connected)),
                            ),
                          ),
                        ),
                ),
                if (connected && _error == null)
                  TopicCard(
                    topic: _topics.current,
                    open: _topicsOpen,
                    note: _topicNote,
                    onNext: _nextTopic,
                    onToggle: () => setState(() => _topicsOpen = !_topicsOpen),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),
                _controls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(CallPhase phase) {
    final (label, color) = switch (phase) {
      CallPhase.connected => (formatDuration(_seconds), AppColors.green),
      CallPhase.reconnecting => ('Reconnecting…', AppColors.gold),
      CallPhase.ended => ('Call ended', AppColors.textSecondary),
      _ => ('Connecting…', AppColors.cyan),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LiveDot(color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Report',
            onPressed: _report,
            icon: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _peerView(bool connected) {
    final peer = _peer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VoiceAvatar(peer: peer, active: connected, level: _engine.peerLevel),
        const SizedBox(height: 26),
        Text(
          '${peer.name}${peer.age > 0 ? ', ${peer.age}' : ''}',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.3),
        const SizedBox(height: 6),
        if (peer.location.isNotEmpty)
          Text(
            '${flagEmoji(peer.countryCode)}  ${peer.location}',
            style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ).animate().fadeIn(delay: 250.ms),
        const SizedBox(height: 8),
        PeerStatsLine(peer: peer).animate().fadeIn(delay: 300.ms),
        if (peer.canInteract && !peer.iFollow) ...[
          const SizedBox(height: 14),
          FollowButton(compact: true, peer: peer, onChanged: (p) => setState(() => _peer = p))
              .animate()
              .fadeIn(delay: 400.ms)
              .scale(begin: const Offset(0.8, 0.8)),
        ],
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: connected
              ? SoundBars(level: _engine.peerLevel, color: AppColors.pink, bars: 9, height: 30)
              : const Text(
                  'Waiting for audio…',
                  key: ValueKey('wait'),
                  style: TextStyle(color: AppColors.textMuted),
                ),
        ),
      ],
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.danger),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
        ],
      ),
    );
  }

  Widget _controls() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundControl(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _muted ? 'Unmute' : 'Mute',
            active: _muted,
            onTap: _toggleMute,
            level: _muted ? null : _engine.myLevel,
          ),
          _RoundControl(
            icon: _speaker ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
            label: 'Speaker',
            active: _speaker,
            onTap: _toggleSpeaker,
          ),
          _RoundControl(
            icon: Icons.call_end_rounded,
            label: 'End',
            danger: true,
            onTap: () => _finish(),
          ),
          if (!widget.isDirect)
            _RoundControl(
              icon: Icons.skip_next_rounded,
              label: 'Next',
              onTap: () => _finish(next: true),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.4, curve: Curves.easeOutCubic);
  }
}

/// Peer avatar wrapped in glow rings that swell with their voice.
class _VoiceAvatar extends StatelessWidget {
  final Peer peer;
  final bool active;
  final ValueNotifier<double> level;

  const _VoiceAvatar({required this.peer, required this.active, required this.level});

  @override
  Widget build(BuildContext context) {
    const size = 150.0;
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!active) const PulseRings(size: 280, color: AppColors.cyan),
          ValueListenableBuilder<double>(
            valueListenable: level,
            builder: (_, v, __) => Stack(
              alignment: Alignment.center,
              children: [
                for (final (i, alpha) in const [(2, 0.12), (1, 0.22), (0, 0.4)])
                  AnimatedContainer(
                    duration: Duration(milliseconds: 160 + i * 60),
                    curve: Curves.easeOut,
                    width: size + (active ? v * (40 + i * 35) : 0) + i * 16,
                    height: size + (active ? v * (40 + i * 35) : 0) + i * 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        AppColors.pink.withValues(alpha: active ? alpha : 0),
                        AppColors.violet.withValues(alpha: 0),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
            ),
            child: InitialsAvatar(name: peer.name, size: size, countryCode: peer.countryCode),
          ).animate().scale(begin: const Offset(0.6, 0.6), duration: 600.ms, curve: Curves.elasticOut),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final ValueNotifier<double>? level;

  const _RoundControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.level,
  });

  @override
  Widget build(BuildContext context) {
    final size = danger ? 68.0 : 58.0;
    final Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: danger ? AppColors.danger : (active ? Colors.white : AppColors.surfaceHigh),
        boxShadow: [
          if (danger) BoxShadow(color: AppColors.danger.withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (c, a) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(a),
          child: ScaleTransition(scale: a, child: c),
        ),
        child: Icon(
          icon,
          key: ValueKey(icon),
          color: danger ? Colors.white : (active ? AppColors.background : AppColors.textPrimary),
          size: danger ? 32 : 26,
        ),
      ),
    );

    return Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Your own mic level shows as a ring around the mute button.
                if (level != null)
                  ValueListenableBuilder<double>(
                    valueListenable: level!,
                    builder: (_, v, __) => AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: size + 4 + v * 14,
                      height: size + 4 + v * 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.green.withValues(alpha: 0.25 + v * 0.6), width: 2),
                      ),
                    ),
                  ),
                button,
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

Future<String?> showReportSheet(BuildContext context, String name) {
  final reasons = ConfigStore.current.reportReasons;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report $name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'They\'ll be blocked and the call will end. Our team reviews every report.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final (i, r) in reasons.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(ctx, r),
              ).animate().fadeIn(delay: (i * 50).ms).slideX(begin: 0.1),
          ],
        ),
      ),
    ),
  );
}
