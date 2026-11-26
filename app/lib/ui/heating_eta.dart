import 'dart:math';

/// Snapshot of a spa heat-up ETA calculation in the active display unit (°F or °C).
class HeatingEtaEstimate {
  final bool reached;
  final DateTime? readyAt;
  final bool calibrated;
  final double ratePerHour;
  final double progress;

  const HeatingEtaEstimate({
    required this.reached,
    required this.readyAt,
    required this.calibrated,
    required this.ratePerHour,
    required this.progress,
  });
}

/// Estimates the time-of-day when the hot tub water will reach a target temperature by
/// observing successive water temperature rises and deriving the real-time rate of rise.
class HeatingEtaTracker {
  static const double defaultRatePerHourF = 5.0;
  static const double minRatePerHourF = 1.0;
  static const double maxRatePerHourF = 15.0;

  static const double defaultRatePerHourC = 5.0 * 5 / 9;
  static const double minRatePerHourC = 1.0 * 5 / 9;
  static const double maxRatePerHourC = 15.0 * 5 / 9;

  double? _sessionTarget;
  double? _startTemp;
  final List<({DateTime time, double temp})> _samples = [];

  void reset() {
    _sessionTarget = null;
    _startTemp = null;
    _samples.clear();
  }

  /// Starts a fresh session anchored at [currentTemp] at [now] for [targetTemp].
  void start({required double currentTemp, required double targetTemp, required DateTime now}) {
    _sessionTarget = targetTemp;
    _startTemp = currentTemp.isNaN ? null : currentTemp;
    _samples.clear();
    if (!currentTemp.isNaN) {
      _samples.add((time: now, temp: currentTemp));
    }
  }

  /// Feeds the latest observed [currentTemp] while the heat-up preset is [active].
  void update({
    required double currentTemp,
    required double targetTemp,
    required bool active,
    required bool isFahrenheit,
    required DateTime now,
  }) {
    if (!active || currentTemp.isNaN || targetTemp.isNaN) {
      reset();
      return;
    }
    if (_samples.isEmpty || _sessionTarget == null || (_sessionTarget! - targetTemp).abs() > 0.25) {
      start(currentTemp: currentTemp, targetTemp: targetTemp, now: now);
      return;
    }

    final riseThreshold = isFahrenheit ? 0.5 : 0.25;
    final last = _samples.last;
    if (currentTemp < last.temp - riseThreshold) {
      // Water cooled (e.g., cover removed); re-anchor slope from the cooler reading while keeping
      // the lowest observed start temperature for progress indication.
      _samples
        ..clear()
        ..add((time: now, temp: currentTemp));
      _startTemp = _startTemp == null ? currentTemp : min(_startTemp!, currentTemp);
    } else if (currentTemp >= last.temp + riseThreshold) {
      _samples.add((time: now, temp: currentTemp));
    }
  }

  /// Computes the time-of-day Ready ETA and progress for [currentTemp] -> [targetTemp].
  HeatingEtaEstimate estimate({
    required double currentTemp,
    required double targetTemp,
    required bool isFahrenheit,
    required DateTime now,
  }) {
    final defaultRate = isFahrenheit ? defaultRatePerHourF : defaultRatePerHourC;
    final minRate = isFahrenheit ? minRatePerHourF : minRatePerHourC;
    final maxRate = isFahrenheit ? maxRatePerHourF : maxRatePerHourC;

    if (currentTemp.isNaN || targetTemp.isNaN) {
      return HeatingEtaEstimate(
        reached: false,
        readyAt: null,
        calibrated: false,
        ratePerHour: defaultRate,
        progress: 0.08,
      );
    }

    if (currentTemp >= targetTemp - 0.05) {
      final rate = _rateInfo(defaultRate: defaultRate, minRate: minRate, maxRate: maxRate);
      return HeatingEtaEstimate(
        reached: true,
        readyAt: null,
        calibrated: rate.calibrated,
        ratePerHour: rate.ratePerHour,
        progress: 1.0,
      );
    }

    final rate = _rateInfo(defaultRate: defaultRate, minRate: minRate, maxRate: maxRate);
    final remainingHours = (targetTemp - currentTemp) / rate.ratePerHour;
    final remainingMs = (remainingHours * 3600000).round();
    final start = _startTemp ?? currentTemp;
    final span = max(isFahrenheit ? 1.0 : 0.5, targetTemp - start);
    final progress = ((currentTemp - start) / span).clamp(0.08, 0.96);

    return HeatingEtaEstimate(
      reached: false,
      readyAt: now.add(Duration(milliseconds: remainingMs)),
      calibrated: rate.calibrated,
      ratePerHour: rate.ratePerHour,
      progress: progress,
    );
  }

  ({double ratePerHour, bool calibrated}) _rateInfo({
    required double defaultRate,
    required double minRate,
    required double maxRate,
  }) {
    if (_samples.length < 2) {
      return (ratePerHour: defaultRate, calibrated: false);
    }
    if (_samples.length == 2) {
      final dtHours = max(1 / 60, _samples[1].time.difference(_samples[0].time).inMilliseconds / 3600000);
      final obs = ((_samples[1].temp - _samples[0].temp) / dtHours).clamp(minRate, maxRate);
      // Smooth the first step crossing with the prior baseline rate because the starting
      // temperature may have been partway through a degree.
      return (ratePerHour: 0.5 * obs + 0.5 * defaultRate, calibrated: true);
    }
    // Use the interval starting at the first observed step crossing (s[1]) through the latest
    // crossing so sub-degree startup offset does not skew the measured rate.
    final firstCross = _samples[1];
    final latest = _samples.last;
    final dtHours = max(1 / 60, latest.time.difference(firstCross.time).inMilliseconds / 3600000);
    final measured = ((latest.temp - firstCross.temp) / dtHours).clamp(minRate, maxRate);
    return (ratePerHour: measured, calibrated: true);
  }
}
