import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'history_series.dart';

enum MicrochartStyle { line, bars }

class MicrochartTab {
  final String label;
  final HistorySeries series;
  final String? spanOverride;

  const MicrochartTab({required this.label, required this.series, this.spanOverride});
}

class MicrochartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final HistorySeries series;
  final String? spanOverride;
  final String unit;
  final int decimals;
  final MicrochartStyle style;
  final bool showTotal;
  final (double, double)? optimalBand;
  final int? splitAt;
  final EdgeInsetsGeometry margin;

  const MicrochartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.series,
    this.spanOverride,
    this.unit = '',
    this.decimals = 0,
    this.style = MicrochartStyle.line,
    this.showTotal = false,
    this.optimalBand,
    this.splitAt,
    this.margin = const EdgeInsets.only(top: 10),
  });

  @override
  Widget build(BuildContext context) => _MicrochartFrame(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accent: accent,
        series: series,
        spanOverride: spanOverride,
        unit: unit,
        decimals: decimals,
        style: style,
        showTotal: showTotal,
        optimalBand: optimalBand,
        splitAt: splitAt,
        margin: margin,
      );
}

class TabbedMicrochartCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<MicrochartTab> tabs;
  final String unit;
  final int decimals;
  final MicrochartStyle style;
  final bool showTotal;
  final int initialIndex;

  const TabbedMicrochartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.tabs,
    this.unit = '',
    this.decimals = 0,
    this.style = MicrochartStyle.line,
    this.showTotal = false,
    this.initialIndex = 0,
  });

  @override
  State<TabbedMicrochartCard> createState() => _TabbedMicrochartCardState();
}

class _TabbedMicrochartCardState extends State<TabbedMicrochartCard> {
  late int _selected = widget.initialIndex.clamp(0, math.max(0, widget.tabs.length - 1));
  bool _userPicked = false;

  @override
  void didUpdateWidget(TabbedMicrochartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected >= widget.tabs.length) {
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) return const SizedBox.shrink();
    var idx = _selected.clamp(0, widget.tabs.length - 1);
    if (!_userPicked && widget.tabs[idx].series.isEmpty) {
      final firstNonEmpty = widget.tabs.indexWhere((t) => t.series.isNotEmpty);
      if (firstNonEmpty >= 0) idx = firstNonEmpty;
    }
    final active = widget.tabs[idx];
    return _MicrochartFrame(
      title: widget.title,
      icon: widget.icon,
      accent: widget.accent,
      series: active.series,
      spanOverride: active.spanOverride,
      unit: widget.unit,
      decimals: widget.decimals,
      style: widget.style,
      showTotal: widget.showTotal,
      tabs: widget.tabs,
      selectedIndex: idx,
      onSelectTab: (i) => setState(() {
        _selected = i;
        _userPicked = true;
      }),
    );
  }
}

class _MicrochartFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final HistorySeries series;
  final String? spanOverride;
  final String unit;
  final int decimals;
  final MicrochartStyle style;
  final bool showTotal;
  final (double, double)? optimalBand;
  final int? splitAt;
  final EdgeInsetsGeometry margin;
  final List<MicrochartTab>? tabs;
  final int selectedIndex;
  final ValueChanged<int>? onSelectTab;

  const _MicrochartFrame({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.series,
    this.spanOverride,
    this.unit = '',
    this.decimals = 0,
    this.style = MicrochartStyle.line,
    this.showTotal = false,
    this.optimalBand,
    this.splitAt,
    this.margin = const EdgeInsets.only(top: 10),
    this.tabs,
    this.selectedIndex = 0,
    this.onSelectTab,
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
    final heroValue = showTotal ? series.sum : series.latest;
    final minOrAvg = showTotal ? series.average : series.min;
    final minOrAvgLabel = showTotal ? 'Avg ${_fmt(minOrAvg)}' : 'Min ${_fmt(minOrAvg)}';
    final maxV = series.max;
    final span = spanOverride ?? series.spanLabel;
    final hasTabs = tabs != null && tabs!.length > 1;

    return Card(
      margin: margin,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: theme.textTheme.labelSmall?.copyWith(color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
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
                  _fmt(heroValue),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (hasTabs) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabs!.length; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i + 1 < tabs!.length ? 6 : 0),
                        child: _RangePill(
                          label: tabs![i].label,
                          selected: i == selectedIndex,
                          accent: accent,
                          onTap: () => onSelectTab?.call(i),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
                        optimalBand: optimalBand,
                        splitAt: splitAt,
                      ),
                    ),
            ),
            if (series.isNotEmpty) ...[
              if (series.values.length >= 2) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(series.labelForIndex(0), style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: muted)),
                    if (series.values.length >= 5)
                      Text(series.labelForIndex(series.values.length ~/ 2),
                          style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: muted)),
                    Text(series.labelForIndex(series.values.length - 1),
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: muted)),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      minOrAvgLabel,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${series.values.length} × ${series.intervalLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Max ${_fmt(maxV)}',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RangePill({required this.label, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? accent : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double?> values;
  final Color accent;
  final MicrochartStyle style;
  final (double, double)? optimalBand;
  final int? splitAt;

  const _SparklinePainter({
    required this.values,
    required this.accent,
    required this.style,
    this.optimalBand,
    this.splitAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nonNull = [for (final v in values) if (v != null) v];
    if (nonNull.isEmpty || size.width <= 0 || size.height <= 0) return;

    var minV = nonNull.reduce(math.min);
    var maxV = nonNull.reduce(math.max);
    if (style == MicrochartStyle.bars && minV > 0) {
      minV = 0;
    }
    if (optimalBand != null) {
      minV = math.min(minV, math.max(0.0, optimalBand!.$1 - 20));
      maxV = math.max(maxV, optimalBand!.$2 + 5);
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

    double yAt(double v) => padY + (1.0 - ((v - minV) / range).clamp(0.0, 1.0)) * drawH;

    if (optimalBand != null) {
      final yTop = yAt(math.min(maxV, optimalBand!.$2));
      final yBot = yAt(math.max(minV, optimalBand!.$1));
      if (yBot > yTop) {
        canvas.drawRect(
          Rect.fromLTRB(0, yTop, size.width, yBot),
          Paint()..color = const Color(0xFF22C55E).withValues(alpha: 0.12),
        );
      }
    }

    final n = values.length;
    if (splitAt != null && splitAt! > 0 && n > splitAt!) {
      final sx = style == MicrochartStyle.bars
          ? (splitAt! / n) * size.width
          : (splitAt! / (n - 1)) * size.width;
      final splitPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      for (var y = padY; y < size.height - padY; y += 6) {
        canvas.drawLine(Offset(sx, y), Offset(sx, math.min(y + 3, size.height - padY)), splitPaint);
      }
    }

    if (style == MicrochartStyle.bars) {
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

    double xAt(int i) => n <= 1 ? size.width / 2 : (i / (n - 1)) * size.width;

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
    for (var i = 0; i < n; i++) {
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
      old.values != values ||
      old.accent != accent ||
      old.style != style ||
      old.optimalBand != optimalBand ||
      old.splitAt != splitAt;
}
