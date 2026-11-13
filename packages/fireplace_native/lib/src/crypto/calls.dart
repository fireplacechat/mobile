part of '../../fireplace_crypto.dart';

extension NativeCryptoCalls on NativeCrypto {
  Uint8List _binary(String symbol, List<int> a, List<int> b) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<FpBuffer>,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
            int,
            Pointer<FpBuffer>,
          )
        >(symbol);
    final out = scope.output();
    NativeCrypto._check(
      function(scope.input(a), a.length, scope.input(b), b.length, out),
    );
    return scope.copy(out);
  });

  Uint8List _ternary(String symbol, List<int> a, List<int> b, List<int> c) =>
      _scope((scope) {
        final function = library
            .lookupFunction<
              Int32 Function(
                Pointer<Uint8>,
                UintPtr,
                Pointer<Uint8>,
                UintPtr,
                Pointer<Uint8>,
                UintPtr,
                Pointer<FpBuffer>,
              ),
              int Function(
                Pointer<Uint8>,
                int,
                Pointer<Uint8>,
                int,
                Pointer<Uint8>,
                int,
                Pointer<FpBuffer>,
              )
            >(symbol);
        final out = scope.output();
        NativeCrypto._check(
          function(
            scope.input(a),
            a.length,
            scope.input(b),
            b.length,
            scope.input(c),
            c.length,
            out,
          ),
        );
        return scope.copy(out);
      });

  Uint8List _quaternary(
    String symbol,
    List<int> a,
    List<int> b,
    List<int> c,
    List<int> d,
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
            Pointer<FpBuffer>,
          )
        >(symbol);
    final out = scope.output();
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
        out,
      ),
    );
    return scope.copy(out);
  });

  Uint8List _seal(
    List<int> identity,
    List<int> uid,
    List<int> device,
    List<int> x,
    List<int> kem,
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
            Pointer<FpBuffer>,
          )
        >('fp_link_seal');
    final out = scope.output();
    NativeCrypto._check(
      function(
        scope.input(identity),
        identity.length,
        scope.input(uid),
        uid.length,
        scope.input(device),
        device.length,
        scope.input(x),
        x.length,
        scope.input(kem),
        kem.length,
        out,
      ),
    );
    return scope.copy(out);
  });

  bool _checkTwo(String symbol, List<int> a, List<int> b) => _scope((scope) {
    final function = library
        .lookupFunction<
          Int32 Function(
            Pointer<Uint8>,
            UintPtr,
            Pointer<Uint8>,
            UintPtr,
            Pointer<Int32>,
          ),
          int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Int32>)
        >(symbol);
    final out = scope.allocate(sizeOf<Int32>()).cast<Int32>();
    NativeCrypto._check(
      function(scope.input(a), a.length, scope.input(b), b.length, out),
    );
    return out.value != 0;
  });

  bool _verify(List<int> identity, List<int> message, List<int> signature) =>
      _scope((scope) {
        final function = library
            .lookupFunction<
              Int32 Function(
                Pointer<Uint8>,
                UintPtr,
                Pointer<Uint8>,
                UintPtr,
                Pointer<Uint8>,
                UintPtr,
                Pointer<Int32>,
              ),
              int Function(
                Pointer<Uint8>,
                int,
                Pointer<Uint8>,
                int,
                Pointer<Uint8>,
                int,
                Pointer<Int32>,
              )
            >('fp_identity_verify');
        final out = scope.allocate(sizeOf<Int32>()).cast<Int32>();
        NativeCrypto._check(
          function(
            scope.input(identity),
            identity.length,
            scope.input(message),
            message.length,
            scope.input(signature),
            signature.length,
            out,
          ),
        );
        return out.value != 0;
      });
}
