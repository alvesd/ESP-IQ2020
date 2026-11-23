// Noise_NNpsk0_25519_ChaChaPoly_SHA256 initiator, as used by the ESPHome native API.
//
// Mirrors aioesphomeapi's NoiseHandshake (prologue "NoiseAPIInit\0\0", PSK = base64 32-byte
// api.encryption.key). Spec: https://noiseprotocol.org/noise.html
//
// Pattern NNpsk0:
//   -> psk, e        (initiator message: e.pub || AEAD tag of empty payload)
//   <- e, ee         (responder message: re.pub || AEAD tag of empty payload)
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String noiseProtocolName = 'Noise_NNpsk0_25519_ChaChaPoly_SHA256';
final Uint8List esphomeNoisePrologue =
    Uint8List.fromList([...utf8.encode('NoiseAPIInit'), 0, 0]);

final _sha256 = Sha256();
final _hmac = Hmac.sha256();
final _aead = Chacha20.poly1305Aead();
final _x25519 = X25519();

Uint8List decodeNoisePsk(String psk) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(base64.normalize(psk.trim()));
  } on FormatException {
    throw const FormatException('Encryption key must be base64');
  }
  if (bytes.length != 32) {
    throw const FormatException('Encryption key must decode to 32 bytes');
  }
  return bytes;
}

Uint8List _nonce(int n) {
  // Noise ChaChaPoly nonce: 32 bits of zeros followed by the 64-bit little-endian counter.
  final d = ByteData(12)..setUint64(4, n, Endian.little);
  return d.buffer.asUint8List();
}

Future<Uint8List> _hmacBytes(List<int> key, List<int> data) async {
  final mac = await _hmac.calculateMac(data, secretKey: SecretKey(key));
  return Uint8List.fromList(mac.bytes);
}

/// Noise HKDF with 2 or 3 outputs.
Future<List<Uint8List>> _hkdf(List<int> ck, List<int> ikm, int outputs) async {
  final tempKey = await _hmacBytes(ck, ikm);
  final o1 = await _hmacBytes(tempKey, [1]);
  final o2 = await _hmacBytes(tempKey, [...o1, 2]);
  if (outputs == 2) return [o1, o2];
  final o3 = await _hmacBytes(tempKey, [...o2, 3]);
  return [o1, o2, o3];
}

/// Transport cipher with its own nonce counter. Never share between directions.
class NoiseCipher {
  final SecretKey _key;
  int _n = 0;
  NoiseCipher(List<int> key) : _key = SecretKey(Uint8List.fromList(key));

  Future<Uint8List> encrypt(List<int> plaintext, {List<int> ad = const []}) async {
    final box = await _aead.encrypt(plaintext, secretKey: _key, nonce: _nonce(_n++), aad: ad);
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [SecretBoxAuthenticationError] on a bad tag (wrong key or corrupted frame).
  Future<Uint8List> decrypt(List<int> ciphertext, {List<int> ad = const []}) async {
    if (ciphertext.length < 16) throw const FormatException('Ciphertext shorter than tag');
    final split = ciphertext.length - 16;
    final box = SecretBox(ciphertext.sublist(0, split),
        nonce: _nonce(_n++), mac: Mac(ciphertext.sublist(split)));
    return Uint8List.fromList(await _aead.decrypt(box, secretKey: _key, aad: ad));
  }
}

/// Symmetric + handshake state for one side of an NNpsk0 handshake.
/// [NoiseHandshake.initiator] is what the app uses; the responder exists for unit tests.
class NoiseHandshake {
  final bool _initiator;
  final Uint8List _psk;
  final SimpleKeyPair? _fixedEphemeral;
  late Uint8List _h;
  late Uint8List _ck;
  NoiseCipher? _k;
  SimpleKeyPair? _e;
  Uint8List? _re;
  bool _initialized = false;

  NoiseHandshake._(this._initiator, this._psk, this._fixedEphemeral);

  factory NoiseHandshake.initiator(Uint8List psk, {SimpleKeyPair? ephemeral}) =>
      NoiseHandshake._(true, psk, ephemeral);

