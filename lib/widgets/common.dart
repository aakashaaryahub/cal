import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'pressable.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final Gradient gradient;
  final Color textColor;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.loading = false,
    this.gradient = AppColors.brandGradient,
    this.textColor = Colors.white,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Pressable(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(height / 2.6),
            boxShadow: [
              if (onTap != null)
                BoxShadow(
                  color: gradient.colors.first.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: a, child: c),
            ),
            child: loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: textColor),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(icon, color: textColor, size: 20),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Gradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.borderColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppColors.surface.withValues(alpha: 0.72) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.stroke),
      ),
      child: child,
    );
  }
}

const _avatarGradients = [
  [Color(0xFFFF4D8D), Color(0xFF7B5CFF)],
  [Color(0xFF22D3EE), Color(0xFF7B5CFF)],
  [Color(0xFFFFC94D), Color(0xFFFF4D8D)],
  [Color(0xFF34E39A), Color(0xFF22D3EE)],
  [Color(0xFFFF9F43), Color(0xFFFF4D5E)],
];

/// Initials on a gradient picked from the name, with an optional flag badge.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? countryCode;

  const InitialsAvatar({super.key, required this.name, this.size = 56, this.countryCode});

  @override
  Widget build(BuildContext context) {
    final colors = _avatarGradients[name.hashCode.abs() % _avatarGradients.length];
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
              ),
            ),
          ),
          if (countryCode != null && countryCode!.isNotEmpty)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: EdgeInsets.all(size * 0.04),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Text(flagEmoji(countryCode!), style: TextStyle(fontSize: size * 0.26)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Concentric rings that expand and fade out, forever.
class PulseRings extends StatefulWidget {
  final double size;
  final Color color;
  final int rings;
  final Duration period;

  const PulseRings({
    super.key,
    required this.size,
    this.color = AppColors.pink,
    this.rings = 3,
    this.period = const Duration(milliseconds: 2400),
  });

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RingsPainter(_c, widget.color, widget.rings),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;
  final int rings;

  _RingsPainter(this.t, this.color, this.rings) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < rings; i++) {
      final p = (t.value + i / rings) % 1.0;
      final r = maxR * (0.35 + 0.65 * Curves.easeOut.transform(p));
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - p) * 0.55);
      canvas.drawCircle(center, r, paint);
      canvas.drawCircle(
        center,
        r,
        Paint()..color = color.withValues(alpha: (1 - p) * 0.06),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.color != color;
}

/// Small live dot that breathes.
class LiveDot extends StatelessWidget {
  final Color color;
  final double size;
  const LiveDot({super.key, this.color = AppColors.green, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.75, end: 1.15, duration: 900.ms, curve: Curves.easeInOut);
  }
}

/// Animated equaliser bars, optionally driven by a live 0..1 level.
class SoundBars extends StatelessWidget {
  final ValueNotifier<double>? level;
  final Color color;
  final int bars;
  final double height;

  const SoundBars({
    super.key,
    this.level,
    this.color = Colors.white,
    this.bars = 5,
    this.height = 22,
  });

  @override
  Widget build(BuildContext context) {
    if (level == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(bars, (i) {
          return Container(
            width: 3.5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true), delay: (i * 120).ms)
              .scaleY(begin: 0.25, end: 1, duration: (420 + i * 60).ms, curve: Curves.easeInOut);
        }),
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: level!,
      builder: (_, v, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(bars, (i) {
          final shape = 0.55 + 0.45 * sin((i + 1) * 1.7);
          final h = height * (0.18 + 0.82 * (v * shape).clamp(0.0, 1.0));
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 3.5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          );
        }),
      ),
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: error ? AppColors.danger : AppColors.green,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ));
}

/// Fade + scale page transition used throughout the app.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
