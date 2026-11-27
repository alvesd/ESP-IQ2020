import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/ui/history_series.dart';
import 'package:iq2020_mobile/ui/sparkline_chart.dart';

void main() {
  group('HistorySeries', () {
    test('parses 6h series with gaps and computes stats', () {
      final s = HistorySeries.parse('6h:101.2,102.0,,103.5');
      expect(s.intervalLabel, '6h');
      expect(s.bucketHours, 6);
      expect(s.endDate, isNull);
      expect(s.values, [101.2, 102.0, null, 103.5]);
      expect(s.nonNullValues, [101.2, 102.0, 103.5]);
      expect(s.min, 101.2);
      expect(s.max, 103.5);
      expect(s.latest, 103.5);
      expect(s.sum, closeTo(306.7, 0.001));
      expect(s.spanLabel, '1d');
      expect(s.labelForIndex(0), '-18h');
      expect(s.labelForIndex(3), 'Now');
    });

    test('parses 1d@YYYY-MM-DD, slices thisMonthOnly, and labels dates', () {
      // 10 days ending 2026-11-03 => Oct 25..Oct 31 (7 days) + Nov 1..Nov 3 (3 days)
      final s = HistorySeries.parse('1d@2026-11-03:1,2,3,4,5,6,7,10,11,12');
      expect(s.isDaily, isTrue);
      expect(s.endDate, DateTime(2026, 11, 3));
      expect(s.spanLabel, '10d');
      expect(s.labelForIndex(0), 'Oct 25');
      expect(s.labelForIndex(9), 'Nov 3');

      final mtd = s.thisMonthOnly();
      expect(mtd.values, [10.0, 11.0, 12.0]);
      expect(mtd.sum, 33.0);
      expect(mtd.labelForIndex(0), 'Nov 1');
      expect(mtd.labelForIndex(2), 'Nov 3');
    });

    test('parses 1mo@YYYY-MM for 24 months, slices lastN(12), and labels months', () {
      final twentyFour = List.generate(24, (i) => '${100 + i}').join(',');
      final s24 = HistorySeries.parse('1mo@2026-11:$twentyFour');
      expect(s24.isMonthly, isTrue);
      expect(s24.values.length, 24);
      expect(s24.spanLabel, '2yr');
      expect(s24.endMonthKey, '2026-11');
      expect(s24.labelForIndex(0), "Dec '24");
      expect(s24.labelForIndex(23), "Nov '26");

      final s12 = s24.lastN(12);
      expect(s12.values.length, 12);
      expect(s12.spanLabel, '1yr');
      expect(s12.labelForIndex(0), 'Dec');
      expect(s12.labelForIndex(11), 'Nov');
    });

    test('returns empty for blank, NA, or all-null payloads', () {
      expect(HistorySeries.parse(null).isEmpty, isTrue);
      expect(HistorySeries.parse('').isEmpty, isTrue);
      expect(HistorySeries.parse('NA').isEmpty, isTrue);
      expect(HistorySeries.parse('6h:,,').isEmpty, isTrue);
    });
  });

  group('Microchart widgets', () {
    testWidgets('renders single-series and switches tabs in TabbedMicrochartCard without overflow', (tester) async {
      final single = HistorySeries.parse('6h:102.4');
      final full = HistorySeries.parse('6h:${List.generate(56, (i) => (98 + (i % 6) * 0.5).toStringAsFixed(1)).join(',')}');
      final daily = HistorySeries.parse('1d@2026-11-27:${List.generate(31, (i) => (4.0 + (i % 4)).toStringAsFixed(2)).join(',')}');
      final monthly = HistorySeries.parse('1mo@2026-11:${List.generate(24, (i) => (110 + i * 2).toStringAsFixed(1)).join(',')}');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                MicrochartCard(
                  title: 'Water temperature',
                  icon: Icons.thermostat,
                  accent: Colors.orange,
                  series: single,
                  unit: '°F',
                  decimals: 1,
                ),
                MicrochartCard(
                  title: 'Total power draw',
                  icon: Icons.bolt,
                  accent: Colors.amber,
                  series: full,
                  unit: 'W',
                ),
                TabbedMicrochartCard(
                  title: 'Energy consumption',
                  icon: Icons.bar_chart,
                  accent: Colors.cyan,
                  unit: 'kWh',
                  decimals: 1,
                  style: MicrochartStyle.bars,
                  showTotal: true,
                  tabs: [
                    MicrochartTab(label: 'Month', series: daily.thisMonthOnly(), spanOverride: 'MTD'),
                    MicrochartTab(label: '31d', series: daily),
                    MicrochartTab(label: '1yr', series: monthly.lastN(12)),
                    MicrochartTab(label: '2yr', series: monthly),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Water temperature'), findsOneWidget);
      expect(find.text('102.4 °F'), findsWidgets);
      expect(find.text('Total power draw'), findsOneWidget);
      expect(find.text('Energy consumption'), findsOneWidget);
      expect(find.text('MTD'), findsOneWidget);

      await tester.tap(find.text('2yr'));
      await tester.pump();
      expect(find.text('2yr'), findsNWidgets(2)); // pill + span badge
    });
  });
}
