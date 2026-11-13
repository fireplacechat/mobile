part of '../../fireplace_crypto.dart';

extension NativeCryptoSessions on NativeCrypto {
  (NativeSession, Map<String, dynamic>) initiate(
    Map<String, dynamic> local,
    Map<String, dynamic> bundle,
    Map<String, dynamic> remote,
    int now,
  ) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Int64,
            Pointer<FpBuffer>,
            Pointer<FpBuffer>,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            int,
            Pointer<FpBuffer>,
            Pointer<FpBuffer>,
          )
        >('fp_session_initiate');
    final a = NativeCrypto.jsonBytes(local),
        b = NativeCrypto.jsonBytes(bundle),
        c = NativeCrypto.jsonBytes(remote);
    final state = scope.output(), handshake = scope.output();
    NativeCrypto._check(
      function(
        scope.input(a),
        a.length,
        scope.input(b),
        b.length,
        scope.input(c),
        c.length,
        now,
        state,
        handshake,
      ),
    );
    return (
      loadSession(NativeCrypto.decodeJson(scope.copy(state))),
      NativeCrypto.decodeJson(scope.copy(handshake)),
    );
  });

  NativeSession accept(
    Map<String, dynamic> local,
    Map<String, dynamic> bundle,
    Map<String, dynamic> remote,
    Map<String, dynamic> handshake,
    Map<String, dynamic> signed,
    Map<String, dynamic>? oneTime,
    int now,
  ) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Int64,
            Pointer<FpBuffer>,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            int,
            Pointer<FpBuffer>,
          )
        >('fp_session_accept');
    final a = NativeCrypto.jsonBytes(local),
        b = NativeCrypto.jsonBytes(bundle),
        c = NativeCrypto.jsonBytes(remote);
    final d = NativeCrypto.jsonBytes(handshake),
        e = NativeCrypto.jsonBytes(signed),
        f = oneTime == null ? Uint8List(0) : NativeCrypto.jsonBytes(oneTime);
    final state = scope.output();
    NativeCrypto._check(
      function(
        scope.input(a),
        a.length,
        scope.input(b),
        b.length,
        scope.input(c),
        c.length,
        scope.input(d),
        d.length,
        scope.input(e),
        e.length,
        scope.input(f),
        f.length,
        now,
        state,
      ),
    );
    return loadSession(NativeCrypto.decodeJson(scope.copy(state)));
  });

  NativeSession loadSession(Map<String, dynamic> state) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, UintPtr, Pointer<Pointer<Void>>),
          int Function(Pointer<Uint8>, int, Pointer<Pointer<Void>>)
        >('fp_session_load');
    final bytes = NativeCrypto.jsonBytes(state);
    final slot = scope.allocate(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    NativeCrypto._check(function(scope.input(bytes), bytes.length, slot));
    if (slot.value == nullptr) throw StateError('Native session is missing.');
    return NativeSession._(this, slot.value, state);
  });
}

/// Owns exactly one Rust session. Its transient refusal budget remains in Rust;
/// only the unchanged session JSON leaves it. Closed sessions fail explicitly.
class NativeSession implements Finalizable {
  NativeSession._(this._core, this._handle, Map<String, dynamic> state)
    : _state = NativeCrypto.decodeJson(NativeCrypto.jsonBytes(state)),
      _finalizer = NativeFinalizer(
        _core.library.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'fp_session_destroy',
        ),
      ) {
    try {
      _finalizer.attach(this, _handle, detach: this);
    } catch (_) {
      _destroy(_handle);
      _handle = nullptr;
      rethrow;
    }
  }

  final NativeCrypto _core;
  Pointer<Void> _handle;
  Map<String, dynamic> _state;
  final NativeFinalizer _finalizer;
  late final _destroy = _core.library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('fp_session_destroy');

  Map<String, dynamic> toJson() {
    _ensureOpen();
    return NativeCrypto.decodeJson(NativeCrypto.jsonBytes(_state));
  }

  void _ensureOpen() {
    if (_handle == nullptr) throw StateError('Native session is closed.');
  }

  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    _destroy(_handle);
    _handle = nullptr;
    _state = {};
  }

  Map<String, dynamic> encrypt(List<int> plaintext, String chat) {
    _ensureOpen();
    return _core._scope((scope) {
      final function = _core.library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              UintPtr,
              Pointer<Uint8>,
              UintPtr,
              Pointer<FpBuffer>,
              Pointer<FpBuffer>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<FpBuffer>,
              Pointer<FpBuffer>,
            )
          >('fp_session_encrypt_handle');
      final id = utf8.encode(chat),
          state = scope.output(),
          envelope = scope.output();
      NativeCrypto._check(
        function(
          _handle,
          scope.input(id),
          id.length,
          scope.input(plaintext),
          plaintext.length,
          state,
          envelope,
        ),
      );
      _state = NativeCrypto.decodeJson(scope.copy(state));
      return NativeCrypto.decodeJson(scope.copy(envelope));
    });
  }

  Uint8List decrypt(Map<String, dynamic> envelope, String chat, {int? now}) {
    _ensureOpen();
    return _core._scope((scope) {
      final function = _core.library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              UintPtr,
              Pointer<Uint8>,
              UintPtr,
              Pointer<Int64>,
              Pointer<FpBuffer>,
              Pointer<FpBuffer>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Int64>,
              Pointer<FpBuffer>,
              Pointer<FpBuffer>,
            )
          >('fp_session_decrypt_handle');
      final id = utf8.encode(chat), bytes = NativeCrypto.jsonBytes(envelope);
      final state = scope.output(), plain = scope.output();
      final time = now == null
          ? nullptr.cast<Int64>()
          : (scope.allocate(sizeOf<Int64>()).cast<Int64>()..value = now);
      NativeCrypto._check(
        function(
          _handle,
          scope.input(bytes),
          bytes.length,
          scope.input(id),
          id.length,
          time,
          state,
          plain,
        ),
      );
      _state = NativeCrypto.decodeJson(scope.copy(state));
      return scope.copy(plain);
    });
  }
}
