import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/messages.dart';
import 'package:iq2020_mobile/api/noise.dart';
import 'package:iq2020_mobile/api/protobuf.dart';

void main() {
  group('protobuf', () {
    test('round-trips scalars, strings and negative int32', () {
      final bytes = (ProtoWriter()
            ..string(1, 'jets_1')
            ..fixed32(2, 0xDEADBEEF)
            ..float32(3, 101.5)
            ..boolean(4, true)
            ..int32(5, -3)
            ..uint(6, 300))
          .toBytes();
      final m = ProtoMessage.decode(bytes);
      expect(m.string(1), 'jets_1');
      expect(m.fixed32(2), 0xDEADBEEF);
      expect(m.float32(3), 101.5);
      expect(m.boolean(4), isTrue);
      expect(m.int32(5), -3);
      expect(m.uint(6), 300);
      expect(m.string(99), '');
    });

    test('decodes packed repeated enums', () {
      // field 7, wire type 2, len 2, values [3, 6] (ClimateMode heat, auto)
      final m = ProtoMessage.decode(Uint8List.fromList([0x3A, 0x02, 0x03, 0x06]));
      expect(m.uints(7), [3, 6]);
    });

    test('parses a ListEntitiesFanResponse and FanStateResponse', () {
      final list = (ProtoWriter()
            ..string(1, 'jets_2')
            ..fixed32(2, 42)
            ..string(3, 'Jets 2')
            ..boolean(6, true)
            ..int32(8, 2))
          .toBytes();
      final info = EntityInfo.fromList(MsgId.listFan, list)!;
      expect(info.kind, EntityKind.fan);
      expect(info.fanSpeedCount, 2);
      final state = EntityState.fromState(
          MsgId.fanState, (ProtoWriter()..fixed32(1, 42)..boolean(2, true)..int32(6, 2)).toBytes())!;
      expect(state.key, 42);
      expect(state.boolValue, isTrue);
      expect(state.fanSpeedLevel, 2);
    });

    test('climate command sets has_* flags', () {
      final (type, data) = Requests.climateCommand(7, target: 102);
      expect(type, MsgId.climateCommand);
      final m = ProtoMessage.decode(data);
      expect(m.fixed32(1), 7);
      expect(m.boolean(4), isTrue);
      expect(m.float32(5), 102);
      expect(m.boolean(2), isFalse);
    });
  });

  group('noise', () {
    final psk = base64.encode(List<int>.generate(32, (i) => i));

    test('rejects malformed keys', () {
      expect(() => decodeNoisePsk('abc'), throwsFormatException);
      expect(decodeNoisePsk(psk).length, 32);
    });

    test('initiator and responder derive matching transport keys', () async {
      final key = decodeNoisePsk(psk);
      final i = NoiseHandshake.initiator(key);
      final r = NoiseHandshake.responder(key);
      final m1 = await i.writeMessage1();
      expect(m1.length, 48);
      await r.readMessage1(m1);
      final (m2, rEnc, rDec) = await r.writeMessage2();
      final (iEnc, iDec) = await i.readMessage2(m2);

      final c1 = await iEnc.encrypt(utf8.encode('hello spa'));
      expect(utf8.decode(await rDec.decrypt(c1)), 'hello spa');
      final c2 = await rEnc.encrypt(utf8.encode('102F'));
      expect(utf8.decode(await iDec.decrypt(c2)), '102F');
      // Nonces advance: a second message must also decrypt.
      final c3 = await iEnc.encrypt([1, 2, 3]);
      expect(await rDec.decrypt(c3), [1, 2, 3]);
    });

    test('wrong PSK fails the handshake', () async {
      final i = NoiseHandshake.initiator(decodeNoisePsk(psk));
      final r = NoiseHandshake.responder(Uint8List(32));
      final m1 = await i.writeMessage1();
      expect(() => r.readMessage1(m1), throwsA(anything));
    });
  });
}
