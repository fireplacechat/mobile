import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/secret_store.dart';

/// The device's MLS records (mobile decision 0050), encrypted with their own
/// account key (`groupkey:{uid}`) in one file in the account's history folder,
/// so account erasure removes it with the history.
///
/// The records are kept in memory as a map; [apply] takes the changes the core
/// returned and [save] writes the whole set atomically (a temporary file, then
/// a rename), so a crash leaves either the old records or the new ones.
class GroupRecordFile {
  GroupRecordFile._(this._file, this._key, this._aad, this._records);

  static final _aead = AesGcm.with256bits();

  final File _file;
  final SecretKey _key;
  final List<int> _aad;
  final Map<String, Uint8List> _records;

  static String keyName(String uid) => 'groupkey:$uid';

  static Future<GroupRecordFile> open({
    required Directory historyDir,
    required SecretStore secrets,
    required String uid,
  }) async {
    var raw = await secrets.read(keyName(uid));
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(keyName(uid), raw);
    }
    await historyDir.create(recursive: true);
    final file = File('${historyDir.path}/groups.bin');
    final key = SecretKey(unb64(raw));
    final aad = utf8Bytes('fireplace-groups-v1:$uid');
    final records = <String, Uint8List>{};
    if (await file.exists()) {
      final data = await file.readAsBytes();
      if (data.length < 28) {
        throw const FormatException('Group records damaged.');
      }
      final box = SecretBox(
        data.sublist(12, data.length - 16),
        nonce: data.sublist(0, 12),
        mac: Mac(data.sublist(data.length - 16)),
      );
      final plain = await _aead.decrypt(box, secretKey: key, aad: aad);
      final parts = plain.isEmpty ? const <Uint8List>[] : unlp(plain);
      if (parts.length.isOdd) {
        throw const FormatException('Group records damaged.');
      }
      for (var i = 0; i < parts.length; i += 2) {
        records[b64(parts[i])] = parts[i + 1];
      }
    }
    return GroupRecordFile._(file, key, aad, records);
  }

  /// The records in the core's blob form: `lp(key, value, ...)`, keys sorted.
  Uint8List blob() {
    final keys = _records.keys.toList()..sort();
    if (keys.isEmpty) return Uint8List(0);
    return lp([
      for (final k in keys) ...[unb64(k), _records[k]!],
    ]);
  }

  bool get isEmpty => _records.isEmpty;

  /// Applies `changes` from a core result: `[{k, v | null}]`, base64.
  void apply(Object? changes) {
    if (changes is! List) return;
    for (final c in changes) {
      final k = (c as Map)['k'] as String;
      final v = c['v'];
      if (v == null) {
        _records.remove(k);
      } else {
        _records[k] = unb64(v as String);
      }
    }
  }

  Future<void> save() async {
    final nonce = randomBytes(12);
    final box = await _aead.encrypt(
      blob(),
      secretKey: _key,
      nonce: nonce,
      aad: _aad,
    );
    final bytes = concat([nonce, box.cipherText, box.mac.bytes]);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file.path);
  }
}
