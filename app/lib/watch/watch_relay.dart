// iPhone side of the Apple Watch app. watchOS can't open the raw TCP socket the ESPHome API
// needs, so the watch sends small requests over WatchConnectivity; WatchRelay.swift forwards
// them on channel `iq2020/watch` to this code, which runs in its own headless Flutter engine
// (so it works when the phone app is closed or the phone is locked), keeps an encrypted
// connection to the first saved spa while the watch is in use, and answers with a SpaSnapshot.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../api/esphome_client.dart';
import '../api/messages.dart';
import '../device_store.dart';
import 'spa_snapshot.dart';

/// Entry point for the headless engine started by WatchRelay.swift.
@pragma('vm:entry-point')
Future<void> watchRelayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  WatchRelay().start();
}

class WatchRelay {
  static const channel = MethodChannel('iq2020/watch');
  static const _idle = Duration(seconds: 45); // free the ESP32 connection slot after this
  static const _ready = Duration(seconds: 8);

  EspHomeClient? _client;
  SavedDevice? _device;
  Timer? _idleTimer;
  Timer? _pushTimer;

  void start() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'request') throw MissingPluginException(call.method);
      return _handle(Map<Object?, Object?>.from(call.arguments as Map));
    });
  }

  Future<Map<String, Object?>> _handle(Map<Object?, Object?> req) async {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idle, _close);
    try {
      final client = await _connected();
      if (client == null) return {'error': 'No hot tub saved on the iPhone. Add it in the IQ2020 Spa app.'};
      var snap = _snapshot();
      if (req['op'] != 'snapshot') {
        await applyWatchCommand(client, snap, req);
        // Give the spa a moment to report the new state before answering.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        snap = _snapshot();
      }
      return {'snapshot': snap.toMap()};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  SpaSnapshot _snapshot() => SpaSnapshot.fromClient(
        _client!,
        name: _device!.name,
        heatUpTempC: _device!.heatUpTempC,
        vacationTempC: _device!.vacationTempC,
      );

  /// The client for the first saved spa, connected and with its states loaded, or null when the
  /// phone has no spa saved.
  Future<EspHomeClient?> _connected() async {
    final store = DeviceStore();
    await store.load();
    final device = store.devices.firstOrNull;
    if (device == null) return null;
    if (_device?.id != device.id || _device?.encryptionKey != device.encryptionKey || _device?.host != device.host) {
      _close();
      _device = device;
      _client = EspHomeClient(
        host: device.host,
        port: device.port,
        encryptionKey: device.encryptionKey.isEmpty ? null : device.encryptionKey,
        clientInfo: 'IQ2020 Watch relay',
      )..addListener(_schedulePush);
    } else {
      _device = device;
    }
    final client = _client!;
    await client.connect();
    final ok = await _waitFor(client, _ready, (c) {
      if (c.status != ConnectionStatus.connected) return false;
      final climate = c.entities.values.where((e) => e.kind == EntityKind.climate).firstOrNull;
      return climate == null ? c.states.isNotEmpty : c.states.containsKey(climate.key);
    });
    if (!ok) throw ApiException(client.lastError ?? 'Hot tub not reachable from the iPhone');
    return client;
  }

  /// Waits until [done] holds or [timeout] passes; true if it held.
  Future<bool> _waitFor(EspHomeClient c, Duration timeout, bool Function(EspHomeClient) done) async {
    if (done(c)) return true;
    final completer = Completer<bool>();
    void check() {
      if (!completer.isCompleted && done(c)) completer.complete(true);
    }

    c.addListener(check);
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(done(c));
    });
    final result = await completer.future;
    timer.cancel();
    c.removeListener(check);
    return result;
  }

  /// While connected, pushes fresh snapshots to the watch (at most once a second) so an open
  /// watch app updates without polling.
  void _schedulePush() {
    if (_pushTimer?.isActive ?? false) return;
    _pushTimer = Timer(const Duration(seconds: 1), () {
      final c = _client;
      if (c == null || c.status != ConnectionStatus.connected) return;
      channel.invokeMethod('push', _snapshot().toMap()).catchError((_) => null);
    });
  }

  void _close() {
    _idleTimer?.cancel();
    _pushTimer?.cancel();
    final c = _client;
    _client = null;
    _device = null;
    if (c != null) {
      c.removeListener(_schedulePush);
      c.disconnect().whenComplete(c.dispose);
    }
  }
}