  factory NoiseHandshake.responder(Uint8List psk, {SimpleKeyPair? ephemeral}) =>
      NoiseHandshake._(false, psk, ephemeral);

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    final name = ascii.encode(noiseProtocolName);
    // Protocol name is longer than HASHLEN (32), so h = HASH(name).
    _h = name.length <= 32
        ? (Uint8List(32)..setAll(0, name))
        : Uint8List.fromList((await _sha256.hash(name)).bytes);
    _ck = Uint8List.fromList(_h);
    await _mixHash(esphomeNoisePrologue);
  }

  Future<void> _mixHash(List<int> data) async {
    _h = Uint8List.fromList((await _sha256.hash([..._h, ...data])).bytes);
  }

  Future<void> _mixKey(List<int> ikm) async {
    final out = await _hkdf(_ck, ikm, 2);
    _ck = out[0];
    _k = NoiseCipher(out[1]);
  }

  Future<void> _mixKeyAndHash(List<int> ikm) async {
    final out = await _hkdf(_ck, ikm, 3);
    _ck = out[0];
    await _mixHash(out[1]);
    _k = NoiseCipher(out[2]);
  }

  Future<Uint8List> _encryptAndHash(List<int> plaintext) async {
    final k = _k;
    final c = k == null ? Uint8List.fromList(plaintext) : await k.encrypt(plaintext, ad: _h);
    await _mixHash(c);
    return c;
  }

  Future<Uint8List> _decryptAndHash(List<int> ciphertext) async {
    final k = _k;
    final p = k == null ? Uint8List.fromList(ciphertext) : await k.decrypt(ciphertext, ad: _h);
    await _mixHash(ciphertext);
    return p;
  }

  Future<Uint8List> _writeEphemeral() async {
    final e = _fixedEphemeral ?? await _x25519.newKeyPair();
    _e = e;
    final pub = Uint8List.fromList((await e.extractPublicKey()).bytes);
    await _mixHash(pub);
    await _mixKey(pub); // psk handshakes mix e into the key as well
    return pub;
  }

  Future<void> _readEphemeral(List<int> pub) async {
    _re = Uint8List.fromList(pub);
    await _mixHash(pub);
    await _mixKey(pub);
  }

  Future<void> _mixDh() async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _e!,
      remotePublicKey: SimplePublicKey(_re!, type: KeyPairType.x25519),
    );
    await _mixKey(await shared.extractBytes());
  }

  /// Initiator: build message 1 (`-> psk, e`).
  Future<Uint8List> writeMessage1() async {
    assert(_initiator);
    await _init();
    await _mixKeyAndHash(_psk);
    final pub = await _writeEphemeral();
    final tag = await _encryptAndHash(const []);
    return Uint8List.fromList([...pub, ...tag]);
  }

  /// Initiator: consume message 2 (`<- e, ee`) and return the (encrypt, decrypt) ciphers.
  Future<(NoiseCipher, NoiseCipher)> readMessage2(Uint8List msg) async {
    assert(_initiator);
    if (msg.length < 32 + 16) throw const FormatException('Handshake response too short');
    await _readEphemeral(msg.sublist(0, 32));
    await _mixDh();
    await _decryptAndHash(msg.sublist(32));
    final keys = await _hkdf(_ck, const [], 2);
    return (NoiseCipher(keys[0]), NoiseCipher(keys[1]));
  }

  /// Responder (tests): consume message 1.
  Future<void> readMessage1(Uint8List msg) async {
    assert(!_initiator);
    await _init();
    await _mixKeyAndHash(_psk);
    await _readEphemeral(msg.sublist(0, 32));
    await _decryptAndHash(msg.sublist(32));
  }

  /// Responder (tests): build message 2 and return (encrypt, decrypt) ciphers.
  Future<(Uint8List, NoiseCipher, NoiseCipher)> writeMessage2() async {
    assert(!_initiator);
    final pub = await _writeEphemeral();
    await _mixDh();
    final tag = await _encryptAndHash(const []);
    final keys = await _hkdf(_ck, const [], 2);
    return (Uint8List.fromList([...pub, ...tag]), NoiseCipher(keys[1]), NoiseCipher(keys[0]));
  }
}
