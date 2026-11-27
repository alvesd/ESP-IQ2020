// ESPHome native API message ids, entity models and (de)serialisers.
// Ids and field numbers: esphome/components/api/api.proto (API 1.x).
import 'dart:typed_data';

import 'protobuf.dart';

abstract final class MsgId {
  static const helloRequest = 1;
  static const helloResponse = 2;
  static const authenticationRequest = 3;
  static const authenticationResponse = 4;
  static const disconnectRequest = 5;
  static const disconnectResponse = 6;
  static const pingRequest = 7;
  static const pingResponse = 8;
  static const deviceInfoRequest = 9;
  static const deviceInfoResponse = 10;
  static const listEntitiesRequest = 11;
  static const listBinarySensor = 12;
  static const listFan = 14;
  static const listSensor = 16;
  static const listSwitch = 17;
  static const listTextSensor = 18;
  static const listEntitiesDone = 19;
  static const subscribeStatesRequest = 20;
  static const binarySensorState = 21;
  static const fanState = 23;
  static const sensorState = 25;
  static const switchState = 26;
  static const textSensorState = 27;
  static const fanCommand = 31;
  static const switchCommand = 33;
  static const subscribeHomeassistantServicesRequest = 34;
  static const homeassistantActionRequest = 35;
  static const getTimeRequest = 36;
  static const getTimeResponse = 37;
  static const listEntitiesServicesResponse = 41;
  static const executeServiceRequest = 42;
  static const listClimate = 46;
  static const climateState = 47;
  static const climateCommand = 48;
  static const listNumber = 49;
  static const numberState = 50;
  static const numberCommand = 51;
  static const listSelect = 52;
  static const selectState = 53;
  static const selectCommand = 54;
  static const listButton = 61;
  static const buttonCommand = 62;
  static const listText = 97;
  static const textState = 98;
  static const textCommand = 99;
}

/// API version this client speaks (matches aioesphomeapi's request).
const int apiVersionMajor = 1;
const int apiVersionMinor = 10;

