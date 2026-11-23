// Interop check against the reference Python `noiseprotocol` 0.3.1 library (the backend that
// aioesphomeapi / Home Assistant use to talk to ESPHome). Vectors were generated with fixed
// ephemeral keys: initiator e = 0x11 * 32, responder e = 0x22 * 32, psk = bytes 0..31,
// prologue "NoiseAPIInit\0\0". c_i / c_r are each side's first transport message.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/noise.dart';

const _v = {
  'psk': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
  'm1': 'e06Qm75//kTEZaIgA31gjuNYl9Me+XLwf3SJLLD3PxPRvBo4tnk2hdx+L/346gkz',
  'm2': 'D6poTtKIZ7l/Smot7l34zpdOdrcBjj8iocTPJnhXDyBzNrlZM7Mhsa6GZz9on1yf',
  'c_i': 'CCyI1A7kKmKDUmhZRcB+OK6wtn8=',
  'c_r': '2Ug79+Z36MUHtwlyhqYtExbZXDKC3So=',
};

Uint8List _b(String k) => base64.decode(_v[k]!);

Future<SimpleKeyPair> _eph(int byte) => X25519().newKeyPairFromSeed(List<int>.filled(32, byte));

void main() {
  test('initiator matches reference noiseprotocol byte-for-byte', () async {
    final hs = NoiseHandshake.initiator(decodeNoisePsk(_v['psk']!), ephemeral: await _eph(0x11));
    expect(await hs.writeMessage1(), _b('m1'));
    final (enc, dec) = await hs.readMessage2(_b('m2'));
    expect(await enc.encrypt([0x00, 0x01, 0x00, 0x00]), _b('c_i'));
    expect(await dec.decrypt(_b('c_r')), [0x00, 0x02, 0x00, 0x03, ...utf8.encode('abc')]);
  });

  test('responder matches reference noiseprotocol byte-for-byte', () async {
    final hs = NoiseHandshake.responder(decodeNoisePsk(_v['psk']!), ephemeral: await _eph(0x22));
    await hs.readMessage1(_b('m1'));
    final (m2, enc, dec) = await hs.writeMessage2();
    expect(m2, _b('m2'));
    expect(await dec.decrypt(_b('c_i')), [0x00, 0x01, 0x00, 0x00]);
    expect(await enc.encrypt([0x00, 0x02, 0x00, 0x03, ...utf8.encode('abc')]), _b('c_r'));
  });
}
