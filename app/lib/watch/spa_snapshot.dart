// The small slice of a spa a watch shows: water and target temperature, heater state, preset
// temperatures, the jets and lights toggles, and salt status. Built from a live EspHomeClient
// and serialised to a plain map, so the Wear OS app can render it directly and the iPhone can
// relay it to the Apple Watch over WatchConnectivity.
import '../api/esphome_client.dart';
import '../api/messages.dart';
import '../device_store.dart';
import '../ui/history_series.dart';
import '../ui/spa_screen.dart' as ui show saltZone;

class WatchToggle {
  final int key;
  final String name;
  final String kind; // 'fan' (jets) or 'light'
  final bool on;
  const WatchToggle({required this.key, required this.name, required this.kind, required this.on});

  Map<String, Object> toMap() => {'key': key, 'name': name, 'kind': kind, 'on': on};
  factory WatchToggle.fromMap(Map<Object?, Object?> m) => WatchToggle(
        key: (m['key'] as num).toInt(),
        name: m['name'] as String,
        kind: m['kind'] as String,
        on: m['on'] as bool,
      );
}

class SpaSnapshot {
  final String name;
  final bool online;
  final String unit; // '°F' or '°C'
  final int? climateKey;
  final double? current, target; // display units
  final double min, max, step; // target range in display units
  final double heatUpTemp, vacationTemp; // preset targets in display units
  final String heater; // 'heating' | 'idle' | 'cooling' | 'off'
  final List<WatchToggle> toggles;
  final double? salt; // 0..120 display scale
  final String? saltZone; // 'Too low' .. 'Too high'
  final int? saltPower; // 1..10 production level
  final bool saltBoost;
  final int? readyEtaSeconds; // ESP32-tracked remaining heat-up seconds
  final bool readyEtaCalibrated;
  final double? heatingRate; // °F/h (or °C/h) from ESP32
  final List<double> tempHistory; // 14-day water temp samples
  final List<double> saltHistory; // 14-day salt samples
  final List<double> dailyEnergyHistory; // up to 31 daily energy totals (kWh)
  final List<double> monthlyEnergyHistory; // up to 24 monthly energy totals (kWh)
  final String? monthlyEnergyEndMonth; // YYYY-MM anchor for monthlyEnergyHistory

  const SpaSnapshot({
    required this.name,
    required this.online,
    this.unit = '°F',
    this.climateKey,
    this.current,
    this.target,
    this.min = 79,
    this.max = 104,
    this.step = 1,
    this.heatUpTemp = 102,
    this.vacationTemp = 85,
    this.heater = 'off',
    this.toggles = const [],
    this.salt,
    this.saltZone,
    this.saltPower,
    this.saltBoost = false,
    this.readyEtaSeconds,
    this.readyEtaCalibrated = false,
    this.heatingRate,
    this.tempHistory = const [],
    this.saltHistory = const [],
    this.dailyEnergyHistory = const [],
    this.monthlyEnergyHistory = const [],
    this.monthlyEnergyEndMonth,
  });

  static double? _num(double v) => v.isNaN ? null : v;

