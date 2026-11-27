// Emulates the physical Hot Spring cabinet logo indicator light in the temperature card header.
import 'package:flutter/material.dart';

import '../api/messages.dart';

/// Operating states reported by the `iq2020` `logo_lights` sensor (states 0..7).
enum LogoLightState {
  unknown('Unknown'),
  powerOn('Power on'),
  powerAndReady('Power on & ready on'),
  readyFlash('Ready flash'),
  powerFlash('Power flash'),
  powerAndReadyFlash('Power & ready flash'),
  powerAndReadyAlternate('Power & ready alternate'),
  saltError('Salt error');

  final String label;
  const LogoLightState(this.label);

  bool get isAnimated => switch (this) {
        LogoLightState.unknown || LogoLightState.powerOn || LogoLightState.powerAndReady => false,
        _ => true,
      };

  Duration get period =>
      this == LogoLightState.saltError ? const Duration(milliseconds: 3500) : const Duration(seconds: 1);
}

/// Maps either the template text sensor (`"Power on & ready on"`, etc.) or the raw numeric
/// `logo_lights` sensor (`0..7`) into a [LogoLightState].
LogoLightState parseLogoLightState(EntityState? state) {
  if (state == null || state.missing) return LogoLightState.unknown;

  final text = state.text.trim().toLowerCase();
  if (text.isNotEmpty) {
    final numeric = int.tryParse(text);
    if (numeric != null) return _stateFromCode(numeric);
    if (text.contains('salt')) return LogoLightState.saltError;
    if (text.contains('alternate')) return LogoLightState.powerAndReadyAlternate;
    final hasPower = text.contains('power');
    final hasReady = text.contains('ready');
    final hasFlash = text.contains('flash');
    if (hasPower && hasReady && hasFlash) return LogoLightState.powerAndReadyFlash;
    if (hasPower && hasFlash) return LogoLightState.powerFlash;
    if (hasReady && hasFlash) return LogoLightState.readyFlash;
    if (hasPower && hasReady) return LogoLightState.powerAndReady;
    if (hasPower) return LogoLightState.powerOn;
    return LogoLightState.unknown;
  }

  if (!state.number.isNaN) return _stateFromCode(state.number.round());
  return LogoLightState.unknown;
}

LogoLightState _stateFromCode(int code) => switch (code) {
      1 => LogoLightState.powerOn,
      2 => LogoLightState.powerAndReady,
      3 => LogoLightState.readyFlash,
      4 => LogoLightState.powerFlash,
      5 => LogoLightState.powerAndReadyFlash,
      6 => LogoLightState.powerAndReadyAlternate,
      7 => LogoLightState.saltError,
      _ => LogoLightState.unknown,
    };

/// Returns `(greenLit, blueLit)` for [state] at animation [phase] in `[0.0, 1.0)`.
(bool green, bool blue) logoLightLedsAt(LogoLightState state, double phase) => switch (state) {
      LogoLightState.unknown => (false, false),
      LogoLightState.powerOn => (false, true),
      LogoLightState.powerAndReady => (true, true),
      LogoLightState.readyFlash => (phase < 0.5, true),
      LogoLightState.powerFlash => (false, phase < 0.5),
      LogoLightState.powerAndReadyFlash => (phase < 0.5, phase < 0.5),
      LogoLightState.powerAndReadyAlternate => (phase < 0.5, phase >= 0.5),
      LogoLightState.saltError => (phase < 0.29, true),
    };

final _svgTokenRe = RegExp(r'[MmLlHhVvCcSsZz]|[-+]?(?:\d*\.\d+|\d+)');

