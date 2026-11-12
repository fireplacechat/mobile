// The Android background push handler (decision 0030): the real receive path
// over fake Firestore, notifications into a fake.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';
import 'package:fireplace/src/model/push/background_push.dart';
import 'package:fireplace/src/model/push/push_chat_index.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_notification_poster.dart';

const _chat = 'alice_bob';

class _Account {
  _Account(this.uid, this.secrets, this.messages, this.device, this.hub);
  final String uid;
  final MemorySecretStore secrets;
  final MemoryMessageStore messages;
  final LocalDevice device;
  final MemoryLockHub hub;

  ChatService service(FakeFirebaseFirestore db) {
    final lock = SharedLock(
      gate: MemoryLockGate(hub),
      generation: hub.generation,
    );
    return ChatService(
      db: db,
      uid: uid,
      device: device,
      keys: KeyService(db, secrets),
      prekeys: PreKeyService(db, secrets, lock: lock),
      secrets: secrets,
      messages: messages,
      lock: lock,
    );
  }

  static Future<_Account> create(FakeFirebaseFirestore db, String uid) async {
    await db.collection('usernames').doc(uid).set({'uid': uid});
    await db.collection('users').doc(uid).set({'username': uid});
    final secrets = MemorySecretStore();
    final device = await KeyService(db, secrets).ensureDevice(uid);
    await PreKeyService(db, secrets).maintain(uid, device);
    return _Account(
      uid,
      secrets,
      MemoryMessageStore(),
      device,
      MemoryLockHub(),
    );
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late _Account alice, bob;
  late ChatService bobApp;
  late FakePoster poster;
  late String key;
  var opened = 0;

  setUp(() async {
    db = FakeFirebaseFirestore();
    alice = await _Account.create(db, 'alice');
    bob = await _Account.create(db, 'bob');
    bobApp = bob.service(db);
    await bobApp.startChat('alice');
    final aliceApp = alice.service(db);
    await aliceApp.acceptRequest(_chat);
    await aliceApp.close();
    await PushChatIndex(alice.secrets, 'alice').save({_chat});
    poster = FakePoster();
    key = await conversationKey(_chat);
    opened = 0;
  });
  tearDown(() => bobApp.close());

  Map<String, String> push({String title = 'bob', String ch = 'messages'}) => {
    'fp': '1',
    'k': key,
    'title': title,
    'ch': ch,
  };

  BackgroundPush handler({
    String? uid = 'alice',
    Future<BackgroundSession> Function(String uid)? open,
    Duration limit = const Duration(seconds: 8),
  }) => BackgroundPush(
    uid: uid,
    prefs: alice.secrets,
    notifier: PreviewNotifier(poster),
    limit: limit,
    fetch: const GetOptions(),
    open:
        open ??
        (uid) async {
          opened++;
          final chat = alice.service(db);
          return BackgroundSession(
            chat: chat,
            store: alice.messages,
            close: chat.close,
          );
        },
  );

  test('a message shows the sender and the text, and is saved', () async {
    await bobApp.sendText(_chat, 'See you at 9');
    await handler().handle(push());
    expect(poster.shown[key], (
      title: 'bob',
      body: 'See you at 9',
      channel: 'messages',
    ));
    final history = await alice.messages.watch(_chat).first;
    expect([for (final m in history) m.body], ['See you at 9']);
  });

  test('the title and channel come from the push', () async {
    await bobApp.sendText(_chat, 'quiet');
    await handler().handle(push(title: 'Fireplace', ch: 'messages_silent'));
    expect(poster.shown[key]?.title, 'Fireplace');
    expect(poster.shown[key]?.channel, 'messages_silent');
  });

  test('nothing new (the app got it first) posts nothing', () async {
    await bobApp.sendText(_chat, 'once');
    await handler().handle(push());
    poster.log.clear();
    await handler().handle(push());
    expect(poster.log, isEmpty);
  });

  test('a reaction to my message has its own alert', () async {
    final aliceApp = alice.service(db);
    await aliceApp.sendText(_chat, 'Dinner at eight?');
    final sent = await alice.messages.watch(_chat).first;
    await aliceApp.close();
    final bobSync = bobApp.startSync(_chat);
    for (var i = 0; i < 100; i++) {
      if ((await bob.messages.watch(_chat).first).isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await bobSync.cancel();
    await bobApp.react(_chat, sent.single.id, '❤️');
    await handler().handle(push());
    expect(
      poster.shown[reactionTag(key)]?.body,
      'Reacted ❤️ to “Dinner at eight?”',
    );
    expect(poster.shown.containsKey(key), isFalse);
  });

  test('a delete removes the alert for that message', () async {
    await bobApp.sendText(_chat, 'oops');
    await handler().handle(push());
    expect(poster.shown.containsKey(key), isTrue);
    final target = (await bob.messages.watch(_chat).first).single.id;
    await bobApp.deleteForEveryone(_chat, target);
    await handler().handle(push());
    expect(poster.shown.containsKey(key), isFalse);
    expect(poster.log.last, 'remove $key');
  });

  test('an edit gives no new alert', () async {
    await bobApp.sendText(_chat, 'helo');
    await handler().handle(push());
    final target = (await bob.messages.watch(_chat).first).single.id;
    await bobApp.editMessage(_chat, target, 'hello');
    poster.log.clear();
    await handler().handle(push());
    expect(poster.log, ['show $key hello (silent)']);
  });

  test('previews off: the plain alert, nothing decrypted or read', () async {
    await alice.secrets.write('pushnopreview:alice', '1');
    await bobApp.sendText(_chat, 'secret');
    await handler().handle(push());
    expect(poster.shown[key]?.body, 'New Message');
    expect(opened, 0);
    expect(await alice.messages.watch(_chat).first, isEmpty);
  });

  test('notifications turned off in Fireplace: nothing', () async {
    await alice.secrets.write('pushoff:alice', '1');
    await bobApp.sendText(_chat, 'hi');
    await handler().handle(push());
    expect(poster.log, isEmpty);
    expect(opened, 0);
  });

  test('a chat this device does not receive: the plain alert', () async {
    await PushChatIndex(alice.secrets, 'alice').save({});
    await bobApp.sendText(_chat, 'request?');
    await handler().handle(push());
    expect(poster.shown[key]?.body, 'New Message');
    expect(opened, 0);
  });

  test('not signed in: the plain alert', () async {
    await handler(uid: null).handle(push());
    expect(poster.shown[key]?.body, 'New Message');
  });

  test('stores that cannot open: the plain alert', () async {
    await bobApp.sendText(_chat, 'hi');
    await handler(open: (_) async => throw StateError('No history yet.'))
        .handle(push());
    expect(poster.shown[key]?.body, 'New Message');
  });

  test('past the time limit: the plain alert', () async {
    await bobApp.sendText(_chat, 'slow');
    final never = Completer<BackgroundSession>();
    await handler(
      open: (_) => never.future,
      limit: const Duration(milliseconds: 50),
    ).handle(push());
    expect(poster.shown[key]?.body, 'New Message');
  });

  test('pushes that are not ours are ignored', () async {
    await handler().handle({'type': 'rateLimitChallenge', 'challenge': 'x'});
    await handler().handle({'k': key});
    await handler().handle({'fp': '1'});
    expect(poster.log, isEmpty);
    expect(opened, 0);
  });

  test('the handler never sends', () async {
    await bobApp.sendText(_chat, 'hi');
    final before =
        (await db.collection('chats').doc(_chat).collection('messages').get())
            .size;
    await handler().handle(push());
    final after =
        (await db.collection('chats').doc(_chat).collection('messages').get())
            .size;
    expect(after, before);
  });
}
