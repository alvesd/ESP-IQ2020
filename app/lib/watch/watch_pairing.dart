// Sets up a Wear OS watch from the phone with a QR code. Watches have no camera, so the watch
// shows the code and the phone scans it:
//
//   1. The watch opens a one-shot HTTP listener on the LAN and shows
//      `iq2020pair:1:<ip>:<port>:<token>:<watch X25519 public key>` as a QR code.
//   2. The phone scans it, makes its own X25519 key pair, derives a key with HKDF-SHA256 from the
//      shared secret (salt = token), encrypts the saved spa (name, host, port, API key) with
//      ChaCha20-Poly1305 (AAD = token) and POSTs it to http://<ip>:<port>/pair/<token>.
//   3. The watch decrypts it, saves it and closes the listener.
//
// The API key only crosses the LAN encrypted, to the one watch whose code was scanned, and the
// listener accepts a single correct request and gives up after a few minutes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../device_store.dart';

const _scheme = 'iq2020pair';
const _version = '1';
final _x25519 = X25519();
final _aead = Chacha20.poly1305Aead();
final _rng = Random.secure();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _unb64(String s) => base64Url.decode(base64Url.normalize(s));

class PairingCode {
  final String host;
  final int port;
  final String token;
  final Uint8List watchPublicKey;
  const PairingCode({required this.host, required this.port, required this.token, required this.watchPublicKey});

  String encode() => [_scheme, _version, host, port, token, _b64(watchPublicKey)].join(':');

  /// Parses a scanned QR text; null if it isn't an IQ2020 pairing code.
  static PairingCode? tryParse(String text) {
    final p = text.trim().split(':');
    if (p.length != 6 || p[0] != _scheme || p[1] != _version) return null;
    final port = int.tryParse(p[3]);
    if (port == null || port <= 0 || port > 65535 || InternetAddress.tryParse(p[2]) == null) return null;
    try {
      final key = _unb64(p[5]);
      if (key.length != 32 || p[4].length < 16) return null;
      return PairingCode(host: p[2], port: port, token: p[4], watchPublicKey: key);
    } on FormatException {
      return null;
    }
  }
}

Future<SecretKey> _sessionKey(SimpleKeyPair mine, Uint8List theirs, String token) async {
  final shared = await _x25519.sharedSecretKey(
    keyPair: mine,
    remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519),
  );
  return _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode(token), info: utf8.encode('iq2020-watch-pairing'));
}

/// Phone side: sends [device] to the watch that showed [code].
Future<void> sendToWatch(PairingCode code, SavedDevice device, {Duration timeout = const Duration(seconds: 10)}) async {
  final mine = await _x25519.newKeyPair();
  final key = await _sessionKey(mine, code.watchPublicKey, code.token);
  final box = await _aead.encrypt(
    utf8.encode(jsonEncode(device.toJson())),
    secretKey: key,
    aad: utf8.encode(code.token),
  );
  final body = jsonEncode({
    'pub': _b64((await mine.extractPublicKey()).bytes),
    'nonce': _b64(box.nonce),
    'data': _b64([...box.cipherText, ...box.mac.bytes]),
  });
  // Debug builds only: Android emulators each sit behind their own NAT (10.0.2.x), so a phone
  // emulator can't reach a watch emulator's address. With the watch's port forwarded to the Mac
  // (`adb -s <watch> forward tcp:<port> tcp:<port>`), 10.0.2.2 (the Mac, as seen from an emulator)
  // reaches it. Release builds only ever use the address in the code.
  final hosts = [code.host, if (kDebugMode && code.host.startsWith('10.0.2.') && code.host != '10.0.2.2') '10.0.2.2'];
  Object? lastError;
  for (final host in hosts) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.post(host, code.port, '/pair/${code.token}').timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(body);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      if (res.statusCode != 200) throw HttpException('Watch refused the setup (${res.statusCode})');
      return;
    } on HttpException {
      rethrow; // reached the watch and it said no: don't try elsewhere
    } catch (e) {
      lastError = e;
    } finally {
      client.close(force: true);
    }
  }
  throw lastError ?? const SocketException('Watch not reachable');
}

/// Watch side: listens for one setup from a phone. [code] is what to show as a QR code;
/// [received] completes with the spa the phone sent.
class PairingListener {
  final PairingCode code;
  final Future<SavedDevice> received;
  final Future<void> Function() close;
  PairingListener._(this.code, this.received, this.close);

  static Future<PairingListener> start({Duration lifetime = const Duration(minutes: 5), String? host}) async {
    final ip = host ?? await _lanAddress();
    if (ip == null) throw const SocketException('Connect the watch to Wi-Fi to set it up from the phone');
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final mine = await _x25519.newKeyPair();
    final token = _b64(List<int>.generate(18, (_) => _rng.nextInt(256)));
    final code = PairingCode(
      host: ip,
      port: server.port,
      token: token,
      watchPublicKey: Uint8List.fromList((await mine.extractPublicKey()).bytes),
    );
    final done = Completer<SavedDevice>();
    final expiry = Timer(lifetime, () {
      if (!done.isCompleted) done.completeError(TimeoutException('Setup code expired'));
      server.close(force: true);
    });

    server.listen((req) async {
      if (done.isCompleted || req.method != 'POST' || req.uri.path != '/pair/$token') {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      try {
        final j = jsonDecode(await utf8.decodeStream(req).timeout(const Duration(seconds: 5))) as Map<String, dynamic>;
        final data = _unb64(j['data'] as String);
        final key = await _sessionKey(mine, _unb64(j['pub'] as String), token);
        final clear = await _aead.decrypt(
          SecretBox(data.sublist(0, data.length - 16), nonce: _unb64(j['nonce'] as String), mac: Mac(data.sublist(data.length - 16))),
          secretKey: key,
          aad: utf8.encode(token),
        );
        final device = SavedDevice.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        expiry.cancel();
        done.complete(device);
        await server.close();
      } catch (_) {
        // Wrong key or garbage: refuse, keep waiting for the real phone until the code expires.
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
      }
    });

    return PairingListener._(code, done.future, () async {
      expiry.cancel();
      await server.close(force: true);
    });
  }

  /// The watch's IPv4 address on the Wi-Fi network.
  static Future<String?> _lanAddress() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final addrs = [for (final i in ifaces) ...i.addresses].where((a) => !a.isLoopback && !a.isLinkLocal);
    String? pick(bool Function(InternetAddress) f) => addrs.where(f).firstOrNull?.address;
    bool private(InternetAddress a) {
      final b = a.rawAddress;
      return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168);
    }

    return pick(private) ?? pick((_) => true);
  }
}