/// Parses a subset of SVG path commands (`M/L/H/V/C/S/Z`) into a Flutter [Path].
Path parseHotSpringSvgPath(String d, {PathFillType fillType = PathFillType.nonZero}) {
  final tokens = _svgTokenRe.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path()..fillType = fillType;
  var i = 0;
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
  var lastCp2x = 0.0, lastCp2y = 0.0;
  String? cmd;
  String? prevCmd;

  double next() => double.parse(tokens[i++]);
  bool isCmd(String s) => s.length == 1 && RegExp(r'[A-Za-z]').hasMatch(s);

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
      case 'm':
        final rel = cmd == 'm';
        cx = (rel ? cx : 0) + next();
        cy = (rel ? cy : 0) + next();
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
        prevCmd = cmd;
        cmd = rel ? 'l' : 'L';
      case 'L':
      case 'l':
        final rel = cmd == 'l';
        cx = (rel ? cx : 0) + next();
        cy = (rel ? cy : 0) + next();
        path.lineTo(cx, cy);
        prevCmd = cmd;
      case 'H':
      case 'h':
        cx = (cmd == 'h' ? cx : 0) + next();
        path.lineTo(cx, cy);
        prevCmd = cmd;
      case 'V':
      case 'v':
        cy = (cmd == 'v' ? cy : 0) + next();
        path.lineTo(cx, cy);
        prevCmd = cmd;
      case 'C':
      case 'c':
        final rel = cmd == 'c';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        final x = ox + next(), y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCp2x = x2;
        lastCp2y = y2;
        cx = x;
        cy = y;
        prevCmd = cmd;
      case 'S':
      case 's':
        final rel = cmd == 's';
        final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
        final hasPrevCubic = prevCmd == 'C' || prevCmd == 'c' || prevCmd == 'S' || prevCmd == 's';
        final x1 = hasPrevCubic ? 2 * cx - lastCp2x : cx;
        final y1 = hasPrevCubic ? 2 * cy - lastCp2y : cy;
        final x2 = ox + next(), y2 = oy + next();
        final x = ox + next(), y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCp2x = x2;
        lastCp2y = y2;
        cx = x;
        cy = y;
        prevCmd = cmd;
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
        prevCmd = cmd;
        cmd = null;
      default:
        throw FormatException('Unsupported SVG path command: $cmd');
    }
  }
  return path;
}

/// Physical Hot Spring cabinet badge (circular glowing swirl medallion + brushed nameplate)
/// with the human-readable status label displayed underneath.
class LogoLightBadge extends StatefulWidget {
  final LogoLightState state;
  final String? customLabel;
  final double height;

  const LogoLightBadge({
    super.key,
    required this.state,
    this.customLabel,
    this.height = 32,
  });

  @override
  State<LogoLightBadge> createState() => _LogoLightBadgeState();
}

