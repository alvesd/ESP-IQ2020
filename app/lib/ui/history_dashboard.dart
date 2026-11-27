import 'package:flutter/material.dart';

import 'history_series.dart';
import 'spa_screen.dart' show saltZone;
import 'sparkline_chart.dart';

enum HistoryTimeframe { mtd, days31, year1, year2, recent14d }

extension HistoryTimeframeLabel on HistoryTimeframe {
  String get chipLabel => switch (this) {
        HistoryTimeframe.mtd => 'Daily · MTD',
        HistoryTimeframe.days31 => 'Daily · 31d',
        HistoryTimeframe.year1 => 'Monthly · 1yr',
        HistoryTimeframe.year2 => 'Annual · 2yr',
        HistoryTimeframe.recent14d => 'Recent · 14d (6h)',
      };

  String get resolutionNote => switch (this) {
        HistoryTimeframe.mtd => 'Current calendar month (1d buckets)',
        HistoryTimeframe.days31 => 'Rolling 31 days (1d buckets)',
        HistoryTimeframe.year1 => 'Trailing 12 months (1mo rollups)',
        HistoryTimeframe.year2 => '24-month annual trend (1mo rollups)',
        HistoryTimeframe.recent14d => 'Last 14 days (6h buckets; Energy/Heater in 1d)',
      };
}

class SettingsHistoryView extends StatelessWidget {
  final HistoryTimeframe timeframe;
  final ValueChanged<HistoryTimeframe> onTimeframeChanged;
  final String tempUnit;
  final HistorySeries waterRecent;
  final HistorySeries waterDaily;
  final HistorySeries waterMonthly;
  final HistorySeries powerRecent;
  final HistorySeries powerDaily;
  final HistorySeries powerMonthly;
  final HistorySeries energyDaily;
  final HistorySeries energyMonthly;
  final HistorySeries heaterDaily;
  final HistorySeries heaterMonthly;
  final HistorySeries saltRecent;
  final HistorySeries saltDaily;
  final HistorySeries saltMonthly;
  final HistorySeries freeHeapRecent;

  const SettingsHistoryView({
    super.key,
    required this.timeframe,
    required this.onTimeframeChanged,
    required this.tempUnit,
    required this.waterRecent,
    required this.waterDaily,
    required this.waterMonthly,
    required this.powerRecent,
    required this.powerDaily,
    required this.powerMonthly,
    required this.energyDaily,
    required this.energyMonthly,
    required this.heaterDaily,
    required this.heaterMonthly,
    required this.saltRecent,
    required this.saltDaily,
    required this.saltMonthly,
    required this.freeHeapRecent,
  });

  HistorySeries _pickAvg(HistorySeries recent, HistorySeries daily, HistorySeries monthly) => switch (timeframe) {
        HistoryTimeframe.mtd => daily.thisMonthOnly().isNotEmpty ? daily.thisMonthOnly() : daily,
        HistoryTimeframe.days31 => daily,
        HistoryTimeframe.year1 => monthly.lastN(12),
        HistoryTimeframe.year2 => monthly,
        HistoryTimeframe.recent14d => recent,
      };

  HistorySeries _pickTotal(HistorySeries daily, HistorySeries monthly) => switch (timeframe) {
        HistoryTimeframe.mtd => daily.thisMonthOnly().isNotEmpty ? daily.thisMonthOnly() : daily,
        HistoryTimeframe.days31 => daily,
        HistoryTimeframe.year1 => monthly.lastN(12),
        HistoryTimeframe.year2 => monthly,
        HistoryTimeframe.recent14d => daily.lastN(14),
      };

  String? _spanForAvg() => switch (timeframe) {
        HistoryTimeframe.mtd => 'MTD',
        HistoryTimeframe.days31 => '31d',
        HistoryTimeframe.year1 => '1yr',
        HistoryTimeframe.year2 => '2yr',
        HistoryTimeframe.recent14d => '14d · 6h',
      };

