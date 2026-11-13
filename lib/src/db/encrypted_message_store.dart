import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/history_log.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_projection.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';

/// Disk-backed message history, encrypted at rest with AES-256-GCM.
/// The 256-bit key lives in the platform secure store (Keychain/Keystore);
/// the files alone reveal nothing. Per chat, a snapshot file rewritten
/// atomically plus, for longer chats, an append-only [HistoryLog] of what
/// changed since (decision 0027). Anything that erases content rewrites the
/// snapshot, so deleted text does not stay behind in the log.
///
/// Every change runs under the account [SharedLock], so the app and a
/// background isolate never write a chat at the same time. When the other
/// one wrote meanwhile, the memory caches are dropped first (decision 0030).
class EncryptedFileMessageStore implements LocalMessageStore {
  EncryptedFileMessageStore._(this._dir, this._key, this._lock) {
    _lock.onInvalidate(_reload);
  }

  /// Chats with fewer records than this are rewritten whole on every change:
  /// that is cheap at this size.
  static const appendFrom = 200;

  /// The log is folded into a new snapshot once it holds this many entries,
  /// so loading stays quick and the rewrite cost per message stays flat.
  static int compactAfter(int snapshotRecords) =>
      snapshotRecords ~/ 4 < 64 ? 64 : snapshotRecords ~/ 4;

  final Directory _dir;
  final SecretKey _key;
  final SharedLock _lock;
  static final _aead = AesGcm.with256bits();
  final Map<String, Map<String, LocalMessage>> _cache = {};
  final Map<String, HistoryLog> _logs = {};
  final Map<String, int> _snapshotRecords = {};
  final Map<String, StreamController<List<LocalMessage>>> _ctrls = {};
  Future<void> _writes = Future.value();

