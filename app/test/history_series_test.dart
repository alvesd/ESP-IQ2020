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
      expect(s.values, [101.2, 102.0, null, 103.5]);
      expect(s.nonNullValues, [101.2, 102.0, 103.5]);
      expect(s.min, 101.2);
      expect(s.max, 103.5);
      expect(s.latest, 103.5);
      expect(s.spanLabel, '1d');
    });

    test('parses 12h and 1d series and 56-point 14-day span', () {
      final fiftySix = List.generate(56, (i) => '${100 + (i % 4)}').join(',');
      final s6 = HistorySeries.parse('6h:$fiftySix');
      expect(s6.values.length, 56);
      expect(s6.spanLabel, '14d');

      final s12 = HistorySeries.parse('12h:100,101,102,103');
      expect(s12.bucketHours, 12);
      expect(s12.spanLabel, '2d');

      final sd = HistorySeries.parse('1d:4.12,5.30,3.80');
      expect(sd.bucketHours, 24);
      expect(sd.spanLabel, '3d');
      expect(sd.latest, 3.80);
    });

    test('returns empty for blank, NA, or all-null payloads', () {
      expect(HistorySeries.parse(null).isEmpty, isTrue);
      expect(HistorySeries.parse('').isEmpty, isTrue);
      expect(HistorySeries.parse('NA').isEmpty, isTrue);
      expect(HistorySeries.parse('6h:,,').isEmpty, isTrue);
    });
  });

  group('MicrochartCard widget', () {
    testWidgets('renders single-point line, 56-point line, and 14-day bars without overflow', (tester) async {
      final single = HistorySeries.parse('6h:102.4');
      final full = HistorySeries.parse('6h:${List.generate(56, (i) => (98 + (i % 6) * 0.5).toStringAsFixed(1)).join(',')}');
      final bars = HistorySeries.parse('1d:${List.generate(14, (i) => (2.5 + (i % 5) * 0.4).toStringAsFixed(2)).join(',')}');

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
                MicrochartCard(
                  title: 'Daily energy',
                  icon: Icons.bar_chart,
                  accent: Colors.cyan,
                  series: bars,
                  unit: 'kWh',
                  decimals: 2,
                  style: MicrochartStyle.bars,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Water temperature'), findsOneWidget);
      expect(find.text('102.4 °F'), findsWidgets);
      expect(find.text('Total power draw'), findsOneWidget);
      expect(find.text('14d'), findsNWidgets(2));
      expect(find.text('Daily energy'), findsOneWidget);
    });
  });
}