  String? _spanForTotal() => switch (timeframe) {
        HistoryTimeframe.mtd => 'MTD',
        HistoryTimeframe.days31 => '31d',
        HistoryTimeframe.year1 => '1yr',
        HistoryTimeframe.year2 => '2yr',
        HistoryTimeframe.recent14d => '14d (1d)',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const accentAqua = Color(0xFF4FE3EA);
    const accentHeat = Color(0xFFFF8A4C);
    const accentAmber = Color(0xFFE8A317);

    final energyS = _pickTotal(energyDaily, energyMonthly);
    final heaterS = _pickTotal(heaterDaily, heaterMonthly);
    final waterS = _pickAvg(waterRecent, waterDaily, waterMonthly);
    final powerS = _pickAvg(powerRecent, powerDaily, powerMonthly);
    final saltS = _pickAvg(saltRecent, saltDaily, saltMonthly);
    final split = timeframe == HistoryTimeframe.year2 ? 12 : null;

    final saltLatest = saltS.latest;
    final saltInfo = saltLatest == null ? null : saltZone(saltLatest);
    final saltAccent = saltInfo?.$2 ?? const Color(0xFF3D8BFD);

    final perUnit = (timeframe == HistoryTimeframe.year1 || timeframe == HistoryTimeframe.year2) ? 'mo' : 'day';
    String fmtNum(double? v, int dec, [String suffix = '']) {
      if (v == null) return '—';
      final s = dec == 0 ? v.round().toString() : v.toStringAsFixed(dec);
      return suffix.isEmpty ? s : '$s $suffix';
    }

    final kpis = [
      (
        label: 'Total Energy',
        value: fmtNum(energyS.sum, 1, 'kWh'),
        sub: energyS.average == null ? 'Collecting…' : 'Avg ${fmtNum(energyS.average, 1, 'kWh')}/$perUnit',
        subColor: muted,
      ),
      (
        label: 'Heater Runtime',
        value: fmtNum(heaterS.sum, 1, 'h'),
        sub: heaterS.average == null ? 'Collecting…' : 'Avg ${fmtNum(heaterS.average, 1, 'h')}/$perUnit',
        subColor: muted,
      ),
      (
        label: 'Water Temp',
        value: fmtNum(waterS.average, 1, tempUnit),
        sub: (waterS.min != null && waterS.max != null)
            ? '${waterS.min!.toStringAsFixed(1)}–${waterS.max!.toStringAsFixed(1)}$tempUnit'
            : 'Collecting…',
        subColor: muted,
      ),
      (
        label: 'Salt Level',
        value: saltLatest == null ? '—' : '${saltLatest.round()}',
        sub: saltInfo?.$1 ?? 'Collecting…',
        subColor: saltInfo?.$2 ?? muted,
      ),
    ];

    final cards = [
      MicrochartCard(
        title: 'Energy Consumption',
        subtitle: 'Pumps + Controller + Heater',
        icon: Icons.bar_chart,
        accent: accentAqua,
        series: energyS,
        spanOverride: _spanForTotal(),
        unit: 'kWh',
        decimals: energyS.isMonthly ? 1 : 2,
        style: MicrochartStyle.bars,
        showTotal: true,
        splitAt: split,
        margin: EdgeInsets.zero,
      ),
      MicrochartCard(
        title: 'Heater Runtime',
        subtitle: 'Active heating hours',
        icon: Icons.local_fire_department,
        accent: accentHeat,
        series: heaterS,
        spanOverride: _spanForTotal(),
        unit: 'h',
        decimals: 1,
        style: MicrochartStyle.bars,
        showTotal: true,
        splitAt: split,
        margin: EdgeInsets.zero,
      ),
      MicrochartCard(
        title: 'Water Temperature',
        subtitle: 'Average water temp',
        icon: Icons.thermostat,
        accent: accentHeat,
        series: waterS,
        spanOverride: _spanForAvg(),
        unit: tempUnit,
        decimals: 1,
        splitAt: split,
        margin: EdgeInsets.zero,
      ),
      MicrochartCard(
        title: 'Total Power Draw',
        subtitle: 'Combined electrical load',
        icon: Icons.bolt,
        accent: accentAmber,
        series: powerS,
        spanOverride: _spanForAvg(),
        unit: 'W',
        splitAt: split,
        margin: EdgeInsets.zero,
      ),
      MicrochartCard(
        title: 'Salt Level',
        subtitle: 'Optimal band: 40–80',
        icon: Icons.water_drop,
        accent: saltAccent,
        series: saltS,
        spanOverride: _spanForAvg(),
        optimalBand: (40, 80),
        splitAt: split,
        margin: EdgeInsets.zero,
      ),
      MicrochartCard(
        title: 'ESP32 Free Heap',
        subtitle: 'Collected at 14d @ 6h',
        icon: Icons.memory,
        accent: accentAqua,
        series: freeHeapRecent,
        spanOverride: '14d · 6h',
        unit: 'KB',
        margin: EdgeInsets.zero,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tf in HistoryTimeframe.values)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onTimeframeChanged(tf),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: tf == timeframe
                        ? accentAqua.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: tf == timeframe
                          ? accentAqua.withValues(alpha: 0.75)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    tf.chipLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tf == timeframe ? accentAqua : muted,
                      fontWeight: tf == timeframe ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(timeframe.resolutionNote, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final kpiCols = constraints.maxWidth >= 640 ? 4 : 2;
            final cardCols = constraints.maxWidth >= 640 ? 2 : 1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGrid(kpiCols, 8, [
                  for (final k in kpis)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.label, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                            const SizedBox(height: 2),
                            Text(
                              k.value,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              k.sub,
                              style: theme.textTheme.labelSmall?.copyWith(color: k.subColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                _buildGrid(cardCols, 10, cards),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildGrid(int cols, double gap, List<Widget> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < cols; c++) {
        if (c > 0) rowChildren.add(SizedBox(width: gap));
        final idx = i + c;
        rowChildren.add(Expanded(child: idx < items.length ? items[idx] : const SizedBox.shrink()));
      }
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
