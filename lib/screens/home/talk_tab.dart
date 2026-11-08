import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/user_profile.dart';
import '../../services/api.dart';
import '../../services/config_store.dart';
import '../../services/storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/permissions.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../matching_screen.dart';
import '../premium_screen.dart';

class TalkTab extends StatefulWidget {
  final VoidCallback onCallFinished;
  const TalkTab({super.key, required this.onCallFinished});

  @override
  State<TalkTab> createState() => _TalkTabState();
}

class _TalkTabState extends State<TalkTab> {
  String _filter = Storage.user?.genderPreference ?? 'any';
  int? _online;
  CallAllowance? _allowance;
  Timer? _onlineTimer;
  int _tip = 0;
  Timer? _tipTimer;

  @override
  void initState() {
    super.initState();
    _loadOnline();
    _loadAllowance();
    _onlineTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadOnline());
    // Index wraps when read, since the tip list can change with fresh config.
    _tipTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _tip++);
    });
    // Drop a saved filter if premium has since expired.
    if (_filter != 'any' && ConfigStore.current.premiumEnabled && !(Storage.user?.hasActivePremium ?? false)) {
      _filter = 'any';
    }
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOnline() async {
    try {
      final n = await Api.onlineCount();
      if (mounted) setState(() => _online = n);
    } catch (_) {}
  }

  Future<void> _loadAllowance() async {
    try {
      final a = await Api.callAllowance();
      if (mounted) setState(() => _allowance = a);
    } catch (_) {}
  }

  Future<bool> _openPremium() async {
    final bought = await Navigator.of(context).push<bool>(fadeRoute(const PremiumScreen()));
    if (bought == true) _loadAllowance();
    return bought == true;
  }

  Future<void> _setFilter(String f) async {
    final option = ConfigStore.current.genderOptions.where((o) => o.value == f).firstOrNull;
    final locked = ConfigStore.current.premiumEnabled && (option?.premium ?? f != 'any');
    if (locked && !(Storage.user?.hasActivePremium ?? false)) {
      if (!await _openPremium()) return;
    }
    try {
      await Storage.saveUser(await Api.savePreferences(genderPreference: f));
      if (mounted) setState(() => _filter = f);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _connect() async {
    if (!await ensureMicPermission(context) || !mounted) return;
    await Navigator.of(context).push(fadeRoute(MatchingScreen(genderFilter: _filter)));
    widget.onCallFinished();
    _loadOnline();
    // The call may still be reporting its length; give it a moment.
    Future.delayed(const Duration(seconds: 2), _loadAllowance);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on premium changes and when fresh config (tips, options) arrives.
    return ListenableBuilder(
      listenable: Listenable.merge([Storage.userNotifier, ConfigStore.notifier]),
      builder: (context, _) {
        final user = Storage.userNotifier.value;
        final premium = user?.hasActivePremium ?? false;
        // With Premium switched off every option is free.
        final unlocked = premium || !ConfigStore.current.premiumEnabled;
        return SafeArea(
          bottom: false,
          child: LayoutBuilder(builder: (context, box) {
            final orb = min(box.maxWidth * 0.62, box.maxHeight * 0.36);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 110),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 124),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _header(user, premium),
                    const SizedBox(height: 18),
                    _onlinePill(),
                    const SizedBox(height: 10),
                    _ConnectOrb(size: orb, onTap: _connect, filter: _filter),
                    const SizedBox(height: 12),
                    _filterSelector(unlocked),
                    _allowanceLine(premium),
                    const SizedBox(height: 18),
                    _tipCard(),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _header(UserProfile? user, bool premium) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hey ${user?.firstName ?? 'there'} 👋',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 2),
              const Text('Ready to meet someone new?', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ).animate().fadeIn().slideX(begin: -0.1),
        ),
        if (ConfigStore.current.premiumEnabled)
          Pressable(
            onTap: premium ? null : _openPremium,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 14)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFF3A2500)),
                  const SizedBox(width: 5),
                  Text(
                    premium ? 'Premium' : 'Go Premium',
                    style: const TextStyle(color: Color(0xFF3A2500), fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(delay: 2500.ms, duration: 1400.ms, color: Colors.white.withValues(alpha: 0.7)),
          ),
      ],
    );
  }

  /// "12 of 15 free minutes left today", hidden when there's no limit.
  Widget _allowanceLine(bool premium) {
    final a = _allowance;
    if (a == null || a.unlimited) return const SizedBox.shrink();
    final left = (a.remainingSeconds! / 60).floor();
    final out = a.remainingSeconds! < 30;
    final kind = a.premium ? 'Premium' : 'free';
    final canUpgrade = !a.premium && ConfigStore.current.premiumEnabled;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Pressable(
        onTap: canUpgrade ? _openPremium : null,
        child: Text.rich(
          TextSpan(
            text: out
                ? 'You\'ve used today\'s ${a.limitMinutes} $kind minutes. They reset at midnight.'
                : '⏱️ $left of ${a.limitMinutes} $kind minutes left today',
            children: [
              if (canUpgrade)
                const TextSpan(
                  text: '  Get more',
                  style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: out ? AppColors.pink : AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _onlinePill() {
    return AnimatedOpacity(
      opacity: _online == null ? 0 : 1,
      duration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LiveDot(),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              child: Text(
                '${_online ?? 0} ${_online == 1 ? 'person' : 'people'} active now',
                key: ValueKey(_online),
                style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterSelector(bool premium) {
    final options = ConfigStore.current.genderOptions;
    if (options.isEmpty) return const SizedBox.shrink();
    // A saved choice the server no longer offers falls back to the first option.
    final index = options.indexWhere((o) => o.value == _filter).clamp(0, options.length - 1);
    return Column(
      children: [
        const Text(
          'I want to talk to',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Container(
          height: 56,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.stroke),
          ),
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / options.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  left: w * index,
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.pink.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final o in options)
                      Expanded(
                        child: Pressable(
                          onTap: () => _setFilter(o.value),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (o.emoji.isNotEmpty) ...[
                                  Text(o.emoji, style: const TextStyle(fontSize: 17)),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    o.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _filter == o.value ? AppColors.textPrimary : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (o.premium && !premium) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.lock_rounded, size: 13, color: AppColors.gold),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2);
  }

  Widget _tipCard() {
    final tips = ConfigStore.current.tips;
    if (tips.isEmpty) return const SizedBox.shrink();
    final tip = tips[_tip % tips.length];
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
            child: c,
          ),
        ),
        child: Row(
          key: ValueKey(_tip),
          children: [
            Text(tip.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tip.text, style: const TextStyle(color: AppColors.textSecondary, height: 1.35)),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 450.ms);
  }
}

/// The big glowing call button: rotating gradient ring, breathing core and
/// radar-style pulse rings.
class _ConnectOrb extends StatefulWidget {
  final double size;
  final VoidCallback onTap;
  final String filter;
  const _ConnectOrb({required this.size, required this.onTap, required this.filter});

  @override
  State<_ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<_ConnectOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final label = switch (widget.filter) {
      'female' => 'Talk to a woman',
      'male' => 'Talk to a man',
      _ => 'Talk to a stranger',
    };
    return Column(
      children: [
        SizedBox(
          width: s * 1.25,
          height: s * 1.25,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PulseRings(size: s * 1.25, color: AppColors.pink),
              // Static glow: a gradient instead of an animated blur shadow,
              // which would be re-rasterized every frame.
              IgnorePointer(
                child: Container(
                  width: s * 1.3,
                  height: s * 1.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.pink.withValues(alpha: 0.35),
                      AppColors.pink.withValues(alpha: 0),
                    ], stops: const [
                      0.55,
                      1
                    ]),
                  ),
                ),
              ),
              Pressable(
                onTap: widget.onTap,
                pressedScale: 0.92,
                child: RepaintBoundary(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RotationTransition(
                        turns: _spin,
                        child: Container(
                          width: s,
                          height: s,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(colors: [
                              AppColors.pink,
                              AppColors.violet,
                              AppColors.cyan,
                              AppColors.violet,
                              AppColors.pink,
                            ]),
                          ),
                        ),
                      ),
                      Container(
                        width: s - 10,
                        height: s - 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0xFF2A1B4D), Color(0xFF120F26)],
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (r) => AppColors.brandGradient.createShader(r),
                            child: Icon(Icons.call_rounded, size: s * 0.3, color: Colors.white),
                          )
                              .animate(onPlay: (c) => c.repeat())
                              .shake(delay: 1800.ms, hz: 6, rotation: 0.12, duration: 600.ms),
                          const SizedBox(height: 6),
                          const Text(
                            'TAP TO CONNECT',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 0.97, end: 1.03, duration: 1600.ms, curve: Curves.easeInOut),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            label,
            key: ValueKey(label),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
