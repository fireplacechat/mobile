import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/encrypted_message_store.dart';
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
  SqliteMessageStore._(
    this._db,
    this._lock,
    this._legacy,
    this._path,
    this._key,
  ) {
    _lock.onInvalidate(_reload);
  }

  /// The per-chat files this database replaces. A chat's file is imported
  /// the first time the chat is used, then removed.
  final EncryptedFileMessageStore? _legacy;
  final _ready = <String, Future<void>>{};

  static const fileName = 'history.db';
  static const schemaVersion = 2;

  final Database _db;
  final SharedLock _lock;

  /// The file and its key, for [search]'s own short-lived connection.
  final String _path;
  final List<int> _key;
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
    EncryptedFileMessageStore? legacy,
  }) async {
    final keyName = 'msgkey:$uid';
    var raw = await secrets.read(keyName);
    if (raw == null && !createKey) throw StateError('No history yet.');
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(keyName, raw);
    }
    await dir.create(recursive: true);
    final path = '${dir.path}/$fileName';
    final key = unb64(raw);
    final db = sqlite3.open(path);
    try {
      _configure(db, key);
      _migrate(db);
    } catch (_) {
      db.close();
      rethrow;
    }
    return SqliteMessageStore._(db, lock ?? SharedLock(), legacy, path, key);
  }

  /// Unlocks [db] with the history key. Fails here, with a clear error, when
  /// the key is wrong or the library is not SQLCipher (a plain SQLite would
  /// create an unencrypted file).
  static void _unlock(Database db, List<int> key) {
    if (key.length != 32) throw StateError('Bad history key.');
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // A raw key: no passphrase stretching, the key is already random.
    db.execute('PRAGMA key = "x\'$hex\'"');
    if (db.select('PRAGMA cipher_version').isEmpty) {
      throw StateError('The history database needs SQLCipher.');
    }
    db.select('SELECT count(*) FROM sqlite_master');
  }

  static void _configure(Database db, List<int> key) {
    _unlock(db, key);
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
      if (version == 1) {
        // Version 2: what kind of line a message is, for counting unread
        // ones without opening each record; and a message deleted by its
        // author is never unread.
        db.execute(
          "ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'ok'",
        );
        db.execute(
          "UPDATE messages SET status = json_extract(record, '\$.status')",
        );
        db.execute(
          'UPDATE messages SET read = 1 '
          "WHERE json_extract(record, '\$.remotelyDeleted') = 1",
        );
        db.execute('DROP INDEX messages_unread');
        db.execute(
          'CREATE INDEX messages_unread ON messages (chat_id, status) '
          'WHERE read = 0 AND visible = 1 AND outgoing = 0',
        );
        db.execute('PRAGMA user_version = $schemaVersion');
        db.execute('COMMIT');
        return;
      }
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
  -- Whether the person has seen it (issue 180). What this account sent,
  -- and what its author deleted, counts as seen.
  read INTEGER NOT NULL DEFAULT 0,
  -- LocalMessage.status: only 'ok' is a readable message.
  status TEXT NOT NULL DEFAULT 'ok',
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
        'CREATE INDEX messages_unread ON messages (chat_id, status) '
        'WHERE read = 0 AND visible = 1 AND outgoing = 0',
      );
      // Chats whose file from before the database has been imported.
      db.execute('CREATE TABLE imported (chat_id TEXT PRIMARY KEY)');
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
      m.status.name,
    ];
    // What this account sent, or what its author deleted, is not something
    // the person has yet to see.
    final seen = m.outgoing || m.remotelyDeleted ? 1 : 0;
    _db.execute(
      'UPDATE messages SET sent_at = ?, visible = ?, outgoing = ?, '
      'target_id = ?, quote_id = ?, record = ?, status = ?, '
      'read = max(read, ?) WHERE chat_id = ? AND id = ?',
      [...values, seen, m.chatId, m.id],
    );
    if (_db.updatedRows == 0) {
      _db.execute(
        'INSERT INTO messages (sent_at, visible, outgoing, target_id, '
        'quote_id, record, status, read, chat_id, id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, seen, m.chatId, m.id],
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
      final changed = changedRecords(current, next);
      for (final m in changed) {
        final old = current[m.id];
        if (old != null && !keepsContent(old, m)) erased = true;
        _put(m);
      }
      _db.execute('COMMIT');
      _updateView(chatId, current, changed);
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

  /// The conversations someone is watching, as last shown: kept in step
  /// with each change, so a new message does not read the whole
  /// conversation from the database again.
  final _views = <String, List<LocalMessage>>{};

  /// Brings a watched conversation's view up to date with [changed], the
  /// records a change just saved ([before] is how they were). Anything it
  /// cannot place exactly makes the next reader ask the database.
  void _updateView(
    String chatId,
    Map<String, LocalMessage> before,
    List<LocalMessage> changed,
  ) {
    final view = _views[chatId];
    if (view == null) return;
    for (final m in changed) {
      final at = view.indexWhere((x) => x.id == m.id);
      final old = before[m.id];
      if (at < 0) {
        if (!m.visible) continue;
        if (old != null && old.visible) {
          // Shown before, yet not in the view: the view is not to be trusted.
          _views.remove(chatId);
          return;
        }
        if (old != null) {
          // A hidden record became a shown one: its place among messages
          // with the same send time is its arrival, which the view lacks.
          _views.remove(chatId);
          return;
        }
        // New: after everything sent at the same time or earlier.
        var i = view.length;
        while (i > 0 && view[i - 1].sentAt.isAfter(m.sentAt)) {
          i--;
        }
        // Older than everything in a window that does not reach the start
        // of the conversation: it belongs before the window, not in it.
        final limit = _limits[chatId];
        if (i == 0 && limit != null && view.length >= limit) continue;
        view.insert(i, m);
      } else if (!m.visible) {
        // One fewer in a window that was full: an older message now belongs
        // in it, which only the database knows.
        final limit = _limits[chatId];
        if (limit != null && view.length >= limit) {
          _views.remove(chatId);
          return;
        }
        view.removeAt(at);
      } else if (view[at].sentAt == m.sentAt) {
        view[at] = m;
      } else {
        _views.remove(chatId);
        return;
      }
    }
  }

  /// How much of each watched conversation its watchers asked for: a number
  /// of newest messages, or null for all of it.
  final _limits = <String, int?>{};

  List<LocalMessage> _newest(String chatId, int count) => [
    for (final row in _db.select(
      'SELECT record FROM messages WHERE chat_id = ? AND visible = 1 '
      'ORDER BY sent_at DESC, seq DESC LIMIT ?',
      [chatId, count],
    ))
      _decode(row),
  ].reversed.toList();

  List<LocalMessage> _view(String chatId) {
    final limit = _limits[chatId];
    return List.unmodifiable(
      _views[chatId] ??= limit == null
          ? _visible(chatId)
          : _newest(chatId, limit),
    );
  }

  /// Widens what [chatId]'s watchers are given to [limit] (null: all).
  void _widen(String chatId, int? limit) {
    if (!_limits.containsKey(chatId)) {
      _limits[chatId] = limit;
      return;
    }
    final now = _limits[chatId];
    if (now == null || (limit != null && limit <= now)) return;
    _limits[chatId] = limit;
    _views.remove(chatId);
  }

  void _emit(String chatId) {
    final c = _ctrls[chatId];
    if (c == null || c.isClosed || !c.hasListener) {
      // Nobody is watching: do not keep the conversation in memory.
      _views.remove(chatId);
      _limits.remove(chatId);
      return;
    }
    c.add(_view(chatId));
  }

  /// Completes once [chatId]'s file from before the database, if there is
  /// one, is in the database (decision 0057). Every use of a chat waits for
  /// this, so nothing reads or writes a chat that is half moved.
  ///
  /// The whole file goes in as one transaction, with a row that says so. The
  /// file is removed only after that is saved: stopped before, the import
  /// starts again from an untouched file; stopped after, only the removal
  /// is left to do. The file's name is a hash of the chat id and its
  /// contents are sealed to it, so files are found chat by chat, as each
  /// chat is first used.
  Future<void> _imported(String chatId) {
    final legacy = _legacy;
    if (legacy == null) return Future.value();
    return _ready[chatId] ??= _lock
        .run(() async {
          final done = _db.select('SELECT 1 FROM imported WHERE chat_id = ?', [
            chatId,
          ]).isNotEmpty;
          final List<LocalMessage>? records;
          try {
            records = await legacy.legacyRecords(chatId);
          } catch (_) {
            // A file that cannot be read stays where it is; the chat starts
            // empty here, as it would have opened empty before.
            return;
          }
          if (records == null) return;
          if (!done) {
            _db.execute('BEGIN IMMEDIATE');
            try {
              for (final m in records) {
                // Anything already here is newer than the file.
                if (_row(chatId, m.id) == null) _put(m);
              }
              _db.execute('INSERT INTO imported (chat_id) VALUES (?)', [
                chatId,
              ]);
              _db.execute('COMMIT');
            } catch (_) {
              _db.execute('ROLLBACK');
              rethrow;
            }
          }
          await legacy.deleteChat(chatId);
        })
        .catchError((Object e, StackTrace st) {
          // Try again on the next use rather than remember the failure.
          _ready.remove(chatId);
          Error.throwWithStackTrace(e, st);
        });
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
    _views.clear();
    for (final chatId in _ctrls.keys.toList()) {
      if (_ctrls[chatId]!.hasListener) _emit(chatId);
    }
  }

  @override
  Future<bool> has(String chatId, String messageId) async {
    await _imported(chatId);
    return _db.select('SELECT 1 FROM messages WHERE chat_id = ? AND id = ?', [
      chatId,
      messageId,
    ]).isNotEmpty;
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async {
    await _imported(chatId);
    final m = _row(chatId, messageId);
    return m == null || m.locallyDeleted ? null : m;
  }

  @override
  Future<void> add(LocalMessage m) async {
    await _imported(m.chatId);
    return _addNow(m);
  }

  Future<void> _addNow(LocalMessage m) => _write(() {
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
  Future<void> remove(String chatId, String messageId) async {
    await _imported(chatId);
    return _removeNow(chatId, messageId);
  }

  Future<void> _removeNow(String chatId, String messageId) => _write(() {
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
  Future<void> clearChat(String chatId) async {
    await _imported(chatId);
    return _clearNow(chatId);
  }

  Future<void> _clearNow(String chatId) => _write(() {
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
    _views.remove(chatId);
    _forget();
    _emit(chatId);
  });

  @override
  Future<void> deleteChat(String chatId) async {
    await _imported(chatId);
    return _deleteNow(chatId);
  }

  Future<void> _deleteNow(String chatId) => _write(() {
    _db.execute('DELETE FROM messages WHERE chat_id = ?', [chatId]);
    _views.remove(chatId);
    _forget();
    _emit(chatId);
  });

  @override
  Future<void> markRead(String chatId, Iterable<String> messageIds) async {
    await _imported(chatId);
    final ids = messageIds.toList();
    if (ids.isEmpty) return;
    return _write(() {
      _db.execute('BEGIN IMMEDIATE');
      try {
        // In pieces: SQLite limits how many values one statement takes.
        for (var i = 0; i < ids.length; i += 400) {
          final part = ids.sublist(
            i,
            i + 400 > ids.length ? ids.length : i + 400,
          );
          _db.execute(
            'UPDATE messages SET read = 1 WHERE chat_id = ? AND read = 0 '
            'AND id IN (${List.filled(part.length, '?').join(',')})',
            [chatId, ...part],
          );
        }
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  @override
  Future<int> unreadCount(String chatId, {bool onlyOk = false}) async {
    await _imported(chatId);
    return _db.select(
          'SELECT count(*) AS n FROM messages WHERE chat_id = ? '
          'AND read = 0 AND visible = 1 AND outgoing = 0'
          "${onlyOk ? " AND status = 'ok'" : ''}",
          [chatId],
        ).first['n']
        as int;
  }

  @override
  Future<List<LocalMessage>> all(String chatId) async {
    await _imported(chatId);
    return _visible(chatId);
  }

  /// Runs on an isolate of its own, over a read-only connection of its own,
  /// so a search of a long history neither holds the UI nor reads whole
  /// conversations into memory: SQLite hands each message's text to
  /// [matches] and keeps only the newest [limit] it accepts.
  @override
  Future<List<LocalMessage>> search(
    Set<String> chatIds,
    bool Function(String body) matches, {
    int limit = 100,
  }) async {
    if (chatIds.isEmpty || limit <= 0) return const [];
    // A chat still in its file from before the database is imported first;
    // one whose file cannot be read is not searched.
    final ids = <String>[];
    for (final id in chatIds) {
      try {
        await _imported(id);
        ids.add(id);
      } catch (_) {}
    }
    if (_closed || ids.isEmpty) return const [];
    final path = _path, key = _key;
    final records = await Isolate.run(
      () => _searchFile(path, key, ids, matches, limit),
    );
    return [
      for (final record in records)
        LocalMessage.fromJson(
          Map<String, dynamic>.from(jsonDecode(record) as Map),
        ),
    ];
  }

  static List<String> _searchFile(
    String path,
    List<int> key,
    List<String> chatIds,
    bool Function(String body) matches,
    int limit,
  ) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      _unlock(db, key);
      db.execute('PRAGMA busy_timeout = 5000');
      db.createFunction(
        functionName: 'fp_matches',
        argumentCount: const AllowedArgumentCount(1),
        deterministic: true,
        function: (args) {
          final body = args[0];
          return body is String && matches(body) ? 1 : 0;
        },
      );
      final marks = List.filled(chatIds.length, '?').join(', ');
      // Readable messages only: not an edit, a reaction or a delete, not a
      // line about a group, and not one its author deleted.
      return [
        for (final row in db.select(
          'SELECT record FROM messages '
          "WHERE visible = 1 AND status = 'ok' AND chat_id IN ($marks) "
          r"AND coalesce(json_extract(record, '$.remotelyDeleted'), 0) = 0 "
          r"AND fp_matches(json_extract(record, '$.body')) "
          'ORDER BY sent_at DESC, chat_id, id LIMIT ?',
          [...chatIds, limit],
        ))
          row['record'] as String,
      ];
    } finally {
      db.close();
    }
  }

  @override
  Future<void> showOlder(String chatId, {int more = 200}) async {
    await _imported(chatId);
    final limit = _limits[chatId];
    // Fewer than asked for are shown: there is nothing older.
    if (limit == null || (_views[chatId]?.length ?? limit) < limit) return;
    _widen(chatId, limit + more);
    _emit(chatId);
  }

  @override
  Future<void> reveal(String chatId, String messageId) async {
    await _imported(chatId);
    final limit = _limits[chatId];
    if (limit == null) return;
    final target = _db.select(
      'SELECT sent_at, seq FROM messages '
      'WHERE chat_id = ? AND id = ? AND visible = 1',
      [chatId, messageId],
    );
    if (target.isEmpty) return;
    final at = target.first['sent_at'] as int, seq = target.first['seq'] as int;
    final newer =
        _db.select(
              'SELECT count(*) AS n FROM messages WHERE chat_id = ?1 '
              'AND visible = 1 AND (sent_at > ?2 OR (sent_at = ?2 AND seq >= ?3))',
              [chatId, at, seq],
            ).first['n']
            as int;
    if (newer + _revealMargin <= limit) return;
    _widen(chatId, newer + _revealMargin);
    _emit(chatId);
  }

  /// How many messages before a revealed one come with it.
  static const _revealMargin = 50;

  @override
  Stream<List<LocalMessage>> watch(String chatId, {int? newest}) {
    final c = _ctrls[chatId] ??= StreamController.broadcast();
    return Stream.multi((s) {
      var cancelled = false;
      final sub = c.stream.listen(s.add, onError: s.addError, onDone: s.close);
      final before = _limits.containsKey(chatId) ? _limits[chatId] : -1;
      _widen(chatId, newest);
      // Someone already watching is now owed more: show them.
      final widened = before != -1 && _limits[chatId] != before;
      s.onCancel = () async {
        cancelled = true;
        await sub.cancel();
        // The last watcher left: forget the window, so the conversation is
        // not kept in memory and the next watcher starts from what it asks.
        if (!c.hasListener) {
          _views.remove(chatId);
          _limits.remove(chatId);
        }
      };
      unawaited(() async {
        try {
          await _imported(chatId);
          if (cancelled || _closed) return;
          if (widened) {
            _emit(chatId);
          } else {
            s.add(_view(chatId));
          }
        } catch (error, stack) {
          if (!cancelled) s.addError(error, stack);
        }
      }());
    });
  }

  /// The connection's settings that the deletion guarantee and durability
  /// rest on, for tests.
  Map<String, Object?> get settings => {
    for (final name in ['secure_delete', 'journal_mode', 'synchronous'])
      name: _db.select('PRAGMA $name').first.values.first,
  };

  /// Wipes history and key (sign-out / "delete local data").
  Future<void> destroy(SecretStore secrets, String uid, Directory dir) async {
    await close();
    final legacy = _legacy;
    // The files' store removes the key they share; do it once.
    if (legacy != null) {
      await legacy.destroy(secrets, uid);
    } else {
      await secrets.delete('msgkey:$uid');
    }
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Drains pending writes, releases listeners and closes the file.
  Future<void> close() async {
    if (_closed) return;
    await Future.wait(_ready.values.map((f) => f.catchError((Object _) {})));
    await _writes;
    await _legacy?.close();
    _closed = true;
    for (final controller in _ctrls.values) {
      unawaited(controller.close());
    }
    _ctrls.clear();
    _views.clear();
    _db.close();
  }
}
