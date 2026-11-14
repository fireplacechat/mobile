/// The approved Rust core's C ABI. No Dart protocol implementation lives here.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'src/crypto/memory.dart';

part 'src/crypto/calls.dart';
part 'src/crypto/sessions.dart';
part 'src/crypto/api.dart';
part 'src/crypto/groups.dart';

class NativeCryptoException implements Exception {
  const NativeCryptoException(this.code);
  final int code;
  @override
  String toString() => 'Native crypto operation failed (code $code).';
}

/// All returned byte arrays are Dart-owned copies. C allocations are released
/// even when an operation fails or output decoding throws.
class NativeCrypto {
  NativeCrypto(this.library);
  final DynamicLibrary library;
  late final FreeBuffer _free = library
      .lookupFunction<Void Function(Pointer<Uint8>, UintPtr), FreeBuffer>(
        'fp_free',
      );

  T _scope<T>(T Function(NativeScope) operation) {
    final scope = NativeScope(_free);
    try {
      return operation(scope);
    } finally {
      scope.dispose();
    }
  }

  static void _check(int code) {
    if (code != 0) throw NativeCryptoException(code);
  }

  static Uint8List jsonBytes(Map<String, dynamic> json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));
  static Map<String, dynamic> decodeJson(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  Uint8List _generate(String symbol) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(Pointer<FpBuffer>),
          int Function(Pointer<FpBuffer>)
        >(symbol);
    final out = scope.output();
    _check(function(out));
    return scope.copy(out);
  });

  Uint8List _generatePrekey(int now) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(Int64, Pointer<FpBuffer>),
          int Function(int, Pointer<FpBuffer>)
        >('fp_prekey_generate');
    final out = scope.output();
    _check(function(now, out));
    return scope.copy(out);
  });

  Uint8List _unary(String symbol, List<int> input) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, UintPtr, Pointer<FpBuffer>),
          int Function(Pointer<Uint8>, int, Pointer<FpBuffer>)
        >(symbol);
    final out = scope.output();
    _check(function(scope.input(input), input.length, out));
    return scope.copy(out);
  });

  bool _checkOne(String symbol, List<int> input) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, UintPtr, Pointer<Int32>),
          int Function(Pointer<Uint8>, int, Pointer<Int32>)
        >(symbol);
    final out = scope.allocate(sizeOf<Int32>()).cast<Int32>();
    _check(function(scope.input(input), input.length, out));
    return out.value != 0;
  });
}
