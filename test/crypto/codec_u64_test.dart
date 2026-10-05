import 'package:fireplace/src/crypto/codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('u64 is big-endian, 8 bytes (wire format pinned; must also work under dart2js)', () {
    expect(u64(0), [0, 0, 0, 0, 0, 0, 0, 0]);
    expect(u64(1), [0, 0, 0, 0, 0, 0, 0, 1]);
    expect(u64(258), [0, 0, 0, 0, 0, 0, 1, 2]);
    expect(u64(0xFFFFFFFF), [0, 0, 0, 0, 255, 255, 255, 255]);
    expect(u64(0x100000000), [0, 0, 0, 1, 0, 0, 0, 0]);
    expect(u64(0x123456789A), [0, 0, 0, 0x12, 0x34, 0x56, 0x78, 0x9A]);
    expect(() => u64(-1), throwsRangeError);
  });
}
