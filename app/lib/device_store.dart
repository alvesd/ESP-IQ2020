// Saved spas. Host/port/name live in secure storage together with the API key so the key is
// never written to plain preferences or backups.
import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/cf_access.dart';

class SavedDevice {
  static const double defaultHeatUpTempC = (102 - 32) * 5 / 9;
  static const double defaultVacationTempC = (85 - 32) * 5 / 9;

  final String id; // ESPHome node name, e.g. "hot-tub"
  final String name;
  final String host;
  final int port;
  final String encryptionKey;
  final String remoteUrl;
  final String cfAccessClientId;
  final String cfAccessClientSecret;
  final double heatUpTempC;
  final double vacationTempC;

  const SavedDevice({
    required this.id,
    required this.name,
    this.host = '',
    this.port = 6053,
    this.encryptionKey = '',
    this.remoteUrl = '',
    this.cfAccessClientId = '',
    this.cfAccessClientSecret = '',
    this.heatUpTempC = defaultHeatUpTempC,
    this.vacationTempC = defaultVacationTempC,
  });

  CfAccessConfig get effectiveRemote => CfAccessConfig.resolve(
        remoteUrl: remoteUrl,
        clientId: cfAccessClientId,
        clientSecret: cfAccessClientSecret,
      );

  SavedDevice copyWith({
    String? name,
    String? host,
    int? port,
    String? encryptionKey,
    String? remoteUrl,
    String? cfAccessClientId,
    String? cfAccessClientSecret,
    double? heatUpTempC,
    double? vacationTempC,
  }) =>
      SavedDevice(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        encryptionKey: encryptionKey ?? this.encryptionKey,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        cfAccessClientId: cfAccessClientId ?? this.cfAccessClientId,
        cfAccessClientSecret: cfAccessClientSecret ?? this.cfAccessClientSecret,
        heatUpTempC: heatUpTempC ?? this.heatUpTempC,
        vacationTempC: vacationTempC ?? this.vacationTempC,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'key': encryptionKey,
        if (remoteUrl.isNotEmpty) 'remoteUrl': remoteUrl,
        if (cfAccessClientId.isNotEmpty) 'cfAccessClientId': cfAccessClientId,
        if (cfAccessClientSecret.isNotEmpty) 'cfAccessClientSecret': cfAccessClientSecret,
        'heatUpTempC': heatUpTempC,
        'vacationTempC': vacationTempC,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        host: (j['host'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 6053,
        encryptionKey: (j['key'] as String?) ?? '',
        remoteUrl: (j['remoteUrl'] as String?) ?? '',
        cfAccessClientId: (j['cfAccessClientId'] as String?) ?? '',
        cfAccessClientSecret: (j['cfAccessClientSecret'] as String?) ?? '',
        heatUpTempC: (j['heatUpTempC'] as num?)?.toDouble() ?? defaultHeatUpTempC,
        vacationTempC: (j['vacationTempC'] as num?)?.toDouble() ?? defaultVacationTempC,
      );
}

class DeviceStore extends ChangeNotifier {
  static const _storageKey = 'iq2020.devices.v1';
  final FlutterSecureStorage _storage;
  List<SavedDevice> devices = [];

  // After first unlock (not "while unlocked"): the Apple Watch relay reads the key while the
  // iPhone is locked in a pocket. Still device-only, so it never syncs to iCloud.
  static const _iosOptions = IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);

  DeviceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(iOptions: _iosOptions);

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      devices = [
        for (final j in jsonDecode(raw) as List<dynamic>) SavedDevice.fromJson(j as Map<String, dynamic>),
      ];
      // Items saved by older builds were "while unlocked"; rewriting moves them to the options
      // above (the plugin replaces the item when only its accessibility differs).
      if (!_migrated) {
        _migrated = true;
        await _storage.write(key: _storageKey, value: raw);
      }
    }
    notifyListeners();
  }

  static bool _migrated = false;

  Future<void> upsert(SavedDevice d) async {
    devices = [...devices.where((e) => e.id != d.id), d];
    await _persist();
  }

  Future<void> remove(String id) async {
    devices = devices.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode([for (final d in devices) d.toJson()]));
    notifyListeners();
  }
}

/// A device announced on the LAN as _esphomelib._tcp.
class DiscoveredDevice {
  final String id;
  final String friendlyName;
  final String host;
  final int port;
  final bool encrypted;
  final String projectName;

  const DiscoveredDevice({
    required this.id,
    required this.friendlyName,
    required this.host,
    required this.port,
    required this.encrypted,
    required this.projectName,
  });

  /// ESPHome advertises `project_name` in TXT records when `esphome.project` is set; the mobile
  /// firmware uses "iq2020.mobile". Upstream configs usually omit it, so this is only a hint.
  bool get looksLikeSpa => projectName.startsWith('iq2020') || id.contains('tub') || id.contains('spa');
}

class Discovery extends ChangeNotifier {
  static const serviceType = '_esphomelib._tcp';
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final Map<String, DiscoveredDevice> found = {};

  Future<void> start() async {
    await stop();
    final d = BonsoirDiscovery(type: serviceType);
    _discovery = d;
    await d.ready;
    _sub = d.eventStream?.listen((event) {
      final service = event.service;
      if (service == null) return;
      switch (event.type) {
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          service.resolve(d.serviceResolver);
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          if (service is ResolvedBonsoirService) {
            final txt = service.attributes;
            final host = service.host;
            if (host == null) return;
            found[service.name] = DiscoveredDevice(
              id: service.name,
              friendlyName: txt['friendly_name'] ?? service.name,
              host: host.endsWith('.') ? host.substring(0, host.length - 1) : host,
              port: service.port,
              encrypted: (txt['api_encryption'] ?? '').isNotEmpty,
              projectName: txt['project_name'] ?? '',
            );
            notifyListeners();
          }
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          found.remove(service.name);
          notifyListeners();
        default:
          break;
      }
    });
    await d.start();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
