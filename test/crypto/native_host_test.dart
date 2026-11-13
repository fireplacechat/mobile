import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Layout and signatures from fireplace-crypto 0.1.0's fireplace_crypto.h.
final class _FpBuf extends Struct {
  external Pointer<Uint8> ptr;

  @UintPtr()
  external int len;
}

void main() {
  test('the pinned Rust host library returns a recovery key through C', () {
    final String filename;
    final DynamicLibrary allocator;
    if (Platform.isWindows) {
      filename = 'fireplace_crypto.dll';
      allocator = DynamicLibrary.open('ucrtbase.dll');
    } else if (Platform.isLinux) {
      filename = 'libfireplace_crypto.so';
      allocator = DynamicLibrary.process();
    } else {
      throw UnsupportedError('The crypto host test needs Linux or Windows.');
    }
    final file = File('build/fireplace_crypto/host/release/$filename');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Build the pinned core with bash scripts/build_crypto_host.sh.',
    );
    final library = DynamicLibrary.open(file.absolute.path);
    // 0.1.1 is required to retain the failed-chain budget between C calls.
    for (final symbol in [
      'fp_session_load',
      'fp_session_save',
      'fp_session_destroy',
      'fp_session_encrypt_handle',
      'fp_session_decrypt_handle',
    ]) {
      expect(library.providesSymbol(symbol), isTrue, reason: symbol);
    }
    final generate = library
        .lookupFunction<
          Int32 Function(Pointer<_FpBuf>),
          int Function(Pointer<_FpBuf>)
        >('fp_recovery_generate');
    final freeBuffer = library
        .lookupFunction<
          Void Function(Pointer<Uint8>, UintPtr),
          void Function(Pointer<Uint8>, int)
        >('fp_free');
    final calloc = allocator
        .lookupFunction<
          Pointer<Void> Function(UintPtr, UintPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    final free = allocator
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final out = calloc(1, sizeOf<_FpBuf>()).cast<_FpBuf>();
    if (out == nullptr) throw StateError('Could not allocate the C output.');
    try {
      expect(generate(out), 0); // FP_OK
      expect(out.ref.ptr, isNot(nullptr));
      expect(out.ref.len, 20);
      expect(library.providesSymbol('fp_set_test_rng'), isFalse);
      expect(library.providesSymbol('fp_clear_test_rng'), isFalse);
    } finally {
      // The core wipes its key before freeing it. The C runtime owns only
      // the empty descriptor, never the key allocation.
      freeBuffer(out.ref.ptr, out.ref.len);
      free(out.cast<Void>());
    }
  });
}
