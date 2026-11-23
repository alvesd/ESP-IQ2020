// Saved spas. Host/port/name live in secure storage together with the API key so the key is
// never written to plain preferences or backups.
import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedDevice {
  final String id; // ESPHome node name, e.g. "hot-tub"
  final String name;
  final String host;
  final int port;
  final String encryptionKey;

  const SavedDevice({
    required this.id,
    required this.name,
    required this.host,
    this.port = 6053,
    this.encryptionKey = '',
  });

  SavedDevice copyWith({String? name, String? host, int? port, String? encryptionKey}) => SavedDevice(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        encryptionKey: encryptionKey ?? this.encryptionKey,
      );

  Map<String, Object> toJson() =>
      {'id': id, 'name': name, 'host': host, 'port': port, 'key': encryptionKey};

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 6053,
        encryptionKey: (j['key'] as String?) ?? '',
      );
}

class DeviceStore extends ChangeNotifier {
  static const _storageKey = 'iq2020.devices.v1';
  final FlutterSecureStorage _storage;
  List<SavedDevice> devices = [];

  DeviceStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      devices = [
        for (final j in jsonDecode(raw) as List<dynamic>) SavedDevice.fromJson(j as Map<String, dynamic>),
      ];
    }
    notifyListeners();
  }

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
