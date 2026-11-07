import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Slowly drifting colour blobs behind the content. Cheap to paint (no blur
/// filters) and isolated in its own repaint boundary.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final double intensity;

  const AuroraBackground({
    super.key,
    required this.child,
    this.colors = const [AppColors.pink, AppColors.violet, AppColors.cyan],
    this.intensity = 0.32,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  // The blobs drift slowly, so ~15 fps looks identical to 60 fps while
  // cutting full-screen repaints by 75% (matters on low-end phones and on
  // emulators using software rendering).
  final _phase = ValueNotifier<double>(0);
  static const _frameGap = 1 / (24 * 15);

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final d = (_c.value - _phase.value).abs();
      if (d >= _frameGap && d < 1 - _frameGap) _phase.value = _c.value;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.background)),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AuroraPainter(_phase, widget.colors, widget.intensity),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final ValueListenable<double> t;
  final List<Color> colors;
  final double intensity;

  _AuroraPainter(this.t, this.colors, this.intensity) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t.value * 2 * pi;
    for (var i = 0; i < colors.length; i++) {
      final offset = i * 2.1;
      final center = Offset(
        size.width * (0.5 + 0.38 * sin(phase + offset)),
        size.height * (0.35 + 0.3 * cos(phase * 0.7 + offset)),
      );
      final radius = size.width * (0.7 + 0.12 * sin(phase * 1.3 + offset));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: intensity),
            colors[i].withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.colors != colors || old.intensity != intensity;
}
