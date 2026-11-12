import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/local_messages.dart';

/// The append-only part of a chat's encrypted history (decision 0027).
///
/// A chat is stored as a snapshot file (all records, rewritten atomically,
/// the format used before this log existed) plus this log of records changed
/// since that snapshot. Appending one small entry instead of rewriting the
/// whole history keeps a message's save cost flat however long the chat is.
///
/// Layout: the SHA-256 of the snapshot file it extends, then entries of a
/// 4-byte big-endian length and an AES-256-GCM box (nonce, ciphertext, tag)
/// whose plaintext is a JSON list of records. Each box is bound to the chat
/// id, the snapshot hash and its position, so entries cannot be reordered,
/// moved to another chat or replayed onto another snapshot. A log whose hash
/// does not match its snapshot was left by a rewrite that stopped before
/// deleting it: everything in it is in the snapshot already, so it is
/// ignored. A last entry cut short by a crash is dropped; any other damage
/// is reported as corruption, as for the snapshot.
class HistoryLog {
  HistoryLog._(this.snapshotHash, this.entries, this.length, this.cutShort);

  /// SHA-256 of the snapshot file these entries extend.
  final List<int> snapshotHash;

  /// Entries read or written so far.
  int entries;

  /// Bytes of complete entries, header included.
  int length;

  /// The file ends in a partial entry that must be cut off before appending.
  bool cutShort;

  static const _hashLength = 32;
  static final _aead = AesGcm.with256bits();

  /// A log for a snapshot that has none yet.
  static Future<HistoryLog> fresh(List<int> snapshotBytes) async =>
      HistoryLog._(await _hash(snapshotBytes), 0, 0, false);

  /// Reads the log at [file] for the snapshot [snapshotBytes], applying its
  /// records to [into]. Returns a fresh log when there is none or it belongs
  /// to an older snapshot.
  static Future<HistoryLog> read({
    required File file,
    required List<int> snapshotBytes,
    required String chatId,
    required SecretKey key,
    required Map<String, LocalMessage> into,
  }) async {
    final hash = await _hash(snapshotBytes);
    if (!await file.exists()) return HistoryLog._(hash, 0, 0, false);
    final bytes = await file.readAsBytes();
    if (bytes.length < _hashLength ||
        !bytesEqual(bytes.sublist(0, _hashLength), hash)) {
      // Left by a rewrite that stopped before removing it: start over.
      return HistoryLog._(hash, 0, 0, bytes.isNotEmpty);
    }
    final view = ByteData.sublistView(bytes);
    var offset = _hashLength, entries = 0;
    while (offset + 4 <= bytes.length) {
      final size = view.getUint32(offset);
      if (offset + 4 + size > bytes.length) break; // cut short by a crash
      final box = SecretBox.fromConcatenation(
        bytes.sublist(offset + 4, offset + 4 + size),
        nonceLength: 12,
        macLength: 16,
      );
      final plain = await _aead.decrypt(
        box,
        secretKey: key,
        aad: _aad(chatId, hash, entries),
      );
      for (final j in jsonDecode(utf8.decode(plain)) as List) {
        final m = LocalMessage.fromJson(Map<String, dynamic>.from(j));
        into[m.id] = m;
      }
      offset += 4 + size;
      entries++;
    }
    return HistoryLog._(hash, entries, offset, offset != bytes.length);
  }

  /// Appends [records] durably (flushed before it returns). On failure the
  /// file is cut back to its last complete entry where possible; the caller
  /// rewrites the snapshot instead if that fails too ([damaged]).
  Future<void> append({
    required File file,
    required String chatId,
    required SecretKey key,
    required List<LocalMessage> records,
  }) async {
    final box = await _aead.encrypt(
      utf8Bytes(jsonEncode([for (final r in records) r.toJson()])),
      secretKey: key,
      aad: _aad(chatId, snapshotHash, entries),
    );
    final body = box.concatenation();
    final entry = Uint8List(4 + body.length);
    ByteData.sublistView(entry).setUint32(0, body.length);
    entry.setRange(4, entry.length, body);
    final raf = await file.open(mode: FileMode.append);
    try {
      if (length == 0 || cutShort) {
        await raf.truncate(length);
        await raf.setPosition(length);
      }
      if (length == 0) {
        await raf.writeFrom(snapshotHash);
        length = _hashLength;
      }
      await raf.writeFrom(entry);
      await raf.flush();
      length += entry.length;
      entries++;
      cutShort = false;
    } catch (_) {
      try {
        await raf.truncate(length);
      } catch (_) {
        damaged = true;
      }
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// A failed append could not be cut back: the next save rewrites.
  bool damaged = false;

  static Future<List<int>> _hash(List<int> bytes) async =>
      (await Sha256().hash(bytes)).bytes;

  static List<int> _aad(String chatId, List<int> hash, int index) {
    final position = Uint8List(4);
    ByteData.sublistView(position).setUint32(0, index);
    return [...utf8Bytes(chatId), 0, ...hash, ...position];
  }
}

/// Records of [next] that differ from [current]. Only these need saving.
List<LocalMessage> changedRecords(
  Map<String, LocalMessage> current,
  Map<String, LocalMessage> next,
) => [
  for (final e in next.entries)
    if (!identical(current[e.key], e.value) &&
        (current[e.key] == null ||
            jsonEncode(current[e.key]!.toJson()) !=
                jsonEncode(e.value.toJson())))
      e.value,
];

/// True when [now] still holds everything [old] held, so appending [now] and
/// keeping [old] in earlier entries reveals nothing deleted. Deletions,
/// quotes losing their text and bodies replaced without being kept as an
/// edit erase content, which only a full rewrite removes from the disk.
bool keepsContent(LocalMessage old, LocalMessage now) {
  if (now.locallyDeleted && !old.locallyDeleted) return false;
  if (now.remotelyDeleted && !old.remotelyDeleted) return false;
  String? json(Object? o) => o == null ? null : jsonEncode(o);
  if (old.quote != null &&
      json(old.quote!.toJson()) != json(now.quote?.toJson())) {
    return false;
  }
  if (old.mutation != null &&
      json(old.mutation!.toJson()) != json(now.mutation?.toJson())) {
    return false;
  }
  if (old.body != now.body &&
      now.originalBody != old.body &&
      !now.edits.values.any((e) => e.body == old.body)) {
    return false;
  }
  return true;
}