class _LogoLightBadgeState extends State<LogoLightBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.state.period);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(LogoLightBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _controller.duration = widget.state.period;
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.state.isAnimated) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (widget.customLabel != null && widget.customLabel!.isNotEmpty)
        ? widget.customLabel!
        : widget.state.label;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: widget.height * (134 / 43),
            height: widget.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                final (green, blue) = logoLightLedsAt(widget.state, _controller.value);
                return CustomPaint(
                  painter: _HotSpringCabinetBadgePainter(greenLit: green, blueLit: blue),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 10.5,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _HotSpringCabinetBadgePainter extends CustomPainter {
  final bool greenLit;
  final bool blueLit;
  _HotSpringCabinetBadgePainter({required this.greenLit, required this.blueLit});

  static final Path _greenSwirl = parseHotSpringSvgPath(
    'M3.1,28.77c-2.42-3.15-3.73-7.05-3.72-11.06c0-9.94,7.89-17.99,17.62-17.99 '
    'c4.6,0,9.02,1.84,12.31,5.13l-2.67,2.73C10.01-5.61-4.66,12.91,1.15,25.1C-3.48,8.85,14.77-0.14,24.36,9.92l-2.61,2.66 '
    'C10.14,2.52-2.83,15.51,1.73,25.84C-0.87,11.25,14.38,8.65,19.6,14.78c-0.91,1.13-2.61,2.8-2.61,2.8 '
    'C9.1,10.45-1.59,18.84,3.1,28.77L3.1,28.77z',
  );

  static final Path _blueSwirl = parseHotSpringSvgPath(
    'M30.88,6.45c2.42,3.15,3.73,7.05,3.72,11.06c-0.01,9.94-7.9,17.99-17.62,17.99 '
    'c-4.6,0-9.02-1.84-12.3-5.13l2.67-2.73c16.63,13.19,31.3-5.33,25.49-17.52C37.46,26.37,19.21,35.36,9.62,25.3l2.61-2.66 '
    'C23.84,32.7,36.81,19.71,32.24,9.38c2.61,14.59-12.65,17.19-17.86,11.06c0.91-1.13,2.61-2.8,2.61-2.8 '
    'C24.88,24.71,35.57,16.38,30.88,6.45L30.88,6.45z',
  );

  static final Path _wordmark = parseHotSpringSvgPath(
    'M46.92,15.11V8.58h3.19v16.25h-3.19v-7.26h-3.59v7.26h-3.19V8.58h3.19v6.53L46.92,15.11z'
    'M50.89,18.64c0-3.33,0.46-6.2,4.62-6.2s4.62,2.86,4.62,6.2c0,3.86-0.52,6.53-4.62,6.53 C51.47,25.17,50.89,22.44,50.89,18.64z '
    'M57.02,18.44c0-2.53-0.13-3.86-1.5-3.86c-1.37,0-1.5,1.27-1.5,3.86 c0,3.73,0.33,4.53,1.5,4.53C56.76,22.97,57.02,22.18,57.02,18.44z'
    'M61,10.58l3.19-1.53v3.46h1.63v2.13h-1.63v6.59c0,0.93,0,1.53,1.04,1.53c0.2,0.01,0.4-0.01,0.59-0.07v2.13 '
    'c-0.54,0.09-1.08,0.13-1.63,0.13c-2.74,0-3.13-2-3.13-2.73V10.58L61,10.58z'
    'M70.58,25.17c-3.19,0-4.82-2.27-4.5-5.33h3c0,1.53,0.2,2.86,1.96,2.86c1.09,0.07,2.04-0.75,2.15-1.86 '
    'c0-4.06-6.98-1.93-6.98-7.93c0-2.53,1.17-4.6,5.09-4.6c3.06,0,4.76,1.13,4.69,4.6h-3.06c0-1.2-0.52-2.33-1.76-2.33 '
    'c-0.97-0.01-1.76,0.78-1.77,1.77c0,0.05,0,0.11,0.01,0.16c0,3.8,7.11,1.53,7.11,7.93C76.45,24.63,73,25.17,70.58,25.17L70.58,25.17 z'
    'M80.1,28.1h-2.93V12.45h2.8v1.27h0.07c0.42-0.99,1.43-1.58,2.48-1.47c3.39,0,3.72,3.66,3.72,6 '
    's-0.13,6.86-3.65,6.86c-1.02,0.16-2.03-0.38-2.48-1.33V28.1L80.1,28.1z '
    'M83.23,18.58c0-2.27-0.33-3.86-1.63-3.86 c-1.24,0-1.56,1.6-1.56,3.86c0,2.86,0.59,4.06,1.56,4.06C82.71,22.64,83.23,21.44,83.23,18.58z'
    'M89.82,12.58v1.6h0.07c0.53-1.28,1.85-2.03,3.19-1.8v2.86c-2.8-0.2-3.13,0.87-3.13,3v6.66h-3.19V12.58 H89.82z'
    'M96.86,24.9h-2.93V12.58h2.93V24.9L96.86,24.9z M96.86,8.98v2.66h-2.93V8.98L96.86,8.98z'
    'M100.9,13.91L100.9,13.91c0.64-1.13,1.86-1.78,3.13-1.67c1.57-0.02,2.85,1.26,2.87,2.86v9.86h-3v-8.46 '
    'c0-1.07-0.39-1.8-1.37-1.8c-1.04,0-1.56,0.73-1.56,1.8v8.46h-3.13V12.65h3.06V13.91L100.9,13.91z'
    'M113.81,23.24c-0.69,0.77-1.65,1.23-2.67,1.27c-3.46,0-3.59-3.86-3.59-6.46c0-2.53,0.39-5.8,3.78-5.8 '
    'c1.08-0.02,2.07,0.64,2.48,1.67h0.07v-1.33h2.8v11.86c0,0.8-0.59,3.93-4.63,3.93c-1.7,0-4.11-0.47-4.17-3.2h2.87 '
    'c0.02,0.68,0.58,1.21,1.24,1.2c0.92,0.02,1.68-0.72,1.7-1.65c0,0,0-0.01,0-0.01L113.81,23.24L113.81,23.24z '
    'M112.24,22.17 c1.04,0,1.5-1.13,1.5-3.53c0-2.53-0.46-4-1.56-4s-1.5,0.87-1.5,4.33C110.68,20.04,110.81,22.17,112.24,22.17z',
    fillType: PathFillType.evenOdd,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // ViewBox (-4, -4, 134, 43) matching the physical cabinet badge proportions.
    canvas.scale(size.width / 134, size.height / 43);
    canvas.translate(4, 4);

    // Subtle drop shadow behind the plaque and circular housing.
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    final outerRect = RRect.fromLTRBR(17, 2.2, 124, 32.8, const Radius.circular(5.5));
    const medallionCenter = Offset(17.6, 17.55);
    canvas.drawRRect(outerRect.shift(const Offset(0, 1.5)), shadowPaint);
    canvas.drawCircle(medallionCenter + const Offset(0, 1.5), 19.2, shadowPaint);

    // Dark nameplate frame + brushed silver plate.
    canvas.drawRRect(outerRect, Paint()..color = const Color(0xFF0D1318));
    canvas.drawRRect(
      outerRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    final plateRect = RRect.fromLTRBR(28, 4.3, 121.5, 30.7, const Radius.circular(3.8));
    canvas.drawRRect(
      plateRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDFE4E8), Color(0xFFB8C1C8), Color(0xFF8B959E)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(plateRect.outerRect),
    );

    // Subtle light wave highlight across the brushed plate.
    canvas.save();
    canvas.clipRRect(plateRect);
    final wave = Path()
      ..moveTo(36, 22)
      ..quadraticBezierTo(68, 12, 121.5, 18)
      ..lineTo(121.5, 30.7)
      ..lineTo(36, 30.7)
      ..close();
    canvas.drawPath(wave, Paint()..color = Colors.white.withValues(alpha: 0.16));
    canvas.restore();

    // HotSpring wordmark.
    canvas.save();
    canvas.translate(3, 1.0);
    canvas.scale(0.96);
    canvas.drawPath(_wordmark, Paint()..color = const Color(0xFF11181E));
    canvas.restore();

    // Raised circular swirl housing with chrome rim.
    canvas.drawCircle(medallionCenter, 19.2, Paint()..color = const Color(0xFF0B1015));
    final rimRect = Rect.fromCircle(center: medallionCenter, radius: 19.2);
    canvas.drawCircle(
      medallionCenter,
      19.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF2F5F7), Color(0xFF9AA4AD), Color(0xFF4E5861)],
        ).createShader(rimRect),
    );
    final innerRect = Rect.fromCircle(center: medallionCenter, radius: 17.4);
    canvas.drawCircle(
      medallionCenter,
      17.4,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.16, -0.24),
          radius: 1.1,
          colors: [Color(0xFF19232C), Color(0xFF070C10)],
        ).createShader(innerRect),
    );

    // Interlocking swirl halves: top-left = Green (Ready), bottom-right = Blue (Power).
    canvas.save();
    canvas.translate(3.0, 2.4);
    canvas.scale(0.855);
    _drawSwirl(canvas, _greenSwirl, greenLit, const Color(0xFF2EF07A));
    _drawSwirl(canvas, _blueSwirl, blueLit, const Color(0xFF2EB0FF));
    canvas.restore();

    canvas.restore();
  }

  void _drawSwirl(Canvas canvas, Path path, bool lit, Color color) {
    if (lit) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
      );
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas.drawPath(path, Paint()..color = const Color(0xFF3A464D));
    }
  }

  @override
  bool shouldRepaint(_HotSpringCabinetBadgePainter old) =>
      old.greenLit != greenLit || old.blueLit != blueLit;
}
