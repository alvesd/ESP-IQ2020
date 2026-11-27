// ESPHome client supporting local native API (TCP 6053 with Noise/plaintext) and optional
// remote HTTPS/SSE + REST via ESPHome web_server v3 (e.g. behind a Cloudflare Tunnel + Access).
//
// Local-only devices (empty remoteUrl) use only TCP 6053 and never issue HTTP requests.
// When both host and remoteUrl are configured, local TCP is tried first with fast failover.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'cf_access.dart';
import 'messages.dart';
import 'noise.dart';
import 'protobuf.dart';
import 'web_client_protocol.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

enum ConnectionStatus { disconnected, connecting, connected, failed }

enum ConnectionTransport { none, local, remote }

/// Byte buffer that lets the reader await an exact number of bytes from the socket stream.
class _ByteReader {
  final BytesBuilder _buf = BytesBuilder(copy: false);
  Uint8List _data = Uint8List(0);
  int _pos = 0;
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  void add(List<int> chunk) {
    _buf.add(chunk);
    _wake();
  }

  void close([Object? error]) {
    _closed = true;
    _error ??= error;
    _wake();
  }

  void _wake() {
    final w = _waiter;
    _waiter = null;
    w?.complete();
  }

  int get _available => _data.length - _pos + _buf.length;

  Future<Uint8List> read(int n) async {
    while (_available < n) {
      if (_closed) throw _error ?? ApiException('Connection closed');
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    if (_data.length - _pos < n) {
      _data = Uint8List.fromList([..._data.sublist(_pos), ..._buf.takeBytes()]);
      _pos = 0;
    }
    final out = Uint8List.sublistView(_data, _pos, _pos + n);
    _pos += n;
    return Uint8List.fromList(out);
  }

  Future<int> readVarint() async {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = (await read(1))[0];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
  }
}

abstract class _FrameHelper {
  Future<void> handshake();
  Future<void> send(int type, Uint8List data);
  Future<(int, Uint8List)> receive();
}

class _PlaintextFrameHelper implements _FrameHelper {
  final Socket _socket;
  final _ByteReader _reader;
  _PlaintextFrameHelper(this._socket, this._reader);

  @override
  Future<void> handshake() async {}

