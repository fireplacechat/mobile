import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/history_log.dart'
    show changedRecords, keepsContent;
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_projection.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';

/// On-device history in one SQLCipher database per account (decision 0057).
///
/// The whole file is encrypted with the account's history key, which stays
/// in the Keychain / Keystore. Unlike the per-chat files it replaces, reading
/// part of a conversation does not read all of it, and a change touches the
/// rows it concerns, not the chat.
///
/// Behaviour is the same as [MemoryMessageStore], record for record: the same
/// projection decides what an edit, a reaction or a delete does. It is applied
/// to the few records a change can affect (see [_family]) instead of to the
/// whole conversation.
///
/// Every change runs under the account [SharedLock] and in one transaction,
/// and is durable before readers see it (decision 0013). After a change that
/// erases content the write-ahead log is emptied, and `secure_delete`
/// overwrites the freed space, so deleted text does not stay in the file.
class SqliteMessageStore implements LocalMessageStore {
  SqliteMessageStore._(this._db, this._lock) {
    _lock.onInvalidate(_reload);
  }

  static const fileName = 'history.db';
  static const schemaVersion = 1;

  final Database _db;
  final SharedLock _lock;
  final _ctrls = <String, StreamController<List<LocalMessage>>>{};
  Future<void> _writes = Future.value();
  bool _closed = false;

