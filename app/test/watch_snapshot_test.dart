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

  test('missing readings become null, not NaN', () {
    final c = EspHomeClient(host: 'test');
    final s = SpaSnapshot.fromClient(c, name: 'x');
    expect(s.online, isFalse);
    expect(s.current, isNull);
    expect(s.climateKey, isNull);
    expect(s.toggles, isEmpty);
  });
}
