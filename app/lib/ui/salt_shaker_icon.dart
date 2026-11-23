// Salt shaker icon for Flutter-drawn navigation (Android, or iOS without the native tab bar).
// Same 24x24 drawing as ios/Runner/Assets.xcassets/saltshaker.imageset/saltshaker.svg, which
// the native tab bar uses; neither SF Symbols nor Material Icons include a salt shaker.
import 'package:flutter/material.dart';

class SaltShakerIcon extends StatelessWidget {
  final double? size;
  final Color? color;
  const SaltShakerIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final s = size ?? iconTheme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(painter: _SaltShakerPainter(color ?? iconTheme.color ?? Colors.black)),
    );
  }
}

class _SaltShakerPainter extends CustomPainter {
  final Color color;
  _SaltShakerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;

    // Domed cap with three pour holes (even-odd cut-outs).
    final cap = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBAndCorners(7, 3, 17, 8,
          topLeft: const Radius.circular(3.5), topRight: const Radius.circular(3.5)))
      ..addOval(Rect.fromCircle(center: const Offset(9.9, 6.4), radius: 0.8))
      ..addOval(Rect.fromCircle(center: const Offset(12, 5.7), radius: 0.8))
      ..addOval(Rect.fromCircle(center: const Offset(14.1, 6.4), radius: 0.8));
    canvas.drawPath(cap, paint);

    // Collar.
    canvas.drawRRect(RRect.fromLTRBR(6.3, 8.6, 17.7, 10.4, const Radius.circular(0.9)), paint);

    // Body, slightly flared toward the base.
    final body = Path()
      ..moveTo(7.2, 11)
      ..lineTo(16.8, 11)
      ..lineTo(17.9, 20.3)
      ..quadraticBezierTo(18.1, 22, 16.4, 22)
      ..lineTo(7.6, 22)
      ..quadraticBezierTo(5.9, 22, 6.1, 20.3)
      ..close();
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(_SaltShakerPainter old) => old.color != color;
}