  /// Opens (creating if needed) the account's database in [dir]. The key is
  /// the one the history files used: `msgkey:{uid}`, 32 random bytes. With
  /// [createKey] false a missing key is an error (a background isolate must
  /// never start a new history).
  static Future<SqliteMessageStore> open({
    required Directory dir,
    required SecretStore secrets,
    required String uid,
    SharedLock? lock,
    bool createKey = true,
  }) async {
    final keyName = 'msgkey:$uid';
    var raw = await secrets.read(keyName);
    if (raw == null && !createKey) throw StateError('No history yet.');
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(keyName, raw);
    }
    await dir.create(recursive: true);
    final db = sqlite3.open('${dir.path}/$fileName');
    try {
      _configure(db, unb64(raw));
      _migrate(db);
    } catch (_) {
      db.close();
      rethrow;
    }
    return SqliteMessageStore._(db, lock ?? SharedLock());
  }

  static void _configure(Database db, List<int> key) {
    if (key.length != 32) throw StateError('Bad history key.');
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // A raw key: no passphrase stretching, the key is already random.
    db.execute('PRAGMA key = "x\'$hex\'"');
    // Fails here, with a clear error, when the key is wrong or the library is
    // not SQLCipher (a plain SQLite would create an unencrypted file).
    if (db.select('PRAGMA cipher_version').isEmpty) {
      throw StateError('The history database needs SQLCipher.');
    }
    db.select('SELECT count(*) FROM sqlite_master');
    db.execute('PRAGMA secure_delete = ON');
    db.execute('PRAGMA journal_mode = WAL');
    // Durable before the caller goes on: the ratchet key is spent by then.
    db.execute('PRAGMA synchronous = FULL');
    // The app and a background isolate each hold a connection.
    db.execute('PRAGMA busy_timeout = 5000');
  }

  static void _migrate(Database db) {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > schemaVersion) {
      throw StateError('History was written by a newer version of the app.');
    }
    if (version == schemaVersion) return;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('''
CREATE TABLE messages (
  -- Arrival order on this device; breaks ties between equal send times.
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_id TEXT NOT NULL,
  id TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  -- 1 for a message shown in the conversation; 0 for an edit, a reaction,
  -- a delete, or the marker a deleted message leaves behind.
  visible INTEGER NOT NULL,
  outgoing INTEGER NOT NULL,
  -- For an edit, a reaction or a delete: the message it changes.
  target_id TEXT,
  -- The message this one quotes.
  quote_id TEXT,
  -- Whether the person has seen it (issue 180). Set by a later step.
  read INTEGER NOT NULL DEFAULT 0,
  -- The whole record, as LocalMessage.toJson.
  record TEXT NOT NULL,
  UNIQUE (chat_id, id)
)''');
      db.execute(
        'CREATE INDEX messages_by_time '
        'ON messages (chat_id, visible, sent_at, seq)',
      );
      db.execute(
        'CREATE INDEX messages_by_target '
        'ON messages (chat_id, target_id) WHERE target_id IS NOT NULL',
      );
      db.execute(
        'CREATE INDEX messages_by_quote '
        'ON messages (chat_id, quote_id) WHERE quote_id IS NOT NULL',
      );
      db.execute(
        'CREATE INDEX messages_unread ON messages (chat_id) '
        'WHERE read = 0 AND visible = 1 AND outgoing = 0',
      );
      db.execute('PRAGMA user_version = $schemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static LocalMessage _decode(Row row) => LocalMessage.fromJson(
    Map<String, dynamic>.from(jsonDecode(row['record'] as String) as Map),
  );

  LocalMessage? _row(String chatId, String id) {
    final rows = _db.select(
      'SELECT record FROM messages WHERE chat_id = ? AND id = ?',
      [chatId, id],
    );
    return rows.isEmpty ? null : _decode(rows.first);
  }

  /// The records a change to [ids] can affect, in arrival order: each of
  /// them, the edits, reactions and deletes aimed at it, and the messages
  /// that quote it. The caller names the message a new record changes or
  /// quotes among [ids]. The projection needs nothing beyond these: it only
  /// ever alters a message through the records aimed at it, and a quote
  /// through the message it quotes. Relations are not followed further, so a
  /// long chain of replies is never walked.
  Map<String, LocalMessage> _family(String chatId, Iterable<String> ids) {
    final found = <int, LocalMessage>{};
    for (final id in ids.toSet()) {
      final rows = _db.select(
        'SELECT seq, record FROM messages WHERE chat_id = ?1 '
        'AND (id = ?2 OR target_id = ?2 OR quote_id = ?2)',
        [chatId, id],
      );
      for (final row in rows) {
        found[row['seq'] as int] = _decode(row);
      }
    }
    final order = found.keys.toList()..sort();
    return {for (final seq in order) found[seq]!.id: found[seq]!};
  }

  void _put(LocalMessage m) {
    final target = m.mutation?.targetId;
    final values = [
      m.sentAt.millisecondsSinceEpoch,
      m.visible ? 1 : 0,
      m.outgoing ? 1 : 0,
      target == null || target.isEmpty ? null : target,
      m.quote?.targetId,
      jsonEncode(m.toJson()),
      m.chatId,
      m.id,
    ];
    _db.execute(
      'UPDATE messages SET sent_at = ?, visible = ?, outgoing = ?, '
      'target_id = ?, quote_id = ?, record = ? WHERE chat_id = ? AND id = ?',
      values,
    );
    if (_db.updatedRows == 0) {
      _db.execute(
        'INSERT INTO messages (sent_at, visible, outgoing, target_id, '
        'quote_id, record, chat_id, id, read) '
        // What this account sent is not something it has yet to see.
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, m.outgoing ? 1 : 0],
      );
    }
  }

  /// Applies [change] to the family of [ids] and saves what differs, in one
  /// transaction. Returns whether any saved record lost content.
  bool _apply(
    String chatId,
    Iterable<String> ids,
    Map<String, LocalMessage> Function(Map<String, LocalMessage> family) change,
  ) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _family(chatId, ids);
      final next = projectMessageRecords(change(current));
      var erased = false;
      for (final m in changedRecords(current, next)) {
        final old = current[m.id];
        if (old != null && !keepsContent(old, m)) erased = true;
        _put(m);
      }
      _db.execute('COMMIT');
      return erased;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Empties the write-ahead log, which still holds the pages as they were
  /// before a deletion. `secure_delete` has already overwritten the freed
  /// space in the main file.
  void _forget() => _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');

  List<LocalMessage> _visible(String chatId) => [
    for (final row in _db.select(
      'SELECT record FROM messages WHERE chat_id = ? AND visible = 1 '
      'ORDER BY sent_at, seq',
      [chatId],
    ))
      _decode(row),
  ];

  void _emit(String chatId) {
    final c = _ctrls[chatId];
    if (c != null && !c.isClosed) c.add(_visible(chatId));
  }

  /// Queues [write] behind earlier ones, holding the lock (taken first, as
  /// in the file store: a receive that already holds it must not wait
  /// behind a write that waits for it).
  Future<void> _write(void Function() write) => _lock.run(() {
    final done = _writes.then((_) {
      if (_closed) throw StateError('History is closed.');
      write();
    });
    _writes = done.catchError((_) {});
    return done;
  });

  /// Another isolate wrote: show the chats someone is watching as they are.
  void _reload() {
    if (_closed) return;
    for (final chatId in _ctrls.keys.toList()) {
      if (_ctrls[chatId]!.hasListener) _emit(chatId);
    }
  }

  @override
  Future<bool> has(String chatId, String messageId) async => _db.select(
    'SELECT 1 FROM messages WHERE chat_id = ? AND id = ?',
    [chatId, messageId],
  ).isNotEmpty;

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async {
    final m = _row(chatId, messageId);
    return m == null || m.locallyDeleted ? null : m;
  }

  @override
  Future<void> add(LocalMessage m) => _write(() {
    // A deleted message stays deleted, whatever arrives under its id.
    if (_row(m.chatId, m.id)?.locallyDeleted == true) return;
    final erased = _apply(m.chatId, [
      m.id,
      ?m.mutation?.targetId,
      ?m.quote?.targetId,
    ], (family) => {...family, m.id: m});
    if (erased) _forget();
    _emit(m.chatId);
  });

  @override
  Future<void> remove(String chatId, String messageId) => _write(() {
    _apply(
      chatId,
      [messageId],
      (family) => {
        ...family,
        messageId: LocalMessage.tombstone(chatId, messageId),
      },
    );
    _forget();
    _emit(chatId);
  });

  @override
  Future<void> clearChat(String chatId) => _write(() {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final ids = [
        for (final row in _db.select(
          'SELECT id FROM messages WHERE chat_id = ?',
          [chatId],
        ))
          row['id'] as String,
      ];
      for (final id in ids) {
        _put(LocalMessage.tombstone(chatId, id));
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _forget();
    _emit(chatId);
  });

  @override
  Future<void> deleteChat(String chatId) => _write(() {
    _db.execute('DELETE FROM messages WHERE chat_id = ?', [chatId]);
    _forget();
    _emit(chatId);
  });

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
      scheduleMicrotask(() {
        if (cancelled || _closed) return;
        try {
          s.add(_visible(chatId));
        } catch (error, stack) {
          s.addError(error, stack);
        }
      });
    });
  }

  /// The connection's settings that the deletion guarantee and durability
  /// rest on, for tests.
  Map<String, Object?> get settings => {
    for (final name in ['secure_delete', 'journal_mode', 'synchronous'])
      name: _db.select('PRAGMA $name').first.values.first,
  };

  /// Drains pending writes, releases listeners and closes the file.
  Future<void> close() async {
    if (_closed) return;
    await _writes;
    _closed = true;
    for (final controller in _ctrls.values) {
      unawaited(controller.close());
    }
    _ctrls.clear();
    _db.close();
  }
}
