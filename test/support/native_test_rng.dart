import 'dart:ffi';
import 'dart:io';

import 'package:fireplace_native/fireplace_crypto.dart';
import 'package:fireplace_native/src/crypto/memory.dart';

NativeCrypto openTestRngCore() => NativeCrypto(
  DynamicLibrary.open(
    const String.fromEnvironment('CRYPTO_TEST_RNG_LIBRARY').isNotEmpty
        ? const String.fromEnvironment('CRYPTO_TEST_RNG_LIBRARY')
        : File(
            'build/fireplace_crypto/host-test-rng/release/${Platform.isWindows ? 'fireplace_crypto_tests.dll' : 'libfireplace_crypto_tests.so'}',
          ).absolute.path,
  ),
);

// Only test code looks up these feature-gated exports. A normal host build
// is checked independently to contain neither symbol.
void nativeTestRng(NativeCrypto core, List<int>? bytes) {
  if (bytes == null) {
    core.library.lookupFunction<Void Function(), void Function()>(
      'fp_clear_test_rng',
    )();
    return;
  }
  final scope = NativeScope(
    core.library
        .lookupFunction<Void Function(Pointer<Uint8>, UintPtr), FreeBuffer>(
          'fp_free',
        ),
  );
  try {
    final function = core.library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, UintPtr),
          int Function(Pointer<Uint8>, int)
        >('fp_set_test_rng');
    final code = function(scope.input(bytes), bytes.length);
    if (code != 0) throw NativeCryptoException(code);
  } finally {
    scope.dispose();
  }
}
