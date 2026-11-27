import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/esphome_client.dart';
import 'package:iq2020_mobile/api/messages.dart';
import 'package:iq2020_mobile/watch/spa_snapshot.dart';

/// A client shaped like the real hotspring device, with no socket.
EspHomeClient fakeSpa() {
  final c = EspHomeClient(host: 'test');
  void add(EntityInfo e, EntityState s) {
    c.entities[e.key] = e;
    c.states[e.key] = s;
  }

  // 102°F water, 104°F target, heating. ESPHome sends climate values in °C.
  add(EntityInfo(kind: EntityKind.climate, key: 1, objectId: 'temperature', name: 'Temperature', minValue: 26.111, maxValue: 40, step: 0.5),
      const EntityState(key: 1, currentTemperature: 38.889, targetTemperature: 40, climateAction: ClimateAction.heating));
  add(EntityInfo(kind: EntityKind.sensor, key: 2, objectId: 'current_temperature', name: 'Current Temperature', unit: '°F'),
      const EntityState(key: 2, number: 102));
  add(EntityInfo(kind: EntityKind.fan, key: 3, objectId: 'jets_1', name: 'Jets 1'), const EntityState(key: 3, boolValue: true));
  add(EntityInfo(kind: EntityKind.switch_, key: 4, objectId: 'lights', name: 'Lights', icon: 'mdi:lightbulb'),
      const EntityState(key: 4));
  add(EntityInfo(kind: EntityKind.switch_, key: 5, objectId: 'spa_lock', name: 'Spa Lock'), const EntityState(key: 5));
  add(EntityInfo(kind: EntityKind.switch_, key: 6, objectId: 'salt_boost', name: 'Salt Boost'), const EntityState(key: 6, boolValue: true));
  add(EntityInfo(kind: EntityKind.sensor, key: 7, objectId: 'salt_level', name: 'Salt Level'), const EntityState(key: 7, number: 24));
  add(EntityInfo(kind: EntityKind.number, key: 8, objectId: 'salt_system_power', name: 'Salt System Power', minValue: 1, maxValue: 10, step: 1),
      const EntityState(key: 8, number: 5));
  c.status = ConnectionStatus.connected;
  return c;
}

void main() {
  test('snapshot shows °F temperatures, heater, jets/lights, presets and salt details', () {
    final s = SpaSnapshot.fromClient(fakeSpa(), name: 'hotspring');
    expect(s.online, isTrue);
    expect(s.unit, '°F');
    expect(s.current!.round(), 102);
    expect(s.target!.round(), 104);
    expect(s.min.round(), 79);
    expect(s.max.round(), 104);
    expect(s.step, 1);
    expect(s.heatUpTemp.round(), 102);
    expect(s.vacationTemp.round(), 85);
    expect(s.heater, 'heating');
    expect([for (final t in s.toggles) '${t.kind}:${t.name}:${t.on}'], ['fan:Jets 1:true', 'light:Lights:false']);
    expect(s.salt, 24);
    expect(s.saltZone, 'Low');
    expect(s.saltPower, 5);
    expect(s.saltBoost, isTrue);
  });

  test('nudged snaps and clamps to the range', () {
    final s = SpaSnapshot.fromClient(fakeSpa(), name: 'hotspring');
    expect(s.nudged(1), closeTo(104, 0.01)); // already at max
    expect(s.nudged(-3), closeTo(101, 0.01));
    expect(s.toCelsius(104), closeTo(40, 0.01));
  });

  test('map round trip survives the relay', () {
    final s = SpaSnapshot.fromClient(fakeSpa(), name: 'hotspring');
    final back = SpaSnapshot.fromMap(s.toMap());
    expect(back.toMap(), s.toMap());
  });

  test('snapshot reads global presets and ESP32 Ready ETA telemetry when exposed', () {
    final c = fakeSpa();
    c.entities[9] = EntityInfo(kind: EntityKind.number, key: 9, objectId: 'heat_up_temperature', name: 'Heat Up Temperature', unit: '°F');
    c.states[9] = const EntityState(key: 9, number: 103);
    c.entities[10] = EntityInfo(kind: EntityKind.number, key: 10, objectId: 'vacation_temperature', name: 'Vacation Temperature', unit: '°F');
    c.states[10] = const EntityState(key: 10, number: 82);
    c.entities[11] = EntityInfo(kind: EntityKind.sensor, key: 11, objectId: 'ready_eta_seconds', name: 'Ready ETA Seconds', unit: 's');
    c.states[11] = const EntityState(key: 11, number: 1800);
    c.entities[12] = EntityInfo(kind: EntityKind.binarySensor, key: 12, objectId: 'heating_rate_calibrated', name: 'Heating Rate Calibrated');
    c.states[12] = const EntityState(key: 12, boolValue: true);
    c.entities[13] = EntityInfo(kind: EntityKind.sensor, key: 13, objectId: 'heating_rate', name: 'Heating Rate', unit: '°F/h');
    c.states[13] = const EntityState(key: 13, number: 6.5);
    c.entities[14] = EntityInfo(kind: EntityKind.textSensor, key: 14, objectId: 'history_water_temp', name: 'History Water Temp');
    c.states[14] = const EntityState(key: 14, text: '6h:101.0,,102.5');
    c.entities[15] = EntityInfo(kind: EntityKind.textSensor, key: 15, objectId: 'history_salt', name: 'History Salt');
    c.states[15] = const EntityState(key: 15, text: '6h:48,50,52');
    c.entities[16] = EntityInfo(kind: EntityKind.textSensor, key: 16, objectId: 'history_energy', name: 'History Energy');
    c.states[16] = const EntityState(key: 16, text: '1d@2026-11-27:3.20,4.50');
    c.entities[17] = EntityInfo(kind: EntityKind.textSensor, key: 17, objectId: 'history_energy_monthly', name: 'History Energy Monthly');
    c.states[17] = const EntityState(key: 17, text: '1mo@2026-11:110.2,125.4');

    final s = SpaSnapshot.fromClient(c, name: 'hotspring');
    expect(s.heatUpTemp.round(), 103);
    expect(s.vacationTemp.round(), 82);
    expect(s.readyEtaSeconds, 1800);
    expect(s.readyEtaCalibrated, isTrue);
    expect(s.heatingRate, closeTo(6.5, 0.01));
    expect(s.tempHistory, [101.0, 102.5]);
    expect(s.saltHistory, [48.0, 50.0, 52.0]);
    expect(s.dailyEnergyHistory, [3.2, 4.5]);
    expect(s.monthlyEnergyHistory, [110.2, 125.4]);
    expect(s.monthlyEnergyEndMonth, '2026-11');

    final roundTrip = SpaSnapshot.fromMap(s.toMap());
    expect(roundTrip.toMap(), s.toMap());
  });

  test('missing readings become null, not NaN', () {
    final c = EspHomeClient(host: 'test');
    final s = SpaSnapshot.fromClient(c, name: 'x');
    expect(s.online, isFalse);
    expect(s.current, isNull);
    expect(s.climateKey, isNull);
    expect(s.toggles, isEmpty);
  });
}
