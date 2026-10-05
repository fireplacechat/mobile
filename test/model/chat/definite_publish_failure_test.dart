import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails writes whose key starts with [prefix], [times] times, like a full or locked store.
class FlakySecretStore extends MemorySecretStore {
  String? prefix;
  int times = 0;
  @override
  Future<void> write(String key, String value) async {
    if (prefix != null && key.startsWith(prefix!) && times > 0) {
      times--;
      throw StateError('secure storage unavailable');
    }
    await super.write(key, value);
  }

  void failNext(String keyPrefix, [int count = 1]) {
    prefix = keyPrefix;
    times = count;
  }
}

class Phone {
  Phone(this.db, this.uid, this.secrets, this.messages);
  final FakeFirebaseFirestore db;
  final String uid;
  final FlakySecretStore secrets;
  final MemoryMessageStore messages;
  late final KeyService keys;
  late final LocalDevice device;
  late final PreKeyService prekeys;
  late ChatService chat;
  StreamSubscription<void>? sub;
  Future<void> Function(WriteBatch)? commit;

  static Future<Phone> create(FakeFirebaseFirestore db, String uid) async {
    final p = Phone(db, uid, FlakySecretStore(), MemoryMessageStore());
    p.keys = KeyService(db, p.secrets);
    p.device = await p.keys.ensureDevice(uid);
    p.prekeys = PreKeyService(db, p.secrets);
    await p.prekeys.maintain(uid, p.device);
    p.restart();
    return p;
  }

  /// A new ChatService over the same stores, like an app restart.
  void restart() => chat = ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    prekeys: prekeys,
    secrets: secrets,
    messages: messages,
    commitBatch: (b) => (commit ?? (x) => x.commit())(b),
  );

  Future<List<String>> bodies(String chatId) async =>
      (await messages.watch(chatId).first).map((m) => m.body).toList();
  String sessKey(Phone peer) =>
      'sess:${device.keys.deviceId}:${peer.uid}:${peer.device.keys.deviceId}';
}

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 120; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('timed out: $why');
}

FirebaseException fb(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

// Review finding E1: a publish that the server definitely refused (free-plan quota used up,
// document too large, ...) escapes as a raw FirebaseException. The chat screen turns anything it
// does not recognise into "We could not confirm this send. It may have reached them", which is
// wrong (nothing was sent) and alarming (it tells the user to go and check). Definite failures
// must become a plain ChatException, with the stored ratchet put back and nothing recorded.
void main() {
  late FakeFirebaseFirestore db;
  late Phone alice, bob;
  const chatId = 'alice_bob';
  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    alice = await Phone.create(db, 'alice');
    bob = await Phone.create(db, 'bob');
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(chatId);
  });
  tearDown(() async => bob.sub?.cancel());

  for (final code in [
    'resource-exhausted',
    'invalid-argument',
    'failed-precondition',
    'unauthenticated',
  ]) {
    test(
      'a definite refusal ($code) is a plain ChatException and nothing is recorded or consumed',
      () async {
        await alice.chat.sendText(chatId, 'first');
        final key = alice.sessKey(bob);
        final before = await alice.secrets.read(key);
        alice.commit = (_) async => throw fb(code);
        await expectLater(
          alice.chat.sendText(chatId, 'refused'),
          throwsA(
            isA<ChatException>().having(
              (e) => e.message.toLowerCase(),
              'message',
              allOf(isNot(contains('may have')), contains('nothing was sent')),
            ),
          ),
        );
        expect(await alice.secrets.read(key), before);
        expect(await alice.bodies(chatId), ['first']);
      },
    );
  }
}
