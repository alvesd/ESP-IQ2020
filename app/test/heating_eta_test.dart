import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/ui/heating_eta.dart';

void main() {
  group('HeatingEtaTracker', () {
    test('uses baseline 5 °F/hr rate before first observed rise', () {
      final tracker = HeatingEtaTracker();
      final t0 = DateTime(2026, 11, 26, 8, 30);
      tracker.update(currentTemp: 94, targetTemp: 102, active: true, isFahrenheit: true, now: t0);

      final est = tracker.estimate(currentTemp: 94, targetTemp: 102, isFahrenheit: true, now: t0);
      expect(est.reached, isFalse);
      expect(est.calibrated, isFalse);
      expect(est.ratePerHour, closeTo(5.0, 0.01));
      // 8°F at 5 °F/hr = 1h 36m = 96 min -> 10:06 AM
      expect(est.readyAt, DateTime(2026, 11, 26, 10, 6));
      expect(est.progress, closeTo(0.08, 0.001));
    });

    test('blends first +1°F crossing with prior baseline, then measures slope across crossings', () {
      final tracker = HeatingEtaTracker();
      final t0 = DateTime(2026, 11, 26, 8, 0);
      tracker.update(currentTemp: 94, targetTemp: 102, active: true, isFahrenheit: true, now: t0);

      // +1°F in 12 min = 5.0 °F/hr, wait let's test fast 6 min = 10.0 °F/hr -> blended (10 + 5) / 2 = 7.5 °F/hr
      final t1 = t0.add(const Duration(minutes: 6));
      tracker.update(currentTemp: 95, targetTemp: 102, active: true, isFahrenheit: true, now: t1);
      final est1 = tracker.estimate(currentTemp: 95, targetTemp: 102, isFahrenheit: true, now: t1);
      expect(est1.calibrated, isTrue);
      expect(est1.ratePerHour, closeTo(7.5, 0.01));
      // 7°F left at 7.5 °F/hr = 56 min -> 9:02 AM
      expect(est1.readyAt, DateTime(2026, 11, 26, 9, 2));

      // Next crossing: +2°F more over 24 min (between t1=8:06 and t2=8:30 -> 5.0 °F/hr measured)
      final t2 = t1.add(const Duration(minutes: 24));
      tracker.update(currentTemp: 97, targetTemp: 102, active: true, isFahrenheit: true, now: t2);
      final est2 = tracker.estimate(currentTemp: 97, targetTemp: 102, isFahrenheit: true, now: t2);
      expect(est2.calibrated, isTrue);
      expect(est2.ratePerHour, closeTo(5.0, 0.01));
      // 5°F left at 5.0 °F/hr = 60 min -> 9:30 AM
      expect(est2.readyAt, DateTime(2026, 11, 26, 9, 30));
    });

    test('marks reached once water meets target temperature', () {
      final tracker = HeatingEtaTracker();
      final now = DateTime(2026, 11, 26, 10, 0);
      tracker.update(currentTemp: 102, targetTemp: 102, active: true, isFahrenheit: true, now: now);
      final est = tracker.estimate(currentTemp: 102, targetTemp: 102, isFahrenheit: true, now: now);
      expect(est.reached, isTrue);
      expect(est.readyAt, isNull);
      expect(est.progress, 1.0);
    });

    test('supports Celsius mode and cooling re-anchor', () {
      final tracker = HeatingEtaTracker();
      final t0 = DateTime(2026, 11, 26, 8, 0);
      tracker.update(currentTemp: 35.0, targetTemp: 39.0, active: true, isFahrenheit: false, now: t0);
      final t1 = t0.add(const Duration(minutes: 15));
      tracker.update(currentTemp: 34.0, targetTemp: 39.0, active: true, isFahrenheit: false, now: t1);
      final est = tracker.estimate(currentTemp: 34.0, targetTemp: 39.0, isFahrenheit: false, now: t1);
      // Re-anchored at 34.0 -> uncalibrated baseline Celsius rate (5 * 5 / 9 = 2.778 °C/hr)
      expect(est.calibrated, isFalse);
      expect(est.ratePerHour, closeTo(5.0 * 5 / 9, 0.01));
    });
  });

  group('SavedDevice preset temps persistence', () {
    test('defaults to 102°F heat up and 85°F vacation when omitted from legacy JSON', () {
      final d = SavedDevice.fromJson({'id': 'spa', 'name': 'Spa', 'host': 'hotspring.local'});
      expect(d.heatUpTempC * 9 / 5 + 32, closeTo(102, 0.01));
      expect(d.vacationTempC * 9 / 5 + 32, closeTo(85, 0.01));
    });

    test('round-trips custom heat up and vacation temperatures through JSON and copyWith', () {
      const heat104C = (104 - 32) * 5 / 9;
      const vac80C = (80 - 32) * 5 / 9;
      const d = SavedDevice(id: 'spa', name: 'Spa', host: 'hotspring.local');
      final updated = d.copyWith(heatUpTempC: heat104C, vacationTempC: vac80C);
      final decoded = SavedDevice.fromJson(updated.toJson());
      expect(decoded.heatUpTempC, closeTo(heat104C, 0.0001));
      expect(decoded.vacationTempC, closeTo(vac80C, 0.0001));
    });
  });
}
