// ESPHome web_server v3 SSE (/events) + REST POST protocol helpers.
// Mirrors the endpoints and event payloads consumed by components/iq2020_web/index.html.
import 'messages.dart';

/// Deterministic 32-bit FNV-1a hash so web_server entity IDs (e.g. "climate-temperature")
/// map to stable integer keys in EspHomeClient.entities / states.
int webEntityKey(String id) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < id.length; i++) {
    hash ^= id.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

class SseEvent {
  final String event;
  final String data;
  const SseEvent(this.event, this.data);
}

/// Incremental SSE chunk parser supporting LF and CRLF line endings.
class SseParser {
  String _buf = '';
  String _event = 'message';
  final List<String> _dataLines = [];

  List<SseEvent> addChunk(String chunk) {
    final out = <SseEvent>[];
    _buf += chunk;
    while (true) {
      final nl = _buf.indexOf('\n');
      if (nl == -1) break;
      var line = _buf.substring(0, nl);
      _buf = _buf.substring(nl + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

      if (line.isEmpty) {
        if (_dataLines.isNotEmpty) {
          out.add(SseEvent(_event, _dataLines.join('\n')));
          _dataLines.clear();
        }
        _event = 'message';
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon == -1 ? line : line.substring(0, colon);
      var value = colon == -1 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      if (field == 'event') {
        _event = value.isEmpty ? 'message' : value;
      } else if (field == 'data') {
        _dataLines.add(value);
      }
    }
    return out;
  }
}

int parseClimateMode(Object? v) {
  final s = '${v ?? ''}'.toUpperCase();
  return switch (s) {
    'OFF' => ClimateMode.off,
    'HEAT_COOL' => ClimateMode.heatCool,
    'COOL' => ClimateMode.cool,
    'HEAT' => ClimateMode.heat,
    'AUTO' => ClimateMode.auto,
    _ => ClimateMode.off,
  };
}

String climateModeToWeb(int mode) => switch (mode) {
      ClimateMode.off => 'OFF',
      ClimateMode.heatCool => 'HEAT_COOL',
      ClimateMode.cool => 'COOL',
      ClimateMode.heat => 'HEAT',
      ClimateMode.auto => 'AUTO',
      _ => 'OFF',
    };

int parseClimateAction(Object? v) {
  final s = '${v ?? ''}'.toUpperCase();
  return switch (s) {
    'COOLING' => ClimateAction.cooling,
    'HEATING' => ClimateAction.heating,
    'IDLE' => ClimateAction.idle,
    _ => ClimateAction.off,
  };
}

int parseClimatePreset(Object? v) {
  final s = '${v ?? ''}'.toUpperCase();
  return switch (s) {
    'BOOST' => ClimatePreset.boost,
    'ECO' => ClimatePreset.eco,
    _ => ClimatePreset.none,
  };
}

String climatePresetToWeb(int preset) => switch (preset) {
      ClimatePreset.boost => 'BOOST',
      ClimatePreset.eco => 'ECO',
      _ => 'NONE',
    };

EntityCategory _parseCategory(Object? v) {
  if (v is int && v >= 0 && v < EntityCategory.values.length) {
    return EntityCategory.values[v];
  }
  final s = '$v'.toLowerCase();
  if (s == '1' || s == 'config') return EntityCategory.config;
  if (s == '2' || s == 'diagnostic') return EntityCategory.diagnostic;
  return EntityCategory.none;
}

double? _toDouble(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isNaN ? null : d;
  }
  if (v is String) {
    final d = double.tryParse(v);
    return (d == null || d.isNaN) ? null : d;
  }
  return null;
}

bool _toBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '${v ?? ''}'.toUpperCase();
  return s == 'ON' || s == 'TRUE' || s == '1' || s == 'YES';
}

EntityKind? _domainToKind(String domain) => switch (domain) {
      'binary_sensor' => EntityKind.binarySensor,
      'sensor' => EntityKind.sensor,
      'text_sensor' => EntityKind.textSensor,
      'switch' => EntityKind.switch_,
      'fan' => EntityKind.fan,
      'climate' => EntityKind.climate,
      'number' => EntityKind.number,
      'select' => EntityKind.select,
      'button' => EntityKind.button,
      'text' => EntityKind.text,
      _ => null,
    };

String _kindToDomainPath(EntityKind kind) => switch (kind) {
      EntityKind.binarySensor => 'binary_sensor',
      EntityKind.sensor => 'sensor',
      EntityKind.textSensor => 'text_sensor',
      EntityKind.switch_ => 'switch',
      EntityKind.fan => 'fan',
      EntityKind.climate => 'climate',
      EntityKind.number => 'number',
      EntityKind.select => 'select',
      EntityKind.button => 'button',
      EntityKind.text => 'text',
    };

/// Parses a single `event: state` JSON object from ESPHome `web_server` v3.
/// Preserves metadata from [existing] if an incremental update omits static fields.
(EntityInfo, EntityState)? parseWebStateEvent(Map<String, dynamic> d, {EntityInfo? existing}) {
  final rawId = d['id'] as String?;
  if (rawId == null || rawId.isEmpty) return null;

  var domain = (d['domain'] as String?) ?? '';
  if (domain.isEmpty) {
    if (rawId.contains('/')) {
      domain = rawId.split('/').first;
    } else if (rawId.contains('-')) {
      domain = rawId.split('-').first;
    }
  }
  final kind = _domainToKind(domain) ?? existing?.kind;
  if (kind == null) return null;

  final key = existing?.key ?? webEntityKey(rawId);
  final name = (d['name'] as String?) ?? existing?.name ?? rawId;
  final objectId = existing?.objectId ?? objectIdFromName(name);
  final icon = (d['icon'] as String?) ?? existing?.icon ?? '';
  final unit = (d['uom'] as String?) ?? existing?.unit ?? '';
  final category = d.containsKey('entity_category')
      ? _parseCategory(d['entity_category'])
      : (existing?.category ?? EntityCategory.none);
  final disabled = d.containsKey('is_disabled_by_default')
      ? _toBool(d['is_disabled_by_default'])
      : (existing?.disabledByDefault ?? false);

  var fanSpeedCount = existing?.fanSpeedCount ?? 0;
  if (kind == EntityKind.fan) {
    final sc = _toDouble(d['speed_count'])?.round();
    if (sc != null) fanSpeedCount = sc;
  }

  var options = existing?.options ?? const <String>[];
  if (d['option'] is List) {
    options = [for (final o in d['option'] as List<dynamic>) '$o'];
  } else if (d['options'] is List) {
    options = [for (final o in d['options'] as List<dynamic>) '$o'];
  }

  var minVal = existing?.minValue ?? 0.0;
  var maxVal = existing?.maxValue ?? 0.0;
  var stepVal = existing?.step ?? 1.0;
  if (kind == EntityKind.climate) {
    minVal = _toDouble(d['min_temp']) ?? minVal;
    maxVal = _toDouble(d['max_temp']) ?? maxVal;
    stepVal = _toDouble(d['step']) ?? stepVal;
  } else if (kind == EntityKind.number) {
    minVal = _toDouble(d['min_value']) ?? minVal;
    maxVal = _toDouble(d['max_value']) ?? maxVal;
    stepVal = _toDouble(d['step']) ?? stepVal;
  }
  if (stepVal == 0) stepVal = 1.0;

  var climateModes = existing?.climateModes ?? const <int>[];
  if (d['modes'] is List) {
    climateModes = [for (final m in d['modes'] as List<dynamic>) parseClimateMode(m)];
  }
  var climatePresets = existing?.climatePresets ?? const <int>[];
  if (d['presets'] is List) {
    climatePresets = [for (final p in d['presets'] as List<dynamic>) parseClimatePreset(p)];
  }

  final info = EntityInfo(
    kind: kind,
    key: key,
    objectId: objectId,
    name: name,
    icon: icon,
    unit: unit,
    deviceClass: existing?.deviceClass ?? '',
    accuracyDecimals: existing?.accuracyDecimals ?? 1,
    category: category,
    disabledByDefault: disabled,
    fanSpeedCount: fanSpeedCount,
    options: options,
    minValue: minVal,
    maxValue: maxVal,
    step: stepVal,
    climateModes: climateModes,
    climatePresets: climatePresets,
    climateSupportsAction: existing?.climateSupportsAction ?? (kind == EntityKind.climate),
  );

  final EntityState state;
  switch (kind) {
    case EntityKind.binarySensor:
      final raw = d.containsKey('value') ? d['value'] : d['state'];
      state = EntityState(key: key, boolValue: _toBool(raw), missing: raw == null && !d.containsKey('value'));
    case EntityKind.switch_:
      final raw = d.containsKey('value') ? d['value'] : d['state'];
      state = EntityState(key: key, boolValue: _toBool(raw));
    case EntityKind.fan:
      final raw = d.containsKey('value') ? d['value'] : d['state'];
      final speed = _toDouble(d['speed_level'])?.round() ?? 0;
      state = EntityState(key: key, boolValue: _toBool(raw), fanSpeedLevel: speed);
    case EntityKind.sensor:
    case EntityKind.number:
      final numVal = _toDouble(d['value']) ?? _toDouble(d['state']);
      state = EntityState(key: key, number: numVal ?? double.nan, missing: numVal == null);
    case EntityKind.textSensor:
    case EntityKind.select:
    case EntityKind.text:
      final txt = d['state']?.toString() ?? d['value']?.toString() ?? '';
      state = EntityState(key: key, text: txt, missing: txt == 'NA');
    case EntityKind.climate:
      final cur = _toDouble(d['current_temperature']) ?? double.nan;
      final tgt = _toDouble(d['target_temperature']) ?? double.nan;
      state = EntityState(
        key: key,
        climateMode: parseClimateMode(d['mode']),
        climateAction: parseClimateAction(d['action']),
        climatePreset: parseClimatePreset(d['preset']),
        currentTemperature: cur,
        targetTemperature: tgt,
      );
    case EntityKind.button:
      state = EntityState(key: key);
  }

  return (info, state);
}

Uri buildWebCommandUri(
  Uri baseUri,
  EntityInfo entity,
  String actionPath, [
  Map<String, String>? query,
]) {
  final domain = _kindToDomainPath(entity.kind);
  final basePath = baseUri.path.endsWith('/') ? baseUri.path.substring(0, baseUri.path.length - 1) : baseUri.path;
  final fullPath = '$basePath/$domain/${Uri.encodeComponent(entity.name)}/$actionPath';
  return baseUri.replace(
    path: fullPath,
    queryParameters: (query == null || query.isEmpty) ? null : query,
  );
}
