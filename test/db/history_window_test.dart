// A long conversation is not read whole (decision 0057): watchers get its
// newest messages, older ones when asked, and a particular old message when
// one is jumped to. Whatever they are given is always the true end of the
// conversation.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late SqliteMessageStore store;
  const chat = 'alice_bob';
  final base = DateTime.utc(2026, 11, 1);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fp_window');
    store = await SqliteMessageStore.open(
      dir: dir,
      secrets: MemorySecretStore(),
      uid: 'alice',
    );
  });
  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  LocalMessage message(String id, int second, {String? body}) => LocalMessage(
    id: id,
    chatId: chat,
    senderUid: 'bob',
    senderDevice: 'd',
    outgoing: false,
    sentAt: base.add(Duration(seconds: second)),
    body: body ?? 'text $id',
  );
  Future<void> fill(int count) async {
    for (var i = 0; i < count; i++) {
      await store.add(message('m$i', i));
    }
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  List<String> ids(List<LocalMessage> l) => [for (final m in l) m.id];

  test('watchers get the newest messages, and more when they ask', () async {
    await fill(100);
    var shown = <LocalMessage>[];
    final sub = store.watch(chat, newest: 30).listen((l) => shown = l);
    addTearDown(sub.cancel);
    await settle();
    expect(ids(shown), [for (var i = 70; i < 100; i++) 'm$i']);

    // A new message joins the end.
    await store.add(message('m100', 100));
    await settle();
    expect(shown.last.id, 'm100');
    expect(shown.first.id, 'm70');

    await store.showOlder(chat, more: 30);
    await settle();
    expect(shown.first.id, 'm41');
    expect(shown.last.id, 'm100');
    await store.showOlder(chat, more: 1000);
    await settle();
    expect(shown.length, 101);
    // Everything is shown: asking again changes nothing.
    final before = shown;
    await store.showOlder(chat, more: 30);
    await settle();
    expect(identical(shown, before), isTrue);
  });

  test(
    'a jump brings an old message in, with some of what came before',
    () async {
      await fill(500);
      var shown = <LocalMessage>[];
      final sub = store.watch(chat, newest: 30).listen((l) => shown = l);
      addTearDown(sub.cancel);
      await settle();
      expect(shown.any((m) => m.id == 'm120'), isFalse);
      await store.reveal(chat, 'm120');
      await settle();
      expect(shown.any((m) => m.id == 'm120'), isTrue);
      expect(shown.first.id, 'm70');
      expect(shown.last.id, 'm499');
      // Already there, or not a message at all: nothing changes.
      final before = shown;
      await store.reveal(chat, 'm400');
      await store.reveal(chat, 'nothing');
      await settle();
      expect(identical(shown, before), isTrue);
    },
  );

  test(
    'a message older than the window does not appear at its start',
    () async {
      await fill(60);
      var shown = <LocalMessage>[];
      final sub = store.watch(chat, newest: 20).listen((l) => shown = l);
      addTearDown(sub.cancel);
      await settle();
      // Arrives now, but was sent long before the window begins.
      await store.add(message('late', -100));
      await settle();
      expect(shown.any((m) => m.id == 'late'), isFalse);
      expect(shown.first.id, 'm40');
      // It is there once the window reaches it.
      await store.showOlder(chat, more: 100);
      await settle();
      expect(shown.first.id, 'late');
    },
  );

  test('a message leaving a full window lets an older one in', () async {
    await fill(60);
    var shown = <LocalMessage>[];
    final sub = store.watch(chat, newest: 20).listen((l) => shown = l);
    addTearDown(sub.cancel);
    await settle();
    await store.remove(chat, 'm50');
    await settle();
    expect(shown.length, 20);
    expect(shown.first.id, 'm39');
    expect(shown.any((m) => m.id == 'm50'), isFalse);
  });

  test('two watchers of one chat share the wider window; all() reads '
      'everything without widening it', () async {
    await fill(80);
    var narrow = <LocalMessage>[], wide = <LocalMessage>[];
    final a = store.watch(chat, newest: 10).listen((l) => narrow = l);
    await settle();
    expect(narrow.length, 10);
    expect((await store.all(chat)).length, 80);
    await settle();
    expect(narrow.length, 10);
    final b = store.watch(chat, newest: 40).listen((l) => wide = l);
    await settle();
    expect(wide.length, 40);
    // "At least": the first watcher is given the wider one too.
    expect(narrow.length, 40);
    await a.cancel();
    await b.cancel();
    // With nobody watching, the next watcher starts from what it asks for.
    var again = <LocalMessage>[];
    final c = store.watch(chat, newest: 10).listen((l) => again = l);
    addTearDown(c.cancel);
    await settle();
    expect(again.length, 10);
  });

  for (var seed = 1; seed <= 12; seed++) {
    test('random changes: what a window shows is always the true end of '
        'the conversation, seed $seed', () async {
      final r = Random(seed);
      final reference = MemoryMessageStore();
      var shown = <LocalMessage>[];
      var limit = 25;
      final sub = store.watch(chat, newest: limit).listen((l) => shown = l);
      addTearDown(sub.cancel);
      final known = <String>[];
      // Distinct send times in no particular order: late arrivals are common.
      final times = [for (var i = 0; i < 400; i++) i]..shuffle(r);
      for (var step = 0; step < 300; step++) {
        final roll = r.nextInt(100);
        Future<void> both(Future<void> Function(LocalMessageStore) f) async {
          await f(reference);
          await f(store);
        }

        if (roll < 60 || known.isEmpty) {
          final m = message('m$step', times[step]);
          known.add(m.id);
          await both((s) => s.add(m));
        } else if (roll < 80) {
          final target = known[r.nextInt(known.length)];
          final kind = r.nextBool()
              ? MessageMutationKind.delete
              : MessageMutationKind.edit;
          final e = LocalMessage(
            id: 'e$step',
            chatId: chat,
            senderUid: 'bob',
            senderDevice: 'd',
            outgoing: false,
            sentAt: base,
            body: '',
            mutation: MessageMutation(
              kind: kind,
              targetId: target,
              body: kind == MessageMutationKind.edit ? 'edited $step' : '',
              revision: 1 + r.nextInt(3),
            ),
          );
          await both((s) => s.add(e));
        } else if (roll < 92) {
          final id = known[r.nextInt(known.length)];
          await both((s) => s.remove(chat, id));
        } else {
          final all = await reference.all(chat);
          if (shown.length >= limit && all.length > shown.length) limit += 25;
          await store.showOlder(chat, more: 25);
        }
        await settle();
        final all = await reference.all(chat);
        final expected = all.sublist(all.length - shown.length);
        expect(
          jsonEncode([for (final m in shown) m.toJson()]),
          jsonEncode([for (final m in expected) m.toJson()]),
          reason: 'seed $seed step $step: not the end of the conversation',
        );
        expect(
          shown.length >= min(limit, all.length),
          isTrue,
          reason:
              'seed $seed step $step: ${shown.length} shown, '
              'limit $limit, ${all.length} in all',
        );
      }
    });
  }
}
