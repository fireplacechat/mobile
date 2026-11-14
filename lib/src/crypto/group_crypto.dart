import 'dart:typed_data';

import 'package:fireplace/src/crypto/backend.dart' show openNativeGroupStore;
import 'package:fireplace_native/fireplace_crypto.dart';

/// A refused or malformed group operation. [invalid] is bad input; otherwise
/// the core refused it on protocol grounds (a forged credential, a Commit for
/// another epoch, a message it cannot decrypt).
class GroupCryptoException implements Exception {
  GroupCryptoException(this.code);
  final int code;
  bool get invalid => code == 1;
  @override
  String toString() => 'Group operation refused ($code).';
}

/// One device's MLS store (mobile decision 0050). Groups use the Rust core
/// only: there is no Dart implementation of MLS.
///
/// A changing request returns `changes` and leaves the store open until
/// [accept] or [rollback]. The caller saves the changes in between, so a crash
/// before [accept] reloads the old records and loses nothing.
class GroupCrypto {
  GroupCrypto._(this._native);

  /// Opens the store from saved records (empty for a new device).
  factory GroupCrypto.open(List<int> records) =>
      GroupCrypto._(openNativeGroupStore(records));

  final NativeGroupStore _native;

  Map<String, dynamic> call(Map<String, dynamic> request) {
    try {
      return _native.call(request);
    } on NativeCryptoException catch (e) {
      throw GroupCryptoException(e.code);
    }
  }

  void accept() => call({'op': 'accept'});
  void rollback() => call({'op': 'rollback'});
  Uint8List records() => _native.records();
  void close() => _native.close();
  bool get isClosed => _native.isClosed;
}
