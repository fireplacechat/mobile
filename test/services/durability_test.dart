import 'dart:async';
import 'dart:convert';

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

  group('M-1 send side', () {
    test('a definite publish failure puts the stored ratchet back, so nothing is skipped', () async {
      await alice.chat.sendText(chatId, 'first'); // creates the session
      final key = alice.sessKey(bob);
      final before = await alice.secrets.read(key);
      alice.commit = (_) async => throw fb('permission-denied');
      await expectLater(
        alice.chat.sendText(chatId, 'denied'),
        throwsA(isA<ChatException>()),
      );
      expect(await alice.secrets.read(key), before);
      alice.commit = null;
      await alice.chat.sendText(chatId, 'second');
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('second'),
        'delivered',
      );
      expect(await bob.bodies(chatId), ['first', 'second']);
    });

    test('an ambiguous failure (network lost) keeps the advanced state: a counter gap, never a reuse', () async {
      await alice.chat.sendText(chatId, 'first');
      final key = alice.sessKey(bob);
      final before = await alice.secrets.read(key);
      alice.commit = (_) async => throw fb('unavailable');
      await expectLater(
        alice.chat.sendText(chatId, 'maybe sent'),
        throwsA(
          isA<SendNotConfirmedException>().having(
            (e) => e.outcome,
            'outcome',
            SendOutcome.publishUnknown,
          ),
        ),
      );
      final after = await alice.secrets.read(key);
      expect(after, isNot(before), reason: 'the counter was consumed');
      alice.commit = null;
      await alice.chat.sendText(chatId, 'next');
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('next'),
        'delivered across the gap',
      );
      // the lost message was never published, the rest arrived in order
      expect((await bob.bodies(chatId)).where((b) => b != 'first'), ['next']);
    });

    test(
      'if saving the ratchet fails nothing is published and nothing changes',
      () async {
        await alice.chat.sendText(chatId, 'first');
        final key = alice.sessKey(bob);
        final before = await alice.secrets.read(key);
        final published =
            (await db.collection('chats/$chatId/messages').get()).docs.length;
        alice.secrets.failNext('sess:');
        await expectLater(
          alice.chat.sendText(chatId, 'x'),
          throwsA(isA<StateError>()),
        );
        expect(
          (await db.collection('chats/$chatId/messages').get()).docs.length,
          published,
        );
        expect(await alice.secrets.read(key), before);
        await alice.chat.sendText(chatId, 'works again');
        bob.sub = bob.chat.startSync(chatId);
        await eventually(
          () async => (await bob.bodies(chatId)).contains('works again'),
          'delivered',
        );
      },
    );

    test(
      'a message is never encrypted twice at the same counter, whatever fails',
      () async {
        final counters = <int>[];
        await alice.chat.sendText(chatId, 'a');
        for (final failure in [
          fb('unavailable'),
          fb('permission-denied'),
          fb('unavailable'),
        ]) {
          alice.commit = (_) async => throw failure;
          await alice.chat.sendText(chatId, 'b').then((_) {}, onError: (_) {});
        }
        alice.commit = null;
        await alice.chat.sendText(chatId, 'c');
        final docs = (await db.collection('chats/$chatId/messages').get()).docs;
        for (final d in docs) {
          final env = (d.data()['envelopes'] as Map).values.first as Map;
          counters.add(env['n'] as int);
        }
        expect(
          counters.toSet().length,
          counters.length,
          reason: 'counters: $counters',
        );
      },
    );
  });

  group('M-1 / M-2 receive side', () {
    Future<void> sendTwo() async {
      await alice.chat.sendText(chatId, 'm1');
      await alice.chat.sendText(chatId, 'm2');
    }

    test('history saved but the session write fails: the next run completes it, no duplicate, no lost message', () async {
      await sendTwo();
      bob.secrets.failNext(
        'sess:',
      ); // first session save fails after the history entry exists
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).length == 2,
        'both messages arrive',
      );
      expect(await bob.bodies(chatId), ['m1', 'm2']);
      // a third message still decrypts: the checkpoint was completed before it
      await alice.chat.sendText(chatId, 'm3');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('m3'),
        'm3',
      );
      expect(await bob.bodies(chatId), ['m1', 'm2', 'm3']);
      expect(
        jsonDecode(
          (await bob.secrets.read('journals:${bob.device.keys.deviceId}')) ??
              '[]',
        ),
        isEmpty,
      );
    });

    test('after an app restart the half-applied message is completed before anything else', () async {
      await alice.chat.sendText(chatId, 'm1');
      bob.secrets.failNext(
        'sess:',
        99,
      ); // persistent trouble: the app "crashes" with the journal pending
      bob.sub = bob.chat.startSync(chatId);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await bob.sub?.cancel();
      expect(await bob.bodies(chatId), ['m1'], reason: 'history was written');
      expect(
        jsonDecode(
          (await bob.secrets.read('journals:${bob.device.keys.deviceId}'))!,
        ),
        isNotEmpty,
      );

      bob.secrets.times = 0; // storage is fine again after the restart
      bob.restart();
      await alice.chat.sendText(chatId, 'm2');
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('m2'),
        'm2 after restart',
      );
      expect(await bob.bodies(chatId), ['m1', 'm2']);
    });

    test('the one-time prekey is still erased when the local prekey store fails once', () async {
      await alice.chat.sendText(chatId, 'm1');
      final before = jsonDecode(
        (await bob.secrets.read('prekeys:bob:${bob.device.keys.deviceId}'))!,
      ) as Map<String, dynamic>;
      final poolBefore = (before['oneTime'] as Map).length;
      bob.secrets.failNext(
        'prekeys:',
      ); // consumeOneTime's save fails the first time
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('m1'),
        'delivered',
      );
      await alice.chat.sendText(
        chatId,
        'm2',
      ); // triggers recovery before processing
      await eventually(
        () async => (await bob.bodies(chatId)).contains('m2'),
        'm2',
      );
      final after = jsonDecode(
        (await bob.secrets.read('prekeys:bob:${bob.device.keys.deviceId}'))!,
      ) as Map<String, dynamic>;
      expect(
        (after['oneTime'] as Map).length,
        poolBefore - 1,
        reason: 'the used prekey was erased',
      );
      // maintenance does not resurrect or re-offer it
      await bob.prekeys.maintain('bob', bob.device);
      final afterMaintain = jsonDecode(
        (await bob.secrets.read('prekeys:bob:${bob.device.keys.deviceId}'))!,
      ) as Map<String, dynamic>;
      final privateIds = (afterMaintain['oneTime'] as Map).keys.toSet();
      final published =
          (await db
                  .collection(
                    'users/bob/devices/${bob.device.keys.deviceId}/prekeys',
                  )
                  .where('kind', isEqualTo: 'onetime')
                  .get())
              .docs
              .map((d) => d.id)
              .toSet();
      expect(
        published.difference(privateIds),
        isEmpty,
        reason: 'no published prekey without a private half',
      );
    });

    test('unused claimed prekeys do not pile up forever', () async {
      final key = 'prekeys:bob:${bob.device.keys.deviceId}';
      final stored =
          jsonDecode((await bob.secrets.read(key))!) as Map<String, dynamic>;
      // age every private one-time prekey beyond the retention period and take its public document away
      final old = DateTime.now()
          .subtract(const Duration(days: 60))
          .millisecondsSinceEpoch;
      final oneTime = stored['oneTime'] as Map<String, dynamic>;
      for (final v in oneTime.values) {
        (v as Map<String, dynamic>)['createdAt'] = old;
      }
      await bob.secrets.write(key, jsonEncode(stored));
      for (final d
          in (await db
                  .collection(
                    'users/bob/devices/${bob.device.keys.deviceId}/prekeys',
                  )
                  .where('kind', isEqualTo: 'onetime')
                  .get())
              .docs) {
        await d.reference
            .delete(); // claimed by initiators who never sent anything
      }
      await bob.prekeys.maintain('bob', bob.device);
      final after =
          jsonDecode((await bob.secrets.read(key))!) as Map<String, dynamic>;
      final ids = (after['oneTime'] as Map).keys.toSet();
      expect(
        ids.intersection(oneTime.keys.toSet()),
        isEmpty,
        reason: 'stale private halves were dropped',
      );
      expect(ids.length, PreKeyService.poolTarget);
    });
  });

  group('journal vs send ordering', () {
    test('a pending receive journal is applied BEFORE the next send, so a counter is never reused', () async {
      // alice -> bob; bob replies, which starts bob's sending chain.
      await alice.chat.sendText(chatId, 'a1');
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('a1'),
        'a1 delivered',
      );
      await bob.chat.sendText(chatId, 'b1');
      // alice has not read b1, so her next message continues the SAME chain: bob will not
      // ratchet when it arrives, and his sending chain keeps its counter.
      await alice.chat.sendText(chatId, 'a2');
      // a2 authenticates at bob but its journal cannot be applied (storage hiccup).
      bob.secrets.failNext('sess:', 1);
      await eventually(
        () async => bob.secrets.times == 0,
        'storage fault consumed while processing a2',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // bob sends while that journal is still pending ...
      await bob.chat.sendText(chatId, 'b2');
      // ... then the app restarts and the journal is replayed, then bob sends again.
      await bob.sub?.cancel();
      bob.restart();
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('a2'),
        'a2 recovered',
      );
      await bob.chat.sendText(chatId, 'b3');
      // alice reads everything bob sent: no message may be lost to a reused counter.
      alice.sub = alice.chat.startSync(chatId);
      await eventually(() async {
        final got = await alice.bodies(chatId);
        return got.contains('b1') && got.contains('b2') && got.contains('b3');
      }, 'alice must be able to read b1, b2 and b3');
      await alice.sub?.cancel();
    });
  });

  group('sync cursor', () {
    test('a message that failed is not skipped when a LATER message succeeds and the app restarts', () async {
      await alice.chat.sendText(chatId, 'first'); // creates the session
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('first'),
        'first delivered',
      );
      // The next message cannot be stored (the journal write fails once), so it is deferred.
      bob.secrets.failNext('journal:', 1);
      await alice.chat.sendText(chatId, 'owed');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await bob.bodies(chatId), [
        'first',
      ], reason: 'owed message is deferred');
      // A later message succeeds in a separate batch.
      await alice.chat.sendText(chatId, 'later');
      await eventually(
        () async => (await bob.bodies(chatId)).contains('later'),
        'later delivered',
      );
      // The app is closed before the deferred retry runs; the in-memory retry list is lost.
      await bob.sub?.cancel();
      bob.restart();
      bob.sub = bob.chat.startSync(chatId);
      await eventually(
        () async => (await bob.bodies(chatId)).contains('owed'),
        'the owed message must be fetched again after restart, not skipped by the cursor',
      );
      expect((await bob.bodies(chatId)).where((b) => b == 'owed').length, 1);
    });
  });
}
