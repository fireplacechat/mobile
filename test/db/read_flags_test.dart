// Whether a message has been seen is a flag on the message (issue 180), in
// the history database: counted with an index, never a growing list.
import 'dart:convert';
import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:fireplace/src/model/settings/legacy_seen.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  final opened = <SqliteMessageStore>[];
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp_read');
    secrets = MemorySecretStore();
  });
  tearDown(() async {
    for (final store in opened) {
      await store.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });
  Future<SqliteMessageStore> database({
    EncryptedFileMessageStore? legacy,
  }) async {
    final store = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      legacy: legacy,
    );
    opened.add(store);
    return store;
  }

  const chat = 'alice_bob';
  final base = DateTime.utc(2026, 11, 1);
  LocalMessage message(
    String id, {
    bool mine = false,
    MessageStatus status = MessageStatus.ok,
    String chatId = chat,
  }) => LocalMessage(
    id: id,
    chatId: chatId,
    senderUid: mine ? 'alice' : 'bob',
    senderDevice: 'd',
    outgoing: mine,
    sentAt: base,
    body: 'body of $id',
    status: status,
  );
  LocalMessage change(String id, MessageMutationKind kind, String target) =>
      LocalMessage(
        id: id,
        chatId: chat,
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '',
        mutation: MessageMutation(
          kind: kind,
          targetId: target,
          body: kind == MessageMutationKind.edit ? 'edited' : '',
          emoji: kind == MessageMutationKind.reaction ? '👍' : '',
          revision: 1,
        ),
      );

  for (final kind in ['database', 'memory']) {
    test('what counts as unread, and what marking read does ($kind)', () async {
      final LocalMessageStore store = kind == 'database'
          ? await database()
          : MemoryMessageStore();
      await store.add(message('a'));
      await store.add(message('b'));
      await store.add(message('mine', mine: true));
      await store.add(message('notice', status: MessageStatus.notice));
      await store.add(message('other', chatId: 'alice_fred'));
      // Theirs count, mine never do; a line that is not a readable message
      // counts unless only readable ones are asked for.
      expect(await store.unreadCount(chat), 3);
      expect(await store.unreadCount(chat, onlyOk: true), 2);
      expect(await store.unreadCount('alice_fred'), 1);
      expect(await store.unreadCount('alice_nobody'), 0);

      await store.markRead(chat, ['a', 'no-such-message']);
      expect(await store.unreadCount(chat), 2);
      await store.markRead(chat, ['a']); // again: no change
      expect(await store.unreadCount(chat), 2);
      expect(await store.unreadCount('alice_fred'), 1);

      // An edit or a reaction is not a new message, and does not make its
      // message unread again.
      await store.add(change('edit', MessageMutationKind.edit, 'a'));
      await store.add(change('react', MessageMutationKind.reaction, 'a'));
      expect(await store.unreadCount(chat), 2);
      // A message its author deleted is not unread.
      await store.add(change('del', MessageMutationKind.delete, 'b'));
      expect(await store.unreadCount(chat), 1);
      // Nor one removed here.
      await store.remove(chat, 'notice');
      expect(await store.unreadCount(chat), 0);
      // A new one is.
      await store.add(message('c'));
      expect(await store.unreadCount(chat), 1);
      await store.markRead(chat, [for (var i = 0; i < 1000; i++) 'x$i', 'c']);
      expect(await store.unreadCount(chat), 0);
    });
  }

  test('read state survives closing and opening', () async {
    var store = await database();
    await store.add(message('a'));
    await store.add(message('b'));
    await store.markRead(chat, ['a']);
    await store.close();
    opened.clear();
    store = await database();
    expect(await store.unreadCount(chat), 1);
  });

  test('a database from before read state had a status column is upgraded', () async {
    // Version 1, as the first database build made it.
    final probe = await database();
    await probe.close();
    opened.clear();
    final key = base64.decode((await secrets.read('msgkey:alice'))!);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final path = '${dir.path}/${SqliteMessageStore.fileName}';
    File(path).deleteSync();
    for (final extra in ['-wal', '-shm']) {
      final f = File('$path$extra');
      if (f.existsSync()) f.deleteSync();
    }
    final db = sqlite3.open(path);
    db.execute('PRAGMA key = "x\'$hex\'"');
    db.execute('''
CREATE TABLE messages (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, chat_id TEXT NOT NULL, id TEXT NOT NULL,
  sent_at INTEGER NOT NULL, visible INTEGER NOT NULL, outgoing INTEGER NOT NULL,
  target_id TEXT, quote_id TEXT, read INTEGER NOT NULL DEFAULT 0,
  record TEXT NOT NULL, UNIQUE (chat_id, id))''');
    db.execute(
      'CREATE INDEX messages_unread ON messages (chat_id) '
      'WHERE read = 0 AND visible = 1 AND outgoing = 0',
    );
    db.execute('CREATE TABLE imported (chat_id TEXT PRIMARY KEY)');
    void put(LocalMessage m) => db.execute(
      'INSERT INTO messages (chat_id, id, sent_at, visible, outgoing, record) '
      'VALUES (?, ?, ?, 1, ?, ?)',
      [m.chatId, m.id, 0, m.outgoing ? 1 : 0, jsonEncode(m.toJson())],
    );
    put(message('a'));
    put(message('notice', status: MessageStatus.notice));
    put(message('gone').copyWith(remotelyDeleted: true));
    db.execute('PRAGMA user_version = 1');
    db.close();

    final store = await database();
    expect(await store.unreadCount(chat), 2);
    expect(await store.unreadCount(chat, onlyOk: true), 1);
    expect((await store.all(chat)).length, 3);
  });

  test('seen ids from before the database become read flags, once, and '
      'leave the preferences file', () async {
    // History in the old files, and a preferences file listing what was seen.
    final files = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    for (final id in ['a', 'b', 'c']) {
      await files.add(message(id));
    }
    await files.add(message('x', chatId: 'alice_fred'));
    await files.close();
    var prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    // As an older version wrote it.
    prefs.seen[chat] = {'a', 'b', 'never-stored'};
    prefs.seen['alice_gone'] = {'z'};
    await prefs.mute('alice_fred', true);
    await prefs.close();
    final before = File('${dir.path}/chat-ui.enc').lengthSync();

    prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    expect(prefs.seen[chat], {'a', 'b', 'never-stored'});
    final store = await database(
      legacy: await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      ),
    );
    await moveLegacySeen(prefs, store);
    // The same unread messages as before: c here, x in the other chat.
    expect(await store.unreadCount(chat), 1);
    expect(await store.unreadCount('alice_fred'), 1);
    expect(prefs.seen, isEmpty);
    expect(prefs.muted, {'alice_fred'});
    expect(File('${dir.path}/chat-ui.enc').lengthSync(), lessThan(before));
    await prefs.close();

    // Nothing to do the next time, and nothing lost.
    prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    expect(prefs.seen, isEmpty);
    await moveLegacySeen(prefs, store);
    expect(await store.unreadCount(chat), 1);
    expect(prefs.muted, {'alice_fred'});
    await prefs.close();
  });

  test('the preferences file no longer grows with what is read', () async {
    final store = await database();
    final prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    await prefs.mute(chat, true);
    final size = File('${dir.path}/chat-ui.enc').lengthSync();
    for (var i = 0; i < 300; i++) {
      await store.add(message('m$i'));
    }
    await store.markRead(chat, [for (var i = 0; i < 300; i++) 'm$i']);
    expect(await store.unreadCount(chat), 0);
    await prefs.mute(chat, false);
    await prefs.mute(chat, true);
    expect(File('${dir.path}/chat-ui.enc').lengthSync(), size);
    await prefs.close();
  });
}