  /// Reads the watch view out of a client. ESPHome reports climate temperatures in °C; they are
  /// shown in °F when the spa's own temperature sensors are configured in °F.
  factory SpaSnapshot.fromClient(
    EspHomeClient c, {
    required String name,
    double heatUpTempC = SavedDevice.defaultHeatUpTempC,
    double vacationTempC = SavedDevice.defaultVacationTempC,
  }) {
    final visible = c.entities.values.where((e) => !e.disabledByDefault).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final fahrenheit = visible.any((e) => e.kind == EntityKind.sensor && e.unit == '°F');
    double disp(double celsius) => fahrenheit ? celsius * 9 / 5 + 32 : celsius;

    final climate = visible.where((e) => e.kind == EntityKind.climate).firstOrNull;
    final cs = climate == null ? null : c.states[climate.key];
    final heater = switch (cs?.climateAction) {
      ClimateAction.heating => 'heating',
      ClimateAction.cooling => 'cooling',
      ClimateAction.idle => 'idle',
      _ => 'off',
    };

    bool isLight(EntityInfo e) => e.objectId.contains('light') || e.icon.contains('lightbulb');
    final main = visible.where((e) => e.category == EntityCategory.none && !e.objectId.contains('salt'));
    final toggles = [
      for (final e in main.where((e) => e.kind == EntityKind.fan))
        WatchToggle(key: e.key, name: e.name, kind: 'fan', on: c.states[e.key]?.boolValue ?? false),
      for (final e in main.where((e) => e.kind == EntityKind.switch_ && isLight(e)))
        WatchToggle(key: e.key, name: e.name, kind: 'light', on: c.states[e.key]?.boolValue ?? false),
    ];

    final saltEntity = visible
        .where((e) => e.kind == EntityKind.sensor && (e.objectId == 'salt_level' || e.objectId == 'salt_content'))
        .firstOrNull;
    final salt = saltEntity == null ? null : _num(c.states[saltEntity.key]?.number ?? double.nan);
    final saltPowerEntity = visible
            .where((e) =>
                e.kind == EntityKind.number &&
                e.objectId.contains('salt') &&
                (e.objectId.contains('power') || e.objectId.contains('output')))
            .firstOrNull ??
        visible.where((e) => e.kind == EntityKind.number && e.objectId.contains('salt')).firstOrNull;
    final saltPowerNum = saltPowerEntity == null ? null : _num(c.states[saltPowerEntity.key]?.number ?? double.nan);
    final saltBoostEntity = visible
        .where((e) => e.kind == EntityKind.switch_ && e.objectId.contains('salt') && e.objectId.contains('boost'))
        .firstOrNull;
    final saltBoost = saltBoostEntity != null && (c.states[saltBoostEntity.key]?.boolValue ?? false);

    double? presetFromEntity(String id) {
      final e = visible.where((x) => x.kind == EntityKind.number && x.objectId == id).firstOrNull;
      if (e == null) return null;
      final v = _num(c.states[e.key]?.number ?? double.nan);
      if (v == null) return null;
      final entityF = e.unit.isNotEmpty ? e.unit == '°F' : fahrenheit;
      if (entityF == fahrenheit) return v;
      return fahrenheit ? (v * 9 / 5 + 32) : ((v - 32) * 5 / 9);
    }

    final remEntity = visible.where((e) => e.kind == EntityKind.sensor && e.objectId == 'ready_eta_seconds').firstOrNull;
    final readyEtaSeconds = remEntity == null ? null : _num(c.states[remEntity.key]?.number ?? double.nan)?.round();
    final calEntity = visible
        .where((e) => e.kind == EntityKind.binarySensor && e.objectId == 'heating_rate_calibrated')
        .firstOrNull;
    final readyEtaCalibrated = calEntity != null && (c.states[calEntity.key]?.boolValue ?? false);
    final rateEntity = visible.where((e) => e.kind == EntityKind.sensor && e.objectId == 'heating_rate').firstOrNull;
    final heatingRate = rateEntity == null ? null : _num(c.states[rateEntity.key]?.number ?? double.nan);

    HistorySeries seriesFor(String id) {
      final e = c.entities.values
          .where((x) => !x.disabledByDefault && x.kind == EntityKind.textSensor && x.objectId == id)
          .firstOrNull;
      if (e == null) return HistorySeries.empty;
      return HistorySeries.parse(c.states[e.key]?.text);
    }

    final waterHist = seriesFor('history_water_temp');
    final saltHist = seriesFor('history_salt');
    final energyDailyHist = seriesFor('history_energy');
    final energyMonthlyHist = seriesFor('history_energy_monthly');

    final lo = climate == null ? (fahrenheit ? 79.0 : 26.0) : disp(climate.minValue);
    final hi = climate == null || climate.maxValue <= climate.minValue ? disp(40) : disp(climate.maxValue);
    final step = fahrenheit ? 1.0 : ((climate == null || climate.step <= 0) ? 0.5 : climate.step);
    final safeHi = hi > lo ? hi : lo + step;
    double snapDisp(double v) => ((v / step).round() * step).clamp(lo, safeHi).toDouble();

    return SpaSnapshot(
      name: name,
      online: c.status == ConnectionStatus.connected,
      unit: fahrenheit ? '°F' : '°C',
      climateKey: climate?.key,
      current: cs == null ? null : _num(disp(cs.currentTemperature)),
      target: cs == null ? null : _num(disp(cs.targetTemperature)),
      min: lo,
      max: safeHi,
      step: step,
      heatUpTemp: snapDisp(presetFromEntity('heat_up_temperature') ?? disp(heatUpTempC)),
      vacationTemp: snapDisp(presetFromEntity('vacation_temperature') ?? disp(vacationTempC)),
      heater: heater,
      toggles: toggles,
      salt: salt,
      saltZone: salt == null ? null : ui.saltZone(salt)?.$1,
      saltPower: saltPowerNum?.round(),
      saltBoost: saltBoost,
      readyEtaSeconds: readyEtaSeconds,
      readyEtaCalibrated: readyEtaCalibrated,
      heatingRate: heatingRate,
      tempHistory: waterHist.nonNullValues,
      saltHistory: saltHist.nonNullValues,
      dailyEnergyHistory: energyDailyHist.nonNullValues,
      monthlyEnergyHistory: energyMonthlyHist.nonNullValues,
      monthlyEnergyEndMonth: energyMonthlyHist.endMonthKey,
    );
  }

