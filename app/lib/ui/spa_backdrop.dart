// Full-screen, heavily blurred hot tub scene painted in code (no photo assets to license):
// a lit tub of turquoise water with underwater lights, rising steam, a stone rim and warm
// string-light bokeh against a night sky. A scrim on top keeps text readable.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SpaBackdrop extends StatelessWidget {
  final Widget child;
  const SpaBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
          child: const CustomPaint(painter: _HotTubScenePainter()),
        ),
      ),
      // Scrim: darker at the top (title) and bottom (navigation), lighter over the water.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3051419), Color(0x59051419), Color(0x66051419), Color(0xCC051419)],
            stops: [0, 0.35, 0.7, 1],
          ),
        ),
      ),
      child,
    ]);
  }
}

class _HotTubScenePainter extends CustomPainter {
  const _HotTubScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final full = Offset.zero & size;

    // Night sky.
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF040E16), Color(0xFF0B2633), Color(0xFF071C24)],
          stops: [0, 0.55, 1],
        ).createShader(full),
    );

    // Warm string-light bokeh across the top.
    final rnd = Random(7);
    for (var i = 0; i < 14; i++) {
      final x = w * (i + 0.5) / 14 + (rnd.nextDouble() - 0.5) * w * 0.05;
      final y = h * (0.10 + 0.06 * sin(i * 0.9)) + rnd.nextDouble() * h * 0.03;
      final r = w * (0.035 + rnd.nextDouble() * 0.03);
      final warm = Color.lerp(const Color(0xFFFFC46B), const Color(0xFFFF8A4C), rnd.nextDouble())!;
      canvas.drawCircle(Offset(x, y), r, Paint()..color = warm.withValues(alpha: 0.55));
    }

    // Tub: stone rim, then lit water inside it.
    final tubCenter = Offset(w * 0.5, h * 0.66);
    final rim = Rect.fromCenter(center: tubCenter, width: w * 1.25, height: h * 0.52);
    canvas.drawOval(
      rim,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A4A52), Color(0xFF1C272D)],
        ).createShader(rim),
    );
    final water = rim.deflate(w * 0.06);
    canvas.drawOval(
      water,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.15),
          radius: 0.75,
          colors: [Color(0xFF8DF6FF), Color(0xFF22C3D6), Color(0xFF0B6F86), Color(0xFF06404F)],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(water),
    );

    // Underwater light pools and shimmer.
    for (final (dx, dy, r, c) in [
      (0.32, 0.70, 0.16, const Color(0xFFB9FBFF)),
      (0.66, 0.74, 0.13, const Color(0xFF7FF0FF)),
      (0.50, 0.62, 0.10, const Color(0xFFE6FFFF)),
      (0.80, 0.64, 0.07, const Color(0xFF9F8CFF)),
    ]) {
      final o = Offset(w * dx, h * dy);
      canvas.drawCircle(
        o,
        w * r,
        Paint()
          ..shader = RadialGradient(colors: [c.withValues(alpha: 0.85), c.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: o, radius: w * r)),
      );
    }

    // Steam rising off the water.
    for (var i = 0; i < 7; i++) {
      final o = Offset(w * (0.15 + i * 0.12), h * (0.44 - (i % 3) * 0.05));
      canvas.drawOval(
        Rect.fromCenter(center: o, width: w * 0.32, height: h * 0.14),
        Paint()..color = Colors.white.withValues(alpha: 0.07),
      );
    }
  }

  @override
  bool shouldRepaint(_HotTubScenePainter oldDelegate) => false;
}
