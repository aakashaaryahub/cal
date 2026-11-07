import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/remote_config.dart';
import '../../services/config_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// First onboarding page: people from around the world orbiting a call button.
class IntroHero extends StatefulWidget {
  const IntroHero({super.key});

  @override
  State<IntroHero> createState() => _IntroHeroState();
}

class _IntroHeroState extends State<IntroHero> with SingleTickerProviderStateMixin {
  late final AnimationController _orbit =
      AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Copy and avatars come from the server; rebuild if fresh config arrives.
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: ConfigStore.notifier,
      builder: (context, cfg, _) => _build(cfg),
    );
  }

  Widget _build(RemoteConfig cfg) {
    final people = cfg.introAvatars;
    return LayoutBuilder(builder: (context, box) {
      final size = min(box.maxWidth - 32, box.maxHeight * 0.55);
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            SizedBox(
              width: size,
              height: size,
              child: AnimatedBuilder(
                animation: _orbit,
                builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    PulseRings(size: size * 0.8, color: AppColors.violet),
                    _orbitPath(size * 0.82),
                    _orbitPath(size * 0.52),
                    Container(
                      width: size * 0.26,
                      height: size * 0.26,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: AppColors.pink.withValues(alpha: 0.55), blurRadius: 36),
                        ],
                      ),
                      child: Icon(Icons.call_rounded, color: Colors.white, size: size * 0.11),
                    ),
                    for (var i = 0; i < people.length; i++) _orbiter(people, i, size),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 700.ms).scale(begin: const Offset(0.85, 0.85), curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              cfg.introTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8),
            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.3),
            const SizedBox(height: 12),
            Text(
              cfg.introSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.45),
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (i, t) in cfg.introChips.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ).animate().fadeIn(delay: (550 + i * 100).ms).scale(begin: const Offset(0.8, 0.8)),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _orbitPath(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
      );

  Widget _orbiter(List<IntroAvatar> people, int i, double size) {
    final inner = i.isOdd;
    final radius = size * (inner ? 0.26 : 0.41);
    final speed = inner ? -1.4 : 1.0;
    final angle = _orbit.value * 2 * pi * speed + i * (2 * pi / people.length);
    final avatar = size * (inner ? 0.13 : 0.16);
    final bob = sin(_orbit.value * 2 * pi * 6 + i) * 3;
    return Transform.translate(
      offset: Offset(cos(angle) * radius, sin(angle) * radius + bob),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)],
        ),
        child: InitialsAvatar(
          name: people[i].name,
          size: avatar,
          countryCode: people[i].countryCode,
        ),
      ),
    );
  }
}