  static Future<EncryptedFileMessageStore> open({
    required Directory dir,
    required SecretStore secrets,
    required String uid,
    SharedLock? lock,
    bool createKey = true,
  }) async {
    final keyName = 'msgkey:$uid';
    var raw = await secrets.read(keyName);
    // The background push handler never makes the key: the app may be making
    // it at the same moment, and two keys would lose a history.
    if (raw == null && !createKey) throw StateError('No history yet.');
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(keyName, raw);
    }
    await dir.create(recursive: true);
    return EncryptedFileMessageStore._(
      dir,
      SecretKey(unb64(raw)),
      lock ?? SharedLock(),
    );
  }

  Future<File> _file(String chatId) async {
    final h = (await Sha256().hash(utf8Bytes(chatId))).bytes;
    final name = h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return File('${_dir.path}/$name.msgs');
  }

  File _logOf(File snapshot) => File('${snapshot.path}.log');

  Future<Map<String, LocalMessage>> _load(String chatId) async {
    final cached = _cache[chatId];
    if (cached != null) return cached;
    final map = <String, LocalMessage>{};
    final f = await _file(chatId);
    var snapshot = const <int>[];
    if (await f.exists()) {
      snapshot = await f.readAsBytes();
      final box = SecretBox.fromConcatenation(
        snapshot,
        nonceLength: 12,
        macLength: 16,
      );
      final plain = await _aead.decrypt(
        box,
        secretKey: _key,
        aad: utf8Bytes(chatId),
      );
      for (final j in jsonDecode(utf8.decode(plain)) as List) {
        final m = LocalMessage.fromJson(Map<String, dynamic>.from(j));
        map[m.id] = m;
      }
      _snapshotRecords[chatId] = map.length;
    }
    _logs[chatId] = await HistoryLog.read(
      file: _logOf(f),
      snapshotBytes: snapshot,
      chatId: chatId,
      key: _key,
      into: map,
    );
    return _cache[chatId] = map;
  }

  /// Saves [next], the projected history after a change to [current]: as a
  /// log entry of the changed records when that is allowed, otherwise as a
  /// new snapshot. Readers see [next] only once it is durable (decision 0013).
  Future<void> _save(
    String chatId,
    Map<String, LocalMessage> current,
    Map<String, LocalMessage> next, {
    bool rewrite = false,
  }) async {
    final changed = changedRecords(current, next);
    final log = _logs[chatId];
    final snapshotRecords = _snapshotRecords[chatId];
    final append =
        !rewrite &&
        log != null &&
        !log.damaged &&
        snapshotRecords != null &&
        current.length >= appendFrom &&
        log.entries < compactAfter(snapshotRecords) &&
        changed.every((r) {
          final old = current[r.id];
          return old == null || keepsContent(old, r);
        });
    final f = await _file(chatId);
    if (append) {
      if (changed.isNotEmpty) {
        await log.append(
          file: _logOf(f),
          chatId: chatId,
          key: _key,
          records: changed,
        );
      }
    } else {
      final box = await _aead.encrypt(
        utf8Bytes(jsonEncode([for (final x in next.values) x.toJson()])),
        secretKey: _key,
        aad: utf8Bytes(chatId),
      );
      final bytes = Uint8List.fromList(box.concatenation());
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      _snapshotRecords[chatId] = next.length;
      _logs[chatId] = await HistoryLog.fresh(bytes);
      try {
        final old = _logOf(f);
        if (await old.exists()) await old.delete();
      } catch (_) {
        // Its hash no longer matches the snapshot: it is ignored when read
        // and replaced by the next append.
      }
    }
    _cache[chatId] = next;
    _ctrls[chatId]?.add(_sorted(next));
  }

  List<LocalMessage> _sorted(Map<String, LocalMessage> m) =>
      m.values.where((m) => m.visible).toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  @override
  Future<bool> has(String chatId, String messageId) async =>
      (await _load(chatId)).containsKey(messageId);

  /// Queues [write] behind earlier ones, holding the lock. The lock is taken
  /// first: a caller that already holds it (a receive saving its message)
  /// must not wait behind a write that waits for the lock.
  Future<void> _write(Future<void> Function() write) => _lock.run(() {
    final done = _writes.then((_) => write());
    _writes = done.catchError((_) {});
    return done;
  });

  /// Another isolate wrote: read every chat from disk again, and show the
  /// chats someone is watching as they are now.
  Future<void> _reload() async {
    _cache.clear();
    _logs.clear();
    _snapshotRecords.clear();
    for (final entry in _ctrls.entries.toList()) {
      if (!entry.value.hasListener) continue;
      try {
        entry.value.add(_sorted(await _load(entry.key)));
      } catch (_) {
        // The next change to that chat shows it, or reports the damage.
      }
    }
  }

  @override
  Future<void> add(LocalMessage m) {
    return _write(() async {
      // Readers and journal replay must only observe durably committed history.
      final current = await _load(m.chatId);
      if (current[m.id]?.locallyDeleted == true) return;
      await _save(
        m.chatId,
        current,
        projectMessageRecords({...current, m.id: m}),
      );
    });
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async {
    final m = (await _load(chatId))[messageId];
    return m?.locallyDeleted == true ? null : m;
  }

  @override
  Future<void> remove(String chatId, String messageId) {
    return _write(() async {
      final current = await _load(chatId);
      // A deletion erases content: always a new snapshot, never a log entry.
      await _save(
        chatId,
        current,
        projectMessageRecords({
          ...current,
          messageId: LocalMessage.tombstone(chatId, messageId),
        }),
        rewrite: true,
      );
    });
  }

  @override
  Future<void> deleteChat(String chatId) {
    return _write(() async {
      final f = await _file(chatId);
      final log = _logOf(f);
      if (await log.exists()) await log.delete();
      if (await f.exists()) await f.delete();
      _logs.remove(chatId);
      _snapshotRecords.remove(chatId);
      _cache[chatId] = {};
      _ctrls[chatId]?.add(const []);
    });
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId) {
    final c = _ctrls[chatId] ??= StreamController.broadcast();
    return Stream.multi((s) {
      var cancelled = false;
      final sub = c.stream.listen(s.add, onError: s.addError, onDone: s.close);
      s.onCancel = () async {
        cancelled = true;
        await sub.cancel();
      };
      unawaited(() async {
        try {
          final initial = _sorted(await _load(chatId));
          if (!cancelled) s.add(initial);
        } catch (error, stack) {
          if (!cancelled) s.addError(error, stack);
        }
      }());
    });
  }

  /// Drains pending writes and releases listeners when the session ends.
  Future<void> close() async {
    await _writes;
    for (final controller in _ctrls.values) {
      unawaited(controller.close());
    }
    _ctrls.clear();
  }

  /// Wipes history and key (sign-out / "delete local data").
  Future<void> destroy(SecretStore secrets, String uid) async {
    await secrets.delete('msgkey:$uid');
    if (await _dir.exists()) await _dir.delete(recursive: true);
    _cache.clear();
  }
}
