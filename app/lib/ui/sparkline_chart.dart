import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'history_series.dart';

enum MicrochartStyle { line, bars }

class MicrochartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final HistorySeries series;
  final String unit;
  final int decimals;
  final MicrochartStyle style;

  const MicrochartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.series,
    this.unit = '',
    this.decimals = 0,
    this.style = MicrochartStyle.line,
  });

  String _fmt(double? v) {
    if (v == null) return '—';
    final numStr = decimals == 0 ? v.round().toString() : v.toStringAsFixed(decimals);
    return unit.isEmpty ? numStr : '$numStr $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final latest = series.latest;
    final minV = series.min;
    final maxV = series.max;
    final span = series.spanLabel;

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent.withValues(alpha: 0.18),
                  child: Icon(icon, size: 15, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (span.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      span,
                      style: theme.textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  _fmt(latest),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: series.isEmpty
                  ? Center(
                      child: Text('Collecting history…', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    )
                  : CustomPaint(
                      painter: _SparklinePainter(
                        values: series.values,
                        accent: accent,
                        style: style,
                      ),
                    ),
            ),
            if (series.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Min ${_fmt(minV)}', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  Text(
                    '${series.values.length} × ${series.intervalLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  Text('Max ${_fmt(maxV)}', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double?> values;
  final Color accent;
  final MicrochartStyle style;

  const _SparklinePainter({required this.values, required this.accent, required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final nonNull = [for (final v in values) if (v != null) v];
    if (nonNull.isEmpty || size.width <= 0 || size.height <= 0) return;

    var minV = nonNull.reduce(math.min);
    var maxV = nonNull.reduce(math.max);
    if (style == MicrochartStyle.bars && minV > 0) {
      minV = 0;
    }
    var range = maxV - minV;
    if (range < 1e-6) {
      range = 1.0;
      if (style == MicrochartStyle.line) {
        minV -= 0.5;
      }
    }

    const padY = 4.0;
    final drawH = math.max(1.0, size.height - padY * 2);

    // Baseline guide
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - padY), Offset(size.width, size.height - padY), gridPaint);

    if (style == MicrochartStyle.bars) {
      final n = values.length;
      final slotW = size.width / math.max(1, n);
      final barW = math.max(2.0, slotW * 0.64);
      final barPaint = Paint()..style = PaintingStyle.fill;

      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        final frac = ((v - minV) / range).clamp(0.05, 1.0);
        final h = frac * drawH;
        final x = i * slotW + (slotW - barW) / 2;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, padY + (drawH - h), barW, h),
          const Radius.circular(2.5),
        );
        barPaint.color = i == n - 1 ? accent : accent.withValues(alpha: 0.55);
        canvas.drawRRect(rect, barPaint);
      }
      return;
    }

    double xAt(int i) => values.length <= 1 ? size.width / 2 : (i / (values.length - 1)) * size.width;
    double yAt(double v) => padY + (1.0 - ((v - minV) / range).clamp(0.0, 1.0)) * drawH;

    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent.withValues(alpha: 0.28), accent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    var segment = <Offset>[];
    void flushSegment() {
      if (segment.isEmpty) return;
      if (segment.length >= 2) {
        final linePath = Path()..moveTo(segment.first.dx, segment.first.dy);
        for (var i = 1; i < segment.length; i++) {
          linePath.lineTo(segment[i].dx, segment[i].dy);
        }
        final areaPath = Path.from(linePath)
          ..lineTo(segment.last.dx, size.height - padY)
          ..lineTo(segment.first.dx, size.height - padY)
          ..close();
        canvas.drawPath(areaPath, fillPaint);
        canvas.drawPath(linePath, linePaint);
      } else {
        canvas.drawCircle(segment.first, 3.5, Paint()..color = accent);
      }
      segment = <Offset>[];
    }

    Offset? lastPt;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        flushSegment();
        continue;
      }
      final pt = Offset(xAt(i), yAt(v));
      segment.add(pt);
      lastPt = pt;
    }
    flushSegment();

    if (lastPt != null) {
      canvas.drawCircle(lastPt, 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(lastPt, 2.5, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.accent != accent || old.style != style;
}
