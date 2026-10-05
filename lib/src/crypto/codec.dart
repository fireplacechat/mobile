import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final _rng = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

String b64(List<int> bytes) => base64Encode(bytes);
Uint8List unb64(String s) => Uint8List.fromList(base64Decode(s));
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

/// Length-prefixed (u32 big-endian) concatenation, so transcripts are unambiguous.
Uint8List lp(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add((ByteData(4)..setUint32(0, p.length)).buffer.asUint8List());
    out.add(p);
  }
  return out.toBytes();
}

List<Uint8List> unlp(List<int> data) {
  final bytes = Uint8List.fromList(data);
  final view = ByteData.sublistView(bytes);
  final parts = <Uint8List>[];
  var i = 0;
  while (i < bytes.length) {
    if (i + 4 > bytes.length) throw const FormatException('truncated length');
    final len = view.getUint32(i);
    i += 4;
    if (i + len > bytes.length) throw const FormatException('truncated field');
    parts.add(Uint8List.sublistView(bytes, i, i + len));
    i += len;
  }
  return parts;
}

/// Big-endian 64-bit encoding. Written as two 32-bit halves because `ByteData.setUint64`
/// is not supported when compiled to JavaScript (the browser build). Counters are far below
/// 2^53, so the split is exact.
Uint8List u64(int n) {
  if (n < 0) throw RangeError.value(n, 'n', 'must not be negative');
  return (ByteData(8)
        ..setUint32(0, (n ~/ 0x100000000) & 0xFFFFFFFF)
        ..setUint32(4, n & 0xFFFFFFFF))
      .buffer
      .asUint8List();
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
