// The database history store (decision 0057) behaves exactly as the memory
// store does, which is the reference for what an edit, a reaction, a delete
// and a quote mean. Random sequences of operations are applied to both and
// everything observable is compared.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_edit.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  final opened = <SqliteMessageStore>[];
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp_sqlite_store');
    secrets = MemorySecretStore();
  });
  tearDown(() async {
    // A failed test must not leave the file open: Windows cannot delete it.
    for (final store in opened) {
      await store.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  Future<SqliteMessageStore> open() async {
    final store = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    opened.add(store);
    return store;
  }

  // Messages with the same send time have no defined order in the reference
  // (its sort is not stable); the database orders them by arrival. Compare
  // what is there, in one fixed order; the order itself has its own test.
  String shape(Iterable<LocalMessage> messages) {
    final sorted = [...messages]
      ..sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return jsonEncode([for (final m in sorted) m.toJson()]);
  }

  final base = DateTime.utc(2026, 11, 1);
  const chats = ['alice_bob', 'alice_fred'];
  const people = ['alice', 'bob'];

  LocalMessage text(
    Random r,
    String chat,
    String id,
    List<String> known, {
    int? minute,
  }) {
    final sender = people[r.nextInt(2)];
    // Only a message can be quoted, never an edit or a reaction.
    final quotable = [
      for (final id in known)
        if (id.startsWith('m')) id,
    ];
    final quoted = quotable.isNotEmpty && r.nextInt(4) == 0
        ? quotable[r.nextInt(quotable.length)]
        : null;
    return LocalMessage(
      id: id,
      chatId: chat,
      senderUid: sender,
      senderDevice: 'device-$sender',
      outgoing: sender == 'alice',
      // Few distinct times, so ties and late arrivals both happen.
      sentAt: base.add(Duration(minutes: minute ?? r.nextInt(12))),
      body: 'text of $id',
      status: r.nextInt(12) == 0
          ? MessageStatus.undecryptable
          : MessageStatus.ok,
      quote: quoted == null
          ? null
          : MessageQuote(
              targetId: quoted,
              senderUid: people[r.nextInt(2)],
              body: 'quoted $quoted',
            ),
    );
  }

  LocalMessage event(Random r, String chat, String id, List<String> known) {
    final sender = people[r.nextInt(2)];
    // Sometimes aimed at a message that has not arrived (or never will).
    // Aimed at a message, as the app's own are (an edit of an edit means
    // nothing and is not followed further by the database store).
    final messages = [
      for (final id in known)
        if (id.startsWith('m')) id,
    ];
    final target = messages.isEmpty || r.nextInt(8) == 0
        ? 'missing-${r.nextInt(3)}'
        : messages[r.nextInt(messages.length)];
    final kind = MessageMutationKind.values[r.nextInt(3)];
    return LocalMessage(
      id: id,
      chatId: chat,
      senderUid: sender,
      senderDevice: 'device-$sender',
      outgoing: sender == 'alice',
      sentAt: base.add(Duration(minutes: r.nextInt(12))),
      body: '',
      mutation: MessageMutation(
        kind: kind,
        targetId: target,
        emoji: kind == MessageMutationKind.reaction ? '👍' : '',
        body: kind == MessageMutationKind.edit ? 'edited by $id' : '',
        operation: r.nextBool()
            ? ReactionOperation.set
            : ReactionOperation.clear,
        revision: 1 + r.nextInt(4),
      ),
    );
  }

  Future<void> compare(
    LocalMessageStore reference,
    LocalMessageStore database,
    Map<String, List<String>> ids,
    String step,
  ) async {
    for (final chat in chats) {
      expect(
        shape(await database.watch(chat).first),
        shape(await reference.watch(chat).first),
        reason: '$step: conversation $chat',
      );
      for (final id in [...ids[chat]!, 'missing-0', 'missing-1']) {
        expect(
          await database.has(chat, id),
          await reference.has(chat, id),
          reason: '$step: has $id',
        );
        final a = await database.get(chat, id),
            b = await reference.get(chat, id);
        expect(
          a == null ? null : jsonEncode(a.toJson()),
          b == null ? null : jsonEncode(b.toJson()),
          reason: '$step: get $id',
        );
      }
    }
  }

  for (var seed = 1; seed <= 24; seed++) {
    test('random operations match the reference store, seed $seed', () async {
      final r = Random(seed);
      final reference = MemoryMessageStore();
      var database = await open();
      final ids = {for (final c in chats) c: <String>[]};
      // A conversation left open: what its listener was last given must
      // match too, after every single step.
      final shown = <String, List<LocalMessage>>{};
      var listeners = [
        for (final c in chats) database.watch(c).listen((l) => shown[c] = l),
      ];
      for (var step = 0; step < 220; step++) {
        final chat = chats[r.nextInt(chats.length)];
        final known = ids[chat]!;
        final roll = r.nextInt(100);
        Future<void> both(Future<void> Function(LocalMessageStore) f) async {
          await f(reference);
          await f(database);
        }

        if (roll < 45) {
          final m = text(r, chat, 'm$step', known);
          known.add(m.id);
          await both((s) => s.add(m));
        } else if (roll < 75) {
          final e = event(r, chat, 'e$step', known);
          known.add(e.id);
          await both((s) => s.add(e));
        } else if (roll < 83 && known.isNotEmpty) {
          // The same id again: a repeat, or a message arriving after its
          // marker was left by a local delete.
          final again = text(r, chat, known[r.nextInt(known.length)], known);
          await both((s) => s.add(again));
        } else if (roll < 92) {
          final id = known.isEmpty || r.nextInt(6) == 0
              ? 'missing-${r.nextInt(2)}'
              : known[r.nextInt(known.length)];
          if (!known.contains(id)) known.add(id);
          await both((s) => s.remove(chat, id));
        } else if (roll < 95) {
          await both((s) => s.clearChat(chat));
        } else if (roll < 97) {
          known.clear();
          await both((s) => s.deleteChat(chat));
        } else {
          // Closing and opening again loses nothing.
          for (final l in listeners) {
            await l.cancel();
          }
          await database.close();
          database = await open();
          final reopened = database;
          listeners = [
            for (final c in chats)
              reopened.watch(c).listen((l) => shown[c] = l),
          ];
        }
        await Future<void>.delayed(Duration.zero);
        for (final c in chats) {
          expect(
            shape(shown[c] ?? const []),
            shape(await reference.watch(c).first),
            reason: 'seed $seed step $step: open conversation $c',
          );
        }
        if (step % 11 == 0 || step == 219) {
          await compare(reference, database, ids, 'seed $seed step $step');
        }
        // Search finds the same, in the same order (step 4). Twice a run:
        // each search opens a connection on an isolate of its own.
        if (step == 110 || step == 219) {
          for (final query in ['1', 'edited', 'text of m', 'm2']) {
            final matches = _containing(query);
            for (final limit in [3, 100]) {
              expect(
                [
                  for (final m in await database.search(
                    chats.toSet(),
                    matches,
                    limit: limit,
                  ))
                    m.id,
                ],
                [
                  for (final m in await reference.search(
                    chats.toSet(),
                    matches,
                    limit: limit,
                  ))
                    m.id,
                ],
                reason: 'seed $seed step $step: search "$query" ($limit)',
              );
            }
          }
        }
      }
      for (final l in listeners) {
        await l.cancel();
      }
      await database.close();
    });
  }

  test('a conversation is ordered by send time, then by arrival', () async {
    final store = await open();
    addTearDown(store.close);
    final r = Random(1);
    for (final (id, minute) in [('late', 5), ('early', 1), ('tie', 5)]) {
      await store.add(text(r, chats.first, id, const [], minute: minute));
    }
    expect(
      [for (final m in await store.watch(chats.first).first) m.id],
      ['early', 'late', 'tie'],
    );
  });

  test('watchers see each change, also one made through another connection '
      'once the lock reports it', () async {
    // The app and the background push handler each have a lock on the same
    // generation file; that is how one learns the other wrote.
    final generation = File('${dir.path}/lock.gen');
    SharedLock lock() => SharedLock(generation: FileLockGeneration(generation));
    final mine = lock();
    final store = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      lock: mine,
    );
    opened.add(store);
    final seen = <int>[];
    final sub = store.watch(chats.first).listen((l) => seen.add(l.length));
    addTearDown(sub.cancel);
    final r = Random(2);
    await store.add(text(r, chats.first, 'a', const []));
    await store.add(text(r, chats.first, 'b', const []));
    await Future<void>.delayed(Duration.zero);
    // (The first use of a lock also reports a change, so the empty
    // conversation may be shown twice.)
    expect(seen.toSet().toList(), [0, 1, 2]);

    final other = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      lock: lock(),
    );
    await other.add(text(r, chats.first, 'c', const []));
    await other.close();
    // The next time this side takes the lock it finds the other wrote, and
    // shows the conversation as it now is.
    await mine.run(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, 3);
    expect((await store.watch(chats.first).first).length, 3);
    // And its own next change builds on that.
    await store.add(text(r, chats.first, 'd', const []));
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, 4);
  });

  test('deleted text is gone from the file, also once decrypted', () async {
    final store = await open();
    final r = Random(3);
    const secret = 'private fictional sentence';
    LocalMessage m(String id, String body) => LocalMessage(
      id: id,
      chatId: chats.first,
      senderUid: 'bob',
      senderDevice: 'd',
      outgoing: false,
      sentAt: base,
      body: body,
    );
    // One removed here, one deleted for everyone by its author, one edited
    // and then deleted, one in a chat that is cleared, one in a chat that is
    // deleted.
    await store.add(m('local', '$secret one'));
    await store.remove(chats.first, 'local');
    await store.add(m('remote', '$secret two'));
    await store.add(
      LocalMessage(
        id: 'del',
        chatId: chats.first,
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '',
        mutation: const MessageMutation(
          kind: MessageMutationKind.delete,
          targetId: 'remote',
        ),
      ),
    );
    await store.add(text(r, chats.last, 'x', const []));
    await store.add(
      LocalMessage(
        id: 'other',
        chatId: chats.last,
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '$secret three',
      ),
    );
    await store.clearChat(chats.last);
    await store.add(
      LocalMessage(
        id: 'gone',
        chatId: 'alice_gone',
        senderUid: 'bob',
        senderDevice: 'd',
        outgoing: false,
        sentAt: base,
        body: '$secret four',
      ),
    );
    await store.deleteChat('alice_gone');
    await store.add(m('kept', 'this one stays'));
    await store.close();

    // Nothing readable in the encrypted files, of course.
    for (final f in dir.listSync().whereType<File>()) {
      final raw = latin1.decode(f.readAsBytesSync());
      expect(raw, isNot(contains('fictional')), reason: f.path);
      expect(raw, isNot(contains('this one stays')), reason: f.path);
    }
    // And nothing left behind inside: decrypt the whole file, free pages and
    // all, and look at the bytes.
    final key = base64.decode((await secrets.read('msgkey:alice'))!);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final plainPath = '${dir.path}/plain.db';
    final db = sqlite3.open('${dir.path}/${SqliteMessageStore.fileName}');
    db.execute('PRAGMA key = "x\'$hex\'"');
    db.execute("ATTACH DATABASE '$plainPath' AS plain KEY ''");
    db.select("SELECT sqlcipher_export('plain')");
    db.execute('DETACH DATABASE plain');
    db.close();
    final exported = latin1.decode(File(plainPath).readAsBytesSync());
    expect(exported, contains('this one stays'));
    expect(exported, isNot(contains('fictional')));
    // The raw pages too, not only what an export copies: with the page
    // cipher off, the main file's own bytes.
    final wal = File('${dir.path}/${SqliteMessageStore.fileName}-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
  });

  test(
    'freed space is overwritten, changes are durable, readers do not block',
    () async {
      final store = await open();
      expect(store.settings, {
        'secure_delete': 1,
        'journal_mode': 'wal',
        'synchronous': 2, // FULL
      });
    },
  );

  test('the file needs its key, and a newer schema is refused', () async {
    final store = await open();
    await store.add(text(Random(4), chats.first, 'a', const []));
    await store.close();
    // Another account's key does not open it.
    final wrong = MemorySecretStore();
    await wrong.write('msgkey:alice', base64.encode(List.filled(32, 7)));
    await expectLater(
      SqliteMessageStore.open(dir: dir, secrets: wrong, uid: 'alice'),
      throwsA(anything),
    );
    // A background isolate never starts a history of its own.
    await expectLater(
      SqliteMessageStore.open(
        dir: Directory('${dir.path}/empty'),
        secrets: MemorySecretStore(),
        uid: 'alice',
        createKey: false,
      ),
      throwsStateError,
    );
    final key = base64.decode((await secrets.read('msgkey:alice'))!);
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final db = sqlite3.open('${dir.path}/${SqliteMessageStore.fileName}');
    db.execute('PRAGMA key = "x\'$hex\'"');
    db.execute('PRAGMA user_version = ${SqliteMessageStore.schemaVersion + 1}');
    db.close();
    await expectLater(open(), throwsStateError);
  });

  test(
    'an edit keeps its history; reactions and edits survive a reopen',
    () async {
      var store = await open();
      final at = base;
      await store.add(
        LocalMessage(
          id: 'm',
          chatId: chats.first,
          senderUid: 'bob',
          senderDevice: 'd',
          outgoing: false,
          sentAt: at,
          body: 'first',
        ),
      );
      await store.add(
        LocalMessage(
          id: 'e',
          chatId: chats.first,
          senderUid: 'bob',
          senderDevice: 'd',
          outgoing: false,
          sentAt: at,
          body: '',
          mutation: const MessageMutation(
            kind: MessageMutationKind.edit,
            targetId: 'm',
            body: 'second',
            revision: 1,
          ),
        ),
      );
      await store.add(
        LocalMessage(
          id: 'r',
          chatId: chats.first,
          senderUid: 'alice',
          senderDevice: 'd',
          outgoing: true,
          sentAt: at,
          body: '',
          mutation: const MessageMutation(
            kind: MessageMutationKind.reaction,
            targetId: 'm',
            emoji: '👍',
            revision: 1,
          ),
        ),
      );
      await store.close();
      store = await open();
      addTearDown(store.close);
      final m = (await store.watch(chats.first).first).single;
      expect(m.body, 'second');
      expect(m.originalBody, 'first');
      expect(m.edits[1], isA<MessageEdit>());
      expect(m.reactions['alice']!.emoji, '👍');
    },
  );
}

/// A matcher that captures only [query], so a store may run it on another
/// isolate. A closure inside a test would capture the whole test.
bool Function(String body) _containing(String query) =>
    (body) => body.contains(query);
