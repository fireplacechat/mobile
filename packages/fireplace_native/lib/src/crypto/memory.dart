import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

final class FpBuffer extends Struct {
  external Pointer<Uint8> ptr;
  @UintPtr()
  external int len;
}

typedef FreeBuffer = void Function(Pointer<Uint8>, int);

/// Each C call owns a scope. Input copies are wiped, C output allocations
/// are released by the core, and no native view escapes the call.
class NativeScope {
  NativeScope(this.freeBuffer);
  final FreeBuffer freeBuffer;
  static final _runtime = Platform.isWindows
      ? DynamicLibrary.open('ucrtbase.dll')
      : DynamicLibrary.process();
  static final _calloc = _runtime
      .lookupFunction<
        Pointer<Void> Function(UintPtr, UintPtr),
        Pointer<Void> Function(int, int)
      >('calloc');
  static final _free = _runtime
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final _allocations = <(Pointer<Uint8>, int)>[];
  final _outputs = <Pointer<FpBuffer>>[];

  Pointer<Uint8> allocate(int bytes) {
    final pointer = _calloc(1, bytes == 0 ? 1 : bytes).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Native allocation failed.');
    _allocations.add((pointer, bytes == 0 ? 1 : bytes));
    return pointer;
  }

  Pointer<Uint8> input(List<int> bytes) {
    if (bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Crypto input exceeds the size limit.');
    }
    final pointer = allocate(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<FpBuffer> output() {
    final pointer = allocate(sizeOf<FpBuffer>()).cast<FpBuffer>();
    _outputs.add(pointer);
    return pointer;
  }

  Uint8List copy(Pointer<FpBuffer> output) {
    final size = output.ref.len;
    if (size == 0) return Uint8List(0);
    if (output.ref.ptr == nullptr || size > 4 * 1024 * 1024) {
      throw StateError('Invalid crypto output buffer.');
    }
    return Uint8List.fromList(output.ref.ptr.asTypedList(size));
  }

  void dispose() {
    for (final output in _outputs) {
      freeBuffer(output.ref.ptr, output.ref.len);
    }
    for (final (pointer, size) in _allocations.reversed) {
      pointer.asTypedList(size).fillRange(0, size, 0);
      _free(pointer.cast<Void>());
    }
  }
}