  static List<int> _varint(int v) {
    final out = <int>[];
    while (v >= 0x80) {
      out.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  @override
  Future<void> send(int type, Uint8List data) async {
    _socket.add([0x00, ..._varint(data.length), ..._varint(type), ...data]);
  }

  @override
  Future<(int, Uint8List)> receive() async {
    final preamble = (await _reader.read(1))[0];
    if (preamble == 0x01) {
      throw ApiException('Device requires encryption: add its API encryption key.');
    }
    if (preamble != 0x00) throw ApiException('Invalid preamble $preamble');
    final len = await _reader.readVarint();
    final type = await _reader.readVarint();
    return (type, len == 0 ? Uint8List(0) : await _reader.read(len));
  }
}

class _NoiseFrameHelper implements _FrameHelper {
  final Socket _socket;
  final _ByteReader _reader;
  final Uint8List _psk;
  NoiseCipher? _enc;
  NoiseCipher? _dec;
  String serverName = '';

  _NoiseFrameHelper(this._socket, this._reader, this._psk);

  void _writeFrame(List<int> payload) {
    final len = payload.length;
    _socket.add([0x01, (len >> 8) & 0xFF, len & 0xFF, ...payload]);
  }

  Future<Uint8List> _readFrame() async {
    final header = await _reader.read(3);
    if (header[0] != 0x01) {
      if (header[0] == 0x00) {
        throw ApiException('Device uses plaintext API: remove the encryption key in the app.');
      }
      throw ApiException('Invalid frame marker ${header[0]}');
    }
    final len = (header[1] << 8) | header[2];
    return len == 0 ? Uint8List(0) : _reader.read(len);
  }

  @override
  Future<void> handshake() async {
    final hs = NoiseHandshake.initiator(_psk);
    final msg1 = await hs.writeMessage1();
    _writeFrame(const []); // NOISE_HELLO: empty frame (0x01 0x00 0x00)
    _writeFrame([0x00, ...msg1]);

    final hello = await _readFrame();
    if (hello.isEmpty || hello[0] != 0x01) {
      throw ApiException('Unsupported Noise protocol from device');
    }
    serverName = String.fromCharCodes(hello.sublist(1)).split('\u0000').first;

    final resp = await _readFrame();
    if (resp.isEmpty) throw ApiException('Empty handshake response');
    if (resp[0] != 0x00) {
      final reason = String.fromCharCodes(resp.sublist(1));
      throw ApiException(reason == 'Handshake MAC failure'
          ? 'Wrong encryption key for $serverName'
          : 'Handshake failed: $reason');
    }
    try {
      final (enc, dec) = await hs.readMessage2(resp.sublist(1));
      _enc = enc;
      _dec = dec;
    } on Exception {
      throw ApiException('Wrong encryption key for $serverName');
    }
  }

  @override
  Future<void> send(int type, Uint8List data) async {
    final plain = [(type >> 8) & 0xFF, type & 0xFF, (data.length >> 8) & 0xFF, data.length & 0xFF, ...data];
    _writeFrame(await _enc!.encrypt(plain));
  }

  @override
  Future<(int, Uint8List)> receive() async {
    final frame = await _readFrame();
    final msg = await _dec!.decrypt(frame);
    if (msg.length < 4) throw ApiException('Decrypted message too short');
    final type = (msg[0] << 8) | msg[1];
    final dataLen = (msg[2] << 8) | msg[3];
    if (dataLen > msg.length - 4) throw ApiException('Bad data packet: length $dataLen > ${msg.length - 4}');
    return (type, Uint8List.sublistView(msg, 4, 4 + dataLen));
  }
}

/// One live connection to one ESPHome device. Exposes entities and their states as a
/// [ChangeNotifier] so widgets can rebuild on every state push. Reconnects automatically.
class EspHomeClient extends ChangeNotifier {
  final String host;
  final int port;
  final String? encryptionKey;
  final String? remoteUrl;
  final String? cfAccessClientId;
  final String? cfAccessClientSecret;
  final String clientInfo;

  EspHomeClient({
    this.host = '',
    this.port = 6053,
    this.encryptionKey,
    this.remoteUrl,
    this.cfAccessClientId,
    this.cfAccessClientSecret,
    this.clientInfo = 'IQ2020 Mobile',
  });

  ConnectionStatus status = ConnectionStatus.disconnected;
  ConnectionTransport transport = ConnectionTransport.none;
  bool get isRemote => transport == ConnectionTransport.remote;
  String? lastError;
  DeviceInfo? deviceInfo;
  final Map<int, EntityInfo> entities = {};
  final Map<int, EntityState> states = {};

  Socket? _socket;
  _FrameHelper? _frames;
  HttpClient? _remoteClient;
  HttpClient? _remoteCommandClient;
  StreamSubscription<String>? _remoteSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime _lastRx = DateTime.now();
  bool _wantConnected = false;
  int _attempt = 0;
  Future<void> _sendChain = Future.value();

  static const _connectTimeout = Duration(seconds: 10);
  static const _localFallbackTimeout = Duration(seconds: 3);
  static const _pingInterval = Duration(seconds: 20);
  static const _rxTimeout = Duration(seconds: 60);
  static const _remoteWatchdogInterval = Duration(seconds: 30);
  static const _remoteRxTimeout = Duration(seconds: 90);

  Future<void> connect() async {
    _wantConnected = true;
    _reconnectTimer?.cancel();
    // Lifecycle "resumed" can fire while a connection is already up or mid-handshake; opening a
    // second socket then makes ESPHome reset the connection.
    if (status == ConnectionStatus.connecting || status == ConnectionStatus.connected) return;
    await _connectOnce();
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    final frames = _frames;
    final remoteClient = _remoteClient;
    if (status == ConnectionStatus.connected && transport == ConnectionTransport.local) {
      try {
        await _send(Requests.empty(MsgId.disconnectRequest));
      } catch (_) {}
    }
    // If connect() ran while we awaited, a newer connection owns the socket: leave it alone.
    if (_wantConnected || !identical(frames, _frames) || !identical(remoteClient, _remoteClient)) return;
    _teardown(ConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _teardown(ConnectionStatus.disconnected, notify: false);
    super.dispose();
  }

  Future<void> _connectOnce() async {
    _setStatus(ConnectionStatus.connecting);
    final normalizedRemote = normalizeRemoteUrl(remoteUrl ?? '');
    final hasLocal = host.trim().isNotEmpty;
    final hasRemote = normalizedRemote.isNotEmpty;

    if (!hasLocal && !hasRemote) {
      _fail('No host or remote URL configured');
      return;
    }

    if (hasLocal) {
      final timeout = hasRemote ? _localFallbackTimeout : _connectTimeout;
      final reader = _ByteReader();
      try {
        final socket = await Socket.connect(host.trim(), port, timeout: timeout);
        socket.setOption(SocketOption.tcpNoDelay, true);
        _socket = socket;
        socket.listen(reader.add,
            onError: (Object e) => reader.close(e), onDone: reader.close, cancelOnError: true);

        final key = encryptionKey;
        final frames = (key != null && key.isNotEmpty)
            ? _NoiseFrameHelper(socket, reader, decodeNoisePsk(key))
            : _PlaintextFrameHelper(socket, reader);
        _frames = frames;
        await frames.handshake().timeout(timeout);

        await _send(Requests.hello(clientInfo));
        await _send(Requests.authenticate());
        await _expectSetup(frames, MsgId.helloResponse);

        await _send(Requests.empty(MsgId.deviceInfoRequest));
        entities.clear();
        states.clear();
        await _send(Requests.empty(MsgId.listEntitiesRequest));

        // Read until entity listing is done (device info arrives in the same window).
        while (true) {
          final (type, data) = await frames.receive().timeout(_connectTimeout);
          if (type == MsgId.listEntitiesDone) break;
          _dispatch(type, data);
        }
        await _send(Requests.empty(MsgId.subscribeStatesRequest));

        transport = ConnectionTransport.local;
        _attempt = 0;
        lastError = null;
        _lastRx = DateTime.now();
        _setStatus(ConnectionStatus.connected);
        _startPing();
        unawaited(_readLoop(frames));
        return;
      } catch (e) {
        _frames = null;
        _socket?.destroy();
        _socket = null;
        if (!hasRemote) {
          _fail(e is ApiException ? e.message : e.toString());
          return;
        }
      }
    }

    if (hasRemote) {
      try {
        await _connectRemote(Uri.parse(normalizedRemote));
      } catch (e) {
        _fail(e is ApiException ? e.message : e.toString());
      }
    }
  }

  Map<String, String> get _cfAccessHeaders {
    final id = (cfAccessClientId ?? '').trim();
    final secret = (cfAccessClientSecret ?? '').trim();
    if (id.isEmpty || secret.isEmpty) return const {};
    return {
      'CF-Access-Client-Id': id,
      'CF-Access-Client-Secret': secret,
    };
  }

  Future<void> _connectRemote(Uri baseUri) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    _remoteClient = client;
    final basePath = baseUri.path.endsWith('/') ? baseUri.path.substring(0, baseUri.path.length - 1) : baseUri.path;
    final eventsUri = baseUri.replace(path: '$basePath/events');

    final req = await client.getUrl(eventsUri).timeout(_connectTimeout);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    _cfAccessHeaders.forEach(req.headers.set);

    final res = await req.close().timeout(_connectTimeout);
    if (!identical(client, _remoteClient)) {
      client.close(force: true);
      return;
    }

    final location = res.headers.value(HttpHeaders.locationHeader);
    final contentType = res.headers.contentType?.mimeType;
    if (res.statusCode >= 300 && res.statusCode < 400 && isCfAccessLoginUrl(location)) {
      await res.drain<void>();
      throw ApiException(kCfAccessBlockedMessage);
    }
    if (res.statusCode != 200 || (contentType != null && contentType.contains('text/html'))) {
      final body = await _readPrefix(res);
      if (isCfAccessBlockedResponse(
        statusCode: res.statusCode,
        locationHeader: location,
        contentType: contentType,
        bodyPrefix: body,
      )) {
        throw ApiException(kCfAccessBlockedMessage);
      }
      throw ApiException('Remote server returned HTTP ${res.statusCode}');
    }

    entities.clear();
    states.clear();
    transport = ConnectionTransport.remote;
    _attempt = 0;
    lastError = null;
    _lastRx = DateTime.now();
    _setStatus(ConnectionStatus.connected);

    final parser = SseParser();
    _remoteSub = res.transform(utf8.decoder).listen(
      (chunk) {
        if (!identical(client, _remoteClient)) return;
        _lastRx = DateTime.now();
        for (final ev in parser.addChunk(chunk)) {
          _dispatchSseEvent(ev);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!identical(client, _remoteClient)) return;
        debugPrint('ESPHome remote stream failed: $e\n$st');
        _fail(e is ApiException ? e.message : 'Remote connection lost ($e)');
      },
      onDone: () {
        if (!identical(client, _remoteClient)) return;
        _fail('Remote stream closed');
      },
      cancelOnError: true,
    );

    _startRemoteWatchdog();
  }

  Future<String> _readPrefix(HttpClientResponse res) async {
    try {
      final bytes = await res.take(2).expand((c) => c).take(2048).toList().timeout(const Duration(seconds: 3));
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  void _dispatchSseEvent(SseEvent ev) {
    if (ev.event == 'ping') {
      try {
        final decoded = jsonDecode(ev.data);
        if (decoded is Map<String, dynamic>) {
          final title = (decoded['title'] as String?)?.trim() ?? '';
          if (title.isNotEmpty && deviceInfo == null) {
            deviceInfo = DeviceInfo.basic(name: title);
            notifyListeners();
          }
        }
      } catch (_) {}
      return;
    }
    if (ev.event != 'state') return;
    try {
      final decoded = jsonDecode(ev.data);
      if (decoded is! Map<String, dynamic>) return;
      final id = decoded['id'] as String?;
      if (id == null || id.isEmpty) return;
      final key = webEntityKey(id);
      final parsed = parseWebStateEvent(decoded, existing: entities[key]);
      if (parsed == null) return;
      entities[key] = parsed.$1;
      states[key] = parsed.$2;
      notifyListeners();
    } catch (e) {
      debugPrint('Ignoring malformed SSE state event: $e');
    }
  }

  void _startRemoteWatchdog() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_remoteWatchdogInterval, (_) {
      if (DateTime.now().difference(_lastRx) > _remoteRxTimeout) {
        _fail('Remote stream stopped responding');
      }
    });
  }

  /// Reads setup-phase messages until [wanted] arrives, answering pings meanwhile.
  Future<void> _expectSetup(_FrameHelper frames, int wanted) async {
    while (true) {
      final (type, data) = await frames.receive().timeout(_connectTimeout);
      if (type == wanted) return;
      if (type == MsgId.authenticationResponse) {
        // Field 1 = invalid_password. The mobile firmware does not use API passwords.
        if (data.isNotEmpty) throw ApiException('Device requires an API password (unsupported)');
        continue;
      }
      _dispatch(type, data);
    }
  }

  Future<void> _readLoop(_FrameHelper frames) async {
    try {
      while (identical(frames, _frames)) {
        final (type, data) = await frames.receive();
        _lastRx = DateTime.now();
        _dispatch(type, data);
      }
    } catch (e, st) {
      if (!identical(frames, _frames)) return;
      debugPrint('ESPHome read loop failed: $e\n$st');
      _fail(e is ApiException ? e.message : 'Connection lost (${e.runtimeType}: $e)');
    }
  }

  void _dispatch(int type, Uint8List data) {
    switch (type) {
      case MsgId.pingRequest:
        _sendQuiet(Requests.empty(MsgId.pingResponse));
        return;
      case MsgId.pingResponse:
      case MsgId.authenticationResponse:
      case MsgId.helloResponse:
        return;
      case MsgId.getTimeRequest:
        _sendQuiet(Requests.getTimeResponse(DateTime.now()));
        return;
      case MsgId.disconnectRequest:
        _sendQuiet(Requests.empty(MsgId.disconnectResponse));
        _fail('Device closed the connection');
        return;
      case MsgId.deviceInfoResponse:
        deviceInfo = DeviceInfo.fromProto(ProtoMessage.decode(data));
        notifyListeners();
        return;
    }
    final info = EntityInfo.fromList(type, data);
    if (info != null) {
      entities[info.key] = info;
      return;
    }
    final state = EntityState.fromState(type, data);
    if (state != null && entities.containsKey(state.key)) {
      states[state.key] = state;
      notifyListeners();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (DateTime.now().difference(_lastRx) > _rxTimeout) {
        _fail('Device stopped responding');
        return;
      }
      _sendQuiet(Requests.empty(MsgId.pingRequest));
    });
  }

  void _fail(String error) {
    lastError = error;
    _teardown(ConnectionStatus.failed);
    _scheduleReconnect();
  }

  void _sendQuiet((int, Uint8List) msg) => unawaited(_send(msg).catchError((_) {}));

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    final seconds = [1, 2, 5, 10, 30][_attempt.clamp(0, 4)];
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (_wantConnected) unawaited(_connectOnce());
    });
  }

  void _teardown(ConnectionStatus next, {bool notify = true}) {
    _pingTimer?.cancel();
    _pingTimer = null;
    _frames = null;
    _socket?.destroy();
    _socket = null;
    unawaited(_remoteSub?.cancel());
    _remoteSub = null;
    _remoteClient?.close(force: true);
    _remoteClient = null;
    _remoteCommandClient?.close(force: true);
    _remoteCommandClient = null;
    transport = ConnectionTransport.none;
    status = next;
    if (notify) notifyListeners();
  }

  void _setStatus(ConnectionStatus s) {
    status = s;
    notifyListeners();
  }

  /// Serialises sends so Noise nonces stay in order even with concurrent callers.
  Future<void> _send((int, Uint8List) msg) {
    final frames = _frames;
    if (frames == null) return Future.error(ApiException('Not connected'));
    final next = _sendChain.then((_) => frames.send(msg.$1, msg.$2));
    _sendChain = next.catchError((_) {});
    return next;
  }

  Future<void> _sendWebCommand(int key, String actionPath, [Map<String, String>? query]) async {
    final entity = entities[key];
    if (entity == null) throw ApiException('Unknown entity');
    final normalizedRemote = normalizeRemoteUrl(remoteUrl ?? '');
    if (normalizedRemote.isEmpty) throw ApiException('Not connected');
    final baseUri = Uri.parse(normalizedRemote);
    final uri = buildWebCommandUri(baseUri, entity, actionPath, query);

    final client = _remoteCommandClient ??= (HttpClient()..connectionTimeout = _connectTimeout);
    final req = await client.postUrl(uri).timeout(_connectTimeout);
    req.followRedirects = false;
    _cfAccessHeaders.forEach(req.headers.set);

    final res = await req.close().timeout(_connectTimeout);
    final location = res.headers.value(HttpHeaders.locationHeader);
    final contentType = res.headers.contentType?.mimeType;
    if (res.statusCode >= 300 && res.statusCode < 400 && isCfAccessLoginUrl(location)) {
      await res.drain<void>();
      throw ApiException(kCfAccessBlockedMessage);
    }
    if (res.statusCode >= 400) {
      final body = await _readPrefix(res);
      if (isCfAccessBlockedResponse(
        statusCode: res.statusCode,
        locationHeader: location,
        contentType: contentType,
        bodyPrefix: body,
      )) {
        throw ApiException(kCfAccessBlockedMessage);
      }
      throw ApiException('Remote command failed (HTTP ${res.statusCode})');
    }
    await res.drain<void>();
  }

  // ---- Commands -------------------------------------------------------------------------

  Future<void> setSwitch(int key, bool on) => transport == ConnectionTransport.remote
      ? _sendWebCommand(key, on ? 'turn_on' : 'turn_off')
      : _send(Requests.switchCommand(key, on));

  Future<void> setFan(int key, {bool? on, int? speedLevel}) {
    if (transport != ConnectionTransport.remote) {
      return _send(Requests.fanCommand(key, on: on, speedLevel: speedLevel));
    }
    if (on == false) return _sendWebCommand(key, 'turn_off');
    return _sendWebCommand(
      key,
      'turn_on',
      speedLevel == null ? null : {'speed_level': '$speedLevel'},
    );
  }

  Future<void> setClimate(int key, {int? mode, double? target, int? preset}) {
    if (transport != ConnectionTransport.remote) {
      return _send(Requests.climateCommand(key, mode: mode, target: target, preset: preset));
    }
    final q = <String, String>{};
    if (mode != null) q['mode'] = climateModeToWeb(mode);
    if (target != null) q['target_temperature'] = target.toStringAsFixed(2);
    if (preset != null) q['preset'] = climatePresetToWeb(preset);
    return _sendWebCommand(key, 'set', q);
  }

  Future<void> setNumber(int key, double value) => transport == ConnectionTransport.remote
      ? _sendWebCommand(key, 'set', {'value': '$value'})
      : _send(Requests.numberCommand(key, value));

  Future<void> setSelect(int key, String option) => transport == ConnectionTransport.remote
      ? _sendWebCommand(key, 'set', {'option': option})
      : _send(Requests.selectCommand(key, option));

  Future<void> pressButton(int key) => transport == ConnectionTransport.remote
      ? _sendWebCommand(key, 'press')
      : _send(Requests.buttonCommand(key));

  Future<void> setText(int key, String value) => transport == ConnectionTransport.remote
      ? _sendWebCommand(key, 'set', {'value': value})
      : _send(Requests.textCommand(key, value));

  // ---- Lookup helpers -------------------------------------------------------------------

  Iterable<EntityInfo> ofKind(EntityKind kind) =>
      entities.values.where((e) => e.kind == kind).toList()..sort((a, b) => a.name.compareTo(b.name));

  EntityInfo? byObjectId(String objectId) {
    for (final e in entities.values) {
      if (e.objectId == objectId) return e;
    }
    return null;
  }
}
