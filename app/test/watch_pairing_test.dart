import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/watch/watch_pairing.dart';

const spa = SavedDevice(id: 'hotspring', name: 'hotspring', host: 'hotspring.local', encryptionKey: 'dGVzdC1rZXk=');

void main() {
  test('code round trips through its QR text', () async {
    final l = await PairingListener.start(host: '127.0.0.1');
    final parsed = PairingCode.tryParse(l.code.encode())!;
    expect(parsed.host, '127.0.0.1');
    expect(parsed.port, l.code.port);
    expect(parsed.token, l.code.token);
    expect(parsed.watchPublicKey, l.code.watchPublicKey);
    await l.close();
  });

  test('rejects other QR codes', () {
    expect(PairingCode.tryParse('https://example.com'), isNull);
    expect(PairingCode.tryParse('iq2020pair:1:not-an-ip:80:abcdefghijklmnopqrstuvwx:AAAA'), isNull);
    expect(PairingCode.tryParse('iq2020pair:2:127.0.0.1:80:abcdefghijklmnopqrstuvwx:AAAA'), isNull);
  });

  test('phone sends the spa to the watch, encrypted', () async {
    final l = await PairingListener.start(host: '127.0.0.1');
    await sendToWatch(PairingCode.tryParse(l.code.encode())!, spa);
    final got = await l.received;
    expect(got.toJson(), spa.toJson());
  });

  test('wrong token or tampered data is refused and the watch keeps waiting', () async {
    final l = await PairingListener.start(host: '127.0.0.1');
    final client = HttpClient();
    Future<int> post(String path, Object body) async {
      final req = await client.post('127.0.0.1', l.code.port, path);
      req.write(jsonEncode(body));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    expect(await post('/pair/wrong-token', {}), 404);
    expect(await post('/pair/${l.code.token}', {'pub': 'AAAA', 'nonce': 'AAAA', 'data': 'AAAA'}), 403);
    // The genuine phone still succeeds afterwards.
    await sendToWatch(l.code, spa);
    expect((await l.received).host, 'hotspring.local');
    client.close(force: true);
  });

  test('a code from a different watch key cannot be decrypted', () async {
    final real = await PairingListener.start(host: '127.0.0.1');
    final other = await PairingListener.start(host: '127.0.0.1');
    // Phone encrypts for "other" but posts to the real watch's address and token.
    final forged = PairingCode(host: '127.0.0.1', port: real.code.port, token: real.code.token, watchPublicKey: other.code.watchPublicKey);
    await expectLater(sendToWatch(forged, spa), throwsA(isA<HttpException>()));
    await real.close();
    await other.close();
  });
}