String objectIdFromName(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

enum EntityKind { binarySensor, sensor, textSensor, switch_, fan, climate, number, select, button, text }

enum EntityCategory { none, config, diagnostic }

// ESPHome ClimateMode / ClimateAction / ClimatePreset enum values.
abstract final class ClimateMode {
  static const off = 0;
  static const heatCool = 1;
  static const cool = 2;
  static const heat = 3;
  static const auto = 6;
}

abstract final class ClimateAction {
  static const off = 0;
  static const cooling = 2;
  static const heating = 3;
  static const idle = 4;
}

abstract final class ClimatePreset {
  static const none = 0;
  static const boost = 3;
  static const eco = 5;
}

class DeviceInfo {
  final String name;
  final String friendlyName;
  final String macAddress;
  final String esphomeVersion;
  final String projectName;
  final String projectVersion;
  final String model;

  const DeviceInfo.basic({
    required this.name,
    this.friendlyName = '',
    this.macAddress = '',
    this.esphomeVersion = '',
    this.projectName = '',
    this.projectVersion = '',
    this.model = '',
  });

  DeviceInfo.fromProto(ProtoMessage m)
      : name = m.string(2),
        macAddress = m.string(3),
        esphomeVersion = m.string(4),
        model = m.string(6),
        projectName = m.string(8),
        projectVersion = m.string(9),
        friendlyName = m.string(13);

  String get displayName => friendlyName.isNotEmpty ? friendlyName : name;
}

class EntityInfo {
  final EntityKind kind;
  final int key;
  final String objectId;
  final String name;
  final String icon;
  final String unit;
  final String deviceClass;
  final int accuracyDecimals;
  final EntityCategory category;
  final bool disabledByDefault;

  // Type specific.
  final int fanSpeedCount;
  final List<String> options; // select
  final double minValue, maxValue, step; // number / climate
  final List<int> climateModes;
  final List<int> climatePresets;
  final bool climateSupportsAction;

  EntityInfo({
    required this.kind,
    required this.key,
    required this.objectId,
    required this.name,
    this.icon = '',
    this.unit = '',
    this.deviceClass = '',
    this.accuracyDecimals = 1,
    this.category = EntityCategory.none,
    this.disabledByDefault = false,
    this.fanSpeedCount = 0,
    this.options = const [],
    this.minValue = 0,
    this.maxValue = 0,
    this.step = 1,
    this.climateModes = const [],
    this.climatePresets = const [],
    this.climateSupportsAction = false,
  });

  static EntityCategory _cat(int v) =>
      v >= 0 && v < EntityCategory.values.length ? EntityCategory.values[v] : EntityCategory.none;

  /// Decodes a ListEntities*Response, or returns null for entity types the app ignores.
  static const _listTypes = {
    MsgId.listBinarySensor, MsgId.listSensor, MsgId.listTextSensor, MsgId.listSwitch, MsgId.listFan,
    MsgId.listClimate, MsgId.listNumber, MsgId.listSelect, MsgId.listButton, MsgId.listText,
  };

  static EntityInfo? fromList(int msgType, Uint8List data) {
    if (!_listTypes.contains(msgType)) return null;
    final m = ProtoMessage.decode(data);
    final key = m.fixed32(2);
    final name = m.string(3);
    // Newer ESPHome no longer sends object_id; derive it from the name the same way ESPHome
    // does ("Power On Counter" -> "power_on_counter").
    final sentId = m.string(1);
    final objectId = sentId.isNotEmpty ? sentId : objectIdFromName(name);
    double step(int f) {
      final v = m.float32(f);
      return v == 0 ? 1 : v;
    }

    switch (msgType) {
      case MsgId.listBinarySensor:
        return EntityInfo(kind: EntityKind.binarySensor, key: key, objectId: objectId, name: name,
            deviceClass: m.string(5), disabledByDefault: m.boolean(7), icon: m.string(8),
            category: _cat(m.uint(9)));
      case MsgId.listSensor:
        return EntityInfo(kind: EntityKind.sensor, key: key, objectId: objectId, name: name,
            icon: m.string(5), unit: m.string(6), accuracyDecimals: m.int32(7),
            deviceClass: m.string(9), disabledByDefault: m.boolean(12), category: _cat(m.uint(13)));
      case MsgId.listTextSensor:
        return EntityInfo(kind: EntityKind.textSensor, key: key, objectId: objectId, name: name,
            icon: m.string(5), disabledByDefault: m.boolean(6), category: _cat(m.uint(7)),
            deviceClass: m.string(8));
      case MsgId.listSwitch:
        return EntityInfo(kind: EntityKind.switch_, key: key, objectId: objectId, name: name,
            icon: m.string(5), disabledByDefault: m.boolean(7), category: _cat(m.uint(8)),
            deviceClass: m.string(9));
      case MsgId.listFan:
        return EntityInfo(kind: EntityKind.fan, key: key, objectId: objectId, name: name,
            fanSpeedCount: m.boolean(6) ? m.int32(8) : 0, disabledByDefault: m.boolean(9),
            icon: m.string(10), category: _cat(m.uint(11)));
      case MsgId.listClimate:
        return EntityInfo(kind: EntityKind.climate, key: key, objectId: objectId, name: name,
            climateModes: m.uints(7), minValue: m.float32(8), maxValue: m.float32(9),
            step: step(10), climateSupportsAction: m.boolean(12),
            climatePresets: m.uints(16), disabledByDefault: m.boolean(18), icon: m.string(19),
            category: _cat(m.uint(20)));
      case MsgId.listNumber:
        return EntityInfo(kind: EntityKind.number, key: key, objectId: objectId, name: name,
            icon: m.string(5), minValue: m.float32(6), maxValue: m.float32(7),
            step: step(8), disabledByDefault: m.boolean(9),
            category: _cat(m.uint(10)), unit: m.string(11), deviceClass: m.string(13));
      case MsgId.listSelect:
        return EntityInfo(kind: EntityKind.select, key: key, objectId: objectId, name: name,
            icon: m.string(5), options: m.strings(6), disabledByDefault: m.boolean(7),
            category: _cat(m.uint(8)));
      case MsgId.listButton:
        return EntityInfo(kind: EntityKind.button, key: key, objectId: objectId, name: name,
            icon: m.string(5), disabledByDefault: m.boolean(6), category: _cat(m.uint(7)),
            deviceClass: m.string(8));
      case MsgId.listText:
        return EntityInfo(kind: EntityKind.text, key: key, objectId: objectId, name: name,
            icon: m.string(5), disabledByDefault: m.boolean(6), category: _cat(m.uint(7)),
            minValue: m.uint(8).toDouble(), maxValue: m.uint(9).toDouble());
    }
    return null;
  }
}

/// Latest known state of one entity. Only the fields relevant to its kind are meaningful.
class EntityState {
  final int key;
  final bool missing;
  final bool boolValue; // binary_sensor, switch, fan on/off
  final double number; // sensor, number
  final String text; // text_sensor, select, text
  final int fanSpeedLevel;
  final int climateMode;
  final int climateAction;
  final int climatePreset;
  final double currentTemperature;
  final double targetTemperature;

  const EntityState({
    required this.key,
    this.missing = false,
    this.boolValue = false,
    this.number = double.nan,
    this.text = '',
    this.fanSpeedLevel = 0,
    this.climateMode = 0,
    this.climateAction = 0,
    this.climatePreset = 0,
    this.currentTemperature = double.nan,
    this.targetTemperature = double.nan,
  });

  /// Decodes a *StateResponse message, or returns null if [msgType] is not a state message.
  static const _stateTypes = {
    MsgId.binarySensorState, MsgId.sensorState, MsgId.textSensorState, MsgId.switchState, MsgId.fanState,
    MsgId.climateState, MsgId.numberState, MsgId.selectState, MsgId.textState,
  };

  static EntityState? fromState(int msgType, Uint8List data) {
    if (!_stateTypes.contains(msgType)) return null;
    final m = ProtoMessage.decode(data);
    final key = m.fixed32(1);
    switch (msgType) {
      case MsgId.binarySensorState:
        return EntityState(key: key, boolValue: m.boolean(2), missing: m.boolean(3));
      case MsgId.sensorState:
      case MsgId.numberState:
        return EntityState(key: key, number: m.float32(2), missing: m.boolean(3));
      case MsgId.textSensorState:
      case MsgId.selectState:
      case MsgId.textState:
        return EntityState(key: key, text: m.string(2), missing: m.boolean(3));
      case MsgId.switchState:
        return EntityState(key: key, boolValue: m.boolean(2), missing: m.boolean(4));
      case MsgId.fanState:
        return EntityState(key: key, boolValue: m.boolean(2), fanSpeedLevel: m.int32(6));
      case MsgId.climateState:
        return EntityState(key: key, climateMode: m.uint(2), currentTemperature: m.float32(3),
            targetTemperature: m.float32(4), climateAction: m.uint(8), climatePreset: m.uint(12),
            missing: m.boolean(17));
    }
    return null;
  }
}

/// Builders for outgoing messages: each returns (message type, payload).
abstract final class Requests {
  static (int, Uint8List) hello(String clientInfo) => (
        MsgId.helloRequest,
        (ProtoWriter()
              ..string(1, clientInfo)
              ..uint(2, apiVersionMajor)
              ..uint(3, apiVersionMinor))
            .toBytes()
      );

  // Empty password: required by older firmware, ignored by newer firmware.
  static (int, Uint8List) authenticate() => (MsgId.authenticationRequest, Uint8List(0));
  static (int, Uint8List) empty(int type) => (type, Uint8List(0));

  static (int, Uint8List) getTimeResponse(DateTime now) => (
        MsgId.getTimeResponse,
        (ProtoWriter()..fixed32(1, now.millisecondsSinceEpoch ~/ 1000)).toBytes()
      );

  static (int, Uint8List) switchCommand(int key, bool on) =>
      (MsgId.switchCommand, (ProtoWriter()..fixed32(1, key)..boolean(2, on)).toBytes());

  static (int, Uint8List) fanCommand(int key, {bool? on, int? speedLevel}) {
    final w = ProtoWriter()..fixed32(1, key);
    if (on != null) {
      w
        ..boolean(2, true)
        ..boolean(3, on);
    }
    if (speedLevel != null) {
      w
        ..boolean(10, true)
        ..int32(11, speedLevel);
    }
    return (MsgId.fanCommand, w.toBytes());
  }

  static (int, Uint8List) climateCommand(int key, {int? mode, double? target, int? preset}) {
    final w = ProtoWriter()..fixed32(1, key);
    if (mode != null) {
      w
        ..boolean(2, true)
        ..uint(3, mode);
    }
    if (target != null) {
      w
        ..boolean(4, true)
        ..float32(5, target);
    }
    if (preset != null) {
      w
        ..boolean(18, true)
        ..uint(19, preset);
    }
    return (MsgId.climateCommand, w.toBytes());
  }

  static (int, Uint8List) numberCommand(int key, double value) =>
      (MsgId.numberCommand, (ProtoWriter()..fixed32(1, key)..float32(2, value)).toBytes());

  static (int, Uint8List) selectCommand(int key, String option) =>
      (MsgId.selectCommand, (ProtoWriter()..fixed32(1, key)..string(2, option)).toBytes());

  static (int, Uint8List) buttonCommand(int key) =>
      (MsgId.buttonCommand, (ProtoWriter()..fixed32(1, key)).toBytes());

  static (int, Uint8List) textCommand(int key, String value) =>
      (MsgId.textCommand, (ProtoWriter()..fixed32(1, key)..string(2, value)).toBytes());

  static (int, Uint8List) executeService(int key) =>
      (MsgId.executeServiceRequest, (ProtoWriter()..fixed32(1, key)).toBytes());
}

class ApiServiceInfo {
  final String name;
  final int key;

  const ApiServiceInfo({required this.name, required this.key});

  factory ApiServiceInfo.fromProto(ProtoMessage m) => ApiServiceInfo(
        name: m.string(1),
        key: m.fixed32(2),
      );
}

class HomeassistantEvent {
  final String service;
  final Map<String, String> data;
  final bool isEvent;

  const HomeassistantEvent({required this.service, required this.data, required this.isEvent});

  factory HomeassistantEvent.fromProto(ProtoMessage m) {
    final map = <String, String>{};
    for (final raw in m.bytesList(2)) {
      final entry = ProtoMessage.decode(raw);
      final k = entry.string(1);
      if (k.isNotEmpty) map[k] = entry.string(2);
    }
    return HomeassistantEvent(
      service: m.string(1),
      data: map,
      isEvent: m.boolean(5),
    );
  }
}
