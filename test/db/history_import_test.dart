// History written as per-chat files moves into the database the first time
// each chat is used (decision 0057): everything arrives, in order; the file
// goes only after the database has it; being stopped at any point loses
// nothing.
import 'dart:convert';
import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  final opened = <SqliteMessageStore>[];
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp_import');
    secrets = MemorySecretStore();
  });
  tearDown(() async {
    for (final store in opened) {
      await store.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  final base = DateTime.utc(2026, 11, 1);
  LocalMessage message(String chat, String id, {int minute = 0}) =>
      LocalMessage(
        id: id,
        chatId: chat,
        senderUid: id.startsWith('mine') ? 'alice' : 'bob',
        senderDevice: 'd',
        outgoing: id.startsWith('mine'),
        sentAt: base.add(Duration(minutes: minute)),
        body: 'body of $id',
      );

  Future<EncryptedFileMessageStore> files() =>
      EncryptedFileMessageStore.open(dir: dir, secrets: secrets, uid: 'alice');

  /// The database, with the files behind it as the app opens it.
  Future<SqliteMessageStore> database({bool legacy = true}) async {
    final store = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      legacy: legacy ? await files() : null,
    );
    opened.add(store);
    return store;
  }

  List<File> historyFiles() => [
    for (final f in dir.listSync().whereType<File>())
      if (f.path.contains('.msgs')) f,
  ];

  String shape(Iterable<LocalMessage> messages) =>
      jsonEncode([for (final m in messages) m.toJson()]);

  /// A chat with an edit, a reaction, a message deleted here and one deleted
  /// by its author, as the file store holds them.
  Future<String> seed(EncryptedFileMessageStore store, String chat) async {
    for (var i = 0; i < 6; i++) {
      await store.add(
        message(chat, i.isEven ? 'theirs$i' : 'mine$i', minute: i),
      );
    }
    await store.add(
      LocalMessage(
        id: 'edit',
        chatId: chat,
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '',
        mutation: const MessageMutation(
          kind: MessageMutationKind.edit,
          targetId: 'theirs0',
          body: 'edited',
          revision: 1,
        ),
      ),
    );
    await store.add(
      LocalMessage(
        id: 'react',
        chatId: chat,
        senderUid: 'alice',
        senderDevice: 'd',
        outgoing: true,
        sentAt: base,
        body: '',
        mutation: const MessageMutation(
          kind: MessageMutationKind.reaction,
          targetId: 'theirs2',
          emoji: '👍',
          revision: 1,
        ),
      ),
    );
    await store.remove(chat, 'mine1');
    await store.add(
      LocalMessage(
        id: 'delete',
        chatId: chat,
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '',
        mutation: const MessageMutation(
          kind: MessageMutationKind.delete,
          targetId: 'theirs4',
        ),
      ),
    );
    return shape(await store.watch(chat).first);
  }

  test('a chat is imported whole the first time it is used, and its file '
      'removed', () async {
    final old = await files();
    final before = await seed(old, 'alice_bob');
    final other = await seed(old, 'alice_fred');
    await old.close();
    expect(historyFiles(), isNotEmpty);

    final db = await database();
    expect(shape(await db.watch('alice_bob').first), before);
    // The hidden records came too: a message deleted here stays deleted, and
    // one seen again is not stored again.
    expect(await db.has('alice_bob', 'mine1'), isTrue);
    expect(await db.get('alice_bob', 'mine1'), isNull);
    await db.add(message('alice_bob', 'mine1'));
    expect(shape(await db.watch('alice_bob').first), before);
    expect(await db.has('alice_bob', 'edit'), isTrue);
    // New messages follow the imported ones.
    await db.add(message('alice_bob', 'theirs-new', minute: 30));
    expect((await db.watch('alice_bob').first).last.id, 'theirs-new');

    // The other chat has not been used: its file is still there, untouched.
    expect(historyFiles(), hasLength(1));
    expect(shape(await db.watch('alice_fred').first), other);
    expect(historyFiles(), isEmpty);
    await db.close();
    opened.clear();

    // Nothing is imported twice.
    final again = await database();
    expect((await again.watch('alice_bob').first).last.id, 'theirs-new');
    expect(shape(await again.watch('alice_fred').first), other);
  });

  test('every way of first using a chat imports it first', () async {
    for (final (name, use)
        in <(String, Future<void> Function(SqliteMessageStore, String))>[
          ('has', (s, c) => s.has(c, 'theirs0')),
          ('get', (s, c) => s.get(c, 'theirs0')),
          ('add', (s, c) => s.add(message(c, 'theirs-new', minute: 40))),
          ('remove', (s, c) => s.remove(c, 'theirs0')),
        ]) {
      final chat = 'alice_$name';
      final old = await files();
      await seed(old, chat);
      await old.close();
      final db = await database();
      await use(db, chat);
      // The imported messages are there, whichever call came first.
      expect(await db.has(chat, 'mine3'), isTrue, reason: name);
      expect(await db.get(chat, 'mine5'), isNotNull, reason: name);
      expect(historyFiles(), isEmpty, reason: name);
      await db.close();
      opened.clear();
    }
  });

  test('clearing or deleting a chat that was never opened removes its file '
      'too', () async {
    final old = await files();
    await seed(old, 'alice_bob');
    await seed(old, 'alice_fred');
    await old.close();
    final db = await database();
    await db.deleteChat('alice_bob');
    await db.clearChat('alice_fred');
    expect(historyFiles(), isEmpty);
    expect(await db.watch('alice_bob').first, isEmpty);
    expect(await db.has('alice_bob', 'theirs0'), isFalse);
    expect(await db.watch('alice_fred').first, isEmpty);
    // Cleared, not forgotten: the markers stay.
    expect(await db.has('alice_fred', 'theirs0'), isTrue);
  });

  test('stopped after the database saved the import but before the file was '
      'removed: the file goes on the next use, and nothing doubles', () async {
    final old = await files();
    final before = await seed(old, 'alice_bob');
    await old.close();
    // Import without the files behind the store, by hand, as a run that was
    // killed right after its transaction would leave things.
    final records = await (await files()).legacyRecords('alice_bob');
    final db = await database(legacy: false);
    for (final m in records!) {
      await db.add(m);
    }
    await db.close();
    opened.clear();
    final key = base64.decode((await secrets.read('msgkey:alice'))!);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final raw = sqlite3.open('${dir.path}/${SqliteMessageStore.fileName}');
    raw.execute('PRAGMA key = "x\'$hex\'"');
    raw.execute("INSERT INTO imported (chat_id) VALUES ('alice_bob')");
    raw.close();
    expect(historyFiles(), isNotEmpty);

    final resumed = await database();
    expect(shape(await resumed.watch('alice_bob').first), before);
    expect(historyFiles(), isEmpty);
  });

  test('stopped before the import was saved: it starts again from the '
      'untouched file', () async {
    final old = await files();
    final before = await seed(old, 'alice_bob');
    await old.close();
    // Some of the chat reached the database (a message received after the
    // update, say), but the import never finished: no row says it did.
    final partial = await database(legacy: false);
    await partial.add(message('alice_bob', 'theirs-after', minute: 50));
    await partial.close();
    opened.clear();

    final db = await database();
    final all = await db.watch('alice_bob').first;
    expect(all.last.id, 'theirs-after');
    expect(shape(all.take(all.length - 1)), before);
    expect(historyFiles(), isEmpty);
  });

  test(
    'a file that cannot be read is left alone and the chat opens empty',
    () async {
      final old = await files();
      await seed(old, 'alice_bob');
      await old.close();
      final file = historyFiles().firstWhere((f) => f.path.endsWith('.msgs'));
      final bytes = file.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xff;
      file.writeAsBytesSync(bytes);
      final db = await database();
      expect(await db.watch('alice_bob').first, isEmpty);
      expect(file.existsSync(), isTrue);
      // The chat still works.
      await db.add(message('alice_bob', 'theirs-new'));
      expect((await db.watch('alice_bob').first).single.id, 'theirs-new');
    },
  );

  test(
    'a long chat with an append log is imported complete and in order',
    () async {
      final old = await files();
      for (var i = 0; i < 450; i++) {
        await old.add(message('alice_bob', 'theirs$i', minute: i));
      }
      final before = shape(await old.watch('alice_bob').first);
      await old.close();
      expect(historyFiles().any((f) => f.path.endsWith('.log')), isTrue);
      final db = await database();
      expect(shape(await db.watch('alice_bob').first), before);
      expect(historyFiles(), isEmpty);
    },
  );
}