  /// Converts a display-unit target back to the °C the device expects.
  double toCelsius(double display) => unit == '°F' ? (display - 32) * 5 / 9 : display;

  /// [target] moved by [steps] steps, snapped and clamped to the spa's range.
  double nudged(int steps) {
    final base = target ?? current ?? min;
    return (((base + steps * step) / step).round() * step).clamp(min, max).toDouble();
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'online': online,
        'unit': unit,
        'climateKey': climateKey,
        'current': current,
        'target': target,
        'min': min,
        'max': max,
        'step': step,
        'heatUpTemp': heatUpTemp,
        'vacationTemp': vacationTemp,
        'heater': heater,
        'toggles': [for (final t in toggles) t.toMap()],
        'salt': salt,
        'saltZone': saltZone,
        'saltPower': saltPower,
        'saltBoost': saltBoost,
        'readyEtaSeconds': readyEtaSeconds,
        'readyEtaCalibrated': readyEtaCalibrated,
        'heatingRate': heatingRate,
        'tempHistory': tempHistory,
        'saltHistory': saltHistory,
        'dailyEnergyHistory': dailyEnergyHistory,
        'monthlyEnergyHistory': monthlyEnergyHistory,
        'monthlyEnergyEndMonth': monthlyEnergyEndMonth,
      };

  factory SpaSnapshot.fromMap(Map<Object?, Object?> m) {
    final unit = m['unit'] as String;
    List<double> numList(String k) =>
        [for (final v in (m[k] as List<Object?>? ?? const [])) (v as num).toDouble()];
    return SpaSnapshot(
      name: m['name'] as String,
      online: m['online'] as bool,
      unit: unit,
      climateKey: (m['climateKey'] as num?)?.toInt(),
      current: (m['current'] as num?)?.toDouble(),
      target: (m['target'] as num?)?.toDouble(),
      min: (m['min'] as num).toDouble(),
      max: (m['max'] as num).toDouble(),
      step: (m['step'] as num).toDouble(),
      heatUpTemp: (m['heatUpTemp'] as num?)?.toDouble() ?? (unit == '°F' ? 102 : 39),
      vacationTemp: (m['vacationTemp'] as num?)?.toDouble() ?? (unit == '°F' ? 85 : 29.5),
      heater: m['heater'] as String,
      toggles: [for (final t in m['toggles'] as List<Object?>) WatchToggle.fromMap(t as Map<Object?, Object?>)],
      salt: (m['salt'] as num?)?.toDouble(),
      saltZone: m['saltZone'] as String?,
      saltPower: (m['saltPower'] as num?)?.toInt(),
      saltBoost: m['saltBoost'] as bool? ?? false,
      readyEtaSeconds: (m['readyEtaSeconds'] as num?)?.toInt(),
      readyEtaCalibrated: m['readyEtaCalibrated'] as bool? ?? false,
      heatingRate: (m['heatingRate'] as num?)?.toDouble(),
      tempHistory: numList('tempHistory'),
      saltHistory: numList('saltHistory'),
      dailyEnergyHistory: numList('dailyEnergyHistory'),
      monthlyEnergyHistory: numList('monthlyEnergyHistory'),
      monthlyEnergyEndMonth: m['monthlyEnergyEndMonth'] as String?,
    );
  }
}

/// Applies a watch command to [client]. Commands are maps so the same code serves the Wear OS
/// UI and requests relayed from the Apple Watch:
///   {'op': 'setTarget', 'value': <display units>}  (needs the current snapshot for units)
///   {'op': 'toggle', 'key': <entity key>, 'kind': 'fan'|'light', 'on': <bool>}
Future<void> applyWatchCommand(EspHomeClient client, SpaSnapshot snap, Map<Object?, Object?> cmd) async {
  switch (cmd['op']) {
    case 'setTarget':
      final key = snap.climateKey;
      if (key == null) throw ApiException('This spa has no thermostat');
      final v = (cmd['value'] as num).toDouble().clamp(snap.min, snap.max).toDouble();
      await client.setClimate(key, target: snap.toCelsius(v));
    case 'toggle':
      final key = (cmd['key'] as num).toInt();
      final on = cmd['on'] as bool;
      if (cmd['kind'] == 'fan') {
        await client.setFan(key, on: on);
      } else {
        await client.setSwitch(key, on);
      }
    default:
      throw ApiException('Unknown watch command ${cmd['op']}');
  }
}
