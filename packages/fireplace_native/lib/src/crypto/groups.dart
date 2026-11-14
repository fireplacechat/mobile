part of '../../fireplace_crypto.dart';

/// One device's MLS group store in the Rust core (Cargo feature `groups`,
/// mobile decision 0050). Requests and results are JSON; see the core's
/// `src/group/mod.rs`. A store can hold several megabytes, so this binding
/// allows larger buffers than the 1:1 calls.
class NativeGroupStore implements Finalizable {
  NativeGroupStore._(this._core, this._handle)
    : _finalizer = _finalizerFor(_core) {
    try {
      _finalizer.attach(this, _handle, detach: this);
    } catch (_) {
      _destroy(_handle);
      _handle = nullptr;
      rethrow;
    }
  }

  static const maxBytes = 64 * 1024 * 1024;

  final NativeCrypto _core;
  Pointer<Void> _handle;
  final NativeFinalizer _finalizer;
  static final _finalizers = <int, NativeFinalizer>{};
  static NativeFinalizer _finalizerFor(NativeCrypto core) {
    final callback = core.library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'fp_group_destroy',
        );
    return _finalizers.putIfAbsent(
      callback.address,
      () => NativeFinalizer(callback),
    );
  }

  late final _destroy = _core.library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('fp_group_destroy');
  late final _call = _core.library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint8>,
          UintPtr,
          Pointer<FpBuffer>,
        ),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<FpBuffer>)
      >('fp_group_call');
  late final _records = _core.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<FpBuffer>),
        int Function(Pointer<Void>, Pointer<FpBuffer>)
      >('fp_group_records');

  /// Runs one request. Throws [NativeCryptoException] with the core's code.
  Map<String, dynamic> call(Map<String, dynamic> request) {
    _ensureOpen();
    final bytes = NativeCrypto.jsonBytes(request);
    return _core._scope((scope) {
      final input = _input(scope, bytes);
      final out = scope.output();
      NativeCrypto._check(_call(_handle, input, bytes.length, out));
      return NativeCrypto.decodeJson(_copy(out));
    });
  }

  /// Every record, as the length-prefixed blob `fp_group_open` takes.
  Uint8List records() {
    _ensureOpen();
    return _core._scope((scope) {
      final out = scope.output();
      NativeCrypto._check(_records(_handle, out));
      return _copy(out);
    });
  }

  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    _destroy(_handle);
    _handle = nullptr;
  }

  bool get isClosed => _handle == nullptr;

  void _ensureOpen() {
    if (_handle == nullptr) throw StateError('The group store is closed.');
  }

  static Pointer<Uint8> _input(NativeScope scope, List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Group request exceeds the size limit.');
    }
    final pointer = scope.allocate(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static Uint8List _copy(Pointer<FpBuffer> output) {
    final size = output.ref.len;
    if (size == 0) return Uint8List(0);
    if (output.ref.ptr == nullptr || size > maxBytes) {
      throw StateError('Invalid group output buffer.');
    }
    return Uint8List.fromList(output.ref.ptr.asTypedList(size));
  }
}

extension NativeCryptoGroups on NativeCrypto {
  /// Opens a store from saved records (empty for a new device).
  NativeGroupStore openGroupStore(List<int> records) {
    final open = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, UintPtr, Pointer<Pointer<Void>>),
          int Function(Pointer<Uint8>, int, Pointer<Pointer<Void>>)
        >('fp_group_open');
    return _scope((scope) {
      final input = NativeGroupStore._input(scope, records);
      final handle = scope
          .allocate(sizeOf<Pointer<Void>>())
          .cast<Pointer<Void>>();
      NativeCrypto._check(open(input, records.length, handle));
      return NativeGroupStore._(this, handle.value);
    });
  }
}
