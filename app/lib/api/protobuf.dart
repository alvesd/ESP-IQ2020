// Minimal protobuf (proto3) wire-format encoder/decoder.
//
// The ESPHome native API only needs scalars, strings, enums and repeated scalars/strings,
// so a hand-written codec avoids a protoc/codegen step. Field numbers come from
// esphome/components/api/api.proto (see messages.dart).
import 'dart:convert';
import 'dart:typed_data';

class ProtoWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void _varint(int v) {
    // Negative int32 values are encoded as 10-byte two's complement varints.
    var value = v < 0 ? v.toUnsigned(64) : v;
    while (true) {
      final byte = value & 0x7F;
      value = value >>> 7;
      if (value == 0) {
        _b.addByte(byte);
        return;
      }
      _b.addByte(byte | 0x80);
    }
  }

  void _tag(int field, int wireType) => _varint((field << 3) | wireType);

  void uint(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _varint(value);
  }

  void int32(int field, int value) => uint(field, value);

  void boolean(int field, bool value) {
    if (!value) return;
    _tag(field, 0);
    _b.addByte(1);
  }

  void fixed32(int field, int value) {
    if (value == 0) return;
    _tag(field, 5);
    final d = ByteData(4)..setUint32(0, value, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void float32(int field, double value) {
    if (value == 0) return;
    _tag(field, 5);
    final d = ByteData(4)..setFloat32(0, value, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void string(int field, String value) {
    if (value.isEmpty) return;
    final bytes = utf8.encode(value);
    _tag(field, 2);
    _varint(bytes.length);
    _b.add(bytes);
  }

  Uint8List toBytes() => _b.toBytes();
}

/// A decoded message: field number -> list of raw values (int for varint/fixed, Uint8List for
/// length-delimited). Accessors interpret them according to the proto type.
class ProtoMessage {
  final Map<int, List<Object>> _fields;
  ProtoMessage._(this._fields);

  factory ProtoMessage.decode(Uint8List data) {
    final fields = <int, List<Object>>{};
    var pos = 0;

    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (pos >= data.length) throw const FormatException('Truncated varint');
        final b = data[pos++];
        result |= (b & 0x7F) << shift;
        if ((b & 0x80) == 0) return result;
        shift += 7;
        if (shift > 63) throw const FormatException('Varint too long');
      }
    }

    while (pos < data.length) {
      final tag = readVarint();
      final field = tag >> 3;
      final wire = tag & 7;
      Object value;
      switch (wire) {
        case 0:
          value = readVarint();
        case 1:
          if (pos + 8 > data.length) throw const FormatException('Truncated fixed64');
          value = ByteData.sublistView(data, pos, pos + 8).getUint64(0, Endian.little);
          pos += 8;
        case 2:
          final len = readVarint();
          if (pos + len > data.length) throw const FormatException('Truncated bytes');
          value = Uint8List.sublistView(data, pos, pos + len);
          pos += len;
        case 5:
          if (pos + 4 > data.length) throw const FormatException('Truncated fixed32');
          value = ByteData.sublistView(data, pos, pos + 4).getUint32(0, Endian.little);
          pos += 4;
        default:
          throw FormatException('Unsupported wire type $wire');
      }
      (fields[field] ??= <Object>[]).add(value);
    }
    return ProtoMessage._(fields);
  }

  Object? _last(int f) => _fields[f]?.last;

  int uint(int f) => (_last(f) as int?) ?? 0;
  int int32(int f) => uint(f).toSigned(32);
  bool boolean(int f) => uint(f) != 0;
  int fixed32(int f) => (_last(f) as int?) ?? 0;

  double float32(int f) {
    final raw = _last(f) as int?;
    if (raw == null) return 0;
    return (ByteData(4)..setUint32(0, raw, Endian.little)).getFloat32(0, Endian.little);
  }

  String string(int f) {
    final raw = _last(f);
    return raw is Uint8List ? utf8.decode(raw, allowMalformed: true) : '';
  }

  List<String> strings(int f) => [
        for (final v in _fields[f] ?? const <Object>[])
          if (v is Uint8List) utf8.decode(v, allowMalformed: true),
      ];

  /// Repeated enum/uint fields; accepts both packed (proto3 default) and unpacked encodings.
  List<int> uints(int f) {
    final out = <int>[];
    for (final v in _fields[f] ?? const <Object>[]) {
      if (v is int) {
        out.add(v);
      } else if (v is Uint8List) {
        var pos = 0;
        while (pos < v.length) {
          var result = 0;
          var shift = 0;
          while (true) {
            final b = v[pos++];
            result |= (b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
          }
          out.add(result);
        }
      }
    }
    return out;
  }
}
