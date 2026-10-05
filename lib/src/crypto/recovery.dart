import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'codec.dart';
import 'identity.dart';

/// A 160-bit random recovery key shown to the user as 9 groups of 4 characters
/// (RFC 4648 base32, 32 chars) plus a 4-char checksum to catch typos.
/// It is high-entropy, so no password stretching is needed.
class RecoveryKey {
  RecoveryKey._(this.bytes);
  final Uint8List bytes; // 20 bytes

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static RecoveryKey generate() => RecoveryKey._(randomBytes(20));

  static String _b32(List<int> data) {
    var bits = 0, value = 0;
    final out = StringBuffer();
    for (final b in data) {
      value = (value << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
      value &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(value << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List? _unb32(String s) {
    var bits = 0, value = 0;
    final out = <int>[];
    for (final c in s.codeUnits) {
      final i = _alphabet.indexOf(String.fromCharCode(c));
      if (i < 0) return null;
      value = (value << 5) | i;
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 255);
        bits -= 8;
        value &= (1 << bits) - 1;
      }
    }
    return Uint8List.fromList(out);
  }

  static Future<String> _checksum(List<int> key) async {
    final h = (await Sha256().hash(
      lp([utf8Bytes('fireplace/v1/rk-check'), key]),
    )).bytes;
    return _b32(h.sublist(0, 3)).substring(0, 4);
  }

  /// "ABCD-EFGH-..." (9 groups).
  Future<String> display() async {
    final s = _b32(bytes) + await _checksum(bytes);
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4)]
        .join('-');
  }

  /// Accepts any case, spaces or dashes. Returns null on a typo.
  static Future<RecoveryKey?> parse(String input) async {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (s.length != 36) return null;
    final data = _unb32(s.substring(0, 32));
    if (data == null || data.length < 20) return null;
    final key = Uint8List.sublistView(data, 0, 20);
    if (await _checksum(key) != s.substring(32)) return null;
    return RecoveryKey._(Uint8List.fromList(key));
  }

  Future<SecretKey> _aeadKey() =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(bytes),
        nonce: const <int>[],
        info: utf8Bytes('fireplace/v1/backup'),
      );
}

class BackupException implements Exception {
  @override
  String toString() => 'Wrong recovery key, or the backup is damaged.';
}

/// Encrypted backup of the account identity (what the server stores).
class RecoveryBackup {
  static final _aead = AesGcm.with256bits();

  static Future<String> encrypt(
    AccountIdentity identity,
    RecoveryKey key,
  ) async {
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(identity.toJson())),
      secretKey: await key._aeadKey(),
      aad: utf8Bytes('fireplace/v1/backup'),
    );
    return b64(box.concatenation());
  }

  static Future<AccountIdentity> decrypt(String blob, RecoveryKey key) async {
    try {
      final box = SecretBox.fromConcatenation(
        unb64(blob),
        nonceLength: 12,
        macLength: 16,
      );
      final plain = await _aead.decrypt(
        box,
        secretKey: await key._aeadKey(),
        aad: utf8Bytes('fireplace/v1/backup'),
      );
      return AccountIdentity.fromJson(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(plain))),
      );
    } catch (_) {
      throw BackupException();
    }
  }
}
