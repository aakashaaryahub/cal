import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api.dart';
import '../services/config_store.dart';
import '../services/social_store.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import 'call_screen.dart';
import 'premium_screen.dart';

class MatchingScreen extends StatefulWidget {
  final String genderFilter;
  const MatchingScreen({super.key, required this.genderFilter});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  static const _pollEvery = Duration(milliseconds: 1500);

  Timer? _poll;
  Timer? _clock;
  bool _inFlight = false;
  bool _done = false;
  int _elapsed = 0;
  int _waiting = 0;
  String? _error;
  MatchResult? _match;

  List<String> get _messages => [
        ConfigStore.current.matchingHeadline(widget.genderFilter),
        ...ConfigStore.current.matchingMessages,
      ];

  @override
  void initState() {
    super.initState();
    CallGuard.enter();
    _start();
  }

  @override
  void dispose() {
    CallGuard.exit();
    _poll?.cancel();
    _clock?.cancel();
    if (_match == null) Api.leaveQueue();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _elapsed = 0;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    await _tick(join: true);
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  Future<void> _tick({bool join = false}) async {
    if (_inFlight || _done) return;
    _inFlight = true;
    try {
      final r = join ? await Api.joinQueue(widget.genderFilter) : await Api.pollMatch();
      if (!mounted || _done) return;
      if (r.isMatched) {
        _onMatched(r);
      } else if (r.status == 'idle') {
        // Server dropped us (e.g. restart); rejoin.
        _inFlight = false;
        await _tick(join: true);
      } else {
        setState(() => _waiting = r.waiting);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isPremiumRequired) {
        _done = true;
        Navigator.of(context).pushReplacement(fadeRoute(const PremiumScreen()));
        return;
      }
      _poll?.cancel();
      _clock?.cancel();
      setState(() => _error = e.message);
    } finally {
      _inFlight = false;
    }
  }

  void _onMatched(MatchResult r) {
    _done = true;
    _poll?.cancel();
    _clock?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _match = r);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeRoute(CallScreen(
        callId: r.callId!,
        roomUrl: r.roomUrl!,
        token: r.token!,
        peer: r.peer!,
        genderFilter: widget.genderFilter,
      )));
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = Storage.user;
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.22,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                formatDuration(_elapsed),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _match != null
                      ? _matchedView(_match!)
                      : _error != null
                          ? _errorView()
                          : _searchingView(me?.name ?? 'You', me?.countryCode),
                ),
              ),
              if (_match == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.stroke),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchingView(String myName, String? myCountry) {
    final msg = _messages[(_elapsed ~/ 4) % _messages.length];
    return LayoutBuilder(
      key: const ValueKey('searching'),
      builder: (context, box) {
        final size = min(box.maxWidth, box.maxHeight * 0.7);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _RadarSweep(size: size * 0.9),
                  PulseRings(size: size, color: AppColors.violet, rings: 4),
                  const _FloatingFlags(),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.6), blurRadius: 30)],
                    ),
                    child: InitialsAvatar(name: myName, size: size * 0.26, countryCode: myCountry),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 0.96, end: 1.04, duration: 1200.ms, curve: Curves.easeInOut),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              child: Text(
                msg,
                key: ValueKey(msg),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              opacity: _waiting > 0 ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                '$_waiting other${_waiting == 1 ? '' : 's'} searching right now',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _matchedView(MatchResult r) {
    final peer = r.peer!;
    return Column(
      key: const ValueKey('matched'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const PulseRings(size: 220, color: AppColors.green, period: Duration(milliseconds: 1200)),
              InitialsAvatar(name: peer.name, size: 120, countryCode: peer.countryCode)
                  .animate()
                  .scale(begin: const Offset(0.2, 0.2), duration: 700.ms, curve: Curves.elasticOut),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'It\'s a match! 🎉',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.green),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.4),
        const SizedBox(height: 6),
        Text(
          'Connecting you with ${peer.name}${peer.age > 0 ? ', ${peer.age}' : ''}',
          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ).animate().fadeIn(delay: 350.ms),
        if (peer.location.isNotEmpty)
          Text(
            '${flagEmoji(peer.countryCode)}  ${peer.location}',
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ).animate().fadeIn(delay: 450.ms),
      ],
    );
  }

  Widget _errorView() {
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📡', style: TextStyle(fontSize: 56)).animate().shake(),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            child: GradientButton(label: 'Try again', height: 50, onTap: _start),
          ),
        ],
      ),
    );
  }
}

class _RadarSweep extends StatefulWidget {
  final double size;
  const _RadarSweep({required this.size});

  @override
  State<_RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<_RadarSweep> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [
            Colors.transparent,
            Colors.transparent,
            AppColors.pink.withValues(alpha: 0.05),
            AppColors.pink.withValues(alpha: 0.35),
          ], stops: const [0, 0.6, 0.85, 1]),
        ),
      ),
    );
  }
}

/// Flags of the countries people are calling from today, drifting up and
/// fading out (from the server's active-countries list).
class _FloatingFlags extends StatelessWidget {
  const _FloatingFlags();

  @override
  Widget build(BuildContext context) {
    final flags = ConfigStore.current.activeCountries.take(10).map(flagEmoji).toList();
    final rnd = Random(7);
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < flags.length; i++)
          Transform.translate(
            offset: Offset((rnd.nextDouble() - 0.5) * 260, (rnd.nextDouble() - 0.5) * 160),
            child: Text(flags[i], style: const TextStyle(fontSize: 26))
                .animate(onPlay: (c) => c.repeat(), delay: (i * 380).ms)
                .fadeIn(duration: 600.ms)
                .moveY(begin: 30, end: -50, duration: 3200.ms, curve: Curves.easeOut)
                .scaleXY(begin: 0.6, end: 1.1, duration: 3200.ms)
                .fadeOut(delay: 2000.ms, duration: 1200.ms),
          ),
      ],
    );
  }
}
